// FocusGuard Windows Agent — Secure Local Storage
// Uses Windows DPAPI (Data Protection API) via ProtectedData to encrypt
// device credentials at rest. No plaintext keys ever touch disk.
//
// Credentials stored in: %AppData%\FocusGuard\device.enc
// DPAPI scope: CurrentUser — only the enrolling user can decrypt.
//
// This is the Windows equivalent of:
//   macOS: Keychain
//   Android: Android Keystore

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FocusGuard.Windows.Domain.Models;
using Microsoft.Extensions.Logging;

namespace FocusGuard.Windows.Storage;

/// <summary>
/// Secure storage for FocusGuard device identity and policy cache.
/// Uses Windows DPAPI for credential encryption and SQLite for policy/usage data.
/// </summary>
public sealed class SecureLocalStorage
{
    private readonly string _appDataPath;
    private readonly ILogger<SecureLocalStorage> _logger;

    private const string CredentialFileName = "device.enc";
    private const string PolicyCacheFileName = "policy_cache.json";
    private const string UsageCacheFileName = "usage_today.json";

    public SecureLocalStorage(ILogger<SecureLocalStorage> logger)
    {
        _logger = logger;
        _appDataPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "FocusGuard");
        Directory.CreateDirectory(_appDataPath);
    }

    // ── Device Identity ───────────────────────────────────────────────────────

    /// <summary>
    /// Saves device identity encrypted with Windows DPAPI (CurrentUser scope).
    /// The deviceKey is the most sensitive field — it is the device's signing secret.
    /// </summary>
    public async Task SaveDeviceIdentityAsync(DeviceIdentity identity)
    {
        var json = JsonSerializer.Serialize(identity, DeviceIdentityContext.Default.DeviceIdentity);
        var plainBytes = Encoding.UTF8.GetBytes(json);

        // Encrypt with DPAPI (CurrentUser scope — only this user, this machine can decrypt)
        var encrypted = ProtectedData.Protect(plainBytes, null, DataProtectionScope.CurrentUser);

        var credPath = Path.Combine(_appDataPath, CredentialFileName);
        await File.WriteAllBytesAsync(credPath, encrypted);
        _logger.LogInformation("[FocusGuard Storage] Device identity saved (DPAPI encrypted)");
    }

    /// <summary>
    /// Loads device identity from DPAPI-encrypted local file.
    /// Returns null if no identity is stored (unpaired state).
    /// </summary>
    public async Task<DeviceIdentity?> LoadDeviceIdentityAsync()
    {
        var credPath = Path.Combine(_appDataPath, CredentialFileName);
        if (!File.Exists(credPath)) return null;

        try
        {
            var encrypted = await File.ReadAllBytesAsync(credPath);
            var plainBytes = ProtectedData.Unprotect(encrypted, null, DataProtectionScope.CurrentUser);
            var json = Encoding.UTF8.GetString(plainBytes);
            return JsonSerializer.Deserialize(json, DeviceIdentityContext.Default.DeviceIdentity);
        }
        catch (CryptographicException ex)
        {
            _logger.LogError(ex, "[FocusGuard Storage] DPAPI decryption failed. Credential may be from another user or corrupted.");
            return null;
        }
    }

    /// <summary>
    /// Deletes stored device identity (used during device revocation or uninstall).
    /// </summary>
    public void DeleteDeviceIdentity()
    {
        var credPath = Path.Combine(_appDataPath, CredentialFileName);
        if (File.Exists(credPath))
        {
            File.Delete(credPath);
            _logger.LogInformation("[FocusGuard Storage] Device identity deleted");
        }
    }

    // ── Policy Cache ──────────────────────────────────────────────────────────

    /// <summary>
    /// Persists the current policy list to local disk.
    /// Policies are NOT sensitive (they are commands, not credentials) so DPAPI is not needed.
    /// </summary>
    public async Task SavePoliciesAsync(IEnumerable<Policy> policies, int version)
    {
        var cache = new PolicyCacheFile(version, policies.ToArray());
        var json = JsonSerializer.Serialize(cache, PolicyCacheContext.Default.PolicyCacheFile);
        var cachePath = Path.Combine(_appDataPath, PolicyCacheFileName);
        await File.WriteAllTextAsync(cachePath, json);
        _logger.LogDebug("[FocusGuard Storage] Policy cache saved (v{Version})", version);
    }

    /// <summary>
    /// Loads the locally cached policy list.
    /// This enables offline policy enforcement after a restart.
    /// </summary>
    public async Task<(List<Policy> Policies, int Version)> LoadPoliciesAsync()
    {
        var cachePath = Path.Combine(_appDataPath, PolicyCacheFileName);
        if (!File.Exists(cachePath)) return ([], 0);

        try
        {
            var json = await File.ReadAllTextAsync(cachePath);
            var cache = JsonSerializer.Deserialize(json, PolicyCacheContext.Default.PolicyCacheFile);
            return (cache?.Policies?.ToList() ?? [], cache?.Version ?? 0);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "[FocusGuard Storage] Failed to load policy cache; starting with empty policies");
            return ([], 0);
        }
    }

    // ── Usage Cache ───────────────────────────────────────────────────────────

    /// <summary>
    /// Saves today's accumulated usage to local disk.
    /// Usage is keyed by target (domain or app name) → seconds used today.
    /// </summary>
    public async Task SaveTodayUsageAsync(Dictionary<string, int> usage)
    {
        var json = JsonSerializer.Serialize(usage);
        var usagePath = Path.Combine(_appDataPath, UsageCacheFileName);
        await File.WriteAllTextAsync(usagePath, json);
    }

    /// <summary>
    /// Loads today's usage. Returns empty dict if no data or if date has rolled over.
    /// </summary>
    public async Task<Dictionary<string, int>> LoadTodayUsageAsync()
    {
        var usagePath = Path.Combine(_appDataPath, UsageCacheFileName);
        if (!File.Exists(usagePath)) return [];

        try
        {
            var json = await File.ReadAllTextAsync(usagePath);
            // Check if usage file is from today (UTC date)
            var lastWrite = File.GetLastWriteTimeUtc(usagePath);
            if (lastWrite.Date != DateTime.UtcNow.Date)
            {
                _logger.LogInformation("[FocusGuard Storage] Usage data is from a previous day — resetting for today");
                return [];
            }

            return JsonSerializer.Deserialize<Dictionary<string, int>>(json) ?? [];
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "[FocusGuard Storage] Failed to load today's usage cache");
            return [];
        }
    }
}

// ── JSON Serialization Contexts (Source-Generated for AOT compatibility) ────────

[System.Text.Json.Serialization.JsonSerializable(typeof(DeviceIdentity))]
internal partial class DeviceIdentityContext : JsonSerializerContext { }

internal sealed record PolicyCacheFile(int Version, Policy[] Policies);

[System.Text.Json.Serialization.JsonSerializable(typeof(PolicyCacheFile))]
internal partial class PolicyCacheContext : JsonSerializerContext { }
