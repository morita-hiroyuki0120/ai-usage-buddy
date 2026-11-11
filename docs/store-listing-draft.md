# App Store Connect 掲載情報（下書き）

作成日：2026-11-11。ローカルの作業メモであり、App Store Connectへは未入力・未アップロード。
対象：AI Usage Buddy（Apple ID 6826562310、主言語 日本語、Store version 1.0、販売者 PUREROAST&BREW, LIMITED LIABILITY COMPANY）。
文字数・バイト数はスクリプトで実測した値（字数はPythonのlen、バイトはUTF-8）。
この文書は審査通過、法務確認、Appleの申告回答の確定を意味しない。最後の「人間が決めること」を先に確認する。

## 方針メモ

- 誇張しない。OpenAIの製品ではないこと、ChatGPTアカウントが必要なこと、サンプルデータ表示があることを説明に明記した。
- 説明に書いた機能は、READMEと現行のLocalizable.stringsで確認できるものに限った（Store版は更新確認UIがないため記載しない）。
- 「データを収集しない」「通信しない」などの断定は、helperの通信監査が未完了のため、説明には書いていない（サンプル表示中の挙動のみ記載）。
- サブタイトルとキーワードには「Codex」「ChatGPT」を入れていない。説明文には、対応サービスを説明する目的で名称を使い、商標の注記を付けた。スクリーンショットの見出し1枚目に「Codex」が入っている（人間判断事項3）。

## 日本語（主言語）

### 名前
`AI Usage Buddy`（14字／上限30字）

### サブタイトル
`利用枠の残量を猫でひと目で確認`（15字／上限30字）

### プロモーションテキスト（上限170字）
98字

```
ChatGPTアカウントのCodex利用枠（5時間枠・週間枠）の残量とリセット時刻を、メニューバーの猫で確認できます。アカウントなしでも、サンプルデータで画面と動作を試せます。OpenAI非公式。
```

### キーワード（上限100バイト）
40字・98バイト（UTF-8、カンマ区切り、カンマ後の空白なし）

```
メニューバー,残量,使用量,利用枠,通知,猫,リセット,モニター,AI,クォータ
```

### 説明（上限4000字）
1062字

```
AI Usage Buddyは、ChatGPTアカウントのCodex利用枠の残量を、Macのメニューバーの猫でひと目で確認できるアプリです。

【できること】
・5時間枠と週間枠の残量（%）を表示します
・各枠のリセットまでの残り時間と、リセット日時を表示します
・残量に応じて猫の表情が変わります（元気／通常／疲れている／睡眠中）
・メニューバーに表示する枠（5時間枠または週間枠）を選べます
・複数のアカウントを切り替えて確認できます
・低残量のときに通知できます（しきい値を2つまで設定、初期値は20%と10%）
・グローバルショートカットで、クイック利用状況の表示（初期値：control＋option＋U）と手動更新（初期値：control＋option＋R）ができます
・ログイン時の自動起動は、ご自身で有効にした場合のみ登録されます
・表示言語は日本語と英語に対応しています（システム設定に従う設定も選べます）

【ご利用にあたって】
・本アプリは独自のアカウント登録を必要としません。残量を表示するには、OpenAIの既存のChatGPTアカウントで、公式のブラウザログインを行います。パスワードを本アプリに入力することはありません。
・残量を表示できるのは、Codexの利用枠が提供されているアカウントです。利用枠の有無や内容は、ご契約のプランによって異なります。
・表示される残量とリセット時刻は、公式のログインを通じてOpenAIのサービスから取得した値です。サービス側の仕様変更や通信状況により、取得できない場合や、表示が遅れる場合があります。
・アカウントを接続していなくても、「サンプルデータで試す」から、サンプルの数値で画面と動作を確認できます。サンプルデータ表示中は、画面に「サンプルデータ表示中」と表示され、通信、ログイン、通知、データの保存は行いません。実際の利用状況ではありません。
・広告表示とアプリ内課金はありません。

【ご注意】
AI Usage Buddyは、OpenAIの製品ではなく、OpenAIが提供・承認・支援するものでもありません。OpenAI、ChatGPT、Codexは、OpenAIの商標または登録商標です。本アプリは、これらの名称を、対応するサービスを説明する目的でのみ使用しています。

【サポート】
ご質問や不具合のご報告は、アプリの設定画面の「サポート（GitHub Issues）」から、サポートページ（GitHub Issues）をご利用ください。
```

## 英語（追加ローカライズ）

### 名前
`AI Usage Buddy`（14字／上限30字）

### サブタイトル
`Usage limits, shown by a cat`（28字／上限30字）

### プロモーションテキスト（上限170字）
163字

```
See your Codex 5-hour and weekly limits and reset times at a glance, via a cat in your menu bar. Try it with sample data, no account needed. Not an OpenAI product.
```

### キーワード（上限100バイト）
78字・78バイト（UTF-8、カンマ区切り、カンマ後の空白なし）

```
menu bar,usage,quota,limit,remaining,reset,tracker,monitor,cat,notification,AI
```

### 説明（上限4000字）
2065字

```
AI Usage Buddy shows how much of your Codex usage limits is left, using a cat in the Mac menu bar.

WHAT IT DOES
- Shows the remaining percentage of the 5-hour limit and the weekly limit
- Shows the time left until each limit resets, and the reset date and time
- The cat's expression changes with your remaining quota (energetic, normal, tired, sleeping)
- Choose which limit (5-hour or weekly) drives the menu bar icon
- Switch between multiple connected accounts
- Optional low-usage notifications with up to two thresholds (defaults: 20% and 10%)
- Global shortcuts to show quick usage (default: Control-Option-U) and to refresh (default: Control-Option-R)
- Launch at login is registered only if you turn it on yourself
- Available in Japanese and English (or follow your system language)

GOOD TO KNOW
- AI Usage Buddy does not ask you to create a separate account. To see your quota, you sign in to your existing ChatGPT account from OpenAI through the official browser login. You never type your password into this app.
- Quota can be shown for accounts that have Codex usage limits. Whether limits are available, and what they are, depends on your plan.
- The remaining quota and reset times come from OpenAI's service through that official sign-in. They may be unavailable or delayed if the service changes or the connection is poor.
- Without connecting an account, you can choose "Try with sample data" to explore the screens with example numbers. While sample data is shown, the app displays a "Showing sample data" notice and does not sign in, make network requests, send notifications, or save data. The numbers are not your actual usage.
- No ads. No in-app purchases.

DISCLAIMER
AI Usage Buddy is not an OpenAI product and is not provided, endorsed, or sponsored by OpenAI. OpenAI, ChatGPT, and Codex are trademarks or registered trademarks of OpenAI. They are used here only to describe the services the app works with.

SUPPORT
For questions or bug reports, use "Support (GitHub Issues)" in the app's Settings to open the support page on GitHub.
```

## 言語共通の項目

| 項目 | 入力値・案 | 備考 |
|---|---|---|
| サポートURL | `https://github.com/morita-hiroyuki0120/ai-usage-buddy/issues` | アプリの設定画面のリンクと同じ。公開リポジトリで開けることを入力前に確認する。 |
| マーケティングURL | （空） | 任意。 |
| プライバシーポリシーURL | `https://（GitHub Pagesの公開URL・未確定）/privacy` | プレースホルダ。公開計画（privacy-publication-plan.md）の承認と公開が済むまで入力不可。必須項目なので未確定のままでは提出できない。 |
| 著作権 | `2026 PUREROAST&BREW, LIMITED LIABILITY COMPANY` | 年は初回公開年の想定。 |
| 価格 | 無料（Free）、すべての地域 | アプリ内課金なし、広告なし。App Store Connectの価格設定は未実施。 |
| 新機能（What's New） | 1.0では入力不要 | |
| 審査メモ・サンプルデータの手順 | `app-review-notes-en.md`の候補を使う | 本書の対象外。 |

### 文字数・バイト数の実測まとめ

| 項目 | 日本語 | 英語 | 上限 |
|---|---|---|---|
| 名前 | 14字 | 14字 | 30字 |
| サブタイトル | 15字 | 28字 | 30字 |
| プロモーションテキスト | 98字 | 163字 | 170字 |
| 説明 | 1062字 | 2065字 | 4000字 |
| キーワード | 40字／98バイト | 78字／78バイト | 100バイト |

## カテゴリ

- 主カテゴリ：仕事効率化（Productivity）
- 副カテゴリ：開発ツール（Developer Tools）
- 理由：主機能は、日々の作業で使う利用枠の残量確認という効率化ユーティリティで、メニューバーに常駐して見るアプリのため。主な利用者はCodexを使う開発者層なので、副カテゴリを開発ツールにすると、その層から見つけてもらいやすい。
- 代替案：主カテゴリを「ユーティリティ（Utilities）」にする案もある。メニューバー常駐の小さな表示アプリという性格には合うが、競合が多く、利用者層の目に留まりにくい可能性がある。
- 副カテゴリを開発ツールにすると、開発者向けアプリとして審査で見られる可能性がある。開発者専用アプリではないので、実害は小さいと考えるが、断定はしない。

## 年齢区分（Age Rating）の質問票への推奨回答

Appleの質問票の項目名や分かれ方は更新されることがある。以下は2026-11時点の想定で、ASC画面の実際の質問と突き合わせて入力する。

| 質問の領域 | 推奨回答 | 根拠 |
|---|---|---|
| 暴力（漫画的／写実的／銃・武器）、ホラー、性的・裸体、ギャンブル（模擬／実際）、薬物・アルコール・タバコ、下品な言葉、成人向けテーマ、医療・健康情報 | すべて「なし」 | 利用枠の残量と猫のキャラクターの表示のみ。 |
| アプリ内課金・懸賞・コンテスト | なし | 課金なし、広告なし。 |
| ユーザー生成コンテンツ、メッセージ・チャット | なし | 利用者同士の機能も投稿もない。 |
| 無制限のWebアクセス（Web閲覧機能） | なし（要確認） | アプリ内にWebビューやブラウザ機能はない。ログイン時だけ、helperが返した認証URLを既定ブラウザで開く。サポートリンクもクリック時に外部ブラウザで開くだけ。外部サイトのログインがある点を、審査メモにも書いておく。 |
| 年齢確認・保護者による制限などのアプリ内機能 | なし | |
| AIによる生成コンテンツ（該当する質問がある場合） | なし | 本アプリは文章や画像を生成しない。残量を表示するだけ。 |

想定結果：4+。最終的な区分はAppleの算出に従う。外部サイトのログイン（ChatGPTアカウント）がある点で、13+や17+に上がると考えていないが、断定はしない。

## App Privacy（栄養ラベル）の推奨回答の整理

結論は出さない。「データを収集しない（Data Not Collected）」と申告できるかどうかは、人間が判断する。

### 根拠になる事実（store-privacy-data-inventory.md、store-helper-data-flow-audit.md から）

1. 開発者（PUREROAST&BREW）が運営するサーバーはなく、利用状況やアカウント情報を開発者が受け取る実装は確認していない。
2. アプリ本体に、広告、アプリ内課金、独自analyticsの実装は確認していない。
3. 設定、アカウント表示名、公式連携から得たメールアドレスとプラン種別、利用枠のスナップショットは、端末内（Application Support）にだけ保存する。認証情報は、Store版ではKeychainを使う設計（実機での有効設定と保存内容は未確認）。
4. 一方で、同梱のCodex app-server helperは、利用者が開始する公式ログイン、account/read、account/rateLimits/readでOpenAIへ通信する。ログイン時はhelperが返した認証URLを既定ブラウザで開く。
5. helperのanalyticsやOTelは起動設定で無効にしているが、helperの通信全体は未監査である。例として、モデル一覧の取得など、認証と利用枠以外の通信がある可能性が、親の調査で挙がっている。
6. サンドボックス内でのhelperの実際の送信内容、OpenAI側の保持期間、アンインストール後のcontainerの扱いは未確認。

### 考え方

- 「収集（collect）」は、Appleの定義では、アプリが端末外へデータを送り、開発者や第三者パートナーが、リアルタイムの処理に必要な期間を超えて取得できる状態を指す。第三者のコード（同梱helperを含む）による取得も、開発者の申告責任に含まれる。
- 申告できる案A：データを収集しない。
  - 理由：開発者はデータを受け取らない。helperとOpenAIの通信は、利用者が自分のOpenAIアカウントで行う、そのサービス自身への接続で、このアプリの開発者や広告・分析の第三者へ渡すものではない、という整理。
  - リスク：helperはOpenAI製コードで、OpenAIが通信を通じてIPアドレスや識別子などを取得する可能性がある。Appleが、同梱のthird-party codeによる取得と見なすなら、不足申告になり得る。通信監査が未完了のため、この整理を裏づける実測がない。
- 申告する案B：OpenAI側の取得を保守的に申告する。
  - 候補は、識別子（ユーザーID、デバイスID）、利用状況データ（製品の操作）、連絡先情報（メールアドレス）など。実際にどのデータが送られ、何のために使われるかを確認してから選ぶ。「トラッキングには使用しない」は、広告・分析目的の利用が確認できてから決める。
  - リスク：過剰申告でも提出は通るが、実際より多くの収集をしていると利用者に見える。
- 案C：helperの通信監査（実測）を終えてから、A か B を決める。提出前の確認として、これが最も安全。

### 前提として必要な作業（未完了）

- helperの通信先と送信内容の確認（サンドボックス署名版での実測）。
- プライバシーポリシー本文の確認と公開（本文とApp Privacyの回答は一致させる）。
- 回答はApp Store ConnectのApp Privacy画面で、開発者本人が行う。

## スクリーンショット

出力先：`build/store-screenshots-20261111/{ja,en}/`。全10枚。2880x1800（16:10、Mac App Storeの指定サイズ）のPNG。
実際のアプリ画面（SwiftUI）を、ライト外観、サンプルデータ表示で、オフスクリーン描画して合成した。架空のグラデーション背景と、汎用のメニューバー風の帯、猫アイコン、見出しを添えている。
サンプルデータのバナーは消していない。画面下の注記に、OpenAI非公式であること、サンプルデータの画面であることを明記した。

| 順 | ファイル（ja／enとも同名で言語サフィックスのみ違う） | 内容 |
|---|---|---|
| 1 | 01-popover-plenty | ポップオーバー。サンプルA、余裕あり（元気な猫、82%／64%） |
| 2 | 02-popover-low | ポップオーバー。低残量（疲れた猫、24%／18%） |
| 3 | 03-popover-depleted | ポップオーバー。サンプルB（通常の猫、55%／71%）、リセットまでの時間と日時 |
| 4 | 04-settings | 設定画面（アカウント、メニューバー表示リミット、通知しきい値） |
| 5 | 05-sample-data | 初回セットアップの接続画面。「アカウントを接続…」と「サンプルデータで試す」 |

注：ファイル名の「03-popover-depleted」は、当初の想定（ほぼ枯渇）からサンプルBの表示に変更した後の名前の名残。英語のバナーで、「Almost empty」が選択ボタン内で「Nearly de…」と省略される表示があったため、その画面は使っていない（下記のアプリ側の気づきを参照）。

## アプリ側で気づいた点（修正していない）

- 英語のポップオーバーのサンプルバナーで、選択肢「Almost empty」が「Nearly de…」に省略される。幅320ptの制約による。
- リセット日時（例：2026/11/11 15:37）の表記は、アプリの言語設定ではなく、Macの地域設定（Locale.current）に従う。英語表示でも数字は日本の形式になる（日本語の文字は混ざらない）。
- 設定画面（Form）に、内容のない空の行が3か所ある（セクション間のDividerが行として描画されている可能性）。オフスクリーン描画の影響かどうかは未確認で、実機での目視確認が必要。

## 人間が決めること

1. 掲載文の「Codex」「ChatGPT」「OpenAI」の名称を、説明文に、対応サービスの説明として使うことを許容するか。はい／いいえ
2. キーワードに「Codex」「ChatGPT」を入れない案でよいか。入れると検索流入は増えるが、他社商標の使用として審査で指摘されるリスクがある。入れない案でよい：はい／いいえ
3. スクリーンショット1枚目の見出し（英語「See Codex usage in your menu bar」、日本語「Codexの残量を、メニューバーの猫で確認」）に「Codex」を入れてよいか。いいえの場合は、見出しを差し替える。はい／いいえ
4. サブタイトルとプロモーションテキストの案（OpenAI非公式の明記を含む）でよいか。はい／いいえ
5. 主カテゴリを仕事効率化、副カテゴリを開発ツールにしてよいか。はい／いいえ
6. 年齢区分の回答は、上の表のとおり（すべて「なし」、想定4+）でよいか。「Web閲覧機能なし」と回答してよいか。はい／いいえ
7. App Privacyは、案C（helperの通信監査を終えてから決める）にするか。はい／いいえ
8. 案Cを取らない場合、先に案A（データを収集しない）で進めるか。はい／いいえ
9. プライバシーポリシーURLは、GitHub Pagesの公開URL確定後に入力する方針でよいか。はい／いいえ
10. 著作権表示「2026 PUREROAST&BREW, LIMITED LIABILITY COMPANY」でよいか。はい／いいえ
11. 価格は無料、全地域でよいか。はい／いいえ
12. 説明文の「広告表示とアプリ内課金はありません」と、サンプルデータ表示の説明を、そのまま掲載してよいか。はい／いいえ
13. 説明文に通信や保存について書いた部分（サンプルデータ表示中は通信しない、など）は、現行実装の確認と単体テストに基づくが、署名済みStore版での実機確認は未実施。この段階で掲載してよいか。はい／いいえ
14. スクリーンショットは、サンプルデータ表示に実画面を使った合成画像（架空背景、見出し付き）でよいか。はい／いいえ
15. 英語のバナー省略（Nearly de…）とFormの空行を、提出前にアプリ側で直すか。はい／いいえ

## 2026-11-11 ユーザー決定

- App Privacy：OpenAI側の取得を保守的に申告する（案B）。同梱helperがOpenAIへ送る可能性のある項目を「アプリの機能」目的、ユーザーに紐づく、トラッキングなしとして申告する。
- 説明文とスクリーンショットで「Codex」「ChatGPT」の名称を使用する（説明文の非公式・商標注記を維持）。
- プライバシーポリシーURL：https://morita-hiroyuki0120.github.io/ai-usage-buddy/privacy/ （英語版 https://morita-hiroyuki0120.github.io/ai-usage-buddy/en/privacy/ ）。2026-11-11にGitHub Pagesで公開し、HTTP 200を確認した。
- サポートURL：https://github.com/morita-hiroyuki0120/ai-usage-buddy/issues
- 署名付きarchive/exportとApp Store Connectへのuploadまで進める。審査提出は別途確認する。
