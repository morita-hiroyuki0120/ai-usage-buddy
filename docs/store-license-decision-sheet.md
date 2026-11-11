# Storeライセンス表記の判断シート

確認日：2026-11-11。
対象は固定Codex 0.163.0のapp-server単独907候補と、標準条項併記済みの草稿[`third-party-notices-app-server-standard-draft-20261024`](../build/third-party-notices-app-server-standard-draft-20261024/validation.json)である。
このシートは人間が承認判断をするための整理であり、法的適合の断言や法律助言ではない。
「推奨」は調査担当の提案、「要人間確認」は人間の判断なしに確定できない事項を指す。
`config/EmbeddedAppServer.json`の`distributionStatus`は`not-ready`のままであり、承認receiptは発行していない。
草稿は`draft-not-approved`のままである。

## 承認が必要な項目のチェックリスト

- [x] Q1：全文候補なし6件（D1〜D6）に、標準条項の併記（`standard-license-text`）と宣言の明記で対応する方針を承認するか。 2026-11-11 ユーザー承認
- [x] Q2：display_containerの版差を、新たに確認した固定commit `13efb6d`への差し替えで整理する方針を承認するか。 2026-11-11 ユーザー承認
- [x] Q3：fxhashのsource headerを実copyrightの出所として表示に加える方針を承認するか。 2026-11-11 ユーザー承認
- [x] Q4：objc2系のApple SDK留保を、原文のまま表示して残余リスクを受容するか。 2026-11-11 ユーザー承認（ユーザーの回答：原文のまま表示し、残余リスクを受け入れる）
- [x] Q5：self_cellはApache-2.0を採用する（GPL-2.0-onlyは採用しない）方針を承認するか。 2026-11-11 ユーザー承認
- [x] Q6：その他のOR選択は上流の全文を併記し、配布者による個別選択を記録しない方針を承認するか。 2026-11-11 ユーザー承認
- [x] Q7：必要なNOTICE（Codex root、Meta buck2、moka、cfg_aliases、各COPYRIGHT）を現行のまま表示する方針を承認するか。 2026-11-11 ユーザー承認
- [x] Q8：MPL-2.0の12候補について、改訂source案内草稿の採用に進むか。 2026-11-11 ユーザー承認（承認の範囲は採用手続へ進むこと。改訂source案内の本文レビューと採用は未実施）
- [x] Q9：上流の消失に備え、source案内に「依頼があれば提供する」旨の窓口を載せるか。 2026-11-11 ユーザー承認（ユーザーの回答：窓口はGitHubリポジトリのIssue。個人の連絡先は載せない）
- [x] Q10：nucleoはGitHubのtree URLと固定commitで案内し、symlink入りarchiveを自社配布物に同梱しない方針を承認するか。 2026-11-11 ユーザー承認
- [x] Q11：MPL-2.0とApple標準EULAの関係を、配布者が確認するか。 2026-11-11 ユーザー承認（ユーザーの回答：配布者であるユーザーが確認済みとして進める。調査担当は確認しておらず、法的適合を判断していない）
- [ ] Q12：Meta系6件（D9）の根拠commitを、4f1406cからcrateごとの公開時点commit（下の表）へ差し替える補完manifestを作る方針を承認するか。
- [ ] Q13：allocativeとallocative_deriveは、公開manifestの宣言`Apache-2.0`をそのまま表示し、repositoryの`MIT OR Apache-2.0`とsource headerのdual-license記述も併記する現行構成のままでよいか。
- [ ] Q14：mxc系3件、tokio-tungstenite、tungstenite、nucleo、nucleo-matcherの`repository-license-scope-unreviewed`を、下の根拠で解消済みと記録するか。
- [ ] Q15：rmcpとrmcp-macrosは、MIT移行中の注記とMIT全文を含むroot LICENSEを原文のまま表示する構成でよいか。
- [ ] Q16：nucleoの表示に、`src/boxcar.rs`と`src/par_sort.rs`の冒頭にある第三者copyrightとpermission本文を、source headerとして加えるか。

## 2026-11-11の承認結果と反映状況

Q1〜Q11はすべて2026-11-11にユーザー（人間）が承認した。
Q1〜Q3、Q5〜Q8、Q10は「推奨どおりでOK」との回答で、Q4、Q9、Q11は質問カードへの回答である。
承認は方針の承認であり、最終本文の承認でも、承認receiptの発行でもない。
`config/EmbeddedAppServer.json`の`distributionStatus`は`not-ready`のままで、草稿は`draft-not-approved`のままである。

反映した成果物は次のとおりである。

- Q2・Q3・Q5：[`build/third-party-notices-app-server-draft-20261111/`](../build/third-party-notices-app-server-draft-20261111/validation.json)に新草稿を生成した。入力は[`build/license-policy-supplement-20261111/manifest.json`](../build/license-policy-supplement-20261111/manifest.json)、生成は`Tools/ThirdPartyNotices/generate_policy_draft.py`である。
- Q9：[`build/source-availability-draft-20261111-2/`](../build/source-availability-draft-20261111-2/SOURCE-AVAILABILITY.draft.txt)に、GitHub Issueの窓口を載せた改訂3を作った。回答期間は未決定のまま記載した。
- Q1・Q6・Q7・Q10：現行の構成を維持した。草稿の本文に変更はない。
- Q4：SDK留保を原文のまま維持した。本文に変更はない。
- Q8：改訂source案内の本文レビューと採用は、人間が別途行う。採用済みにはしていない。
- Q11：ユーザーの回答を記録しただけで、MPL-2.0とApple標準EULAの関係を調査担当は確認していない。

「推奨」欄と判断表は、承認前の記録として残している。

## 残件ごとの判断表

宣言は公開crate manifestとcrates.ioのmetadata（2026-11-11に確認）の値である。
「確認できなかった」と書いた事項は、今回の調査で確かめていない。

### 1. 上流全文候補なし6件

| ID | 対象 | 現状・根拠 | 推奨対応 | 人間が決めること（はい／いいえ） |
| --- | --- | --- | --- | --- |
| D1 | objc2-foundation 0.3.2<br>宣言`MIT` | crates.ioは`MIT`、repositoryは`madsmtm/objc2`。<br>公開crateにlicense fileはない（`.crate`内はREADME、Cargo.toml等のみ）。<br>固定commit `7b1abfd`のroot `LICENSE.md`はMITの適用先を示すがMIT全文ではなく、Apple SDK由来の留保を含む。<br>同commitに`LICENSE-MIT.txt`はない（取得結果404）。<br>現在のHEADには`LICENSE-MIT.txt`があり「Copyright 2026 Mads Marquart」と書かれるが、0.3.2より後の記述である。 | `LICENSE.md`を原文のまま表示し、標準MIT本文を参考併記する（現行草稿の構成）。<br>HEADの著作権表示を0.3.2へ当てはめない。<br>著作権者・年を補作しない。<br>SDK留保はD7で別に扱う。 | 標準MIT本文の参考併記と宣言の明記で足りるとする方針を採るか。（Q1） |
| D2 | debugserver-types 0.5.0<br>宣言`MIT` | crates.ioは`MIT`、repositoryは`Marwes/debugserver-types`。<br>`Cargo.toml`のauthorsは`Markus Westerlind`で、これはmanifestのメタデータでありcopyright表示ではない。<br>crate内とGitHubのtop levelにlicense／NOTICEはない。<br>固定commit `d444f16`の全9 tree entriesにも全文候補はない（既存補完資料）。<br>生成元DAP schemaの固定revisionは確認できなかった。 | 標準MIT本文を参考併記し、「このpackageから取得した本文ではなく、著作権表示は見つかっていない」と明示する（現行草稿の構成）。<br>authorsをcopyrightに格上げしない。<br>schemaの出所は別件として残す。 | D1と同じ方針でよいか。（Q1） |
| D3 | display_container 0.9.0<br>宣言`MIT OR Apache-2.0` | crates.ioは`MIT OR Apache-2.0`、repositoryは`facebookincubator/gazebo`。<br>source headerは「Copyright (c) Meta Platforms, Inc. and affiliates」で、MITとApacheの「both」と書く。<br>旧草稿の根拠はcommit `e867865`で、そのmanifestは0.8.1だった。<br>**今回の新規確認**：crates.ioの0.9.0公開は2023-06-05 12:23 UTC。同日のgazebo commit `13efb6d415c4729178dfccc36fa9c87491f0813d`（"Prepare for a release"）のmanifest versionは`0.9.0`で、`display_container/src/lib.rs`（SHA-256 `13db2d71…add5`）と`Cargo.toml`（`9eb42b9a…ad39`）がcrateの`src/lib.rs`と`Cargo.toml.orig`にbyte一致した。<br>同commitの`LICENSE-MIT`（`da6d3703…8e93`）と`LICENSE-APACHE`（`50e67517…780a`）は、旧草稿が保存した本文とbyte一致した。<br>取得物とhashは[`gazebo-13efb6d`](../build/license-decision-check-20261111/gazebo-13efb6d/)に保存した。<br>なおgazebo repoの最新commitは「Prepare to retire allocative and gazebo repositories」（2026-06-14）で、将来の移動や削除の可能性がある。 | 根拠commitを`e867865`から`13efb6d`へ差し替える補完manifestを新規に作り、版差を「解消候補」とする。<br>Meta copyrightのheaderと両全文を保持する。<br>OR／bothの扱いはD8に従い、生成器は選択を推測しない。<br>commitの一致は「公開時点のsourceと同一」の根拠であり、適用義務の確認完了ではない。 | 根拠commitを`13efb6d`へ差し替えてよいか。（Q2）<br>差し替え後も、Metaへの版差の問い合わせは不要としてよいか。 |
| D4 | eventsource-stream 0.2.3<br>宣言`MIT OR Apache-2.0` | crates.ioは`MIT OR Apache-2.0`、repositoryは`jpopesculian/eventsource-stream`。<br>READMEに「Licensed under either of Apache License, Version 2.0 / MIT license at your option」とある。<br>manifestのauthorsは`Julian Popescu`（copyright表示ではない）。<br>crate内とGitHubのtop levelにlicense／NOTICEはない。<br>固定commit `3d46f1c`の全18 tree entriesにも本文候補はない。 | D2と同じ。標準MIT本文とApache-2.0本文を参考併記し、READMEの宣言を根拠として示す。<br>OR選択はD8に従う。 | D1と同じ方針でよいか。（Q1） |
| D5 | fxhash 0.2.1<br>宣言`Apache-2.0/MIT` | crates.ioは`Apache-2.0/MIT`、repositoryは`cbreeden/fxhash`。<br>`lib.rs`のheaderに「Copyright 2015 The Rust Project Developers. See the COPYRIGHT file」と、ApacheまたはMITを選べる記述がある。<br>参照先のRust `COPYRIGHT`、`LICENSE-APACHE`、`LICENSE-MIT`はcrateにもGitHubのtop levelにもない。<br>現行草稿のtextsには標準条項2件だけがあり、このheaderは含まれていない。 | `lib.rs`冒頭のheader（実在する唯一のcopyright表示）を`source-header`として表示に加える（次回の補完manifestで追加）。<br>標準MIT／Apache-2.0本文は参考併記のままにする。<br>現在のRust COPYRIGHT本文や年を過去版へ当てはめない。<br>raw宣言`Apache-2.0/MIT`はそのまま保つ。 | headerを表示に加える方針でよいか。（Q3）<br>Rust COPYRIGHTのURL参照は載せなくてよいか。 |
| D6 | io_tee 0.1.1<br>宣言`MIT OR Apache-2.0` | crates.ioは`MIT OR Apache-2.0`、repositoryは`TheOnlyMrCat/io_tee`。<br>READMEに「License: MIT OR Apache-2.0」とある。<br>manifestにauthorsはない。<br>crate内とGitHubのtop levelにlicense／NOTICEはない。<br>固定commit `8a7adec`に本文候補はない。 | D4と同じ。copyright holderと年は補作しない。 | D1と同じ方針でよいか。（Q1） |

6件に共通する整理は次のとおりである。
- 標準条項の併記は「宣言された条件の参考表示」であり、そのpackageから取得した本文ではない。
- MITは著作権表示と許諾表示の保持を条件に含むが、6件のうち実在する著作権表示はD3のMeta headerとD5のRust headerだけである。
- 見つからない著作権表示は補作できないため、「見つからなかった」と明記する対応が現実的な上限である。要人間確認。
- 上流の保守者への問い合わせは、第三者へ連絡する操作なので今回行っていない。必要なら人間が許可する。

### 2. SDK留保・版差・OR選択・NOTICE

| ID | 対象 | 現状・根拠 | 推奨対応 | 人間が決めること（はい／いいえ） |
| --- | --- | --- | --- | --- |
| D7 | Apple SDK留保 | 固定commitの`LICENSE.md`は、これらのcrateがXcodeのSDK由来であり、派生物の配布が許されるかはXcode licenseから読み取れず不明と明記する。<br>同じ`LICENSE.md`を全文候補に持つのは、objc2-foundation、objc2-app-kit、objc2-core-foundation、objc2-local-authentication（SDK由来のframework crate）、およびobjc2、block2、objc2-encode（SDK由来かどうかは確認できなかった）である。<br>留保が及ぶ範囲はobjc2-foundationだけではない可能性が高い。<br>同crate群はOpenAIがビルドしたhelperに静的に含まれ、AI Usage Buddyは無変更で再配布する。<br>`LICENSE.md`は上流issue `#23`を参照するが、その内容は確認できなかった。 | `LICENSE.md`を原文のまま表示し、留保を隠さない。<br>留保を解消したと書かない。<br>配布者が受容するかを人間が判断する。<br>受容しない場合の代替（helperの作り直し）は現計画の範囲外。 | Apple SDK由来の留保を原文表示のうえ受容するか。（Q4）<br>留保が及ぶcrateを上の4件＋3件として記録してよいか。 |
| D8 | OR選択ライセンス | 907件のうち、COPYLEFT系を含むORは`self_cell 1.2.2`の`Apache-2.0 OR GPL-2.0-only`だけである。<br>他は`MIT OR Apache-2.0`（357件）、`Unlicense OR MIT`、`Zlib OR Apache-2.0 OR MIT`、`Apache-2.0 OR BSL-1.0`、`BSD-3-Clause OR Apache-2.0`等の寛容なライセンス同士である。<br>`ring`（`Apache-2.0 AND ISC`）や`aws-lc-sys`等のANDは全条件が適用されるためORとは別である。<br>生成器はORを選択せず、旧slash表記も変更しない（validationの`ORNotSelected…`）。 | self_cell：**Apache-2.0を採用**し、GPL-2.0-onlyは採用しない。<br>self_cellの`LICENSE-APACHE`は保持し、GPL本文も上流どおり残すが「Apache-2.0を選択」と明記する。<br>それ以外のOR：上流の全文を併記し、受領者がどれかを選べる状態を保つ。個別の選択記録は不要。記録する場合の既定は、MITがあればMIT、なければApache-2.0。 | self_cellにApache-2.0を採用するか。（Q5）<br>他のORは個別選択を記録しない方針でよいか。（Q6） |
| D9 | 版差（D3以外） | `historical-snapshot-scope-and-NOTICE-review-pending`は11件。内訳はD2〜D6の5件に加え、allocative、allocative_derive、lock_free_hashtable、static_interner、strong_hash、strong_hash_derive（いずれもMeta系）。<br>後者6件の固定commitとcrate versionの対応は今回調べていない。 | D3と同じ手順（公開日と同日commit、source byte一致、LICENSE hash一致）で順に確認する。<br>確認できるまで現行の留保を維持する。 | 後者6件の追加確認を次の作業として進めてよいか。 |
| D10 | 必要なNOTICE | 草稿のnotice／copyright候補は145参照。<br>Codex root `NOTICE`（"OpenAI Codex / Copyright 2025 OpenAI"とRatatui帰属）は、116のworkspace crateに共有されている。<br>Meta buck2の`NOTICE`はallocative系等の6件に対応する。<br>mokaの`NOTICE`は、`frequency_sketch.rs`と`timer_wheel.rs`がApache-2.0のみである旨を示す。<br>cfg_aliasesの`NOTICES.md`は、tectonic_cfg_supportのMIT本文を含む。<br>rand、rustix、encoding_rs、unicode-*等には`COPYRIGHT`がある。<br>これら以外に、新たに必要と判断したNOTICEは見つかっていない（網羅の保証ではない）。 | 現行草稿の145参照を維持する。<br>Codex rootのLICENSEとNOTICEは、既存計画どおり`StoreNotices`にも同梱する。<br>mokaの例外は、表示で見える位置に残す。 | 上記NOTICEを現行のまま表示する方針でよいか。（Q7） |
| D11 | repository-license-scopeの未確認9件 | mxc_config_contract、mxc_telemetry、wxc_common、rmcp、rmcp-macros、tokio-tungstenite、tungstenite、nucleo、nucleo-matcherは、repository全体のlicenseが当該packageに及ぶ範囲が未確認。 | 今回は調べていない。次の作業として、各repositoryのLICENSE配置とpackageの対応を確認する。 | 9件の確認を次の作業として進めてよいか。 |

### 3. MPL-2.0の12候補とsource案内

| ID | 対象 | 現状・根拠 | 推奨対応 | 人間が決めること（はい／いいえ） |
| --- | --- | --- | --- | --- |
| D12 | MPL-2.0の12候補<br>nucleo、nucleo-matcher、option-ext、symphonia系9件 | 全件が907件の集合に含まれる。<br>10件のcrateは、2026-10-23の取得でarchive SHA-256がpinと一致した。<br>2026-11-11に10 crateのURL、nucleoのcodeload archiveとtree、Codex commitのtree、MPL-2.0本文ページをheader取得し、全件HTTP 200だった（[記録](../build/license-decision-check-20261111/head-checks-20261111.tsv)）。<br>この再確認は内容やhashの再検証ではない。<br>helperは無変更で再署名のみの計画であり、MPL-2.0 §3.2は実行形式の受領者へsourceの入手方法を知らせることを求める。<br>改訂草稿は[`build/source-availability-draft-20261111/`](../build/source-availability-draft-20261111/SOURCE-AVAILABILITY.draft.txt)に作った。<br>変更点は、確認結果の反映、nucleoのarchive URLとSHA-256の追記、nucleo-matcherの注意書き、symlinkの注記、上流消失時の窓口（未決定のプレースホルダ）である。 | 改訂草稿を正式本文の候補として人間がレビューする。<br>Apple標準EULAがMPLの§3.2（受領者のsource権利を制限しない）と衝突しないかを配布者が確認する（要人間確認。今回は確認できなかった）。 | 改訂草稿のレビューと採用手続に進むか。（Q8）<br>上流消失時の問い合わせ窓口を載せるか。載せる場合の窓口は何か。（Q9）<br>MPLとApple標準EULAの関係を確認するか。（Q11） |
| D13 | nucleo固定commit archiveのsymlink | codeload archiveは`matcher/LICENSE`が`../LICENSE`へのsymlinkで、リンクを禁止する安全検査がblockedのまま。<br>root LICENSE（`1f256eca…f1d5`）と2 manifestの確認は成功済み。<br>**今回の新規確認**：crates.ioの`nucleo-matcher 0.3.1`（SHA-256 `bf33f538…ac85`、`path_in_vcs: matcher`）は、`src`の9ファイルの内容が固定commitと異なり、`utf32_str`ディレクトリは固定commit側にしかない。crates.ioのcrateは固定commitの代替にならない。<br>crates.ioのcrateとcommitの`LICENSE`は同一hash（`1f256eca…f1d5`）だった。<br>GitHubのtree、blob（root LICENSEと`matcher/LICENSE`）のURLはHTTP 200。 | 受領者向けの案内は、GitHubのtree URLと固定commit（必要ならcodeload URLを併記）とする。<br>symlinkは受領者側の展開の注意であり、案内上は注記で足りる（改訂草稿に反映済み）。<br>自社配布物にarchiveを同梱する場合のみ、symlinkを通常ファイルへ置換した派生archiveを別hashで作るか、同梱しないかを選ぶ。<br>crates.ioの`nucleo-matcher`への差し替えはしない。 | symlink入りarchiveを自社配布物に同梱せず、URL案内にとどめる方針でよいか。（Q10） |

## 判断を待つ間に進められる作業

- D3の補完manifest（根拠commitを`13efb6d`へ変更）とD5のheader追加を反映した新規草稿の再生成。generatorは変更せず、新規の補完manifestと新規出力directoryで行える。今回は承認前のため再生成していない。（承認後の2026-11-11に生成した。上の「承認結果と反映状況」を参照）
- D9とD11の追加調査。

## 今回実施した確認

- 公開情報のGET：crates.io API 7件（6 crate＋self_cell）、GitHub API／rawのtop level一覧と数ファイル、nucleo-matcherのcrate取得1件、gazebo固定commitの4ファイル、header取得14件。認証は使っていない。
- 保存したもの：`build/license-decision-check-20261111/`（gazebo固定commitの4ファイルとheader取得の記録）。
- generatorのfixture 34件は成功した（`python3 -m unittest discover -s Tools/ThirdPartyNotices/tests`）。generatorは再実行していない。入力の補完資料が変わっていないため、既存の標準条項草稿の内容は変わらない。
- 既存のbuild配下のファイル、`config/EmbeddedAppServer.json`、Sources／Store／scriptsは変更していない。

## 確認できなかったこと

- 上流保守者への問い合わせ結果（問い合わせていない）。
- objc2-foundationの0.3.2に対応する著作権者（HEADの記載は版が異なる）。
- debugserver-typesの埋込schemaの固定revision。
- fxhashが参照するRust `COPYRIGHT`のうち、2015年当時の版の内容。
- Apple SDK留保の法的帰結、MPL-2.0とApple標準EULAの関係。
- allocative系6件の版対応（D9）と、scope未確認9件（D11）。
- 実binaryに907件が含まれることの証明（source graph由来の保守的候補であり、証明ではない）。

## 2026-11-11 追加調査（D9・D11）

D9のMeta系6件とD11のscope未確認9件を、公開情報のGETだけで調べた。
取得物とhashは[`build/license-decision-check-20261111-2/`](../build/license-decision-check-20261111-2/)に保存した（SHA256SUMS.txtと[findings-20261111-2.json](../build/license-decision-check-20261111-2/findings-20261111-2.json)を含む）。
ここに書いた結論は根拠の整理であり、法的適合の断言ではない。
草稿は再生成していない。policy manifestへの反映は、承認後に別途行う。
`config/EmbeddedAppServer.json`は`not-ready`、草稿は`draft-not-approved`のままである。

### A. Meta系6件（D9）

6件とも、crates.ioの公開versionは現行manifestのversionと一致した。
版番号の差はない。
`.crate`に`.cargo_vcs_info.json`はなく、公開時のcommit SHAはregistry自身の記録としては得られなかった。
代わりに、repository（現在は`meta/buck2`。旧`facebook/buck2`は301で転送される）のpath履歴と、`.crate`内の全ファイルとのbyte比較を使った。
現行の根拠commit `4f1406c`（2026-05-22 13:53 UTC）は、6件のうち5件の公開より後である。
そのうちstatic_internerとstrong_hashでは、`4f1406c`の`Cargo.toml`が公開の`Cargo.toml.orig`と一致しない（依存の書き方などの差）。
公開直前にpathを最後に変更したcommitでは、6件とも`.crate`内の全ファイルがbyte一致した（`Cargo.toml.orig`を含む。`Cargo.toml`と`Cargo.lock`は生成物のため除外）。
root `LICENSE-APACHE`（`50e67517…780a`）、`LICENSE-MIT`（`da6d3703…8e93`）、`NOTICE`（`b3355ad3…982e`）は、公開時点のrepository tipでも現行草稿と同じhashだった。

| crate | 公開日時（UTC） | 公開直前にpathを最後に変更したcommit | 比較結果 | 結論 |
| --- | --- | --- | --- | --- |
| allocative 0.3.6 | 2026-05-20 19:53 | `1209cd7ca53158b33923d5d8d01ae5929026401e`（19:47、"Bump allocative and allocative_derive to 0.3.6"）。path `allocative/allocative` | 62ファイル一致 | 解消候補（根拠あり） |
| allocative_derive 0.3.6 | 2026-05-20 19:53 | `1209cd7…`（同上）。path `allocative/allocative_derive` | 4ファイル一致 | 解消候補（根拠あり） |
| lock_free_hashtable 0.1.4 | 2026-05-22 14:34 | `48ae5c61c93c808e0831b27104d3bc7262f06bd4`（13:35）。path `shed/lock_free_hashtable`。`4f1406c`もpath内容は同じ | 8ファイル一致 | 解消候補（根拠あり） |
| static_interner 0.1.2 | 2026-05-17 18:38 | `bb9114292d98db0a2919d37d673bb27f930e6aa1`（05-16、"Bump versions of crates to be published to crates.io"）。path `shed/static_interner` | 3ファイル一致。`4f1406c`では`Cargo.toml.orig`が不一致 | 解消候補（根拠あり）。`4f1406c`は不適 |
| strong_hash 0.1.0 | 2026-05-17 18:32 | `7ef58762149c23402d89f13af2cb293481ef950e`（04-23）。path `gazebo/strong_hash` | 6ファイル一致。`4f1406c`では`Cargo.toml.orig`が不一致 | 解消候補（根拠あり）。`4f1406c`は不適 |
| strong_hash_derive 0.1.0 | 2026-05-17 15:04 | `2f0651cacb701a8ca12df4c59468e44a2a2bfeec`（2025-08-24）。path `gazebo/strong_hash_derive` | 3ファイル一致 | 解消候補（根拠あり） |

各crateの`src`の全`.rs`ファイル（合計65件）の冒頭に「Copyright (c) Meta Platforms, Inc. and affiliates.」と、MITまたはApache-2.0の「either」を選べる旨のheaderがある（headerの無い`.rs`はなかった）。
display_containerのheader（「both」）とは文言が異なる。
allocativeとallocative_deriveは、公開`Cargo.toml`のlicenseが`Apache-2.0`である。
一方、公開`Cargo.toml.orig`は`license = { workspace = true }`で、公開直前のroot `Cargo.toml`の`workspace.package.license`は`MIT OR Apache-2.0`だった。
公開時に宣言が`Apache-2.0`へ書き換わった理由は確認できなかった。
他の4件は公開`Cargo.toml`も`MIT OR Apache-2.0`である。
各crate dirにLICENSE／NOTICEはなく、root `NOTICE`の内容（thiserror、complete_pty、probminhashの由来）は別pathの記述である。
`NOTICE`の適用範囲は、これまでどおり「保守的に保持」とし、適用を断言しない。

推奨：
- 6件の根拠commitを、上表のcommitへ差し替える（display_containerと同じ手法）。
- LICENSE／NOTICEの本文は変わらないため、草稿の本文はほぼ変わらないはずである。
- 差し替え後は、`historical-snapshot-scope-and-NOTICE-review-pending`のうち「別版のsnapshot」に由来する部分は外せる。
- copyright／NOTICEの適用レビューは未完のまま残す。

### B. scope未確認9件（D11）

9件はすべてgit依存で、mxc系3件はcrates.ioに存在しない（404）。
他の6件はcrates.ioに同名crateがある。
git依存のpinned commitと同一ではないため、crates.ioのcrateは「同じupstreamでのlicense配置の傍証」としてだけ使った。
pinned commitのファイルはraw取得し、手元のcargo git checkoutとbyte一致を確認した。

| crate | 根拠 | 結論 | 残る留意点 |
| --- | --- | --- | --- |
| mxc_config_contract 0.8.0 | manifestは`license.workspace = true`、`src/Cargo.toml`の`workspace.package.license`は`MIT`。root `LICENSE.md`はMITで"Copyright (c) Microsoft Corporation"（`d9a1b1e3…f1cb`）。READMEは「See LICENSE.md」。`.rs` 95件すべてにMicrosoftのMIT header | 解消候補（根拠あり） | crate dirにLICENSEはない。root `LICENSE.md`はMIT本文の各行が4スペース字下げされている |
| mxc_telemetry 0.8.0 | 同上。`.rs` 3件すべてにheader | 解消候補（根拠あり） | 同上 |
| wxc_common 0.8.0 | 同上。`.rs` 61件中58件にheader | 解消候補（根拠あり） | headerの無い3件（`tests/proxy_env_spec.rs`、`src/test_env.rs`、`src/network_parser_loopback_spec_tests.rs`）にも、別license表示や第三者由来の記述は見つからなかった |
| rmcp 3.5.1 | `workspace.package.license = "Apache-2.0"`。crates.io 3.5.1の`path_in_vcs`は`crates/rmcp`（commit `79437f2`）。READMEが「repository's LICENSE（`../../LICENSE`）」を参照する。root LICENSE（`0382b005…be58a`）は`79437f2`とpinned `4048ac4`でbyte同一 | 解消候補（根拠あり）。ただしQ15の確認が必要 | LICENSEは冒頭で「MITからApache-2.0へ移行中」と述べ、移行同意の無い寄与はMITのままと書く。Apache-2.0全文とMIT全文（"Copyright (c) 2024-2025 Model Context Protocol a Series of LF Projects, LLC"）を含む。manifest宣言はApache-2.0のみ |
| rmcp-macros 3.5.1 | rmcpと同じ（`path_in_vcs`は`crates/rmcp-macros`、READMEが`../../LICENSE`を参照） | 解消候補（根拠あり）。Q15 | 同上 |
| tokio-tungstenite 0.28.0 | fork（`openai-oss-forks`）はrepo root単一package。manifestは`MIT`。root `LICENSE`（`fdd55e2b…bc8f`）はcrates.io 0.28.0のLICENSEとbyte同一。upstream crateの`path_in_vcs`は空（repo root） | 解消候補（根拠あり） | forkでOpenAIが加えた変更の著作権表示は、repositoryのtop levelに見つからなかった。無いこと以上は確認していない |
| tungstenite 0.27.0 | forkはrepo root単一package。manifestは`MIT OR Apache-2.0`。`LICENSE-APACHE`（`a60eea81…59f2`）と`LICENSE-MIT`（`7fea0ee5…033f`）はcrates.io 0.27.0と同名fileがbyte同一 | 解消候補（根拠あり） | 同上 |
| nucleo 0.5.0 | manifestは`MPL-2.0`。root `LICENSE`（MPL-2.0、`1f256eca…f1d5`）。crates.io 0.5.0（`path_in_vcs`は空）も同hashのLICENSEを同梱 | 解消候補（根拠あり）。Q16の確認が必要 | `src/boxcar.rs`冒頭に「Adapted from the `boxcar` crate ... under MIT」「Copyright (c) 2022 Ibraheem Ahmed」とMIT本文がある。`src/par_sort.rs`冒頭に「Copyright (c) 2010 The Rust Project Developers」と許諾本文がある。現行草稿のnucleoはroot LICENSEのみで、これらは含まれていない |
| nucleo-matcher 0.3.1 | manifestは`MPL-2.0`。crates.io 0.3.1の`path_in_vcs`は`matcher`で、crate内にLICENSE（`1f256eca…f1d5`）を同梱する。gitでは`matcher/LICENSE`が`../LICENSE`へのsymlink | 解消候補（根拠あり） | `matcher/src`に第三者copyrightの記述は見つからなかった。`chars/case_fold.rs`はucd-generate（Unicode 15.0.0）の生成物で、file内にlicense記述はない |

「標準条項併記で対応」に分類したcrateはなかった。
「未解決」に分類したcrateもなかった。
ただし、解消候補とした根拠は「LICENSEの配置と宣言の対応」であり、copyright holderの網羅や、配布義務を満たしたことの確認ではない。
各crateの`distribution-applicability-copyright-NOTICE-review-pending`は、この調査では外せない。

### 人間が決めること

| ID | 質問（はい／いいえ） | 推奨 | 理由 |
| --- | --- | --- | --- |
| Q12 | Meta系6件の根拠commitを、上表のcrateごとの公開時点commitへ差し替えるか | はい | `4f1406c`は5件で公開より後であり、2件でmanifestが公開版と一致しない。差し替え先は全ファイルbyte一致で、LICENSE／NOTICEのhashは変わらない |
| Q13 | allocative／allocative_deriveの宣言差（`Apache-2.0`と`MIT OR Apache-2.0`）を、宣言を書き換えず両方併記する現行構成のままにするか | はい | 公開manifestの値を隠さず、repositoryとheaderの記述も併記できる。どちらを採用するかの選択は記録しない |
| Q14 | mxc系3件、tokio-tungstenite、tungstenite、nucleo、nucleo-matcherのscope未確認を、上の根拠で解消済みと記録するか | はい | 各crateのLICENSE配置、manifestの宣言、source headerまたはupstream crateの`path_in_vcs`が一致した |
| Q15 | rmcp／rmcp-macrosは、移行中の注記とMIT全文を含むLICENSEを原文のまま表示するか | はい | 注記を要約や選択で置き換えない方が、宣言との差を隠さない |
| Q16 | nucleoの表示に、boxcarとRust Project Developersのheader本文を加えるか | はい | 現行草稿はroot LICENSEだけで、実在するfile内の第三者表示が表示から漏れている。加える場合は改変せず`source-header`として扱い、holderや年を補作しない |

Q14に含めなかった点：rmcpの2件はQ15、nucleoのboxcarとpar_sortの扱いはQ16で別に決める。
nucleo-matcherに第三者copyright記述は見つからなかったが、網羅の保証ではない。

### 今回確認できなかったこと

- Meta系6件の`.crate`は`.cargo_vcs_info.json`を持たず、公開時に実際に使われたcommit SHAは確認できなかった。上表はpath履歴とbyte比較による推定である。
- allocative系の公開manifestが`Apache-2.0`となった理由。
- mxc系3件は、crates.io上のpackageが無く、公開版との照合はできなかった（pinned commitのgit blobだけで確認した）。
- forkのtungstenite、tokio-tungsteniteが、upstream crateから加えた変更の範囲（license fileがupstream crateとbyte同一であることしか確認していない）。
- rmcpのLICENSEが言及する「relicensing同意を得ていない寄与」が、pinned commitのどの部分にあたるか。
- nucleoの`boxcar.rs`／`par_sort.rs`が、現在のupstreamでも同じ表示を保っているか（pinned commitのみ確認）。
- Unicodeデータ由来の生成物（nucleo-matcherの`case_fold.rs`）に、別のlicense表示が要るか。
- 上流の保守者への問い合わせ（行っていない）。GitHub APIのrate limitには達しなかった。

### 今回のネットワーク確認の概要

- crates.io API：crate情報15件とversion情報12件。`.crate`の取得12件（SHA-256はAPIのchecksumと一致）。mxc系3件は404。
- GitHub API：commit情報、path履歴（公開前後、各path）、repository tip、contents一覧、repository情報で約30件。認証なし、rate limitには達していない。
- raw.githubusercontent.com：Meta系6件の比較用ファイル（約190件）、LICENSE／NOTICE、9件のscope確認用ファイル。
- HEAD／GET確認：旧`facebook/buck2`と現`meta/buck2`のURLが、ともにHTTP 200（記録は`head-checks-20261111-2.tsv`）。
- `.crate`の展開は、symlink、絶対パス、`..`を含むmemberを拒否する方式で行い、新規の空directoryへ展開した。取得物内のscript、`build.rs`は実行していない。`cargo build`も実行していない。
- 既存の`build/`配下、`config/EmbeddedAppServer.json`、Sources／Store／scriptsは変更していない。
