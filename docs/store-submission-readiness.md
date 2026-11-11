# Store提出用archiveとexportの準備状況

更新日：2026-10-24。
archive用の包装経路は実装済みだが、検証はfixtureと通常のunsigned compileまでである。
[固定manifest](../config/EmbeddedAppServer.json)は`distributionStatus: not-ready`のままであり、提出可能とは判定しない。
一般項目は[app-store-readiness](app-store-readiness.md)、実行履歴と人間の確認記録はローカル作業記録（公開対象外）を参照する。

## 実装と検証の到達点

| 項目 | 現物で確認できる状態と証拠の限界 |
|---|---|
| 本番候補と署名設定 | [project](../Store/AIUsageBuddy.xcodeproj/project.pbxproj)はBID `com.aiusagebuddy.app.store`、Team `9HYDLV4RY2`、候補version/build 1.0/2（2026-11-11に1.0.1から変更）。app targetは1本で`SKIP_INSTALL=NO`。ReleaseはManual、distribution identity変数は空、profile UUID/specifierの明示はない。Explicit App ID登録済み。最新human承認に基づき親CUAがApp Store Connect recordを作成しApple ID `6826562310`を確認した。macOS、AI Usage Buddy、主言語日本語、会社PUREROAST&BREW, LIMITED LIABILITY COMPANY、BID一致、SKU `AIUsageBuddy-macOS`、access制限なし。既定Store version 1.0とproject候補は2026-11-11に1.0へ整合済み（実archiveでの確認は未実施）。 |
| archive包装 | [shell入口](../scripts/prepare-store-archive.sh)と[Python実装](../Tools/StorePackaging/prepare.py)が存在する。Release install/archive時に固定0.163.0のsource commitと元tar hash、config全文hash、明示的review status、payloadのsizeとhashを検査する。現行not-readyは拒否する。承認済みreceiptを発行した証拠はない。 |
| helperと本文の配置 | projectにarchive専用CopyFilesを登録済み。コピーしたhelperにad-hoc署名patternを設定し、CodeSignOnCopyで`Contents/Helpers/codex-app-server`へ配置する構成。appのLICENSE、helper root LICENSEとNOTICE、依存notices、source案内は`Contents/Resources/StoreNotices`へ配置する。元artifactを変更せず、helperをarchiveトップへ別installしない。実際の本番同梱は未検証。 |
| entitlementsと署名順 | helperはsandboxとinheritの2権限完全一致。親はsandboxとnetwork client/serverの必須3権限に加え、Team/BIDへ束縛したidentity entitlementだけを許容する。wildcard、追加files権限、get-task-allow=trueは拒否する実装。helperを検証後にXcodeが親を署名する構成であり、profileを適用した最終内外署名の検証は未実施。[包装仕様](../Tools/StorePackaging/README.md) |
| fixtureと通常build | 包装fixture 18件成功とpreflightのnot-ready拒否は過去checkpointに記録済み。最新のサポート導線検証ではDirectとStoreflagがそれぞれ全196 tests/18 suites成功、focused各2件成功。native unsigned Releaseも1回成功（exit 0）、warning 1件。[保存log](../build/store-support-check.xtYHVI/)とcheckpointを照合した。通常buildにはhelperとStoreNotices本文がなく、archive/exportの成功を意味しない。 |
| ローカルUI | XCwI1p/keyringtestで公式ログイン後の5時間枠と週間枠の残量およびリセット時刻表示を人が確認。再起動後に再ログイン不要、対象削除後の再起動で非表示との人間の報告がある。正式Store署名版、Keychain実項目の削除、remote失効の検証とは区別する。 |
| 証明書とexport | Apple DistributionとMac Installer Distributionの作成確認はcheckpointの履歴にある。親CUAは既存Distribution証明書1本を選びStore profile生成とダウンロードに成功したと報告。許可された公開metadataだけをCMSから抽出しTeam/BIDを照合した（下記）。インストール、projectへの配布identity/profile割当、export設定、実archive/exportは未実施。 |

最新native保存物は`build/store-support-check.xtYHVI/DerivedData/Build/Products/Release/AI Usage Buddy.app`である。
記録上のRelease warningは`Metadata extraction skipped, no AppIntents.framework dependency found`である。
この文書更新ではテストやbuildを再実行せず、実装、保存物、実行履歴を照合した。
既存Direct配布とDeveloper IDローカル検証経路は本番archive経路と分け、timestamp=noneの検証版を提出用とは扱わない。

Store profileは`AI Usage Buddy Mac App Store`、portal profile ID `MFL8B9QQAD`である。
親CUAは既存profileのStatus Active、macOS、expiry 2027-10-23、BID一致を確認し、再生成せずダウンロードした。
保存先は`/Users/hiroyuki/Downloads/AI_Usage_Buddy_Mac_App_Store.provisionprofile`。
今回の限定CMS読取りではUUID `12df9150-9fe1-4e9b-a2a1-ba399280778b`、TeamIdentifier `9HYDLV4RY2`、Platform `OSX`、`com.apple.application-identifier=9HYDLV4RY2.com.aiusagebuddy.app.store`、`com.apple.developer.team-identifier=9HYDLV4RY2`を確認した。
ExpirationDateは2027-10-22 21:09:59 UTC（2027-10-23 06:09:59 JST）である。
許可項目の`application-identifier`と`get-task-allow`は存在せず、後者を明示falseと同一視しない。
CMS decode成功は最終署名やインストール成功の証明ではない。
DeveloperCertificatesの内容とCMS全文は表示も保存もしていない。

## noticesとsource案内の現在地

最新のapp-server単独草稿は[validation](../build/third-party-notices-app-server-draft-20261024/validation.json)と[生成完了marker](../build/third-party-notices-app-server-draft-20261024/GENERATION-COMPLETE.json)で確認した。
記録は生成1回exit 0、generator fixture 27件、907 component、491 texts、全文候補なし6件、1684 evidence refsである。
全文候補なしはobjc2-foundation、debugserver-types、display_container、eventsource-stream、fxhash、io_teeである。
validationには出力と資料参照のhash/size検証、旧草稿15ファイルと入力10ファイルの不変確認が記録されている。
今回は保存記録を照合し、全資料のhash計算は再実行していない。
907件の適用義務レビューは未完で、SDK留保とversion不一致も残り、`draft-not-approved/not-ready`である。
source graph由来の保守的候補集合であり、実binary含有や法的適合の証明ではない。
本文収集の進展を適用義務レビューや配布承認の完了とは扱わない。

2026-11-11の追記：残件の再調査結果と承認用の質問は[判断シート](store-license-decision-sheet.md)にまとめた。
標準条項併記後の草稿は907 components、492 texts、標準条項6件、全文候補なし6件である（上の491 textsは併記前の草稿）。
display_containerの版差は、同日commitの照合により解消候補が見つかったが、補完manifestへの反映と承認は未実施である。
source案内は[改訂草稿](../build/source-availability-draft-20261111/SOURCE-AVAILABILITY.draft.txt)を新規に作成し、2026-10-23の取得結果と2026-11-11のheader確認を反映した。
既存の公開候補txtは変更していない。
nucleoのsymlink入りarchiveは、URL案内にとどめる方針を判断シートで提案している。
いずれも承認前であり、`draft-not-approved`と`distributionStatus: not-ready`は変わらない。

旧release-unionの[草稿3 validation](../build/third-party-notices-draft-20261023-3/validation.json)と[生成完了marker](../build/third-party-notices-draft-20261023-3/GENERATION-COMPLETE.json)は保持している。
同草稿の936 component、507 texts、全文候補なし8件、1729 refs、当時のgenerator fixture 19件という履歴を、app-server単独scopeの数値と混同しない。

source案内は[計画](store-source-availability-plan.md)と[公開候補txt](../build/source-availability-draft-20261023/SOURCE-AVAILABILITY.draft.txt)が存在し、未準備ではなく「草稿作成と限定取得確認まで完了、正式本文は未承認、未公開」である。
[取得結果JSON](../build/source-availability-check-20261023.IN0yac/availability-results.json)には11 GET、全HTTP 200、通常metadata確認済み12対象を記録している。
前回更新では保存取得物11件の実sizeとSHA-256が同JSONに一致することを再照合した。
今回、そのhash再計算、ネットワーク再確認、archive内容の再監査はしていない。
10 crateは安全検査済みだが、nucleo固定commit archiveはmatcher/LICENSEのsymlinkによりblockedのままである。
リンクを辿らないroot LICENSEと2 manifestの確認成功を、archive全体の受入成功へ拡張しない。

公開候補txtは初回草稿のままで、後続の取得確認結果を反映した正式本文のレビューが必要である。
MPL-2.0の12候補とself_cell等の選択ライセンスについて、同梱対象への適用、表示、source入手方法を確認する。
上流URLの時点確認、ローカルcacheの存在、本文hash一致は、将来の可用性や法的適合を保証しない。
自社source hostは未作成だが、全sourceの自社再ホストを一律の追加条件にはしない。
本番包装は承認済みSOURCE-AVAILABILITY本文もhashで結び付ける設計であり、現在のdraftを採用していない。

過去の「archive工程なし」「helper CopyFilesなし」「最新noticesは草稿2」「source案内未準備」は、現物と上記記録により更新した。
草稿2を含む旧union草稿と過去checkpointは当時の記録として残し、現行scopeの配布承認の証拠には用いない。

## 次に必要な承認と実作業

- [ ] app-server単独scopeの残る6件の全文候補、SDK留保、版差、選択ライセンス、必要NOTICE、source入手案内の扱いを決める。正式noticesとsource案内の本文を人間が承認し、対象hashを束縛するreceiptを用意する。根拠未了のままreadyへ変更しない。
- [ ] 登録済みExplicit App ID、生成済みprofile、承認後作成済みApp Store Connect recordを前提に署名workflowを確定する。profileのインストールと割当、既存証明書の割当、export方法とinstaller署名は未実施。Store version 1.0とproject候補は2026-11-11に1.0/2へ整合済み。無料価格等は未設定、自動releaseは既定表示のみで変更も保存もしていない。今回これらを決定しない。
- [ ] 実archive/exportの実行承認後、新規出力で包装経路を検証する。archiveとexport後の両appについて、helperの元artifact対応、自己完結性、本文同梱、内外の署名、Team/BID、entitlements、archiveトップがappのみであることを確認する。
- [ ] [固定source監査](store-helper-data-flow-audit.md)の確認済み範囲と留保を踏まえ、提出対象runtimeの通信とmodel catalog取得、plugin/MCP制限を判断する。監査は一部完了しているが実通信と全下流は未確認である。最終署名構成でログイン、quota、再起動、削除を検証し、ローカルUI報告や設定引数だけで全通信抑制やremote失効を断言しない。
- [ ] [privacy公開計画](privacy-publication-plan.md)に沿って本文掲載の人間承認と公開操作の別途承認を得る。実URL、アプリ内導線、第三者helperとWebホストを区別したApp Privacy回答を整える。StoreのGitHub更新確認無効をDirect版の挙動と混同しない。
- [ ] [審査アクセス相談](store-review-access-plan.md)は2026-10-24、既存human承認済み日本語文案を公式App Reviewのその他/EメールフォームからApple ID 6826562310とmacOSを設定して1件送信済み。親CUAが公式受付画面の問い合わせ番号103007143655を確認した。以前の数値ID不足と未送信blockは解消した。Apple回答と事前承認は未取得、デモは未実装。個人資格情報を共有せず、回答を踏まえて審査アクセス方法を判断する。upload、審査提出、公開は未実施で、それぞれ別途承認を得る。

今回の変更はこのreadiness文書とcheckpointだけである。
指定profileの許可された公開metadataをメモリ内CMS decodeで確認した以外に、認証情報、Keychain、利用者containerには触れていない。
profileのインストール、code/config変更、ネットワーク、テスト、build、署名、portal、公開、Gitへの変更操作は行っていない。
このチェックリストは実行承認や審査通過の保証を代替しない。

## 2026-11-11のライセンス表記の状態

ライセンス表記の判断シートQ1〜Q11は、2026-11-11にユーザー（人間）がすべて承認した。
承認は方針の承認であり、最終本文の承認ではない。
承認receiptは発行しておらず、`distributionStatus`は`not-ready`のままである。
[新notices草稿](../build/third-party-notices-app-server-draft-20261111/validation.json)は907 component、493本文で、`draft-not-approved`である。
旧standard草稿との差分は、display_containerの根拠commit差し替え、fxhashのsource header追加、self_cellのApache-2.0採用記録の3点だけである。
[改訂source案内草稿3](../build/source-availability-draft-20261111-2/SOURCE-AVAILABILITY.draft.txt)は、窓口にGitHubのIssueを載せた。
回答期間は未決定で、本文は未承認、未公開である。
Q11はユーザーが確認済みとして進めると回答した。
この回答を記録しただけで、法的適合は確認していない。
Apple SDK留保は原文のまま残し、ユーザーが残余リスクを受け入れた。
前節「次に必要な承認と実作業」の最初の項目は、方針の承認で一部進んだが、正式noticesとsource案内の本文承認とreceiptが未了のため、チェックを付けない。
詳細は[判断シート](store-license-decision-sheet.md)と[残件レビュー](store-license-remaining-review.md)にある。

## 2026-11-11の追加調査（D9・D11）

Meta系6件とscope未確認9件の公開情報調査を行った。
結果は[判断シートの追加調査節](store-license-decision-sheet.md)にある。
取得物は[`build/license-decision-check-20261111-2/`](../build/license-decision-check-20261111-2/)に保存した。
15件はすべて「解消候補（根拠あり）」で、標準条項併記に回す件と未解決の件はなかった。
Meta系6件は、公開直前のcommitで`.crate`内の全ファイルがbyte一致した。
ただし`.crate`に`.cargo_vcs_info.json`はなく、公開時のcommit SHAそのものは確認できていない。
新しい承認質問Q12〜Q16は、未承認である。
草稿は再生成しておらず、policy manifestも変更していない。
草稿は`draft-not-approved`、`distributionStatus`は`not-ready`のままで、承認receiptは発行していない。
