# Codex app-server helper候補の監査

監査対象は、OpenAI Codexの`rust-v0.163.0`から配布されたApple Silicon向けstandalone app-serverである。

確認日は2026-10-18であり、配布物を実行、再署名、アプリへ同梱していない。

配布元とartifact hash、元Developer ID署名は確認できたが、Store向けhelperとしての最終署名、entitlement設計、実動作が未検証のため採用可否は未判定である。

## 配布物の確認

[公式release API](https://api.github.com/repos/openai/codex/releases/tags/rust-v0.163.0)は、asset名を`codex-app-server-aarch64-apple-darwin.tar.gz`、サイズを76,413,371 bytes、SHA-256を`8165de84cc8e436d46d5e52fe6b68de053ba729c543e6310a1bd41e881cf4c37`としている。

保存したAPI応答とtarballは`build/dependency-audit/codex-0.163.0/`に置き、取得物のサイズとSHA-256をAPI値に照合した。

gzip検査は成功し、tarには相対パスの通常ファイル`codex-app-server-aarch64-apple-darwin`が1点だけ含まれていた。

tar一覧に絶対パス、`..`を含む経路、symlinkはなかったため、そのbinaryだけを同じ監査フォルダーへ展開した。

展開したbinaryはMach-O arm64で、`LC_BUILD_VERSION`のminimum OSはmacOS 11.0、SDKは15.5だった。

`otool -L`が示す直接リンク先は`/System/Library/Frameworks`または`/usr/lib`内のmacOS標準frameworkとdylibだった。

この結果はMach-Oの直接リンク先に限り、実行時にロードする任意のコードやネットワーク動作を証明しない。

## 署名とentitlement

正規の権限昇格付き`codesign -dv --verbose=4`はDeveloper ID Application署名、TeamIdentifier `2DC432GLL2`、timestamp、runtimeフラグを表示した。

通常権限で行った前回のstrict検証は失敗したが、正規の権限昇格付き`codesign --verify --strict --verbose=4`は`valid on disk`および`satisfies its Designated Requirement`を返した。

通常権限でのentitlement読み取りはinvalid blobと警告したが、正規の権限昇格付き再確認ではXMLを読み取れ、`allow-jit`と`allow-unsigned-executable-memory`が含まれていた。

元署名から読み取ったentitlementには`com.apple.security.inherit`が含まれていなかったが、Store bundleへ埋め込み署名した最終構成は別途検証が必要である。

通常権限での失敗原因は特定していないため、監査の元署名判定には昇格付きの検証結果を採用する。

元の署名が有効であることは確認できたが、Store appへの埋め込み後に適用する署名とentitlement、sandbox継承、notarizationは未検証である。

再署名やentitlementの付け直しはこの監査では行っていない。

## 起動引数と実行範囲

[tag固定のapp-server manifest](https://github.com/openai/codex/blob/rust-v0.163.0/codex-rs/app-server/Cargo.toml#L1-L10)はbinary名を`codex-app-server`としている。

[tag固定のentrypoint](https://github.com/openai/codex/blob/rust-v0.163.0/codex-rs/app-server/src/main.rs#L32-L76)では`--listen`の既定値が`stdio://`、`--session-source`の既定値が`vscode`である。

このstandalone binary自体がapp-serverのCLI entrypointであり、現在のAI Usage Buddyクライアントが外部CLIへ渡す`app-server` subcommandをそのまま付けてよいとは確認できない。

[entrypointのruntime設定](https://github.com/openai/codex/blob/rust-v0.163.0/codex-rs/app-server/src/main.rs#L103-L129)は`AppServerRuntimeOptions::default()`を使い、analytics既定値として`false`を渡す。

[runtime optionsの既定値](https://github.com/openai/codex/blob/rust-v0.163.0/codex-rs/app-server/src/lib.rs#L468-L492)では`PluginStartupTasks::Start`が選ばれ、起動処理はplugin startupをskipしない。

plugin startupの起動経路は下記で限定追跡したが、設定されたMCP serverの起動条件とpluginが実行できる処理の範囲は未調査である。

manifestには`codex-mcp`、`codex-mcp-extension`、`codex-plugin`、`codex-core-plugins`、`codex-otel`などが依存として並ぶが、これだけで各機能が常時起動すると判断することもできない。

analytics既定値`false`は確認できたが、設定ファイルや他のtelemetry経路を含む通信全体は監査していない。

「telemetryを一切送信しない」または「MCP/pluginを実行しない」と説明できる根拠は、現時点で揃っていない。

## 起動時のplugin・MCP・telemetryの限定追跡

公式GitHub APIで確認されたtag provenanceは、`ref/tags/rust-v0.163.0`、annotated tag object `129b8ec7ee6f4511557a4856279f529025c25af4`、commit `83086188ae0614bd882818ff1aa23f3194962012`の順である。

起動経路はcommit固定の8ファイルで追跡し、公開設定の既定値とSerde表現を確かめるため、同じcommitから4ファイルを追加確認した。

[app-server entrypoint](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/main.rs#L64-L125)は通常のruntime optionsを既定値で作り、既定値は`PluginStartupTasks::Start`である。

plugin startupをskipする`--disable-plugin-startup-tasks-for-tests`はdebug build限定の隠しtest hookであり、release CLIの利用者向け停止optionではない。

[共通CLI override実装](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/utils/cli/src/config_override.rs#L15-L36)は汎用の`-c`／`--config key=value`を受け取り、以下では固定commitのschemaとfeature registryでkey名と既定値を照合する。

[app-server初期化](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/lib.rs#L1004-L1010)はstartup taskを有効な場合に`MessageProcessor`へ渡し、[processor構築](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/message_processor.rs#L542-L560)がRPC処理とは別にplugin managerを呼び出す。

したがって、利用RPCを`initialize`、account read/login、`account/rateLimits/read`だけに絞っても、このstartup経路自体は止まらない。

[plugin manager](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core-plugins/src/manager.rs#L2824-L2946)は内部値`plugins_enabled`がtrueなら、marketplace更新worker、remote plugin/cache warmup、featured plugin ID warmupを開始し、remote catalogやinstalled bundleの更新を条件付きでscheduleする。

同じ内部gateがtrueでremote global catalogがactiveでなく、Git source policyが許可すれば、[curated marketplace同期](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core-plugins/src/manager.rs#L752-L773)を別threadで開始する。

[同期先](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core-plugins/src/startup_sync.rs#L23-L38)は`https://github.com/openai/plugins.git`であり、Git経路の失敗時には[GitHub APIと`https://chatgpt.com/backend-api/plugins/export/curated`を使うHTTP fallback](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core-plugins/src/startup_sync.rs#L105-L125)を試す。

このため、新規`CODEX_HOME`や環境変数・RPC allowlistだけでは、条件成立時のplugin関連外部通信を抑止できない。

[feature registry](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/features/src/lib.rs#L1619-L1624)では`Feature::Plugins`の`default_enabled`が`true`であり、[生成済みpublic schema](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/config.schema.json)は`features.plugins`をbooleanとして定義する。

現行[Config Reference](https://learn.chatgpt.com/docs/config-file/config-reference)もこのkeyを掲載するが、説明はmanaged user向けのavailability pinである。

そのため、managed policyなどの上書きがない新規`CODEX_HOME`ではplugin startup gateが既定で有効になる。

`-c features.plugins=false`または`[features]`の`plugins = false`を指定すると、[Configからplugin managerへ値を渡す処理](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/mod.rs#L1766-L1776)の`plugins_enabled`がfalseになり、[startup task群の外側gate](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core-plugins/src/manager.rs#L2824-L2832)でplugin起動時warmupをskipする。

この設定はplugin機能のgateであり、別途設定された`mcp_servers`の起動を含む全MCP経路まで無効化すると確認したわけではない。

追跡したstartup pathはplugin catalog/cache同期を示すものであり、MCP server processの自動起動までは示していない。

他のapp-server経路におけるMCP起動条件は今回調べていないため、「MCPは起動しない」とは結論しない。

[Serde型](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/config/src/types.rs#L243-L252)とschemaは`analytics.enabled`をoptional booleanとして定義し、`false`はOpenAI analyticsを無効にするが、custom OTLP metrics exporterは別設定に残す。

fixed `rust-v0.163.0`では`analytics.enabled=false`が無効化するのはmetrics exporterが`Statsig`の場合だけであり、明示したOTLP metrics exporterには適用されない。

一方、[現行Advanced Configuration](https://learn.chatgpt.com/docs/config-file/config-advanced)はCodex CLIで`analytics.enabled=false`がcustom OTLP metrics exporterも無効化すると説明しており、これは固定commitの型コメントと実装に反するためversion差として扱う。

[Serde enum](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/config/src/types.rs#L596-L647)は`OtelExporterKind`に`#[serde(rename_all = "kebab-case")]`を指定し、`None`を`"none"`として受け取る。

固定commitでOTelの各exportを止める設定値は`otel.exporter = "none"`、`otel.trace_exporter = "none"`、`otel.metrics_exporter = "none"`である。

[resolver](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/otel.rs#L13-L21)の既定値はlog exporter `none`、trace exporter `none`、metrics exporter `statsig`であり、app-serverの`default_analytics_enabled = false`は未指定時のStatsig metricsを抑止する。

app-serverはprovider構築後にprocess-start/SQLite telemetry hookを呼び、[analytics events client](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/lib.rs#L706-L707)も生成するため、`default_analytics_enabled = false`だけで全telemetryや全送信を否定できない。

三つの`otel.*_exporter`を`"none"`にする設定はOTel logs、traces、metrics exporterを停止するが、OpenAI account/login/quota通信など別のnetwork requestまで止める設定ではない。

analytics events clientの実送信条件とpayload、MCP serverの全起動経路、exporter以外のtelemetry経路は未調査のため、「全通信がない」とは結論しない。

## ライセンスと配布条件

[crate manifest](https://github.com/openai/codex/blob/rust-v0.163.0/codex-rs/app-server/Cargo.toml#L1-L10)は`license.workspace = true`を指定し、[workspace metadata](https://github.com/openai/codex/blob/rust-v0.163.0/codex-rs/Cargo.toml#L161-L168)は`Apache-2.0`を指定している。

tag rootの[LICENSE](https://github.com/openai/codex/blob/rust-v0.163.0/LICENSE)はApache License 2.0であり、[NOTICE](https://github.com/openai/codex/blob/rust-v0.163.0/NOTICE)はOpenAI Codexの著作権表示と、Ratatui由来コードのMIT attributionを記載する。

配布tarにはbinaryのみが含まれ、LICENSEとNOTICEは含まれていなかった。

tag rootのApache-2.0 LICENSEはlicense copyとNOTICE attributionに関する条件を記載するが、この監査ではbinaryと推移依存に適用されるnotice一式を確定していない。

全推移依存のlicenseとnoticeは調べておらず、依存全体のnoticeが揃っているとは確認できない。

コードのlicenseは、OpenAI accountの認証、quota照会、サービス利用条件、Mac App Storeでの配布可否を決めないため、これらは別の確認事項として残る。

この記述は調査結果の整理であり、再配布許諾や法令に関する法律判断ではない。

## 採用前に残る確認

- [ ] standalone binaryの正しい起動引数、stdio protocol、session sourceをアプリ実装へ反映し、protocolと終了処理を検証する。
- [ ] Mac App SandboxとHardened Runtimeに必要なhelper署名、entitlement継承、sandbox内の起動と終了を検証する。
- [ ] 埋め込みとStore向け署名後にstrict検証し、macOS 11.0対応はminimum OS metadataだけでなく実機または対応環境で検証する。
- [ ] human loginのcallback方式、再起動後のaccount分離、logout後のcleanupをStore buildで検証する。
- [ ] MCP serverとpluginの起動条件、設定の保存先、外部通信を確認し、telemetry設定も実装から追跡する。
- [ ] 推移依存のlicenseとnoticeを収集し、必要な表示と再配布条件を確認する。
- [ ] archive、TestFlight、App Store Connect upload、review、privacy disclosure、公開privacy URL、説明文、screenshotsを別途整える。

現行の配布計画は無料で、広告と課金を含めず、support窓口は[GitHub Issues](https://github.com/morita-hiroyuki0120/ai-usage-buddy/issues)とする。

公開privacy URLは未作成であり、アプリはOpenAIへの認証とaccount quota照会を行うため、「一切データを送信しない」または「申告対象データがない」とは記載しない。

## 監査ファイル

- Release API応答：`build/dependency-audit/codex-0.163.0/release-api.json`
- 公式tarball：`build/dependency-audit/codex-0.163.0/codex-app-server-aarch64-apple-darwin.tar.gz`
- 展開binary：`build/dependency-audit/codex-0.163.0/codex-app-server-aarch64-apple-darwin`
- tag固定source：`build/dependency-audit/codex-0.163.0/source-app-server/`
- 起動経路監査source：`build/dependency-audit/codex-0.163.0/source-cli/`、`source-core/`、`source-core-config/`、`source-core-plugins/`
- 公開設定追跡source：`build/dependency-audit/codex-0.163.0/source-features/lib.rs`、`source-core-config/schema.json`、`source-core-config/otel.rs`、`source-config/types.rs`
- tag root license類：`build/dependency-audit/codex-0.163.0/source-licenses/`
