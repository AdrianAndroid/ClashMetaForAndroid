import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "gauge") }

            ProfilesView()
                .tabItem { Label("Profiles", systemImage: "doc.on.doc") }

            ProxiesView()
                .tabItem { Label("Proxies", systemImage: "square.stack.3d.up") }

            LogsView()
                .tabItem { Label("Logs", systemImage: "text.alignleft") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
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
