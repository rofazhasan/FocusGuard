// FocusGuard Windows Agent — WPF System Tray Application + Block Overlay UI
// Entry point, dependency injection container setup, system tray integration.
//
// Architecture:
//   App.xaml.cs creates the DI container and starts the AgentOrchestrator.
//   SystemTrayManager manages the NotifyIcon.
//   BlockOverlayWindow is a topmost WPF window shown when a block is triggered.

using System.Windows;
using FocusGuard.Windows.Domain;
using FocusGuard.Windows.Platform;
using FocusGuard.Windows.Storage;
using FocusGuard.Windows.Sync;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace FocusGuard.Windows.UI;

/// <summary>
/// WPF Application entry point.
/// Bootstraps the DI container and starts all agent services.
/// </summary>
public sealed partial class App : Application
{
    private ServiceProvider? _services;
    private AgentOrchestrator? _orchestrator;
    private SystemTrayManager? _tray;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // ── Dependency Injection Setup ────────────────────────────────────────
        var services = new ServiceCollection();

        services.AddLogging(b => b
            .SetMinimumLevel(LogLevel.Debug)
            .AddConsole()
            .AddDebug());

        services.AddHttpClient("FocusGuard", client =>
        {
            client.Timeout = TimeSpan.FromSeconds(30);
        });

        // Register all agent services
        services.AddSingleton<LocalPolicyEngine>();
        services.AddSingleton<SecureLocalStorage>();
        services.AddSingleton<WindowsEnforcementAdapter>();
        services.AddSingleton<SyncEngine>();
        services.AddSingleton<EnrollmentService>();
        services.AddSingleton<AgentOrchestrator>(sp =>
        {
            var policyEngine = sp.GetRequiredService<LocalPolicyEngine>();
            var storage = sp.GetRequiredService<SecureLocalStorage>();
            var enforcementAdapter = sp.GetRequiredService<WindowsEnforcementAdapter>();
            var syncEngine = sp.GetRequiredService<SyncEngine>();
            var enrollmentService = sp.GetRequiredService<EnrollmentService>();
            var logger = sp.GetRequiredService<ILogger<AgentOrchestrator>>();

            // Usage adapter is wired to the orchestrator's tick handler
            var usageAdapter = new WindowsUsageAdapter(
                policyEngine,
                sp.GetRequiredService<ILogger<WindowsUsageAdapter>>(),
                (target, delta, type) => sp.GetRequiredService<AgentOrchestrator>()
                    .HandleUsageTick(target, delta, type));

            return new AgentOrchestrator(
                policyEngine, usageAdapter, enforcementAdapter,
                syncEngine, enrollmentService, storage, logger);
        });

        _services = services.BuildServiceProvider();

        // ── Start Orchestrator ────────────────────────────────────────────────
        _orchestrator = _services.GetRequiredService<AgentOrchestrator>();
        _orchestrator.OnBlockOverlayRequested += HandleBlockOverlayRequest;
        _orchestrator.OnStatusChanged += HandleStatusChanged;

        // ── System Tray ───────────────────────────────────────────────────────
        _tray = new SystemTrayManager(_orchestrator);
        _tray.Show();

        // Don't create a main window — tray-only app
        ShutdownMode = ShutdownMode.OnExplicitShutdown;

        await _orchestrator.StartAsync();
    }

    private void HandleBlockOverlayRequest(bool show, string target, Domain.Models.PolicyDecision? decision)
    {
        if (show && decision is not null)
        {
            Dispatcher.Invoke(() =>
            {
                var overlay = new BlockOverlayWindow(target, decision);
                overlay.Show();
            });
        }
    }

    private void HandleStatusChanged(AgentStatus status)
    {
        _tray?.UpdateStatus(status);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _orchestrator?.Dispose();
        _tray?.Dispose();
        _services?.Dispose();
        base.OnExit(e);
    }
}
