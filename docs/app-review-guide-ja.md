# AI Usage Buddyの審査資料作成手引き

作成日：2026-11-09。内部チェック用の草稿であり、提出済み資料ではない。
今回の承認は実ログイン手順、機能説明、動画台本の準備までである。
動画は未撮影で、添付もしていない。
デモ実装、審査提出、upload、公開は行わない。

## 確認済み範囲と審査アクセスの課題

正式Store archiveは未完成で、[固定manifest](../config/EmbeddedAppServer.json)はnot-readyである。
ローカル署名Sandbox検証版では、公式ログイン後の5時間枠と週間枠の残量およびリセット時刻表示、再起動後の認証保持、削除後の非表示について人間の確認報告がある。
これは最終Store署名版や実Keychain項目の削除、remote失効を検証したものではない。
以下のチェック欄はこれからの資料確認用であり、過去報告だけでチェックを入れない。

case 103007143655へのDeveloper Support返信要旨は2026-11-09にユーザーから共有された。
一般的な提出情報と添付案内であり、個別の事前判断やデモ、4.8の承認ではない。
審査員が自分のアカウントを使えば十分とも、動画だけで十分とも判断しない。
既存資料で整理したGuideline 2.1(a)のprior approval条件は解消していない。
審査アクセス方法は[相談記録](store-review-access-plan.md)に沿って別途判断する。

## 撮影前に人間が確認する事項

- [ ] 撮影対象のbuild、保存先、撮影範囲、共有先を人間が承認する。今回の文書作成承認を撮影許可とみなさない。
- [ ] 正式候補かローカルSandbox検証版かを明示する。後者を提出用buildと呼ばない。
- [ ] ログインは人間が操作する。パスワード、2FA、セキュリティ確認を自動操作しない。
- [ ] 認証画面、ブラウザのアドレスバー、公式login URL、token、通知内の個人情報を撮影しない。認証の前に録画停止し、アプリへ戻った後に再開する。
- [ ] 個人メール、アカウント識別子、実利用残量と実リセット日時を公開repoへ保存しない。実データ画面が必要なら、マスク内容と機密審査用共有について別途承認を得る。
- [ ] 既存のサンプル画面はない。架空のsample UIや取得成功画面を作らない。手動補正を公式取得結果として見せない。

## 撮影台本と機能確認

| 場面 | 操作と確認欄 | 制約と説明 |
|---|---|---|
| 起動と未接続 | [ ] メニューバーの猫をクリックし、未接続時の実表示と「設定… / Settings…」を確認する。セットアップの接続はスキップ可能。 | 独立した本アプリ用アカウント登録はない。未接続では実quotaを表示できない。既定アカウント行の存在を認証済みと説明しない。 |
| 公式ログイン | [ ] 「アカウントを追加… / Add Account…」またはセットアップの「アカウントを接続… / Connect Account…」を使う手順を説明する。 | OpenAIの既存ChatGPTアカウントの公式ブラウザログイン。録画外で人間が操作する。個人credentialsを審査用入力欄や資料へ転記しない。利用枠が提供されるアカウント条件も確認する。 |
| quota表示 | [ ] アプリ復帰後、5時間枠 / 5-hour limit、週間枠 / Weekly limit、残量、リセットまでの時間と日時を確認する。 | 機密レビュー用に許可された範囲だけ撮影する。値は外部サービス由来であり、減少やreset発生を任意に再現できるとはしない。猫の状態変化が撮れなければ未実証と記す。 |
| 更新 | [ ] 「今すぐ更新 / Refresh Now」、取得中表示と取得日時を確認する。設定の「自動更新間隔 / Auto refresh interval」も示す。 | quota再取得とアプリ更新を区別する。Store版ではGitHub更新確認UIを出さない。実際の取得失敗を再現しなければstale成功例として撮らない。 |
| アカウントと表示枠 | [ ] 複数接続が承認され用意できた場合のみアカウント切替を確認する。「選択中のアカウント / Selected account」と「メニューバー表示リミット / Menu bar limit」で表示枠を選ぶ。 | 別アカウントがなければ切替の実証は未実施とする。メニューバー用の枠選択と、詳細画面の両枠表示を区別する。 |
| 設定と通知 | [ ] 「通知 / Notifications」「低残量通知 / Low-usage notifications」と2つのしきい値を確認する。初期値20%と10%、範囲5〜100%、5刻み。言語設定も確認する。 | 既存設定では初期値と異なる場合がある。実通知にはmacOS許可と条件が必要。通知は各アカウント、枠、しきい値につきreset枠ごとに1回で、stale、取得失敗中、手動補正値では送らない。設定操作だけで配信成功とは記載しない。 |
| ショートカット | [ ] 初期値⌃⌥Uでクイック利用状況、⌃⌥Rで手動更新を確認する。「クイック利用状況の表示 / Show quick usage window」で変更可能。 | 既存設定や他アプリとの競合があればその条件を記録する。 |
| 右クリック | [ ] 「今すぐ更新 / Refresh Now」「アカウント切り替え / Switch Account」「設定… / Settings…」「終了 / Quit」を確認する。 | 接続していないアカウントのデータを捏造しない。 |
| 再起動 | [ ] 許可された同一buildで終了と再起動を行い、実際の表示と認証要否を確認する。 | 過去のローカル確認報告を最終Store版の結果へ転用しない。 |
| 削除 | [ ] 削除対象を人間が承認した場合だけ「アカウントを削除 / Delete account」を確認する。再起動後の表示も記録する。 | Store実装は公式logoutと所有helper停止確認後にローカル削除を試みる。失敗時の保持とエラー表示も説明する。OpenAIアカウント自体の削除やremote失効成功とは扱わない。 |

確認できなかった場面は「未実施」として残す。
通知を出すための実quota消費や、架空データを実取得に見せる操作は行わない。

## 添付候補と提出前チェック

- [ ] 機能説明と[英語Review Notes候補](app-review-notes-en.md)を人間が確認する。
- [ ] 動画候補：未接続操作、録画外のログインを挟んだアプリ操作、許可範囲の設定確認。全て未撮影、未添付。
- [ ] 静止画候補：機密情報を除いた機能説明。新規撮影と共有承認は未実施。
- [ ] 添付前にマスクの漏れ、音声、通知、背景ウィンドウ、認証URLがないことを確認する。個人情報入り素材をrepoへ置かない。
- [ ] build識別情報と実施済み項目を最終提出物に合わせる。現在のStore versionとproject候補の未整合も解消前は隠さない。
- [ ] 審査用credentials欄へ秘密や架空アカウントを入力しない。アクセス手段の未解決を動画で代替解決済みとしない。
- [ ] 最終署名、helper同梱、sandbox権限と認証手順を別途確認する。今回の資料作成で配布可能とは判定しない。

## 根拠

UI名は[日本語](../Sources/AIUsageBuddy/Resources/ja.lproj/Localizable.strings)と[英語](../Sources/AIUsageBuddy/Resources/en.lproj/Localizable.strings)、操作は[SettingsView](../Sources/AIUsageBuddy/Views/SettingsView.swift)、[PopoverView](../Sources/AIUsageBuddy/Views/PopoverView.swift)、[右クリック](../Sources/AIUsageBuddy/Services/MenuBarContextMenu.swift)を照合した。
初期設定は[UsageModels](../Sources/AIUsageBuddy/Models/UsageModels.swift)、通知条件は[NotificationPolicy](../Sources/AIUsageBuddy/Services/NotificationPolicy.swift)、認証RPCは[client](../Sources/AIUsageBuddy/Services/CodexAppServerClient.swift)、起動設定は[runtime policy](../Sources/AIUsageBuddy/Services/AppServerRuntimePolicy.swift)を参照する。
権限の予定は[Store entitlements](../Store/AIUsageBuddyStore.entitlements)と[包装実装](../Tools/StorePackaging/prepare.py)に基づく。最終署名済み権限は未確認である。
保存済み検証の限界は[提出準備状況](store-submission-readiness.md)と[privacy inventory](store-privacy-data-inventory.md)を参照する。
