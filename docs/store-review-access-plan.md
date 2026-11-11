# AI Usage Buddyの審査アクセス相談案

作成日：2026-10-23。
現在の状態（受領共有日2026-11-09）：ユーザーがcase 103007143655へのDeveloper Support返信要旨を共有した。メール送信日は不明であり推定しない。
返信は一般的な提出情報と添付案内で、事前承認や個別判断はできず、提出後のfeedbackで扱うという内容である。
デモや4.8の明示承認はなく、審査アクセス方法は未解決である。
以下の2026-10-24の作成と送信記録は履歴として保持する。
親CUAがhumanの明示承認後にApp Store ConnectのmacOSアプリrecordを作成し、Apple ID 6826562310を確認した。
承認済み日本語相談文を公式App Reviewのその他/Eメールフォームから1件送信し、受付画面の問い合わせ番号103007143655を親が確認した。
上記の一般案内の返信要旨は受領共有済みだが、個別の事前承認は未取得である。
Team 9HYDLV4RY2のBundle ID登録、Store profile生成とダウンロードは確認済み、profileインストールは未実施。
審査員へ開発者のOpenAI個人アカウント認証を渡さず、アプリを確認してもらう方法は未決である。
デモモードは未実装で、Appleの事前承認も得ていない。

## 2026-11-09の返信共有と資料準備

返信の全文引用、個人メール、認証情報は保存しない。
受領共有の事実は「デモによる代替が承認された」「4.8該当と判断された」「動画だけで審査可能になった」を意味しない。
既存の2.1(a)のprior approval条件に関する整理を撤回せず、今回ネットワークでガイドラインを再取得したとは記載しない。
過去節の「Apple回答未取得」は当時の履歴であり、現在は一般案内の返信要旨を共有済み、個別判断と事前承認は未取得と区別する。
新たに[日本語手引き](app-review-guide-ja.md)と[英語Review Notes候補](app-review-notes-en.md)をローカル準備した。
個人passwordを共有せず実ログイン手順と機能説明、動画台本を用意する範囲であり、動画は未撮影、未添付である。
デモ実装、upload、審査提出、公開、追加メール送信は行っていない。

## 現在の事実と確認範囲

- 無料のmacOSメニューバーアプリとしてMac App Store公開を予定している。アプリ本体に広告、アプリ内課金、独自analyticsはない。helper全体の通信監査は未完了である。
- Store向け構成ではOpenAI公式Codex app-serverの同梱を準備し、利用者が公式ブラウザログインを開始してCodex利用枠を取得する。正式な提出用archiveと配布構成は未完成である。
- 機能は5時間枠と週間枠の残量、リセット時刻、残量に応じた猫の状態、低残量通知、各種設定である。
- ローカルのSandbox検証版では、人間が公式ログイン後の残量表示、再起動後の保持、アカウント削除後の非表示を確認済みである。この確認は正式Store最終版の認証経路の検証完了を意味しない。
- 本アプリはMac App Storeで未公開である。第三者サービスの利用許諾、同梱helperの配布条件、提出構成の適合性は別途確認が必要である。

根拠は[提出準備状況](store-submission-readiness.md)、[Store構成](../Store/README.md)、[情報処理インベントリ](store-privacy-data-inventory.md)を参照する。
ログイン開始と利用枠取得は[CodexAppServerClient](../Sources/AIUsageBuddy/Services/CodexAppServerClient.swift)、ブラウザ起動は[AppModel](../Sources/AIUsageBuddy/Services/AppModel.swift)、猫の状態は[CharacterState](../Sources/AIUsageBuddy/Models/CharacterState.swift)で確認した。
一般READMEにはDirect版の要件も含まれるため、Store提出条件はStore資料を優先して確認する。

## Appleへ確認する論点

2026-10-23に[Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)の該当箇所を照合した。
以下は相談のための要約であり、本アプリへの適用判断や審査承認ではない。

| 該当箇所 | 相談上の扱い |
|---|---|
| Before You Submit | アカウント機能を含む場合、アクティブなデモアカウントまたは全機能を確認できるデモモード等による十分なアクセスが必要となる。 |
| 2.1(a) | 法的義務またはセキュリティ上の義務でデモアカウントを提供できない場合、組み込みデモによる代替にはAppleの事前承認が条件となる。本件が該当するかを相談し、提供不能の根拠を未確認のまま断定しない。 |
| 2.2 | 単なるデモ版やベータ版はApp Store公開対象とせずTestFlightを使う。完成アプリ内の審査アクセス手段として提案するデモと、未完成アプリの公開は区別する。 |
| 4.8 | 特定の第三者サービスのクライアントが既存サービスへ直接ログインする例外がある。本件の該当性を確認する。この例外から審査アクセス要件の免除を推定しない。 |

## 日本語の相談文案

件名：AI Usage Buddyの審査アクセス方法と組み込みデモの事前相談

App Reviewご担当者様

AI Usage Buddyは、無料のmacOSメニューバーアプリとして公開を準備しています。
アプリ本体に広告、アプリ内課金、独自の利用分析はありません。
Store版にはOpenAI公式Codex app-serverを同梱する構成を準備しており、利用者が公式ブラウザログインで自身の既存OpenAIアカウントへ接続すると、Codexの5時間枠と週間枠の残量、リセット時刻、猫の状態、通知、設定を利用できます。
ローカルSandbox検証版のログイン後の表示は人間が確認済みですが、正式なStore提出用archiveは未完成で、Mac App Storeでは未公開です。

開発者のOpenAI個人アカウントの認証情報を共有せずに、審査員が全機能を確認できる方法をご相談したく存じます。
Guideline 2.1(a)に基づく事前承認の対象となるでしょうか。
未実装の案として、利用者全員が選べる組み込みデモを検討しています。
常にサンプルであることを明示し、実際の利用枠取得と区別したデータで表示と状態変化、通知、設定を確認できるようにし、審査専用の隠しモードや機能の隠蔽は設けません。
この方法を認めていただけるか、実ログインと実データ取得にはどのような追加の確認手段が必要か、事前承認の手続きと併せてご教示ください。
認められない場合は、個人認証情報を共有せずに満たせる別の審査アクセス方法をご案内いただけますでしょうか。

あわせて、本アプリの既存OpenAIサービスへの直接ログインがGuideline 4.8の特定の第三者サービス向けクライアントの例外に該当するか確認をお願いします。
デモは未実装で、Appleの承認はまだ得ていません。
回答を踏まえて設計を決め、実ログインの検証も継続します。

## English inquiry draft

Subject: Prior consultation on review access and a proposed built-in demo for AI Usage Buddy

Dear App Review team,

We are preparing AI Usage Buddy, a free macOS menu bar app without advertising, in-app purchases, or our own usage analytics.
The Store configuration is being prepared to bundle OpenAI's official Codex app-server.
Users connect their existing OpenAI account through the official browser sign-in flow to view Codex five-hour and weekly quota balances, reset times, cat states, notifications, and settings.
Post-login display has been checked by a person in a local sandboxed validation build; the final Store submission archive is incomplete, and the app is not published on the Mac App Store.

We seek a way to provide full review access without sharing the developer's personal OpenAI credentials.
Would our circumstances qualify for prior approval under Guideline 2.1(a)?
We propose a built-in demo available to all users, with sample data always clearly labeled and separated from live quota retrieval, allowing inspection of displays, state changes, notifications, and settings.
It would not be a hidden review-only mode or conceal functionality.
Could you approve this approach, explain the prior approval process, and specify how reviewers should additionally verify real sign-in and live data retrieval?
If it is unsuitable, what alternative review access can meet the requirements without sharing personal credentials?

Please also advise whether direct sign-in to the existing OpenAI service qualifies for Guideline 4.8's exception for a client of a specific third-party service.
The demo is not implemented or approved by Apple.
We will decide its design after your response and continue validating real sign-in.

## 回答待ちと判断の手順

1. ユーザーが上記の日英文案と事実を確認する。法的義務やセキュリティ上の義務でデモアカウントを提供できないという説明を使う場合は、具体的な根拠を確認する。個人認証情報を共有しない方針だけで、2.1(a)の条件充足とは断定しない。
2. 送信担当者が、別途承認されたApple公式窓口から相談する。この文書の作成は送信承認を含まない。必要に応じてアプリ名と予定Bundle ID `com.aiusagebuddy.app.store`を伝える。パスワード、トークン、実個人メール、審査用秘密資格情報は本文や添付へ入れない。
3. 回答を受けるまで、審査アクセス方法は「判断待ち」とする。回答なし、受付通知、一般的なガイドライン案内だけでは、組み込みデモの事前承認を得たと扱わない。相談の受付番号、回答日、対象案、条件を、秘密情報を除いた形で記録する。
4. デモ案への明示的な承認と条件が得られた場合、ユーザーと対象範囲を確認して設計を決める。サンプルで再現できる機能と、認証や実取得など別の検証が必要な機能を対応づけ、条件を満たす実装を別タスクとして承認する。承認を審査通過の保証とは扱わない。
5. 回答が曖昧、デモ案が不承認、または追加の確認手段を求められた場合、指定条件をユーザーと整理して再相談する。資格情報の共有や新機能の実装を自動で選ばない。4.8の判断は審査アクセス方法の判断と分けて記録する。
6. 待機中も正式Store構成の実ログイン、実利用枠取得、再起動、削除の検証を継続する計画を維持する。デモ案はその代替としない。完成した提出対象に対して再確認し、審査メモに実際の操作手順とデモの限界を記載する。未完成版の試験には2.2に沿った配布方法を別途判断する。

本作業で行ったのは、この文書のローカル準備のみである。
Appleへの相談、App Store Connect操作、契約、アップロード、審査提出、公開、新機能の実装は行っていない。

## 2026-10-24の相談送信の試行状況

ユーザーは本ファイルの既存日英文案をApple公式App Review窓口へ1件送信することを明示承認した。
本担当は両文案を読み、利用可能なツールを確認したが、ブラウザーCUAツールが提供されていなかった。
browser UIだけを使うという指定に従い、HTTPやCLIによる代替操作は行っていない。

公式review/contactページの閲覧、問い合わせカテゴリの選択、フォーム入力、送信はいずれも未実施。
ログイン画面や認証ダイアログにも到達しておらず、認証が必要かは未確認である。
送信件数は0、送信channelは未選択、受付確認と受付番号は未取得、Appleの回答と事前承認も未取得である。

再開にはブラウザーCUAを利用できる担当または実行環境が必要である。
既存の送信承認を引き継ぎ、https://developer.apple.com/app-store/review/ または https://developer.apple.com/contact/ から実際のリンクで適切な相談先へ進む。
ログイン、パスワード、2FA、CAPTCHA、security promptが出た場合は自動応答せず、人間操作を依頼して停止する。
送信済みとは扱わず、送信前に既送信の有無を引き継いで重複を避ける。

## 2026-10-24 親への引継ぎ後の現在状態

親からの報告では、提供されたCUAを使い、公式 https://developer.apple.com/contact/ をIABに開いた。
Apple Developerのsign-in画面が表示されたため、親は人間へログインと必要な2FAの操作を依頼し、tabをmarkHandoffで保持した。
当初の「実作業担当にCUAがない」という停止理由は親への引継ぎで解消した。
現在の停止理由はAppleへの人間ログイン待ちであり、この担当が画面や認証状態を再確認したものではない。

相談送信は0件、受付番号は未取得、Apple回答と事前承認も未取得である。
既存相談文の送信承認は維持されており、同じ範囲の送信に再承認は不要である。
認証URL、session文字列、画面上のメール値は記録していない。
今回の作業はこの状態の記録のみで、code変更やportalへのアクセスは行っていない。

## 2026-10-24 必須App Apple IDと規約同意による停止

以下は親のCUA操作について共有された結果であり、この担当はbrowser操作や画面の再確認を行っていない。
親はApple contactのログイン後画面から、contact/topic/select → App Review（SC1103）→ その他（30023）→ Eメール（CONTACT.EML.GEN/details）へ進んだ。
app名AI Usage Buddy、platform macOS、承認済み日本語本文のみを入力した。
数値App Apple ID欄（Q236564）のrequired=trueをUIのreadonly DOM属性で確認したが、欄は空のままである。

親は送信ボタンを1回試行したが、受付画面への遷移も受付番号も確認できなかった。
送信成功とは扱わず、相談は未送信扱い、送信確認件数0、受付番号なしとして保持する。
再送は行っていない。

既存の数値IDを確認するため、表示リンク先の https://appstoreconnect.apple.com/ を開いたところ、App Store Connect Terms of Serviceの同意モーダル（V100、Last updated 04 June 2018）が表示された。
親はチェックと同意の操作を一切せず、人間へ規約確認と本人による同意操作を依頼した。
問い合わせフォームとApp Store Connectの両tabはmarkHandoff済みである。
親が保存した画面の所在は`/private/tmp/aiusagebuddy-appstore-terms-1792795722847.png`。この担当は画像を開いたり複製したりしていない。

現在はログイン待ちの段階を過ぎ、規約の本人同意、その後の既存appの数値ID確認が必要な状態である。
app recordが未登録と判明した場合、作成の判断と承認は別途必要であり、IDを捏造したり作成済みと扱ったりしない。
既存相談文の送信承認は維持され、同じ範囲の送信に再承認は不要である。
Appleの事前承認、デモ実装、upload、公開、契約承諾はいずれも未実施である。
個人contact値、認証URL、session文字列は記録していない。

## 2026-10-24 本人同意後の空一覧と作成前の状態

ユーザーは「同意したよ」と報告した。
親のCUAで https://appstoreconnect.apple.com/apps を確認し、規約モーダルが解消したことと、同チームの一覧が「アプリがありません」であることを確認したとの共有を受けた。
この担当が規約へ同意したり、browserで画面を再確認したりしたものではない。

親は「アプリを追加」dialogのみ開き、macOS checkboxを選択した。
作成ボタンは押しておらず、アプリrecordの書込みは確定していない。
dialogには初回companyName（公開App Store表示）、name、primaryLanguage、Bundle ID、SKU、access fieldsがある。
親保存screenshotの所在は`/private/tmp/aiusagebuddy-new-app-1792802185763.png`で、この担当は画像を開いたり複製したりしていない。

アプリrecord作成について、親がhumanへ別確認する提案値は次のとおり。

- platform：macOS
- name：AI Usage Buddy
- primary language：日本語
- companyName：PUREROAST&BREW, LIMITED LIABILITY COMPANY（対象チームの同一法人名。公開表示となることを含めて確認する）
- Bundle ID：com.aiusagebuddy.app.store
- SKU：AIUsageBuddy-macOS

これらは提案値であり、アプリrecord作成の承認または作成済みを意味しない。
access fieldの値はこの共有では確定していない。
数値App Apple IDはまだなく、問い合わせフォームの必須ID条件は未解決である。
相談は未送信扱い、受付番号なし。既存相談文の送信承認は維持する。
upload、審査提出、公開は行っていない。

Bundle IDの登録には以前のhuman承認がある。
親が公式dialog内リンクからdeveloper.apple.com/account/resources/identifiers/bundleId/add/を新tabで開くと/add/bundleへ遷移したが、画面はblankまたは初期headerのみだった。
reloadを1回行った段階で表示内容は未確認で、親が引き続き表示を確認する予定である。
Bundle ID登録確認や新規登録を完了扱いにしない。
個人contact値、認証URL、session値は記録していない。

## 2026-10-24 Developer Bundle ID登録の完了

親CUAから、Bundle ID画面の読込み成功と登録完了の共有を受けた。
Team 9HYDLV4RY2のIdentifiers一覧は当初XCWildcard（*）だけだった。
以前のhumanによる「.storeを確認し、未登録なら登録してよい」という明示承認に基づき、親はApp IDs→AppでDescriptionをAI Usage Buddy Store、Explicit Bundle IDをcom.aiusagebuddy.app.storeとして入力した。
追加capabilitiesを選ばず既定状態のままContinue→Registerを実行した。
登録後のIdentifiers一覧にAI Usage Buddy Store/com.aiusagebuddy.app.storeと元のXCWildcardの2行があることを親がUIで確認した。
親保存screenshotの所在は`/private/tmp/aiusagebuddy-identifier-registered-1792802338001.png`である。この担当は画像を開いたり複製したりしていない。

これはDeveloperサイトのBundle ID登録完了であり、App Store Connectのアプリrecord作成や数値App Apple ID発行ではない。
profile作成は未実施である。
App Store Connectの新規recordは未作成でhuman確認待ち。提案はmacOS、AI Usage Buddy、primary日本語、company PUREROAST&BREW, LIMITED LIABILITY COMPANY、SKU AIUsageBuddy-macOSである。
相談は未送信扱い、受付番号なし。既存の相談送信承認は維持する。
source code、config、配布物、credentialsの変更はないとの親共有を記録する。
この担当の操作は本docとcheckpointの記録更新だけであり、個人contact値、認証URL、session等の秘密情報は保存していない。

## 2026-10-24 Store profile生成成功の共有

親CUAから、Team 9HYDLV4RY2のProfiles一覧が空であることを確認後、以前のhuman承認に基づいてprofileを生成したとの共有を受けた。
選択はMac App Store Connect/Mac、Explicit com.aiusagebuddy.app.store、会社名が一致する既存Distribution証明書1本（有効期限2027-10-22）である。
Generate成功後のUIで、Name AI Usage Buddy Mac App Store、Type App Store、App ID 9HYDLV4RY2.com.aiusagebuddy.app.store、expires 2027/10/23、portal profile ID MFL8B9QQADを確認した。
portal profile IDをprofile UUIDやApp Store Connectの数値App Apple IDと同一視しない。
親保存screenshotは`/private/tmp/aiusagebuddy-store-profile-created-1792816607228.png`。この担当は画像を開いたり複製したりしていない。

DownloadリンクのdownloadMedia処理が長時間応答せずkernel timeoutとなったため、ダウンロードとインストールの成功、保存先は未確認である。
生成済みprofileを再生成しない。
App Store Connectアプリrecord作成の具体的承認は未回答で、recordと数値IDは未作成のまま。相談は未送信、受付番号なしである。
実配布署名archive、upload、審査提出、公開は実施していない。
この担当は状態記録のみを行い、codeやcredentialsは操作していない。

同日追加共有：親によるDownloads配下のmmin 240・provisionprofile対象の限定findでは該当なし。
親CUAの生成画面はDownload and Install、Name、Type、App ID、expiryの表示を保持している。
検索対象外の保存先やインストールの有無は確定せず、ダウンロード・インストール成功と保存先は未確認のままとする。
追加調査や再生成は行わない。

## 2026-10-24 アプリrecord作成と相談受付

最新humanの「作成してよい」に基づき、親CUAがTeam 9HYDLV4RY2のApp Store Connectアプリrecordを作成したとの共有を受けた。
macOS、AI Usage Buddy、主言語日本語、会社PUREROAST&BREW, LIMITED LIABILITY COMPANY、Bundle ID com.aiusagebuddy.app.store、SKU AIUsageBuddy-macOSである。
accessは制限なしで、UIの制限ありはdisabledだった。
一覧reload後にAI Usage Buddy、macOS 1.0、提出準備中を確認し、アプリ情報画面でName、Bundle ID、SKU、Apple ID 6826562310、主言語の一致を確認した。
既定Store versionは1.0で、project候補1.0.1/build 2との整合は未実施。
自動releaseは既定表示のままで変更も保存もしていない。
無料価格等は未設定であり、upload、審査提出、公開は未実施である。

親は既存human承認済み日本語文案をそのまま使用し、数値ID 6826562310とmacOSを設定して公式App Reviewのその他/Eメールフォームから1件送信した。
公式/submit受付画面「ご連絡ありがとうございました。お問い合わせ番号103007143655」を親がAXで確認した。
以前の未作成、数値ID不足、未送信のblockは解消したが、受付はApple回答や事前承認を意味しない。
デモは未実装で、審査アクセス方法の判断はApple回答待ちである。

親保存proofは/private/tmp/aiusagebuddy-app-record-created-1792841681531.png、/private/tmp/aiusagebuddy-app-record-info-1792841708990.png、/private/tmp/aiusagebuddy-apple-inquiry-received-1792841748366.png。
この担当は画像を開かず、共有された確認結果だけを記録した。
過去の未送信等の記録は履歴として保持し、現在状態は本節を優先する。
disabledの自動contact値、認証情報、session等は記録していない。
