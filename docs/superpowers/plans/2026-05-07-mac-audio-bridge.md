# Mac Audio Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS の任意の入力デバイスから任意の出力デバイスへ音声を pass-thru するメニューバー常駐アプリを実装する。

**Architecture:** AVAudioEngine + 動的に作成したプライベート AggregateDevice で異なる入出力デバイスを束ね、`mainMixerNode` 経由でフォーマット自動変換しながら pass-thru。CoreAudio HAL のリスナーでシステムデフォルト変更・接続/切断を監視し、メニューバー UI（SwiftUI MenuBarExtra）で操作する。Pure Swift ロジック層（Core/）は TDD、CoreAudio/AVFoundation 依存層（Audio/）は手動結合テスト。並行性は MainActor / engineQueue / CoreAudio スレッドの 3 系統で分担。

**Tech Stack:** Swift 5.10+, AVFoundation, CoreAudio HAL, SwiftUI `MenuBarExtra`, ServiceManagement (`SMAppService`), Swift Testing, OSLog (`Logger`), xcodegen, macOS 13.0+ / Xcode 16+

**Spec:** `docs/superpowers/specs/2026-05-07-mac-audio-bridge-design.md`

---

## File Structure

```
mac-audio-bridge/
├── project.yml                            # xcodegen の source of truth
├── MacAudioBridge.xcodeproj/              # generated（.gitignore 対象）
├── README.md
├── LICENSE                                # MIT
├── .gitignore
├── .claudeignore
├── docs/superpowers/{specs,plans}/...
│
├── MacAudioBridge/                        # アプリ本体ターゲット
│   ├── MacAudioBridgeApp.swift            # @main
│   ├── Info.generated.plist               # xcodegen 生成
│   ├── Assets.xcassets/                   # アイコン
│   │
│   ├── App/
│   │   ├── AppState.swift                 # ObservableObject
│   │   └── Preferences.swift              # ★テスト対象
│   │
│   ├── UI/
│   │   ├── MenuBarView.swift
│   │   ├── DeviceMenuSection.swift
│   │   └── StatusIcon.swift
│   │
│   ├── Core/                              # ★Pure Swift、テスト対象
│   │   ├── BridgeStatus.swift
│   │   ├── StopReason.swift
│   │   ├── DeviceChoice.swift
│   │   ├── ResolvedDevice.swift
│   │   ├── DeviceSelection.swift
│   │   ├── FeedbackLoopDetector.swift
│   │   └── BridgeStateMachine.swift
│   │
│   ├── Audio/                             # CoreAudio / AVFoundation 依存
│   │   ├── Device.swift
│   │   ├── DeviceProvider.swift           # protocol
│   │   ├── CoreAudioDeviceProvider.swift  # 本番実装
│   │   ├── DeviceMonitor.swift
│   │   ├── AggregateDeviceManager.swift
│   │   ├── AUAudioUnit+Device.swift
│   │   └── AudioBridgeEngine.swift
│   │
│   ├── System/
│   │   ├── LoginItemController.swift
│   │   └── PermissionHelper.swift
│   │
│   └── Logging/
│       └── Log.swift
│
└── MacAudioBridgeTests/
    ├── Mocks/
    │   └── MockDeviceProvider.swift
    ├── PreferencesTests.swift
    ├── DeviceSelectionTests.swift
    ├── FeedbackLoopDetectorTests.swift
    └── BridgeStateMachineTests.swift
```

**実行 cwd**: すべての CLI コマンドは `/Users/ryugo/Developer/src/personal/mac-audio-bridge` で実行する。

---

## Phase 1: プロジェクトセットアップ

### Task 1: xcodegen 導入とプロジェクト生成

**Files:**
- Create: `project.yml`
- Create: `MacAudioBridge/MacAudioBridgeApp.swift`（仮の最小版、Task 22 で本実装）
- Create: `MacAudioBridge/{App,UI,Core,Audio,System,Logging}/.keep`
- Create: `MacAudioBridgeTests/Mocks/.keep`
- Generated: `MacAudioBridge.xcodeproj/`, `MacAudioBridge/Info.generated.plist`

- [ ] **Step 1: xcodegen をインストール（未導入時のみ）**

```bash
brew install xcodegen
xcodegen --version
```

Expected: `Version: 2.x.x` が表示される。

- [ ] **Step 2: project.yml を作成**

```yaml
name: MacAudioBridge
options:
  bundleIdPrefix: com.ryugo
  deploymentTarget:
    macOS: "13.0"
  defaultConfig: Debug

settings:
  base:
    SWIFT_VERSION: "5.10"
    MACOSX_DEPLOYMENT_TARGET: "13.0"
    ENABLE_HARDENED_RUNTIME: YES
    ENABLE_USER_SCRIPT_SANDBOXING: NO
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: ""

targets:
  MacAudioBridge:
    type: application
    platform: macOS
    sources:
      - path: MacAudioBridge
    info:
      path: MacAudioBridge/Info.generated.plist
      properties:
        CFBundleIdentifier: com.ryugo.mac-audio-bridge
        CFBundleName: MacAudioBridge
        CFBundleDisplayName: Mac Audio Bridge
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        LSUIElement: true
        LSMinimumSystemVersion: "13.0"
        NSMicrophoneUsageDescription: "MacAudioBridge は選択された入力デバイスから音声を取得し、選択された出力デバイスへパススルーします。"

  MacAudioBridgeTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: MacAudioBridgeTests
    dependencies:
      - target: MacAudioBridge
```

- [ ] **Step 3: ソース scaffold ディレクトリを作成**

```bash
cd /Users/ryugo/Developer/src/personal/mac-audio-bridge
mkdir -p MacAudioBridge/{App,UI,Core,Audio,System,Logging,Assets.xcassets}
mkdir -p MacAudioBridgeTests/Mocks
for d in MacAudioBridge/{App,UI,Core,Audio,System,Logging} MacAudioBridgeTests/Mocks; do touch "$d/.keep"; done
```

- [ ] **Step 4: 仮の `MacAudioBridgeApp.swift`（最小ビルドが通ることの確認用）を作成**

`MacAudioBridge/MacAudioBridgeApp.swift`:

```swift
import SwiftUI

@main
struct MacAudioBridgeApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 5: xcodegen を実行**

```bash
cd /Users/ryugo/Developer/src/personal/mac-audio-bridge
xcodegen generate
```

Expected: `Project generated successfully`

- [ ] **Step 6: ビルドが通ることを確認**

```bash
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: commit**

```bash
git add project.yml MacAudioBridge MacAudioBridgeTests
git commit -m "build: scaffold Xcode project via xcodegen"
```

---

### Task 2: .gitignore / .claudeignore / LICENSE / README skeleton

**Files:**
- Create: `.gitignore`
- Create: `.claudeignore`
- Create: `LICENSE`
- Create: `README.md`

- [ ] **Step 1: `.gitignore` を作成**

```
# Xcode
build/
DerivedData/
*.xcodeproj/
!project.yml
xcuserdata/
*.xcworkspace/
*.xcuserstate

# macOS
.DS_Store

# Swift Package Manager
.build/
Packages/
Package.pins
Package.resolved
.swiftpm/

# generated
MacAudioBridge/Info.generated.plist
```

- [ ] **Step 2: `.claudeignore` を作成**

```
build/
DerivedData/
MacAudioBridge.xcodeproj/
MacAudioBridge/Info.generated.plist
.build/
*.xcuserstate
```

- [ ] **Step 3: `LICENSE` を作成（MIT）**

```
MIT License

Copyright (c) 2026 Toshihiko Ryugo

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 4: `README.md` を作成（skeleton）**

```markdown
# Mac Audio Bridge

macOS の任意の入力デバイスを任意の出力デバイスへ pass-thru するメニューバー常駐ツール。

## 必要環境

- macOS 13.0 以上
- Xcode 16 以上
- xcodegen (`brew install xcodegen`)

## ビルド

\`\`\`bash
xcodegen generate
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Release build
\`\`\`

## 使い方

メニューバーアイコンから:

- ON/OFF トグル
- 入力デバイス / 出力デバイス選択
- ログイン時自動起動の有無

## 設計ドキュメント

`docs/superpowers/specs/2026-05-07-mac-audio-bridge-design.md` 参照。

## ライセンス

MIT (LICENSE 参照)
```

> README に書く `\`\`\`` は実際には ``` （バックティック 3 つ）。

- [ ] **Step 5: 既に commit 済みの `MacAudioBridge.xcodeproj/` を git 管理から外す**

```bash
git rm -rf --cached MacAudioBridge.xcodeproj 2>/dev/null || true
git rm --cached MacAudioBridge/Info.generated.plist 2>/dev/null || true
```

- [ ] **Step 6: commit**

```bash
git add .gitignore .claudeignore LICENSE README.md
git commit -m "chore: add gitignore, license, readme skeleton"
```

---

## Phase 2: Core types（Pure Swift、型のみ）

### Task 3: Core types を一括実装

`BridgeStatus`, `StopReason`, `DeviceChoice`, `ResolvedDevice`。enum / struct のみで振る舞いを持たないため、型存在 + Equatable を確認するテストのみ。

**Files:**
- Create: `MacAudioBridge/Core/BridgeStatus.swift`
- Create: `MacAudioBridge/Core/StopReason.swift`
- Create: `MacAudioBridge/Core/DeviceChoice.swift`
- Create: `MacAudioBridge/Core/ResolvedDevice.swift`
- Delete: `MacAudioBridge/Core/.keep`

- [ ] **Step 1: `BridgeStatus.swift` を作成**

```swift
import Foundation

enum BridgeStatus: Equatable {
    case idle
    case starting
    case running
    case stopped(StopReason)
}
```

- [ ] **Step 2: `StopReason.swift` を作成**

```swift
import Foundation

enum StopReason: Equatable {
    case userToggledOff
    case deviceDisconnected(uid: String)
    case feedbackLoop
    case micPermissionDenied
    case engineFailed(message: String)
}
```

- [ ] **Step 3: `DeviceChoice.swift` を作成**

```swift
import Foundation

enum DeviceChoice: Equatable, Codable {
    case systemDefault
    case specific(uid: String)

    /// UserDefaults 保存用文字列。"system_default" or UID。
    var storageString: String {
        switch self {
        case .systemDefault: return "system_default"
        case .specific(let uid): return uid
        }
    }

    /// UserDefaults 保存文字列から復元。
    init(storageString: String) {
        if storageString == "system_default" {
            self = .systemDefault
        } else {
            self = .specific(uid: storageString)
        }
    }
}
```

- [ ] **Step 4: `ResolvedDevice.swift` を作成**

```swift
import Foundation

struct ResolvedDevice: Equatable {
    let uid: String
    let name: String
    let isConnected: Bool
}
```

- [ ] **Step 5: .keep を削除し再生成・ビルド**

```bash
rm MacAudioBridge/Core/.keep
xcodegen generate
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: commit**

```bash
git add MacAudioBridge/Core
git commit -m "feat(core): add BridgeStatus, StopReason, DeviceChoice, ResolvedDevice"
```

---

## Phase 3: Pure ロジック層（TDD）

### Task 4: DeviceSelection（TDD）

`(DeviceChoice, systemDefault, connectedDevices) → ResolvedDevice?` の純関数。

**Files:**
- Create: `MacAudioBridge/Core/DeviceSelection.swift`
- Create: `MacAudioBridgeTests/DeviceSelectionTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`MacAudioBridgeTests/DeviceSelectionTests.swift`:

```swift
import Testing
@testable import MacAudioBridge

struct DeviceSelectionTests {
    let mic = ResolvedDevice(uid: "mic-1", name: "USB Mic", isConnected: true)
    let speaker = ResolvedDevice(uid: "spk-1", name: "AirPods", isConnected: true)
    let unplugged = ResolvedDevice(uid: "ghost", name: "Ghost", isConnected: false)

    @Test func systemDefaultReturnsSystemDefault() {
        let result = DeviceSelection.resolve(
            choice: .systemDefault,
            systemDefault: mic,
            connectedDevices: [mic, speaker]
        )
        #expect(result == mic)
    }

    @Test func systemDefaultReturnsNilWhenNoDefault() {
        let result = DeviceSelection.resolve(
            choice: .systemDefault,
            systemDefault: nil,
            connectedDevices: [mic]
        )
        #expect(result == nil)
    }

    @Test func specificReturnsConnectedDevice() {
        let result = DeviceSelection.resolve(
            choice: .specific(uid: "mic-1"),
            systemDefault: speaker,
            connectedDevices: [mic, speaker]
        )
        #expect(result == mic)
    }

    @Test func specificReturnsNilWhenNotConnected() {
        let result = DeviceSelection.resolve(
            choice: .specific(uid: "ghost"),
            systemDefault: mic,
            connectedDevices: [mic, speaker]
        )
        #expect(result == nil)
    }

    @Test func specificReturnsDeviceEvenIfMarkedDisconnected() {
        // connectedDevices に含まれていれば isConnected=false でも返す
        // （isConnected フラグは UI 表示用、解決の判定は配列存在で行う）
        let result = DeviceSelection.resolve(
            choice: .specific(uid: "ghost"),
            systemDefault: nil,
            connectedDevices: [unplugged]
        )
        #expect(result == unplugged)
    }
}
```

- [ ] **Step 2: テストが「コンパイル不可」で落ちることを確認**

```bash
xcodegen generate
xcodebuild test -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `Cannot find 'DeviceSelection' in scope` 等のコンパイルエラーで失敗。

- [ ] **Step 3: `DeviceSelection.swift` を実装**

```swift
import Foundation

enum DeviceSelection {
    /// DeviceChoice と現在のシステムデフォルト・接続中デバイス一覧から ResolvedDevice を解決する。
    /// - .systemDefault: systemDefault をそのまま返す（nil なら nil）
    /// - .specific(uid): connectedDevices から uid 一致を探して返す（無ければ nil）
    static func resolve(
        choice: DeviceChoice,
        systemDefault: ResolvedDevice?,
        connectedDevices: [ResolvedDevice]
    ) -> ResolvedDevice? {
        switch choice {
        case .systemDefault:
            return systemDefault
        case .specific(let uid):
            return connectedDevices.first(where: { $0.uid == uid })
        }
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

```bash
xcodegen generate
xcodebuild test -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`、`5 passing` 相当。

- [ ] **Step 5: commit**

```bash
git add MacAudioBridge/Core/DeviceSelection.swift MacAudioBridgeTests/DeviceSelectionTests.swift
git commit -m "feat(core): add DeviceSelection.resolve()"
```

---

### Task 5: FeedbackLoopDetector（TDD）

入力 UID == 出力 UID 判定の純関数。

**Files:**
- Create: `MacAudioBridge/Core/FeedbackLoopDetector.swift`
- Create: `MacAudioBridgeTests/FeedbackLoopDetectorTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`MacAudioBridgeTests/FeedbackLoopDetectorTests.swift`:

```swift
import Testing
@testable import MacAudioBridge

struct FeedbackLoopDetectorTests {
    @Test func sameUIDIsLoop() {
        #expect(FeedbackLoopDetector.isLoop(inputUID: "dev-1", outputUID: "dev-1") == true)
    }

    @Test func differentUIDIsNotLoop() {
        #expect(FeedbackLoopDetector.isLoop(inputUID: "in-1", outputUID: "out-1") == false)
    }

    @Test func nilInputIsNotLoop() {
        #expect(FeedbackLoopDetector.isLoop(inputUID: nil, outputUID: "out-1") == false)
    }

    @Test func nilOutputIsNotLoop() {
        #expect(FeedbackLoopDetector.isLoop(inputUID: "in-1", outputUID: nil) == false)
    }

    @Test func bothNilIsNotLoop() {
        #expect(FeedbackLoopDetector.isLoop(inputUID: nil, outputUID: nil) == false)
    }
}
```

- [ ] **Step 2: テストが「コンパイル不可」で落ちることを確認**

```bash
xcodebuild test -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `Cannot find 'FeedbackLoopDetector' in scope`

- [ ] **Step 3: `FeedbackLoopDetector.swift` を実装**

```swift
import Foundation

enum FeedbackLoopDetector {
    /// 入力 UID と出力 UID が同じならフィードバックループ。
    /// 片方が nil なら判定不可（false 扱い）。
    static func isLoop(inputUID: String?, outputUID: String?) -> Bool {
        guard let inputUID, let outputUID else { return false }
        return inputUID == outputUID
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

```bash
xcodegen generate
xcodebuild test -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: commit**

```bash
git add MacAudioBridge/Core/FeedbackLoopDetector.swift MacAudioBridgeTests/FeedbackLoopDetectorTests.swift
git commit -m "feat(core): add FeedbackLoopDetector"
```

---

### Task 6: BridgeStateMachine（TDD）

状態遷移ロジック。トリガー入力 → 出力 BridgeStatus を純関数で表現。

**Files:**
- Create: `MacAudioBridge/Core/BridgeStateMachine.swift`
- Create: `MacAudioBridgeTests/BridgeStateMachineTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`MacAudioBridgeTests/BridgeStateMachineTests.swift`:

```swift
import Testing
@testable import MacAudioBridge

struct BridgeStateMachineTests {
    @Test func userToggleOnFromIdle() {
        let next = BridgeStateMachine.transition(from: .idle, on: .userToggledOn)
        #expect(next == .starting)
    }

    @Test func userToggleOnFromStoppedRestart() {
        let next = BridgeStateMachine.transition(from: .stopped(.userToggledOff), on: .userToggledOn)
        #expect(next == .starting)
    }

    @Test func userToggleOffFromRunningStops() {
        let next = BridgeStateMachine.transition(from: .running, on: .userToggledOff)
        #expect(next == .stopped(.userToggledOff))
    }

    @Test func userToggleOffFromStartingStops() {
        let next = BridgeStateMachine.transition(from: .starting, on: .userToggledOff)
        #expect(next == .stopped(.userToggledOff))
    }

    @Test func startSucceededFromStartingRunning() {
        let next = BridgeStateMachine.transition(from: .starting, on: .startSucceeded)
        #expect(next == .running)
    }

    @Test func startFailedFromStartingStops() {
        let next = BridgeStateMachine.transition(
            from: .starting,
            on: .startFailed(reason: .feedbackLoop)
        )
        #expect(next == .stopped(.feedbackLoop))
    }

    @Test func deviceDisconnectedFromRunningStops() {
        let next = BridgeStateMachine.transition(
            from: .running,
            on: .deviceDisconnected(uid: "spk-1")
        )
        #expect(next == .stopped(.deviceDisconnected(uid: "spk-1")))
    }

    @Test func deviceReconnectedFromStoppedDisconnectedRestarts() {
        let next = BridgeStateMachine.transition(
            from: .stopped(.deviceDisconnected(uid: "spk-1")),
            on: .deviceReconnected(uid: "spk-1")
        )
        #expect(next == .starting)
    }

    @Test func deviceReconnectedFromStoppedDisconnectedDifferentUIDIgnored() {
        let next = BridgeStateMachine.transition(
            from: .stopped(.deviceDisconnected(uid: "spk-1")),
            on: .deviceReconnected(uid: "other-uid")
        )
        // 別 UID の再接続は無視（状態維持）
        #expect(next == .stopped(.deviceDisconnected(uid: "spk-1")))
    }

    @Test func feedbackLoopFromRunningStops() {
        let next = BridgeStateMachine.transition(from: .running, on: .feedbackLoopDetected)
        #expect(next == .stopped(.feedbackLoop))
    }

    @Test func userToggleOffFromIdleIgnored() {
        let next = BridgeStateMachine.transition(from: .idle, on: .userToggledOff)
        // idle で OFF を押しても何も起きない
        #expect(next == .idle)
    }
}
```

- [ ] **Step 2: テストが「コンパイル不可」で落ちることを確認**

```bash
xcodebuild test -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `Cannot find 'BridgeStateMachine' in scope`

- [ ] **Step 3: `BridgeStateMachine.swift` を実装**

```swift
import Foundation

enum BridgeEvent: Equatable {
    case userToggledOn
    case userToggledOff
    case startSucceeded
    case startFailed(reason: StopReason)
    case deviceDisconnected(uid: String)
    case deviceReconnected(uid: String)
    case feedbackLoopDetected
}

enum BridgeStateMachine {
    /// 現在状態とイベントから次状態を返す純関数。
    /// 副作用を持たない。AppState 側で副作用（実エンジン操作）を起こす。
    static func transition(from current: BridgeStatus, on event: BridgeEvent) -> BridgeStatus {
        switch (current, event) {
        // ON トグル: idle / stopped から starting へ
        case (.idle, .userToggledOn),
             (.stopped, .userToggledOn):
            return .starting

        // OFF トグル: starting / running から stopped(.userToggledOff)
        case (.starting, .userToggledOff),
             (.running, .userToggledOff):
            return .stopped(.userToggledOff)

        // 起動成功
        case (.starting, .startSucceeded):
            return .running

        // 起動失敗
        case (.starting, .startFailed(let reason)):
            return .stopped(reason)

        // 動作中の切断
        case (.running, .deviceDisconnected(let uid)):
            return .stopped(.deviceDisconnected(uid: uid))

        // 切断状態からの再接続（同じ UID のときだけ再起動）
        case (.stopped(.deviceDisconnected(let stoppedUID)), .deviceReconnected(let uid)):
            return stoppedUID == uid ? .starting : current

        // フィードバックループ検知（動作中・起動中とも停止）
        case (.running, .feedbackLoopDetected),
             (.starting, .feedbackLoopDetected):
            return .stopped(.feedbackLoop)

        // それ以外は状態維持
        default:
            return current
        }
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

```bash
xcodebuild test -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: commit**

```bash
git add MacAudioBridge/Core/BridgeStateMachine.swift MacAudioBridgeTests/BridgeStateMachineTests.swift
git commit -m "feat(core): add BridgeStateMachine pure transition function"
```

---

## Phase 4: Preferences（TDD）

### Task 7: Preferences（TDD）

UserDefaults ラッパー。テストでは `UserDefaults(suiteName:)` を使って分離する。

**Files:**
- Create: `MacAudioBridge/App/Preferences.swift`
- Create: `MacAudioBridgeTests/PreferencesTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`MacAudioBridgeTests/PreferencesTests.swift`:

```swift
import Testing
import Foundation
@testable import MacAudioBridge

struct PreferencesTests {
    /// テスト用の独立 UserDefaults を返す。
    private func makeStore() -> (UserDefaults, String) {
        let suite = "com.ryugo.mac-audio-bridge.tests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        ud.removePersistentDomain(forName: suite)
        return (ud, suite)
    }

    @Test func defaultsAreSystemDefaultAndAutoRunFalse() {
        let (ud, _) = makeStore()
        let prefs = Preferences(store: ud)
        #expect(prefs.inputChoice == .systemDefault)
        #expect(prefs.outputChoice == .systemDefault)
        #expect(prefs.autoRun == false)
    }

    @Test func savesAndLoadsSpecificDevice() {
        let (ud, _) = makeStore()
        let prefs = Preferences(store: ud)
        prefs.inputChoice = .specific(uid: "mic-1")
        prefs.outputChoice = .specific(uid: "spk-1")
        prefs.autoRun = true

        // 別インスタンスで読み込み確認
        let prefs2 = Preferences(store: ud)
        #expect(prefs2.inputChoice == .specific(uid: "mic-1"))
        #expect(prefs2.outputChoice == .specific(uid: "spk-1"))
        #expect(prefs2.autoRun == true)
    }

    @Test func ignoresUnknownKeys() {
        let (ud, _) = makeStore()
        ud.set("unexpected", forKey: "some.unrelated.key")
        let prefs = Preferences(store: ud)
        #expect(prefs.inputChoice == .systemDefault)
    }

    @Test func systemDefaultStorageString() {
        let (ud, _) = makeStore()
        let prefs = Preferences(store: ud)
        prefs.inputChoice = .systemDefault
        #expect(ud.string(forKey: "device.input") == "system_default")
    }

    @Test func specificUIDStorageString() {
        let (ud, _) = makeStore()
        let prefs = Preferences(store: ud)
        prefs.inputChoice = .specific(uid: "mic-1")
        #expect(ud.string(forKey: "device.input") == "mic-1")
    }
}
```

- [ ] **Step 2: テストが「コンパイル不可」で落ちることを確認**

```bash
xcodegen generate
xcodebuild test -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `Cannot find 'Preferences' in scope`

- [ ] **Step 3: `Preferences.swift` を実装**

```swift
import Foundation

final class Preferences {
    private let store: UserDefaults

    private enum Keys {
        static let inputDevice = "device.input"
        static let outputDevice = "device.output"
        static let autoRun = "app.autoRun"
    }

    init(store: UserDefaults = .standard) {
        self.store = store
    }

    var inputChoice: DeviceChoice {
        get {
            DeviceChoice(storageString: store.string(forKey: Keys.inputDevice) ?? "system_default")
        }
        set {
            store.set(newValue.storageString, forKey: Keys.inputDevice)
        }
    }

    var outputChoice: DeviceChoice {
        get {
            DeviceChoice(storageString: store.string(forKey: Keys.outputDevice) ?? "system_default")
        }
        set {
            store.set(newValue.storageString, forKey: Keys.outputDevice)
        }
    }

    var autoRun: Bool {
        get { store.bool(forKey: Keys.autoRun) }
        set { store.set(newValue, forKey: Keys.autoRun) }
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

```bash
xcodegen generate
xcodebuild test -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: commit**

```bash
git add MacAudioBridge/App/Preferences.swift MacAudioBridgeTests/PreferencesTests.swift
git commit -m "feat(app): add Preferences with UserDefaults persistence"
```

---

## Phase 5: Logging

### Task 8: Log（OSLog ラッパー）

**Files:**
- Create: `MacAudioBridge/Logging/Log.swift`

- [ ] **Step 1: `Log.swift` を実装**

```swift
import Foundation
import OSLog

enum Log {
    private static let subsystem = "com.ryugo.mac-audio-bridge"

    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let deviceMonitor = Logger(subsystem: subsystem, category: "device-monitor")
    static let aggregate = Logger(subsystem: subsystem, category: "aggregate")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let app = Logger(subsystem: subsystem, category: "app")
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodegen generate
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: commit**

```bash
git add MacAudioBridge/Logging
git commit -m "feat(logging): add Log namespace wrapping OSLog"
```

---

## Phase 6: System 層

### Task 9: PermissionHelper（マイク権限）

**Files:**
- Create: `MacAudioBridge/System/PermissionHelper.swift`

- [ ] **Step 1: `PermissionHelper.swift` を実装**

```swift
import AVFoundation
import AppKit

enum MicrophoneAuthorization {
    case authorized
    case denied
    case notDetermined
}

enum PermissionHelper {
    static var microphoneStatus: MicrophoneAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    /// マイク権限をユーザーに要求し、結果を completion で返す。
    /// 既に決定済みの場合は即座に現状を返す。
    static func requestMicrophoneAccess(completion: @escaping (MicrophoneAuthorization) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(.authorized)
        case .denied, .restricted:
            completion(.denied)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted ? .authorized : .denied)
                }
            }
        @unknown default:
            completion(.denied)
        }
    }

    /// 「システム設定 > プライバシー > マイク」を開く。
    static func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodegen generate
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: commit**

```bash
git add MacAudioBridge/System/PermissionHelper.swift
git commit -m "feat(system): add PermissionHelper for microphone authorization"
```

---

### Task 10: LoginItemController（SMAppService）

**Files:**
- Create: `MacAudioBridge/System/LoginItemController.swift`

- [ ] **Step 1: `LoginItemController.swift` を実装**

```swift
import Foundation
import ServiceManagement

enum LoginItemError: Error, LocalizedError {
    case registrationFailed(underlying: Error)
    case unregistrationFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let e): return "ログイン項目の登録に失敗: \(e.localizedDescription)"
        case .unregistrationFailed(let e): return "ログイン項目の解除に失敗: \(e.localizedDescription)"
        }
    }
}

enum LoginItemController {
    /// 現在ログイン項目に登録されているか。
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 登録（ログイン時自動起動を有効化）。
    static func register() throws {
        do {
            try SMAppService.mainApp.register()
            Log.app.info("LoginItem registered")
        } catch {
            Log.app.error("LoginItem register failed: \(error.localizedDescription)")
            throw LoginItemError.registrationFailed(underlying: error)
        }
    }

    /// 解除（ログイン時自動起動を無効化）。
    static func unregister() throws {
        do {
            try SMAppService.mainApp.unregister()
            Log.app.info("LoginItem unregistered")
        } catch {
            Log.app.error("LoginItem unregister failed: \(error.localizedDescription)")
            throw LoginItemError.unregistrationFailed(underlying: error)
        }
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: commit**

```bash
git add MacAudioBridge/System/LoginItemController.swift
git commit -m "feat(system): add LoginItemController wrapping SMAppService"
```

---

## Phase 7: Audio 層（CoreAudio 依存、手動結合確認）

### Task 11: Device + DeviceProvider protocol + MockDeviceProvider

**Files:**
- Create: `MacAudioBridge/Audio/Device.swift`
- Create: `MacAudioBridge/Audio/DeviceProvider.swift`
- Create: `MacAudioBridgeTests/Mocks/MockDeviceProvider.swift`

- [ ] **Step 1: `Device.swift` を作成**

```swift
import Foundation

/// 音声デバイス（入力 / 出力どちらも表現）。
struct Device: Equatable, Identifiable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
}
```

> `AudioDeviceID` は CoreAudio の `UInt32` typealias。`import CoreAudio` で使えるはず。

- [ ] **Step 2: `Device.swift` の修正（CoreAudio 依存を解決）**

```swift
import Foundation
import CoreAudio

struct Device: Equatable, Identifiable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
}
```

- [ ] **Step 3: `DeviceProvider.swift` を作成**

```swift
import Foundation

protocol DeviceProvider: AnyObject {
    var connectedInputDevices: [Device] { get }
    var connectedOutputDevices: [Device] { get }
    var defaultInputDevice: Device? { get }
    var defaultOutputDevice: Device? { get }

    /// Device を `ResolvedDevice` に変換するヘルパー。
    func resolvedDevice(for device: Device) -> ResolvedDevice
}

extension DeviceProvider {
    func resolvedDevice(for device: Device) -> ResolvedDevice {
        ResolvedDevice(uid: device.uid, name: device.name, isConnected: true)
    }
}
```

- [ ] **Step 4: `MockDeviceProvider.swift` を作成（テスト用）**

```swift
import Foundation
@testable import MacAudioBridge

final class MockDeviceProvider: DeviceProvider {
    var connectedInputDevices: [Device]
    var connectedOutputDevices: [Device]
    var defaultInputDevice: Device?
    var defaultOutputDevice: Device?

    init(
        connectedInput: [Device] = [],
        connectedOutput: [Device] = [],
        defaultInput: Device? = nil,
        defaultOutput: Device? = nil
    ) {
        self.connectedInputDevices = connectedInput
        self.connectedOutputDevices = connectedOutput
        self.defaultInputDevice = defaultInput
        self.defaultOutputDevice = defaultOutput
    }
}
```

- [ ] **Step 5: ビルドが通ることを確認**

```bash
xcodegen generate
xcodebuild test -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`（既存テストが壊れていないこと）

- [ ] **Step 6: commit**

```bash
git add MacAudioBridge/Audio/Device.swift MacAudioBridge/Audio/DeviceProvider.swift MacAudioBridgeTests/Mocks/MockDeviceProvider.swift
git commit -m "feat(audio): add Device, DeviceProvider protocol, MockDeviceProvider"
```

---

### Task 12: CoreAudioDeviceProvider（CoreAudio HAL からデバイス列挙）

**Files:**
- Create: `MacAudioBridge/Audio/CoreAudioDeviceProvider.swift`

- [ ] **Step 1: `CoreAudioDeviceProvider.swift` を実装**

```swift
import Foundation
import CoreAudio

final class CoreAudioDeviceProvider: DeviceProvider {
    var connectedInputDevices: [Device] {
        allDevices().filter { $0.hasInput }
    }

    var connectedOutputDevices: [Device] {
        allDevices().filter { $0.hasOutput }
    }

    var defaultInputDevice: Device? {
        guard let id = defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice) else { return nil }
        return makeDevice(id: id)
    }

    var defaultOutputDevice: Device? {
        guard let id = defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice) else { return nil }
        return makeDevice(id: id)
    }

    // MARK: - Private

    private func allDevices() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        )
        guard status == noErr else {
            Log.deviceMonitor.error("kAudioHardwarePropertyDevices size failed: \(status)")
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids
        )
        guard status == noErr else {
            Log.deviceMonitor.error("kAudioHardwarePropertyDevices data failed: \(status)")
            return []
        }
        return ids.compactMap(makeDevice(id:))
    }

    private func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private func makeDevice(id: AudioDeviceID) -> Device? {
        guard let uid = stringProperty(deviceID: id, selector: kAudioDevicePropertyDeviceUID),
              let name = stringProperty(deviceID: id, selector: kAudioDevicePropertyDeviceNameCFString) else {
            return nil
        }
        let hasInput = streamCount(deviceID: id, scope: kAudioDevicePropertyScopeInput) > 0
        let hasOutput = streamCount(deviceID: id, scope: kAudioDevicePropertyScopeOutput) > 0
        return Device(id: id, uid: uid, name: name, hasInput: hasInput, hasOutput: hasOutput)
    }

    private func stringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        var cfString: CFString?
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &cfString)
        guard status == noErr, let cf = cfString else { return nil }
        return cf as String
    }

    private func streamCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr else { return 0 }
        return Int(dataSize) / MemoryLayout<AudioStreamID>.size
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodegen generate
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 手動確認: 接続中デバイス一覧が取れることを REPL で確認**

`MacAudioBridgeApp.swift` を一時的に書き換え、起動時に listOnly でログ出力するモードを追加してもよい。最低限のチェックは `system_profiler SPAudioDataType | grep "Default"` と整合するかを確認。

- [ ] **Step 4: commit**

```bash
git add MacAudioBridge/Audio/CoreAudioDeviceProvider.swift
git commit -m "feat(audio): add CoreAudioDeviceProvider listing devices via HAL"
```

---

### Task 13: AUAudioUnit+Device extension（setDeviceID ヘルパー）

**Files:**
- Create: `MacAudioBridge/Audio/AUAudioUnit+Device.swift`

- [ ] **Step 1: `AUAudioUnit+Device.swift` を実装**

```swift
import Foundation
import AVFoundation
import CoreAudio

extension AUAudioUnit {
    enum DeviceError: Error, LocalizedError {
        case osStatus(OSStatus)
        var errorDescription: String? {
            switch self {
            case .osStatus(let s): return "AUAudioUnit kAudioOutputUnitProperty_CurrentDevice 設定失敗 (\(s))"
            }
        }
    }

    /// AUAudioUnit に CoreAudio の AudioDeviceID をバインドする。
    /// AVAudioEngine の inputNode / outputNode の auAudioUnit に対して使う。
    func setDeviceID(_ deviceID: AudioDeviceID) throws {
        var mutable = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutable,
            size
        )
        guard status == noErr else {
            throw DeviceError.osStatus(status)
        }
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: commit**

```bash
git add MacAudioBridge/Audio/AUAudioUnit+Device.swift
git commit -m "feat(audio): add AUAudioUnit+Device extension for binding AudioDeviceID"
```

---

### Task 14: AggregateDeviceManager（作成・破棄・残骸掃除）

**Files:**
- Create: `MacAudioBridge/Audio/AggregateDeviceManager.swift`

- [ ] **Step 1: `AggregateDeviceManager.swift` を実装**

```swift
import Foundation
import CoreAudio

enum AggregateDeviceError: Error, LocalizedError {
    case createFailed(OSStatus)
    case destroyFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .createFailed(let s): return "AggregateDevice 作成失敗 (\(s))"
        case .destroyFailed(let s): return "AggregateDevice 破棄失敗 (\(s))"
        }
    }
}

final class AggregateDeviceManager {
    static let uidPrefix = "com.ryugo.mac-audio-bridge.aggregate."

    /// 入力 UID と出力 UID から動的に Private AggregateDevice を作成し AudioDeviceID を返す。
    /// MainSubDevice は出力（マスタークロック）。入力にはドリフト補正キーを設定。
    func create(inputUID: String, outputUID: String) throws -> AudioDeviceID {
        let aggregateUID = Self.uidPrefix + UUID().uuidString
        let inputDict: [String: Any] = [
            kAudioSubDeviceUIDKey as String: inputUID,
            kAudioSubDeviceDriftCompensationKey as String: 1
        ]
        let outputDict: [String: Any] = [
            kAudioSubDeviceUIDKey as String: outputUID
        ]
        let dict: [String: Any] = [
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceNameKey as String: "MacAudioBridge",
            kAudioAggregateDeviceIsPrivateKey as String: 1,
            kAudioAggregateDeviceMainSubDeviceKey as String: outputUID,
            kAudioAggregateDeviceSubDeviceListKey as String: [inputDict, outputDict]
        ]

        var deviceID = AudioDeviceID(0)
        let status = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &deviceID)
        guard status == noErr else {
            Log.aggregate.error("create failed: \(status)")
            throw AggregateDeviceError.createFailed(status)
        }
        Log.aggregate.info("created \(aggregateUID) id=\(deviceID)")
        return deviceID
    }

    /// AggregateDevice を破棄する。
    func destroy(_ deviceID: AudioDeviceID) throws {
        let status = AudioHardwareDestroyAggregateDevice(deviceID)
        guard status == noErr else {
            Log.aggregate.error("destroy failed id=\(deviceID) status=\(status)")
            throw AggregateDeviceError.destroyFailed(status)
        }
        Log.aggregate.info("destroyed id=\(deviceID)")
    }

    /// 起動時に呼ぶ。前回の残骸 AggregateDevice をプレフィックス一致で全削除。
    /// 多重起動は §5.1 で防いでいるため、自プロセスのアクティブ Aggregate を消す心配はない。
    func cleanupOrphans() {
        let provider = CoreAudioDeviceProvider()
        for device in provider.connectedInputDevices + provider.connectedOutputDevices {
            if device.uid.hasPrefix(Self.uidPrefix) {
                let status = AudioHardwareDestroyAggregateDevice(device.id)
                if status == noErr {
                    Log.aggregate.info("cleaned orphan \(device.uid)")
                } else {
                    Log.aggregate.error("orphan cleanup failed \(device.uid) status=\(status)")
                }
            }
        }
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: commit**

```bash
git add MacAudioBridge/Audio/AggregateDeviceManager.swift
git commit -m "feat(audio): add AggregateDeviceManager (create/destroy/cleanup)"
```

---

### Task 15: DeviceMonitor（CoreAudio リスナー登録）

**Files:**
- Create: `MacAudioBridge/Audio/DeviceMonitor.swift`

- [ ] **Step 1: `DeviceMonitor.swift` を実装**

```swift
import Foundation
import CoreAudio

/// CoreAudio HAL の各種プロパティ変更を監視する。
/// コールバックは任意スレッドで呼ばれるため、常に呼び出し側のキュー（engineQueue や MainActor）にディスパッチする。
final class DeviceMonitor {
    enum Event {
        case defaultInputChanged
        case defaultOutputChanged
        case deviceListChanged
    }

    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private let queue: DispatchQueue
    private let onEvent: (Event) -> Void

    /// - Parameters:
    ///   - dispatchQueue: コールバックをディスパッチするキュー（engineQueue 推奨）
    ///   - onEvent: イベント受信時のコールバック（dispatchQueue 上で呼ばれる）
    init(dispatchQueue: DispatchQueue, onEvent: @escaping (Event) -> Void) {
        self.queue = dispatchQueue
        self.onEvent = onEvent
    }

    func start() {
        addListener(
            selector: kAudioHardwarePropertyDefaultInputDevice,
            event: .defaultInputChanged
        )
        addListener(
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            event: .defaultOutputChanged
        )
        addListener(
            selector: kAudioHardwarePropertyDevices,
            event: .deviceListChanged
        )
        Log.deviceMonitor.info("DeviceMonitor started")
    }

    func stop() {
        for (var address, block) in listeners {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                queue,
                block
            )
        }
        listeners.removeAll()
        Log.deviceMonitor.info("DeviceMonitor stopped")
    }

    deinit {
        stop()
    }

    // MARK: - Private

    private func addListener(selector: AudioObjectPropertySelector, event: Event) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onEvent(event)
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            block
        )
        if status == noErr {
            listeners.append((address, block))
        } else {
            Log.deviceMonitor.error("listener register failed selector=\(selector) status=\(status)")
        }
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: commit**

```bash
git add MacAudioBridge/Audio/DeviceMonitor.swift
git commit -m "feat(audio): add DeviceMonitor for HAL property change listeners"
```

---

### Task 16: AudioBridgeEngine（中核）

**Files:**
- Create: `MacAudioBridge/Audio/AudioBridgeEngine.swift`

- [ ] **Step 1: `AudioBridgeEngine.swift` を実装**

```swift
import Foundation
import AVFoundation
import CoreAudio

/// 単一の入出力ペアの pass-thru を担うエンジン。
/// engineQueue 上で start / stop / restart を直列実行する前提（並行性モデル §7.6 参照）。
/// 将来マルチブリッジ拡張時はこのクラスを複数インスタンス化する。
final class AudioBridgeEngine {
    private let aggregateManager = AggregateDeviceManager()
    private var engine: AVAudioEngine?
    private var aggregateDeviceID: AudioDeviceID?
    private var configChangeObserver: NSObjectProtocol?

    /// 起動。事前に inputUID と outputUID は呼び出し側で解決済みであること。
    /// 同一 UID（feedback loop）の場合は呼び出し側で弾くこと。
    /// AVAudioEngine は毎回新規インスタンスを作る（再利用しない、§8.5）。
    func start(inputUID: String, outputUID: String) throws {
        try stopInternal(destroyAggregate: true)

        let aggID = try aggregateManager.create(inputUID: inputUID, outputUID: outputUID)
        self.aggregateDeviceID = aggID

        let engine = AVAudioEngine()
        try engine.inputNode.auAudioUnit.setDeviceID(aggID)
        try engine.outputNode.auAudioUnit.setDeviceID(aggID)

        // pass-thru 不変条件 (§8.7):
        // I1: ゲイン 1.0
        // I2: input → mainMixer の 1 本のみ、エフェクト無し
        // I4: format=nil で AVAudioEngine の自動マッチに任せる
        engine.mainMixerNode.outputVolume = 1.0
        engine.connect(engine.inputNode, to: engine.mainMixerNode, format: nil)

        // engine.outputNode は AVAudioEngine が暗黙に mainMixerNode と接続するため明示しない (I3)

        try engine.start()
        self.engine = engine

        // configurationChangeNotification を購読（フル再構築のトリガー、§6.2 #12）
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { _ in
            Log.engine.info("AVAudioEngineConfigurationChange received")
            // ここでは通知を投げるだけ。再構築は AppState 側が engineQueue 上で行う。
            NotificationCenter.default.post(name: .audioBridgeShouldRebuild, object: nil)
        }

        Log.engine.info("engine started input=\(inputUID) output=\(outputUID)")
    }

    /// 停止。AggregateDevice も破棄する。
    func stop() {
        try? stopInternal(destroyAggregate: true)
    }

    private func stopInternal(destroyAggregate: Bool) throws {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
        engine?.stop()
        engine = nil

        if destroyAggregate, let aggID = aggregateDeviceID {
            try? aggregateManager.destroy(aggID)
            aggregateDeviceID = nil
        }
    }

    /// 起動時に呼ぶ：前回の残骸 AggregateDevice を掃除する。
    func cleanupOrphans() {
        aggregateManager.cleanupOrphans()
    }
}

extension Notification.Name {
    static let audioBridgeShouldRebuild = Notification.Name("com.ryugo.mac-audio-bridge.shouldRebuild")
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: commit**

```bash
git add MacAudioBridge/Audio/AudioBridgeEngine.swift
git commit -m "feat(audio): add AudioBridgeEngine (AVAudioEngine + AggregateDevice)"
```

---

## Phase 8: App 層（AppState）

### Task 17: AppState（並行性モデルに従う中核）

**Files:**
- Create: `MacAudioBridge/App/AppState.swift`

- [ ] **Step 1: `AppState.swift` を実装**

```swift
import Foundation
import AVFoundation
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published（UI 用）

    @Published private(set) var status: BridgeStatus = .idle
    @Published private(set) var inputChoice: DeviceChoice = .systemDefault
    @Published private(set) var outputChoice: DeviceChoice = .systemDefault
    @Published private(set) var connectedInputDevices: [Device] = []
    @Published private(set) var connectedOutputDevices: [Device] = []
    @Published private(set) var defaultInputDevice: Device?
    @Published private(set) var defaultOutputDevice: Device?
    @Published var autoRun: Bool = false {
        didSet { applyAutoRunChange() }
    }

    // MARK: - Dependencies

    private let preferences: Preferences
    private let provider: DeviceProvider
    private let engine: AudioBridgeEngine
    private let engineQueue = DispatchQueue(
        label: "com.ryugo.mac-audio-bridge.engine",
        qos: .userInitiated
    )
    private var monitor: DeviceMonitor?
    private var rebuildObserver: NSObjectProtocol?
    private var debounceWorkItem: DispatchWorkItem?

    // MARK: - Init

    init(
        preferences: Preferences = Preferences(),
        provider: DeviceProvider = CoreAudioDeviceProvider(),
        engine: AudioBridgeEngine = AudioBridgeEngine()
    ) {
        self.preferences = preferences
        self.provider = provider
        self.engine = engine
        self.inputChoice = preferences.inputChoice
        self.outputChoice = preferences.outputChoice
        self.autoRun = preferences.autoRun

        refreshDeviceLists()
    }

    // MARK: - Lifecycle

    func bootstrap() {
        engineQueue.async { [weak self] in
            self?.engine.cleanupOrphans()
        }

        let monitor = DeviceMonitor(dispatchQueue: engineQueue) { [weak self] event in
            self?.handleMonitorEvent(event)
        }
        monitor.start()
        self.monitor = monitor

        rebuildObserver = NotificationCenter.default.addObserver(
            forName: .audioBridgeShouldRebuild,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.engineQueue.async {
                self?.rebuildSync()
            }
        }

        if preferences.autoRun {
            Task { @MainActor in
                self.toggleOn()
            }
        }
    }

    func shutdown() {
        if let observer = rebuildObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        monitor?.stop()
        engineQueue.sync {
            engine.stop()
        }
    }

    // MARK: - User Actions (called from UI on MainActor)

    func toggleOn() {
        guard status != .running, status != .starting else { return }
        status = .starting
        engineQueue.async { [weak self] in
            self?.startSync()
        }
    }

    func toggleOff() {
        engineQueue.async { [weak self] in
            self?.engine.stop()
            Task { @MainActor in
                self?.status = .stopped(.userToggledOff)
            }
        }
    }

    func setInputChoice(_ choice: DeviceChoice) {
        inputChoice = choice
        preferences.inputChoice = choice
        scheduleRebuild()
    }

    func setOutputChoice(_ choice: DeviceChoice) {
        outputChoice = choice
        preferences.outputChoice = choice
        scheduleRebuild()
    }

    // MARK: - Private (engineQueue)

    private func handleMonitorEvent(_ event: DeviceMonitor.Event) {
        // engineQueue 上で呼ばれる
        switch event {
        case .deviceListChanged:
            Task { @MainActor in
                self.refreshDeviceLists()
            }
            // 切断検知 → 動作中なら停止判定（main へ）
            scheduleRebuildOnEngineQueue()
        case .defaultInputChanged, .defaultOutputChanged:
            Task { @MainActor in
                self.refreshDeviceLists()
            }
            scheduleRebuildOnEngineQueue()
        }
    }

    private func scheduleRebuild() {
        engineQueue.async { [weak self] in
            self?.scheduleRebuildOnEngineQueue()
        }
    }

    private func scheduleRebuildOnEngineQueue() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rebuildSync()
        }
        debounceWorkItem = work
        engineQueue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func startSync() {
        // engineQueue 上で実行
        let inputResolved = resolve(choice: preferences.inputChoice, defaultDevice: provider.defaultInputDevice, list: provider.connectedInputDevices)
        let outputResolved = resolve(choice: preferences.outputChoice, defaultDevice: provider.defaultOutputDevice, list: provider.connectedOutputDevices)

        guard let inputUID = inputResolved?.uid, let outputUID = outputResolved?.uid else {
            Task { @MainActor in
                self.status = .stopped(.engineFailed(message: "no system default"))
            }
            return
        }

        if FeedbackLoopDetector.isLoop(inputUID: inputUID, outputUID: outputUID) {
            Task { @MainActor in
                self.status = .stopped(.feedbackLoop)
            }
            return
        }

        // マイク権限チェック（main で要求）
        let semaphore = DispatchSemaphore(value: 0)
        var authorized = false
        DispatchQueue.main.async {
            PermissionHelper.requestMicrophoneAccess { auth in
                authorized = (auth == .authorized)
                semaphore.signal()
            }
        }
        semaphore.wait()

        guard authorized else {
            Task { @MainActor in
                self.status = .stopped(.micPermissionDenied)
            }
            return
        }

        do {
            try engine.start(inputUID: inputUID, outputUID: outputUID)
            Task { @MainActor in
                self.status = .running
            }
        } catch {
            Log.engine.error("start failed: \(error.localizedDescription)")
            Task { @MainActor in
                self.status = .stopped(.engineFailed(message: error.localizedDescription))
            }
        }
    }

    private func rebuildSync() {
        // 動作中のみ再構築（idle のままなら何もしない）
        let currentStatus = DispatchQueue.main.sync { self.status }
        if case .running = currentStatus {
            engine.stop()
            startSync()
        }
    }

    private func resolve(choice: DeviceChoice, defaultDevice: Device?, list: [Device]) -> ResolvedDevice? {
        let resolvedDefault = defaultDevice.map { provider.resolvedDevice(for: $0) }
        let resolvedList = list.map { provider.resolvedDevice(for: $0) }
        return DeviceSelection.resolve(
            choice: choice,
            systemDefault: resolvedDefault,
            connectedDevices: resolvedList
        )
    }

    private func refreshDeviceLists() {
        connectedInputDevices = provider.connectedInputDevices
        connectedOutputDevices = provider.connectedOutputDevices
        defaultInputDevice = provider.defaultInputDevice
        defaultOutputDevice = provider.defaultOutputDevice
    }

    private func applyAutoRunChange() {
        preferences.autoRun = autoRun
        do {
            if autoRun {
                try LoginItemController.register()
            } else {
                try LoginItemController.unregister()
            }
        } catch {
            Log.app.error("autoRun change failed: \(error.localizedDescription)")
            // ロールバック
            autoRun = preferences.autoRun
        }
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: commit**

```bash
git add MacAudioBridge/App/AppState.swift
git commit -m "feat(app): add AppState orchestrating engine + monitor + permissions"
```

---

## Phase 9: UI 層

### Task 18: StatusIcon

**Files:**
- Create: `MacAudioBridge/UI/StatusIcon.swift`

- [ ] **Step 1: `StatusIcon.swift` を実装**

```swift
import SwiftUI

enum StatusIcon {
    static func systemImageName(for status: BridgeStatus) -> String {
        switch status {
        case .running: return "speaker.wave.2"
        case .idle, .stopped(.userToggledOff): return "speaker.slash"
        case .stopped(.feedbackLoop): return "exclamationmark.triangle.fill"
        case .stopped(.deviceDisconnected),
             .stopped(.micPermissionDenied),
             .stopped(.engineFailed):
            return "exclamationmark.triangle.fill"
        case .starting: return "speaker.wave.2"
        }
    }

    /// メニューバーアイコン用の色付き SwiftUI Image。
    static func image(for status: BridgeStatus) -> some View {
        let name = systemImageName(for: status)
        let img = Image(systemName: name)
        switch status {
        case .stopped(.feedbackLoop): return AnyView(img.foregroundStyle(.yellow))
        case .stopped(.deviceDisconnected),
             .stopped(.micPermissionDenied),
             .stopped(.engineFailed): return AnyView(img.foregroundStyle(.red))
        case .idle, .stopped(.userToggledOff): return AnyView(img.foregroundStyle(.secondary))
        default: return AnyView(img)
        }
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodegen generate
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: commit**

```bash
git add MacAudioBridge/UI/StatusIcon.swift
git commit -m "feat(ui): add StatusIcon mapping BridgeStatus to SF Symbol"
```

---

### Task 19: DeviceMenuSection

**Files:**
- Create: `MacAudioBridge/UI/DeviceMenuSection.swift`

- [ ] **Step 1: `DeviceMenuSection.swift` を実装**

```swift
import SwiftUI

struct DeviceMenuSection: View {
    let title: String
    let devices: [Device]
    let defaultDevice: Device?
    let currentChoice: DeviceChoice
    let onSelect: (DeviceChoice) -> Void

    var body: some View {
        Section(header: Text(title)) {
            Button {
                onSelect(.systemDefault)
            } label: {
                HStack {
                    Image(systemName: currentChoice == .systemDefault ? "checkmark" : "")
                        .frame(width: 14)
                    Text("System Default (\(defaultDevice?.name ?? "—"))")
                }
            }

            Divider()

            ForEach(devices) { device in
                Button {
                    onSelect(.specific(uid: device.uid))
                } label: {
                    HStack {
                        Image(systemName: isSelected(device) ? "checkmark" : "")
                            .frame(width: 14)
                        Text(device.name)
                    }
                }
            }
        }
    }

    private func isSelected(_ device: Device) -> Bool {
        if case .specific(let uid) = currentChoice, uid == device.uid {
            return true
        }
        return false
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: commit**

```bash
git add MacAudioBridge/UI/DeviceMenuSection.swift
git commit -m "feat(ui): add DeviceMenuSection for input/output device picker"
```

---

### Task 20: MenuBarView

**Files:**
- Create: `MacAudioBridge/UI/MenuBarView.swift`

- [ ] **Step 1: `MenuBarView.swift` を実装**

```swift
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        // ON/OFF トグル
        Button(action: toggleAction) {
            Text(toggleLabel)
        }

        Divider()

        // 状態表示
        Text(statusText).disabled(true)

        Divider()

        // Input
        DeviceMenuSection(
            title: "Input Device",
            devices: state.connectedInputDevices,
            defaultDevice: state.defaultInputDevice,
            currentChoice: state.inputChoice,
            onSelect: state.setInputChoice
        )

        Divider()

        // Output
        DeviceMenuSection(
            title: "Output Device",
            devices: state.connectedOutputDevices,
            defaultDevice: state.defaultOutputDevice,
            currentChoice: state.outputChoice,
            onSelect: state.setOutputChoice
        )

        Divider()

        // Settings
        Toggle("ログイン時に自動起動 + 自動 Run", isOn: $state.autoRun)

        // 権限拒否時の補助
        if case .stopped(.micPermissionDenied) = state.status {
            Button("システム設定 > マイクを開く") {
                PermissionHelper.openMicrophoneSettings()
            }
        }

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
    }

    private var toggleLabel: String {
        switch state.status {
        case .running, .starting: return "OFF にする"
        default: return "ON にする"
        }
    }

    private func toggleAction() {
        switch state.status {
        case .running, .starting: state.toggleOff()
        default: state.toggleOn()
        }
    }

    private var statusText: String {
        switch state.status {
        case .idle: return "状態: 停止中"
        case .starting: return "状態: 起動中…"
        case .running:
            let inputName = state.connectedInputDevices.first(where: { isCurrentInput($0) })?.name
                ?? state.defaultInputDevice?.name ?? "—"
            let outputName = state.connectedOutputDevices.first(where: { isCurrentOutput($0) })?.name
                ?? state.defaultOutputDevice?.name ?? "—"
            return "状態: 動作中 (\(inputName) → \(outputName))"
        case .stopped(.userToggledOff): return "状態: 停止中"
        case .stopped(.feedbackLoop): return "状態: ⚠ 入出力が同一デバイスです"
        case .stopped(.deviceDisconnected(let uid)):
            return "状態: ⚠ 選択デバイス未接続: \(uid)"
        case .stopped(.micPermissionDenied):
            return "状態: ✕ マイク権限が拒否されています"
        case .stopped(.engineFailed(let msg)):
            return "状態: ✕ \(msg)"
        }
    }

    private func isCurrentInput(_ device: Device) -> Bool {
        if case .specific(let uid) = state.inputChoice { return uid == device.uid }
        return device.uid == state.defaultInputDevice?.uid
    }

    private func isCurrentOutput(_ device: Device) -> Bool {
        if case .specific(let uid) = state.outputChoice { return uid == device.uid }
        return device.uid == state.defaultOutputDevice?.uid
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: commit**

```bash
git add MacAudioBridge/UI/MenuBarView.swift
git commit -m "feat(ui): add MenuBarView composing all menu sections"
```

---

## Phase 10: エントリポイント

### Task 21: MacAudioBridgeApp（@main、多重起動防止）

**Files:**
- Modify: `MacAudioBridge/MacAudioBridgeApp.swift`

- [ ] **Step 1: `MacAudioBridgeApp.swift` を本実装に置き換え**

```swift
import SwiftUI
import AppKit

@main
struct MacAudioBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: delegate.state)
        } label: {
            StatusIcon.image(for: delegate.state.status)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let state: AppState

    override init() {
        self.state = AppState()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 多重起動防止 (§5.1 step 2)
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            Log.app.info("Another instance is running; activating it and terminating self")
            others.first?.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }

        state.bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.shutdown()
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認**

```bash
xcodegen generate
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 全テストが通ることを確認**

```bash
xcodebuild test -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: commit**

```bash
git add MacAudioBridge/MacAudioBridgeApp.swift
git commit -m "feat(app): wire MacAudioBridgeApp as @main with MenuBarExtra and dup-instance guard"
```

---

## Phase 11: 動作確認・整理

### Task 22: アイコンリソース追加（最低限）

**Files:**
- Modify: `MacAudioBridge/Assets.xcassets/`

メニューバーは `StatusIcon` の SF Symbol を使うため、別途画像は不要。アプリアイコン（Dock 非表示なので最低限でよい）も今回は scaffold のままで OK。明示的に追加が必要なら `Assets.xcassets` にアイコンセットを足す。

- [ ] **Step 1: 空の `Assets.xcassets/Contents.json` が無ければ作成**

`MacAudioBridge/Assets.xcassets/Contents.json`:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 2: ビルドして警告がないことを確認**

```bash
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: commit**

```bash
git add MacAudioBridge/Assets.xcassets
git commit -m "chore: add empty Assets.xcassets to silence build warnings"
```

---

### Task 23: 手動結合テスト（spec §9.6 チェックリスト）

実機での動作確認。すべての項目に PASS が必要。

- [ ] **Step 1: Release ビルドを起動**

```bash
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Release build 2>&1 | tail -3
open build/Release/MacAudioBridge.app  # path は xcodebuild の出力で確認
```

- [ ] **Step 2: 以下を 1 つずつ確認**

各項目を手で確認し、PASS/FAIL を記録。FAIL があれば該当 Task に戻って修正。

- [ ] アプリ起動 → デフォルトで OFF（autoRun OFF を期待）
- [ ] 入力に内蔵マイク、出力に内蔵スピーカーを選択 → 喋ると聞こえる
- [ ] 入力と出力を同じデバイスに → 自動停止 + 警告アイコン（黄）
- [ ] 動作中に出力デバイスを抜く → 停止 + エラーアイコン（赤）
- [ ] 「System Default」設定中、システム出力を切替 → 自動追従
- [ ] アプリ終了 → AggregateDevice が消える（下記コマンドで確認）
  ```bash
  system_profiler SPAudioDataType | grep -i mac-audio-bridge
  ```
  Expected: 出力なし
- [ ] ログイン時自動起動を ON → システム設定 > 一般 > ログイン項目 に出現
- [ ] 再ログイン → 自動起動 + autoRun ON 中なら稼働中
- [ ] マイク権限拒否 → メニューでエラー表示 + 「システム設定 > マイクを開く」ボタン
- [ ] クラッシュ模擬（`kill -9`）後の再起動 → 残骸 AggregateDevice が掃除される
- [ ] 入出力で異なるサンプルレートのデバイス → format 変換されて pass-thru

- [ ] **Step 3: 結果を README に記載**

「動作確認済みデバイスの組み合わせ」セクションを追加。
（任意、個人ツールなので省略可）

- [ ] **Step 4: commit（手動テストで何か修正があれば）**

```bash
git add -A
git commit -m "fix: address manual integration test issues" || echo "no fixes needed"
```

---

### Task 24: README 仕上げ + spec / plan の最終 commit

**Files:**
- Modify: `README.md`

- [ ] **Step 1: `README.md` を最終形に更新**

```markdown
# Mac Audio Bridge

macOS の任意の入力デバイスを任意の出力デバイスへ pass-thru するメニューバー常駐ツール。

## 機能

- メニューバー常駐（Dock 非表示）
- 入力 / 出力デバイスを個別に選択可能（システムデフォルトに追従も可）
- フィードバックループ自動検知 → 停止
- ログイン時自動起動 + 自動 Run
- フォーマット変換（サンプルレート / チャンネル数差）は AVAudioEngine が自動処理

## 必要環境

- macOS 13.0 以上
- Xcode 16 以上
- xcodegen (`brew install xcodegen`)

## ビルド

\`\`\`bash
xcodegen generate
xcodebuild -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -configuration Release build
\`\`\`

ビルド成果物: `build/Release/MacAudioBridge.app`

## テスト

ユニットテスト（Pure Swift ロジック層のみ）:

\`\`\`bash
xcodebuild test -project MacAudioBridge.xcodeproj -scheme MacAudioBridge -destination 'platform=macOS'
\`\`\`

CoreAudio 依存層は手動結合テストで確認。手順は spec §9.6 を参照。

## 設計ドキュメント

- 設計仕様: `docs/superpowers/specs/2026-05-07-mac-audio-bridge-design.md`
- 実装計画: `docs/superpowers/plans/2026-05-07-mac-audio-bridge.md`

## ライセンス

MIT
```

> 実際のファイルでは `\`\`\`` を ``` （バックティック 3 つ）に置き換え。

- [ ] **Step 2: 最終 commit**

```bash
git add README.md
git commit -m "docs: finalize README with build/test/spec links"
```

- [ ] **Step 3: タグを打つ（任意）**

```bash
git tag -a v0.1.0 -m "v0.1.0 - first working release"
```

---

## Self-Review チェック（writing-plans 完了時）

実装プランナーが本 plan を spec と突き合わせて確認した結果:

| spec 要件 | 担当 Task |
|---------|----------|
| §2.1〜2.4 入出力選択・pass-thru・feedback loop 防止 | Task 4, 5, 16, 17 |
| §2.5 デバイス変更検知（HAL リスナー） | Task 15, 17 |
| §3 メニュー UI（アイコン状態、メニュー構成） | Task 18, 19, 20 |
| §4 Preferences | Task 7 |
| §5.1 起動シーケンス（多重起動防止、残骸掃除、autoRun） | Task 16, 17, 21 |
| §5.2 終了シーケンス | Task 17, 21 |
| §6 エラーハンドリング全般 | Task 9, 16, 17, 20 |
| §6.1.1 切断時挙動の決定表 | Task 17 (rebuildSync, scheduleRebuild) |
| §6.2 #12 AVAudioEngineConfigurationChange | Task 16, 17 |
| §6.2 #13 debounce | Task 17 (debounceWorkItem) |
| §6.2 #14 多重起動禁止 | Task 21 |
| §7.6 並行性モデル（MainActor / engineQueue / CoreAudio） | Task 15, 17 |
| §8.1 AggregateDevice 作成（ドリフト補正、Private） | Task 14 |
| §8.5 AVAudioEngine 毎回新規化 | Task 16 |
| §8.7 pass-thru 不変条件 I1〜I6 | Task 16 (start メソッド内コメント参照) |
| §9 テスト戦略（ユニット + 手動） | Task 4, 5, 6, 7 / Task 23 |
| §10 ファイル構成 | 全タスク |
| §13 命名・識別子（Bundle ID, Aggregate UID prefix） | Task 1, 14 |
| §14 Info.plist 権限 | Task 1 (project.yml) |
