# Store用Xcodeプロジェクト

`AIUsageBuddyStoreApp`は、既存の`Sources/AIUsageBuddy`を直接コンパイルする唯一のnative macOS app target。
共有scheme名は`AIUsageBuddyStore`。
ソースとlproj resourceは`PBXFileSystemSynchronizedRootGroup`でtargetへ一度だけ含める。
ja/enの`Localizable.strings`は`PBXVariantGroup`でまとめ、Copy Bundle Resourcesへ二重登録しない。

両configurationで`AI_USAGE_BUDDY_APP_STORE`を定義する。
`Bundle.module`互換extensionはこのターゲットだけに含める。

署名方式はManualで、DevelopmentとDistributionのidentity欄、provisioning profileは未設定。
通常buildにはhelperを同梱せず、compile確認専用を維持する。
Release archiveには[offline包装工程](../Tools/StorePackaging/README.md)を追加したが、現在の`distributionStatus: not-ready`と未承認noticesによりpreflightを拒否する。
実archive、配布署名、exportは未検証であり、提出用artifactは未完成である。

プロジェクトとschemeの確認:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -list -project Store/AIUsageBuddy.xcodeproj
```

署名を無効にしたarm64 compile check:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Store/AIUsageBuddy.xcodeproj \
  -scheme AIUsageBuddyStore -configuration Debug \
  -destination 'generic/platform=macOS' -arch arm64 \
  -derivedDataPath build/app-store-project-check \
  CODE_SIGNING_ALLOWED=NO build
```

この出力はcompile確認専用。
既存のpackage-releaseやDMGスクリプトでStore版を梱包せず、Store helperの配布監査と実装が終わるまで提出しない。
