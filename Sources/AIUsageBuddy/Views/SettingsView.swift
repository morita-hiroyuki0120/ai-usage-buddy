import SwiftUI

/// 設定画面。
/// - アカウント追加・削除・表示名変更・表示リミット切り替え
/// - 通知オン/オフ・しきい値2つ
/// - ログイン時自動起動
/// - 日本語/英語・システム追従/手動上書き
/// - 手動補正・手動更新
struct SettingsView: View {
    @ObservedObject var model: AppModel
    /// しきい値等の変更をクリック直後に反映させるため、AppModel が使うのと同じ
    /// SettingsStore インスタンスを直接監視する（ネストした ObservableObject の
    /// 変更は AppModel の objectWillChange 経由では View へ伝播しないため）。
    @ObservedObject private var settingsStore: SettingsStore
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var scheduler = NotificationScheduler.shared
    @ObservedObject private var shortcutManager: GlobalShortcutManager
    @ObservedObject private var updateService: UpdateService

    init(model: AppModel) {
        _model = ObservedObject(wrappedValue: model)
        _settingsStore = ObservedObject(wrappedValue: model.settingsStore)
        _shortcutManager = ObservedObject(wrappedValue: model.shortcutManager)
        _updateService = ObservedObject(wrappedValue: model.updateService)
    }

    @State private var newDisplayName = ""
    @State private var renamingAccountID: UUID?
    @State private var renameText = ""
    @State private var manualFiveHour = ""
    @State private var manualWeekly = ""
    #if AI_USAGE_BUDDY_APP_STORE
    @State private var showsStoreNotices = false
    #endif

    var body: some View {
        Form {
            accountSection
            Divider()
            selectedAccountSection
            Divider()
            notificationSection
            Divider()
            shortcutSection
            if !model.distributionChannel.isAppStore {
                Divider()
                updateSection
            }
            Divider()
            generalSection
            Divider()
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 760)
        #if AI_USAGE_BUDDY_APP_STORE
        .sheet(isPresented: $showsStoreNotices) { StoreNoticesView() }
        #endif
    }

    // MARK: - Accounts

    private var accountSection: some View {
        Section(L("settings.accounts")) {
            if model.isSampleMode {
                SampleModeBanner(model: model)
                Text(L("sample.settings.note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(model.accounts) { account in
                accountRow(account)
            }

            if let deletionError = model.accountDeletionErrorMessage {
                Label(deletionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            loginFlowView

            if !model.isSampleMode {
                Button {
                    Task { await model.beginAddAccount() }
                } label: {
                    Label(L("settings.addAccount"), systemImage: "plus")
                }
                .disabled(loginInProgress)
            }

            if model.canStartSampleMode {
                Button {
                    model.startSampleMode()
                } label: {
                    Label(L("sample.start"), systemImage: "flask")
                }
                .disabled(loginInProgress)
                Text(L("sample.start.note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loginInProgress: Bool {
        switch model.loginFlow {
        case .awaitingBrowserAuth, .completing: return true
        default: return false
        }
    }

    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                if renamingAccountID == account.id {
                    TextField(L("settings.accountName"), text: $renameText, onCommit: {
                        model.renameAccount(account.id, displayName: renameText)
                        renamingAccountID = nil
                    })
                    .textFieldStyle(.roundedBorder)
                } else {
                    Text(account.displayName)
                    if let email = account.officialEmail {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let plan = account.officialPlanType {
                        Text(planLabel(plan))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if !model.isSampleMode {
                Button {
                    renamingAccountID = account.id
                    renameText = account.displayName
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help(L("settings.rename"))
                .accessibilityLabel(L("settings.rename"))

                Button(role: .destructive) {
                    Task { await model.deleteAccount(account.id) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(L("settings.delete"))
                .accessibilityLabel(L("settings.delete"))
            }
        }
    }

    @ViewBuilder
    private var loginFlowView: some View {
        switch model.loginFlow {
        case .awaitingBrowserAuth(let authURL):
            VStack(alignment: .leading, spacing: 6) {
                Text(L("settings.login.waiting"))
                    .font(.callout)
                HStack {
                    Button(L("settings.login.reopen")) {
                        if let url = URL(string: authURL) { NSWorkspace.shared.open(url) }
                    }
                    Button(L("settings.login.cancel")) {
                        Task { await model.cancelLogin() }
                    }
                }
            }
        case .completing:
            Text(L("settings.login.completing")).font(.callout)
        case .success(let name):
            Label(L("settings.login.success") + " " + name, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failed(let message):
            Label("\(L("settings.login.failed")): \(message)", systemImage: "xmark.circle")
                .foregroundStyle(.red)
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Selected account details (display limit + manual correction)

    private var selectedAccountSection: some View {
        Section(L("settings.selectedAccount")) {
            if let account = model.selectedAccount {
                Picker(L("settings.displayLimit"), selection: Binding(
                    get: { model.displayLimit(for: account.id) },
                    set: { model.setDisplayLimit($0, for: account.id) }
                )) {
                    Text(L(QuotaLimitKind.fiveHour.localizedNameKey)).tag(QuotaLimitKind.fiveHour)
                    Text(L(QuotaLimitKind.weekly.localizedNameKey)).tag(QuotaLimitKind.weekly)
                }

                manualCorrectionControls(account: account)

                Button {
                    Task { await model.manualRefresh() }
                } label: {
                    Label(
                        model.isRefreshing ? L("settings.refreshing") : L("settings.refreshNow"),
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(model.isRefreshing)
            } else {
                Text(L("popover.noAccount")).foregroundStyle(.secondary)
            }
        }
    }

    private func manualCorrectionControls(account: Account) -> some View {
        Group {
            if let snapshot = model.snapshots[account.id], snapshot.isStale() {
                Text(L("settings.manual.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(L(QuotaLimitKind.fiveHour.localizedNameKey))
                        .frame(width: 70, alignment: .leading)
                    TextField("0-100", text: $manualFiveHour)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("%")
                    if model.snapshotStore.manualOverride(accountID: account.id, kind: .fiveHour) != nil {
                        Button(L("settings.manual.clear")) {
                            model.clearManualOverride(accountID: account.id, kind: .fiveHour)
                        }
                        .buttonStyle(.link)
                    }
                }
                HStack {
                    Text(L(QuotaLimitKind.weekly.localizedNameKey))
                        .frame(width: 70, alignment: .leading)
                    TextField("0-100", text: $manualWeekly)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("%")
                    if model.snapshotStore.manualOverride(accountID: account.id, kind: .weekly) != nil {
                        Button(L("settings.manual.clear")) {
                            model.clearManualOverride(accountID: account.id, kind: .weekly)
                        }
                        .buttonStyle(.link)
                    }
                }
                Button(L("settings.manual.apply")) {
                    if let value = Int(manualFiveHour) {
                        model.setManualOverride(accountID: account.id, kind: .fiveHour, percent: value)
                    }
                    if let value = Int(manualWeekly) {
                        model.setManualOverride(accountID: account.id, kind: .weekly, percent: value)
                    }
                }
                .disabled(Int(manualFiveHour) == nil && Int(manualWeekly) == nil)
            }
        }
    }

    // MARK: - Notifications

    private var notificationSection: some View {
        Section(L("settings.notifications")) {
            Toggle(L("settings.notificationsEnabled"), isOn: Binding(
                get: { model.settingsStore.settings.notificationsEnabled },
                set: { model.settingsStore.settings.notificationsEnabled = $0 }
            ))

            ForEach(settingsStore.settings.notificationThresholds.indices, id: \.self) { index in
                // macOS の Stepper は手作り Binding(get:set:) との同期が不安定で
                // クリック時に setter が呼ばれないことがあるため、クロージャ直指定にする。
                Stepper(
                    onIncrement: {
                        let current = settingsStore.settings.notificationThresholds[index]
                        settingsStore.updateNotificationThreshold(at: index, to: min(100, current + 5))
                    },
                    onDecrement: {
                        let current = settingsStore.settings.notificationThresholds[index]
                        settingsStore.updateNotificationThreshold(at: index, to: max(5, current - 5))
                    }
                ) {
                    Text(
                        "\(L("settings.threshold")) \(index + 1): " +
                        "\(settingsStore.settings.notificationThresholds[index])%"
                    )
                }
            }

            if scheduler.authorizationStatus == .denied {
                Label(L("settings.notificationDenied"), systemImage: "bell.slash")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Button(L("settings.openNotificationSettings")) {
                    scheduler.openSystemNotificationSettings()
                }
            }
            Text(L("settings.notificationsCommonNote"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shortcuts

    /// グローバルショートカットの設定（キー記録・無効化・初期値復元）。
    private var shortcutSection: some View {
        Section(L("settings.shortcuts")) {
            shortcutRow(
                titleKey: "shortcut.name.showUsage",
                spec: settingsStore.settings.showUsageShortcut
            ) { updated in
                model.updateShortcuts(
                    show: updated,
                    refresh: settingsStore.settings.refreshShortcut
                )
            }
            shortcutRow(
                titleKey: "shortcut.name.refresh",
                spec: settingsStore.settings.refreshShortcut
            ) { updated in
                model.updateShortcuts(
                    show: settingsStore.settings.showUsageShortcut,
                    refresh: updated
                )
            }

            // 競合・登録失敗の表示
            ForEach(shortcutManager.validationIssues, id: \.self) { issue in
                Label(L(issue.messageKey), systemImage: "warningtriangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            ForEach(shortcutManager.failedShortcutNames, id: \.self) { name in
                Label(
                    "\(L("shortcut.error.registrationFailed")) (\(L(name)))",
                    systemImage: "xmark.circle"
                )
                .foregroundStyle(.red)
                .font(.caption)
            }

            Button(L("shortcut.restoreDefaults")) {
                model.updateShortcuts(show: .defaultShowUsage, refresh: .defaultRefresh)
            }
            Text(L("shortcut.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func shortcutRow(
        titleKey: String,
        spec: HotKeySpec,
        onChange: @escaping (HotKeySpec) -> Void
    ) -> some View {
        HStack {
            Text(L(titleKey))
            Spacer()
            ShortcutRecorderView(spec: spec, onChange: onChange)
                .frame(width: 130)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Update

    /// 更新確認（署名・公証前は確認とGitHub Releases手動案内のみ）。
    private var updateSection: some View {
        Section(L("settings.update")) {
            Toggle(L("settings.update.automaticCheck"), isOn: Binding(
                get: { settingsStore.settings.automaticUpdateChecksEnabled },
                set: { settingsStore.settings.automaticUpdateChecksEnabled = $0 }
            ))

            HStack {
                Button(L("settings.update.checkNow")) {
                    Task { await updateService.checkNow() }
                }
                .disabled(updateService.outcome == .checking)

                switch updateService.outcome {
                case .idle:
                    EmptyView()
                case .checking:
                    ProgressView()
                        .controlSize(.small)
                    Text(L("settings.update.checking"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .upToDate:
                    Text(L("settings.update.upToDate"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .available(let version, _):
                    Text("\(L("settings.update.available")): \(version)")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .notConfigured:
                    Text(L("settings.update.notConfigured"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let reason):
                    Text("\(L("settings.update.failed")): \(reason)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if case .available(_, let url) = updateService.outcome, url != nil {
                Button(L("settings.update.openReleases")) {
                    updateService.openReleasePage()
                }
            }

            Text(L("settings.update.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section(L("settings.general")) {
            Toggle(L("settings.launchAtLogin"), isOn: Binding(
                get: { model.settingsStore.settings.launchAtLogin },
                set: { enabled in
                    model.setLaunchAtLogin(enabled)
                }
            ))
            if let loginItemError = model.launchAtLoginError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(L("settings.rerunOnboarding")) {
                model.startOnboarding()
            }

            Picker(L("settings.language"), selection: Binding(
                get: { localization.override },
                set: { newValue in
                    if let newValue {
                        localization.override = newValue
                    } else {
                        localization.resetToSystemLanguage()
                    }
                }
            )) {
                Text(L("settings.language.system")).tag(AppLanguage?.none)
                Text(L(AppLanguage.japanese.localizedNameKey)).tag(AppLanguage?.some(.japanese))
                Text(L(AppLanguage.english.localizedNameKey)).tag(AppLanguage?.some(.english))
            }

            Picker(L("settings.refreshInterval"), selection: Binding(
                get: { model.settingsStore.settings.autoRefreshInterval },
                set: { model.settingsStore.settings.autoRefreshInterval = $0 }
            )) {
                Text("30s").tag(TimeInterval(30))
                Text("1m").tag(TimeInterval(60))
                Text("5m").tag(TimeInterval(300))
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        let release = ReleaseConfiguration.from()
        return Section(L("settings.about")) {
            LabeledContent(L("settings.about.version"), value: release.appVersion)
            if let build = Int(release.buildNumber), build > 0 {
                LabeledContent(L("settings.about.build"), value: release.buildNumber)
            }
            LabeledContent(L("settings.about.source"), value: L("settings.about.sourceValue"))
            #if AI_USAGE_BUDDY_APP_STORE
            if model.distributionChannel.isAppStore {
                Button(L("settings.notices.title")) { showsStoreNotices = true }
                    .accessibilityHint(L("settings.notices.hint"))
                if let supportURL = ReleaseConfiguration.storeSupportURL {
                    Link(L("settings.about.support"), destination: supportURL)
                        .accessibilityHint(L("settings.about.supportHint"))
                }
            }
            #endif
            if !model.isSampleMode, let completed = model.lastRefreshCompletedAt {
                LabeledContent(L("popover.lastFetched"), value: UsageFormatter.fetchedDateTime(completed))
            }
        }
    }

    private func planLabel(_ plan: String) -> String {
        "\(L("settings.plan")): \(plan)"
    }
}
