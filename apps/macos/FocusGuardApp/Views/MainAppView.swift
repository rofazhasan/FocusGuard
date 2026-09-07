import SwiftUI
import FocusGuardCore

public struct MainAppView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(AppState.NavigationItem.allCases, id: \.self, selection: $appState.selectedTab) { item in
                NavigationLink(value: item) {
                    Label(item.rawValue, systemImage: item.iconName)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .navigationTitle("FocusGuard")
            .listStyle(.sidebar)
            .frame(minWidth: 200)
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
