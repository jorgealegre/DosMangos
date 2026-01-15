#if DEBUG || TESTFLIGHT
import SwiftUI
import SQLiteData
import Dependencies
import IssueReporting
import Sharing
import UIKit

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
            }
            .navigationTitle("Debug Menu")
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

