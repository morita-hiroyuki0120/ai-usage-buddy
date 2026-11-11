# Store版のsource入手案内の配布準備

確認日：2026-10-23。
状態：ローカル草稿、本文未承認、正式source案内として未承認、未公開。
法的適合の認定や法律助言ではなく、受領者向けのsource入手案内を準備する記録である。

## 対象と一次資料

MPL-2.0の12候補はnotices草稿-2のinternal-manifestと既存Cargo inventoryに対応する。
12候補すべてがappServer 907件の集合に含まれることは親担当のjq照合済みという共有に基づく。
今回、target inventoryのappServerPackages=907も確認した。
このsource由来の候補集合を、配布binaryの完全な再現buildによる証明とは扱わない。

[MPL 2.0本文](https://www.mozilla.org/en-US/MPL/2.0/)の3.1、3.2、3.3、3.4と[Mozilla FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/)のQ7、Q8を確認した。
sourceにMPLが適用される旨とライセンスの入手方法、実行形式の受領者が対応sourceを合理的な方法で適時入手する方法を案内する準備を進める。
元の通知を保持し、実行形式側の条件でMPL sourceの権利を制限しないことも確認対象とする。
FAQ Q7は他者が作成した完全な無変更実行形式の再配布を、Q8は他者の無変更sourceから自分でコンパイルした場合を扱う。
Q7の説明は上流の遵守を前提とし、一部だけの配布等には追加対応が必要な場合があるため、本件を自動的に義務充足済みとはしない。

## 再配布予定の範囲

固定Codex helperの元実行形式をsource無変更で同梱し、変更はStore向けの再署名のみとする予定である。
これは現在の配布計画であり、最終成果物の変更履歴や同梱通知は配布前に照合する。
sourceを変更した場合は案内を更新し、対象変更sourceの提供方法も再判断する。
再現binary buildの絶対証明をこの案内の必須条件にはしないが、固定helper、source commit、依存version、保存archiveの対応は残す。

AI Usage Buddy本体のMIT、Codex rootのApache-2.0、対象依存のMPL-2.0はそれぞれの対象に適用される別の条件である。
アプリやCodex rootのライセンスを依存source全体へ一括適用しない。

## 既存ローカル資料の確認結果

以下の略号はすべてリポジトリrootからの固定相対pathであり、公開候補本文には含めない。

- `A = build/dependency-audit/codex-0.163.0/rust-toolchain-audit-1.95.0`
- `R = A/results`
- `C = A/cargo-home/registry/cache/index.crates.io-1949cf8c6b5b557f`
- `G = A/cargo-home/git/checkouts/nucleo-425d994cd74b3654/4253de9`

照合元は`build/third-party-notices-draft-20261023-2/internal-manifest.json`と`R/cargo-lock-license-inventory.json`。
公開候補の各URLはinternal-manifestのsourceURLと同じ値を使用する。
10件のcrateについて、実ファイルのSHA-256がinventoryのarchive SHAと一致し、inventory上はlock checksumとも同値であることを確認した。
全archiveの一覧内にRust sourceが存在し、12件分の保存済みLICENSE本文の実SHA-256がmanifestの値と一致した。
初回は保存資料だけを照合した。
後続の公開HTTPS取得結果と安全検査の留保は下記「公開sourceの入手確認」に記録する。

| 対象 | version | sourceArtifactSHA256（ローカル再計算一致） |
|---|---|---|
| nucleo | 0.5.0 | 対象外（Git checkout、下記commit） |
| nucleo-matcher | 0.3.1 | 対象外（Git checkout、下記commit） |
| option-ext | 0.2.0 | `04744f49eae99ab78e0d5c0b603ab218f515ea8cfe5a456d7629ad883a3b6e7d` |
| symphonia | 0.6.0 | `1758d6c853020a7244de03cc3e0185eaea3f58715122422dd3cc7452e6d4c16a` |
| symphonia-bundle-mp3 | 0.6.0 | `350f1f2f2e19ad4dd315db94304d1eb361b29af070681f94e51b8fdaad769546` |
| symphonia-common | 0.6.0 | `8257891ffa7f05e02b58f4761e2abf7e5278c8744fd59e981559e050f86eef55` |
| symphonia-core | 0.6.0 | `95ec293b5f288383b72a7bffcade6b2860b642cf66f28b3bd5967349a49938b1` |
| symphonia-format-isomp4 | 0.6.0 | `2d179a01305b3505940135a9f0180d6ef4b487912748fe97554756f120fbd05e` |
| symphonia-format-mkv | 0.6.0 | `fb17713e134f5ad316c2690fa3104590ccc85842cdbcf82c3cd1a845cb08aa74` |
| symphonia-format-ogg | 0.6.0 | `b05a67e02b1e4fca1a261ba4fe06910a9357489ad8c36aafdd2960e9c6559433` |
| symphonia-format-riff | 0.6.0 | `17424452a777666d3eaf09a5c651029b15b6a333812fcc5b5474f2a3f0cff3f0` |
| symphonia-metadata | 0.6.0 | `a31acf5cd623398a6208e2225d18f4b20f761c55098a796a5247ad516a4a8681` |

nucleo 2件は上流commit `4253de9faabb4e5c6d81d946a5e35a90f87347ee`に固定され、既存inventoryのrevisionと公開URLが対応する。
checkoutのCargo.tomlでname、version、MPL-2.0表記を確認し、rootとmatcherのsource計24ファイルの保存を確認した。
Git操作は行っていないため、今回はcheckoutのHEADや全内容をcommitへ再検証していない。
初回の保存単位はGit checkoutなので、上表の既存inventoryにはsource archive SHA-256が存在しない。
後続で取得したcodeload archiveのSHA-256は下記に別記し、commit IDやLICENSEのSHAと区別する。

| 対象 | source保存先またはmanifest | 保存済みLICENSE |
|---|---|---|
| nucleo@0.5.0 | `G/Cargo.toml` | `R/git-license-texts/nucleo-425d994cd74b3654-4253de9faabb/LICENSE` |
| nucleo-matcher@0.3.1 | `G/matcher/Cargo.toml` | `R/git-license-texts/nucleo-425d994cd74b3654-4253de9faabb/LICENSE` |
| option-ext@0.2.0 | `C/option-ext-0.2.0.crate` | `R/lockfile-license-texts/option-ext-0.2.0/option-ext-0.2.0/LICENSE.txt` |
| symphonia@0.6.0 | `C/symphonia-0.6.0.crate` | `R/lockfile-license-texts/symphonia-0.6.0/symphonia-0.6.0/LICENSE` |
| symphonia-bundle-mp3@0.6.0 | `C/symphonia-bundle-mp3-0.6.0.crate` | `R/lockfile-license-texts/symphonia-bundle-mp3-0.6.0/symphonia-bundle-mp3-0.6.0/LICENSE` |
| symphonia-common@0.6.0 | `C/symphonia-common-0.6.0.crate` | `R/lockfile-license-texts/symphonia-common-0.6.0/symphonia-common-0.6.0/LICENSE` |
| symphonia-core@0.6.0 | `C/symphonia-core-0.6.0.crate` | `R/lockfile-license-texts/symphonia-core-0.6.0/symphonia-core-0.6.0/LICENSE` |
| symphonia-format-isomp4@0.6.0 | `C/symphonia-format-isomp4-0.6.0.crate` | `R/lockfile-license-texts/symphonia-format-isomp4-0.6.0/symphonia-format-isomp4-0.6.0/LICENSE` |
| symphonia-format-mkv@0.6.0 | `C/symphonia-format-mkv-0.6.0.crate` | `R/lockfile-license-texts/symphonia-format-mkv-0.6.0/symphonia-format-mkv-0.6.0/LICENSE` |
| symphonia-format-ogg@0.6.0 | `C/symphonia-format-ogg-0.6.0.crate` | `R/lockfile-license-texts/symphonia-format-ogg-0.6.0/symphonia-format-ogg-0.6.0/LICENSE` |
| symphonia-format-riff@0.6.0 | `C/symphonia-format-riff-0.6.0.crate` | `R/lockfile-license-texts/symphonia-format-riff-0.6.0/symphonia-format-riff-0.6.0/LICENSE` |
| symphonia-metadata@0.6.0 | `C/symphonia-metadata-0.6.0.crate` | `R/lockfile-license-texts/symphonia-metadata-0.6.0/symphonia-metadata-0.6.0/LICENSE` |

LICENSE本文のSHA-256はnucleo 2件の共有本文が`1f256ecad192880510e84ad60474eab7589218784b9a50bc7ceee34c2b91f1d5`、option-extが`66a3107d5ad6a058aab753eaac2047ccb2ed0e39465dd0fe5844da3e300d5172`、symphonia 9件それぞれが`c76f740d1521b9bed9ca7a04ad526c310493c62621b1341d623b431736533b30`で、すべて実ファイルと一致した。
nucleoのcheckout内LICENSEも共有保存本文と同じSHA-256だった。
LICENSE候補の保存確認は各fileの適用範囲や著作権表示の最終承認を代替しない。

Codex rootはcommit `83086188ae0614bd882818ff1aa23f3194962012`に固定する。
既存archive `build/dependency-audit/codex-0.163.0/source-audit-83086188/codex-source-83086188.tar.gz`の実SHA-256は`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`で既存記録と一致した。
同directoryの`checkout/codex-83086188ae0614bd882818ff1aa23f3194962012/LICENSE`でApache License Version 2.0表記を確認した。
root sourceだけでは外部Cargo依存sourceの代替にはならないため、MPLの12件を別記する。

## 公開sourceの入手確認

2026-10-23 21:26 JST（12:26 UTC）に、10件のstatic.crates.io固定URLとnucleo固定commitのcodeload archiveを公開HTTPS GETで各1回取得した。
通常ファイルの追加検査は同日21:27 JSTに保存済みarchiveだけで行った。
取得は計11 GET、再試行0、redirect0で、すべてHTTP 200だった。
requestedURL、finalURL、HTTP status、UTC日時、取得物SHA-256、入力inventoryのhash、検査結果は[availability-results.json](../build/source-availability-check-20261023.IN0yac/availability-results.json)に記録した。
最終URLは全11件でrequestedURLと同一であり、認証情報は使用していない。

| 対象 | 取得と検査結果 |
|---|---|
| option-ext 0.2.0とsymphonia系9件の各0.6.0 | 10件ともHTTP 200。archive SHA-256は既存inventoryのpinと一致。全memberのpath containment、通常fileまたはdirectoryのみであること、サイズ上限を確認し、通常Cargo.tomlのname/version/MPL-2.0とLICENSEの保存済みhashも一致した。 |
| nucleo 0.5.0とnucleo-matcher 0.3.1 | 固定commitのcodeload archiveはHTTP 200。通常Cargo.toml 2件のname/version/MPL-2.0とroot LICENSEのhashは一致。ただしmatcher/LICENSEがsymlinkのため、archive全体の安全検査はblockedとして保持した。 |

nucleo取得URLは`https://codeload.github.com/helix-editor/nucleo/tar.gz/4253de9faabb4e5c6d81d946a5e35a90f87347ee`。
取得物は86,782 bytes、SHA-256は`d1676ac33a82c5903ffede68ce73c9d924666aa8a102bb649a8fb926a7a61ce1`である。
これは今回取得物の計算値であり、上流公表checksumや従来inventoryのarchive pinではない。
公開候補に記載したGitHub treeのHTML自体は取得せず、同じ固定commitに対応するcodeload sourceの取得と通常manifestでの対応を確認した。

blocked itemは`nucleo-4253de9faabb4e5c6d81d946a5e35a90f87347ee/matcher/LICENSE`から`../LICENSE`へのsymlink 1件である。
リンクは辿らず、archiveを展開せず、全56 memberのpath containmentとサイズを読み取り検査した上で、通常fileであるroot LICENSEと2 manifestだけを追加で読んだ。
root LICENSEのSHA-256は既存保存本文の`1f256ecad192880510e84ad60474eab7589218784b9a50bc7ceee34c2b91f1d5`と一致した。
この結果は「URL取得不能」ではなく、「取得と通常metadata確認は成功、リンクを禁止するarchive全体検査は不合格」と区別する。
安全検査済みarchiveは10件、通常metadata確認済み対象は12件であり、12件すべてのarchiveを受入済みとは扱わない。
後続で利用する場合もリンクを展開または実行しない方針を維持し、必要なsourceの安全な提供方法を判断する。

取得物と確認スクリプトは新規`build/source-availability-check-20261023.IN0yac/`内だけに保存した。
圧縮後は各16 MiB、非圧縮は各64 MiB、member数10,000、metadata各1 MiBを上限とし、symlink、hardlink、特殊fileを受入対象から除外した。
sourceのコード実行、source build、Git操作、既存global Cargo/cacheの変更は行っていない。
この記録は確認時点の入手可能性であり、将来の可用性、配布binaryの再現性、法的適合、正式本文の承認を保証しない。
自社source hostは引き続き未作成、未公開で、自社で全sourceを再ホストする一律の追加条件は設けない。

## 公開候補と配布前の判断

公開候補は[SOURCE-AVAILABILITY.draft.txt](../build/source-availability-draft-20261023/SOURCE-AVAILABILITY.draft.txt)。
12件それぞれのexact versionとsource URL、nucleoの固定commit、Codex rootの固定commit、ライセンスの区別を記載する。
URLは既存manifestからの候補である。
初回のネット取得はMozilla公式の本文とFAQの2ページのみ、今回のsource入手確認は上記の11 GETに限定した。
公開候補txtは初回草稿のまま未承認であり、現在の確認結果を反映する正式本文のレビューと採用は別工程で行う。

1. 最終同梱helperと対象sourceの対応、無変更再配布の範囲、LICENSEとNOTICEの保持、案内本文を担当者が確認し承認する。
2. 今回の確認時点では10件のcrateとnucleo固定commit archiveを取得できた。配布時にはこの具体的な根拠とリンク検査の留保を使って、versionとcommitの一致、MPLの表示、合理的な方法で適時入手できるかを判断する。確認時点以後の可用性や未確認範囲を成功と推測しない。
3. 上流URLを使う方法、配布物にsourceを添付する方法、自社host等を必要に応じて選ぶ。自社で全sourceを再ホストすることを一律の必須条件にはしない。自社hostは現時点で未作成、未公開であり、存在する配布先として案内しない。
4. 上流URLが削除や移動で利用できなくなるリスクを踏まえ、公開案内の保守と代替入手方法を決める。既存ローカルcacheは未公開で、受領者が利用できる入手先ではない。cacheの存在だけで配布準備完了とはしない。
5. 採用した入手先と案内を正式配布物から到達できるようにする方法を決め、最終配布物とともに確認する。今回の草稿を公開済み、正式承認済み、法的適合確認済みとは記載しない。

初回はこの計画と公開候補の2ファイルを作成した。
今回の追補では新規隔離フォルダーへの公開source取得と結果JSON保存、本計画更新、checkpoint追記を行った。
アプリのコード変更、認証、アプリ操作、portal操作、実公開は行っていない。

## 現在状態（2026-11-11）

最終本文は`build/store-approved-inputs-20261111/SOURCE-AVAILABILITY.txt`で、回答期間は「30日以内」、ユーザー（人間）が承認した。
公開済みではなく、法的適合を断言するものでもない。
