import ClashCoreKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Tunnel") {
                    Picker("Stack", selection: $model.settings.stack) {
                        Text("GVisor").tag(TunStack.gvisor.rawValue)
                        Text("System").tag(TunStack.system.rawValue)
                        Text("Mixed").tag(TunStack.mixed.rawValue)
                    }

                    Toggle("IPv6", isOn: $model.settings.ipv6)
                    Toggle("Bypass private network", isOn: $model.settings.bypassPrivateNetwork)
                    Toggle("DNS hijacking", isOn: $model.settings.dnsHijacking)

                    Stepper("MTU: \(model.settings.mtu)", value: $model.settings.mtu, in: 1280...9000, step: 4)
                }

                Section("Notice") {
                    Text("These settings are applied the next time the tunnel starts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Storage") {
                    LabeledContent("Profiles", value: ClashShared.profilesDirectory.path)
                    LabeledContent("Logs", value: ClashShared.logsDirectory.path)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                    LabeledContent("Core", value: "mihomo")

                    Text("Core logic ported one to one from ClashMetaForAndroid. Powered by the mihomo kernel.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onChange(of: model.settings) { _ in
                model.saveSettings()
            }
        }
    }
}
