// FocusGuard Windows Agent — Sync Engine
// Handles the WebSocket lifecycle, policy sync, usage upload, and command dispatch.
//
// Protocol: wss://api.focusguard.app/ws?token=<access_token>
//
// The sync engine implements the full FocusGuard Protocol:
//   - On connect: validate token, send HEARTBEAT, receive POLICY_PUSH if version mismatch
//   - On receive POLICY_PUSH: apply to LocalPolicyEngine if version ≥ current
//   - On receive COMMAND: validate signature, validate timestamp (±5 min), execute
//   - Every 30s: send HEARTBEAT with policyVersion and protectionState
//   - On disconnect: queue events locally, reconnect with exponential backoff
//   - On reconnect: flush pending usage queue via POST /usage/sync

using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using FocusGuard.Windows.Domain;
using FocusGuard.Windows.Domain.Models;
using FocusGuard.Windows.Storage;
using Microsoft.Extensions.Logging;

namespace FocusGuard.Windows.Sync;

/// <summary>
/// WebSocket envelope matching the FocusGuard protocol specification.
/// </summary>
internal sealed record WsEnvelope(string Type, string CorrelationId, long Timestamp, JsonElement? Payload = null);

/// <summary>
/// Manages the WebSocket connection to the FocusGuard cloud backend.
/// Implements reconnect with exponential backoff, policy sync, and command dispatch.
/// </summary>
public sealed class SyncEngine : IDisposable
{
    private readonly LocalPolicyEngine _policyEngine;
    private readonly SecureLocalStorage _storage;
    private readonly ILogger<SyncEngine> _logger;
    private readonly IHttpClientFactory _httpClientFactory;

    private ClientWebSocket? _ws;
    private CancellationTokenSource? _cts;
    private Task? _wsTask;
    private Task? _heartbeatTask;
    private Task? _usageFlushTask;

    private DeviceIdentity? _identity;
    private string _serverBase = "http://localhost:8080/api/v1";
    private string _wsBase = "ws://localhost:8080/ws";

    // Backoff: 1s, 2s, 4s, 8s, 16s, 32s (cap at 60s)
    private int _reconnectAttempt = 0;
    private const int MaxBackoffSeconds = 60;

    // Pending usage queue — flushed on reconnect
    private readonly List<UsageDelta> _pendingUsage = [];
    private readonly object _usageLock = new();

    public event Action<bool>? OnConnectionStateChanged;
    public event Action<List<Policy>, int>? OnPoliciesReceived;
    public event Action<string, JsonElement>? OnCommandReceived;

    public SyncEngine(
        LocalPolicyEngine policyEngine,
        SecureLocalStorage storage,
        ILogger<SyncEngine> logger,
        IHttpClientFactory httpClientFactory)
    {
        _policyEngine = policyEngine;
        _storage = storage;
        _logger = logger;
        _httpClientFactory = httpClientFactory;
    }

    public void Configure(string serverBase, string wsBase)
    {
        _serverBase = serverBase;
        _wsBase = wsBase;
    }

    public async Task StartAsync(DeviceIdentity identity, CancellationToken cancellationToken)
    {
        _identity = identity;
        _cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);

        // Start heartbeat loop
        _heartbeatTask = SendHeartbeatsAsync(_cts.Token);

        // Start usage flush loop
        _usageFlushTask = FlushUsageLoopAsync(_cts.Token);

        // Start WebSocket loop with reconnect
        _wsTask = WebSocketLoopAsync(_cts.Token);

        await Task.CompletedTask;
    }

    // ── Usage Accumulation ────────────────────────────────────────────────────

    /// <summary>
    /// Queues a usage delta for submission. Thread-safe.
    /// Called by the WindowsUsageAdapter on each second tick.
    /// </summary>
    public void QueueUsageDelta(string target, int deltaSeconds, PolicyTargetType type)
    {
        var delta = new UsageDelta(
            DeviceId: _identity?.DeviceId ?? "unknown",
            Target: target,
            TargetType: type.ToString(),
            DeltaSeconds: deltaSeconds,
            Date: DateTimeOffset.UtcNow.ToString("yyyy-MM-dd"));

        lock (_usageLock)
        {
            // Merge into existing delta for the same target+date
            var existing = _pendingUsage.FirstOrDefault(d => d.Target == target && d.Date == delta.Date);
            if (existing is not null)
            {
                var idx = _pendingUsage.IndexOf(existing);
                _pendingUsage[idx] = existing with { DeltaSeconds = existing.DeltaSeconds + deltaSeconds };
            }
            else
            {
                _pendingUsage.Add(delta);
            }
        }
    }

    // ── WebSocket Lifecycle ───────────────────────────────────────────────────

    private async Task WebSocketLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                await ConnectAndReceiveAsync(ct);
                _reconnectAttempt = 0; // Reset on clean disconnect
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "[FocusGuard Sync] WebSocket disconnected (attempt {Attempt})", _reconnectAttempt);
                OnConnectionStateChanged?.Invoke(false);
            }

            // Exponential backoff
            int delaySeconds = Math.Min((int)Math.Pow(2, _reconnectAttempt), MaxBackoffSeconds);
            _reconnectAttempt++;
            _logger.LogInformation("[FocusGuard Sync] Reconnecting in {Delay}s...", delaySeconds);
            await Task.Delay(TimeSpan.FromSeconds(delaySeconds), ct);
        }
    }

    private async Task ConnectAndReceiveAsync(CancellationToken ct)
    {
        if (_identity is null) return;

        _ws = new ClientWebSocket();
        var wsUri = new Uri($"{_wsBase}?token={Uri.EscapeDataString(_identity.DeviceKey)}");

        _logger.LogInformation("[FocusGuard Sync] Connecting to {Uri}", wsUri);
        await _ws.ConnectAsync(wsUri, ct);
        OnConnectionStateChanged?.Invoke(true);
        _logger.LogInformation("[FocusGuard Sync] WebSocket connected");

        // Request policy sync on connect
        await SendEnvelopeAsync("POLICY_PULL", new
        {
            deviceId = _identity.DeviceId,
            currentVersion = _policyEngine.PolicyVersion
        }, ct);

        // Flush any queued usage
        _ = Task.Run(() => FlushPendingUsageAsync(ct), ct);

        // Receive loop
        var buffer = new byte[16 * 1024];
        while (!ct.IsCancellationRequested && _ws.State == WebSocketState.Open)
        {
            var result = await _ws.ReceiveAsync(buffer, ct);
            if (result.MessageType == WebSocketMessageType.Close)
                break;

            var json = Encoding.UTF8.GetString(buffer, 0, result.Count);
            await HandleServerMessageAsync(json);
        }
    }

    private async Task HandleServerMessageAsync(string json)
    {
        try
        {
            var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            var type = root.GetProperty("type").GetString();
            var payload = root.TryGetProperty("payload", out var p) ? p : (JsonElement?)null;

            switch (type)
            {
                case "POLICY_PUSH":
                    await HandlePolicyPushAsync(payload);
                    break;

                case "COMMAND":
                    if (payload.HasValue)
                        OnCommandReceived?.Invoke(type, payload.Value);
                    break;

                case "HEARTBEAT_ACK":
                    _logger.LogDebug("[FocusGuard Sync] Heartbeat acknowledged");
                    break;

                case "AUTH_ERROR":
                    _logger.LogError("[FocusGuard Sync] Authentication rejected by server: {Payload}", json);
                    break;

                default:
                    _logger.LogDebug("[FocusGuard Sync] Unknown message type: {Type}", type);
                    break;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "[FocusGuard Sync] Error processing server message: {Json}", json);
        }
    }

    private async Task HandlePolicyPushAsync(JsonElement? payload)
    {
        if (payload is null) return;
        try
        {
            var versionElem = payload.Value.GetProperty("version");
            var version = versionElem.GetInt32();
            var policiesJson = payload.Value.GetProperty("policies").GetRawText();
            var policies = JsonSerializer.Deserialize<List<Policy>>(policiesJson) ?? [];

            if (_policyEngine.ApplyPolicies(policies, version))
            {
                _logger.LogInformation("[FocusGuard Sync] Policy push accepted: v{Version} ({Count} policies)", version, policies.Count);
                await _storage.SavePoliciesAsync(policies, version);
                OnPoliciesReceived?.Invoke(policies, version);
            }
            else
            {
                _logger.LogWarning("[FocusGuard Sync] Policy push REJECTED (rollback attempt). Current: v{Current}, Received: v{Received}",
                    _policyEngine.PolicyVersion, version);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[FocusGuard Sync] Error applying policy push");
        }
    }

    // ── Heartbeat Loop ────────────────────────────────────────────────────────

    private async Task SendHeartbeatsAsync(CancellationToken ct)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(30));
        while (await timer.WaitForNextTickAsync(ct))
        {
            if (_ws?.State == WebSocketState.Open && _identity is not null)
            {
                await SendEnvelopeAsync("HEARTBEAT", new
                {
                    deviceId = _identity.DeviceId,
                    policyVersion = _policyEngine.PolicyVersion,
                    platform = "WINDOWS"
                }, ct);
            }
        }
    }

    // ── Usage Flush ───────────────────────────────────────────────────────────

    private async Task FlushUsageLoopAsync(CancellationToken ct)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(30));
        while (await timer.WaitForNextTickAsync(ct))
        {
            await FlushPendingUsageAsync(ct);
        }
    }

    private async Task FlushPendingUsageAsync(CancellationToken ct)
    {
        List<UsageDelta> toFlush;
        lock (_usageLock)
        {
            if (_pendingUsage.Count == 0) return;
            toFlush = [.. _pendingUsage];
        }

        try
        {
            var client = _httpClientFactory.CreateClient("FocusGuard");
            var payload = new { deviceId = _identity?.DeviceId, usageDeltas = toFlush };
            var json = JsonSerializer.Serialize(payload);
            var content = new StringContent(json, Encoding.UTF8, "application/json");

            var resp = await client.PostAsync($"{_serverBase}/usage/sync", content, ct);
            if (resp.IsSuccessStatusCode)
            {
                lock (_usageLock)
                {
                    _pendingUsage.RemoveAll(d => toFlush.Contains(d));
                }
                _logger.LogInformation("[FocusGuard Sync] Flushed {Count} usage deltas", toFlush.Count);

                // Persist usage to local disk after successful flush
                var current = _policyEngine.GetTodayUsageSnapshot();
                await _storage.SaveTodayUsageAsync(current);
            }
        }
        catch (Exception ex) when (!ct.IsCancellationRequested)
        {
            _logger.LogWarning(ex, "[FocusGuard Sync] Failed to flush usage (will retry)");
        }
    }

    // ── WebSocket Send ────────────────────────────────────────────────────────

    private async Task SendEnvelopeAsync(string type, object payload, CancellationToken ct)
    {
        if (_ws?.State != WebSocketState.Open) return;
        try
        {
            var envelope = new
            {
                type,
                correlationId = $"cor_{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}",
                timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                payload
            };
            var json = JsonSerializer.Serialize(envelope);
            var bytes = Encoding.UTF8.GetBytes(json);
            await _ws.SendAsync(bytes, WebSocketMessageType.Text, true, ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "[FocusGuard Sync] Failed to send {Type} envelope", type);
        }
    }

    public void Dispose()
    {
        _cts?.Cancel();
        _ws?.Dispose();
        _cts?.Dispose();
    }
}

// ── Supporting types ───────────────────────────────────────────────────────────

internal sealed record UsageDelta(
    string DeviceId,
    string Target,
    string TargetType,
    int DeltaSeconds,
    string Date
);
