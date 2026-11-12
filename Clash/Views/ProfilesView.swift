import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                if model.profiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No profiles")
                            .font(.headline)

                        Text("Import a subscription URL to get started")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                ForEach(model.profiles) { profile in
                    Button {
                        model.setActive(profile.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(profile.name)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if model.activeProfileID == profile.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }

                            if !profile.isInstalled {
                                Text("Download failed or missing")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else {
                                Text(Self.detail(for: profile))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            model.delete(profile)
                        }

                        if profile.source == .url {
                            Button("Update") {
                                Task {
                                    await model.updateProfile(profile)
                                }
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Profiles")
            .toolbar {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddProfileView()
                    .environmentObject(model)
            }
        }
    }

    private static func detail(for profile: Profile) -> String {
        var parts: [String] = []

        if let used = profile.usedTraffic {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .binary
            parts.append("Used " + formatter.string(fromByteCount: used))
        }

        if let total = profile.total {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .binary
            parts.append("of " + formatter.string(fromByteCount: total))
        }

        if let expire = profile.expireDate {
            parts.append("expires " + expire.formatted(date: .abbreviated, time: .omitted))
        }

        if parts.isEmpty {
            parts.append("Updated " + Date(timeIntervalSince1970: TimeInterval(profile.updatedAt) / 1000)
                .formatted(date: .abbreviated, time: .shortened))
        }

        return parts.joined(separator: " · ")
    }
}

struct AddProfileView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Subscription") {
                    TextField("https://example.com/subscribe", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField("Name (optional)", text: $name)
                }
            }
            .navigationTitle("Import Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        Task {
                            await model.importProfile(url: url.trimmingCharacters(in: .whitespacesAndNewlines), name: name)
                            dismiss()
                        }
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .disabled(model.busy)
        }
    }
}
