# mac-audio-bridge 設計仕様書

- **作成日**: 2026-05-07
- **プロジェクト**: mac-audio-bridge
- **リポジトリ**: https://github.com/ryugou/mac-audio-bridge
- **macOS 最低バージョン**: 13.0
- **配布形態**: 個人利用・local signed build（Sandbox 無効）
- **ステータス**: 初版（ブレスト合意済み、ユーザーレビュー待ち）

---

## 1. 概要

macOS の入力デバイスを指定した出力デバイスに pass-thru するメニューバー常駐ツール。入力・出力の両方をユーザーがメニューから選択可能。初期値は両方ともシステムデフォルト。

主な特徴:

- メニューバー常駐型（SwiftUI `MenuBarExtra`）
- pass-thru は無加工（ゲイン 1.0）
- AVAudioEngine + 動的に作成したプライベート AggregateDevice で実装
- フィードバックループ（入力 == 出力）を自動検知して停止
- システムデフォルトのデバイス変更や接続/切断にリアルタイム追従
- ログイン時自動起動（`SMAppService`）対応

---

## 2. 動作要件

### 2.1 入力（Input Device）

- メニューから選択可能
- 選択肢: 「システムデフォルトに追従」 + 接続中の各入力デバイス
- 初期値: システムデフォルト
- 「システムデフォルト」選択時は、システム入力の変更に自動追従

### 2.2 出力（Output Device）

- メニューから選択可能
- 選択肢: 「システムデフォルトに追従」 + 接続中の各出力デバイス
- 初期値: システムデフォルト
- 「システムデフォルト」選択時は、システム出力の変更に自動追従

### 2.3 音声処理

- pass-thru（無加工で右から左に流す）
- ゲイン: 1.0 固定
- フォーマット変換: 入出力のフォーマットに合わせて AVAudioEngine の `mainMixerNode` で自動変換
  - サンプルレート差（48kHz ↔ 44.1kHz 等）
  - チャンネル数差（モノラル ↔ ステレオ）

### 2.4 フィードバックループ防止

- 入力 UID == 出力 UID の場合: 自動停止（`StopReason.feedbackLoop`）
- 検知タイミング:
  - エンジン起動時
  - ユーザーがデバイス選択を変更した時
  - システムデフォルトが変更された時（`.systemDefault` 選択時）

### 2.5 デバイス変更検知

#### システムデフォルトの変更検知

- 入力: `kAudioHardwarePropertyDefaultInputDevice` のリスナー登録
- 出力: `kAudioHardwarePropertyDefaultOutputDevice` のリスナー登録
- 「システムデフォルト追従」設定時のみエンジン再構築

#### デバイス接続/切断検知

- `kAudioHardwarePropertyDevices` のリスナー登録
- 選択中のデバイスが切断された場合: エンジン停止、メニューで警告表示
- 一定時間（5 秒）以内に同 UID で再出現したら自動再開、超えたら停止維持
- 短時間の連続通知は 200〜500ms の debounce で吸収

---

## 3. UI 仕様

### 3.1 メニューバーアイコン

| 状態 | SF Symbol | 色 |
|------|-----------|-----|
| 動作中 (`running`) | `speaker.wave.2` | 通常 |
| 停止中 (`idle` / `stopped(.userToggledOff)`) | `speaker.slash` | グレーアウト |
| フィードバックループ検知 (`stopped(.feedbackLoop)`) | `exclamationmark.triangle.fill` | 黄 |
| デバイス未接続 / エンジン失敗 / 権限拒否 | `exclamationmark.triangle.fill` | 赤 |

### 3.2 メニュー項目

```
┌─────────────────────────────────────────┐
│ ◉ ON / OFF（トグル）                     │
├─────────────────────────────────────────┤
│ 状態: 動作中 (USB Mic → AirPods Pro)     │ ← 1 行で現状を要約
├─────────────────────────────────────────┤
│ Input Device                            │
│   ✓ System Default (内蔵マイク)         │
│   ────                                  │
│     内蔵マイク                          │
│     USB Mic                             │
├─────────────────────────────────────────┤
│ Output Device                           │
│     System Default (AirPods Pro)        │
│   ────                                  │
│     内蔵スピーカー                       │
│   ✓ AirPods Pro                         │
├─────────────────────────────────────────┤
│ Settings                                │
│   ☑ ログイン時に自動起動 + 自動 Run      │
├─────────────────────────────────────────┤
│ Quit                                    │
└─────────────────────────────────────────┘
```

#### 状態表示行の文言例

| 状態 | 表示 |
|------|------|
| running | `状態: 動作中 (USB Mic → AirPods Pro)` |
| feedbackLoop | `状態: ⚠ 入出力が同一デバイスです` |
| deviceDisconnected（フォールバック中） | `状態: ⚠ 選択デバイス未接続: USB Mic（フォールバック: 内蔵マイク）` |
| micPermissionDenied | `状態: ✕ マイク権限が拒否されています` + 「システム設定を開く」ボタン |
| engineFailed | `状態: ✕ エンジン起動失敗: <error>` |

---

## 4. 設定保存（Preferences）

`UserDefaults` に以下を保存。

| キー | 型 | 既定値 | 説明 |
|------|------|--------|------|
| `device.input` | String | `"system_default"` | 入力選択。`"system_default"` または特定 UID |
| `device.output` | String | `"system_default"` | 出力選択。同上 |
| `app.autoRun` | Bool | `false` | true なら ログイン時自動起動 + 起動直後に Run |

`autoRun` のセマンティクス:

- `true`: SMAppService 登録 + アプリ起動時に Bridge を即 ON
- `false`: SMAppService 解除 + アプリ起動時は Bridge OFF（ユーザーが明示的に ON にする）

「前回の ON/OFF 状態の復元」は YAGNI で省略（autoRun に集約）。手動起動時は常に OFF からスタートし、ユーザーが明示的に ON にする。

### スキーマ進化耐性

- 未知キーは無視
- 既存キーで型不一致 → 既定値にフォールバック + ログ出力

---

## 5. 起動・終了シーケンス

### 5.1 起動時

```
1. SMAppService が登録されていれば、ログイン時に macOS が自動起動
2. アプリ起動 → Preferences 読込
3. 残骸 AggregateDevice の掃除（UID プレフィックス
   "com.ryugo.mac-audio-bridge.aggregate.*" を全削除）
4. DeviceMonitor のリスナー登録
   - kAudioHardwarePropertyDefaultInputDevice
   - kAudioHardwarePropertyDefaultOutputDevice
   - kAudioHardwarePropertyDevices
5. autoRun == true なら AudioBridgeEngine.start() を試行
   - DeviceSelection で選択デバイスを解決
   - 未接続なら一時的に systemDefault にフォールバック（メニュー警告）
   - feedback loop 検知なら .stopped(.feedbackLoop)
   - マイク権限未許可なら要求 → 拒否なら .stopped(.micPermissionDenied)
   - 正常なら AggregateDevice 構築 → AVAudioEngine 起動 → .running
6. autoRun == false なら BridgeStatus = .idle のまま、ユーザーのトグル待機
```

### 5.2 終了時 (`applicationWillTerminate`)

```
1. DeviceMonitor の全リスナー解除
2. AVAudioEngine.stop()
3. AggregateDeviceManager.destroy()  ← 重要: 残骸防止
4. atexit(3) でも保険として 2 と 3 を呼ぶ
```

---

## 6. エラーハンドリング

### 6.1 仕様書ベースのケース

| # | ケース | 挙動 |
|---|--------|------|
| 1 | 選択デバイス未接続で起動 | systemDefault に一時フォールバック、メニュー警告。再接続検知で本来の選択に復帰 |
| 2 | 動作中に選択デバイス切断 | engine.stop() → AggregateDevice 破棄 → `.stopped(.deviceDisconnected(uid:))` |
| 3 | 入力 == 出力（feedback loop） | `.stopped(.feedbackLoop)` + 警告アイコン |
| 4 | マイク権限拒否 | `.stopped(.micPermissionDenied)` + メニュー表示 + 設定ボタン |
| 5 | サンプルレート不一致 | `mainMixerNode` 経由で AVAudioEngine が自動変換（実装上は何もしない） |

### 6.2 設計上カバーする追加エッジケース

| # | ケース | 挙動 |
|---|--------|------|
| 6 | AggregateDevice 作成失敗 | `.stopped(.engineFailed(error))` でメニューにエラー表示。リトライ可能 |
| 7 | 前回終了時の AggregateDevice 残骸 | 起動時に UID プレフィックスマッチで全削除（クラッシュ後の起動でも安全） |
| 8 | AVAudioEngine.start() 失敗 | catch → AggregateDevice 破棄 → `.stopped(.engineFailed(error))` |
| 9 | SMAppService 登録失敗 | チェックボックスのトグル失敗時 alert + 状態ロールバック |
| 10 | システムデフォルトデバイスが nil | `.stopped(.engineFailed("no system default"))` |
| 11 | 同 UID デバイスの瞬断と再出現 | 5 秒以内の再出現なら自動再開、超えたら停止維持 |
| 12 | `mediaServicesWereReset` 通知 | エンジンと AggregateDevice をフル再構築 |
| 13 | デバイス変更通知の連続発火 | DeviceMonitor で 200〜500ms debounce |

### 6.3 ロギング

- `OSLog` (`Logger`) を使用
- Subsystem: `com.ryugo.mac-audio-bridge`
- カテゴリ: `engine` / `device-monitor` / `aggregate` / `permissions`
- レベル: `error` / `info` の 2 段階のみ
- 出力対象: 起動・停止・エラー・デバイス変更

---

## 7. 実装アーキテクチャ

### 7.1 採用方式: AVAudioEngine + 動的プライベート AggregateDevice

異なる入力デバイスと出力デバイスを束ねるプライベート AggregateDevice を CoreAudio HAL API で動的作成し、AVAudioEngine をそこにバインドする方式。

**選定理由**:

1. 仕様書の AVAudioEngine 指定と整合
2. AggregateDevice の動的作成は macOS 標準のパターン
3. format 変換が AVAudioEngine の `mainMixerNode` で自動処理される
4. ring buffer 自前実装の落とし穴（lock-free、エイリアシング）を回避できる

### 7.2 検討した他の選択肢

| 方式 | 採用しない理由 |
|------|--------------|
| AUHAL 直接 2 つ + lock-free ring buffer | コード量多、ring buffer 自前実装、format 変換も自前 |
| AVAudioEngine 2 つ + AVAudioSourceNode/SinkNode + ring buffer | 2 エンジン同期問題、レイテンシ大、安定性不明 |

### 7.3 コンポーネント分割

責務単位で 10 コンポーネント。**Pure Swift（テスタブル）**と **CoreAudio/AVFoundation 依存（手動確認）** を明確に分離。

| # | 名前 | 責務 | テスト |
|---|------|------|--------|
| 1 | `MacAudioBridgeApp` | SwiftUI エントリポイント、`@main`、`MenuBarExtra` | 手動 |
| 2 | `MenuBarView` / `DeviceMenuSection` / `StatusIcon` | メニュー UI | 手動 |
| 3 | `AppState` | UI 表示用の集約状態（`ObservableObject`） | 手動 |
| 4 | `Preferences` | UserDefaults の薄いラッパー | ★ユニット |
| 5 | `DeviceSelection` | `(DeviceChoice, systemDefault, connected) → ResolvedDevice?` | ★ユニット |
| 6 | `FeedbackLoopDetector` | 入力 UID == 出力 UID 判定 | ★ユニット |
| 7 | `BridgeStateMachine` | 状態遷移ロジック（純関数） | ★ユニット |
| 8 | `AudioBridgeEngine` | AVAudioEngine 起動・停止・再構築 | 手動 |
| 9 | `AggregateDeviceManager` | CoreAudio HAL で AggregateDevice 作成・破棄・残骸掃除 | 手動 |
| 10 | `DeviceMonitor` | CoreAudio プロパティリスナー登録・通知配信 | 手動 |
| 11 | `LoginItemController` | SMAppService.mainApp の register/unregister | 手動 |
| 12 | `PermissionHelper` | マイク権限要求 | 手動 |

### 7.4 主要な状態モデル

#### `BridgeStatus`

```swift
enum BridgeStatus: Equatable {
    case idle
    case starting
    case running
    case stopped(StopReason)
}

enum StopReason: Equatable {
    case userToggledOff
    case deviceDisconnected(uid: String)
    case feedbackLoop
    case micPermissionDenied
    case engineFailed(message: String)
}
```

#### `DeviceChoice`

```swift
enum DeviceChoice: Equatable {
    case systemDefault
    case specific(uid: String)
}
```

#### `ResolvedDevice`

```swift
struct ResolvedDevice: Equatable {
    let uid: String
    let name: String
    let isConnected: Bool
}
```

### 7.5 状態遷移トリガー

| トリガー | 影響 |
|---------|------|
| ユーザーが ON/OFF トグル | `idle ⇄ running`、Preferences 保存 |
| ユーザーがデバイス選択変更 | エンジン停止 → AggregateDevice 再構築 → 再起動。途中で feedback loop 検知すれば停止 |
| `kAudioHardwarePropertyDefaultInputDevice` 変更通知 | `DeviceChoice == .systemDefault` の時のみエンジン再構築 |
| `kAudioHardwarePropertyDefaultOutputDevice` 変更通知 | 同上（出力側） |
| `kAudioHardwarePropertyDevices` 変更通知 | 接続デバイスリスト更新、選択中が切断 → 停止、再接続 → 再開 |
| マイク権限拒否 | `.stopped(.micPermissionDenied)` |
| `mediaServicesWereReset` | フル再構築 |

---

## 8. データフロー & pass-thru 実装詳細

### 8.1 AggregateDevice 作成

`AudioHardwareCreateAggregateDevice()` に渡す dict:

```
{
  kAudioAggregateDeviceUIDKey:
    "com.ryugo.mac-audio-bridge.aggregate.<UUID>",
  kAudioAggregateDeviceNameKey: "MacAudioBridge",
  kAudioAggregateDeviceIsPrivateKey: 1,                   // ← プライベート
  kAudioAggregateDeviceMainSubDeviceKey: <output UID>,    // ← 出力をマスタークロックに
  kAudioAggregateDeviceSubDeviceListKey: [
    { kAudioSubDeviceUIDKey: <input UID> },
    { kAudioSubDeviceUIDKey: <output UID> }
  ]
}
```

**ポイント**:

- `MainSubDevice` を出力デバイスにすることで、出力側のクロックがマスターになりドリフトを最小化
- `IsPrivate = 1` でシステム設定や他アプリには出現しない
- UID に UUID を含めることで、複数インスタンスや前回の残骸との衝突を防止

### 8.2 AVAudioEngine 構築

```swift
let engine = AVAudioEngine()

// inputNode の AUHAL に AggregateDevice をセット
let inputAU = engine.inputNode.auAudioUnit
try inputAU.setDeviceID(aggregateDeviceID)  // 自前ヘルパー

// outputNode も同じ AggregateDevice
let outputAU = engine.outputNode.auAudioUnit
try outputAU.setDeviceID(aggregateDeviceID)

// pass-thru 結線（format: nil で自動マッチ）
engine.connect(engine.inputNode, to: engine.mainMixerNode, format: nil)

try engine.start()
```

`AUAudioUnit.setDeviceID()` は AVFoundation 標準にないため、`kAudioOutputUnitProperty_CurrentDevice` を `audioUnit` 経由で設定する自前 extension として実装する。

### 8.3 pass-thru 経路

```
[Input Device]
      │
      ▼
  AggregateDevice (input subdevice)
      │
      ▼
  AVAudioEngine.inputNode (HAL Input AU)
      │  ← format: native of input device
      ▼
  AVAudioEngine.mainMixerNode (auto format conversion)
      │  ← format: native of output device
      ▼
  AVAudioEngine.outputNode (HAL Output AU)
      │
      ▼
  AggregateDevice (output subdevice)
      │
      ▼
[Output Device]
```

`mainMixerNode` 経由で:

- サンプルレート変換（AVAudioConverter 内部使用）
- チャンネル数差の自動補正
- ゲインは pass-thru なので 1.0 固定

### 8.4 起動シーケンス（`AudioBridgeEngine.start()`）

```
1. DeviceSelection で入出力 UID 解決
2. FeedbackLoopDetector でループチェック
   └─ ループなら .stopped(.feedbackLoop) で return
3. AggregateDeviceManager.create() → aggregateDeviceID
4. AVAudioEngine 構築 + AU に AggregateDevice バインド
5. inputNode → mainMixerNode 接続
6. engine.start()
   └─ 例外時: AggregateDevice 破棄 → .stopped(.engineFailed)
7. BridgeStatus = .running
```

### 8.5 再構築シーケンス（`AudioBridgeEngine.restart()`）

```
1. engine.stop()
2. AggregateDeviceManager.destroy(currentID)
3. start() を再実行
```

数百 ms の音切れがこの 1〜3 の間に発生（仕様で許容済み）。

### 8.6 終了シーケンス

```
1. DeviceMonitor リスナー解除
2. engine.stop()
3. AggregateDeviceManager.destroy()
```

破棄を確実に行わないとシステムに残骸が残る。`applicationWillTerminate` と `atexit(3)` の二重防御。

---

## 9. テスト戦略

### 9.1 採用方針

「**ロジック層のみユニットテスト + 手動結合テスト**」（CI なし）。

### 9.2 フレームワーク

- **Swift Testing**（`@Test` 構文、Xcode 16+ 必須）

### 9.3 テスト対象

| モジュール | テスト内容 |
|-----------|-----------|
| `Preferences` | UserDefaults round-trip、デフォルト値、スキーマ進化耐性（未知キー無視、型不一致フォールバック） |
| `DeviceSelection` | `(DeviceChoice, systemDefault, connectedDevices) → ResolvedDevice?` の純関数。`.systemDefault` / `.specific(uid)` 接続中 / 未接続 の 3 ケース |
| `FeedbackLoopDetector` | 同一 UID → true、異なる → false、片方 nil → false |
| `BridgeStateMachine` | `userToggleOff` → `idle`、`deviceDisconnected` → `stopped(...)`、再接続 → `running` 復帰 等の状態遷移 |
| AggregateDevice UID 命名 | プレフィックスマッチ・衝突しない |

### 9.4 テスト対象**外**（手動確認）

- `AudioBridgeEngine`（実機で耳確認）
- `AggregateDeviceManager`（`system_profiler SPAudioDataType` で AggregateDevice の出現/消失確認）
- `DeviceMonitor`（実機でデバイス抜き挿し確認）
- `LoginItemController`（再ログイン後の自動起動確認）
- `MenuBarView` / `StatusIcon`（各状態の見た目確認）
- `PermissionHelper`（権限ダイアログ確認）

### 9.5 DI 用 Protocol 抽象化

```swift
protocol DeviceProvider {
    var connectedInputDevices: [Device] { get }
    var connectedOutputDevices: [Device] { get }
    var defaultInputDevice: Device? { get }
    var defaultOutputDevice: Device? { get }
}

// 本番: CoreAudioDeviceProvider（CoreAudio 依存）
// テスト: MockDeviceProvider（任意のデバイスリストを注入）
```

### 9.6 手動結合テスト チェックリスト

実装完了時に以下を確認:

- [ ] アプリ起動 → 既定で OFF（または autoRun に従う）
- [ ] 入力に内蔵マイク、出力に内蔵スピーカーを選択 → 喋ると聞こえる
- [ ] 入力と出力を同じデバイスに → 自動停止 + 警告アイコン
- [ ] 動作中に出力デバイスを抜く → 停止 + エラーアイコン
- [ ] 「システムデフォルト追従」設定中、システム出力を切替 → 自動追従
- [ ] アプリ終了 → AggregateDevice が消える（`system_profiler SPAudioDataType` で確認）
- [ ] ログイン項目に登録 → 再ログインで自動起動 + autoRun true なら稼働中
- [ ] マイク権限拒否 → メニューでエラー表示 + 設定を開けるボタン
- [ ] クラッシュ模擬（`kill -9`）後の再起動 → 残骸 AggregateDevice が掃除される
- [ ] 入出力で異なるサンプルレートのデバイス → format 変換されて pass-thru

---

## 10. ファイル構成

### 10.1 Xcode プロジェクト

```
mac-audio-bridge/
├── MacAudioBridge.xcodeproj/
├── MacAudioBridge/                       # アプリ本体ターゲット
│   ├── MacAudioBridgeApp.swift           # @main + MenuBarExtra
│   ├── Info.plist                        # NSMicrophoneUsageDescription
│   ├── Assets.xcassets/                  # アイコン
│   │
│   ├── App/
│   │   ├── AppState.swift                # ObservableObject、UI 向けハブ
│   │   └── Preferences.swift             # UserDefaults ラッパー ★テスト対象
│   │
│   ├── UI/
│   │   ├── MenuBarView.swift
│   │   ├── DeviceMenuSection.swift
│   │   └── StatusIcon.swift
│   │
│   ├── Core/                             # ★Pure Swift、テスト対象
│   │   ├── BridgeStatus.swift
│   │   ├── StopReason.swift
│   │   ├── DeviceChoice.swift
│   │   ├── ResolvedDevice.swift
│   │   ├── DeviceSelection.swift
│   │   ├── FeedbackLoopDetector.swift
│   │   └── BridgeStateMachine.swift
│   │
│   ├── Audio/                            # CoreAudio / AVFoundation 依存
│   │   ├── DeviceProvider.swift          # protocol（DI 用）
│   │   ├── CoreAudioDeviceProvider.swift # 本番実装
│   │   ├── DeviceMonitor.swift
│   │   ├── AggregateDeviceManager.swift
│   │   ├── AUAudioUnit+Device.swift      # setDeviceID extension
│   │   └── AudioBridgeEngine.swift
│   │
│   ├── System/
│   │   ├── LoginItemController.swift     # SMAppService.mainApp
│   │   └── PermissionHelper.swift
│   │
│   └── Logging/
│       └── Log.swift                     # OSLog ラッパー
│
└── MacAudioBridgeTests/                  # ユニットテスト（Swift Testing）
    ├── PreferencesTests.swift
    ├── DeviceSelectionTests.swift
    ├── FeedbackLoopDetectorTests.swift
    ├── BridgeStateMachineTests.swift
    └── Mocks/
        └── MockDeviceProvider.swift
```

### 10.2 リポジトリルート

```
mac-audio-bridge/
├── MacAudioBridge.xcodeproj/
├── MacAudioBridge/...
├── MacAudioBridgeTests/...
├── README.md                             # 概要・ビルド手順・使い方
├── LICENSE                               # MIT を想定
├── .gitignore                            # Xcode 用
├── .claudeignore                         # ビルド成果物除外
└── docs/
    └── superpowers/
        └── specs/
            └── 2026-05-07-mac-audio-bridge-design.md
```

### 10.3 規模目安

- ソース: 約 20 ファイル
- 1 ファイル平均 100〜200 行
- 最大級: `AudioBridgeEngine.swift`（推定 250 行）、`AggregateDeviceManager.swift`（推定 200 行）

### 10.4 命名規則

- ファイル名 = 主たる型名
- protocol は名前に suffix なし（Swift API Design Guidelines）
- enum case は lowerCamelCase
- アクセス制御: 原則 `internal`、テストから見るものは `@testable import`

### 10.5 依存関係グラフ（一方向）

```
            MacAudioBridgeApp
                  │
                  ▼
              AppState ──────────────────────┐
            ┌───┼─────────────────┐          │
            ▼   ▼                 ▼          ▼
       Preferences   BridgeStateMachine   AudioBridgeEngine
                          │                 │
                          │                 ├─ AggregateDeviceManager
                          │                 ├─ DeviceMonitor
                          │                 └─ DeviceProvider (protocol)
                          ▼
              DeviceSelection / FeedbackLoopDetector
              (Pure, depends only on Core types)
```

---

## 11. 制限事項

仕様書記載の制限を再掲:

- デバイス切替時、数百 ms 程度の音切れが発生する可能性あり
- 入出力のサンプルレートが大きく違う場合、品質劣化の可能性
- Bluetooth デバイスをマイクとして SCO/HFP で使う場合、サンプリングレートが 16kHz 以下に落ちる（macOS 仕様）

---

## 12. 将来の拡張: マルチブリッジ（同時並走）

### 12.1 ユースケース

「マイク → URX44」と「マイク → 別の出力先」のように、複数の pass-thru ペアを**同時に並列で**動かしたい。

例:
- セット 1: USB マイク → AirPods Pro
- セット 2: ライン入力 → モニタースピーカー

### 12.2 推定実装ボリューム（MVP 比 +50%）

| 観点 | 追加コスト |
|------|-----------|
| AVAudioEngine 並走 | 軽（10%） |
| Preferences スキーマ配列化 | 軽（10%） |
| メニュー UI（ブリッジ追加/削除、各々のデバイス選択、ON/OFF） | 重（40%） |
| フィードバックループ検知（経路サイクル検知） | 中（25%） |
| メニューバーアイコン状態（一部稼働中、警告中など） | 軽（5%） |

### 12.3 MVP 段階で配慮しておく設計

- `AudioBridgeEngine` を「**単一**ブリッジを表すクラス」として切り出す（インスタンス化可能、将来 `[AudioBridgeEngine]` への拡張容易）
- `Preferences` の保存キーを将来配列化しても破壊的変更が小さい構造に（例: 単一値 → 単要素配列の自動マイグレーション）
- `FeedbackLoopDetector` の API を「単一の入出力ペアを判定」に絞り、将来は「複数ペアを受け取って交差判定」する別関数として拡張

### 12.4 拡張時に主に変更が必要なファイル

- `AppState.swift`（`engine: AudioBridgeEngine` → `engines: [AudioBridgeEngine]`）
- `MenuBarView.swift` / `DeviceMenuSection.swift`（UI 全面刷新）
- `Preferences.swift`（スキーマ進化、マイグレーション）
- `FeedbackLoopDetector.swift`（経路グラフのサイクル検知関数を追加）
- `BridgeStateMachine.swift`（複数ブリッジの集合状態への対応）

---

## 13. 命名・識別子

| 項目 | 値 |
|------|-----|
| プロジェクト名 | mac-audio-bridge |
| Xcode プロジェクト名 | `MacAudioBridge` |
| Bundle ID | `com.ryugo.mac-audio-bridge` |
| Logger Subsystem | `com.ryugo.mac-audio-bridge` |
| AggregateDevice UID プレフィックス | `com.ryugo.mac-audio-bridge.aggregate.` |
| LSUIElement | `true`（Dock に表示しない、メニューバーアプリ） |

---

## 14. 権限（Info.plist）

| キー | 値 |
|------|-----|
| `NSMicrophoneUsageDescription` | `MacAudioBridge は選択された入力デバイスから音声を取得し、選択された出力デバイスへパススルーします。` |
| `LSUIElement` | `YES` |
| `LSMinimumSystemVersion` | `13.0` |

---

## 15. 技術スタック

- 言語: Swift
- フレームワーク: AVFoundation, CoreAudio, SwiftUI（`MenuBarExtra`）, ServiceManagement (`SMAppService`), os.log (`Logger`)
- macOS 最低バージョン: 13.0
- ビルド: Xcode 16+（Swift Testing 対応）
- 配布: 個人利用・ローカル開発者署名のみ（Sandbox 無効）

---

## 16. ブレストの記録

このドキュメントは以下の合意に基づいて作成された:

| 項目 | 決定 |
|------|------|
| プロジェクト名 | `mac-audio-bridge`（候補 audio-bridge / audio-pipe-mac / route-mic から命名再検討） |
| 配布形態 | A. 個人利用・local signed build（Sandbox 無効） |
| テスト戦略 | A. ロジック層のみユニットテスト + 手動結合テスト（CI なし） |
| ログイン時自動起動 | A. SMAppService（macOS 13+ 公式 API） |
| 実装アーキテクチャ | A. AVAudioEngine + 動的プライベート AggregateDevice |
| マルチブリッジ | MVP では単一ペア、将来拡張として記録（§12） |
| AggregateDevice 公開範囲 | A. プライベート（`IsPrivateKey = 1`） |
| autoRun のセマンティクス | ログイン時自動起動 + アプリ起動時に Bridge を即 ON、を 1 つの設定で表現 |
