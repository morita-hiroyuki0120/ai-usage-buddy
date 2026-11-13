# Store署名付きarchive・export・uploadの手順

作成日：2026-11-11。
手順は[scripts/store-release.sh](../scripts/store-release.sh)に実装した。
このdocの作成時点では、署名、archive、export、upload、profileインストールのいずれも実行していない。
現在はnot-readyのため、`preflight`が正しく失敗することだけを確認した。

## 前提

- Xcodeは27.1（Build 27A9275）で、`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`を使う。
- Team `9HYDLV4RY2`、BID `com.aiusagebuddy.app.store`、候補version 1.0 / build 2。
- Store profile「AI Usage Buddy Mac App Store」のUUIDは`12df9150-9fe1-4e9b-a2a1-ba399280778b`。
- ダウンロード済みprofileは`~/Downloads/AI_Usage_Buddy_Mac_App_Store.provisionprofile`で、未インストール。
- 承認receiptは`approval.json`として専用directoryに置き、そのSHA-256を`AI_USAGE_BUDDY_STORE_APPROVAL_SHA256`で渡す。
- receiptの`signing.profileSpecifier`はprofile UUID、`signing.profileUUID`は空文字にする。
- archiveは`PROVISIONING_PROFILE_SPECIFIER`だけをUUIDで渡し、`prepare.py`はこの2値の一致を検査するため。

## 確認した証明書の状況

`security find-identity`の名前とSHA-1だけを確認した。秘密鍵とKeychainには触れていない。

| 種別 | 状態 | SHA-1 |
|---|---|---|
| Apple Distribution: PUREROAST&BREW, LIMITED LIABILITY COMPANY (9HYDLV4RY2) | codesigning identityとして有効、1本 | 6AE300F004DC636FB2D4BD590366491E31F372BA |
| 3rd Party Mac Developer Installer: PUREROAST&BREW, LIMITED LIABILITY COMPANY (9HYDLV4RY2) | `find-identity -v`に有効identityとして存在（codesigningポリシーには出ない） | 586896B28821B23E6EA0C01E5E01D21E7A81A908 |
| Apple Development / Developer ID Application | 存在するが提出には使わない | - |

Mac Installer Distributionという名前の証明書は無く、installerは旧名称の3rd Party Mac Developer Installerである。
export時のinstallerSigningCertificateは、この名前（またはSHA-1）で指定する。
自動selectorの`Mac Installer Distribution`が旧名称の証明書を選べるかは未確認。

## 手順と承認

| 手順 | コマンド | 副作用 | 承認 |
|---|---|---|---|
| 1. 事前検査 | `scripts/store-release.sh preflight --inputs DIR --approval-sha SHA` | なし | 不要 |
| 2. profileインストール | `scripts/store-release.sh install-profile --execute` | `~/Library/MobileDevice/Provisioning Profiles/<UUID>.provisionprofile`を新規作成 | 必要（既存は上書きしない） |
| 3. archive | `scripts/store-release.sh archive --inputs DIR --approval-sha SHA --execute` | Keychainの秘密鍵を使う署名、`build/store-archive-<日時>/`を新規作成 | 必要（Keychainのアクセス許可ダイアログが出る場合は人が操作） |
| 4. archive検査 | `scripts/store-release.sh verify --archive PATH --inputs DIR --approval-sha SHA` | `build/store-verify-<日時>/`を新規作成 | 不要 |
| 5. export | `scripts/store-release.sh export --archive PATH --execute` | installer証明書でpkg署名、`build/store-export-<日時>/`を新規作成 | 必要 |
| 6. export検査 | `scripts/store-release.sh verify --export DIR --inputs DIR --approval-sha SHA` | pkgを新規dirへ展開して検査 | 不要 |
| 7. upload | `scripts/store-release.sh upload --pkg PATH` | なし（コマンド表示のみ） | 必要（認証と実行は人が行う） |

`install-profile`、`archive`、`export`は`--execute`が無いとコマンドを表示するだけである。
`upload`は`--i-have-approval`があっても実行せず、コマンドを表示するだけである。
認証情報はscriptに書かず、読まない。
App Store Connect API keyまたはapp専用passwordは人が用意する。

## 各手順の仕様

archiveは`Release`、`generic/platform=macOS`、Manual署名、`CODE_SIGN_IDENTITY="Apple Distribution"`、`DEVELOPMENT_TEAM=9HYDLV4RY2`、`PROVISIONING_PROFILE_SPECIFIER=<UUID>`で実行する。
`-arch`は付けない（destinationとの併用でエラーになるため）。
`AI_USAGE_BUDDY_STORE_INPUTS`は絶対pathでコマンドラインから渡し、`prepare.py`のnoncanonical-path検査を避ける。
helperの配置と本文の同梱は既存のCopyFilesとprepare-store-archive.shに任せ、scriptは何も追加しない。
exportのmethodは、Xcode 27.1の`xcodebuild -help`が`app-store-connect`を挙げ、`app-store`をdeprecatedとしているため`app-store-connect`を使う。
ExportOptions.plistには`signingStyle=manual`、`teamID`、`provisioningProfiles={BID: UUID}`、`installerSigningCertificate`、`manageAppVersionAndBuildNumber=false`、`uploadSymbols=false`を入れる。
`manageAppVersionAndBuildNumber`をfalseにするのは、Xcodeがbuild番号を書き換えると検査済みの1.0/2とずれるため。
verifyはcodesignの識別子、Team、Authority、runtime、entitlements、embedded.provisionprofile、helperの署名とentitlements（sandboxとinheritのみ）、StoreNotices、archiveのProductsがappのみであること、pkgのinstaller署名を検査する。
exportしたappには、承認済み入力を渡した場合に限り`prepare-store-archive.sh --verify-app`も実行する。

## 現在のblocker

1. noticesとsource案内の承認が無く、`distributionStatus`は`not-ready`である。承認receipt（`approval.json`）も存在しない。
2. Store profileが未インストールである。
3. approved inputs directoryとreceiptのSHA-256が未用意である。
4. receiptの`signing`はprofileSpecifier=UUID、profileUUID=空文字にする必要がある。
5. 無料価格、審査アクセス（Appleへの相談は回答待ち）など、App Store Connect側の残件がある。これらは[準備状況](store-submission-readiness.md)を参照する。

2026-11-11時点の`preflight`は、blockerを3件（not-ready、inputs未指定、profile未インストール）と報告して終了コード1で失敗する。

## 未確認点

- `CODE_SIGN_IDENTITY="Apple Distribution"`が`EXPANDED_CODE_SIGN_IDENTITY`の40桁fingerprintに展開され、prepare.pyの検査を通るか。通らない場合は`--identity`にSHA-1を渡す。
- 旧名称のinstaller証明書を`installerSigningCertificate`の名前指定で選べるか。
- 実profileが付与するentitlementsが、prepare.pyの許可リストに収まるか。
- helperのCodeSignOnCopy再署名後の入れ子署名がpkgでも保たれるか。
- `altool --upload-app`のオプション（`--type`の要否を含む）。実行前に`xcrun altool --help`で確認する。
- build 2がApp Store Connect上で未使用かどうか。

## 2026-11-13 build 3の成果物と検証結果

入力は`build/store-approved-inputs-20261113/`（approval.json SHA-256 `742d9fe9acfef0c4d2abaea272fef0050501d66c7cdf0afddddaea208a778c4e`）、helperは0.167.2である。
`preflight`は`--expect-version 1.0 --expect-build 3`付きでall checks passedだった。

| 成果物 | path |
|---|---|
| archive | `build/store-archive-20261113-102409/AIUsageBuddy.xcarchive` |
| export | `build/store-export-20261113-102504/export/AI Usage Buddy.pkg`（83,223,321 bytes、SHA-256 `66e5034262aeaeebd60761097efd8e6182b1e1c4b520d9aabe02613b2f9753a7`） |
| archiveのverify | `build/store-verify-20261113-102542/` |
| exportのverify | `build/store-verify-20261113-102543/`（pkgの展開先を含む） |

archiveとexportの`verify`はどちらもall checks passedだった。
確認できた内容は次のとおりである。

- Info.plistはCFBundleShortVersionString=1.0、CFBundleVersion=3、LSApplicationCategoryType=public.app-category.productivityである。
- 親appのentitlementsは、application-identifier、team-identifier、app-sandbox、network.clientだけである。network.serverは無い。
- helperは0.167.2で、entitlementsはsandboxとinheritだけである。prepare.pyの検証で、tar.gz由来の元バイナリとの一致も確認した（CodeDirectory以外）。
- archiveとexportの両方で、helperの`otool -L`にliblzmaは無く、`nm -u`に`_lzma_`も無い。
- export後のappの2つのMach-O（親とhelper）が参照する`/usr/lib`のdylibは、すべてSDKの.tbdに存在する。helperはlibSystem、libobjc、libbz2、libiconvだけで、親はlibSystem、libobjc、libswift系である。
- pkgはinstaller証明書（Team 9HYDLV4RY2）で署名されている。

実profileが付与するentitlementsは、prepare.pyの許可リストに収まった。
upload、審査提出、App Store Connectの操作は行っていない。
