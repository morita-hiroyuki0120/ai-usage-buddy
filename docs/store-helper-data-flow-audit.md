# Store helperの限定データフロー監査

確認日：2026-10-23。状態：内部草稿、提出可否とApp Privacy回答は未確定。
対象は固定公開helper 0.163.0、commit `83086188ae0614bd882818ff1aa23f3194962012`と、現在のStore client設定である。
実認証情報、実保存ファイル、Keychain、通信観測には触れず、記載したURLへも接続していない。

## 起動と設定の前提

[固定manifest](../config/EmbeddedAppServer.json:3)はversion、commit、元artifact SHAを固定し、distributionStatusはnot-ready、telemetryとMCPの監査もincompleteのままである。
[起動policy](../Sources/AIUsageBuddy/Services/AppServerRuntimePolicy.swift:4)はkeyring、secret_auth_storage=false、plugins=false、analytics.enabled=false、OTELのlog/trace/metrics exporter各noneをCLIで指定し、listenはstdio://とする。
[環境分離](../Sources/AIUsageBuddy/Services/CodexProcessConfiguration.swift:53)はアカウント管理homeのHOME/CODEX_HOME、専用TMPDIR、固定PATHだけを子へ渡す。
これは設定上の根拠であり、最終Store archiveの実効設定の検証ではない。

[Swift client](../Sources/AIUsageBuddy/Services/CodexAppServerClient.swift:256)はinitializeにclientInfo.name/versionを渡し、initializedを通知する。
利用する要求はaccount/read、account/rateLimits/read、type=chatgptのaccount/login/start、account/logoutである（同file:341–372）。
このclient側のRPC範囲と、helper自身が起動する背景処理は分けて評価する。

## 初回25ファイルで確認できた処理とデータ

以下の表と停止条件の初回留保は、後述「補完8ファイルの確認結果」で確認できた範囲を更新する。

| 経路 | 固定source上の確認結果と留保 |
|---|---|
| constructorから背景モデル更新 | [lib.rs:986](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/lib.rs#L986)がMessageProcessorを生成し、[message_processor.rs:337–386](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/message_processor.rs#L337)がModelsManagerとModelCatalogを作り、ModelsRefreshWorkerをspawnする。[models_refresh_worker.rs:30–58](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/models_refresh_worker.rs#L30)は初回からOnlineで一覧を取得し、その後270秒ごとに反復する。model/list RPCを送らないことだけでは、このworkerを止められない。 |
| catalogからHTTP | [model_catalog.rs:32–44](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/model_catalog.rs#L32)はprovider要件を確認してModelsManager.list_modelsへ渡す。[manager.rs:545–594](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/models-manager/src/manager.rs#L545)は認証方式とdiscovery設定を確認し、Onlineならfetchへ進む。[同:675–678](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/models-manager/src/manager.rs#L675)の条件はCodex backend認証、command認証、対応API-key discoveryのいずれか。従って未ログイン時とログイン後で到達条件が変わる。 |
| モデル取得の送信内容 | [models_endpoint.rs:91–164](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/model-provider/src/models_endpoint.rs#L91)は認証を解決し、providerまたはmodel_catalog_urlからURLを構成、client_versionを渡してModelsClientで取得する。既定経路のpathは/models（同:45）。認証付きの取得とclient versionの受渡しを確認したが、正確な最終host、全query/header、認証refreshのHTTP先は下流未読。API-key時のCodex baseへの切替条件も同:113–119にある。固定hostだけに接続すると断定しない。 |
| 利用枠取得 | [account_processor.rs:1192–1232](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/account_processor.rs#L1192)はCodex backend認証を要求し、chatgpt_base_urlからBackendClientを作る。空paramsでも通常usage要求に加えて、exclude_reset_credit_detailsがfalseなら詳細reset-credit取得を並行する。Swift側が表示する残量だけがHTTP応答の全内容ではない。通常経路はget_rate_limits_with_reset_creditsで、補助処理のexact URLとparamsの既定値定義は今回の上限内で未監査。 |
| backendの識別情報 | [backend-client/client.rs:232–286](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/backend-client/src/client.rs#L232)はUser-Agentとauth providerを設定し、headerを追加する。ChatGPT-Account-IdやFedRAMPのheaderを設定する分岐もある。具体的なアカウント値やtokenは取得していない。providerが追加する全認証headerは未監査。戻り値には利用枠、reset credits、account ID等があり、[account_processor.rs:1284–1298](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/account_processor.rs#L1284)でRPCへ整形する。 |
| initializeと分析識別 | [initialize_processor.rs:130–132](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/initialize_processor.rs#L130)はclient名をoriginator、name/versionをUser-Agent suffixへ使い、同:185でtrack_initializeを呼ぶ。これはstdio内だけの識別値と、外部送信に使い得る識別値の橋渡しである。実送信の有無はanalytics/OTELの条件と別途判断する。 |
| loginとlogout | [account_processor.rs:645以降](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/account_processor.rs#L645)はChatGPTログインのserverを開始し、同:684/727でauth URLを取得して返す。[同:1047–1054](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/account_processor.rs#L1047)のlogoutはlogout_with_revokeへ委譲しMCP runtimeを無効化する。OAuth交換、refresh、revokeのexact endpointと全データは今回未読で、既存privacy inventoryの保存方式調査とも区別する。 |

## analyticsとOTELの停止条件

[AnalyticsEventsClient::new:314–327](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/analytics/src/client.rs#L314)はanalytics_enabled=Some(false)ならqueueを作らず、専用workerが生成されない構造である。
有効時の送信先文字列はbase_urlに/codex/analytics-events/eventsを付ける（同:152–155）。
app-serverは[lib.rs:706–710](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/lib.rs#L706)でconfig由来のclientを渡すが、変換関数analytics_events_client_from_configの実装は今回未読なので、Store overrideがその引数に反映されることの全経路を独立確認済みとはしない。

[OtelProvider::try_new:194–206](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/otel/src/provider.rs#L194)はlog、trace、metricsのすべてがnoneならproviderを作らず、global metrics bufferも停止する。
analytics.enabled=falseだけでcustom metricsまで止まるとは扱わず、Store側が3 exporterを明示noneにする根拠と対応づける。
providerを組み立てるcore/otel_init、設定reload、HTTP側の別telemetryは未監査であり、全telemetry停止を実証したものではない。

## extensionsとplugins/MCPの到達条件

[extensions.rs:67–121](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/extensions.rs#L67)はconstructorからMCP、plugins、web search、image generation等のcontributorを登録する。
登録だけをネットワーク接続や外部プロセス起動の証拠とは扱わない。
[thread_manager.rs:558–599](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/thread_manager.rs#L558)はPluginsManager、McpManager、条件付きcode-mode providerを保持し、[McpManager::new_with_extensions:122–132](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/mcp.rs#L122)自体はmanagerとcacheの保持である。
呼出先の内部初期化まで無作用と断定する監査ではない。

- pluginsの起動同期は[message_processor.rs:542–560](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/message_processor.rs#L542)からconfig.plugins_config_input()を通じて呼ばれる。[manager.rs:2824–2834](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core-plugins/src/manager.rs#L2824)はplugins_enabled=trueのブロックにcurated repo同期を置き、同:2901–2906のremote plugin cache処理もそのブロック内にある。falseならこの起動同期経路に進まない。
- plugin読込みも[同:821–824](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core-plugins/src/manager.rs#L821)でplugins_enabled=falseなら空の結果を返す。Storeはfeatures.plugins=falseを指定するが、Config.plugins_config_input()でのfield変換本体は未読なので、この接続の最終照合は残す。
- [plugin_contributor.rs:20–39](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/mcp/src/plugin_contributor.rs#L20)はthread/config/turn/MCPのcallbackを登録する。[ext/mcp/lib.rs:48–59](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/mcp/src/lib.rs#L48)のHostedApps contributorはFeature::Appsを別に判定する。plugins=falseを全MCP無効化と同一視できず、Storeの7 overrideにAppsやmcp_serversの全面停止指定はない。
- clientはthread/turn、plugin install、MCP list/call等を要求しない。ただし[message_processor.rs:813–827](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/message_processor.rs#L813)はinitialize後にworkspace routingとthread_processor.connection_initializedへ進む。MCP runtime接続、設定済み外部server、executor plugin、remote downloadの全下流を読み切っていないため、この限定RPC構成でのプロセス起動やdownloadが完全に到達不能とは判定しない。

## 補完8ファイルの確認結果

同じ固定commitの公開sourceを追加8ファイルに限定して確認した。
本節は初回の「未読」のうち、Config.plugins_config_input、analytics_events_client_from_config、OTEL組立て、利用枠paramsと直接HTTP読取りについて更新する。
実効設定や実通信を観測した結果ではない。

### pluginsとanalyticsの設定伝播

[Config.plugins_config_input:1767–1777](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/mod.rs#L1767)はfeatures.enabled(Feature::Plugins)をPluginsConfigInput::newの引数へ渡す。
前回確認したcore-plugins/src/manager.rs:174–195のconstructorがそのboolをplugins_enabledに保持するため、実効features.plugins=falseなら、既述のplugins_for_config:821–824と起動同期:2824–2834の停止条件に反映される。
この経路について「field変換未読」という初回の留保は解消したが、Appsや通常の設定済みMCPまで無効にする根拠にはならない。

[Config組立て:4619](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/mod.rs#L4619)はcfg.analytics.enabledをanalytics_enabledへ転記する。
[analytics_utils.rs:7–15](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/analytics_utils.rs#L7)はその値をAnalyticsEventsClient::newへそのまま渡す。
既述のanalytics/src/client.rs:314–327とつなぐと、実効analytics.enabled=falseはSome(false)となり、専用analytics queueとそのworkerを作らない。
この設定伝播はsource上で確認できた。
同意flagだけで、別のOTEL collector、通常API呼出し、model catalog更新まで止まるとは扱わない。

### OTELのnone指定とreload

[Config組立て:4405](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/mod.rs#L4405)はcfg.otelを設定resolverへ渡す。
[config/otel.rs:9–39](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/otel.rs#L9)は指定されたexporter、trace_exporter、metrics_exporterを保持する。
省略時のmetrics既定値はStatsigだが、明示noneをStatsigに置き換えない。
[otel_init.rs:22–24](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/otel_init.rs#L22)のKind::NoneはOtelExporter::Noneへ変換され、同:68–97からOtelProvider::try_newへ渡る。
従ってStoreの3つの明示noneが実効設定なら、前回のprovider.rs:194–206の「全exporter無効ならproviderなし」に到達する。
同:70–79はanalytics無効時にStatsig metricsを止める一方、明示OTLPはこの同意flagで止めないため、3 exporter指定を別に確認する理由もsourceと一致する。

[otel_reloader.rs:55–86](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/otel_reloader.rs#L55)は認証変更を受けると最新Configを読み、同じbuild_providerを再実行する。
reloadにも同じ変換規則が使われることを確認したが、managed/cloud設定とCLI overrideの全優先順位、全reload後の実効値は未検証である。
3 noneによるこのproviderの停止を全通信抑止の証明に広げない。

### 空paramsから通常usageとreset-credit詳細のGET

[GetAccountRateLimitsParams:311–324](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/account.rs#L311)はDefaultをderiveし、2つのboolへserde(default)を付ける。
supports_luna_reserveとexclude_reset_credit_detailsは、いずれも省略時falseである。
現在のSwift clientの空paramsはこの既定値を使うため、既述account_processor.rs:1216–1232では通常usageと詳細reset-credit lookupを並行する。
Luna Reserve用headerは追加されない。

baseはBackendClientに渡されたchatgpt_base_urlであり、既読backend-client/src/client.rs:208–220で末尾slashの除去等を行う。
同:149–155ではbaseに/backend-apiを含む場合ChatGptApi、それ以外はCodexApiのpath形式を選ぶ。
実際の設定hostを読んでいないので、以下は最終hostを決め打ちしないpath規則として記載する。

| 呼出し | methodとbaseからのpath | この関数内で追加するrequest payload |
|---|---|---|
| 通常usage | GET。ChatGptApiは/wham/usage、CodexApiは/api/codex/usage | JSON body、queryの追加なし。共通headersを付ける。supports_luna_reserve=falseなのでx-openai-codex-luna-reserve: 1も付けない。 |
| 詳細reset credits | GET。ChatGptApiは/wham/rate-limit-reset-credits、CodexApiは/api/codex/rate-limit-reset-credits | JSON body、queryの追加なし。共通headersを付ける。 |

根拠は[rate_limit_resets.rs:23–38](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/backend-client/src/client/rate_limit_resets.rs#L23)、[同:69–86](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/backend-client/src/client/rate_limit_resets.rs#L69)、[同:124–139](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/backend-client/src/client/rate_limit_resets.rs#L124)。
認証headerとUser-Agent等は既読Client.headersを使うが、共通HTTP transportによる全headers、再試行、redirect処理まで今回監査したわけではない。

[account_processor/rate_limit_resets.rs:3–42](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/account_processor/rate_limit_resets.rs#L3)の詳細取得には5秒timeoutがあり、HTTP失敗、timeout、parse失敗ではNoneを返す。
前回のaccount_processor.rs:1260以降はusage応答のsummaryへfallbackするため、画面に残量が出たことだけでは詳細GETの成功を証明しない。
source上の別処理であるconsumeはPOSTのJSON（redeem_request_id、任意credit_id）を使うが、今回示したaccount/rateLimits/readのGET分岐では呼ばない（backend-client側同file:89–121）。
実際のcredit消費、HTTP要求、アカウント操作は行っていない。

### 補完の範囲

追加で確認したファイルは次の8件のみ。

1. core/src/config/mod.rs
2. app-server/src/otel_reloader.rs
3. core/src/otel_init.rs
4. backend-client/src/client/rate_limit_resets.rs
5. app-server-protocol/src/protocol/v2/account.rs
6. app-server/src/analytics_utils.rs
7. app-server/src/request_processors/account_processor/rate_limit_resets.rs
8. core/src/config/otel.rs

初回既読の呼出元とconstructorは必要箇所だけ再参照した。
OAuth、実通信、利用者データ、Keychain、portal、ネットワーク取得、build、testは実施していない。
編集は本docだけであり、manifest、既存草稿、not-ready、checkpointは変更していない。


## Store pollの最小化変更

上記の空paramsは変更前の監査記録である。
固定protocol v2/account.rs:313のcamelCase指定を照合し、Swift clientのStore channelだけaccount/rateLimits/readへexcludeResetCreditDetails=trueを送るよう変更した。
Direct channelは空paramsを維持し、UsageProviderの公開interface、通常usageの残量とreset日時のdecode、security overrideは変更していない。
source上では前述の補助GETを省く条件になるが、実helperやライブHTTPでの検証は未実施である。
実requestのparamsと通常応答の保持を確認する専用ローカルfixture testを追加した。
通常Direct build設定とStore flag付きの両方で、同じ1 test/2 channel casesが成功した。
StoreのcamelCase bool true、Directの空params、両枠の残量とreset絶対日時のdecodeをfixtureで確認し、handleのexit 0を回収した。実行結果はcheckpointに記録済みで、ライブHTTPは未検証である。

## MCPとEnvironmentManagerの補完15ファイル

2026-10-24に同じ固定commitの公開sourceだけを15関連ファイルまで確認し、ここで有限調査を終了した。
前提は本Store clientのinitialize/initialized、account/read、login/logout、quotaというRPC範囲であり、thread/turn/tool設定RPCを送らない構成である。
このRPC範囲と、helper自身の起動時処理やbackground workerは区別する。
管理HOME/CODEX_HOME/workingの分離とplugins=falseは既述のsource設定上の前提で、実際の管理homeやconfigは読んでいない。

| 経路 | 確認できた処理と到達条件 |
|---|---|
| McpManagerのconstructor | [core/mcp.rs:122–132](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/mcp.rs#L122)はplugins manager、extension registry、cacheを保持する。本体内に接続開始の呼出しはない。保持先の全constructorが無作用だという意味ではない。 |
| initialize後のthread側処理 | [thread_processor.rs:3736–3743](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L3736)はThreadStateManagerへ委譲し、[thread_state.rs:387–397](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/thread_state.rs#L387)はlive_connectionsへconnection IDとcapabilitiesを登録する。この2関数にはMCP runtime生成、接続、program起動はない。workspace routingなどinitialize全体の別分岐の無通信は保証しない。 |
| runtimeを作る場合 | [runtime.rs:302–351](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-mcp/src/runtime.rs#L302)のMcpRuntime::newはemptyを作った後replace→publish→McpConnectionSet::newへ進む。従って「MCP runtimeのnewも保持だけ」とは扱わない。thread/sessionからこのruntime構築に入る全入口は今回の範囲では閉じ切っていない。 |
| 設定serverの接続 | [connection_manager.rs:290–332](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-mcp/src/connection_manager.rs#L290)はrequired/enabledとstartup policyを判断し、enabledなserverを列挙する。同:796–798にはstartupのtokio::spawn/join_set.spawnがある。runtimeが構築され、有効serverが渡された場合には実接続のtaskへ進み得る。 |
| 外部programとHTTP transport | [rmcp_client.rs:1222–1268](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-mcp/src/rmcp_client.rs#L1222)はStdioのcommand/args/env/cwdを取り、localまたはexecutor launcherを選んでnew_stdio_client_with_protocol_modeへ渡す。StreamableHttpは別match分岐である。これはtransport構築時の外部実行/接続経路であって、現在のclientのinitializeだけがここを呼ぶという証拠ではない。launcher下流の実spawn、HTTP接続、download実装は今回未読。 |
| EnvironmentManager起動 | [app-server/lib.rs:619–633](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/lib.rs#L619)はRPC受付処理とは別にEnvironmentManager::from_envまたはfrom_codex_homeをawaitする。[environment.rs:191–237](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/exec-server/src/environment.rs#L191)のprepare段階はsource snapshotを作り、from_*はbuildまで進む。[environment_bootstrap.rs:41–59](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/exec-server/src/environment_bootstrap.rs#L41)のbuildはsnapshotまたはNoise設定からmanagerを構築する。 |
| 設定remote環境のbackground接続 | [environment.rs:286–360](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/exec-server/src/environment.rs#L286)はsnapshotからremote環境を作り、有効なsnapshotの環境ごとにstart_connectingを呼ぶ。したがって将来remote環境設定が存在すれば、thread/turn RPCを呼ばないことだけでremote executor接続を止められない。Noise経路の全接続条件、remote clientのtransport、再接続、bootstrap/download下流は今回未読。 |
| 環境変数providerの既定分岐 | [environment_provider.rs:66–108](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/exec-server/src/environment_provider.rs#L66)はCODEX_EXEC_SERVER_URLを参照し、remote URLがあればremote entryを作る。remote URLなし、disabledでもない場合はremote entries空、include_local=true、default localとなる。これはDefaultEnvironmentProviderの分岐の確認であり、Storeが常にこの分岐を通るという保証ではない。 |

### 今回の構成に対する限定判断

constructorのmanager保持やinitialize後の接続情報登録を、MCP serverの起動と混同しない。
現在の限定RPC構成からMCP外部server接続や外部program起動へ進む直接の呼出し鎖は、今回確認した初期化箇所では見つかっていない。
ただしruntimeの構築条件を全入口で排除したわけではないため、「MCPが一切起動しない」とは判定しない。
plugins=falseについては既述のplugin起動同期と読込みの停止条件が有効であり、任意のmcp_serversやAppsとは別に扱う。

EnvironmentManagerは起動時にbuildまで進み、設定remote環境をbackground接続する構造である。
この経路はclientのthread/turn RPCとは独立している。
Store側は既述のallowlist環境にCODEX_EXEC_SERVER_URLを渡さないが、environments.toml読込み、Noise設定、managed設定の全優先順位を今回読み切っていない。
空の管理homeという想定を、既存または将来の全configの安全性へ拡張しない。

[Config:4283](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/mod.rs#L4283)はcfg.mcp_serversを制約付き設定へ渡す。
この15ファイル調査時点ではConfigTomlのserde/defaultは未読だった。後述の既定値追補で基本field省略時の空mapを確認したが、runtime全体のserver空までは保証しない。
CLI overrideによる全面無効化案も、公式keyの定義と使用箇所が揃う範囲まで確認できていないため、新しい設定案やcode変更は行わない。

追加downloadについては、今回確認したmanager保持と接続情報登録の関数内に取得処理はない。
外部programが動けばそのprogram自身が取得する可能性、executor接続のbootstrap、plugin/Appsなど別分岐からの取得は未監査である。
「追加binary downloadが全経路で到達不能」とは扱わない。
既知の270秒ごとのmodel catalog更新と、認証/usageのHTTPは本補完とは別に残る。

### 読取り範囲と残る不確実性

対象15ファイルはapp-server/src/{lib,thread_state}.rs、app-server/src/request_processors/thread_processor.rs、core/src/{mcp,thread_manager}.rs、core/src/config/mod.rs、core/src/session/mcp.rs、codex-mcp/src/{runtime,connection_manager,rmcp_client}.rs、codex-mcp/src/connection_manager/startup.rs、exec-server/src/{environment,environment_bootstrap,environment_provider,environment_config}.rsである。
関連シンボルと該当箇所だけの確認であり、15ファイルの全行を監査したものではない。
environment configファイルの探索やsession側の呼出し探索だけでは下流が確定しなかった箇所は、上記の未確認に含める。

MCP runtimeの全生成入口、接続launcherの実装、remote bootstrap/downloadは未確認として残す。基本MCP fieldの省略値は後述の追補で確認済みに更新する。
これは本有限調査の境界であり、無制限の追加auditを新たな必須条件にしない。
提出構成の判断に必要な具体的な残りを担当者が選ぶ。
実helper起動、任意program実行、source build、test、実network、実config/ログ/認証情報の読取は行っていない。
編集対象は本docとcheckpoint末尾だけで、code、security override、既存成果物、not-readyは変更していない。


## 基本既定値と環境provider入力由来の追補

2026-10-24、前回停止時にcheckpointだけへ保存した3ファイルの根拠を再照合し、本節へ反映した。
追加の入力経路確認は5ファイルに限定した（指定上限6以内）。
固定commitは引き続き`83086188ae0614bd882818ff1aa23f3194962012`で、実利用者の設定や環境変数の値は読んでいない。

### 基本設定のMCP server省略値

[ConfigToml:164](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/config/src/config_toml.rs#L164)はDefaultをderiveし、[同:295–299](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/config/src/config_toml.rs#L295)のmcp_serversはserde(default)付きHashMapである。
従ってこの基本設定fieldを省略した場合の値は空mapである。
[Config組立て:4283–4284](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/mod.rs#L4283)はcfg.mcp_serversをconstrain_mcp_serversへ渡し、[同:2285–2297](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/mod.rs#L2285)はrequirementsなしならそのmapを保持、ありならfilterする。
前節の「ConfigTomlのserde/default未確認」は、この基本fieldの範囲で解消した。
この事実を、managed/cloud設定の合成、extensionやAppsによるruntime寄与後も必ずserver空、という保証に広げない。

### DefaultEnvironmentProviderの既定値

[environment_provider.rs:118–123](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/exec-server/src/environment_provider.rs#L118)はURLなしと空文字を(None,false)、明示noneを(None,true)へ正規化する。
同:77–108はURLなし・disabledでない場合、remote entriesを空、include_local=true、defaultをlocalにする。
これは指定providerの既定分岐であり、provider自体の選択条件を含む結論ではない。

### 本AppServerからの実呼出しと入力元

| 段階 | 固定sourceの根拠と本Store構成への限定適用 |
|---|---|
| standalone入口 | [main.rs:30–77](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/main.rs#L30)のAppServerArgsはconfig overrides、code-mode host設定、listen、session source、auth、strict config、remote-control等を受け、同:119–129でrun_main_with_transport_optionsへ渡す。この構造体にexecutorのremote_url/exec_server_urlを直接渡すfieldはない。remote-controlはexecutor URLと別の機能である。flatten先の全引数を包括監査したものではない。 |
| local runtime options | [lib.rs:531–536](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/lib.rs#L531)はfind_codex_homeとarg0の実行file pathからExecServerRuntimeOptions::from_optional_pathsを作る。[runtime_options.rs:10–24、28–53](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/exec-server/src/runtime_options.rs#L10)は自己実行file、sandbox helper、policy等を保持し、ここにはexecutor remote URL fieldがない。これをremote URLのCLI入力と取り違えない。 |
| manager入口の選択 | [lib.rs:537](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/lib.rs#L537)のloader_overrides.ignore_user_configにより、同:624–633はfrom_envまたはfrom_codex_homeを選択する。main.rs:94–100は通常LoaderOverridesのdefaultを使うが、その型のdefaultと全managed設定経路は今回未読なので、ここは値に応じた条件分岐として示す。 |
| Noise入力が先行 | [environment.rs:196–225](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/exec-server/src/environment.rs#L196)は両prepare入口でnoise_environment_config_from_envを先に判定する。同:639–677はNoise registry URL、environment ID、auth token、任意account IDという名前の環境変数から構成する。主要3値が全部なければNone、全部あればNoise設定、不完全ならerrorになる。これは公開コードの変数名と分岐だけの確認で、値は取得していない。既知のStore環境allowlistはこれらを渡さない。 |
| home内の別設定 | Noiseなしのfrom_codex_home経路は[environment_toml.rs:234–245](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/exec-server/src/environment_toml.rs#L234)でCODEX_HOME/environments.tomlを選ぶ。[同:330–335](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/exec-server/src/environment_toml.rs#L330)の読込みがNotFoundならNoneとなり、DefaultEnvironmentProvider::from_envへfallbackする。存在時はTomlEnvironmentProviderを構築し、parse失敗等を「設定なし」と扱わない。今回その実fileは読んでいない。 |
| 設定fileからのremote options | [同:39–56](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/exec-server/src/environment_toml.rs#L39)にurl、program、args、env、cwd、timeout等のfieldがある。[同:157–181](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/exec-server/src/environment_toml.rs#L157)はurlあり/programなしの分岐でRemoteEnvironmentOptions.exec_server_urlを設定しtransportへ変換する。従ってremote optionsの由来はCLI/envだけに限定できず、このfile経路がある。programを持つ別分岐の全実行下流は既述の未監査を維持する。 |
| legacy環境変数fallback | [environment_provider.rs:72–85](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/exec-server/src/environment_provider.rs#L72)はCODEX_EXEC_SERVER_URLを読み、remote URLがあればremote entryを作る。既知のStore子process環境allowlistはこの変数も渡さない。上記fileがなくNoise入力もないという条件が成立すれば、既述のlocal既定分岐につながる。 |
| Option引数を渡す別caller | [environment.rs:174–187](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/exec-server/src/environment.rs#L174)のcreate_for_testsはexec_server_url: Optionを受けてDefaultEnvironmentProvider::newへ渡すが、これはtest用callerである。productionのAppServerがこのOption引数をそのままCLIから受け取る経路とは扱わない。 |

### 今回解消した範囲と留保

基本ConfigTomlのMCP空map、DefaultEnvironmentProviderのURLなしlocal分岐、AppServerからNoise/file/envへ進むprovider選択の呼出しと入力元を確認した。
Storeの固定stdio起動と7 overrideだけを根拠に、environments.tomlや別provider入口まで存在しないとはしない。
隔離homeが将来も空という想定を安全性の証明に使わず、managed/cloud設定や別caller、dynamic environment追加、全bootstrap/download下流は未監査のまま残す。
既述のmodel catalogやaccount関連通信も継続して別評価する。
全追加通信停止、全外部実行不能、実動作保証、配布可能性の認定は行わない。

再照合した3ファイルはconfig/src/config_toml.rs、core/src/config/mod.rs、exec-server/src/environment_provider.rs。
追加5ファイルはapp-server/src/main.rs、app-server/src/lib.rs、exec-server/src/environment.rs、exec-server/src/environment_toml.rs、exec-server/src/runtime_options.rs。
code、CLI override、security設定は変更せず、実config、環境dump、認証情報、runtime、通信、buildに触れていない。


## 未監査の境界と次の判断

MCP runtimeとconnection manager、EnvironmentManager初期化は15ファイル補完と既定値追補で一部確認済みに更新した。基本MCP fieldの省略値とproviderのNoise/file/env入力元は確認済み。残る具体範囲はruntimeの全生成入口、launcherとbootstrap/download、設定合成後のMCP寄与、OAuth/refresh/revokeのHTTP実装等である。
Configのplugins/analytics変換、OTELのnone指定とreload呼出し、利用枠paramsの既定値、usage/reset-creditの直接GET実装は補完節で確認済みに更新した。
Models endpointの全headersと既定base設定、constructorでspawnするTurnCostWorker（message_processor.rs:387–388）、gateway通知、remote control、skills watcher、共通HTTP transport、managed/cloud設定とCLIの全優先順位、実効reload値等は未監査または未検証である。
今回の証拠から言えるのは、モデル更新という具体的な追加通信経路が存在し、pluginsとtelemetryに限定された停止条件があることまでである。
外部送信先、識別子、利用目的、保持期間、第三者処理を確定するには残る下流の確認が必要で、「全通信ゼロ」「データ収集なし」、法的適合、Apple許可、App Privacyの確定回答は作成しない。

## 確認した25ファイル

探索用のパス一覧とシンボル検索に続き、以下の25ファイルの関連箇所に読取りを限定した。
固定sourceの保存rootは`build/dependency-audit/codex-0.163.0/source-audit-83086188/checkout/codex-83086188ae0614bd882818ff1aa23f3194962012/`、以下のRust pathはそのcodex-rsからの相対pathである。

| 件数 | ファイル |
|---|---|
| 5 | docs/store-privacy-data-inventory.md、config/EmbeddedAppServer.json、Sources/AIUsageBuddy/Services/{AppServerRuntimePolicy,CodexProcessConfiguration,CodexAppServerClient}.swift |
| 7 | app-server/src/{lib,message_processor,models_refresh_worker,model_catalog,extensions}.rs、app-server/src/request_processors/{account_processor,initialize_processor}.rs |
| 2 | models-manager/src/manager.rs、model-provider/src/models_endpoint.rs |
| 2 | ext/mcp/src/{lib,plugin_contributor}.rs |
| 3 | analytics/src/{lib,client}.rs、otel/src/provider.rs |
| 3 | core/src/{thread_manager,mcp}.rs、core-plugins/src/manager.rs |
| 3 | codex-mcp/src/lib.rs、backend-client/src/{lib,client}.rs |

この文書だけを新規作成し、code、config、他のdocs、checkpointは変更していない。
追加build、test、helper起動、認証、ネットワーク観測、公開は行っていない。
