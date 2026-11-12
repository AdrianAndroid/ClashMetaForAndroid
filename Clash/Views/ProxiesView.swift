import SwiftUI

struct ProxiesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if !model.running {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tunnel is not running")
                            .font(.headline)

                        Text("Start the tunnel to browse proxies")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else if model.groupNames.isEmpty {
                    ProgressView()
                        .task {
                            await model.refreshGroups()
                        }
                }

                ForEach(model.groupNames, id: \.self) { name in
                    NavigationLink {
                        GroupDetailView(groupName: name)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name)

                            if let group = model.groups[name] {
                                Text("Now: \(group.now) · \(group.proxies.count) nodes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Proxies")
            .toolbar {
                Button {
                    Task {
                        await model.refreshGroups()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!model.running)
            }
            .refreshable {
                await model.refreshGroups()
            }
            .task {
                if model.running {
                    await model.refreshGroups()
                }
            }
        }
    }
}
