import SwiftUI
import FocusGuardCore

public struct MainAppView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if let logoPath = Bundle.main.path(forResource: "AppLogo", ofType: "png") ?? (FileManager.default.fileExists(atPath: "/Applications/FocusGuard.app/Contents/Resources/AppLogo.png") ? "/Applications/FocusGuard.app/Contents/Resources/AppLogo.png" : nil),
                       let nsImg = NSImage(contentsOfFile: logoPath) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .frame(width: 38, height: 38)
                            .cornerRadius(9)
                            .shadow(color: Color.cyan.opacity(0.4), radius: 6)
                    } else {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 26))
                            .foregroundColor(.cyan)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("FOCUSGUARD")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Fleet Node")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                if appState.isEmergencyLocked {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("REMOTE STOP ACTIVE")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.red)
                        Spacer()
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.15))
                    .cornerRadius(8)
                    .padding(.horizontal, 12)
                } else if appState.isFocusActive {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("FOCUS LOCKDOWN")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.orange)
                        Spacer()
                        Text("\(appState.focusRemainingSeconds / 60)m")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(8)
                    .padding(.horizontal, 12)
                }

                Divider()

                List(AppState.NavigationItem.allCases, id: \.self, selection: $appState.selectedTab) { item in
                    NavigationLink(value: item) {
                        Label(item.rawValue, systemImage: item.iconName)
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 220)
        } detail: {
            Group {
                switch appState.selectedTab {
                case .dashboard:
                    DashboardView()
                case .usage:
                    UsageView()
                case .policies:
                    PoliciesView()
                case .applications:
                    ApplicationsView()
                case .devices:
                    DevicesView()
                case .diagnostics:
                    DiagnosticsView()
                }
            }
            .frame(minWidth: 540, minHeight: 480)
        }
    }
}
