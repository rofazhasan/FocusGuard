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

                // Incognito Compliance Protection Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "eye.slash.fill")
                            .foregroundColor(.purple)
                            .font(.system(size: 16))
                        Text("Incognito & Private Browsing Compliance")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("ENFORCED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(4)
                    }

                    Text("FocusGuard extension operates with 'spanning' incognito access. If incognito windows are opened without extension protection, or if unapproved browsing occurs, the native watchdog alerts and enforces compliance.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color.purple.opacity(0.04))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple.opacity(0.15), lineWidth: 1)
                )

                // Central Admin Fleet Device Management & Blocking
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Paired Fleet Devices (\(appState.fleetDevices.count))")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text("Manage Android phones, macOS workstations, and browser extensions from central admin")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button(action: {
                                Task { await appState.fetchFleetDevices() }
                            }) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)

                            Button(action: {
                                Task { await appState.emergencyStopAllFleet() }
                            }) {
                                Label("🚨 Block All Devices", systemImage: "bolt.shield.fill")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }

                    if appState.fleetDevices.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "network")
                                .font(.system(size: 26))
                                .foregroundColor(.secondary)
                            Text("No remote fleet devices connected yet. Pair an Android phone or Chrome extension with your pairing code.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(appState.fleetDevices) { dev in
                                HStack(spacing: 12) {
                                    Image(systemName: dev.platformIcon)
                                        .font(.system(size: 18))
                                        .foregroundColor(dev.isLocked ? .red : .accentColor)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(dev.name)
                                                .font(.system(size: 13, weight: .semibold))
                                            Text(dev.platform)
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.secondary.opacity(0.12))
                                                .cornerRadius(4)
                                        }

                                        Text("ID: \(dev.id.prefix(8))... • Status: \(dev.status)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if dev.isLocked {
                                        HStack(spacing: 4) {
                                            Circle().fill(Color.red).frame(width: 6, height: 6)
                                            Text("LOCKED")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.red)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.red.opacity(0.12))
                                        .cornerRadius(6)

                                        Button(action: {
                                            Task { await appState.unblockDevice(id: dev.id) }
                                        }) {
                                            Label("Unblock", systemImage: "lock.open.fill")
                                                .font(.system(size: 11, weight: .semibold))
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.green)
                                    } else {
                                        HStack(spacing: 4) {
                                            Circle().fill(Color.green).frame(width: 6, height: 6)
                                            Text("ACTIVE")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.green)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.green.opacity(0.12))
                                        .cornerRadius(6)

                                        Button(action: {
                                            Task { await appState.blockDevice(id: dev.id) }
                                        }) {
                                            Label("Stop App", systemImage: "exclamationmark.octagon.fill")
                                                .font(.system(size: 11, weight: .semibold))
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.red)
                                    }
                                }
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(12)
                .onAppear {
                    Task { await appState.fetchFleetDevices() }
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
