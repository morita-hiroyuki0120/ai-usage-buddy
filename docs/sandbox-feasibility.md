# App Sandbox feasibility probe

実施日: 2026-10-16

## 結論

既存のCodex CLIは、Developer ID署名された最小AppKitアプリのApp Sandbox内から起動できた。LaunchServicesで起動したProbeから`codex --version`とapp-serverの`initialize`、未ログイン状態の`account/read`・`account/rateLimits/read`を実測した。

これはSandbox下で外部CLIのプロセス起動とRPC初期化が技術的に可能というPoCであり、App Store審査適合、CLI再配布許諾、ログイン済み利用枠取得、複数ログインアカウント対応を示すものではない。

## Probeと署名

- Bundle ID: `com.aiusagebuddy.app.sandboxprobe`
- 成果物: `build/sandbox-probe/SandboxProbe.app`
- 最終Entitlementsは`com.apple.security.app-sandbox=true`、`com.apple.security.network.client=true`、`com.apple.security.network.server=true`。後者は次のloopback bind/listen比較で必要性を実測した後に追加した。
- Developer ID Application署名、Team ID `9HYDLV4RY2`、secure timestamp、hardened runtimeを確認。`codesign --verify --strict`成功。
- 既存Codex CLIはコピー・変更・再署名せず、`/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`を実行対象にした。

## 実測

通常controlはProbe外から、空の一時`HOME`と`CODEX_HOME`、一時cwdとTMPDIRを同じパターンで個別指定して実行した。対象CLIと`--version`引数はSandbox側と同一。controlはexit 0、`codex-cli 0.162.0-alpha.17.2`。

環境差は次のとおり。両方とも認証情報を引き継がず、PATHは同じ固定値。通常controlのapp-server RPCは実行していない。

| 設定 | 通常control | Sandbox Probe |
|---|---|---|
| 実行対象 | 同じ公式`codex` wrapper | 同じ公式`codex` wrapper |
| `HOME` / `CODEX_HOME` | `/private/tmp`配下の新規home（両変数に同じ値） | App Sandbox container内のAccount-A/Bごとの新規home（両変数に同じ値） |
| cwd | 同じ一時control rootの`working` | 各home専用の`Account-A/Working`・`Account-B/Working` |
| `TMPDIR` | control rootの`tmp` | 各account directoryの`Temporary` |
| `PATH` | `/usr/bin:/bin:/usr/sbin:/sbin` | `/usr/bin:/bin:/usr/sbin:/sbin` |
| 実行した処理 | `codex --version` | `codex --version`、app-server RPC |

最終測定はLaunchServicesから絶対`.app`パスを指定して起動し、`open -n -W`はexit 0。更新後のレポートrun IDは`12003ab6-68da-4e4b-8efe-c8a51f4f7a06`。最初に試した相対`.app`パスの`open`失敗は起動前のパス解決失敗であり、Sandbox拒否の証拠として扱っていない。

| 観測 | 結果 |
|---|---|
| codesign entitlements / strict verification | Sandboxとnetwork.clientあり、strict検証成功 |
| LaunchServices起動 | 成功（exit 0） |
| 実行中アプリのhome | 専用container配下 |
| Account-Aの`HOME` / `CODEX_HOME` / cwd | すべて専用container配下 |
| 外部fixture | ホストcontrolでは読取可能、Sandbox Probeでは`EPERM`拒否 |
| Codex CLI `--version` | 成功（exit 0）。これはversion確認だけを意味する |
| Account-A / Account-B | 別々の新規container内`CODEX_HOME`を使用 |
| 両homeの`initialize` | 成功 |
| 両homeの`account/read` | `unauthenticated` |
| 両homeの`account/rateLimits/read` | `authentication_required`、RPC error code `-32600` |
| app-server cleanup | 両方terminate後exit 0。残存PIDなし |

ProbeはRPC本文、標準出力・標準エラー、email、account ID、auth URL、tokenを保存しない。記録はphase/status、終了コード、Sandbox fixtureのerrno classなどに限定した。`auth.json`等の認証データは読み取り・コピー・表示していない。ログイン操作も行っていない。

## ログインUIの最小Probe

独立した`--login`モードを追加した。起動時にウィンドウを表示するだけで、app-serverもログインも開始しない。ユーザーが「検証用アカウントでログイン」を押した場合に限り、専用container内の固定Account-A `CODEX_HOME`でCodex app-serverを起動し、既存クライアントと同じ公式`account/login/start`の`type=chatgpt`のみを送る。返されたHTTPS `authUrl`はメモリ内で`NSWorkspace`に渡すだけで、URLやlogin IDをUI・ログ・レポートに出さない。完了通知もlogin IDをメモリ内で照合し、結果状態だけを表示する。5分の待機期限と`account/login/cancel`によるキャンセルを備える。

「残量を確認」はAccount-Aの`account/read`を確認し、`account`オブジェクトがある場合は`requiresOpenaiAuth=true`だけを根拠に未ログインと分類せず、`account/rateLimits/read`の結果で認証要否を判断する。表示対象は5時間・週間残量だけで、email、account ID、plan、RPC本文は出さない。Account-Bは別の空containerパスに分離し、このUIからログインさせない。

ログイン開始の失敗表示はこれまで原因を一律化していたため、固定診断コードを追加した。RPC error/authentication-required、timeout、応答切断、不正RPC応答、結果schema不正、不正auth URLを別々に分類し、画面にはコードのみ、container内の`Diagnostics` JSONにもstage/codeと必要時の数値system codeのみを保存する。RPC本文、エラー文字列、URL、login IDは記録しない。今回の既存失敗試行にはこの診断コードが保存されていないため、その過去分の細分類はできない。

callback用listenerのentitlement要否は、署名済みProbeをLaunchServicesから起動し、IPv4 loopback `127.0.0.1`・ephemeral port（port 0）でsocket/bind/listenだけを行う専用テストで比較した。`network.server`なしでは`bind`が`EPERM`（`loopback_bind_permission_denied`）、同じ条件で追加後は`loopback_listen_passed`。固定portを使わないため既存port競合を原因とする結果ではなく、外向き接続・ブラウザ・OAuth callback・認証成功を試験したものでもない。Appleは`com.apple.security.network.server`を受信接続/listen許可として説明している（[entitlement reference](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server)）。

ログインUIの実装確認ではウィンドウ表示とユーザーによる開始失敗まで確認した。人間の失敗試行後に今回の作業で再ログイン操作はしていない。loopback listenの許可は確認したが、app-serverのbrowser callbackが実際に成功するか、ログイン後の残量取得、再起動後のAccount-A復元、Account-Bとの切替混線は未検証である。`network.server`追加はこの独立Probeの標準entitlementだけで、本番アプリには適用していない。

更新版UIをLaunchServicesから開き、Account-A専用の説明と「検証用アカウントでログイン」「残量を確認」「終了」のボタン表示を確認した。UIは開いたまま引き渡す。ログイン開始・残量取得のどちらも押しておらず、追加のapp-server processやブラウザOAuthは開始していない。

Codex App Serverの公開ブラウザログイン手順と`account/login/completed`通知は[公式ドキュメント](https://learn.chatgpt.com/docs/app-server)に沿う。公式資料がlocal/open-source利用とcommercial/hosted利用を区別することと、App Storeへの無料配布が再配布・認証利用の包括的許諾を意味しないことは別論点として扱う。App Store審査適合やCodex CLIの再配布許諾は、このローカルProbeから判断しない。

## 未検証と判断上の注意

- rate-limits取得が認証要求で拒否されたのは新規homeが未ログインだからであり、Sandbox非対応とは判定しない。ログイン済み状態でのrate取得は未検証。
- Account-A/Bは独立した空のhomeであり、別々の実アカウントではない。アカウント切替時の混線防止、ログイン状態の再起動復元、複数アカウント完全合格は未検証。
- 起動対象CLIをアプリへ同梱していない。このPoCは技術的なプロセス/RPC可否のみ。Mac App Storeの自己完結性・helper要件・審査、Codex CLIの再配布ライセンスは別途確認が必要。
- このProbeから本体アプリ、配布候補、ログイン状態への変更は行っていない。

## 再現手順

リポジトリrootから実行する。署名はローカルKeychain上のDeveloper ID identityを使う。

```sh
app='build/sandbox-probe/SandboxProbe.app'
mkdir -p "$app/Contents/MacOS"
cp Tools/SandboxProbe/Info.plist "$app/Contents/Info.plist"
swiftc -parse-as-library -O -framework AppKit \
  -o "$app/Contents/MacOS/SandboxProbe" \
  Tools/SandboxProbe/SandboxProbe.swift Tools/SandboxProbe/SandboxLoginUI.swift
codesign --force \
  --sign 'Developer ID Application: PUREROAST&BREW, LIMITED LIABILITY COMPANY (9HYDLV4RY2)' \
  --identifier com.aiusagebuddy.app.sandboxprobe --options runtime --timestamp \
  --entitlements Tools/SandboxProbe/SandboxProbe.entitlements --strict "$app"
codesign --verify --strict --verbose=2 "$app"
"$app/Contents/MacOS/SandboxProbe" --self-test
```

自己テストはPOSIX pipeから遅延して届く2断片のJSON Lines応答を本番と同じ`poll/read` helperで改行まで読み切ること、account応答の分類、重複ログイン操作ロック、キャンセル応答判定、ログイン開始RPC/timeout/切断/不正応答と結果schema/URLの固定分類を確認する。最終実行は`passed`。`--listener-self-test --diagnostic-id <UUID>`はLaunchServices経由でloopback listener比較を実行し、秘匿値を含まないJSONをcontainer内`Diagnostics`へ書く。`--login`モードは次でLaunchServicesから開く。認証を試す場合も、ユーザーがウィンドウ上のログインボタンを明示的に押すまでブラウザは開かない。

```sh
open -n -a "$(pwd)/build/sandbox-probe/SandboxProbe.app" --args --login
```

通常controlは一時ディレクトリの`home`を`HOME`と`CODEX_HOME`に、同じ一時領域の`working`をcwdに指定し、同じCLIの`--version`を実行する。Sandbox測定は次のようにLaunchServicesから起動する。実行ごとにUUIDが異なる新規container homeを使う。

```sh
run_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
open -n -W -a "$(pwd)/build/sandbox-probe/SandboxProbe.app" --args \
  --run-id "$run_id" \
  --codex-binary '/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex' \
  --fixture "$(pwd)/Tools/SandboxProbe/outside-fixture.txt"
```

秘匿化済みレポートは`~/Library/Containers/com.aiusagebuddy.app.sandboxprobe/Data/Library/Application Support/AIUsageBuddySandboxProbe/Runs/<run-id>/Report.json`に作られる。
