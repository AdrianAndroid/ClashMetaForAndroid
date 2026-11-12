import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var autoScroll = true

    var body: some View {
        NavigationStack {
            List(model.logs) { line in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(line.level.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(color(for: line.level))

                        Spacer()

                        Text(timeText(line.time))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(line.message)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .listStyle(.plain)
            .navigationTitle("Logs")
            .toolbar {
                Button {
                    Task {
                        await model.refreshLogs()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!model.running)
            }
            .refreshable {
                await model.refreshLogs()
            }
        }
    }

    private func color(for level: String) -> Color {
        switch level {
        case "error": return .red
        case "warning": return .orange
        case "debug": return .secondary
        default: return .green
        }
    }

    private func timeText(_ time: Int64) -> String {
        guard time > 0 else { return "" }

        return Date(timeIntervalSince1970: TimeInterval(time) / 1000)
            .formatted(date: .omitted, time: .standard)
    }
}
