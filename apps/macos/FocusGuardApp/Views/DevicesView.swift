import SwiftUI
import FocusGuardCore

public struct DevicesView: View {
    @EnvironmentObject var appState: AppState
    @State private var pairingTokenInput: String = ""
    @State private var pairingCodeInput: String = ""
    @State private var customDeviceIdInput: String = UUID().uuidString
    @State private var isSubmittingCode: Bool = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device Identity & Pairing")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Cryptographic device enrollment and FocusGuard Cloud synchronization")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                // Status Card
                HStack(spacing: 16) {
                    Image(systemName: "laptopcomputer.and.iphone")
                        .font(.system(size: 36))
                        .foregroundColor(appState.isEnrolled ? .green : .orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.deviceName)
                            .font(.system(size: 18, weight: .bold))
                        Text("Device Status: \(appState.deviceStatus.rawValue)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(appState.isEnrolled ? .green : .orange)
                        Text("Device ID: \(appState.deviceId)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if appState.isEnrolled {
                        Button(role: .destructive, action: { appState.revokeCurrentDevice() }) {
                            Label("Revoke Device", systemImage: "xmark.shield")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(20)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)

                // Pairing Section
                if !appState.isEnrolled {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Enroll as FocusGuard Device")
                            .font(.system(size: 16, weight: .bold, design: .rounded))

                        Text("Pair with your FocusGuard account using the 6-character code shown on your Web Dashboard (http://localhost:3001).")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Button(action: {
                            Task {
                                await appState.autoEnrollWithLocalServer()
                            }
                        }) {
                            Label("1-Click Connect to Local Fleet (:8080)", systemImage: "bolt.horizontal.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)

                        HStack {
                            VStack { Divider() }
                            Text("OR").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                            VStack { Divider() }
                        }
                        .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Dashboard Pairing Code (e.g. FG-XXXXXX)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            HStack {
                                TextField("FG-XXXXXX", text: $pairingCodeInput)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.system(size: 14, design: .monospaced))

                                Button(isSubmittingCode ? "Enrolling..." : "Pair with Code") {
                                    isSubmittingCode = true
                                    Task {
                                        await appState.pairWithCode(code: pairingCodeInput)
                                        isSubmittingCode = false
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(pairingCodeInput.isEmpty || isSubmittingCode)
                            }
                        }

                        Divider().padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Advanced: Direct Device Token")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            HStack {
                                SecureField("Paste raw token...", text: $pairingTokenInput)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                Button("Connect Token") {
                                    if let devUuid = UUID(uuidString: customDeviceIdInput) {
                                        appState.pairDevice(deviceId: devUuid, deviceToken: pairingTokenInput)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(pairingTokenInput.isEmpty)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(12)
                }

                // Public Key PEM Card
                VStack(alignment: .leading, spacing: 10) {
                    Label("Ed25519 Public Key (Apple CryptoKit)", systemImage: "key.fill")
                        .font(.system(size: 14, weight: .bold))

                    Text("This hardware-derived public key signs device telemetry and offline event envelopes.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Text(appState.publicKeyPem.isEmpty ? "Generating key..." : appState.publicKeyPem)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                }
                .padding(16)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(12)
            }
            .padding(24)
        }
    }
}
