// FocusGuard Windows Agent — Enrollment Service
// Implements the FocusGuard device pairing protocol on the client (device) side.
//
// Flow:
//   1. User opens the Windows agent and sees the pairing wizard.
//   2. User enters the 6-character pairing code (FG-XXXXXX) shown in the owner dashboard.
//   3. Agent calls POST /enrollment/claim with the code + platform details.
//   4. Server validates the code (TTL ≤ 5 min, unclaimed), creates device record,
//      and returns { deviceId, accessToken, policyVersion }.
//   5. Agent stores deviceId + accessToken securely via DPAPI.
//   6. Agent stores policyVersion and downloads current policies via POLICY_PULL.
//   7. Agent transitions PairingState → Active.

using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using FocusGuard.Windows.Domain.Models;
using FocusGuard.Windows.Storage;
using Microsoft.Extensions.Logging;

namespace FocusGuard.Windows.Sync;

/// <summary>
/// Response from POST /enrollment/claim.
/// </summary>
internal sealed record ClaimEnrollmentResponse(
    string DeviceId,
    string UserId,
    string DeviceName,
    string Platform,
    string Role,
    bool IsManaged,
    int PolicyVersion,
    string AccessToken,
    string Status
);

/// <summary>
/// Handles device enrollment (pairing) and re-registration.
/// Stateless after pairing — device identity persists in SecureLocalStorage.
/// </summary>
public sealed class EnrollmentService
{
    private readonly SecureLocalStorage _storage;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<EnrollmentService> _logger;
    private string _serverBase = "http://localhost:8080/api/v1";

    public EnrollmentService(
        SecureLocalStorage storage,
        IHttpClientFactory httpClientFactory,
        ILogger<EnrollmentService> logger)
    {
        _storage = storage;
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    public void Configure(string serverBase) => _serverBase = serverBase;

    /// <summary>
    /// Checks whether this device has a stored identity.
    /// Returns the existing identity, or null if unpaired.
    /// </summary>
    public async Task<DeviceIdentity?> TryLoadExistingIdentityAsync()
    {
        return await _storage.LoadDeviceIdentityAsync();
    }

    /// <summary>
    /// Claims a pairing code from the server and stores the resulting device identity.
    /// This is the single enrollment action — it only needs to succeed once.
    ///
    /// Returns the DeviceIdentity on success, or throws on failure.
    /// </summary>
    public async Task<DeviceIdentity> ClaimPairingCodeAsync(
        string pairingCode,
        string deviceName,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation("[FocusGuard Enrollment] Attempting to claim pairing code: {Code}", pairingCode);

        var payload = new
        {
            pairingCode = pairingCode.Trim().ToUpperInvariant(),
            deviceName,
            platform = "WINDOWS",
            osVersion = GetWindowsVersion()
        };

        var json = JsonSerializer.Serialize(payload);
        var content = new StringContent(json, Encoding.UTF8, "application/json");

        var client = _httpClientFactory.CreateClient("FocusGuard");
        var response = await client.PostAsync($"{_serverBase}/enrollment/claim", content, cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            var errBody = await response.Content.ReadAsStringAsync(cancellationToken);
            _logger.LogError("[FocusGuard Enrollment] Claim failed: HTTP {Status} — {Body}", response.StatusCode, errBody);
            throw new InvalidOperationException($"Enrollment claim failed: {response.StatusCode} — {errBody}");
        }

        var responseJson = await response.Content.ReadAsStringAsync(cancellationToken);
        var claimed = JsonSerializer.Deserialize<ClaimEnrollmentResponse>(responseJson,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
            ?? throw new InvalidOperationException("Invalid enrollment response from server");

        _logger.LogInformation("[FocusGuard Enrollment] Device enrolled. DeviceId: {DeviceId}, PolicyVersion: {Version}",
            claimed.DeviceId, claimed.PolicyVersion);

        // Generate device identity record
        var identity = new DeviceIdentity(
            DeviceId: claimed.DeviceId,
            DeviceKey: claimed.AccessToken,    // JWT stored as device key for reconnection
            Platform: "WINDOWS",
            PlatformVersion: GetWindowsVersion(),
            AppVersion: "1.0.0",
            DeviceName: claimed.DeviceName,
            CreatedAt: DateTimeOffset.UtcNow,
            PolicyVersion: claimed.PolicyVersion,
            PairingState: PairingState.Active,
            ProtectionState: ProtectionState.Protected
        );

        // Persist securely via DPAPI
        await _storage.SaveDeviceIdentityAsync(identity);

        return identity;
    }

    /// <summary>
    /// Fetches current policy list from the server and caches locally.
    /// Called after enrollment and on reconnect when version is stale.
    /// </summary>
    public async Task<(List<Domain.Models.Policy> Policies, int Version)> FetchPoliciesAsync(
        string accessToken,
        CancellationToken cancellationToken = default)
    {
        var client = _httpClientFactory.CreateClient("FocusGuard");
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        var response = await client.GetAsync($"{_serverBase}/policies", cancellationToken);
        if (!response.IsSuccessStatusCode)
            return ([], 0);

        var json = await response.Content.ReadAsStringAsync(cancellationToken);
        var policies = JsonSerializer.Deserialize<List<Domain.Models.Policy>>(json,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? [];

        // Server sends current version in a header
        int version = 0;
        if (response.Headers.TryGetValues("X-Policy-Version", out var vals))
            _ = int.TryParse(vals.FirstOrDefault(), out version);

        return (policies, version);
    }

    /// <summary>
    /// Revokes local device identity. Used when owner revokes the device remotely,
    /// or when the user explicitly un-pairs the device from this agent.
    /// </summary>
    public void RevokeLocalIdentity()
    {
        _storage.DeleteDeviceIdentity();
        _logger.LogWarning("[FocusGuard Enrollment] Device identity revoked and deleted from local storage");
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private static string GetWindowsVersion()
    {
        try
        {
            return Environment.OSVersion.ToString();
        }
        catch
        {
            return "Windows (version unknown)";
        }
    }
}
