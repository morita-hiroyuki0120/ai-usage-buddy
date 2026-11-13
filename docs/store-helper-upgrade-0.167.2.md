# 同梱helperの0.167.2への更新

作成日：2026-11-13。状態：内部草稿。実行時検証、notice、ライセンス監査は未完了。
helperバイナリは実行していない。
ソースと依存先への接続は、公開GitHubからのダウンロードだけである。

## 更新理由

0.163.0のhelperは非公開の`/usr/lib/liblzma.5.dylib`にリンクしており、App Reviewで却下された。
公式の`rust-v0.167.2`は`liblzma`にリンクしないことを`otool -L`で確認した。
リンク先は公開framework、`libSystem`、`libobjc`、`libiconv`、`libbz2`のみである。
`libbz2`と`libiconv`は0.163.0でもリンクされていた。

## 固定した入力

| 項目 | 値 |
|---|---|
| tag | `rust-v0.167.2`（annotated tag `08a3b12b3298577534a28b62ed976acf8de66eda`） |
| commit | `ce21072c90d32c40af7a55b60b2fb35c84a43a6a` |
| 配布tar.gz | `codex-app-server-aarch64-apple-darwin.tar.gz`、82,824,270バイト |
| 配布tar.gz SHA-256 | `6d42b6a34bbe05d083e66b0dec65e23db77b2c87a82435882acfda043aab1e06` |
| ソースtar.gz SHA-256 | `11e3321cd1a158dcfd920f8d24b07a08e896b9eaa7f4800f3042227b56342170` |
| 展開ソースのファイル一覧hash | `25cf3d9ee71563b277a2e878c67beab17bf5fde4a8eefd45c7f09a70894b5913`（9,817ファイル、`build/helper-upgrade-0.167.2/src-manifest.sha256`のSHA-256） |

配布tar.gzのSHA-256は、GitHub Releases APIが返すdigestと、手元のダウンロード結果の両方で一致した。
tar.gzの中身は単一メンバー`codex-app-server-aarch64-apple-darwin`（約207MB）で、`prepare.py`の検査条件（単一メンバー、名前、300MiB以下）を満たす。
展開済みバイナリはOpenAIのDeveloper ID（Team `2DC432GLL2`）で署名され、`codesign --verify --strict`が通る。
ReleaseのAPI上の`target_commitish`は`main`だった。
そのためcommitは、tag参照からannotated tagを辿った結果を採用した。
ソースは`build/helper-upgrade-0.167.2/src/`に取得した。
配布tar.gzは`build/dependency-audit/codex-0.167.2/`にコピーした。
同じフォルダの`source-licenses/`には、ソースのLICENSEとNOTICEをそのまま置いた。
両ファイルのSHA-256は0.163.0のものと同一である。

## 確認した差分

比較対象は、`build/dependency-audit/codex-0.163.0/source-audit-83086188/`に保存済みの0.163.0ソースである。

### 起動引数

- `--listen stdio://`は引き続き既定値であり、有効である。
- `--config`（`CliConfigOverrides`）は引き続き受け付けられる。
- `cli_auth_credentials_store`は`file`、`keyring`、`auto`、`ephemeral`のままである。
- `analytics.enabled`の定義は0.163.0と同一である。
- `otel.exporter`、`otel.trace_exporter`、`otel.metrics_exporter`の種類は`none`、`statsig`、`otlp-http`、`otlp-grpc`のままで、`none`の扱いも変わらない。
- `features.plugins`と`features.secret_auth_storage`は存在する。
- `secret_auth_storage`の既定値は、macOSではfalseのままである（既定がtrueになるのはWindowsだけ）。
- 新しい引数`--cloud-skills-snapshot`、`--print-startup-config`などが加わったが、Storeは使わない。
- 名前変更や削除はないため、Swift側の起動引数は変更していない。

### JSON-RPC（protocol v2）

- `initialize`、`account/read`、`account/rateLimits/read`、`account/login/start`、`account/logout`、`account/login/completed`のメソッド名は同一である。
- `account/login/start`の`chatgpt`と`chatgptDeviceCode`は、パラメータもレスポンス（`loginId`、`authUrl`、`verificationUrl`、`userCode`）も同一である。
- `account/login/completed`通知（`loginId`、`success`、`error`）は同一で、新しい任意項目`onboardingEntrypoint`があるだけである。
- `account/read`の応答に`workspaceName`（任意）が加わり、`account.type`に`gcp`が加わった。Swift側のデコーダは未知の項目を無視し、`type`は文字列なので影響しない。
- `account/rateLimits/read`のパラメータ`excludeResetCreditDetails`と応答の形は同一である。
- `initialize`のcapabilitiesに任意項目`requiredHumanApproval`が加わった。Storeはcapabilitiesを送らない。
- `account/login/cancel`はSwift側で使っていない。
- 以上から、Swift側のRPCコードは変更していない。

### ネットワーク、テレメトリ、起動時処理

- モデル一覧の定期取得（`ModelsRefreshWorker`、270秒周期）のソースは0.163.0と同一である。
- ログイン、ログアウト、アカウント変更の後に`ModelCatalog.invalidate()`が呼ばれ、モデル一覧を取り直す経路が加わった。到達先は0.163.0と同じ種類のモデル取得である。
- プラグインの起動時処理に、新機能`plugin_discovery_prefetch`（既定true）が加わった。プラグイン一覧、推奨、featuredの先読みを行う。
- この先読みは`plugins_enabled`のブロック内にあるため、`features.plugins=false`で止まることをソースで確認した。
- ログイン完了時の`recommended_plugins_mode_for_config`の先読みも、先頭で`plugins_enabled`を判定して戻る。
- OTELの初期化（`otel_init.rs`）は、ヘッダ型の変更だけで、`none`の扱いは同一である。
- Statsigの指標は、`metrics_exporter`が`statsig`かつ`analytics.enabled`が偽なら無効になる。ただしStoreは3つのexporterすべてを`none`にしている。
- リモート制御は既定の`ResolvePersisted`のままで、Storeが明示的に有効にしない限り接続しない。
- 認証情報の保存は、`auth.lock`と`auth.json.lock`などのロックファイル、同一ディレクトリの一時ファイル作成を伴うようになった。保存先は`CODEX_HOME`（アカウント専用のhome）である。
- デバイスコードのログインは、ローカルのlistenerを開かず、HTTPSのクライアント通信だけで完結する。`network.server`は不要のままである。
- 新しいワークスペース切替（`accountSession/*`）、GCP設定、ガードレール関連のRPCが加わったが、Storeは呼ばない。

### Store sandboxの権限

- 新しいentitlementが必要になる変更は、ソース上では見つからなかった。
- 追加のlistener、Unix socket、ファイルアクセス範囲の拡大は確認していない。
- 新しいロックファイルの作成先は`CODEX_HOME`であり、既存のsandbox内の書込み範囲に収まる見込みである。

## 修正内容

- `config/EmbeddedAppServer.json`のversion、tag、sourceCommit、artifactのurlとsha256を0.167.2に更新した。
- `distributionStatus`を`not-ready`に戻した。
- `noticeAudit`と`transitiveLicenseAudit`を`pending`に戻した。notice生成とユーザーの再承認の後に戻す。
- `Tools/StorePackaging/prepare.py`の`COMMIT`、`ARCHIVE_SHA`、バージョン検査を更新した。
- `Tools/StorePackaging/tests/test_prepare.py`のfixtureを更新した。
- `Tools/StorePackaging/README.md`と`Tools/StoreRuntimeValidation/README.md`の固定値を更新した。
- `scripts/validate-store-runtime.sh`の期待SHA-256、ダウンロードURL、tar.gzの配置先、notice配置先を0.167.2に更新した。
- `scripts/store-release.sh`と`scripts/prepare-store-archive.sh`には0.163.0前提の値がなく、変更していない。
- Swift側は変更していない。起動引数とRPCに差分がなかったため、Swiftのテストも追加していない。
- `features.plugin_discovery_prefetch=false`は追加していない。`features.plugins=false`で止まることをソースで確認したためである。

## 未確認点と懸念

- helperを実行していないため、実際の起動、設定の実効値、実通信は未確認である。
- 特にデバイスコードのログイン（`chatgptDeviceCode`）の実機での成功、完了通知、キーチェーンへの保存は未確認である。
- 無効化設定（plugins、analytics、OTEL）が実行時に効くことは、ソース読取りのみの確認である。
- `plugin_discovery_prefetch`は、`plugins=false`が効かなくなった場合の保険として明示的にfalseにする案がある。今回は見送った。
- 差分の読取りは、認証、プラグイン、OTEL、app-serverの起動経路が中心である。120を超えるcrateすべての差分は読んでいない。
- 新たに加わったcrate（`lzma`、`xz`、`zstd`、`bzip2-rs`など）は、notice側の監査に回す。
- `libbz2`へのリンクは残っている。公開ヘッダがSDKにあるため問題になりにくいが、審査で指摘される可能性は残る。
- `docs/store-helper-data-flow-audit.md`など既存の監査文書は0.163.0の記述のままであり、更新していない。
- telemetryAudit、mcpStartupAudit、analyticsEventsClientAuditは`incomplete`のままである。
- 第三者noticeとライセンスの再生成、およびユーザーの再承認は別担当の作業である。
