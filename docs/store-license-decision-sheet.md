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
- [x] Q12：Meta系6件（D9）の根拠commitを、4f1406cからcrateごとの公開時点commit（下の表）へ差し替える補完manifestを作る方針を承認するか。 2026-11-11 ユーザー承認（「推奨どおりでOK」との回答）
- [x] Q13：allocativeとallocative_deriveは、公開manifestの宣言`Apache-2.0`をそのまま表示し、repositoryの`MIT OR Apache-2.0`とsource headerのdual-license記述も併記する現行構成のままでよいか。 2026-11-11 ユーザー承認（「推奨どおりでOK」との回答）
- [x] Q14：mxc系3件、tokio-tungstenite、tungstenite、nucleo、nucleo-matcherの`repository-license-scope-unreviewed`を、下の根拠で解消済みと記録するか。 2026-11-11 ユーザー承認（「推奨どおりでOK」との回答）
- [x] Q15：rmcpとrmcp-macrosは、MIT移行中の注記とMIT全文を含むroot LICENSEを原文のまま表示する構成でよいか。 2026-11-11 ユーザー承認（「推奨どおりでOK」との回答）
- [x] Q16：nucleoの表示に、`src/boxcar.rs`と`src/par_sort.rs`の冒頭にある第三者copyrightとpermission本文を、source headerとして加えるか。 2026-11-11 ユーザー承認（「推奨どおりでOK」との回答）

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

### Q12〜Q16の承認と反映（2026-11-11）

Q12〜Q16も、2026-11-11にユーザー（人間）が「推奨どおりでOK」と回答して承認した。
承認は方針の承認であり、最終本文の承認でも、承認receiptの発行でもない。
`config/EmbeddedAppServer.json`の`distributionStatus`は`not-ready`のままで、草稿は`draft-not-approved`のままである。
各crateの`distribution-applicability-copyright-NOTICE-review-pending`は外していない。

反映した成果物は次のとおりである。

- policy manifest：[`build/license-policy-supplement-20261111-2/manifest.json`](../build/license-policy-supplement-20261111-2/manifest.json)に、Q2・Q3・Q5の内容を引き継いでQ12〜Q16を加えた。
- 新草稿：[`build/third-party-notices-app-server-draft-20261111-2/`](../build/third-party-notices-app-server-draft-20261111-2/validation.json)に、907 component、496本文で生成した。
- Q12：Meta系6件の根拠commitを`4f1406c`からcrateごとの公開時点commitへ差し替えた。`.crate`の公開memberのうち生成物（`Cargo.toml`、`Cargo.lock`）を除く全件が、固定commitのfileとbyte一致することを生成器が確認する。LICENSE-APACHEとLICENSE-MITのbytesは従前と同じである。
- Q12の注意：strong_hash_deriveの公開時点commit（`2f0651c`）のroot NOTICE（227 bytes、`4d21d639…`）は、従前の`4f1406c`のNOTICE（`b3355ad3…`）と異なる。probminhashに関する段落がない。この表の「LICENSE／NOTICEの本文は変わらない」は、この1件には当てはまらなかった。草稿は、承認したcommitのbytesのとおり、strong_hash_deriveに古い方のNOTICEを表示する。
- Q12の扱い：履歴の記録と`historical-snapshot-scope-and-NOTICE-review-pending`は残した。NOTICEの適用範囲のレビューが未完のためである。
- Q13：allocativeとallocative_deriveは、公開manifestの`Apache-2.0`とrepository workspaceの`MIT OR Apache-2.0`を、`declarationRecord`として両方記録した。宣言は書き換えず、どちらも選択していない。公開本文は変えていない。
- Q14：mxc系3件、tokio-tungstenite、tungstenite、nucleo、nucleo-matcherの`repository-license-scope-unreviewed`を、`scope-resolution-recorded-by-approved-policy`へ置き換えた。根拠は、保存したmanifestの宣言、LICENSEの配置、公開crateとのbyte一致である。
- Q15：rmcpとrmcp-macrosも同じ記録にした。MIT移行中の注記とMIT全文を含むroot LICENSEは、原文のまま表示している。
- Q16：nucleoに、`src/boxcar.rs`（22行）と`src/par_sort.rs`（32行）の先頭のコメント領域を、改変せずsource headerとして加えた。par_sort.rsは、先頭の`//!`の説明（std由来であること、nucleoでの改変）と空行を挟んだcopyright部分を、領域としてまとめて含む。boxcar.rsの原文にある綴り（`licenes`）もそのままである。holderと年は補作していない。
- 旧草稿20261111との差分は、上記15 componentだけである。`validation.json`に、component数、本文数、text参照のhashとsize照合を保存した。

Q14・Q15の「解消」は、LICENSEの配置と宣言の対応を記録したという意味である。
copyright holderの網羅、配布義務の充足、NOTICEの適用は、確認していない。
mxc系の`.rs`のheader件数など、一部の観察は記録のみで、生成器は再検証していない。

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
（追記：Q12〜Q16の承認後に反映した。上の「Q12〜Q16の承認と反映」を参照。この行は調査時点の記録として残す。）
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

## 最終本文の承認（2026-11-11）

ユーザー（人間）が2026-11-11にチャットの質問カードで、最新草稿を最終版として承認した。
承認範囲は、Q1〜Q16の方針と、THIRD-PARTY-NOTICESおよびSOURCE-AVAILABILITYの最終本文である。
各crateの義務レビューは「方針どおり」として扱う。これは法的適合を断言するものではない。
source提供依頼への回答期間は「30日以内」と決めた。
最終版と承認receiptは新規directory `build/store-approved-inputs-20261111/` に置いた。
草稿からの変更は、draft-not-approved等の状態表示の置換と、回答期間のプレースホルダ置換だけである（差分は同directoryの`DRAFT-TO-FINAL.diff`）。
元の草稿は変更していない。

| 対象 | SHA-256 |
|---|---|
| THIRD-PARTY-NOTICES.txt（元草稿 fd9561946bc9f58bf9431a6714fda951ed83ae8233c8afe5a4955b9eff3c82bc） | e2a9f491303eef16bf2445bec44403b31584e89cb4623b50d391616362a9fd85 |
| SOURCE-AVAILABILITY.txt | f1dbf07f4a0bd3a3a189137503a7892149caa610df21dc20e9690033f5c3ce6f |
| approval.json（receipt） | d496463a12754dddff688f872682423fe7775ce596c765c7f63ac1022397f500 |
| config/EmbeddedAppServer.json（ready後） | 165371917e5eab3098db9e8d0b48b73f020b6eb0aaeaf8c8dcc0175e5321f2c2 |

`config/EmbeddedAppServer.json`は`distributionStatus: ready`、`noticeAudit`と`transitiveLicenseAudit`を`approved-by-project-owner-2026-11-11`に更新した。
telemetry系の3つのauditは`incomplete`のまま変更していない。

## 2026-11-13 helper 0.167.2 更新に伴う再生成

同梱helperを0.163.0から公式`rust-v0.167.2`へ更新するため、notices草稿とsource案内の草稿を0.167.2用に作り直した。
2026-11-11に承認された最終本文（`build/store-approved-inputs-20261111/`）は0.163.0用であり、0.167.2のhelperには使えない。
最終本文の再承認が必要である。
承認receiptは発行していない。
`config/EmbeddedAppServer.json`は編集していない。
新草稿は`draft-not-approved`、`distributionStatus`は`not-ready`である。
ここに書く結論は根拠の整理であり、法的適合の断言ではない。

### 固定した版と入力

- GitHub APIで`rust-v0.167.2`を確認した。tag objectは`08a3b12b3298577534a28b62ed976acf8de66eda`（annotated tag）、commitは`ce21072c90d32c40af7a55b60b2fb35c84a43a6a`である。
- codeloadのtar.gz（19,116,043 bytes）のSHA-256は`11e3321cd1a158dcfd920f8d24b07a08e896b9eaa7f4800f3042227b56342170`で、`build/helper-upgrade-0.167.2/`の別担当の取得物と一致した。
- 取得物は[`build/dependency-audit/codex-0.167.2/`](../build/dependency-audit/codex-0.167.2/)に置いた（source-audit-ce21072c、rust-toolchain-audit-1.95.0/results）。
- 依存集合は0.163.0と同じ方法で作った。`cargo metadata`と`cargo tree --edges normal,build`（`--target aarch64-apple-darwin --locked --offline`）の結果から、source graph由来の保守的候補を出した。
- 実行したcargoは`metadata`と`tree`だけである。`cargo build`、build script、proc-macroは実行していない。
- 初回の`cargo metadata`だけネットワークを使い、crates.ioとgit依存のmetadataとsourceを新規のcargo-homeへ取得した。
- `v8`は0.167.2で`[patch.crates-io]`のgit依存（`seanh-oai/rusty_v8`）になった。submodule取得を避けるため、scratch copyでは同一commitのcodeload展開へのpathに差し替えて解決し、lockとpackage idはgit形式へ戻した。差し替え以外のlockの差分は、path crateのversion同期（`0.0.0`から`0.167.2`）だけである。
- Cargo.lockは1479 package（registry 1296、path 171、git 12）で、registryのversion・checksumの組は0.163.0と同数の1296件である。
- 依存の差分一覧は[`dependency-diff-0.163.0-to-0.167.2.json`](../build/dependency-audit/codex-0.167.2/dependency-diff-0.163.0-to-0.167.2.json)に保存した。

### 依存差分の要約

| 集合 | 0.163.0 | 0.167.2 |
| --- | --- | --- |
| app-server | 907 | 934 |
| code-mode-host | 543 | 585 |
| release union（2 binary） | 936 | 964 |

app-server集合の内訳は次のとおりである。

| 区分 | 0.163.0 | 0.167.2 | 追加 | 削除 |
| --- | --- | --- | --- | --- |
| 外部（registry・git） | 791 | 812 | 80 | 59 |
| Codex path crate | 116 | 122 | 7 | 1 |

- 新規の名前は15件である（cmov、cpubits、ctutils、flatbuffers、gix-macros、gix-parallel、gix-zlib、jiff-core、libbz2-rs-sys、lzma-rust2、mxc-sdk、objc2-security、sha1dc、typed-path、widestring）。
- 消えた名前は9件である（gix-features、lzma-rs、lzma-sys、maybe-async、mxc_config_contract、mxc_telemetry、sha1-checked、wxc_common、xz2）。
- 版が変わった名前は63件で、そのうちgix系が36件である。aes、cipher、digest等は旧版が残り、新版が加わった。
- 同じ版で固定revisionだけ変わったのは、rmcpとrmcp-macros（`4048ac4`から`98a5478`）である。
- lzmaは、`xz2`、`lzma-sys`、`lzma-rs`が消え、`lzma-rust2 0.21.0`（Apache-2.0）が入った。
- 同名crateの宣言ライセンスが変わった件はない。
- 追加80件のうち、本文候補は75件がcrate内に、flatbuffersとobjc2-securityの2件が上流の固定commitにある。mxc-sdk、rmcp、rmcp-macrosの3件はgit repositoryのLICENSEである。
- 追加のうち`v8`（git fork）と`deno_core_icudata 0.78.0`はcode-mode-hostだけの集合に入り、app-server集合の外である。

### ライセンス上の確認結果（app-server集合）

| 観点 | 結果 |
| --- | --- |
| 全文候補なし | 新規なし。既存の5件（debugserver-types、eventsource-stream、fxhash、io_tee、objc2-foundation）は同じ版のまま、標準条項の併記で変わらない。 |
| OR選択 | 新規のOR宣言は67件で、すべて寛容なライセンス同士である。新しい組み合わせは`CC0-1.0 OR MIT-0 OR Apache-2.0`（constant_time_eq 0.4.2）だけである。`Apache-2.0 OR GPL-2.0-only`は既存のself_cellだけで、Q5の方針のまま変わらない。 |
| copyleft | MPL-2.0の12候補（nucleo、nucleo-matcher、option-ext、symphonia系9件）は同じ版・同じ固定sourceのままである。GPL、LGPL、EPL等の単独宣言の新規はない。 |
| NOTICE必須 | 第三者の新規NOTICEファイルは見つからなかった。noticeまたはcopyright参照は145件から151件に増えたが、増分6件はCodex rootのNOTICEを共有する新規path crateである。gix-trace 0.3.0には、派生元tracing-forestのMIT帰属を記す`LICENSE-MIT-tracing-forest`が同梱され、全文候補として表示される。 |
| SDK留保 | objc2-security 0.3.2が新規である。固定commit `7b1abfd`の`LICENSE.md`は、objc2-app-kit等と同じ文面である（同じファイルのbytesを再利用し、GitHubのblob shaと照合した）。 |
| 版差（historical snapshot） | 新規なし。既存の11件は版が変わらず、`historical-snapshot-scope-and-NOTICE-review-pending`を維持している。 |
| repository-license-scopeの未確認 | 新規のgit依存3件（mxc-sdk、rmcp、rmcp-macros）をQ14・Q15と同じ根拠の取り方で記録した。open issueは0件である。 |
| その他の新規ライセンス種別 | bzip2-1.0.6（libbz2-rs-sys、crate内にLICENSE）とCC0-1.0、MIT-0（constant_time_eq）が新しい。lzma-rust2は「tukaani xz for java」からの移植と説明されるが、crateに移植元の帰属表示は同梱されていない。 |

### 承認済み方針の引き継ぎ状況

- policy manifestは[`build/license-policy-supplement-20261113/manifest.json`](../build/license-policy-supplement-20261113/manifest.json)である。作成手順は同directoryの`record-scripts/make_manifest.py`に記録した。
- Q1（標準条項の併記）：対象6件は同じ版・同じcrate checksumのまま引き継いだ。標準条項のmanifestは`standard-license-supplement-20261113`に、同じ本文のコピーとして置いた。
- Q2（display_container 0.9.0）、Q3（fxhash）、Q5（self_cell）、Q12（Meta系6件）、Q13（allocative系）、Q16（nucleo）は、crateの版が同じなので、そのまま引き継いだ。版固有の根拠（公開日と同日commit、byte一致）は、版が変わっていないため再確認していない。
- Q4・Q6・Q7・Q10：現行の構成を維持した。NOTICEの参照は、上の表のとおり増えた。
- Q14：mxc系3件（mxc_config_contract、mxc_telemetry、wxc_common）は0.167.2の集合から消えた。代わりにmxc-sdk 1.0.0を、同じ根拠の取り方（manifestの宣言、root `LICENSE.md`の配置、workspace継承の解決）で記録した。root `LICENSE.md`は0.163.0の固定commitのものとbyte一致した。
- Q15：rmcpとrmcp-macrosは新しい固定revision `98a5478`で再確認した。root `LICENSE`（MIT移行中の注記、Apache-2.0本文、MIT本文）は旧revisionとbyte一致し、`mustContain`の2文も通った。
- Q8・Q9・Q10・Q11：source案内で扱う。MPL-2.0の12候補は変わらない。
- 新草稿から0.163.0固有の記述を外した。path crateのrecorded-size-unavailableは、サイズを記録したので解消した（232件が0件）。

### 生成結果

- notices草稿：[`build/third-party-notices-app-server-draft-20261113/`](../build/third-party-notices-app-server-draft-20261113/validation.json)。934 component、504本文、noticeまたはcopyright参照151件、全文候補なし5件、標準条項6 component・10参照である。
- `THIRD-PARTY-NOTICES.draft.txt`は2,162,660 bytes、SHA-256は`309dc8a72a47deed599efb22c353bbb55099af4a4a2c2fa3d6bb66d88a6559ee`である。
- 旧草稿20261111-2と比べて、共通のcomponentでtext・issue・宣言が変わったものは0件である。path crateの差は、recorded-size-unavailableの解消だけである。
- 1743のtext参照が504本文のいずれかと一致し、1747の証拠fileのhashとsizeを再計算して照合した。local pathの混入はない。
- source案内の改訂草稿：[`build/source-availability-draft-20261113/`](../build/source-availability-draft-20261113/validation.json)。窓口はGitHub Issue、回答期間は30日以内（改訂3で承認済みの文言を引き継ぎ、改訂4は未承認と明記）、Codexは0.167.2とcommit `ce21072c`に更新した。SHA-256は`7c1f37bb1e528267876b9cc42c625cfeb5d8c89e39927ed5a9481fdd5e1e5a76`である。
- 生成器の改修は最小限である。`Tools/ThirdPartyNotices/helper_update.py`を追加し、`generate_policy_draft.py`に`--inputs helper-0.167.2`を加えた（既定は従来どおり）。fixtureは58件に11件を加えた69件が成功した。

### 新たに人間の判断が要る項目

- [x] Q17：objc2-security 0.3.2（新規）にも、Q4と同じ扱い（Apple SDK留保を原文のまま表示し、残余リスクを受け入れる）を適用するか。 2026-11-13 ユーザー承認
- [x] Q18：新しいcrateのライセンス種別（CC0-1.0、MIT-0、bzip2-1.0.6、gix-traceの派生元MIT帰属）にも、Q6・Q7と同じ扱いを適用するか。 2026-11-13 ユーザー承認
- [x] Q19：lzma-rust2 0.21.0の移植元の帰属を、公開情報だけで追加調査するか。 2026-11-13 ユーザー承認（調査を依頼。結果は下の節）

Q17〜Q19が「いいえ」の場合の扱いは、回答を受けてから決める。
上記以外に、新たな判断が必要な項目は見つからなかった。
最終本文の再承認（THIRD-PARTY-NOTICESとSOURCE-AVAILABILITYの0.167.2版）は、Q17〜Q19とは別に必要である。

### 確認できていないこと

- 934件が実binaryに含まれることは、証明していない。source graph由来の保守的候補である。
- 参考として、0.167.2のapp-server binary（別担当の取得物）の文字列を数えた。lzma-rust2は24件、gix-zlibは5件、jiff-0.2.38は20件、zip-9.0.0は7件に一致した。v8、mxc-sdk、flatbuffers、objc2-securityは0件である。これは含有の証明でも除外の証明でもない。
- code-mode-host専用の追加（v8のgit fork、deno_core_icudata 0.78.0）は、app-server集合の外とした。0.163.0と同じ扱いで、配布tar.gzにcode-mode-hostが含まれるかは確認していない。
- deno_core_icudata 0.78.0とv8のgit forkには、上流の追加取得をしていない。
- flatbuffers 25.12.19は、crate内にlicenseがなく、固定commitのroot `LICENSE`（Apache-2.0）を上流候補とした。`rust/flatbuffers`配下に別のlicenseはない（GitHub APIの一覧で確認）。適用範囲のレビューは未完で、`upstream-candidate-applicability-unreviewed`を付けた。
- 版が同じでも、新しいversion固有のNOTICEやcopyrightが他にあるかは網羅していない。
- 新規のregistry crate 77件について、`.crate`内の名前による候補だけを集めた。READMEやsource headerのcopyright表示は、既存の方針（Q3・Q16）の対象を除き、探していない。
- 既存の`build/`配下、`build/store-approved-inputs-20261111/`、`config/EmbeddedAppServer.json`、`Tools/StorePackaging/`、Sources、Store、scripts、siteは変更していない。

### 2026-11-13 Q17〜Q19の承認と反映

Q17とQ18は、2026-11-13にユーザー（人間）が承認した。Q19は調査の実施を依頼された。
承認は方針の承認であり、最終本文の承認でも、承認receiptの発行でもない。
最終本文の再承認は未了である。`config/EmbeddedAppServer.json`は編集していない。
Q17とQ18は、既存の扱いの適用であり、草稿の本文は変わらない。

反映した成果物は次のとおりである。

- policy manifest：[`build/license-policy-supplement-20261113-2/manifest.json`](../build/license-policy-supplement-20261113-2/manifest.json)。20261113にQ17・Q18の承認記録とQ19の`attributionReviews`を加えた。
- 新草稿：[`build/third-party-notices-app-server-draft-20261113-2/`](../build/third-party-notices-app-server-draft-20261113-2/validation.json)。934 component、504本文、`THIRD-PARTY-NOTICES.draft.txt`は2,162,660 bytes、SHA-256は`309dc8a72a47deed599efb22c353bbb55099af4a4a2c2fa3d6bb66d88a6559ee`である。
- 20261113の草稿とtxtはbyte一致する。差は、lzma-rust2の`attributionReview`が内部manifestに加わった1 componentだけである。
- 生成器に`attributionReviews`節を加えた（記録のみで、本文は加えない）。fixtureは71件が成功した。

#### Q19の調査結果：lzma-rust2 0.21.0の移植元の帰属

結論：調べた範囲では、追加で表示すべき帰属は見つからず、本文は加えなかった。表示が望ましいと判断できる根拠もなかった。

- crate内（README.md、src/lib.rs、Cargo.toml）は、「tukaani xz for javaからの移植」と、「unmaintainedなlzma-rust crateのfork」と書くだけである。移植元の版、著作者、ライセンスは書いていない。
- crateのsource fileにcopyright headerはなく、crateの`LICENSE`はApache-2.0の原文で、copyright holderの行がない。上流のcommit `7405a770`のroot `LICENSE`と同一である。
- tukaani.orgのXZ for Javaのページ（2026-11-13取得）は、1.10以降が0BSD、1.9以前がpublic domainと述べる。
- xz-javaの`COPYING`は0BSDの本文で、著作権表示や許諾表示の保持を条件としない。
- 以上から、保持を求める表示がcrateにもXZ for Java側にも見つからない。XZ for Javaの`COPYING`は、このpackageに含まれず、移植した版も不明なので、補作を避けて加えなかった。
- 根拠のファイルとhashは[`build/license-decision-check-20261113-lzma/`](../build/license-decision-check-20261113-lzma/)に保存した。manifestの`attributionReviews`は、crateの記述の存在とこれらのhashを生成時に照合する。

残る未確認点は次のとおりである。

- どの版のXZ for Javaから移植したかは、確認できなかった。そのため、移植部分にpublic domainと0BSDのどちらが当たるかは確定していない。
- forkの元のlzma-rust crateは調べていない。そのcopyright holderとライセンスは記録していない。
- BCJ filter、CRC、lzip等に別の出所があるかは調べていない。
- 法的結論ではない。各crateの配布時の適用、copyright、NOTICEのレビューは未完である。

## 最終本文の承認（2026-11-13、0.167.2）

ユーザー（人間）が2026-11-13にチャットで、helper 0.167.2版のライセンス表記とsource案内の最終本文の承認を求められ、「承認する」と回答した。
承認範囲は、Q1〜Q19の方針と、THIRD-PARTY-NOTICESおよびSOURCE-AVAILABILITYの最終本文である。
各crateの義務レビューは「方針どおり」として扱う。これは法的適合を断言するものではない。
source提供依頼への回答期間は「30日以内」のままである。
最終版と承認receiptは新規directory `build/store-approved-inputs-20261113/` に置いた。
草稿からの変更は、draft-not-approved等の状態表示の置換と、回答期間のプレースホルダ置換だけである（差分は同directoryの`DRAFT-TO-FINAL.diff`）。
元の草稿と、2026-11-11の最終版は変更していない。

| 対象 | SHA-256 |
|---|---|
| THIRD-PARTY-NOTICES.txt（元草稿 309dc8a72a47deed599efb22c353bbb55099af4a4a2c2fa3d6bb66d88a6559ee） | 66819664b32d2effad869e3ecea40f00b0020026e4a1581a25b71ae9221e7b59 |
| SOURCE-AVAILABILITY.txt（元草稿 7c1f37bb1e528267876b9cc42c625cfeb5d8c89e39927ed5a9481fdd5e1e5a76） | 815c7c4c28875d30cb9dae9fa02737d0c3f077ce2719ef8296fbbaef4bb1d64c |
| approval.json（receipt） | 742d9fe9acfef0c4d2abaea272fef0050501d66c7cdf0afddddaea208a778c4e |
| config/EmbeddedAppServer.json（ready後） | 0c449249e2be439158123ac0389dbff6a6981c84693798e9a08bf9569523494a |

`config/EmbeddedAppServer.json`は`distributionStatus: ready`、`noticeAudit`と`transitiveLicenseAudit`を`approved-by-project-owner-2026-11-13`に更新した。
telemetry系の3つのauditは`incomplete`のまま変更していない。
