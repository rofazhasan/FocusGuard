// FocusGuard Windows Agent — Domain Layer
// Shared policy model matching the FocusGuard Platform Specification v1.
// This is a pure domain model with no platform dependencies.

namespace FocusGuard.Windows.Domain.Models;

/// <summary>
/// Action types the policy engine can evaluate.
/// </summary>
public enum PolicyAction
{
    Allow,
    Block,
    TimeLimit,
    Schedule,
    Focus,
    NetworkBlock,
    AppLimit
}

/// <summary>
/// What kind of target this policy applies to.
/// </summary>
public enum PolicyTargetType
{
    App,
    Domain,
    Category,
    Url,
    Device,
    DeviceGroup
}

/// <summary>
/// Decision produced by the local policy evaluation engine.
/// </summary>
public enum DecisionOutcome
{
    Allow,
    Block,
    Warn
}

/// <summary>
/// A scheduled time window for a policy.
/// days: ISO weekday numbers (0=Sun, 6=Sat). Null/empty = all days.
/// </summary>
public sealed record PolicySchedule(
    int[]? Days,
    string? Start,   // "HH:mm" 24h
    string? End      // "HH:mm" 24h (can cross midnight: 22:00–07:00)
);

/// <summary>
/// A FocusGuard attention policy as received from the server and cached locally.
/// Immutable record — any update produces a new record with a higher Version.
/// </summary>
public sealed record Policy(
    string Id,
    int Version,
    string Name,
    PolicyTargetType TargetType,
    string Target,
    PolicyAction Action,
    int LimitSeconds,            // Only meaningful for TimeLimit / AppLimit actions
    PolicySchedule? Schedule,
    string Timezone,
    string[] Devices,            // Empty = all devices
    int Priority,
    bool IsEnabled
);

/// <summary>
/// The structured result of evaluating one navigation or app access request
/// against the local policy store.
/// </summary>
public sealed record PolicyDecision(
    DecisionOutcome Decision,
    string Reason,
    string? PolicyId,
    int PolicyVersion,
    int UsedSeconds = 0,
    int LimitSeconds = 0
);

/// <summary>
/// Protection sub-system states reported to the owner dashboard.
/// </summary>
public enum ProtectionState
{
    Protected,
    Degraded,
    Offline,
    PermissionRequired,
    PolicyOutdated,
    Revoked,
    Error
}

/// <summary>
/// Enrollment pairing states — matches the FocusGuard pairing state machine.
/// </summary>
public enum PairingState
{
    Unpaired,
    Pairing,
    PendingApproval,
    Paired,
    Active,
    Offline,
    Revoked,
    Blocked,
    Untrusted
}

/// <summary>
/// Cryptographic device identity. Never uses MAC, IP, IMEI or hardware ID.
/// The deviceId and deviceKey are generated once at enrollment and persisted
/// securely via Windows DPAPI (Credential Manager).
/// </summary>
public sealed record DeviceIdentity(
    string DeviceId,
    string DeviceKey,   // 32-byte hex, stored encrypted in Credential Manager
    string Platform,
    string PlatformVersion,
    string AppVersion,
    string DeviceName,
    DateTimeOffset CreatedAt,
    int PolicyVersion,
    PairingState PairingState,
    ProtectionState ProtectionState
);

/// <summary>
/// A usage session for a foreground process window.
/// </summary>
public sealed record UsageSession(
    string SessionId,
    string Target,         // Hostname or app executable / bundle name
    PolicyTargetType TargetType,
    DateTimeOffset StartTime,
    DateTimeOffset? EndTime,
    int DurationSeconds
);

/// <summary>
/// An enforcement event emitted when a block is triggered.
/// </summary>
public sealed record EnforcementEvent(
    string EventId,
    string EventType,
    string DeviceId,
    int PolicyVersion,
    long TimestampMs,
    Dictionary<string, object> Payload
);
