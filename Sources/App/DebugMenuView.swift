#if DEBUG || TESTFLIGHT
import SwiftUI
import SQLiteData
import Dependencies
import IssueReporting
import Sharing
import UIKit
import UniformTypeIdentifiers

// MARK: - Debug Date Override

extension SharedKey where Self == AppStorageKey<Date?>.Default {
    static var debugDateOverride: Self {
        Self[.appStorage("debug_date_override"), default: nil]
    }
}

// MARK: - Debug Menu View

struct DebugMenuView: View {
    @Dependency(\.defaultDatabase) var database
    @Environment(\.dismiss) var dismiss

    @Shared(.debugDateOverride) var debugDate: Date?
    @State private var selectedDate: Date = Date()
    @State private var backupURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Override Current Date", isOn: isOverrideEnabled)

                    if debugDate != nil {
                        DatePicker(
                            "Date",
                            selection: $selectedDate,
                            displayedComponents: .date
                        )

                        HStack {
                            Button {
                                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button("Today") {
                                selectedDate = Date()
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button {
                                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("Time Travel")
                } footer: {
                    if debugDate != nil {
                        Text("Restart the app for changes to take effect.")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button("Seed Database") {
                        seedDatabase()
                    }
                }

                Section("Data Backup") {
                    Button("Backup Database") {
                        backupDatabase()
                    }
                }
            }
            .navigationTitle("Debug Menu")
            .sheet(item: $backupURL) { url in
                ShareSheet(activityItems: [url])
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let debugDate {
                    selectedDate = debugDate
                }
            }
            .onChange(of: selectedDate) { _, newValue in
                if debugDate != nil {
                    $debugDate.withLock { $0 = newValue }
                }
            }
        }
    }

    private var isOverrideEnabled: Binding<Bool> {
        Binding(
            get: { debugDate != nil },
            set: { newValue in
                if newValue {
                    $debugDate.withLock { $0 = selectedDate }
                } else {
                    $debugDate.withLock { $0 = nil }
                }
            }
        )
    }

    private func seedDatabase() {
        withErrorReporting {
            try seedSampleData()
        }
        dismiss()
    }

    private func backupDatabase() {
        withErrorReporting {
            let fileManager = FileManager.default

            // Get version and build number
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

            // Create timestamped filename
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let timestamp = formatter.string(from: Date())

            let filename = "DosMangos_v\(version)_\(build)_\(timestamp).sqlite"

            // Copy to temp directory for sharing
            let tempDir = fileManager.temporaryDirectory
            let destinationURL = tempDir.appendingPathComponent(filename)

            // Remove existing file if present
            try? fileManager.removeItem(at: destinationURL)

            // Use GRDB's backup API for transactionally-consistent snapshot
            let destination = try DatabaseQueue(path: destinationURL.path)
            try database.backup(to: destination)

            backupURL = destinationURL
        }
    }
}

// MARK: - Share Sheet

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            action()
        }
    }
}

extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name(rawValue: "deviceDidShakeNotification")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
    }
}
#endif

