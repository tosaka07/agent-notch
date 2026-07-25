# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Agent Notch — macOS ネイティブの OSS アプリ。Mac の notch に AI コーディングエージェント（Claude Code, Codex 等）のセッション状態・ツール実行・トークン消費・権限リクエストをリアルタイム表示する。`docs/requirements.md` / `docs/tech-selection.md` / `docs/roadmap.md` に設計意図が集約されている。

- 最小 macOS: 26.0 (Tahoe) — `Package.swift` の `platforms` が真実。macOS 26 の API
  （`glassEffect` / Liquid Glass など）を availability 分岐なしで使える
- Swift tools: 6.0, SwiftUI + AppKit（NSPanel ベースの notch オーバーレイ）
- サンドボックス **無効**（Unix socket / Accessibility API のため）
- LSUIElement=YES（メニューバー常駐、Dock に出ない）

## コマンド

ビルド・実行は SPM ベース。Xcode プロジェクトは無く `Package.swift` が真実。

```bash
# ビルド（デバッグ）
swift build

# GUI アプリ実行（hook の自動インストール、socket サーバー起動を含む）
swift run AgentNotch
#   ログレベル変更: AGENT_NOTCH_LOG=debug swift run AgentNotch

# CLI（hook 本体。通常は agent の hook から起動される）
swift run agent-notch install       # Claude/Codex 両方に hook を登録
swift run agent-notch remove
swift run agent-notch hook --agent claude   # stdin JSON → socket 転送
swift run agent-notch hook --agent codex

# テスト
swift test
swift test --filter AgentNotchTests.TranscriptParserTests           # ファイル単位
swift test --filter AgentNotchTests.TranscriptParserTests/testName  # 個別
```

ビルド生成物は `.build/debug/AgentNotch`（.app ではなく裸の実行ファイル）。配布用の .app バンドル化は未整備。

## アーキテクチャ

### ターゲット分割

Package は 3 実行 + 1 ライブラリ + 1 テスト構成。**UI 非依存のコードは必ず `AgentNotchCore` 側に置く**。GUI と CLI の両方から参照するため。

- `AgentNotchCore/` — モデル, イベントパーサー, socket サーバー/クライアント, hook インストーラー, ユーティリティ。AppKit/SwiftUI には依存しない（`swift-log` のみ）
- `AgentNotch/` — GUI アプリ。`NotchPanel`（NSPanel）+ SwiftUI View を `NSHostingView` で埋め込み
- `AgentNotchCLI/` — `agent-notch` バイナリ。hook entry point + installer
- `AgentNotchTests/` — Swift Testing (`import Testing` / `@Test`)。Core と GUI 両方を対象

### イベントフロー（全体）

```
Claude Code / Codex CLI
    │  (hook 起動)
    ▼
agent-notch hook  ──stdin JSON──▶  AgentNotchCore/HookHandler
    │                                       │ (fire-and-forget)
    │                                       ▼
    │                        /tmp/agent-notch-$USER.sock (Unix socket, 4B長さprefix + JSON)
    │                                       │
    ▼                                       ▼
即時 exit（agent をブロックしない）   AgentNotch/AppDelegate.startSocketServer
                                            │
                                            ▼
                        EventProcessor.parseMessage (非 MainActor, 純データ)
                                            │
                                            ▼
                        EventProcessor.apply (@MainActor, SessionManager 更新)
                                            │
                                            ▼
                        @Published sessions → SwiftUI re-render
```

**重要な制約（`docs/roadmap.md` §2 末尾参照）**: `HookHandler` は現状すべて fire-and-forget。socket に送信後、応答を待たずに即 exit する。そのため以下は**現時点では実装不能**:
- hook の stdout 経由で permission を approve/deny（PermissionRequest のみ recv ありに戻す将来プランあり）
- PreToolUse での block / deny 返却
- systemMessage / additionalContext の注入

代わりに現状は、socket の `respondToPermission` で別経路でレスポンスを返している（`SocketServer.swift` 内 `PendingSocketResponse`）。権限機能を触る際はこの分岐を確認すること。

### MainActor 境界

socket コールバックは非 MainActor で走る。`EventProcessor` は意図的に **parse（pure）/ apply（@MainActor）/ backfill（@MainActor）** に三分割されている。新しいイベントを処理する際も同じ分割を維持する：
1. socket 受信クロージャ内で必要なフィールドを取り出し（`message["cwd"]` 等）
2. `Task { @MainActor in ... }` で state 変更と NotificationCenter.post
3. 重い I/O（transcript パース、TerminalJumper 解決など）は `Task.detached` で off-MainActor、結果を `await MainActor.run { ... }` で反映

### UI モードステートマシン

`NotchContentView.swift` の `NotchMode`: `compact` → `notification` / `expanded` → `sessionDetail(id)`。`NotchViewModel`（`@Observable`）が単一の source of truth。モード遷移は多数の通知名で駆動される（`AppDelegate.swift` 先頭の `Notification.Name` extension がカタログ）。新しいトリガーを追加する際はそこに定義を集める。

### セッションモデル

`UnifiedSession`（`AgentNotchCore/Models/`）が**全エージェント共通**のセッション表現。`AgentType` で分岐する表示・挙動は UI 側で行い、コアモデルは agent 非依存を保つ。`SessionManager` は `@Published sessions: [String: UnifiedSession]` を持ち、state 変更後は必ず `notifyChange()` を呼ぶ（`UnifiedSession` は class なので dictionary の identity 変化だけでは SwiftUI が再描画しない）。

### Hook インストール

`HookInstaller` が `~/.claude/settings.json` と Codex の `hooks.json` / `config.toml` を書き換える。GUI 起動時に `installIfNeeded()` が自動実行される。Codex は `[features] codex_hooks = true` が必要で、これも installer が追記する。**既存 config を壊さないこと**が最優先（ユーザーの他設定が混ざっているため）。

### Notch ジオメトリ

`AgentNotch/Geometry/` が notch 形状 / サイズ計算を集約。`NSScreen+Notch.swift` が `safeAreaInsets` + `auxiliaryTopLeftArea/Right` から物理 notch を割り出す。notch 無し Mac / 外部ディスプレイ時の fallback は `AppDelegate.applyDisplayMode()` が `Defaults[.displayMode]`（followFocus / allDisplays / builtinOnly / specificDisplay）で分岐。

## コーディング規約

- 会話・コミットメッセージ・ドキュメントは**日本語**。コードのコメントも原則日本語で OK
- ログは `Log.panel` / `Log.events` / `Log.socket` / `Log.hooks` / `Log.terminal` / `Log.notification` / `Log.input` のいずれかを使い、`print` は使わない
- Swift Concurrency 優先（`DispatchQueue` は socket 層のように Network.framework と直接対話する箇所のみ）
- `@Sendable` / `Sendable` 準拠は MainActor 境界を跨ぐクロージャで必須
- `Defaults.Key` は `AppSettings.swift` に集約

## 参照すべきドキュメント

- `docs/requirements.md` — 機能要件と差別化戦略
- `docs/tech-selection.md` — ライブラリ選定理由と不採用候補（再議論前に読む）
- `docs/roadmap.md` — Phase 0/1/2/3 の完了基準と残タスク。**「技術的注意事項」節に hook fire-and-forget / Codex hooks 有効化の罠が書かれている**
- `docs/data-and-display-spec.md` — UI 表示仕様の詳細
- `docs/superpowers/plans/` — 過去の実装計画（現在の実装の経緯を知りたいとき）
