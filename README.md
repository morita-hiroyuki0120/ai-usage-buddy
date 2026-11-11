# AI Usage Buddy

ChatGPTプラン（Plus / Pro / Business等）に含まれる **Codex の5時間枠・週間枠の残量** を、OpenAI公式のローカル連携手段（Codex app-server）から取得してメニューバーのキャラクターで表示するmacOSアプリ。

- メニューバーにはキャラクターのみ表示（数値・バーなし・モノクロ）
- クリックでポップオーバー: 残量%・プログレス・リセットまでの残り時間・リセット日時（ローカル時刻）・最終取得時刻
- **右クリックメニュー**: 今すぐ更新・アカウント切り替え・セットアップ再実行・設定・更新確認・終了（MenuBarExtraとキャラクターアニメーションは維持）
- **グローバルショートカット**（Carbon登録・設定で変更・無効化・初期値復元可能）:
  - `⌃⌥U` クイック利用状況ウインドウ（ポップオーバーと同じ表示内容）
  - `⌃⌥R` 手動更新
- **初回セットアップ（5段階）**: 歓迎 → 公式アカウント接続（任意） → 通知許可（任意） → ログイン時自動起動（明示確認） → 使い方。全ステップスキップ可能・未接続でも利用可能。既存ユーザーには表示されず、設定と右クリックメニューから再実行できる
- **エラー表示の分類**: 認証が必要／公式Codex連携が見つからない／タイムアウト／サーバーエラー／不正な応答／プロセス終了／stale／その他。状況別の説明と再試行・設定への導線を表示。取得失敗中は前回値をstale表示で保持し、低残量通知を送らない
- 複数アカウント対応（公式OAuthログインフローで追加）
- 5時間枠／週間枠の表示リミットをアカウントごとに選択可能
- 低残量通知（しきい値2つ・5〜100%の5刻み・リセット枠ごとに1回だけ・stale/手動補正中/取得失敗中は送らない）
- **更新確認**（1日1回・設定でオフ可。署名・公証前はGitHub Releasesへの手動案内のみで自動インストールは行わない）
- 日本語／英語、ライト／ダークモード追従、Reduce Motion対応
- Dock非表示（LSUIElement）、SMAppServiceによるログイン時自動起動

## 要件

- macOS 13 Ventura以降 / Apple Silicon
- **ChatGPT公式macOSアプリ**（同梱の公式Codex CLIを使用するため）
  - バイナリパス: `/Applications/ChatGPT.app/Contents/Resources/codex`
  - 検証時バージョン: codex-cli 0.153.4
- 既定アカウントは `~/.codex` のChatGPTログイン（`codex login` またはChatGPTアプリでのログイン）を利用

## 公式連携の前提と制約

### 使用している公式インターフェース

ChatGPTアプリ同梱の `codex` バイナリを `app-server` モード（JSON-RPC 2.0 / stdio）で起動し、公式プロトコルの読み取り系メソッドのみを使用する。

| 用途 | 公式メソッド | 備考 |
|---|---|---|
| ハンドシェイク | `initialize` → `initialized` | clientInfoにアプリ名を通知 |
| アカウント識別情報 | `account/read` | email・planType |
| 5時間枠・週間枠・リセット時刻 | `account/rateLimits/read` | `primary`（5時間）・`secondary`（週間）、`usedPercent` と `resetsAt`（絶対時刻） |
| アカウント追加 | `account/login/start` | 公式OAuth URLをブラウザで開き `account/login/completed` 通知を待つ |
| アカウント削除 | `account/logout` | アプリ管理のCODEX_HOMEに対してのみ実行 |

プロトコル定義は公式バイナリ自身の `codex app-server generate-json-schema` が生成するスキーマに準拠している。

### 制約

- **app-serverプロトコルは実験的（experimental）** と公式に宣言されている。ChatGPTアプリの更新でcodexバイナリのバージョンが上がると、メソッド名・レスポンス形状が変わる可能性がある。その場合は `account/rateLimits/read` 等のレスポンス構造を公式スキーマ再生成して確認する必要がある。
- 複数アカウントは「CODEX_HOMEディレクトリの分離」で実現する（公式の環境変数）。公式アプリにアカウント切替UIがあるわけではないため、アカウント数だけapp-serverプロセスが起動する。
- レートリミット値はChatGPTプランのCodex利用枠であり、OpenAI APIのOrganization Usageとは別物（本アプリは後者を代替として使用しない）。
- 5時間枠・週間枠の割当はプラン種別（plus / pro / business等）によって異なり、公式レスポンスの `planType` で判別可能。

### やっていないこと（プライバシー設計）

- `~/.codex/auth.json` をアプリ側で読み書きしない（codexバイナリ自身が管理）
- Cookie・ブラウザセッション・DOMスクレイピング・画面解析を一切使用しない
- APIキー等の認証情報をソースコード・設定に保存しない（アプリ自身は認証情報を保持しない）
- 非公開Webエンドポイント・内部APIの逆解析を行わない
- 利用履歴グラフ・クラウド同期・独自analyticsなし。開発者のサーバーへの送信もない（利用枠の取得とログインのため、codexバイナリがOpenAIのサーバーと通信する）
- ログにはメールアドレス・トークンが出力されない（`LogRedactor` で強制、ユニットテストで検証）

## ビルドと実行（開発）

```bash
# テスト（要: 公式ツールチェーン → 下記「テスト環境」参照）
./scripts/run-tests.sh

# リリーススクリプトのモック回帰（署名・公証は実行しない）
bash ./scripts/test-release-scripts.sh

# Apple Silicon向けReleaseビルド + .appバンドル生成
./scripts/build-app.sh
# → build/AI Usage Buddy.app

# ローカルで起動
open "build/AI Usage Buddy.app"
```

`scripts/build-app.sh` は ad-hoc署名（`codesign --sign -`）を行う。これはローカル実行の安定化のためで、**配布用の正式署名ではない**（ad-hoc署名ビルドでは自動インストールが無効になる。下記「アップデート」参照）。

### 未署名アプリの起動手順

配布パッケージ（署名・公証なし）をダウンロードした場合の初回起動:

1. DMG内の `AI Usage Buddy.app` を `Applications` へドラッグ
2. Gatekeeperにブロックされた場合:
   - Finderで `AI Usage Buddy.app` を右クリック →「開く」→「開く」を再選択
   - またはターミナルで隔離属性を除去:
     ```bash
     xattr -dr com.apple.quarantine "/Applications/AI Usage Buddy.app"
     ```
3. 通知を利用する場合は通知権限を許可する（拒否した場合は設定画面からシステム設定へ誘導される）

## リリース設定（config/ReleaseConfig.xcconfig）

バージョン・GitHub所有者などのリリース設定は `config/ReleaseConfig.xcconfig` で一元管理する（**秘密情報は書かない**。所有者名・リポジトリ名・URL・バージョン番号のみ）。実運用ファイルが無い場合はテンプレート `config/ReleaseConfig.example.xcconfig` の値が使われる。

| キー | 内容 | 未設定の場合 |
|---|---|---|
| `APP_MARKETING_VERSION` | アプリバージョン（例: 1.0.0） | ビルドエラー |
| `APP_BUILD_NUMBER` | ビルド番号（リリースごとに+1） | ビルドエラー |
| `GITHUB_OWNER` | GitHub所有者名（現在: morita-hiroyuki0120） | **更新確認の通信を一切行わず**手動更新モード（設定画面に「更新の取得元（GitHub）が未設定」と表示） |
| `GITHUB_REPOSITORY` | リポジトリ名（現在: ai-usage-buddy） | 既定値（ai-usage-buddy）を使用 |
| `SPARKLE_APPCAST_URL` | Sparkle 2 用Appcast URL（後続作業） | 自動更新（自動インストール）には使われない |

設定の流れ: `build-app.sh` がこの値をInfo.plist（`CFBundleShortVersionString` / `CFBundleVersion` / `GitHubOwner` / `GitHubRepository` / `SparkleAppcastURL`）へ注入し、アプリは `ReleaseConfiguration.from()` で読み取る。GitHub所有者は **リポジトリ公開後** に設定する（未設定・`YOUR_GITHUB_OWNER` プレースホルダーはどちらも「未設定」として扱われ、通信しない）。

## リリースパッケージの作成

```bash
# .appをReleaseビルドし、zip + SHA-256 + リリースノートを作る
./scripts/package-release.sh
#   → build/release/AIUsageBuddy-<version>-<build>-arm64.zip
#   → build/release/SHA256SUMS.txt
#   → build/release/RELEASE_NOTES.txt（署名状態を明記）

# DMG（.app + Applicationsエイリアス + インストール案内）
./scripts/create-dmg.sh
#   → build/release/AIUsageBuddy-<version>-<build>-arm64.dmg

# Developer ID署名・公証・ステープル後は同じ.appを再利用して最終梱包
./scripts/package-release.sh --reuse-app
./scripts/create-dmg.sh --reuse-app

# 公証プロファイルの準備前は、別ディレクトリでローカル署名だけ行う
export AI_USAGE_BUDDY_RELEASE_DIR="$PWD/build/release-candidate-1.0.1-2"
./scripts/package-release.sh
./scripts/sign-and-notarize.sh.example --sign-only
```

- 通常の `package-release.sh` はApple Silicon arm64向けReleaseビルドを行う。`--reuse-app` は既存.appを再ビルド・再署名せずに梱包する
- `SHA256SUMS.txt` はその版で実在するZIPとDMGを梱包後の内容から集約する
- Developer ID等で署名済みの.appは通常ビルドで上書きしない。署名後は必ず `--reuse-app` を指定する
- `create-dmg.sh --reuse-app` は.appが無い場合に停止し、DMG完成後に既存DMGを置き換える
- `AI_USAGE_BUDDY_RELEASE_DIR` を指定すると別のリリース出力先を使える。`--sign-only` は公証を行わず、成果物にも未公証・未ステープルと明記する
- 成果物の検証: `cd build/release && shasum -a 256 -c SHA256SUMS.txt`
- 出力に現在の署名状態を**明示**する。正式署名・公証済みの表示には署名・ステープル・Gatekeeper検証がすべて必要
- ユーザー設定（`~/Library/Application Support/AIUsageBuddy/`）には触れない

## 署名・公証の手順（Apple Developer Program加入後）

実際の署名・公証はテンプレート `scripts/sign-and-notarize.sh.example` をコピーして使う（`scripts/sign-and-notarize.sh` はコミットしない）:

```bash
cp scripts/sign-and-notarize.sh.example scripts/sign-and-notarize.sh
chmod +x scripts/sign-and-notarize.sh

# 環境変数で署名情報を渡す（値はスクリプトにもREADMEにも書かない）
export AI_USAGE_BUDDY_SIGNING_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)"
export AI_USAGE_BUDDY_TEAM_ID="TEAMID"
export AI_USAGE_BUDDY_NOTARY_PROFILE="notary-profile-name"
export AI_USAGE_BUDDY_BUNDLE_ID="com.aiusagebuddy.app"

# 公証プロファイルをキーチェーンへ保存。続けて対話プロンプトへパスワードを入力する
xcrun notarytool store-credentials "notary-profile-name" --apple-id "you@example.com" --team-id "TEAMID"

./scripts/package-release.sh   # ad-hoc署名の.app + zipを用意
./scripts/sign-and-notarize.sh # Developer ID署名 → 公証Accepted確認 → ステープル → 最終zip/DMG
```

スクリプトの内容:

1. **環境変数の確認** — 1つでも不足していれば署名も公証も行わず、不足項目を表示して停止する
2. **証明書の確認** — Developer ID Applicationだけを受け付け、Team IDが指定値と一致しなければ停止する。Apple Development証明書は拒否する
3. **構造とBundle IDの確認** — 現在の単一実行ファイル構成を検証し、ネスト実行コードやBundle ID不一致で停止する
4. **署名** — Hardened Runtimeとsecure timestampを有効にする。一致する既存署名は再署名せず再利用する
5. **公証** — `notarytool submit --wait` の結果が `Accepted` の場合だけ続行する
6. **ステープル** — `stapler validate`・`spctl --assess`・署名検証を行う
7. **最終梱包** — 署名済み.appを再ビルドせずzip/DMGを作り、両方のSHA-256を最終状態から更新する

手順の全体像:

| 手順 | コマンド | 備考 |
|---|---|---|
| 1. 証明書 | Developer ID Application証明書をキーチェーンへインポート | Apple Developerサイトで発行 |
| 2. 公証プロファイル | `xcrun notarytool store-credentials` | パスワードは対話入力し、キーチェーンへ保存 |
| 3. ビルド | `./scripts/package-release.sh` | arm64 Release + ad-hoc署名の状態 |
| 4. 署名・公証 | `./scripts/sign-and-notarize.sh` | Developer ID + Hardened Runtime + timestamp。Accepted必須 |
| 5. ステープル・検証 | （同上スクリプト内） | stapler validate + spctl + codesign |
| 6. 最終パッケージ | （同上スクリプト内） | 既存.appを再利用してzip/DMGとSHA-256を生成 |

SMAppServiceによるログイン時自動起動は、正式署名済みで `/Applications` 等の安定した場所に配置した場合に最も確実に動作する。

### 秘密情報の扱い（必読）

- Apple ID、Team ID、Developer ID証明書、App Store Connect APIキー、EdDSA秘密鍵、パスワードを **コード・README・スクリプト・Git・xcconfigへ保存しない**
- 署名情報は環境変数で渡し、公証情報はキーチェーンプロファイル（`notarytool store-credentials`）を使う
- `config/ReleaseConfig.xcconfig` には所有者名などの公開情報だけを書く
- ログに認証情報が出ないことは `LogRedactor` とユニットテストで検証している

## GitHub Releases の設定方法

1. リポジトリをGitHubへ公開したら `config/ReleaseConfig.xcconfig` の `GITHUB_OWNER` に所有者名を設定する（このリポジトリでは `morita-hiroyuki0120` を設定済み）
2. バージョンを上げる: `APP_MARKETING_VERSION` を更新し `APP_BUILD_NUMBER` を+1
3. パッケージ作成: `./scripts/package-release.sh && ./scripts/create-dmg.sh`
4. GitHubでタグ `v<version>`（例: `v1.0.1`）を作成し、Releaseに以下を添付:
   - `AIUsageBuddy-<version>-<build>-arm64.zip`
   - `AIUsageBuddy-<version>-<build>-arm64.dmg`
   - `SHA256SUMS.txt`（検証用）
5. アプリの「更新を確認」は GitHub Releases API（`https://api.github.com/repos/morita-hiroyuki0120/ai-usage-buddy/releases/latest`）をHTTPSで参照する

**注意**: アプリの更新確認はタグ名をバージョンとして比較する（`v1.0.1` → `1.0.1`）。

## Sparkle 2 導入（後続作業・現在は未導入）

現在の更新機能は「GitHub Releases確認＋手動ダウンロード案内」（`UpdateProvider` 抽象化）。Sparkle 2 への置き換えは **Developer ID署名・公証が済んでから** の後続作業として分離している。

導入条件（すべて揃うまで自動インストールは有効化しない）:

- [ ] Developer ID署名 + Hardened Runtime + 公証済みビルドであること
- [ ] HTTPSのAppcast URLを `SPARKLE_APPCAST_URL` に設定（http://やプレースホルダーは拒否される）
- [ ] EdDSA署名鍵を生成し、**公開鍵のみ** をアプリへ埋め込む

導入手順の概要:

1. **EdDSA鍵生成**: Sparkle 2 の `generate_keys` ツールで鍵ペアを生成
   - 秘密鍵はキーチェーンへ保存され、**ログ出力・Git保存をしない**
   - 公開鍵（`SUPublicEDKey`）はInfo.plistへ
2. **SPM依存追加**: `Package.swift` に `https://github.com/sparkle-project/Sparkle` を追加
3. **実装**: `UpdateProviding` 準拠のSparkleプロバイダを追加し、`AutoUpdateEligibility.eligible` の場合のみ自動更新を有効化。更新前のユーザー確認（「後で」選択可）と1日1回の自動確認制御は現在の設計を維持
4. **Appcast生成**: `sparkle generate_appcast` で `appcast.xml`（EdDSA署名付き）を生成し、GitHub Pages等のHTTPSで配信
5. **手動更新確認**（設定画面・右クリックメニュー）は常時利用可能にする

未署名・ad-hoc署名ビルドでは `AutoUpdateEligibility` が `manualOnly` を返すため、Sparkle導入後も自動インストールは実行されない。

## アップデート（更新確認）

- **現在（署名・公証前）**: 設定の「アップデート」セクションと右クリックメニューの「更新を確認」で、GitHub Releases の最新版を **確認** し、新しいバージョンがあればリリースページへのリンクを表示する（手動ダウンロード案内のみ）。**自動インストールは行わない**
  - 自動確認は1日1回まで（設定でオフ可）。**手動の更新確認は自動確認オフでも常に動作する**
  - 更新の適用には必ずユーザー確認を経る設計（「後で」で先送り可能）
- **GitHub所有者の設定**（`config/ReleaseConfig.xcconfig` の `GITHUB_OWNER`）:
  - 未設定・`YOUR_GITHUB_OWNER` プレースホルダー → **通信を一切行わず**、設定画面に「更新の取得元（GitHub）が未設定」と表示（手動更新モード）
  - 設定済み → `https://api.github.com/repos/<owner>/<repo>/releases/latest` へHTTPS接続（タイムアウト15秒）
- **自動更新（自動インストール）が manualOnly（手動案内のみ）になる条件**（`AutoUpdateEligibility` が判定）:
  - `.app` バンドル外での実行（開発ビルド等）
  - 未署名、または署名情報を検査できないビルド
  - ad-hoc署名（TeamIdentifierが無い）— `build-app.sh` の成果物はこれに該当
  - Sparkle 2 導入前のため、**Developer ID署名済みでも現在は手動ダウンロード案内のみ**（`requestInstall` は `manualDownload` を返す）
- **将来（Developer ID署名・公証後）**: GitHub Releases + **Sparkle 2** への置き換えを想定した抽象化（`UpdateProvider` プロトコル）。手順は上記「Sparkle 2 導入（後続作業）」参照

## 設定ファイルのスキーマ

`settings.json` はスキーマバージョン管理（現在 v2）。v2で追加されたキー: `onboardingCompleted` / `onboardingVersion` / `showUsageShortcut` / `refreshShortcut` / `automaticUpdateChecksEnabled` / `schemaVersion`。
旧v1ファイルは欠落キーを既定値で補って読み込み、v2へ自動移行する（既存のしきい値・アカウント選択・言語などはそのまま保持される）。

## テスト環境（このリポジトリ特有の事情）

本環境には **Xcodeが未導入**（Command Line Toolsのみ）で、XCTest・swift-testingのいずれも利用できない。そのため:

- swift.org公式ツールチェーン 6.3.3（swift-testing同梱）を `~/Library/Developer/Toolchains/` に展開して使用（約4.6GB・sudo不要）
- セットアップ: `./scripts/setup-test-toolchain.sh`
- 実行: `./scripts/run-tests.sh`（内部でツールチェーンのswiftで `swift test` を実行）
- 削除: `rm -rf ~/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain`

テストは143件（状態判定・ヒステリシス・リセット日時・残り時間・stale処理・手動補正復帰・通知重複抑制・リセット後再送・複数アカウント・表示リミット保持・通知しきい値の即時更新と永続化（5〜100の5刻み正規化・旧設定の移行を含む）・日英切替・ライト/ダーク・Reduce Motion・ログ検閲・メニューバーアニメーション・初回セットアップ表示/スキップ/再実行・既存ユーザー移行・通知許可の要求タイミング・自動起動の明示確認・右クリックメニュー（ヒットテスト幾何を含む）・アカウント切り替え・ショートカット保存/復元/競合/解除・クイック表示（PopoverView共有）・手動更新・エラー分類・stale表示・失敗時の通知抑制・詳細情報の秘密情報除去・更新バージョン比較・24時間更新制御・自動更新オフ・ad-hoc版の自動インストール抑止・GitHub所有者未設定時の通信抑止・HTTPS以外・プレースホルダーURLの拒否・未署名バンドルのmanualOnly判定・手動確認の常時動作・リリース成果物の命名規則・SHA-256チェックサム・失敗理由の秘密情報除去）。ライブデータには依存せず `MockUsageProvider` を使用する。

## 公開前チェックリスト

リリース（GitHub Releases公開）の前に確認すること:

- [ ] `./scripts/run-tests.sh` — 全テスト合格
- [ ] `./scripts/build-app.sh` — 成功・警告ゼロ・`LSUIElement = true` と表示される
- [ ] `./scripts/package-release.sh` — zip + SHA256SUMS.txt生成。Developer IDなしならad-hoc/未署名と明示されている
- [ ] `./scripts/create-dmg.sh` — DMG生成（.app + Applicationsエイリアス + 案内）
- [ ] Developer ID署名後は `--reuse-app` で最終梱包し、通常ビルドで署名済み.appを上書きしていない
- [ ] `cd build/release && shasum -a 256 -c SHA256SUMS.txt` — チェックサム検証
- [ ] DMGをマウントして `.app` が起動する・Applicationsへドラッグできることを確認
- [ ] `config/ReleaseConfig.xcconfig` の `APP_MARKETING_VERSION` / `APP_BUILD_NUMBER` を更新した
- [ ] リポジトリ公開済みなら `GITHUB_OWNER` を設定した（未設定なら更新確認が無効＝手動モードであることをリリースノートに明記）
- [ ] Apple Developer Program加入済みならDeveloper ID Applicationで署名し、公証Accepted・ステープル・Gatekeeper検証を確認した
- [ ] 秘密情報（Apple ID・Team ID・証明書・EdDSA秘密鍵・パスワード）がコード・README・スクリプト・Gitに含まれていない
- [ ] GitHub Release に zip・DMG・SHA256SUMS.txt を添付し、タグ `v<version>` を打った

**このREADMEの記載は「署名・公証済み」を意味しない。** 各配布物の署名状態は `codesign -dv "AI Usage Buddy.app"` と `RELEASE_NOTES.txt` で確認すること。

## データの保存先

| データ | 場所 |
|---|---|
| 設定・アカウント・スナップショット | `~/Library/Application Support/AIUsageBuddy/` |
| 追加アカウントのCODEX_HOME | `~/Library/Application Support/AIUsageBuddy/Homes/<UUID>/` |
| 既定アカウントの認証 | `~/.codex/`（codex公式が管理・本アプリは読み書きしない） |

手動補正値・通知送信済みキーもスナップショットファイルに保存される。

## キャラクター画像の差し替え

初期状態ではキャラクターはSwiftUI描画（外部画像に依存しない）。差し替える場合:

1. 以下の名前でPNG（36×36pt以上推奨）を用意:
   `character-energetic.png` / `character-normal.png` / `character-tired.png` / `character-sleeping.png` / `character-unknown.png`
2. `Sources/AIUsageBuddy/Resources/` に置いて再ビルド
3. モノクロの単色デザイン推奨（テンプレート描画でメニューバーの明暗に自動追従する）

### アニメーションフレーム素材（任意）

メニューバーのキャラクターは既定でベクター描画による低負荷アニメーション（約4〜8fps、状態ごとのサイクル速度）で動く。
独自素材でアニメーションさせる場合は次の命名規則でフレームPNGを並べる:

```
character-energetic-frame-0.png
character-energetic-frame-1.png
character-energetic-frame-2.png
character-normal-frame-0.png
...
```

- `frame-0` から連続して存在する分だけフレームとして使われ、ループ再生される
- フレーム素材が1枚も無い状態で単一PNG（`character-<state>.png`）だけがある場合は **静止表示** になる
- `unknown` 状態、macOSの **Reduce Motion が有効な場合は常に静止フレーム** を表示する
- 状態が変わるとアニメーションはフレーム0からやり直す

## トラブルシュート

- **キャラクターが「接続が必要」のまま**: `~/.codex` にログインがない。`codex login`（PATHに無い場合は `/Applications/ChatGPT.app/Contents/Resources/codex login`）またはChatGPTアプリでログインしてから手動更新
- **データが古い（stale警告）**: ChatGPTアプリ同梱codexのバージョン変更でプロトコルが変わった可能性。ポップオーバーのエラー表示を確認
- **通知が来ない**: 通知権限を確認（設定画面に誘導が出る）。stale中・手動補正中・同一リセット枠で既に通知済みの場合は送らない仕様
