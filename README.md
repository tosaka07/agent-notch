# Agent Notch

Mac の notch を AI コーディングエージェント（Claude Code, Codex 等）の**統合コマンドセンター**に変える、無料・OSS・多エージェント対応の macOS ネイティブアプリです。

セッションの状態・実行中のツール・トークン消費・権限リクエストを notch 領域にリアルタイム表示し、ターミナルを切り替えることなくエージェントの動きを把握できます。

## 特徴

- **多エージェント対応**: Claude Code / Codex のセッションを統一モデルで表示（拡張可能）
- **リアルタイム状態表示**: thinking / ツール実行 / 権限待ち / 完了などをコンパクトに可視化
- **権限リクエストの通知**: notch 上での確認導線
- **OSS・無料**: サンドボックスなしのネイティブアプリとして配布

詳しい差別化戦略やコンセプトは [`docs/requirements.md`](docs/requirements.md) を参照してください。

## 動作要件

- macOS 26 以降
- Swift tools 6.2 以降（Xcode プロジェクトは無く、SPM の `Package.swift` が真実）

## セットアップ

```bash
# ビルド（デバッグ）
swift build

# GUI アプリ実行（hook の自動インストール、socket サーバー起動を含む）
swift run AgentNotch
#   ログレベル変更: AGENT_NOTCH_LOG=debug swift run AgentNotch
```

初回起動時に `~/.claude/settings.json`（および Codex の hooks 設定）へフックが自動登録されます。手動で操作したい場合は CLI から直接実行できます。

```bash
# CLI（hook 本体。通常は agent の hook から起動される）
swift run agent-notch install       # Claude/Codex 両方に hook を登録
swift run agent-notch remove
swift run agent-notch hook --agent claude   # stdin JSON → socket 転送
swift run agent-notch hook --agent codex
```

## テスト

```bash
swift test
swift test --filter AgentNotchTests.TranscriptParserTests           # ファイル単位
swift test --filter AgentNotchTests.TranscriptParserTests/testName  # 個別
```

## アーキテクチャ概要

Package は 3 実行ターゲット + 1 ライブラリ + 1 テストターゲットで構成されています。UI に依存しないコードはすべて `AgentNotchCore` に置き、GUI と CLI の両方から参照します。

| ターゲット | 役割 |
| --- | --- |
| `AgentNotchCore/` | モデル、イベントパーサー、socket サーバー/クライアント、hook インストーラー（AppKit/SwiftUI 非依存） |
| `AgentNotch/` | GUI アプリ。`NotchPanel`（NSPanel）+ SwiftUI View |
| `AgentNotchCLI/` | `agent-notch` バイナリ（hook entry point + installer） |
| `AgentNotchTests/` | Swift Testing による Core / GUI 双方のテスト |

エージェントの hook 起動 → Unix socket 経由でのイベント転送 → `EventProcessor` によるセッション状態更新 → SwiftUI 再描画、という一方向のイベントフローを取ります。詳細は [`CLAUDE.md`](CLAUDE.md) を参照してください。

## ドキュメント

- [`docs/requirements.md`](docs/requirements.md) — 機能要件と差別化戦略
- [`docs/tech-selection.md`](docs/tech-selection.md) — ライブラリ選定理由と不採用候補
- [`docs/roadmap.md`](docs/roadmap.md) — Phase 0/1/2/3 の完了基準と残タスク
- [`docs/data-and-display-spec.md`](docs/data-and-display-spec.md) — UI 表示仕様の詳細

## コントリビュート

コーディング規約や設計上の制約は [`CLAUDE.md`](CLAUDE.md) にまとめています。Pull Request を送る前に一読してください。
