import SwiftUI
import UserNotifications

struct PreferencesView: View {
    @AppStorage("tapes_appearance_mode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("tapes_marketing_emails") private var marketingEmails = true
    @AppStorage("tapes_product_updates") private var productUpdates = true

    @State private var notificationsEnabled = false
    @State private var notificationsDetermined = false

    var body: some View {
        Form {
            notificationsSection.listRowBackground(Tokens.Colors.secondaryBackground)
            communicationSection.listRowBackground(Tokens.Colors.secondaryBackground)
            appearanceSection.listRowBackground(Tokens.Colors.secondaryBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
        .navigationTitle("Preferences")
        .task { await checkNotificationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await checkNotificationStatus() }
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            if notificationsDetermined {
                Toggle("Push Notifications", isOn: Binding(
                    get: { notificationsEnabled },
                    set: { _ in openNotificationSettings() }
                ))
            } else {
                HStack {
                    Text("Push Notifications")
                    Spacer()
                    ProgressView()
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Manage tape activity alerts, collaboration invites, and sync updates. Opens system settings.")
        }
    }

    // MARK: - Communication

    private var communicationSection: some View {
        Section {
            Toggle("Product Updates", isOn: $productUpdates)
            Toggle("Tips & Recommendations", isOn: $marketingEmails)
        } header: {
            Text("Communication")
        } footer: {
            Text("Choose what emails you receive from Tapes.")
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        } footer: {
            Text("Choose how Tapes looks. System follows your device settings.")
        }
    }

    // MARK: - Helpers

    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            notificationsEnabled = settings.authorizationStatus == .authorized
            notificationsDetermined = true
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        PreferencesView()
    }
}
