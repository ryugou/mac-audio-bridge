# Mac Audio Bridge

macOS の任意の入力デバイスを任意の出力デバイスへ pass-thru するメニューバー常駐ツール。

## 機能

- メニューバー常駐（Dock 非表示）
- 入力 / 出力デバイスを個別に選択（システムデフォルトに追従も可）
- 入出力が同一デバイスのときフィードバックループを自動検知して停止
- ログイン時自動起動（SMAppService）
- 選択デバイスが切断されたら自動停止、再接続で自動再開
- 多重起動禁止（`NSRunningApplication` 検知 + `LSMultipleInstancesProhibited`）

## 必要環境

- macOS 13.0 以上
- Xcode 16 以上
- [xcodegen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

## ビルド

```bash
xcodegen generate
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Release -derivedDataPath build/ build
open build/Build/Products/Release/MacAudioBridge.app
```

## 開発環境（任意）

SourceKit-LSP に Xcode の build settings を渡してエディタの補完・診断を有効化する場合：

```bash
brew install xcode-build-server
xcode-build-server config -project MacAudioBridge.xcodeproj -scheme MacAudioBridge
```

`buildServer.json` が生成されますが `.gitignore` 済みです。

## テスト

ユニットテスト（Pure Swift ロジック層）：

```bash
xcodebuild test -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -destination 'platform=macOS'
```

CoreAudio / AVFoundation 依存層は実機での手動結合テスト（手順は spec §9.6）。

## 使い方

メニューバーアイコンから：

- **ON / OFF トグル**: pass-thru の開始 / 停止
- **Input Device** / **Output Device**: 「System Default 追従」または個別デバイス
- **ログイン時に自動起動 + 自動 Run**: ログイン項目に登録、起動時に Bridge を即 ON

## ログ

OSLog で以下のサブシステム / カテゴリに出力されます：

```bash
log stream --predicate 'subsystem == "com.ryugo.mac-audio-bridge"' --info
```

カテゴリ: `engine` / `aggregate` / `device-monitor` / `permissions` / `app`

## 既知の制限

- デバイス切替時に数百 ms の音切れが発生
- マイクとスピーカーが物理的に近い場合、当然ハウリングが発生する（pass-thru の物理的特性）
- Bluetooth デバイスを SCO/HFP マイクとして使う場合、サンプリングレートが 16kHz 以下に落ちる（macOS 仕様）

## 設計ドキュメント

- 設計仕様: [`docs/superpowers/specs/2026-05-07-mac-audio-bridge-design.md`](docs/superpowers/specs/2026-05-07-mac-audio-bridge-design.md)
- 実装計画: [`docs/superpowers/plans/2026-05-07-mac-audio-bridge.md`](docs/superpowers/plans/2026-05-07-mac-audio-bridge.md)

実装上、spec §8.7 の不変条件 I5（tap 禁止）は緩和し、`AVAudioPlayerNode` 中継方式（`inputNode` の tap で取得したバッファを player に schedule する標準パターン）を採用しています。`inputNode → mainMixerNode` 直接接続では HAL Input AU と HAL Output AU の I/O cycle が同期せず、特に input/output の channel 数や sample rate が異なるとき信号が流れない問題への対応です。

## ライセンス

MIT (LICENSE 参照)
