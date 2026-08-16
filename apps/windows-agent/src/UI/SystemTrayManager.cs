// FocusGuard Windows Agent — System Tray Manager
// Manages the Windows Notification Area (system tray) icon and context menu.
// Uses System.Windows.Forms.NotifyIcon (available in WPF via Windows.Forms reference).

using System.Drawing;
using System.Windows.Forms;
using FocusGuard.Windows.Domain.Models;

namespace FocusGuard.Windows.UI;

/// <summary>
/// Manages the FocusGuard system tray icon, tooltip, and context menu.
/// All interaction with the agent happens through here when the UI is not visible.
/// </summary>
public sealed class SystemTrayManager : IDisposable
{
    private readonly AgentOrchestrator _orchestrator;
    private readonly NotifyIcon _notifyIcon;
    private readonly ContextMenuStrip _contextMenu;

    // Menu items
    private readonly ToolStripMenuItem _statusItem;
    private readonly ToolStripMenuItem _openDashboardItem;
    private readonly ToolStripMenuItem _pairingItem;
    private readonly ToolStripMenuItem _protectionScoreItem;
    private readonly ToolStripMenuItem _exitItem;

    public SystemTrayManager(AgentOrchestrator orchestrator)
    {
        _orchestrator = orchestrator;

        _statusItem = new ToolStripMenuItem("🛡 Status: Starting...")
            { Enabled = false, Font = new Font("Segoe UI", 9f, FontStyle.Bold) };

        _protectionScoreItem = new ToolStripMenuItem("Protection Score: —")
            { Enabled = false };

        _openDashboardItem = new ToolStripMenuItem("📊 Open FocusGuard Dashboard");
        _openDashboardItem.Click += (_, _) => OpenDashboard();

        _pairingItem = new ToolStripMenuItem("📱 Pair This Device...");
        _pairingItem.Click += (_, _) => ShowPairingWizard();

        _exitItem = new ToolStripMenuItem("Exit FocusGuard");
        _exitItem.Click += (_, _) => ExitApplication();

        _contextMenu = new ContextMenuStrip();
        _contextMenu.Items.AddRange([
            _statusItem,
            _protectionScoreItem,
            new ToolStripSeparator(),
            _openDashboardItem,
            _pairingItem,
            new ToolStripSeparator(),
            _exitItem
        ]);

        _notifyIcon = new NotifyIcon
        {
            Text = "FocusGuard — Protecting your focus",
            Icon = SystemIcons.Shield,
            ContextMenuStrip = _contextMenu,
            Visible = false
        };

        _notifyIcon.BalloonTipTitle = "FocusGuard";
        _notifyIcon.BalloonTipIcon = ToolTipIcon.Info;
        _notifyIcon.DoubleClick += (_, _) => OpenDashboard();
    }

    public void Show()
    {
        _notifyIcon.Visible = true;
        ShowBalloon("FocusGuard is protecting your focus.", 3000);
    }

    public void UpdateStatus(AgentStatus status)
    {
        // Must update on the UI thread
        if (_contextMenu.InvokeRequired)
        {
            _contextMenu.Invoke(() => UpdateStatus(status));
            return;
        }

        var emoji = status.ProtectionState switch
        {
            ProtectionState.Protected => "🛡",
            ProtectionState.Degraded => "⚠️",
            ProtectionState.Offline => "🔴",
            ProtectionState.Revoked => "❌",
            _ => "⚪"
        };

        var pairingDesc = status.PairingState switch
        {
            PairingState.Active => "Active",
            PairingState.Unpaired => "Unpaired",
            PairingState.Pairing => "Pairing...",
            _ => status.PairingState.ToString()
        };

        _statusItem.Text = $"{emoji} {status.ProtectionState} — {pairingDesc}";
        _protectionScoreItem.Text = $"Score: {status.ProtectionScore}/100 | Policies: {status.ActivePolicyCount}";

        _notifyIcon.Text = status.ProtectionState == ProtectionState.Protected
            ? $"FocusGuard — Protected (v{status.PolicyVersion})"
            : $"FocusGuard — {status.ProtectionState}";

        _pairingItem.Visible = status.PairingState == PairingState.Unpaired;
    }

    public void ShowBalloon(string message, int durationMs = 5000)
    {
        _notifyIcon.BalloonTipText = message;
        _notifyIcon.ShowBalloonTip(durationMs);
    }

    public void ShowBlockNotification(string target, string reason)
    {
        ShowBalloon($"🚫 Blocked: {target}\nReason: {reason}", 4000);
    }

    private static void OpenDashboard()
    {
        // Open the FocusGuard web dashboard in the default browser
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
        {
            FileName = "http://localhost:8080",
            UseShellExecute = true
        });
    }

    private static void ShowPairingWizard()
    {
        var wizard = new PairingWizardWindow();
        wizard.Show();
    }

    private static void ExitApplication()
    {
        System.Windows.Application.Current.Shutdown();
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _contextMenu.Dispose();
    }
}
