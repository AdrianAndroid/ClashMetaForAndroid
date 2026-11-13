import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection = RootView.initialTab

    private static var initialTab: Int {
        let arguments = ProcessInfo.processInfo.arguments

        if let index = arguments.firstIndex(of: "-tab"),
           arguments.count > index + 1,
           let tab = Int(arguments[index + 1]) {
            return tab
        }

        return 0
    }

    var body: some View {
        TabView(selection: $selection) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "gauge") }
                .tag(0)

            ProfilesView()
                .tabItem { Label("Profiles", systemImage: "doc.on.doc") }
                .tag(1)

            ProxiesView()
                .tabItem { Label("Proxies", systemImage: "square.stack.3d.up") }
                .tag(2)

            LogsView()
                .tabItem { Label("Logs", systemImage: "text.alignleft") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
