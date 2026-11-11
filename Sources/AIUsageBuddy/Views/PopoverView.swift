import SwiftUI

/// メニューバーキャラクタークリック時のポップオーバー。
/// - アカウント切り替え
/// - 5時間枠・週間枠の残量%とプログレス
/// - リセットまでの残り時間／ローカル時刻でのリセット日時
/// - 最終取得日時・手動更新・stale/エラー警告・手動補正中表示
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// メニューバーと共通の5コマを表示する。Reduce Motion 時は静止画。
    @ViewBuilder
    private var headerCharacter: some View {
        let state = model.characterState
        if MotionPolicy.resolve(reduceMotionEnabled: reduceMotion) == .staticOnly || state == .unknown {
            FullBodyCat(state: state)
                .frame(width: 60, height: 44)
        } else {
            TimelineView(.periodic(from: .now, by: CatDrawing.cycleDuration(for: state) / Double(CatDrawing.menuFrameCount(for: state)))) { timeline in
                FullBodyCat(state: state, elapsed: timeline.date.timeIntervalSinceReferenceDate)
                    .frame(width: 60, height: 44)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.isSampleMode {
                SampleModeBanner(model: model)
            }

            if let account = model.selectedAccount {
                accountPicker(account: account)

                Divider()

                windowSection(
                    kind: .fiveHour,
                    window: model.snapshots[account.id]?.fiveHour
                )
                windowSection(
                    kind: .weekly,
                    window: model.snapshots[account.id]?.weekly
                )

                Divider()

                footer(accountID: account.id)
            } else {
                Text(L("popover.noAccount"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            headerCharacter
            VStack(alignment: .leading, spacing: 2) {
                Text(L("app.name"))
                    .font(.headline)
                Text(L(model.characterState.localizedNameKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.manualRefresh() }
            } label: {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help(L("popover.refresh.help"))
            .accessibilityLabel(L("popover.refresh.help"))
        }
    }

    // MARK: - Account picker

    private func accountPicker(account: Account) -> some View {
        Picker(L("popover.account"), selection: Binding(
            get: { account.id },
            set: { model.selectAccount($0) }
        )) {
            ForEach(model.accounts) { candidate in
                Text(candidate.displayName).tag(candidate.id)
            }
        }
        .labelsHidden()
    }

    // MARK: - Quota window

    @ViewBuilder
    private func windowSection(kind: QuotaLimitKind, window: QuotaWindow?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L(kind.localizedNameKey))
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let window {
                    Text(UsageFormatter.percent(window.remainingPercent, language: model.localization.currentLanguage))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(remainingColor(window.remainingPercent))
                    if window.state == .manual {
                        Text(L("popover.manualBadge"))
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.25)))
                    }
                } else {
                    Text(L("popover.noData"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let window {
                ProgressView(value: Double(window.remainingPercent), total: 100)
                    .progressViewStyle(QuotaProgressStyle(color: remainingColor(window.remainingPercent)))

                HStack(spacing: 8) {
                    if let resetAt = window.resetAt {
                        Label {
                            Text(UsageFormatter.remainingTime(
                                from: Date(),
                                to: resetAt,
                                language: model.localization.currentLanguage
                            ))
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text(UsageFormatter.resetDateTime(resetAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L("popover.resetUnknown"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(windowAccessibilityText(kind: kind, window: window))
    }

    private func windowAccessibilityText(kind: QuotaLimitKind, window: QuotaWindow?) -> String {
        guard let window else {
            return "\(L(kind.localizedNameKey)): \(L("popover.noData"))"
        }
        var text = "\(L(kind.localizedNameKey)): \(window.remainingPercent)%"
        if window.state == .manual {
            text += ", \(L("popover.manualBadge"))"
        } else if window.state == .stale {
            text += ", \(L("popover.staleWarning"))"
        }
        return text
    }

    private func remainingColor(_ percent: Int) -> Color {
        let highContrast = colorSchemeContrast == .increased
        if percent <= 10 {
            return highContrast ? .red : Color.red.opacity(0.9)
        } else if percent <= 30 {
            return highContrast ? .orange : Color.orange.opacity(0.9)
        }
        return highContrast ? .green : Color.green.opacity(0.9)
    }

    // MARK: - Footer

    private func footer(accountID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let snapshot = model.snapshots[accountID] {
                // 取得エラー（種別ごとの説明と導線）
                if let kind = snapshot.lastErrorKind {
                    errorCard(kind: kind, detail: snapshot.lastErrorMessage)
                } else if snapshot.isStale() {
                    // 種別不明のまま古くなっている場合（旧データ等）
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L(UsageErrorKind.stale.titleKey))
                                .font(.caption.weight(.medium))
                            if let error = snapshot.lastErrorMessage {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.yellow)
                    }
                }

                // 手動補正中の表示
                if model.snapshotStore.hasManualOverride(accountID: accountID) {
                    Label {
                        Text(L("popover.manualActive"))
                            .font(.caption)
                    } icon: {
                        Image(systemName: "pencil.and.list.clipboard")
                            .foregroundStyle(.orange)
                    }
                }

                if let fetchedAt = snapshot.fetchedAt {
                    Text("\(L("popover.lastFetched")): \(UsageFormatter.fetchedDateTime(fetchedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button(L("popover.openSettings")) {
                    model.openSettingsWindow()
                }
                .buttonStyle(.link)
                .font(.caption)
                Spacer()
                Button(L("popover.quit")) {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.link)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Error card

    /// エラー種別ごとの説明と導線（再試行・設定）。前回値は stale として表示し続ける。
    @ViewBuilder
    private func errorCard(kind: UsageErrorKind, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(kind.titleKey))
                        .font(.caption.weight(.medium))
                    Text(L(kind.explanationKey))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } icon: {
                Image(systemName: kind == .authenticationRequired ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle")
                    .foregroundStyle(kind == .authenticationRequired ? Color.orange : Color.yellow)
            }

            HStack(spacing: 10) {
                ForEach(kind.recommendedAction == .openSettings ? ErrorAction.allCases.filter { $0 == .openSettings } : ErrorAction.allCases, id: \.self) { action in
                    Button(L(action.buttonTitleKey)) {
                        switch action {
                        case .retry:
                            Task { await model.manualRefresh() }
                        case .openSettings:
                            model.openSettingsWindow()
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }
}

/// 残量バーのスタイル（高コントラスト対応）。
struct QuotaProgressStyle: ProgressViewStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        let fraction = configuration.fractionCompleted ?? 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: max(4, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
    }
}
