# Mac Audio Bridge

macOS の任意の入力デバイスを任意の出力デバイスへ pass-thru するメニューバー常駐ツール。

## 必要環境

- macOS 13.0 以上
- Xcode 16 以上
- xcodegen (`brew install xcodegen`)

## ビルド

```bash
xcodegen generate
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Release build
```

## 使い方

メニューバーアイコンから:

- ON/OFF トグル
- 入力デバイス / 出力デバイス選択
- ログイン時自動起動の有無

## 設計ドキュメント

`docs/superpowers/specs/2026-05-07-mac-audio-bridge-design.md` 参照。

## ライセンス

MIT (LICENSE 参照)
