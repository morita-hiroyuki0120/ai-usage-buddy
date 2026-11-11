# Store向けライセンス残件8件の確認案

確認日：2026-10-24。
対象は固定Codex 0.163.0の収集済み資料とnotices草稿-3であり、配布承認や法的適合の確定ではない。
日本語技術文書スキルに従い、収集の事実、適用範囲の未確認、配布者の判断を分けて記録した。

## 草稿の対象と不足件数

[草稿manifest][draft]の実数は936 components、507 unique texts、全文候補なし8件である。
対応する草稿本文SHA-256は`03ac362b996adf9b221da106cddd82bdda5b89dc7121772be23c55d99b863fa2`。
ここでいう「全文候補なし」は生成器の`license-text-candidate`に該当する資料がないという集計であり、「宣言ライセンス不明」「配布禁止」を意味しない。
display_containerのように、実本文を取得していても対象版への適用確認が残るため、この集計に入る例もある。

[対象graph][graph]はapp-server単独907、code-mode-host単独543、releaseUnion936を記録する。
releaseUnionは公開同時2バイナリbuildを参照した、2 rootの保守的な近似feature unionであり、936件が実binaryに含まれる証明ではない。
今回の同梱対象はapp-server単独であり、残8件のうちV8とdeno_core_icudataはunionのみ、他6件はapp-server候補に入る。
将来、既存936草稿を保護したままappServer907の別草稿を生成する判断は可能だが、収集対象の縮小と実binaryの含有断定は分ける。
初回分類時点では生成器も草稿も変更していない。
その後の単独scopeと標準条項の実装結果は末尾に区別して記録する。

## 8件の分類と次の確認先

宣言欄は公開crate manifestの値を保持する。
補完資料の`explicit-missing`は資料収集上の状態であり、宣言そのものの否定ではない。
以下の確認依頼は未送信であり、返答を取得済みとは扱わない。

| Component／対象 | 宣言 | 保存済み証拠と残る論点 | 解決案と確認先 |
| --- | --- | --- | --- |
| objc2-foundation 0.3.2／app-server | `MIT` | [補完-2][s2]のcrate VCS固定commit `7b1abfd750a2cacaea71d6a56ecfb83cb7de560b`。root `LICENSE.md`は当該packageをMITと指定するが、MITの許諾全文ではなくApple SDK由来の留保も記す。調べた浅いdirectory範囲でNOTICEは未発見。 | 標準MIT本文の併記は候補だがSDK留保は解消しない。配布者が当該留保と適用するSDK条件を確認し、必要ならmadsmtm/objc2の保守者へ0.3.2の適用範囲と付属noticeを問い合わせる。 |
| debugserver-types 0.5.0／app-server | `MIT` | [補完-3][s3]のVCS固定commit `d444f163123af5b4fbce7375d1afead7e9b8a224`の全9 tree entriesに全文候補なし。crateとの5ファイル比較は改行正規化後一致。生成元DAP schemaのREADME参照は固定revisionを示さない。 | 標準MIT本文を別役割で添える案と、schemaの出所確認を分離する。Marwes/debugserver-typesの保守者へ埋込schemaのrevisionと付属license／noticeを確認する。manifest authorsからcopyrightは作らない。 |
| display_container 0.9.0／app-server | `MIT OR Apache-2.0` | [補完-3][s3]の歴史snapshot `e867865433b6ca061f347ea4275e03faf8f8389c`からMITとApacheの実全文、Metaの実headerを取得済み。Rust sourceは一致するがsnapshot manifestは0.8.1。headerの「both」とmanifestのORも併存する。 | 新しい標準本文の取得より、保存済み本文の0.9.0への適用確認を優先する。Meta/Gazeboの保守者へ版差とboth／ORの意図を確認し、配布者が採用する条件を記録する。両全文と実headerは保持する。 |
| eventsource-stream 0.2.3／app-server | `MIT OR Apache-2.0` | [補完-3][s3]のVCS固定commit `3d46f1c758f9ee4681e9da0427556d24c53f9c01`の全18 tree entriesに本文候補なし。11対応ファイルはbyte一致。manifestとREADMEには宣言がある。 | 標準本文を添える案を配布者が検討し、ORの採用経路は生成器が推測しない。必要な上流確認はjpopesculian/eventsource-streamへ、0.2.3に付属する本文やnoticeが別途あるかを具体的に問い合わせる。 |
| fxhash 0.2.1／app-server | 原文`Apache-2.0/MIT` | [補完-3][s3]の歴史snapshot `537570af68de22d2f4bbdd5bee5d6e07268e6f42`と全Rust sourceがbyte一致。実`lib.rs` headerにはRust Project Developersのcopyright、ApacheまたはMITを選べる記述、Rust `COPYRIGHT`参照があるが、参照先資料は未収集。元VCS復元とは区別する。 | raw宣言を保持し、headerにある選択根拠を別記する。cbreeden/fxhashの保守者へ元Rust revisionと対応COPYRIGHTを確認し、配布者が条件と付属noticeを整理する。現在のRust本文や年を過去版へ推測適用しない。 |
| io_tee 0.1.1／app-server | `MIT OR Apache-2.0` | [補完-3][s3]のVCS固定commit `8a7adecebf3429cbc58a0368751d1851dfaf58ed`。sourceと元manifestがbyte一致し、READMEに選択可能な宣言があるが固定snapshotに実全文候補なし。 | eventsource-streamと同様に、宣言を根拠とする標準本文の併記を配布者が検討する。必要ならTheOnlyMrCat/io_teeへ0.1.1の付属本文とnoticeの所在を確認する。見つからない著作権者や年を補作しない。 |
| v8 150.4.0／unionのみ | crateは`MIT` | [lock inventory][lock]と一致するarchiveのSHA-256を今回再確認。`Cargo.toml.orig`は`LICENSE*`等の除外を記録し、`src/lib.rs`にはDenoの実copyright headerがある。VCS情報は`5c15a6995c9bb4bacd3e341b59fff32c909c80bf`、`dirty:true`。草稿はHighwayのcopyright資料を保持するが全文候補はない。 | まず配布者がapp-server単独草稿の別生成を判断する。union候補を継続対象にする場合はdenoland/rusty_v8へ150.4.0のwrapper、V8本体、同梱third-partyの本文／notice対応とdirty差分を確認する。wrapperのMIT標準本文で全体を代替しない。 |
| deno_core_icudata 0.77.0／unionのみ | crateは`MIT` | [lock inventory][lock]と一致するarchiveのSHA-256を今回再確認。VCSは`83537ba16a4bf1645fc8322e81f7aaf0149a8922`。READMEはRusty V8の`third_party/icu/common/icudtl.dat`を示し、sourceは同名dataを埋め込むがdata元revisionと適用本文／noticeは未確認。 | app-server単独scopeの判断はV8と同じ。継続対象ならdenoland/deno_core_icudataへ当該dataの固定元revisionと付属ICU／Unicode等の条件を確認する。crate宣言のMITと埋込dataの条件を同一視しない。 |

本文やcopyrightが見つからない場合に、存在しない著作権者の証明や全権利者の列挙を一律の完了条件にはしない。
実際に付属しているheaderとNOTICEを保全し、参照先が具体的に残るfxhashやschema／data由来が未確定の件を個別に扱う。
上流への照会結果が得られない場合も、宣言、取得した本文、取得できていない資料、配布者の判断を分けて残す。

## 標準本文を別役割で併記する生成設計案

SPDXはLicense ListをtextとJSON等で提供しているため、宣言されたライセンスの標準条項を提示する供給元候補になる。[公式license-list-data](https://github.com/spdx/license-list-data)
ただし、標準本文の存在だけでは個別packageへの許諾や第三者由来部分の適用範囲は確定しない。
以下は初回文書化時に未実装だった設計案である。
その時点ではSPDXのcommit選定や本文取得をしておらず、後日の実装を上流6件の再調査や法的承認とは扱わない。

1. `spdx/license-list-data`の確認済み40桁commitを固定し、license IDごとに固定URL、member path、SHA-256、sizeを記録する。
   branch HEADや可変tagだけを生成入力にせず、通常ファイル、UTF-8、包含、hashを既存証拠と同様に検証する。
2. roleを`standard-license-text`とし、上流取得本文、実copyright、NOTICE、source headerとは別の来歴として表示する。
   公開本文にも「SPDX標準条項の参考併記であり、このpackageから取得した本文ではない」と明示する。
3. componentへの参照はname、version、lock source、crate checksumを厳格に結合し、raw宣言を保つ。
   ORの選択は配布者の明示判断として別記し、旧slash表記を無言で書き換えない。
4. placeholderを実在のholder／yearに置換せず、残る場合は標準本文中のplaceholderと明示する。
   実noticeは原文bytesと出所を保持し、manifest authorsをcopyrightへ格上げしない。
5. 同一hashの本文共有は可能だが、roleと出所とcomponent参照は失わない。
   `upstreamFullTextAvailable`、`standardTermsAvailable`、`attributionReview`、`scopeReview`を別集計にし、標準本文の追加で「上流全文取得済み」や「義務充足」に変更しない。
6. 将来のfixtureでは固定commit／hash不一致、ID取り違え、OR未選択、placeholder表示、既存NOTICE保持、SDK留保と版差の残存を検証する。
   別の新規草稿directoryだけへ出力し、既存936草稿を上書きしない。

MITはcopyright noticeと許諾noticeの保持を条件に含むため、標準条項の添付と実際に付属するnoticeの保全は別に扱う。[SPDXのMIT本文](https://spdx.org/licenses/MIT.html)
Apache-2.0の4項には本文の提供、変更表示、source配布時の関連notice保持、上流NOTICEが含まれる場合の関連帰属表示があり、標準本文だけでそれら全部を代替したとは扱わない。[ASFのApache-2.0本文](https://www.apache.org/licenses/LICENSE-2.0)
これらの公式3資料は確認日にオンラインで参照したが、8件それぞれの権利関係をオンラインで再証明したものではない。

## 判断の範囲

固定release asset、tag、source、外部pin不変、normalized graph、収集本文とnoticeの対応を来歴の判断材料にする。
全936件の個別法律家承認、再現build、SBOMを一律の新しい必須条件にはせず、SBOMや再現結果が取得できれば補強証拠として扱う。
具体的なSDK条件、版差、schema／dataの由来について疑義が残れば、その条件を配布者へ提示して判断を求める。
既存草稿の`draft-not-approved`と`distributionStatus: not-ready`は変更せず、承認receiptも発行しない。

## 2026-10-24の実装後の状態

app-server単独907候補を選ぶscopeに続き、明示supplementだけから標準条項を併記する機能を実装した。
公式SPDXのcommit `31ba1a50e5397e00a304dbadc76531740e89ee48`のMITとApache-2.0本文を固定し、`standard-license-text`として来歴を分ける。
holder/year placeholderは未置換で、実copyrightや上流取得本文ではないと公開headerへ明記する。
34 fixtureが成功し、新規草稿は907 components、492本文、標準条項6件／10参照となった。
上流全文候補なし6件、SDK留保、版差、必要noticeの適用確認、OR未選択とnot-readyは維持する。
この実装では上流6件の追加探索を行っておらず、表の具体的な未確認事項が解消したとは扱わない。
詳細と固定URL、hash、sizeは[Tools README](../Tools/ThirdPartyNotices/README.md)と[新規草稿validation](../build/third-party-notices-app-server-standard-draft-20261024/validation.json)を参照する。

## 2026-11-11の追記

上流6件、SDK留保、版差、OR選択、NOTICE、MPL-2.0の12候補、nucleoのsymlinkを再調査し、承認用に[判断シート](store-license-decision-sheet.md)へまとめた。
上の表と履歴は変更していない。
現在状態の要点は次のとおりである。

- display_container 0.9.0：crates.io公開と同日のgazebo commit `13efb6d415c4729178dfccc36fa9c87491f0813d`のmanifestが0.9.0で、`src/lib.rs`と`Cargo.toml`がcrateにbyte一致した。LICENSE-MITとLICENSE-APACHEも旧保存本文と同hashだった。版差は解消候補だが、補完manifestへの反映と承認は未実施。
- fxhash：`lib.rs`のRust Project Developers headerが現行草稿のtextsにない。表示に加える提案を判断シートに記載した。
- 他の4件（objc2-foundation、debugserver-types、eventsource-stream、io_tee）：crates.io metadata、READMEの宣言、GitHubのtop levelを再確認したが、新たな全文は見つからなかった。標準条項の参考併記と宣言の明記が提案の上限である。
- Apple SDK留保：同じ`LICENSE.md`はobjc2-foundationに限らず、objc2-app-kit等にも及ぶ。
- OR選択：COPYLEFT系の選択肢を含むのはself_cell（`Apache-2.0 OR GPL-2.0-only`）だけで、Apache-2.0の採用を推奨案とした。
- nucleo：crates.ioのnucleo-matcher 0.3.1は固定commitと内容が異なり、代替にならない。
- source案内：[改訂草稿](../build/source-availability-draft-20261111/SOURCE-AVAILABILITY.draft.txt)を新規に作成した。既存草稿は変更していない。
- 上流の保守者への問い合わせは行っていない。生成器の再実行もしていない（fixture 34件は成功）。

[draft]: ../build/third-party-notices-draft-20261023-3/internal-manifest.json
[graph]: ../build/dependency-audit/codex-0.163.0/rust-toolchain-audit-1.95.0/results/target-closure-followup/target-closure-inventory.json
[s2]: ../build/dependency-audit/codex-0.163.0/rust-toolchain-audit-1.95.0/results/license-supplement-20261023-2/manifest.json
[s3]: ../build/dependency-audit/codex-0.163.0/rust-toolchain-audit-1.95.0/results/license-supplement-20261023-3/manifest.json
[lock]: ../build/dependency-audit/codex-0.163.0/rust-toolchain-audit-1.95.0/results/cargo-lock-license-inventory.json
