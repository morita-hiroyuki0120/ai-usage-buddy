# Store archiveのoffline包装

この経路は未承認草稿の誤配布を防ぐための準備実装であり、現在の提出物を作るものではない。
`config/EmbeddedAppServer.json`の`distributionStatus`は`not-ready`のまま維持し、本番preflightを拒否する。
既存のDirect配布とStoreRuntimeValidationの各modeは変更しない。

## 承認済み入力の契約

将来のレビュー後に、専用directoryへ次の入力を用意する。
生成器の`GENERATION-COMPLETE.json`や`draft-not-approved`は承認receiptの代用にならない。
このtaskでは実資料の承認、status変更、承認receiptの発行を行っていない。

| 入力 | 照合 |
|---|---|
| 固定helper tar.gz | version 0.167.2、tag rust-v0.167.2、commit `ce21072c90d32c40af7a55b60b2fb35c84a43a6a`、SHA-256 `6d42b6a34bbe05d083e66b0dec65e23db77b2c87a82435882acfda043aab1e06` |
| `approval.json` | 呼出側が指定するSHA-256、config全文hash、sourceとartifactのpin、明示的review status |
| appのMIT本文 | 現在のroot LICENSEとのhash一致 |
| helper root LICENSEとNOTICE | 保存済み固定tag本文のhash一致 |
| 依存notices本文とsource入手案内 | receiptに記録したsizeとhashの一致。実際の適用判断と公開可能な入手案内はレビュー担当の責任範囲 |

receiptのschemaは次の構造を持つ。
これは説明用の構造であり、承認済み入力ではない。

```text
schemaVersion: 1
status: approved-for-store-packaging
configSHA256: レビュー対象EmbeddedAppServer.jsonのSHA-256
artifactSHA256: 上記の固定tar SHA-256
sourceCommit: 上記の固定commit
artifact: {path: 入力directory内の相対path, size: 正のbyte数, sha256: SHA-256}
payloads:
  App-LICENSE: {path, size, sha256}
  LICENSE: {path, size, sha256}
  NOTICE: {path, size, sha256}
  THIRD-PARTY-NOTICES.txt: {path, size, sha256}
  SOURCE-AVAILABILITY.txt: {path, size, sha256}
review: {status: approved, reference: 人間のレビュー記録, approvedAt: 承認日時}
signing: {team: 9HYDLV4RY2, bundleID: com.aiusagebuddy.app.store,
          profileSpecifier: 明示設定又は空文字, profileUUID: 明示設定又は空文字}
```

`SOURCE-AVAILABILITY.txt`は公開向けの実際の案内本文をhashで結び付ける。
別担当が準備中の`build/source-availability-draft-20261023/SOURCE-AVAILABILITY.draft.txt`は未承認であり、この構造の追加をもってsource入手案内の完成や公開済みと扱わない。
本文hashの一致は、ライセンス義務の履行や法的適合を自動判定するものではない。

## Xcodeとの接続

本番時に指定する公開metadataは`AI_USAGE_BUDDY_STORE_INPUTS`（symlinkを含まない絶対path）と`AI_USAGE_BUDDY_STORE_APPROVAL_SHA256`である。
XcodeのRelease install/archive actionでは、TeamとBID、Apple Distributionの展開済みidentity名とfingerprint、署名有効設定、Hardened Runtime、Store専用compile flagを検査する。
profileはXcode設定値とreceiptの文字列一致だけを確認し、両方空のworkflowも許容する。
ローカルの証明書一覧、秘密鍵、profile本文は読まず、証明書の有効性とprofile適合性の最終判定はXcodeに委ねる。

1. Preflightで`not-ready`、未承認receipt、変更されたpayload、symlink、逸脱pathを拒否する。
2. 新規DerivedDataの`StorePackaging`へhelperを排他的に展開する。既存directoryは再利用せず、途中失敗後も上書きしない。
3. コピーしたhelperだけへad-hoc署名pattern（専用identifier、runtime、sandboxとinheritだけ）を設定する。元tarと元binaryは変更しない。
4. archive専用CopyFilesのCodeSignOnCopyがhelperを`Contents/Helpers/codex-app-server`へ配置し、appのidentityで再署名する。
5. 別のarchive専用CopyFilesが5つの本文とhash receiptを`Contents/Resources/StoreNotices`へ一度コピーする。
6. 最終app署名の前にhelperのstrict署名、Apple Distribution、Team、identifier、runtime、厳密な2 entitlementと本文hashを検査する。その後Xcodeが親appを署名する。

targetはappの1本だけで`SKIP_INSTALL=NO`を明示し、helperをarchiveのトップへ別installするtargetは作らない。
通常のDebug/Release `build`ではarchive包装を実行せず、helperなしのcompile確認専用を維持する。
Build Script Sandboxの設定は緩和せず、phaseに公開入力と生成出力を宣言した。
ネットワーク取得、helper実行、`--deep`署名、runtimeでのdownloadは実装していない。

## 検証と未完了範囲

fixtureは標準Pythonだけで実行し、実helper、codesign、認証、profileを使わない。

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/StorePackaging/tests -v
bash -n scripts/prepare-store-archive.sh
plutil -lint Store/AIUsageBuddy.xcodeproj/project.pbxproj
```

将来の実archiveとexport後には、それぞれのappを`bash scripts/prepare-store-archive.sh --verify-app --app <絶対path>`で検査する。
同じ承認済み入力directoryとapproval hashを環境変数で渡し、appとhelperの署名、identifier、Team、runtime、entitlements、本文hashを確認する。
親appの必須3権限はtrueを厳密に確認し、identity entitlementは対象TeamとBIDへの完全一致だけを許容する。
Keychain access groupも`9HYDLV4RY2.com.aiusagebuddy.app.store`だけに限定し、wildcard、追加files権限、get-task-allow=trueは拒否する。
helperはsandboxとinheritの2権限だけを許容し、親appの許容リストは適用しない。
正式profileで実際に付与されるentitlementsは未検証であり、今後のarchive/export結果と照合する必要がある。
この検査も実行せず、今回のunsigned compileを「archive署名とexportの成功」の証明にしない。
署名によってhelperのbytesは変化するため、元tarのhashと最終helperの署名検証は別の検査である。
将来の実行時にはarchiveの構造、本体とnested codeの署名、export後の同一条件を確認する必要がある。

署名patternとCodeSignOnCopyは[Apple公式のexternal tool手順](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app)に基づく（2026-10-23本文確認）。
公式例はContents/MacOSを使うが、このappでは既存resolver契約のContents/Helpersを維持しており、実archive/exportによる検証は未実施である。
