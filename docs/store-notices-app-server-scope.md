# app-server単独notices草稿のscope

2026-10-24に`--scope app-server`を追加した。
既定の`release-union`と明示指定の同scopeは従来の出力bytesを維持し、未知のscopeを拒否する。

## 対象の選び方

保存済みnormalized graphの`closures.releaseUnion`は936、`closures.appServer`は907 IDである。
生成器は従来どおり全Unionの固定mapping、hash、size、包含、symlink制約と両補完validatorを検証した後、appServerの正確なID集合だけを選ぶ。
Unionとの一致、appServerの包含、重複と件数、codex-app-server root、arm64 macOS targetを確認し、名前だけで依存を除外しない。
選択集合はsource由来の保守的候補であり、907件の実binary含有証明ではない。
936側は同時2バイナリbuildを近似する保守的unionで、今回同梱予定のapp-server単独とはscopeが異なる。
V8とdeno_core_icudataを含む29候補は今回の選択集合外となるが、既存936草稿とその資料は保護する。

## 実行結果

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/ThirdPartyNotices/tests -v
PYTHONDONTWRITEBYTECODE=1 python3 scripts/generate-third-party-notices.py --scope app-server --output build/third-party-notices-app-server-draft-20261024
```

既存19件と新規8件のfixture計27件が成功した。
実データ生成は未存在directoryへ1回だけ実行してexit 0となり、907 components、491本文、NOTICE/copyright参照145件を出力した。
txtのSHA-256は`32341f6dcf508018c14573531685e4399a9f37e91fd2a137de0ef7ed3cd4f5f9`、sizeは2,153,406 bytes。
1684資料参照のhashとsize、包含、本文bytes、選択レコードの旧Unionとの一致、旧草稿15 fileと入力10 fileのhash不変を検証した。
結果のscope、root、graph hash、候補数は[新規草稿の検証結果](../build/third-party-notices-app-server-draft-20261024/validation.json)にある。

全文候補なしはobjc2-foundation、debugserver-types、display_container、eventsource-stream、fxhash、io_teeの6件だった。
これは宣言ライセンス不明の判定ではなく、上流全文の欠落や版への適用未確認を含む生成器上の分類である。
SDK留保、display_containerの0.8.1／0.9.0版差、歴史資料、実NOTICEとheaderを変更せず、適用義務のレビュー未完907件を維持した。
[残件の分類](store-license-remaining-review.md)を判断材料とし、全936個別法律家承認や再現buildを一律の新gateにはしない。
標準termsの追加、法的適合の確定、配布承認receipt発行、config.ready変更は行っていない。
草稿はdraft-not-approvedかつdistributionStatus: not-readyのままであり、公開もアプリへの組込みもしていない。
