import SwiftUI
import UserNotifications
import Network

enum DeliveryMode: String, CaseIterable, Identifiable {
    case auto
    case hourly
    case twiceDaily = "twice_daily"
    case onceDaily = "once_daily"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:       "Immediate"
        case .hourly:     "Hourly Digest"
        case .twiceDaily: "Twice Daily"
        case .onceDaily:  "Once Daily"
        }
    }

    var description: String {
        switch self {
        case .auto:       "Get notified the moment something happens."
        case .hourly:     "Receive a summary every hour."
        case .twiceDaily: "Receive a summary at 12 pm and 6 pm."
        case .onceDaily:  "Receive a summary at 6 pm."
        }
    }
}

struct PreferencesView: View {
    @AppStorage("tapes_appearance_mode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("tapes_marketing_emails") private var marketingEmails = true
    @AppStorage("tapes_product_updates") private var productUpdates = true
    @AppStorage("tapes_delivery_mode") private var deliveryModeRaw = DeliveryMode.auto.rawValue
    @AppStorage("tapes_delivery_mode_pending_sync") private var pendingSync = false
    @AppStorage("allowCellularUploads") private var allowCellularUploads = true

    @EnvironmentObject private var authManager: AuthManager

    @State private var notificationsEnabled = false
    @State private var notificationsDetermined = false
    @State private var monitor: NWPathMonitor?

    private var deliveryMode: Binding<DeliveryMode> {
        Binding(
            get: { DeliveryMode(rawValue: deliveryModeRaw) ?? .auto },
            set: { newValue in
                deliveryModeRaw = newValue.rawValue
                syncPreference(mode: newValue)
            }
        )
    }

    var body: some View {
        Form {
            notificationsSection.listRowBackground(Tokens.Colors.secondaryBackground)
            deliverySection.listRowBackground(Tokens.Colors.secondaryBackground)
            communicationSection.listRowBackground(Tokens.Colors.secondaryBackground)
            uploadsSection.listRowBackground(Tokens.Colors.secondaryBackground)
            appearanceSection.listRowBackground(Tokens.Colors.secondaryBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
        .navigationTitle("Preferences")
        .task {
            await checkNotificationStatus()
            await loadServerPreference()
            startConnectivityMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await checkNotificationStatus() }
        }
        .onDisappear { monitor?.cancel() }
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

    // MARK: - Delivery

    private var deliverySection: some View {
        Section {
            Picker("Delivery", selection: deliveryMode) {
                ForEach(DeliveryMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
        } header: {
            Text("Notification Delivery")
        } footer: {
            Text((DeliveryMode(rawValue: deliveryModeRaw) ?? .auto).description)
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

    // MARK: - Uploads

    private var uploadsSection: some View {
        Section {
            Toggle("Allow Cellular Uploads", isOn: $allowCellularUploads)
                .onChange(of: allowCellularUploads) { _, _ in
                    BackgroundTransferManager.shared.refreshSession()
                }
        } header: {
            Text("Uploads")
        } footer: {
            Text("When off, tape uploads and downloads will wait for a Wi-Fi connection.")
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

    private func loadServerPreference() async {
        guard let api = authManager.apiClient else { return }
        do {
            let user = try await api.getMe()
            if let serverMode = user.deliveryMode,
               let mode = DeliveryMode(rawValue: serverMode) {
                deliveryModeRaw = mode.rawValue
            }
        } catch { }
    }

    private func syncPreference(mode: DeliveryMode) {
        guard let api = authManager.apiClient else {
            pendingSync = true
            startConnectivityMonitor()
            return
        }

        Task {
            do {
                _ = try await api.updateNotificationPreference(
                    deliveryMode: mode.rawValue,
                    timezone: TimeZone.current.identifier
                )
                pendingSync = false
            } catch {
                pendingSync = true
                startConnectivityMonitor()
            }
        }
    }

    private func startConnectivityMonitor() {
        guard monitor == nil else { return }
        let pathMonitor = NWPathMonitor()
        pathMonitor.pathUpdateHandler = { path in
            guard path.status == .satisfied, pendingSync else { return }
            let mode = DeliveryMode(rawValue: deliveryModeRaw) ?? .auto
            syncPreference(mode: mode)
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.studiomorph.tapes.netmonitor"))
        monitor = pathMonitor
    }
}

#Preview {
    NavigationStack {
        PreferencesView()
            .environmentObject(AuthManager())
    }
}
