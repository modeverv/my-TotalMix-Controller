# TotalMix Snapshot Touch Controller
## Codex 引き継ぎ・実装仕様メモ

作成日: 2026-09-07

---

## 1. 目的

RME TotalMix FX の Snapshot 1〜8 を、macOS 上の自作アプリから大きなボタンで呼び出す。

主な利用方法は、iPad を OpenDisplay で Mac の外部ディスプレイとして使用し、その iPad 上に本アプリを表示してタッチ操作すること。

TotalMix 本体は高機能だが、iPad 上では UI が細かくタッチ操作しづらいため、本アプリを「Snapshot 呼び出し専用の大型タッチパネル」として使う。

### 最終イメージ

```text
iPad
  │
  │ OpenDisplay（タッチ → macOS のクリック操作）
  ▼
macOS
┌─────────────────────────────────┐
│ TotalMix Snapshot Touch         │
│                                 │
│ ┌───────────┐ ┌───────────┐     │
│ │ Snapshot 1│ │ Snapshot 2│     │
│ │  任意名称  │ │  任意名称  │     │
│ └───────────┘ └───────────┘     │
│                                 │
│      ... Snapshot 8 まで ...    │
└─────────────────────────────────┘
  │
  │ CoreMIDI
  ▼
IAC Bus: TotalMixRemote
  │
  ▼
TotalMix FX
  │
  ▼
Snapshot 1〜8 Recall
```

---

## 2. 現在すでに完了している環境設定

macOS の「Audio MIDI 設定」→「MIDI スタジオ」→ IAC Driver で、TotalMix 専用の IAC バスを作成済み。

### IAC バス

```text
TotalMixRemote
```

TotalMix FX 側では以下まで設定済み。

```text
Mixer Settings
  └─ MIDI
      ├─ Select Controller: 1
      ├─ In Use: ON
      ├─ Input Port: IAC TotalMixRemote
      └─ Output Port: None
```

つまりアプリ側では、独自の仮想 MIDI デバイスを作成する必要はない。

**既存の IAC TotalMixRemote 宛てに MIDI を送信するだけでよい。**

---

## 3. TotalMix 側で確認する設定

実装テスト前に以下を確認する。

### 必須

```text
TotalMix FX
  Options
    Enable MIDI Control = ON
```

Mixer Settings → MIDI では、

```text
In Use = ON

Input Port
  IAC TotalMixRemote

Mackie Control Options
  Enable Protocol Support = ON
```

にする。

Snapshot 呼び出し用 Note メッセージは TotalMix の Mackie Protocol 系 MIDI コマンドに含まれるため、`Enable Protocol Support` が OFF だと反応しない。

### バックグラウンド動作

本アプリをタッチすると TotalMix はバックグラウンドになるため、

```text
Disable MIDI in background = OFF
```

にしておく。

本アプリの主要要件の一つは、

> TotalMix がバックグラウンドのまま Snapshot を変更できること

である。

---

## 4. MIDI 仕様

RME Fireface UCX II / TotalMix FX の MIDI Remote Control 仕様を使用する。

### MIDI Channel

```text
MIDI Channel 1
```

プログラム内部で MIDI チャンネルを 0 origin で扱う場合は、

```text
channel = 0
```

となる。

### Snapshot と Note Number

| Snapshot | Note decimal | Hex |
|---|---:|---:|
| Snapshot 1 | 54 | 0x36 |
| Snapshot 2 | 55 | 0x37 |
| Snapshot 3 | 56 | 0x38 |
| Snapshot 4 | 57 | 0x39 |
| Snapshot 5 | 58 | 0x3A |
| Snapshot 6 | 59 | 0x3B |
| Snapshot 7 | 60 | 0x3C |
| Snapshot 8 | 61 | 0x3D |

### 送信方法

TotalMix では Snapshot 切り替えが Note Off で動作する事例が複数確認されている。

MVP では明示的に MIDI Note Off を送る。

```text
Status: 0x80       // Note Off, MIDI Channel 1
Data1 : 54〜61     // Snapshot 1〜8
Data2 : 0          // Velocity 0
```

例:

```text
Snapshot 1
80 36 00

Snapshot 2
80 37 00

Snapshot 8
80 3D 00
```

もし実機テストで `0x80` Note Off が反応しない場合のフォールバックとして、

```text
Note On / velocity 0

90 36 00
```

も試せるよう、MIDI 送信処理は一箜所に集約すること。

MIDI 仕様上 Note On velocity 0 は Note Off として扱われ、TotalMix でも動作報告がある。

---

## 5. 技術構成

### 必須

- macOS native application
- Swift
- SwiftUI
- CoreMIDI
- 外部ライブラリなし
- ネットワーク通信なし
- AppleScript 不使用
- Accessibility API 不使用
- TotalMix UI の自動クリック等は行わない

### 推奨構成

```text
TotalMixSnapshotTouch/
├── TotalMixSnapshotTouchApp.swift
├── Models/
│   └── Snapshot.swift
├── MIDI/
│   └── MIDIManager.swift
├── Views/
│   ├── MainView.swift
│   ├── SnapshotButton.swift
│   └── SettingsView.swift
└── Persistence/
    └── AppSettings.swift
```

複雑にしすぎないこと。

このアプリは「8 個のボタンから MIDI Note を送る」ことが本質であり、過剰なアーキテクチャは不要。

---

## 6. CoreMIDI 実装方針

本アプリ自身は Virtual MIDI Source を作らない。

IAC Driver に存在する MIDI Destination を列挙し、その中から `TotalMixRemote` を選択して送信する。

概念的には以下。

```text
MIDIClientCreate
    ↓
MIDIOutputPortCreate
    ↓
MIDIGetNumberOfDestinations
    ↓
MIDIGetDestination
    ↓
目的の IAC Destination を特定
    ↓
MIDISend
```

### MIDIManager の責務

`MIDIManager` は以下のみ担当する。

```swift
final class MIDIManager: ObservableObject {
    // MIDI destination 一覧取得
    // destination 選択
    // 接続状態管理
    // Snapshot Note Off の送信
}
```

想定 API:

```swift
func refreshDestinations()

func selectDestination(_ destination: MIDIDestinationInfo)

func sendSnapshot(_ number: Int) throws
```

### Destination の検索

macOS / CoreMIDI 側の表示名称が、

```text
IAC TotalMixRemote
```

または

```text
TotalMixRemote
```

等になる可能性を考慮する。

初回起動時は、

```text
displayName.lowercased().contains("totalmixremote")
```

で自動候補を探してよい。

ただし、名前だけに完全依存しないこと。

ユーザーが Settings で MIDI Destination を選択できるようにし、選択後は可能なら CoreMIDI の Unique ID を UserDefaults に保存する。

次回起動時:

1. 保存済み Unique ID が存在すればそれを優先
2. 見つからなければ `TotalMixRemote` の名前一致を検索
3. それでも無ければ未接続状態

とする。

---

## 7. UI 要件

### 基本画面

Snapshot 1〜8 の大型ボタンを表示する。

iPad / OpenDisplay でタッチするため、マウス向けの細かい UI にしない。

### レイアウト

ウインドウサイズに応じて自動変更。

#### 横長

```text
┌─────────┬─────────┬─────────┬─────────┐
│    1    │    2    │    3    │    4    │
│ name    │ name    │ name    │ name    │
├─────────┼─────────┼─────────┼─────────┤
│    5    │    6    │    7    │    8    │
│ name    │ name    │ name    │ name    │
└─────────┴─────────┴─────────┴─────────┘
```

#### 縦長

```text
┌──────────────┬──────────────┐
│      1       │      2       │
├──────────────┼──────────────┤
│      3       │      4       │
├──────────────┼──────────────┤
│      5       │      6       │
├──────────────┼──────────────┤
│      7       │      8       │
└──────────────┴──────────────┘
```

SwiftUI の `LazyVGrid` 等で実現してよい。

### ボタン

各ボタンには、

```text
Snapshot 番号
ユーザー設定可能な名前
```

を表示する。

初期値:

```text
Snapshot 1
Snapshot 2
...
Snapshot 8
```

ユーザーが後で、

```text
普段
DAW
Guitar
Bass
Recording
Surround
Headphones
etc.
```

のように自由に変更できるようにする。

### タッチ領域

- 各ボタンは可能な限り画面を均等に埋める
- 小さなアイコン中心の UI にしない
- ボタン全体がクリック / タッチ領域
- タップ時の視覚フィードバックを明確にする

---

## 8. 状態表示

画面の端に小さく MIDI 接続状態を表示する。

例:

```text
● MIDI: IAC TotalMixRemote
```

接続できていない場合:

```text
● MIDI destination not found
```

接続エラーでアプリをクラッシュさせない。

Settings を開いてポート選択できるようにする。

---

## 9. 「現在の Snapshot」表示についての重要事項

現在 TotalMix 側は、

```text
Output Port = None
```

である。

したがってアプリは TotalMix から状態フィードバックを受け取らない。

よって、ボタンを強調表示する場合、それは厳密には、

```text
Current Snapshot
```

ではなく、

```text
Last Sent Snapshot
```

である。

TotalMix 本体・ARC USB・別 MIDI Controller 等から Snapshot が変更された場合、本アプリはその変更を検知できない。

### MVP の仕様

最後に本アプリから送信した Snapshot を強調表示してよい。

ただしコード・UI上の意味は、

```text
lastSentSnapshot
```

とする。

`currentSnapshot` と命名して TotalMix の実状態と誤解させない。

将来的に双方向同期が必要になった場合のみ、TotalMix の MIDI Output / OSC 等を検討する。

---

## 10. Settings 画面

画面右上等に小さな歯車ボタンを置く。

Settings には最低限以下を用意する。

### MIDI Destination

CoreMIDI から列挙した MIDI 出力先を Picker で表示。

例:

```text
MIDI Destination

[IAC TotalMixRemote ▼]
```

Refresh ボタンも用意する。

### Snapshot Names

```text
Snapshot 1 [________________]
Snapshot 2 [________________]
...
Snapshot 8 [________________]
```

UserDefaults に保存する。

### Reset

Snapshot 名を初期値へ戻すボタン。

---

## 11. キーボード操作

タッチ操作が主目的だが、Mac 単体でも便利なので低コストで実装可能なら対応する。

```text
1 → Snapshot 1
2 → Snapshot 2
...
8 → Snapshot 8
```

ただし MVP の完成を遅らせる場合は後回しでよい。

---

## 12. ウインドウ

普通の macOS アプリとして作る。

- menu bar only app にはしない
- 通常ウインドウを持つ
- resizable
- macOS Full Screen 対応
- iPad/OpenDisplay 側で最大化して使用可能

初期サイズの目安:

```text
900 x 600
```

ただしレイアウトは固定ピクセルに依存しない。

---

## 13. 非要件

MVP では以下を実装しない。

- TotalMix のフェーダー操作
- TotalMix の EQ 操作
- TotalMix の Routing 編集
- TotalMix Workspace 管理
- Snapshot の保存
- OSC
- ARC USB の制御
- Audio Unit / VST
- 独自 Virtual MIDI device
- MIDI Learn
- ネットワーク経由制御
- iPad ネイティブアプリ
- AppleScript
- UI Automation
- Accessibility 権限
- TotalMix のプロセス操作

Snapshot Recall 専用アプリとして小さく保つ。

---

## 14. エラー処理

### IAC Destination が存在しない

アプリは起動可能。

画面に、

```text
MIDI destination not found.
Open Settings and select a MIDI destination.
```

相当を表示。

ボタンを押してもクラッシュしない。

### Destination が途中で消えた

CoreMIDI の送信失敗を捕捉し、

```text
MIDI disconnected
```

状態にする。

Refresh で再検索できるようにする。

### TotalMix が起動していない

MIDI の送信自体は成功し得るため、アプリ側では TotalMix の起動状態を必須チェックしない。

TotalMix のプロセス監視も MVP では不要。

---

## 15. Acceptance Criteria

以下を満たしたら MVP 完了。

### AC-01

アプリ起動時に IAC `TotalMixRemote` を発見できる。

### AC-02

Snapshot 1 ボタンを押すと MIDI Channel 1 / Note 54 の Note Off が送信され、TotalMix が Snapshot 1 に切り替わる。

### AC-03

Snapshot 2〜8 についても Note 55〜61 で正しく切り替わる。

### AC-04

TotalMix がバックグラウンドでも切り替わる。

### AC-05

アプリを OpenDisplay 上の iPad に表示し、タッチでボタン操作できる。

OpenDisplay 側のタッチは macOS の通常クリックとして届く前提なので、本アプリ側で iPad 固有 API は使用しない。

### AC-06

MIDI destination が見つからなくてもクラッシュしない。

### AC-07

Settings から MIDI destination を手動選択できる。

### AC-08

Snapshot 1〜8 の表示名を変更して再起動しても保持される。

### AC-09

最後に押したボタンを視覚的に識別できる。

ただしこれは `lastSentSnapshot` であり、TotalMix の実状態を保証するものではない。

---

## 16. 手動テスト項目

### MIDI 接続

1. TotalMix を起動
2. `Options > Enable MIDI Control` が ON
3. Mixer Settings → MIDI
4. Controller 1 → In Use
5. Input = `IAC TotalMixRemote`
6. Enable Protocol Support = ON
7. Disable MIDI in background = OFF
8. 本アプリ起動
9. Status が `IAC TotalMixRemote` 接続済みになること

### Snapshot

順番に、

```text
1 → 2 → 3 → 4 → 5 → 6 → 7 → 8
```

を押し、TotalMix 側の Snapshot が追従すること。

### Background

1. TotalMix を背面へ
2. 本アプリを foreground にする
3. Snapshot ボタンを押す
4. TotalMix が裏で切り替わること

### OpenDisplay

1. アプリウインドウを iPad 側へ移動
2. Full Screen または最大化
3. 全 8 ボタンを指でタッチ
4. 誤タップしにくいサイズであること

---

## 17. 実装上の注意

### MIDI note name は使わない

RME マニュアルには、

```text
F#3
G3
...
```

等のノート名表記もあるが、オクターブ表記はソフトウェアによって異なる。

コードでは必ず decimal Note Number を使う。

```text
54〜61
```

を正とする。

### Channel 1 の 0 origin

ライブラリ/API により、

```text
MIDI Channel 1
```

を

```text
0
```

として扱う。

Raw MIDI Status Byte を使う場合は明確で、

```text
Note Off Ch.1 = 0x80
```

となる。

### CoreMIDI endpoint 名

UI 上の名前と CoreMIDI API で得られる Display Name が完全一致するとは限らない。

そのため、

- Unique ID 保存
- 手動選択
- 名前部分一致による初回候補検索

の順で堅牢にする。

---

## 18. 将来拡張候補

MVP 完成後、必要なら以下を追加可能。

### A. Speaker B / Dim / Mono

同じ TotalMix MIDI Remote Note を使える。

例:

```text
Speaker B : Note 50
Mono      : Note 42
Dim       : Note 93
```

Snapshot と同様に大型ボタン化できる。

### B. Main Volume

MIDI CC により Main Out volume 制御を追加可能。

ただし今回の MVP には入れない。

### C. 双方向状態同期

TotalMix の MIDI Output または OSC を使い、TotalMix / ARC 等から変更された状態も UI に反映する。

ただし仕様が大幅に増えるため別フェーズとする。

### D. レイアウトプリセット

「Snapshot の 8 ボタンだけ」以外に、

```text
Recording
Practice
Monitoring
```

等の画面ページを追加する。

これも MVP 後。

---

## 19. Codex に対する実装優先順位

以下の順で進める。

### Phase 1: MIDI 疎通だけ

最初に UI を作り込まず、

```text
Test Snapshot 1
```

ボタン一つだけで、

```text
IAC TotalMixRemote
↓
Channel 1
↓
Note Off 54
```

を送信する。

**TotalMix の Snapshot 1 が実際に切り替わるところまで最優先で確認する。**

### Phase 2: 8 ボタン化

Note 54〜61 をマッピング。

### Phase 3: UI

OpenDisplay / iPad 用に大型化し、adaptive grid 化。

### Phase 4: Settings

- MIDI destination 選択
- Snapshot 名変更
- UserDefaults 保存

### Phase 5: 仕上げ

- エラー表示
- lastSentSnapshot 表示
- Full Screen 確認
- README

---

## 20. Codex に最初に渡す指示

以下をそのまま Codex の最初のタスクとして使用できる。

```text
このリポジトリに macOS native app
「TotalMix Snapshot Touch」を実装してください。

まず HANDOFF.md を読み、仕様を理解してください。

最優先は UI ではなく MIDI 疎通です。

Swift + SwiftUI + CoreMIDI のみを使用し、
外部ライブラリは追加しないでください。

macOS の IAC Driver に作成済みの
「TotalMixRemote」destination を探索し、
MIDI Channel 1 の Note Off 54 を送信して、
RME TotalMix FX の Snapshot 1 を呼び出せる
最小実装から開始してください。

Raw MIDI では以下です。

Snapshot 1:
80 36 00

Snapshot 2〜8:
Note number 55〜61

TotalMix 側はすでに
Input Port = IAC TotalMixRemote
に設定済みです。

MIDI 疎通コードは MIDIManager に分離し、
その後 8 個の大型 Snapshot ボタン、
MIDI destination picker、
Snapshot 名の UserDefaults 保存を実装してください。

OpenDisplay を使った iPad タッチ操作を主用途とするため、
ボタンは画面全体を使う大きな adaptive grid にしてください。

重要:
TotalMix Output Port は None のため、
アプリが把握できるのは Current Snapshot ではなく
Last Sent Snapshot だけです。
変数名や UI 上でもこの違いを守ってください。

実装後は xcodebuild でビルド確認し、
README に起動方法と TotalMix 側の必須設定を記載してください。
```

---

## 21. 参照仕様

RME Fireface UCX II User's Guide v1.6 (02/2026)

- Chapter 25.8.2 MIDI Page
- Chapter 28 MIDI Remote Control
- Chapter 28.3 Setup
- Chapter 28.5 MIDI Control

公式仕様上、

- TotalMix は MIDI remote control をサポート
- MIDI Input / Output を個別指定可能
- feedback 不要なら MIDI Output = NONE でよい
- Snapshot 1〜8 は MIDI Channel 1 / Note 54〜61
- `Enable Protocol Support` を無効化すると Snapshot 等の simple MIDI commands も無効になる

という前提で実装する。

---

## 22. MVP 完成形

最終的にユーザー操作はこれだけでよい。

```text
iPadを見る
    ↓
大きな「Guitar」ボタンをタップ
    ↓
macOS app
    ↓
IAC TotalMixRemote
    ↓
MIDI Note Off
    ↓
TotalMix Snapshot Recall
    ↓
完了
```

TotalMix の細かい UI を iPad から直接操作する必要をなくすことが、このアプリの価値。
