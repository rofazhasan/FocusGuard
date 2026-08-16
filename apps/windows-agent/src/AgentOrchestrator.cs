// FocusGuard Windows Agent — Main Application Orchestrator
// Background service that coordinates all subsystems:
//   - EnrollmentService (pairing)
//   - WindowsUsageAdapter (foreground detection)
//   - LocalPolicyEngine (offline policy evaluation)
//   - WindowsEnforcementAdapter (overlay blocking, capability probing)
//   - SyncEngine (WebSocket + REST synchronization)
//   - SecureLocalStorage (DPAPI credential + policy cache)
//
// Design: LocalFirst. All enforcement happens offline.
// Sync engine coordinates with server but is never blocking.

using FocusGuard.Windows.Domain;
using FocusGuard.Windows.Domain.Models;
using FocusGuard.Windows.Platform;
using FocusGuard.Windows.Storage;
using FocusGuard.Windows.Sync;
using Microsoft.Extensions.Logging;

namespace FocusGuard.Windows;

/// <summary>
/// Application state snapshot exposed to the system tray / UI.
/// </summary>
public sealed record AgentStatus(
    PairingState PairingState,
    ProtectionState ProtectionState,
    int ProtectionScore,
    bool IsConnected,
    int PolicyVersion,
    int ActivePolicyCount,
    string[] Degradations,
    string DeviceName
);

/// <summary>
/// Central orchestrator for the FocusGuard Windows agent.
/// Created once at startup, runs until process exit.
/// Wires subsystems together and exposes status events to the system tray UI.
/// </summary>
public sealed class AgentOrchestrator : IDisposable
{
    private readonly LocalPolicyEngine _policyEngine;
    private readonly WindowsUsageAdapter _usageAdapter;
    private readonly WindowsEnforcementAdapter _enforcementAdapter;
    private readonly SyncEngine _syncEngine;
    private readonly EnrollmentService _enrollmentService;
    private readonly SecureLocalStorage _storage;
    private readonly ILogger<AgentOrchestrator> _logger;

    private DeviceIdentity? _identity;
    private bool _running;
    private CancellationTokenSource? _cts;

    public event Action<AgentStatus>? OnStatusChanged;
    public event Action<string, PolicyDecision>? OnBlockTriggered;

    // Expose enforcement adapter events to UI
    public event Action<bool, string, PolicyDecision?>? OnBlockOverlayRequested;

    public AgentOrchestrator(
        LocalPolicyEngine policyEngine,
        WindowsUsageAdapter usageAdapter,
        WindowsEnforcementAdapter enforcementAdapter,
        SyncEngine syncEngine,
        EnrollmentService enrollmentService,
        SecureLocalStorage storage,
        ILogger<AgentOrchestrator> logger)
    {
        _policyEngine = policyEngine;
        _usageAdapter = usageAdapter;
        _enforcementAdapter = enforcementAdapter;
        _syncEngine = syncEngine;
        _enrollmentService = enrollmentService;
        _storage = storage;
        _logger = logger;

        WireEvents();
    }

    private void WireEvents()
    {
        // Forward block overlay events to UI
        _enforcementAdapter.BlockOverlayRequested += (show, target, decision) =>
            OnBlockOverlayRequested?.Invoke(show, target, decision);

        // Policy updates from sync engine
        _syncEngine.OnPoliciesReceived += async (policies, version) =>
        {
            _policyEngine.ApplyPolicies(policies, version);
            EmitStatus();
            await Task.CompletedTask;
        };

        // Connection state changes
        _syncEngine.OnConnectionStateChanged += connected =>
        {
            _logger.LogInformation("[FocusGuard] Server connection: {State}", connected ? "ONLINE" : "OFFLINE");
            EmitStatus();
        };

        // Commands from server
        _syncEngine.OnCommandReceived += (type, payload) =>
            HandleCommand(type, payload);
    }

    // ── Startup ───────────────────────────────────────────────────────────────

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        _cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        _running = true;

        _logger.LogInformation("[FocusGuard] Agent starting...");

        // 1. Probe enforcement capabilities (honest reporting)
        _enforcementAdapter.Initialize();

        // 2. Load locally stored policies (offline-first)
        var (cachedPolicies, cachedVersion) = await _storage.LoadPoliciesAsync();
        if (cachedPolicies.Count > 0)
        {
            _policyEngine.ApplyPolicies(cachedPolicies, cachedVersion);
            _logger.LogInformation("[FocusGuard] Loaded {Count} cached policies (v{Version}) from disk — enforcement active offline",
                cachedPolicies.Count, cachedVersion);
        }

        // 3. Load today's usage from disk
        var todayUsage = await _storage.LoadTodayUsageAsync();
        _policyEngine.SetTodayUsage(todayUsage);
        _logger.LogInformation("[FocusGuard] Today's usage loaded from disk");

        // 4. Try to load existing device identity
        _identity = await _enrollmentService.TryLoadExistingIdentityAsync();

        if (_identity is null)
        {
            _logger.LogInformation("[FocusGuard] No device identity found — showing pairing wizard");
            EmitStatus();
            // UI will trigger enrollment flow; Start waits for pairing
            return;
        }

        _logger.LogInformation("[FocusGuard] Device identity found: {DeviceId} (Paired)", _identity.DeviceId);

        // 5. Start usage adapter
        _usageAdapter.Start();

        // 6. Start sync engine
        await _syncEngine.StartAsync(_identity, _cts.Token);

        _logger.LogInformation("[FocusGuard] Agent fully started. Protection: ACTIVE");
        EmitStatus();
    }

    // ── Enrollment ────────────────────────────────────────────────────────────

    /// <summary>
    /// Called by the pairing wizard when user submits a pairing code.
    /// On success, starts all subsystems.
    /// </summary>
    public async Task<DeviceIdentity> EnrollWithPairingCodeAsync(
        string pairingCode,
        string deviceName,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation("[FocusGuard] Enrolling with pairing code: {Code}", pairingCode);

        _identity = await _enrollmentService.ClaimPairingCodeAsync(pairingCode, deviceName, cancellationToken);

        // Start subsystems now that we have an identity
        _usageAdapter.Start();
        await _syncEngine.StartAsync(_identity, _cts?.Token ?? default);

        // Download initial policies
        var (policies, version) = await _enrollmentService.FetchPoliciesAsync(_identity.DeviceKey, cancellationToken);
        if (policies.Count > 0)
        {
            _policyEngine.ApplyPolicies(policies, version);
            await _storage.SavePoliciesAsync(policies, version);
        }

        EmitStatus();
        return _identity;
    }

    // ── Usage Tick Handler ────────────────────────────────────────────────────

    /// <summary>
    /// Called by WindowsUsageAdapter on every 1-second usage tick.
    /// Records usage, evaluates policy, triggers enforcement if needed.
    /// </summary>
    public void HandleUsageTick(string target, int deltaSeconds, PolicyTargetType type)
    {
        // 1. Record usage in policy engine
        _policyEngine.RecordUsage(target, deltaSeconds);

        // 2. Queue for upload
        _syncEngine.QueueUsageDelta(target, deltaSeconds, type);

        // 3. Evaluate current policy
        var decision = _policyEngine.Evaluate(target, type);

        // 4. Enforce if needed
        if (decision.Decision == DecisionOutcome.Block)
        {
            _logger.LogWarning("[FocusGuard] BLOCK triggered for {Target}. Reason: {Reason}", target, decision.Reason);
            _enforcementAdapter.EnforceAppBlock(target, decision);
            OnBlockTriggered?.Invoke(target, decision);
        }
        else
        {
            // Release any active block for this target
            _enforcementAdapter.ReleaseAppBlock(target);
        }
    }

    // ── Command Dispatch ──────────────────────────────────────────────────────

    private void HandleCommand(string commandType, System.Text.Json.JsonElement payload)
    {
        _logger.LogInformation("[FocusGuard] Remote command received: {Type}", commandType);

        switch (commandType)
        {
            case "START_FOCUS":
                var allowedDomains = payload.TryGetProperty("allowedDomains", out var ad)
                    ? ad.EnumerateArray().Select(e => e.GetString() ?? "").ToArray()
                    : Array.Empty<string>();
                _policyEngine.SetFocusSession(true, allowedDomains);
                break;

            case "STOP_FOCUS":
                _policyEngine.SetFocusSession(false, []);
                break;

            case "UPDATE_POLICY":
            case "SYNC_POLICY":
                // Server will send POLICY_PUSH via WebSocket; no separate action needed
                break;

            case "REVOKE_DEVICE":
                _logger.LogWarning("[FocusGuard] Remote device revocation command received");
                _enrollmentService.RevokeLocalIdentity();
                EmitStatus();
                break;

            default:
                _logger.LogDebug("[FocusGuard] Unhandled command type: {Type}", commandType);
                break;
        }

        EmitStatus();
    }

    // ── Status ────────────────────────────────────────────────────────────────

    public AgentStatus GetCurrentStatus()
    {
        var (score, state, degradations) = _enforcementAdapter.ComputeProtectionScore();

        return new AgentStatus(
            PairingState: _identity is not null ? PairingState.Active : PairingState.Unpaired,
            ProtectionState: _identity is null ? ProtectionState.Offline : state,
            ProtectionScore: score,
            IsConnected: false, // TODO: expose sync engine connection state
            PolicyVersion: _policyEngine.PolicyVersion,
            ActivePolicyCount: 0,           // TODO: expose from policy engine
            Degradations: degradations,
            DeviceName: _identity?.DeviceName ?? "Unknown"
        );
    }

    private void EmitStatus()
    {
        OnStatusChanged?.Invoke(GetCurrentStatus());
    }

    public void Dispose()
    {
        _running = false;
        _cts?.Cancel();
        _usageAdapter.Dispose();
        _syncEngine.Dispose();
        _cts?.Dispose();
    }
}
