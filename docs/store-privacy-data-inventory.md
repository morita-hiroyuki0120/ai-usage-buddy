# App Store版の情報処理インベントリ

> 内部確認用。
> 公開用ポリシーではなく、法的助言やAppleの申告回答でもない。

## 状態と確認範囲

この表は、現時点のStore向けソースで確認できた保存と処理を、helperの未確認事項から分けて記録する。

privacy policyは未承認、未公開であり、公開URLも未作成である。

運営者名にPUREROAST&BREW, LIMITED LIABILITY COMPANYを使用することと、既存リポジトリのGitHub Pagesを公開先にする方針は利用者承認済みである。
この承認は名称と公開先方針に限り、privacy本文の確認、掲載承認、公開操作の承認は含まない。
公開前の隔離方針と承認手順は[公開計画](privacy-publication-plan.md)に記録する。

認証ファイル、Keychain、実ログ、利用者データ、稼働中アプリの保存内容は読んでいない。

| 対象 | ソースで確認できた内容 | 根拠と留保 |
|---|---|---|
| 設定 | Application Support配下のAIUsageBuddy/settings.jsonに、選択アカウント、表示枠、通知、言語、更新間隔、ログイン時起動、ショートカットなどを保存する。 | [SettingsStore.swift:18–22](../Sources/AIUsageBuddy/Services/SettingsStore.swift#L18-L22)、[SettingsStore.swift:48–57](../Sources/AIUsageBuddy/Services/SettingsStore.swift#L48-L57)、[UsageModels.swift:291–350](../Sources/AIUsageBuddy/Models/UsageModels.swift#L291-L350)。Store targetはApp Sandboxを有効にする（[entitlements:5–10](../Store/AIUsageBuddyStore.entitlements#L5-L10)）。 |
| アカウント | accounts.jsonにUUID、表示名、home種別、公式連携から得たメールアドレスとプラン種別を保存する。 | [AccountStore.swift:28–38](../Sources/AIUsageBuddy/Services/AccountStore.swift#L28-L38)、[AccountStore.swift:66–83](../Sources/AIUsageBuddy/Services/AccountStore.swift#L66-L83)、[UsageModels.swift:58–88](../Sources/AIUsageBuddy/Models/UsageModels.swift#L58-L88)。 |
| 利用枠 | snapshots.jsonに5時間枠と週間枠の残量、リセット時刻、取得時刻、取得状態、プラン、失敗概要を保存する。手動補正値と通知済みキーも保存する。 | [SnapshotStore.swift:8–14](../Sources/AIUsageBuddy/Services/SnapshotStore.swift#L8-L14)、[SnapshotStore.swift:27–35](../Sources/AIUsageBuddy/Services/SnapshotStore.swift#L27-L35)、[UsageModels.swift:31–39](../Sources/AIUsageBuddy/Models/UsageModels.swift#L31-L39)、[UsageModels.swift:91–105](../Sources/AIUsageBuddy/Models/UsageModels.swift#L91-L105)。 |
| 認証状態 | Store版はアカウントごとの管理homeをHOMEとCODEX_HOMEに指定する。起動policyはkeyringとdirect backendを明示する引数へ更新済み。固定版helper自体の既定modeはfileである。 | [CodexProcessConfiguration.swift:25–60](../Sources/AIUsageBuddy/Services/CodexProcessConfiguration.swift#L25-L60)、[AppServerRuntimePolicy.swift:3–17](../Sources/AIUsageBuddy/Services/AppServerRuntimePolicy.swift#L3-L17)。[人間によるUI確認](#2026-10-23の人間によるui確認)でログイン後の取得と再起動後の保持を報告済み。保存方式そのもの、実Keychain内容、旧file残存は未確認である。 |
| OpenAI連携 | 同梱Codex app-serverを介して、利用者が開始する公式ログイン、account/read、account/rateLimits/readを行う。ログイン時はhelperから受け取った認証URLを既定ブラウザで開く。 | [CodexAppServerClient.swift:340–366](../Sources/AIUsageBuddy/Services/CodexAppServerClient.swift#L340-L366)、[CodexUsageProvider.swift:70–140](../Sources/AIUsageBuddy/Services/CodexUsageProvider.swift#L70-L140)、[AppModel.swift:602–620](../Sources/AIUsageBuddy/Services/AppModel.swift#L602-L620)。実際の全送信内容、helperの別通信、OpenAI側の保持期間は未確定。 |
| macOS機能 | 通知を有効にして許可した場合、低残量時にアカウント表示名、残量、しきい値を含む通知をmacOSへ依頼する。ログイン時起動は利用者が明示的に有効化した場合に登録する。 | [NotificationScheduler.swift:45–79](../Sources/AIUsageBuddy/Services/NotificationScheduler.swift#L45-L79)、[LoginItemManager.swift:11–38](../Sources/AIUsageBuddy/Services/LoginItemManager.swift#L11-L38)、[AppSettings defaults](../Sources/AIUsageBuddy/Models/UsageModels.swift#L323-L336)。起動時には利用枠の更新を試みる（[AppModel.swift:204–219](../Sources/AIUsageBuddy/Services/AppModel.swift#L204-L219)）。 |
| GitHub更新 | Store channelでは自動確認と手動確認を停止する。Direct版のGitHub Releases確認は別の配布経路である。 | [UpdateService.swift:252–281](../Sources/AIUsageBuddy/Services/UpdateService.swift#L252-L281)、[AppModel.swift:475–489](../Sources/AIUsageBuddy/Services/AppModel.swift#L475-L489)。 |
| サポート | Store版設定の情報欄に[GitHub Issues](https://github.com/morita-hiroyuki0120/ai-usage-buddy/issues)への標準SwiftUI Linkを実装した。利用者のクリック時だけ外部ブラウザで開き、アプリのバックグラウンド通信やissue自動投稿は追加しない。 | [SettingsView](../Sources/AIUsageBuddy/Views/SettingsView.swift)のStore条件内に配置し、[ReleaseConfiguration.storeSupportURL](../Sources/AIUsageBuddy/Services/ReleaseConfiguration.swift)で承認済み固定HTTPS URLを定義する。queryやfragment、ログやaccount dataは付与しない。source実装の確認であり、実UIでのリンク操作とprivacy review承認は未実施。 |
| 公開予定のWebページ | GitHub Pagesでのホストを予定しているが、現時点では本文掲載未承認、未公開。公開後の閲覧時には、GitHubがサインインの有無にかかわらずセキュリティ目的で閲覧者のIPアドレスを記録し保存する。 | 一次資料の親による取得確認日：2026-10-23。[GitHub PagesのData collection節](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)、[GitHubの一般プライバシー声明](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)。Web閲覧時のホスト側処理であり、アプリのバックグラウンド送信、アプリ内analyticsの追加、Apple App Privacyの回答とは区別する。 |
| アカウント削除 | Store managedでは公式account/logout成功応答、所有helper停止確認、取消確認を経て、管理homeとローカル登録を削除する。成功後にsnapshot、補正値と設定を消す。logoutや停止確認の失敗、取消ではローカル削除を開始せず、安全なUIエラーを表示する。Direct版はlogoutを送らない既存処理を維持する。OpenAIアカウント自体の削除ではない。 | [AppModel.swift:759–814](../Sources/AIUsageBuddy/Services/AppModel.swift#L759-L814)、[CodexUsageProvider.swift:149–159](../Sources/AIUsageBuddy/Services/CodexUsageProvider.swift#L149-L159)、[ClientCache:278–340](../Sources/AIUsageBuddy/Services/CodexUsageProvider.swift#L278-L340)、[AccountStore.swift:86–130](../Sources/AIUsageBuddy/Services/AccountStore.swift#L86-L130)。ソースとmockの確認であり、実Keychain削除やremote失効成功の証明ではない。ローカル削除開始後のOS部分失敗と一覧保存失敗では一部だけ削除される可能性がある。 |

今回確認したアプリ本体コードの範囲では、広告、アプリ内課金、独自analyticsの実装を確認していない。

この限定的な確認は、同梱helperの通信やデータ処理がないことを意味しない。

## 2026-10-23の人間によるUI確認

対象は`build/store-keyring-interactive.XCwI1p/AI Usage Buddy.app`、BIDは`com.aiusagebuddy.app.store.keyringtest`である。
親が受領したhuman-confirmed UI evidenceとして、公式ログイン後の5時間枠と週間枠の残量およびリセット時刻表示を人が確認したという報告を記録する。
続いて、人が終了と再起動を行い、再ログインなしで残量が表示され、対象アカウントの削除後に再び終了と再起動を行うと、そのアカウントと残量が非表示になったと報告した。
本担当は画像や利用者データを再取得しておらず、この証拠をKeychain実項目の保存方式や削除、旧file消去、remote失効成功の検証とは扱わない。

## 認証保存と削除の固定ソース確認

2026-10-23に、helperの固定commit `83086188ae0614bd882818ff1aa23f3194962012`（0.163.0）の公開ソースと、本体の起動設定および削除処理を確認した。
初回調査はhelper側12ファイル、本体側7ファイル、公開manifest 1ファイルの計20ファイルに範囲を限定した。
後続のStore引数固定では、config解決、auth_keyring、featureキーの該当箇所だけを追加照合した。
以下はソース上の規則であり、実利用者の保存内容や実行時の有効設定を証明するものではない。

| 確認項目 | 固定ソースの規則と根拠 |
|---|---|
| modeの既定値と切替 | `cli_auth_credentials_store`は`file`、`keyring`、`auto`、`ephemeral`を選べ、既定値は`file`。`keyring`は利用不可なら失敗し、`auto`は読み込み時にkeyringが空または失敗するとfileへ、保存時にkeyringが失敗するとfileへフォールバックする。`ephemeral`はプロセス内メモリのみ。[config/src/types.rs:133–145](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/config/src/types.rs#L133-L145)、[core/src/config/mod.rs:4460–4465](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/mod.rs#L4460-L4465)、[login/src/auth/storage.rs:478–611](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/login/src/auth/storage.rs#L478-L611)。 |
| fileの保存 | `CODEX_HOME/auth.json`へJSONを書き込む。Unixで新規作成時に指定するmodeは0600であり、暗号化保存を示す実装ではない。[login/src/auth/storage.rs:162–173](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/login/src/auth/storage.rs#L162-L173)、[同:214–235](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/login/src/auth/storage.rs#L214-L235)。ChatGPTログインの保存処理は選択されたmodeへ渡す。[app-server/src/request_processors/account_processor.rs:605–615](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/account_processor.rs#L605-L615)、[login/src/server.rs:833–877](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/login/src/server.rs#L833-L877)。 |
| macOSのkeyring | macOSではapple-native backendを使う。既定backendは`direct`で、service名`Codex Auth`、CODEX_HOMEの正規化パス由来のキーを使用するため、HOMEを変えるだけではKeychain項目はディレクトリ内へ移動しない。別backendの`secrets`は暗号化ローカルファイルとOS keyring内の鍵を組み合わせる。[keyring-store/Cargo.toml:18–20](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/keyring-store/Cargo.toml#L18-L20)、[config/src/types.rs:165–181](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/config/src/types.rs#L165-L181)、[login/src/auth/storage.rs:243–256](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/login/src/auth/storage.rs#L243-L256)、[同:279–344](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/login/src/auth/storage.rs#L279-L344)。secretsの保存先詳細は今回の確認範囲外。 |
| 現在のStore設定 | HOMEとCODEX_HOMEはいずれもApplication Support配下の`AIUsageBuddy/Homes/<UUID>`。7つのconfig overrideに`cli_auth_credentials_store="keyring"`と`features.secret_auth_storage=false`を追加した。ローカル署名Sandbox版のUI動作は上記の人間報告で確認済みだが、実機の有効設定と保存方式の直接確認、管理要件との整合は未確認。[CodexProcessConfiguration.swift:32–60](../Sources/AIUsageBuddy/Services/CodexProcessConfiguration.swift#L32-L60)、[AppServerRuntimePolicy.swift:3–17](../Sources/AIUsageBuddy/Services/AppServerRuntimePolicy.swift#L3-L17)、[core/src/config/auth_keyring.rs:13–17](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/auth_keyring.rs#L13-L17)、[同:110–117](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/auth_keyring.rs#L110-L117)。 |
| helperのaccount/logout | 認証失効を試み、失敗しても選択modeのローカル認証削除を進める。非ephemeral modeではメモリ内認証も削除するが、全modeや過去の別backendを網羅する削除ではない。fileはauth.jsonのみ、direct keyringは対応項目とfallback file、autoはそのkeyring削除へ委ねる。削除失敗時に一部が残り得て、サーバー側失効の成功も保証しない。[app-server/src/request_processors/account_processor.rs:1047–1054](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/account_processor.rs#L1047-L1054)、[login/src/auth/manager.rs:2956–2973](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/login/src/auth/manager.rs#L2956-L2973)、[同:1463–1485](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/login/src/auth/manager.rs#L1463-L1485)、[login/src/auth/storage.rs:334–344](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/login/src/auth/storage.rs#L334-L344)、[同:530–539](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/login/src/auth/storage.rs#L530-L539)。 |
| アプリ内削除との関係 | Store managed削除はaccount/logoutを呼び、成功応答と所有helper停止を確認した後に管理homeの削除へ進む。失敗や取消では登録、管理home、snapshot、補正値と設定のローカル削除を開始しないが、helper内で既に起きた認証変更を巻き戻す保証はない。実機Keychain削除、remote失効成功、旧fileの消去は未検証である。home外の`Working/<UUID>`と`Temporary/<UUID>`は管理home削除の対象外で、内容やOS後処理も未確認。[AppModel.swift:759–814](../Sources/AIUsageBuddy/Services/AppModel.swift#L759-L814)、[ClientCache:278–340](../Sources/AIUsageBuddy/Services/CodexUsageProvider.swift#L278-L340)、[AccountStore.swift:86–130](../Sources/AIUsageBuddy/Services/AccountStore.swift#L86-L130)、[CodexProcessConfiguration.swift:41–60](../Sources/AIUsageBuddy/Services/CodexProcessConfiguration.swift#L41-L60)。 |

### Keychainのみという承認済み仕様との差分

初期承認済みの「認証情報が必要な場合はKeychainのみ」に向け、Store起動policyとmanifestに以下の設定引数を追加した。
Direct版のargvは変更していない。
コード上の引数固定に加え、Store managed削除からのlogout呼び出しと所有helper停止確認を実装済みである。
ローカル作業記録（公開対象外）の統合検証記録では、専用tmpのRPC fixtureとmock providerを使い、focused 49件、DirectとStoreの全体テスト各185件の成功を記録している。
この文書更新ではテストを再実行していない。
上記の人間報告で再起動後の残量表示と削除後の非表示を確認したが、実機の有効保存設定、Keychain実内容と項目削除、旧fileの移行や消去は未検証であり、remote失効成功も保証しない。

```toml
cli_auth_credentials_store = "keyring"
[features]
secret_auth_storage = false
```

現在のStoreは`--config`と`cli_auth_credentials_store="keyring"`、別の`--config`と`features.secret_auth_storage=false`をそれぞれ別argv要素として渡す。
保存modeは[core/src/config/mod.rs:4460–4465](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/mod.rs#L4460-L4465)、公開featureキーは[features/src/lib.rs:1065–1070](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/features/src/lib.rs#L1065-L1070)、falseからdirectへの対応は[core/src/config/auth_keyring.rs:110–117](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/auth_keyring.rs#L110-L117)で確認した。
bootstrap側も同featureからbackendを解決する（[同:85–107](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/auth_keyring.rs#L85-L107)）。

macOS用Cargo設定は`apple-native`を有効にし、既定のdirect backendは`keyring::Entry::new`からcredential factoryへ委ねるAPIを使う（[keyring-store/Cargo.toml:18–20](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/keyring-store/Cargo.toml#L18-L20)、[keyring-store/src/lib.rs:77–103](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/keyring-store/src/lib.rs#L77-L103)）。
この根拠は固定ソースのfeature宣言と呼び出しまでであり、依存crate内のfactory実装、公式配布バイナリへの実組込み、Sandbox署名下での利用可能性は今回の20ファイル確認では証明していない。
また、macOSの既定backendはdirectだが、別backendのsecretsはローカル暗号化ファイルも使うため、「Keychainのみ」の実装ではbackendの選択も確認対象になる（[config/src/types.rs:165–181](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/config/src/types.rs#L165-L181)）。

keyringが選択されたdirect backendでは、読み書きのエラーを伝播し、fileへフォールバックしない。
既存auth.jsonを読み込んで移行する処理もなく、Keychain項目がなければ未認証として扱う（[login/src/auth/storage.rs:279–319](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/login/src/auth/storage.rs#L279-L319)、[同:600–627](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/login/src/auth/storage.rs#L600-L627)、[login/src/auth/manager.rs:1566–1574](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/login/src/auth/manager.rs#L1566-L1574)）。
ただし、LOCAL_DEV_BUILD_VERSIONのビルドでは設定解決時にkeyringまたはautoをfileへ変更する特例があるため、これは「選択されたkeyring backendでの失敗処理」と区別する（[core/src/config/mod.rs:283–293](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/mod.rs#L283-L293)）。

direct keyringへの保存成功後は既存auth.jsonの削除を試みるが、削除失敗を警告して保存自体は成功として返すため、保存成功だけで古いfileの消去は保証できない。
keyring保存失敗時はこのcleanupへ進まず、既存fileが残り得る。
direct keyringのlogout削除はKeychain項目の削除後にfileを削除するため、前段のエラーでfileが残る場合もある（[login/src/auth/storage.rs:315–344](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/login/src/auth/storage.rs#L315-L344)）。
既存fileの有無や内容は確認しておらず、移行と残存情報への対応は次の実装判断として残す。

## 未確認事項と公開前TODO

Store向けhelperにはfeatures.plugins=false、analytics.enabled=false、OTel exporter無効化の設定を渡すが、helperの通信全体は未監査である。

従来の5設定を渡した実バイナリでinitialize、account、quotaの動作を確認した。
keyringとdirect指定を含むローカル署名版では、空profileの固定RPC検証に加え、上記の人間によるUI動作確認が済んでいる。
引数付き実行の成功と通信抑制効果の検証は別であり、全送信経路の網羅監査は未完了である（[EmbeddedAppServer.json:15–33](../config/EmbeddedAppServer.json#L15-L33)、[helper監査:91–115](codex-app-server-audit.md#L91-L115)）。

親の固定source限定調査では、`app-server/src/analytics_utils.rs`から渡るanalytics設定が`core/src/config/mod.rs:4619`で反映され、`analytics/src/client.rs:319`付近のSome(false)でqueueがNoneとなる経路を確認したという報告がある。
一方、MessageProcessorのconstructorから始まるModelsRefreshWorkerが起動直後と270秒ごとにlist_models(Online)を呼ぶため、model catalog取得等もauth/quota以外の通信調査候補として残す。
これは親から共有されたsource根拠の記録であり、このtaskで再監査やruntime通信観測はしておらず、analytics.enabled=falseを全通信停止の保証とは扱わない。

独自サーバーへの送信有無と、Apple App Privacyの「Data Not Collected」回答は別々の確認事項であり、現時点ではどちらも確定しない。

Appleの申告では同梱helperなどthird-party codeの実データ処理も含めて確認する必要があるため、現時点では回答を確定しない（[App Privacy reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy)）。

公開前にhelperの実データ処理と通信、保存期間、アンインストール後のcontainerの扱いを確認する。

運営者名の表示は承認済みのPUREROAST&BREW, LIMITED LIABILITY COMPANYを草稿へ反映した。
GitHub Pagesを公開先にする方針も承認済みだが、公開URL、アプリ内privacyリンク、Apple App Privacy回答、本文の最終確認と掲載承認は未完了である。

アンインストール後にsandbox containerが自動削除される保証は、今回確認していない。
