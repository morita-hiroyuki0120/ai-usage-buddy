# Mac App Store公開チェックリスト

このチェックリストは無料配布を目指すMac版の提出準備に使う。
現在は提出前であり、App Store Connectへのアップロードや審査提出は行っていない。
2026-10-23更新。ローカル検証済みの範囲と提出対象の未完了を分け、archive/exportの具体的な設定不足は[提出構成の準備状況](store-submission-readiness.md)へ集約する。

## 公開条件

- 価格は無料。
- 確認したアプリ本体には広告、アプリ内課金、独自analyticsの実装はなく、helperのデータ処理は別途確認する。
- サポートURLは[GitHub Issues](https://github.com/morita-hiroyuki0120/ai-usage-buddy/issues)。
- 公開プライバシーポリシーURLは未作成。
- アプリはCodex app-serverを介してOpenAIへログインし、アカウント情報と利用枠を取得する。
- Store版のGitHub Releases自動確認と手動確認は無効化済み。Direct版の更新確認と、利用者が開くWebページの通信は別に扱う。
- アカウント情報、利用枠スナップショット、設定をローカルに保存する実装がある。
- 外部通信と保存項目を最終ビルドで確認するまで、「データを一切送信しない」「申告対象データなし」と記載しない。

## Store版の実装と署名

- [x] Store隔離、keyring/direct指定、managed削除時logoutを実装し、DirectとStore flagの全体テスト各185件の成功を記録した。
- [ ] 提出対象の差分と構成を固定する。
- [ ] ChatGPT.appの同梱CLIやPATH上のCLIがないMacでも、Store版が必要な機能を実行できることを確認する。
- [ ] 同梱helperを使う場合、実際に配布するバージョン、ソース、hash、依存関係のライセンスとNOTICEを確定する。
- [ ] helperのtelemetry、MCP/plugin実行範囲、ファイルとネットワークへのアクセス、子プロセスの終了動作を監査する。
- [ ] Apache-2.0等のコードライセンスと、OpenAIの認証やサービス利用条件を別々に確認する。
- [ ] App Sandbox、network、Hardened Runtime、helperのinherit entitlement、実行コード署名をStore版で検証する。
- [ ] 採用するブラウザログインcallback方式で、戻りと失敗時の動作を提出対象で確認する。URL scheme登録を一律の前提にはしない。
- [x] 専用ローカル署名Sandbox版XCwI1pについて、公式ログイン後の5時間枠と週間枠の残量およびリセット時刻表示を人が確認した。
- [x] 同じ検証版で、終了と再起動後の再ログイン不要、対象アカウント削除後の終了と再起動でアカウントと残量が非表示となったとの人間報告を記録した。
- [ ] 提出対象の署名済みビルドで認証とアカウント分離、callback、helper停止を再検証し、実在する審査手順を説明できるようにする。人のUI確認をKeychain実内容や実項目削除、remote失効の検証とは扱わない。
- [x] Store版のGitHub Releases更新確認を無効化し、Direct版のargvと挙動を維持する回帰を確認した。
- [x] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`のローカルRelease buildとテスト結果を記録した。
- [ ] Store用archive/export、profile、配布署名、entitlementsと同梱物を検証する。
- [ ] TestFlight相当の配布候補を実機で確認し、提出するarchiveと同一のビルドであることを記録する。

## プライバシーと製品ページ

- [ ] 実装とhelperを調べ、OpenAIへのauth/account/quota通信とその他の通信候補、ローカル保存、保持期間、削除方法を整理する。Storeで無効なGitHub更新確認、Direct版、Webホストの処理を混同しない。
- [ ] 実際の通信と保存に一致するプライバシーポリシーを作り、公開URLを用意する。
- [ ] App Store Connectのプライバシー項目を、アプリ本体と同梱helperの挙動に照らして回答する。
- [ ] 説明文、対応macOS、必要なChatGPTログイン、サポートURL、プライバシーURLを整える。
- [ ] アイコン、対象サイズのスクリーンショット、日本語と英語の掲載情報を用意する。
- [ ] 審査メモには実在するログイン手順と制約だけを書く。審査用アカウントや資格情報を作り話で用意しない。
- [ ] 既存の著作権表示、同梱コード、画像、フォント、依存物のライセンスとNOTICEを確認する。
- [ ] notices本文の収集に加え、MPL対象の対応source取得案内と公開経路、ORライセンスの選択、配布対象への適用と義務を確認する。

## 提出直前

- [ ] 現行のApple提出要件を確認し、archive、署名、entitlement、プライバシー回答、掲載内容が一致することを確認する。
- [ ] 外部通信、ログ、アカウント削除、アンインストール後のデータ扱いを確認する。
- [ ] 提出対象のversion、build番号、署名済みarchiveと審査メモを記録する。
- [ ] 開発者がApp Store Connectへアップロードし、審査結果と要対応事項を記録する。

## Historical（2026-10-23改訂前の記録）

2026-10-16/18の独立SandboxProbeは、公式ログインとquota、再起動保持の人間確認があった一方、外部ChatGPT.app同梱CLIへ依存する当時の検証だった。
この過去記録はローカル作業記録（公開対象外）に保持し、今回のnative通常UI検証版や提出用archiveの検証とは分ける。
本チェックリストの改訂前にあった「Store実装取込とUI確認は未了」「更新有効時にGitHubへ通信」という項目は当時の計画記述であり、現在のStore実装と人間確認範囲は上記へ更新した。
過去の監査結果そのものは上書きせず、未完了の提出条件を完了扱いしない。
