# Third-party notices草稿生成器

保存済み固定0.163.0資料から、配布用noticesのレビュー草稿をオフライン生成する。
標準Pythonライブラリのみを使用し、依存コード、build script、Cargo、ネットワークは実行しない。
日本語技術文書スキルの規範に従い、資料の収集と適用判断、草稿生成と配布承認を区別する。

## 入力と結合

`scripts/generate-third-party-notices.py`は既定の監査results配下の基本7 JSONに加え、-2補完manifest、-3補完manifest、-3のparent-verification receiptを読む。
既定は`closure.releaseUnion`の936 IDを対象とする。
`--scope app-server`ではUnion全体の証拠検証後、`closures.appServer`の正確な907 IDを選ぶ。
metadata全1270 packageやlock全1474 packageを配布binaryの含有集合とは扱わない。
外部依存はname、version、sourceを完全一致させ、Gitでは40桁revisionも照合する。
path依存はmanifest相対位置、name、manifestVersion、元lockVersionの明示対応を使い、160件の内部version同期のみという保存済み分類を確認する。
名前だけの推測一致、曖昧な重複、対象IDの欠落は失敗とする。
この生成器は元lock差分やtarget graphを再解決せず、入力JSONの来歴hashと既存の分類を内部manifestへ記録する。

## 生成と検証

リポジトリrootで実行する。
出力先の親directoryは存在し、出力先自身は未作成である必要がある。

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/ThirdPartyNotices/tests -v
PYTHONDONTWRITEBYTECODE=1 python3 scripts/generate-third-party-notices.py --output build/third-party-notices-draft-NEW
PYTHONDONTWRITEBYTECODE=1 python3 scripts/generate-third-party-notices.py --scope app-server --output build/third-party-notices-app-server-draft-NEW
```

出力は常に`draft-not-approved`かつ`distributionStatus: not-ready`であり、アプリresourcesや公開siteへコピーしない。
`THIRD-PARTY-NOTICES.draft.txt`には公開component名、version、source URL、本文hashと収集本文を記録し、ローカル絶対pathや内部package IDを出さない。
原文bytesは改行変換せず、hash単位で本文を1回だけ保存し、各componentから参照する。
root NOTICEを含むNOTICEとcopyright候補も保持する。
pagable_deriveの実帰属は保存source冒頭のblock comment bytesを抽出し、ライセンス本文ではないsource headerと明示する。
README全文やコードをライセンス全文とみなさず、認識できない候補は内部manifestへ残す。

`internal-manifest.json`は資料path、source、hash、実size、欠落、未レビュー条件をcomponent別に保持する。
`unresolved-report.json`は本文未対応と未レビュー義務を列挙する。
`GENERATION-COMPLETE.json`は生成3ファイルすべての書込み後に作り、各hashとsizeを記録する。
これは草稿の生成完了markerであり、配布承認receiptではない。
途中失敗したdirectoryは完了扱いせず、再利用や既存出力の上書きもしない。
exit 0は草稿生成の完了だけを示し、法的適合、掲載承認、審査通過を示さない。

各資料のSHA-256、記録済みsize、regular file、realpath包含を検証し、途中階層を含むsymlinkを拒否する。
hash不一致や逸脱は生成前に失敗する。
不正UTF-8や本文候補と認識できないfileは本文へ入れず、明示的なreview-neededを残す。
元資料に期待sizeの記録がない場合はhashと実sizeを記録し、`recorded-size-unavailable`を残す。
候補のfile名は全文性や適用範囲の証明ではなく、全componentの帰属と必要NOTICEの適用レビューを未完了とする。
SPDXのOR経路を新たに選択せず、authorsをcopyrightへ変換せず、雛形で帰属を補わない。

## 2026-10-23の限定実行結果

fixtureテスト8件が成功した。
実資料の生成は次の新規directoryへ1回だけ実行し、exit 0だった。

`build/third-party-notices-draft-20261023-1/`

- 対象936 component、本文504 hash、資料参照1642件。
- 配布上の適用と帰属とNOTICEレビュー未完了936件、本文候補なし15件。
- noticeまたはcopyrightの本文参照144件で、固定source root NOTICEも保持した。
- txtは2,218,604 bytes、SHA-256は`4235ec64c70ea7bf84656478c3ca40a34155d013b17a35ddd742bd5991b34d1b`。

保存後に出力3ファイルのhashとsize、936 IDの一意性、1642資料参照のhashとsize、本文のbytesと重複排除、ローカルpathの非混入を照合した。
本文候補なし15件の具体名とversionは内部manifestと未解決reportに記録している。
全依存のlicense適用レビューや新しいlicense取得は行っていない。

## 2026-10-23 補完資料の統合

既定入力へ`license-supplement-20261023-2/manifest.json`を追加した。
source-qualified name/version、元crate checksum、通常member内のVCSと正規化manifest、各保存fileのSHA-256/size/Git blob、collection内包含とURLを照合し、対象closureへの接続漏れも拒否する。
starlark_syntaxの本文と実headerを取り込み、objc2-foundationのSDK留保は全文licenseとは別roleで保持する。
補完の収集statusを義務充足に格上げせず、READMEとprovenance fileは本文へ入れない。
元7入力だけのfixtureは明示的な`supplement_relative=None`と`historical_relative=None`注入で検証し、通常CLIは両補完入力と-3 receiptを必須とする。

全fixture 11件が成功し、新規`build/third-party-notices-draft-20261023-2/`へ1回だけ生成してexit 0だった。
936 component、505本文hash、1645資料参照、全文候補なし14件、義務レビュー未完了936件である。
txtは2,220,013 bytes、SHA-256は`214b79eeb4db24b59156c31dd98cc52f52ec68d9ffc658d18014e499c0f5d3e7`。
旧草稿全fileのhash、同じ936 ID、対象2件以外のcomponent不変、全資料参照hash/size、本文bytes、root NOTICE、objc2の不足とSDK留保を検証した。
常にdraft-not-approvedかつnot-readyを維持する。

## supplement-3専用validator

`historical_supplement_evidence`は-2の実crate VCS照合とは別に、schemaVersion 2のhistorical snapshotを扱う。
-2のvalidatorは元crateのVCS commitとpathの一致を引き続き要求する。
-3では元crateのname/version/source/checksumと通常manifestを照合し、VCSが付属する場合はそれも照合する。
VCS欠落時にhistorical snapshotを元crateのcommitとして扱わず、保存APIの公開version checksum、発行時刻以前のcommit選択、固定repo/commitのsource archiveと通常Rust sourceのbyte一致を検証する。
依存コード、build scriptやsource中の命令は実行しない。

165 references／145 unique pathsはpackages[].filesの件数であり、sourceComparison 11件とreuseVerification 2件を含めた158 combined unique filesとは区別する。
receiptのmanifest hashと訂正件数を照合し、同一pathの重複参照は全metadataの整合を要求する。
全資料と保存API応答のhash、size、包含、通常file、symlink拒否を検証する。
sourceComparisonは元crateと固定snapshotの実bytesからhashと一致判定を再計算し、Rust fileやmanifest比較行の欠落も拒否する。
archiveの逸脱、重複entry、非通常memberの参照を拒否し、リンクを辿った展開は行わない。

6件の確認済み本文、root NOTICE、付属source headerだけを適切な別roleで追加する。
NOTICEやheaderの黙った欠落と、READMEやmanifestの本文への昇格も拒否する。
display_containerのsnapshot manifest 0.8.1と元crate 0.9.0の差はレビュー未完として保持し、候補本文を確認済み対象versionの本文へ昇格しない。
元manifestのSPDX宣言を保持し、全文取得未完をlicense不明や配布禁止とは一括判定しない。
このsupplement-3統合時点ではcanonical SPDX本文の追加機能は未実装だった。
後述の2026-10-24の明示opt-in機能は標準条項を別roleで追加し、上流取得本文とは区別する。

既存11件と-3専用8件の計19 fixtureが成功した。
実資料の生成と結果保存は、親の生成直前quota確認後に新規出力directoryだけへ行う。

## supplement-3統合後の限定生成結果

親は生成直前に利用枠を確認し、実データ生成を承認した。
`build/third-party-notices-draft-20261023-3/`は未存在を確認してから1回だけ生成し、exit 0だった。
全fixture 19件が成功し、生成失敗やrepair、再生成は発生していない。

対象936 componentは旧草稿と同一で、本文507 hash、全文候補なし8件、配布上のレビュー未完了936件である。
6件の実license本文、root NOTICE、付属headerを追加し、NOTICE/copyright参照は150件になった。
保存後に1729資料参照のhash/size、全507本文のbytesと重複排除、出力3fileのhash/sizeを検証した。
訂正済み件数は165 package file references／145 unique paths／158 combined unique filesで、12保存応答も検証した。
新txtは2,238,484 bytes、SHA-256は`03ac362b996adf9b221da106cddd82bdda5b89dc7121772be23c55d99b863fa2`。

objc2-foundationのSDK留保と全文未対応、display_containerの0.8.1／0.9.0不一致を保持し、既存draft-1/-2と入力receiptのhash不変を確認した。
変更対象11 component以外の925 componentは旧草稿と同じであり、元root NOTICEも保持した。
取得資料の不足をlicense不明や配布禁止とは一括判定せず、元manifestの宣言を維持する。
新directoryの`validation.json`に検証と未解決8件を記録し、draft-not-approvedとnot-readyを維持する。
新規取得、Swift build、認証、アプリ、portal、公開、Git、goal状態操作、checkpoint編集は実施していない。
この有限taskを終了し、次の親個別依頼まで自動継続しない。

## 2026-10-24 app-server単独scope

`--scope`は`release-union`（既定）と`app-server`だけを受け付ける。
既存19 fixtureを維持し、scope選択の8件を追加して全27件が成功した。
未指定と明示release-unionは、変更前fixtureの本文、内部manifest、未解決reportの3 hashと一致する。
app-serverでは正確なID集合、Unionからの包含、重複とcount、root、targetを検証し、同名別sourceを名前で採否判定しない。
全Unionと両補完validatorの検証を先に実行するため、除外候補の不正をscope選択で隠さない。

新規`build/third-party-notices-app-server-draft-20261024/`へ1回生成し、exit 0だった。
907 component、491本文hash、NOTICE/copyright参照145件、全文候補なし6件、適用義務レビュー未完907件である。
txtは2,153,406 bytes、SHA-256は`32341f6dcf508018c14573531685e4399a9f37e91fd2a137de0ef7ed3cd4f5f9`。
1684資料参照と全本文bytes、選択907レコードの旧Unionとの同一性、旧草稿15 fileと入力10 fileのhash不変を検証した。
SDK留保、歴史snapshotの版差、実NOTICE、header、未レビュー条件を保持している。
scopeとrootと907件の候補解釈は本文header、内部manifest、未解決report、生成完了markerへ記録する。
標準terms追加や配布承認は行わず、常にdraft-not-approvedかつnot-readyを維持する。
詳細は新規directoryの`validation.json`と[scope説明](../../docs/store-notices-app-server-scope.md)に保存した。

## 2026-10-24 標準条項の明示opt-in

`--standard-license-supplement`でproject相対manifestを明示した場合だけ、標準MITとApache-2.0を`standard-license-text`として併記する。
未指定時は従来どおりで、旧Unionの3出力hash互換fixtureと旧app-server出力保持を確認した。
今回の実装は上流6件の再探索ではなく、宣言に対応する標準条項を別来歴で示す機能である。

SPDX公式`license-list-data`のcommitを`31ba1a50e5397e00a304dbadc76531740e89ee48`に固定した。
公式公開APIでcommitを解決し、固定URLから2本文を取得した計3 requestの応答だけを新規監査directoryへ保存した。
生成器はネットワークを使わず、明示supplementと保存済み応答、本文だけを読む。
保存先は`build/dependency-audit/codex-0.163.0/rust-toolchain-audit-1.95.0/results/standard-license-supplement-20261024/`である。

| 標準本文member | size | SHA-256 |
| --- | --- | --- |
| `text/MIT.txt` | 1078 | `b05785f9f18e6716bab63424b11454513b9943a222595b70411009202fc592b5` |
| `text/Apache-2.0.txt` | 10280 | `074e6e32c86a4c0ef8b3ed25b721ca23aca83df277cd88106ef7177c354615ff` |

commit、repo、member、URL、license ID、hashとsizeを固定照合し、通常fileとsymlink拒否、collection包含、UTF-8を確認する。
対象packageはname、version、lockSource、crate checksumを結合し、元archiveの通常Cargo.tomlの宣言も照合する。
raw宣言を保持し、ORや古いslash表記から採用経路を決めず、両標準本文を参考として提示する。
holder/year placeholderは原文を保持し、packageの実copyrightではないと公開headerで説明する。
`licenseEvidenceAvailability`で上流全文候補の有無、標準条項の有無、帰属と適用範囲の未レビューを別記する。
標準条項を追加しても上流全文取得済みや配布承認へ昇格しない。

```sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/generate-third-party-notices.py \
  --scope app-server \
  --standard-license-supplement build/dependency-audit/codex-0.163.0/rust-toolchain-audit-1.95.0/results/standard-license-supplement-20261024/manifest.json \
  --output build/third-party-notices-app-server-standard-draft-20261024
```

既存27件と新規7件、計34 fixtureが成功した。
新規directoryへの実生成は1回でexit 0、907 components、492 unique texts、標準条項6件／10参照となった。
標準本文は2種類だがApache本文は既存本文hashと共有され、unique textsの増加は1件だった。
上流全文候補なし6件、義務レビュー未完907件、NOTICE/copyright参照145件を維持した。
txtは2,157,754 bytes、SHA-256は`79c5a44f0d280147676805179ef89a06e2c2f52b5da76bfcab3ae9d870fa8419`。
1694資料参照のhash、sizeと包含、全本文bytes、raw宣言、実NOTICE、header、SDK留保、版差とhistoryの保持を検証した。
旧907/936を含む草稿20 fileと既存入力10 fileのhash不変を確認し、新規directoryの`validation.json`へ保存した。
日本語技術文書スキルに従い、標準条項の追加と上流資料収集、法的適合と配布承認を分けて記録した。
draft-not-approvedとnot-readyを維持し、配布承認receipt、config.ready変更、アプリ組込み、公開は行っていない。
