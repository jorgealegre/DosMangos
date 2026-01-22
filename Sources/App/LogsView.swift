#if DEBUG || TESTFLIGHT
import OSLog
import SwiftUI

private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
}()

struct LogsView: View {
    @State private var logs: [LogEntry] = []
    @State private var isLoading = false
    @State private var searchText = ""

    private var filteredLogs: [LogEntry] {
        if searchText.isEmpty {
            return logs
        }
        return logs.filter {
            $0.message.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if logs.isEmpty && isLoading {
                ProgressView("Loading logs...")
            } else if logs.isEmpty {
                ContentUnavailableView(
                    "No Logs",
                    systemImage: "doc.text",
                    description: Text("No logs found for this app.")
                )
            } else {
                List(filteredLogs) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.category)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(timeFormatter.string(from: entry.date))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Text(entry.message)
                            .font(.caption)
                            .foregroundStyle(entry.level.color)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    logs = []
                    Task { await loadLogs() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task {
            await loadLogs()
        }
        .searchable(text: $searchText, prompt: "Search logs")
    }

    private func loadLogs() async {
        isLoading = true
        defer { isLoading = false }

        let entries = await Task.detached {
            await Self.fetchLogs()
        }.value

        logs = entries.reversed()
    }

    private static func fetchLogs() -> [LogEntry] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let predicate = NSPredicate(format: "subsystem == %@", "dev.alegre.DosMangos")
            let entries = try store.getEntries(matching: predicate)

            var result: [LogEntry] = []
            for entry in entries {
                guard let logEntry = entry as? OSLogEntryLog else { continue }
                result.append(LogEntry(
                    id: UUID(),
                    date: logEntry.date,
                    category: logEntry.category,
                    message: logEntry.composedMessage,
                    level: LogLevel(logEntry.level)
                ))
            }
            return result
        } catch {
            return []
        }
    }
}

struct LogEntry: Identifiable {
    let id: UUID
    let date: Date
    let category: String
    let message: String
    let level: LogLevel
}

enum LogLevel {
    case debug
    case info
    case notice
    case error
    case fault

    init(_ level: OSLogEntryLog.Level) {
        switch level {
        case .debug: self = .debug
        case .info: self = .info
        case .notice: self = .notice
        case .error: self = .error
        case .fault: self = .fault
        case .undefined: self = .info
        @unknown default: self = .info
        }
    }

    var color: Color {
        switch self {
        case .debug: .secondary
        case .info: .primary
        case .notice: .blue
        case .error: .orange
        case .fault: .red
        }
    }
}
#endif
