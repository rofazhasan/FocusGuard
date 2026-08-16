// FocusGuard Windows Agent — Platform Adapter Layer
// Windows Foreground Usage Detector using Win32 GetForegroundWindow API.
//
// Architecture:
//   WindowsUsageAdapter (Platform) → LocalPolicyEngine (Domain) → EnforcementAdapter (Platform)
//
// Uses only official documented Windows APIs:
//   - User32.dll GetForegroundWindow()
//   - User32.dll GetWindowText()
//   - User32.dll GetWindowThreadProcessId()
//   - System.Diagnostics.Process for executable resolution
//   - System.Runtime.InteropServices for P/Invoke
//
// Does NOT use: kernel drivers, DLL injection, undocumented APIs, hook chains.

using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using FocusGuard.Windows.Domain;
using FocusGuard.Windows.Domain.Models;
using Microsoft.Extensions.Logging;

namespace FocusGuard.Windows.Platform;

/// <summary>
/// Detects the foreground application using documented Win32 APIs.
/// Polls GetForegroundWindow every 1 second, tracks session duration,
/// and emits usage ticks to the local policy engine.
/// </summary>
public sealed class WindowsUsageAdapter : IDisposable
{
    private readonly LocalPolicyEngine _policyEngine;
    private readonly ILogger<WindowsUsageAdapter> _logger;
    private readonly Action<string, int, PolicyTargetType> _onUsageTick;
    private readonly PeriodicTimer _pollTimer;
    private Task? _pollTask;
    private CancellationTokenSource? _cts;

    // Current foreground session
    private string _currentTarget = string.Empty;
    private PolicyTargetType _currentType = PolicyTargetType.App;
    private DateTimeOffset _sessionStart = DateTimeOffset.Now;
    private bool _isIdle;

    // IDLE threshold: 60 seconds without foreground window or user input
    private const int IdleThresholdSeconds = 60;

    public WindowsUsageAdapter(
        LocalPolicyEngine policyEngine,
        ILogger<WindowsUsageAdapter> logger,
        Action<string, int, PolicyTargetType> onUsageTick)
    {
        _policyEngine = policyEngine;
        _logger = logger;
        _onUsageTick = onUsageTick;
        _pollTimer = new PeriodicTimer(TimeSpan.FromSeconds(1));
    }

    public void Start()
    {
        _cts = new CancellationTokenSource();
        _pollTask = PollForegroundWindowAsync(_cts.Token);
        _logger.LogInformation("[FocusGuard] WindowsUsageAdapter started — polling foreground window every 1s");
    }

    public void Stop()
    {
        _cts?.Cancel();
    }

    private async Task PollForegroundWindowAsync(CancellationToken cancellationToken)
    {
        while (await _pollTimer.WaitForNextTickAsync(cancellationToken))
        {
            try
            {
                var (target, type) = GetForegroundTarget();

                // Detect idle: if no foreground window or system is idle
                bool idle = string.IsNullOrEmpty(target) || IsSystemIdle();
                if (idle)
                {
                    if (!_isIdle)
                    {
                        _isIdle = true;
                        _logger.LogDebug("[FocusGuard] System idle — pausing usage tracking");
                    }
                    continue;
                }

                _isIdle = false;

                if (!string.Equals(target, _currentTarget, StringComparison.OrdinalIgnoreCase))
                {
                    // Flush previous session
                    if (!string.IsNullOrEmpty(_currentTarget))
                    {
                        var elapsed = (int)(DateTimeOffset.Now - _sessionStart).TotalSeconds;
                        if (elapsed > 0)
                        {
                            _onUsageTick(_currentTarget, elapsed, _currentType);
                        }
                    }

                    _currentTarget = target;
                    _currentType = type;
                    _sessionStart = DateTimeOffset.Now;
                }
                else
                {
                    // Emit a 1s delta tick for the running session
                    _onUsageTick(_currentTarget, 1, _currentType);
                }
            }
            catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
            {
                _logger.LogWarning(ex, "[FocusGuard] Error polling foreground window");
            }
        }
    }

    /// <summary>
    /// Resolves the current foreground window to a (target, type) pair.
    /// For browser windows, returns the active hostname; for other apps, returns the executable name.
    /// </summary>
    private static (string target, PolicyTargetType type) GetForegroundTarget()
    {
        var hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return (string.Empty, PolicyTargetType.App);

        GetWindowThreadProcessId(hwnd, out var pid);
        if (pid == 0) return (string.Empty, PolicyTargetType.App);

        try
        {
            var process = Process.GetProcessById((int)pid);
            var exeName = process.ProcessName.ToLowerInvariant();

            // Detect browser processes and extract active tab domain from window title
            if (IsBrowserProcess(exeName))
            {
                var title = GetWindowTitle(hwnd);
                var domain = ExtractDomainFromBrowserTitle(title);
                if (!string.IsNullOrEmpty(domain))
                    return (domain, PolicyTargetType.Domain);

                // Browser open but can't determine domain — track browser as app
                return (exeName, PolicyTargetType.App);
            }

            return (exeName, PolicyTargetType.App);
        }
        catch (Exception)
        {
            return (string.Empty, PolicyTargetType.App);
        }
    }

    private static bool IsBrowserProcess(string processName) =>
        processName is "chrome" or "msedge" or "brave" or "firefox" or "opera";

    /// <summary>
    /// Extracts a domain from a browser window title.
    /// Browsers typically format titles as: "Page Title — Domain"
    /// This is a best-effort extraction. The browser extension remains the authoritative
    /// source for domain-level usage in the browser layer.
    /// </summary>
    private static string ExtractDomainFromBrowserTitle(string title)
    {
        if (string.IsNullOrEmpty(title)) return string.Empty;

        // Look for URL-like patterns in title (some browsers show the URL)
        var parts = title.Split([" - ", " — ", " | "], StringSplitOptions.RemoveEmptyEntries);
        foreach (var part in parts.Reverse())
        {
            var trimmed = part.Trim();
            if (Uri.TryCreate("https://" + trimmed, UriKind.Absolute, out _))
            {
                return DomainNormalizer.GetBaseDomain(trimmed);
            }
        }

        return string.Empty;
    }

    private static string GetWindowTitle(IntPtr hwnd)
    {
        var sb = new StringBuilder(512);
        GetWindowText(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    // ── IDLE DETECTION ──────────────────────────────────────────────────────

    private static bool IsSystemIdle()
    {
        var info = new LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf<LASTINPUTINFO>() };
        if (!GetLastInputInfo(ref info)) return false;
        var idleMs = (uint)Environment.TickCount - info.dwTime;
        return idleMs > IdleThresholdSeconds * 1000;
    }

    // ── Win32 P/Invoke Declarations ─────────────────────────────────────────
    // All APIs are documented at learn.microsoft.com/en-us/windows/win32/api/

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [StructLayout(LayoutKind.Sequential)]
    private struct LASTINPUTINFO
    {
        public uint cbSize;
        public uint dwTime;
    }

    public void Dispose()
    {
        _cts?.Cancel();
        _cts?.Dispose();
        _pollTimer.Dispose();
    }
}
