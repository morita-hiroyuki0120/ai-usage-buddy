# 既存catによるAppIcon

2026-10-23にユーザーが1024px画像を見て「このアイコンで進める」と採用を承認した。
デザインは採用承認済みだが、Store提出物は未完成であり、公開や審査提出の承認ではない。
新しい絵や外部素材は使わず、共有のCatDrawingとCharacterStateを直接コンパイルする。
既存normal状態のframe 0を、Aqua appearanceのsystemTeal、濃紺の角丸背景に描画する。
メニューバーと状態表示の描画本文、サイズ、タイミング、5フレームの仕様は変更しない。

```sh
bash Tools/AppIcon/generate.sh
```

standalone rendererだけを一時ディレクトリへコンパイルし、既存Contents.jsonに従ってPNGを生成する。
同じmacOS/AppKit環境で再生成できる構成であり、systemTealの解決値が異なるOS間でのbytes一致は保証しない。
16/32/128/256/512ptの1x/2x計10ファイルをStore/Assets.xcassets/AppIcon.appiconsetへ出力する。
1024px候補は`Store/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png`。
assetはnative targetだけへ登録し、SwiftPM resourcesには追加しない。
生成はアプリを起動せず、署名も行わない。
親のGO後、DirectとStore flagの全体テスト各186件、および専用DerivedDataでのunsigned native Release buildが成功した。
確認結果と未完了の提出条件はローカル作業記録（公開対象外）に記録する。
