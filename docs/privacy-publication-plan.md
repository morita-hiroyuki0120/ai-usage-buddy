# プライバシー文書の公開準備

> 内部手順。掲載未承認、未公開。
> この文書は公開本文や公開操作の承認を代替しない。

## 承認済みの範囲

利用者は、運営者名にPUREROAST&BREW, LIMITED LIABILITY COMPANYを使用することと、既存リポジトリのGitHub Pagesを公開先にする方針を承認した。
既存資料のサポートURLから参照できる対象リポジトリは`morita-hiroyuki0120/ai-usage-buddy`である。
Pages設定や公開URLは確認しておらず、この文書では確定URLを指定しない。
本文を公開前に利用者が確認し、掲載を承認する必要がある。

## 公開ファイルの隔離

既存の`docs/`には内部監査資料があるため、ディレクトリ全体をPagesの公開対象にしない。
承認済みの公開本文だけを置く専用の`site/`フォルダーを推奨する。
このフォルダーは未作成で、公開範囲やデプロイ方法も未設定である。
将来workflowを用いる場合も、専用公開フォルダーだけを公開成果物に含め、内部文書や監査資料を含めない構成を確認する。

## 本文確認から公開まで

1. [草稿](privacy-policy-draft-ja.md)と[内部インベントリ](store-privacy-data-inventory.md)の未確認事項を整理する。StoreのKeychainとdirect指定、および削除時logout統合のソースとmock検証を、Sandbox下の実Keychain削除やremote失効成功の保証とは扱わない。
2. 公開候補の本文を利用者へ提示し、掲載承認を得る。法人住所、メール、電話、保存日数を推測して補わない。サポート窓口は承認済みのGitHub Issuesを使用する。
3. 本文承認後に、公開用assetsと必要なworkflowの作成範囲を確認する。Pagesの有効化、push、公開操作は別途明示承認を得てから行う。
4. 公開後に実URLと掲載内容を確認し、アプリ内リンクとStore申告への反映を別途判断する。現時点ではURL作成や公開確認を行っていない。

今回の変更は名称と公開先方針の文書反映のみである。
ソース、認証情報、実container、CI、Pages設定、portalには触れていない。

## 2026-11-11追記：公開用ページのローカル準備と公開方式案

> 内部手順。掲載未承認、未公開。以下は案であり、実行していない。

### ローカルに用意したもの（未コミット・未公開）

`site/`に静的HTML（外部CDN・解析・フォント読み込みなし）を作成した。内部資料を含む`docs/`は含めない。

- `site/index.html`、`site/en/index.html`（紹介と日英切替）
- `site/privacy/index.html`（日本語）、`site/en/privacy/index.html`（英語）
- `site/support/index.html`、`site/en/support/index.html`
- `site/style.css`、`site/.nojekyll`

本文は[草稿](privacy-policy-draft-ja.md)と[内部インベントリ](store-privacy-data-inventory.md)に基づく公開本文の候補である。施行日は「[施行日：公開時に記入]」のプレースホルダのままで、住所、メール、電話、保存日数は記載していない。2026-11-11追加のStore版サンプルデータ表示（通信、helper起動、認証、保存、実通知なし）を反映した。本文の承認は未了であり、公開前に利用者の確認が必要である。

### 想定URL（未確認）

Pagesの設定とURLは確認していない。プロジェクトサイトの通常の形式から次を想定するが、実際のURLは公開後に確認する。

- https://morita-hiroyuki0120.github.io/ai-usage-buddy/
- https://morita-hiroyuki0120.github.io/ai-usage-buddy/privacy/
- https://morita-hiroyuki0120.github.io/ai-usage-buddy/en/privacy/
- https://morita-hiroyuki0120.github.io/ai-usage-buddy/support/

ページ内のリンクは相対パスで、サブパス配信でも動作する。

### GitHub Actionsで`site/`だけを公開するworkflow案

`.github/workflows/pages.yml`としては作成していない。公開承認後に作成を判断する。

```yaml
name: Deploy site to GitHub Pages

on:
  push:
    branches: [main]
    paths: ["site/**", ".github/workflows/pages.yml"]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v3
        with:
          path: site
      - id: deployment
        uses: actions/deploy-pages@v4
```

actionsのバージョンは作成時に最新を確認する。`path: site`により、`docs/`などの内部資料は成果物に含まれない。

### 公開に必要な人間の操作と承認

1. `site/`の本文（日英）を確認して掲載を承認する。施行日を記入する。
2. workflowの作成とコミット、`main`へのマージとpushを明示承認する。
3. リポジトリ設定のPagesでSourceを「GitHub Actions」にする。
4. 公開後に実URLと掲載内容を確認する。
5. その後に、アプリ内のプライバシーリンク実装とStore申告（Privacy Policy URL、App Privacy）への反映を別途判断する。

### 未確認点

- Pagesの有効化状態、リポジトリの公開設定、実URL。
- 本文中の「運営者は独自サーバーを運用していない」は、アプリ本体コードの確認範囲に基づく。運営者側の運用事実としての確認は利用者が行う。
- 同梱helperの通信全体、OpenAI側の保存期間、Keychainの実保存内容は未確認で、本文でもその旨を述べ、断言を避けている。
- 法的適合の確認、Apple App Privacy回答は未実施。
- READMEの「外部サーバー通信なし（ローカル完結）」はhelperの通信と整合しない表現であり、公開前に見直しを推奨する。
