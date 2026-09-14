import SwiftUI

/// 初回セットアップ（5段階）。
/// 歓迎 → 公式アカウント接続（任意） → 通知許可（任意） → ログイン時自動起動（明示確認） → 使い方。
/// すべてのステップはスキップ可能で、未接続でも通常利用できる。
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settingsStore: SettingsStore

    @State private var notificationRequested = false

    init(model: AppModel) {
        _model = ObservedObject(wrappedValue: model)
        _settingsStore = ObservedObject(wrappedValue: model.settingsStore)
    }

    private var stepIndex: Int {
        OnboardingStep.allCases.firstIndex(of: model.onboardingStep) ?? 0
    }
    private var stepCount: Int { OnboardingStep.allCases.count }
    private var isLastStep: Bool { stepIndex == stepCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 500, height: 430)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            FullBodyCat(state: .energetic)
                .frame(width: 54, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("app.name"))
                    .font(.headline)
                Text("\(stepIndex + 1)/\(stepCount) — \(L(model.onboardingStep.titleKey))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("onboarding.skip")) {
                model.skipOnboarding()
            }
            .buttonStyle(.link)
            .font(.callout)
            .accessibilityHint(L("onboarding.skip.hint"))
        }
        .padding(14)
    }

    /// ステップ位置のインジケータ（Reduce Motionに配慮し装飾アニメーションなし）。
    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<stepCount, id: \.self) { index in
                Circle()
                    .fill(index <= stepIndex ? Color.accentColor : Color.primary.opacity(0.2))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stepIndex + 1)/\(stepCount)")
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                stepIndicator
                switch model.onboardingStep {
                case .welcome: welcomeStep
                case .connect: connectStep
                case .notifications: notificationsStep
                case .loginItem: loginItemStep
                case .usageGuide: usageGuideStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }

    private var welcomeStep: some View {
        OnboardingStepContent(
            titleKey: model.onboardingStep.titleKey,
            bodyKey: model.onboardingStep.bodyKey,
            bullets: [
                "onboarding.welcome.bullet1",
                "onboarding.welcome.bullet2",
                "onboarding.welcome.bullet3",
            ]
        )
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingStepContent(
                titleKey: model.onboardingStep.titleKey,
                bodyKey: model.onboardingStep.bodyKey
            )

            switch model.loginFlow {
            case .awaitingBrowserAuth(let authURL):
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("settings.login.waiting")).font(.callout)
                    Text(authURL)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    HStack {
                        Button(L("settings.login.reopen")) {
                            if let url = URL(string: authURL) { NSWorkspace.shared.open(url) }
                        }
                        Button(L("settings.login.cancel")) {
                            Task { await model.cancelLogin() }
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            case .completing:
                Text(L("settings.login.completing")).font(.callout)
            case .success(let name):
                Label(L("settings.login.success") + " " + name, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.callout)
            case .failed(let message):
                Label("\(L("settings.login.failed")): \(message)", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
                    .font(.callout)
                Button(L("onboarding.connect.action")) {
                    Task { await model.beginAddAccount() }
                }
            case .idle:
                Button {
                    Task { await model.beginAddAccount() }
                } label: {
                    Label(L("onboarding.connect.action"), systemImage: "person.crop.circle.badge.plus")
                }
                Text(L("onboarding.connect.optional"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingStepContent(
                titleKey: model.onboardingStep.titleKey,
                bodyKey: model.onboardingStep.bodyKey
            )
            if notificationRequested {
                Label(L("onboarding.notifications.done"), systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Button {
                    Task {
                        await model.requestNotificationAuthorizationFromOnboarding()
                        notificationRequested = true
                    }
                } label: {
                    Label(L("onboarding.notifications.action"), systemImage: "bell")
                }
                Text(L("onboarding.notifications.optional"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loginItemStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingStepContent(
                titleKey: model.onboardingStep.titleKey,
                bodyKey: model.onboardingStep.bodyKey
            )
            // 明示確認: ユーザーがこのボタンを押したときだけ登録する
            if settingsStore.settings.launchAtLogin {
                Label(L("onboarding.loginItem.enabled"), systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Button {
                    model.setLaunchAtLogin(true)
                } label: {
                    Label(L("onboarding.loginItem.action"), systemImage: "arrow.forward.circle")
                }
                Text(L("onboarding.loginItem.optional"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = model.launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var usageGuideStep: some View {
        OnboardingStepContent(
            titleKey: model.onboardingStep.titleKey,
            bodyKey: model.onboardingStep.bodyKey,
            bullets: [
                "onboarding.guide.bullet1",
                "onboarding.guide.bullet2",
                "onboarding.guide.bullet3",
                "onboarding.guide.bullet4",
                "onboarding.guide.bullet5",
            ]
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if stepIndex > 0 {
                Button(L("onboarding.back")) {
                    if let previous = OnboardingStep(rawValue: model.onboardingStep.rawValue - 1) {
                        model.goToOnboardingStep(previous)
                    }
                }
            }
            Spacer()
            Button(isLastStep ? L("onboarding.finish") : L("onboarding.next")) {
                model.advanceOnboarding()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
    }
}

/// ステップ本文（タイトル・説明・箇条書き）。VoiceOver向けに要素を結合する。
private struct OnboardingStepContent: View {
    let titleKey: String
    let bodyKey: String
    var bullets: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L(titleKey))
                .font(.title3.weight(.semibold))
            Text(L(bodyKey))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !bullets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(bullets, id: \.self) { key in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundStyle(.green)
                                .padding(.top, 2)
                            Text(L(key))
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
