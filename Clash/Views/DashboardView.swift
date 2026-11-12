import ClashCoreKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    HStack {
                        Circle()
                            .fill(model.running ? Color.green : Color.secondary)
                            .frame(width: 10, height: 10)

                        Text(model.running ? "Connected" : "Disconnected")

                        Spacer()

                        Text(model.status.mode.uppercased())
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Profile", value: model.activeProfile?.name ?? "None")
                }

                Section("Traffic") {
                    LabeledContent("Upload", value: Self.format(model.status.upload) + "/s")
                    LabeledContent("Download", value: Self.format(model.status.download) + "/s")
                    LabeledContent("Total upload", value: Self.format(model.status.totalUpload))
                    LabeledContent("Total download", value: Self.format(model.status.totalDownload))
                }

                Section {
                    Button {
                        Task {
                            if model.running {
                                model.stopTunnel()
                            } else {
                                await model.startTunnel()
                            }
                        }
                    } label: {
                        Text(model.running ? "Stop" : "Start")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(model.busy || model.activeProfile == nil)
                }

                if model.running {
                    Section("Groups") {
                        ForEach(model.groupNames, id: \.self) { name in
                            NavigationLink(name) {
                                GroupDetailView(groupName: name)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Clash")
            .refreshable {
                await model.refreshTunnelStatus()
            }
        }
    }

    private static func format(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary

        return formatter.string(fromByteCount: Int64(value))
    }
}

struct GroupDetailView: View {
    @EnvironmentObject private var model: AppModel
    let groupName: String

    var body: some View {
        List {
            if let group = model.groups[groupName] {
                Section("Now: \(group.now)") {
                    ForEach(group.proxies) { proxy in
                        Button {
                            Task {
                                await model.select(group: groupName, proxy: proxy.name)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(proxy.title.isEmpty ? proxy.name : proxy.title)
                                    if !proxy.subtitle.isEmpty {
                                        Text(proxy.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if proxy.delay > 0 {
                                    Text("\(proxy.delay) ms")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if proxy.name == group.now {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(groupName)
        .toolbar {
            Button("Test") {
                Task {
                    await model.healthCheck(group: groupName)
                }
            }
        }
        .task {
            await model.refreshGroup(groupName)
        }
    }
}
