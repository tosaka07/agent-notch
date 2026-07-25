# Agent Notch — 開発ロードマップ

## フェーズ概要

```
Phase 0 (基盤)     ██░░░░░░░░░░░░░░  Xcode プロジェクト + Notch ウィンドウ
Phase 1 (MVP)      ████████░░░░░░░░  Claude Code 統合 + コア UI
Phase 2 (拡張)     ████████████░░░░  Codex 統合 + テレメトリ + 権限管理
Phase 3 (成熟)     ████████████████  Gemini + プラグイン + カスタマイズ
```

---

## Phase 0: 基盤構築

**ゴール**: 空の notch オーバーレイアプリが起動し、notch 領域にウィンドウを表示できる状態

### 0.1 プロジェクトセットアップ
- [ ] Xcode プロジェクト作成 (macOS App, Swift, SwiftUI)
- [ ] SPM 依存追加: Sparkle, Defaults, LaunchAtLogin-Modern
- [ ] アプリ設定: LSUIElement=YES (メニューバーアプリ), サンドボックス無効
- [ ] GitHub リポジトリ初期化、CI (GitHub Actions: build + test)
- [ ] ライセンス選定 (Apache 2.0 or MIT)

### 0.2 Notch ウィンドウ
- [ ] `NotchPanel` (NSPanel サブクラス): borderless, transparent, level=mainMenu+3
- [ ] `NotchGeometry`: NSScreen.safeAreaInsets + auxiliaryTopLeftArea/Right で notch サイズ計算
- [ ] `NotchShape`: quadratic curve で notch 形状描画 (animatableData 対応)
- [ ] マウスイベント: ignoresMouseEvents + NSEvent グローバルモニターでホバー/クリック検出
- [ ] マルチディスプレイ: 外部ディスプレイ/notch なし Mac でフローティングバー表示
- [ ] スクリーン接続/切断の監視 (NSScreen.didChangeScreenParametersNotification)

### 0.3 基本 UI シェル
- [ ] コンパクトモード: notch 両サイドにプレースホルダー表示
- [ ] 展開アニメーション: クリックで NotchShape を spring アニメーションで拡大
- [ ] 折りたたみ: 外側クリックまたはエスケープで閉じる
- [ ] 3段階遷移: コンパクト → 展開 → フルパネル

### 0.4 アプリライフサイクル
- [ ] メニューバーアイコン (NSStatusItem) + 設定メニュー
- [ ] LaunchAtLogin-Modern でログイン時自動起動
- [ ] Sparkle 2 で自動アップデート基盤

**成果物**: notch に被さるアニメーション付きの空パネルが表示されるアプリ

---

## Phase 1: Claude Code 統合 (MVP)

**ゴール**: Claude Code のセッションをリアルタイム監視し、notch で状態・ツール・トークンを表示。権限の Approve/Deny が GUI から可能

### 1.1 Unix Socket サーバー
- [ ] Network.framework (NWListener) で Unix socket サーバー起動
  - ソケットパス: `/tmp/agent-notch-{username}.sock`
  - AeroSpace 方式: 4バイト長さプレフィックス + JSON
- [ ] Swift Concurrency で接続ごとに Task 生成
- [ ] 接続切断の検出とクリーンアップ
- [ ] ソケットファイルの起動時クリーンアップ

### 1.2 Hook インストーラー
- [ ] 初回起動時に `~/.claude/hooks/` 配下にフック登録
  - 対象イベント (10個): SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, Notification, Stop, SubagentStop, SessionEnd
  - PreCompact (auto/manual)
- [ ] フックスクリプト: stdin JSON を Unix socket に転送する Python/Shell スクリプト
  - PID + TTY 情報を付加 (`os.getppid()`, `ps -p PID -o tty=`)
- [ ] フックの自動更新 (バージョンチェック)
- [ ] フック登録の確認ダイアログ

### 1.3 統一イベントモデル (Claude 部分)
- [ ] `AgentType.claudeCode`
- [ ] `SessionStatus` enum: idle, thinking, toolRunning, permissionWaiting, compacting, error, completed
- [ ] `UnifiedSession`: セッション状態管理
- [ ] `ToolInfo`: ツール名 + 要約生成 (Edit→ファイル名, Bash→コマンド先頭, etc.)
- [ ] イベントマッピング:
  - SessionStart → starting → idle
  - UserPromptSubmit → thinking
  - PreToolUse → toolRunning (ToolInfo 更新)
  - PostToolUse → thinking (ToolInfo 完了)
  - PermissionRequest → permissionWaiting
  - Stop → idle
  - SessionEnd → completed

### 1.4 トークン取得
- [ ] `transcript_path` から JSONL ファイルをパース
- [ ] Stop イベント受信時に末尾の `usage` フィールドを読み取り
- [ ] input_tokens / output_tokens / cache_creation_input_tokens / cache_read_input_tokens を集計
- [ ] モデル名 × トークン数 × 価格テーブルでコスト推計

### 1.5 コンパクトモード UI
- [ ] エージェントインジケーター: アイコン + 状態色 + アニメーション
  - idle=グレー静止, thinking=黄パルス, toolRunning=緑スライド, permissionWaiting=赤速パルス, error=赤フラッシュ, completed=青フェード
- [ ] ツール要約テキスト表示 (最大30文字)
- [ ] 複数セッション表示 (左右に分配)

### 1.6 展開モード UI
- [ ] セッションカード: エージェント名 + モデル + 経過時間
- [ ] 現在のツール + 引数要約
- [ ] トークン表示: `12.4k in / 3.2k out ~$0.24`
- [ ] ツール実行回数 + 作業ディレクトリ
- [ ] 権限待ちバッジ

### 1.7 権限管理 (Claude Code)
- [ ] PermissionRequest 受信 → pendingPermissions キューに追加
- [ ] 展開モードに権限バッジ表示
- [ ] フルパネル権限タブ:
  - ツール名 + 引数のプレビュー
  - Approve / Deny / Approve for Session ボタン
  - hook stdout 経由で `decision.behavior` を返却
- [ ] 承認履歴のリスト表示
- [ ] PermissionRequest の timeout 対応 (86400秒)

### 1.8 通知 & サウンド
- [ ] 状態遷移に応じたサウンド再生 (AVAudioPlayer)
  - completed: 完了音, permissionWaiting: アラート音, error: エラー音
- [ ] バンドルサウンドファイル (3種)
- [ ] macOS 通知センター連携 (UNUserNotificationCenter)
- [ ] サウンド ON/OFF 設定

**成果物**: Claude Code の全セッションを notch でリアルタイム監視。GUI から権限承認が可能。トークン/コスト表示。

---

## Phase 2: Codex 統合 + テレメトリ強化

**ゴール**: Codex をリアルタイム監視。テレメトリダッシュボードで日次/週次のコスト・利用統計を表示

### 2.1 OTLP/HTTP レシーバー
- [ ] Hummingbird で HTTP サーバー起動 (port 4318)
  - `POST /v1/logs` → LogRecord デコード
  - `POST /v1/metrics` → MetricData デコード
- [ ] swift-protobuf で OTLP proto からデコーダー生成
  - `opentelemetry.proto.logs.v1.LogsData`
  - `opentelemetry.proto.metrics.v1.MetricsData`
- [ ] protobuf (binary) と JSON の両方を Accept
- [ ] Content-Type ヘッダーで判定

### 2.2 Codex 自動設定
- [ ] 初回起動時に `~/.codex/config.toml` を検出
- [ ] `[otel]` セクションが未設定なら追加:
  ```toml
  [otel]
  exporter = { otlp-http = { endpoint = "http://localhost:4318/v1/logs" } }
  metrics_exporter = "otlp-http"
  ```
- [ ] 設定変更の確認ダイアログ

### 2.3 Codex イベントパーサー
- [ ] OTLP Log イベントを統一イベントモデルにマッピング:
  - `conversation_starts` → starting
  - `user_prompt` → thinking
  - `tool_result` (開始/完了) → toolRunning / thinking
  - `tool_decision` → permissionWaiting (pending 時)
  - `sse_event` (response.completed) → トークン集計
  - `api_request` (error) → error
- [ ] `conversation.id` でセッション管理
- [ ] トークン: `sse_event` の input/output/cached/reasoning_token_count をリアルタイム集計

### 2.4 SQLite 永続化
- [ ] sqlite-data + swift-structured-queries セットアップ
- [ ] `@Table` マクロでスキーマ定義:
  - `sessions` (id, agent_type, model, started_at, ended_at, status)
  - `token_usage` (session_id, timestamp, input_tokens, output_tokens, model, estimated_cost)
  - `tool_events` (session_id, timestamp, tool_name, status, duration_ms, metadata)
  - `permission_actions` (session_id, timestamp, action, tool_name, details)
- [ ] マイグレーション基盤
- [ ] セッション終了時にサマリーを保存

### 2.5 テレメトリダッシュボード (フルパネル Analytics タブ)
- [ ] 今日の統計: 合計コスト、セッション数、トークン合計、ツール実行数
- [ ] エージェント別コスト比率 (棒グラフ)
- [ ] 7日間コストトレンド (棒グラフ)
- [ ] `@FetchAll` でリアルタイム更新
- [ ] CSV / JSON エクスポートボタン

### 2.6 価格テーブル
- [ ] `~/.agent-notch/pricing.json` にデフォルト価格を書き出し
- [ ] Anthropic / OpenAI / Google のモデル別価格
- [ ] ユーザーがカスタム価格を追加可能
- [ ] アプリ更新時に新モデルの価格を追加

### 2.7 フルパネル セッション詳細タブ
- [ ] ツール実行履歴リスト (時系列)
  - アイコン + ツール名 + 引数要約 + 時刻 + 実行時間 + 成否
- [ ] Claude: Edit 差分プレビュー (old_string / new_string の diff 表示)
- [ ] Claude: Bash コマンド + 出力プレビュー
- [ ] Codex: ツール実行時間 (duration_ms) 表示
- [ ] トークン内訳セクション

### 2.8 ターミナルジャンプ (基本)
- [ ] Claude Code: hook スクリプトで取得した PID + TTY からターミナルアプリを特定
- [ ] Accessibility API (AXUIElement) でウィンドウにフォーカス
- [ ] 対応ターミナル: Terminal.app, iTerm2, Ghostty, Warp
- [ ] notch 展開モードのセッションカードに「Jump」ボタン

**成果物**: Claude Code + Codex の並列監視。日次コストダッシュボード。ターミナルジャンプ。

### 技術的注意事項

#### Hook の fire-and-forget 制約
現在、HookHandler は全イベントを fire-and-forget で処理している（socket に送信後、応答を待たずに即終了）。
これにより agent の動作をブロックしないが、以下の機能が実現できない:

- **GUI からの権限 approve/deny** — hook の stdout で応答を返せないため、PermissionRequest に介入不可
- **hook による tool のブロック** — PreToolUse で deny/block を返却不可
- **hook レスポンスへの context 注入** — systemMessage, additionalContext 等の注入不可

**対策案 (将来)**:
PermissionRequest のみ recv ありモードに戻し、短いタイムアウト（例: 30秒）を設定。
タイムアウト時はパススルー（agent 側の通常プロンプトにフォールバック）。
PreToolUse/PostToolUse 等の通常イベントは fire-and-forget を維持。

#### Codex CLI の hooks 有効化
Codex CLI は hooks がデフォルト無効。`~/.codex/config.toml` に以下の設定が必要:
```toml
[features]
codex_hooks = true
```
HookInstaller が自動追記するが、既存の config.toml の内容は保持する。

#### Claude 資格情報の読み取りと Keychain 認証ダイアログ（issue #35）

Claude Code は OAuth トークンの Keychain item を `/usr/bin/security add-generic-password`
をサブプロセス起動して作成している。そのため item の ACL が信頼するのは
**`/usr/bin/security` のみ**で、Claude Code 本体も Agent Notch も ACL に含まれない。

| アクセス方法 | 認証ダイアログ |
| --- | --- |
| `SecItemCopyMatching` でデータ取得（`kSecReturnData: true`） | **出る**（ACL 不一致） |
| `SecItemCopyMatching` で属性のみ取得 | 出ない（ACL を参照しない） |
| `/usr/bin/security find-generic-password -w` をサブプロセス起動 | 出ない（ACL が信頼済み） |

「常に許可」を選んでも許可はバイナリの署名で識別されるため、`swift build` ごとに
ad-hoc 署名が変わる開発ビルドでは grant が無効化され、繰り返し聞かれる。

したがって `ClaudeCredentialsStore` は
`~/.claude/.credentials.json` → `/usr/bin/security` サブプロセス
の順で読み、**`SecItemCopyMatching` でのデータ読み出しは行わない**。
新たに Keychain を読むコードを足す場合も同じ方針に従うこと。

**残る限界**: 署名済み .app として配布した場合でも、ACL は Claude Code が作った
ものなので Agent Notch は含まれない。`SecItemCopyMatching` 経路に戻すと
Developer ID 署名があっても初回ダイアログは出る（安定した署名なら「常に許可」が
効き続ける点だけが改善される）。ダイアログを 0 回にできるのは上記の
サブプロセス経路のみ。

---

## Phase 3: Gemini CLI + プラグイン + カスタマイズ

**ゴール**: 3大エージェント対応完了。プラグイン SDK でコミュニティ拡張可能に。テーマ/サウンドのカスタマイズ

### 3.1 Gemini CLI 統合
- [ ] `.gemini/settings.json` にフック登録 (自動インストーラー)
  - 対象: SessionStart, BeforeAgent, BeforeTool, AfterTool, AfterModel, AfterAgent, SessionEnd, Notification, PreCompress
- [ ] stdin/stdout JSON 通信の Adapter 実装
- [ ] イベントマッピング:
  - SessionStart → starting
  - BeforeAgent → thinking
  - BeforeTool → toolRunning
  - AfterTool → thinking
  - AfterModel → トークン集計 (totalTokenCount)
  - AfterAgent → idle
  - SessionEnd → completed
- [ ] トークン表示: total のみ (in/out 分離なし) のフォールバック UI

### 3.2 プラグインシステム
- [ ] Plugin Manifest スキーマ定義 (`manifest.json`)
  ```json
  {
    "name": "my-agent",
    "version": "1.0.0",
    "agent_type": "custom_agent",
    "adapter": "adapter.sh",
    "events": ["session_start", "tool_use", "session_end"],
    "icon": "icon.png"
  }
  ```
- [ ] Adapter Protocol: スクリプトが stdin JSON を受け取り、統一イベントモデルの JSON を stdout に出力
- [ ] `~/.agent-notch/plugins/` ディレクトリ監視
- [ ] プラグインの有効/無効切り替え UI
- [ ] プラグインのインストール/アンインストール

### 3.3 カスタマイズ
- [ ] テーマエンジン
  - ダーク (デフォルト) / ライト / システム追従
  - カスタムカラー: アクセントカラー、背景色、テキスト色
- [ ] サウンドカスタマイズ
  - イベント別にサウンドファイルを指定 (.wav/.mp3/.aiff)
  - `~/.agent-notch/sounds/` にカスタムサウンドを配置
  - サウンドなし選択可能
- [ ] notch 表示設定
  - コンパクトモードの情報密度 (minimal / normal / detailed)
  - 展開モードのデフォルトサイズ
  - 表示するエージェントのフィルター

### 3.4 ターミナルジャンプ (拡張)
- [ ] 追加ターミナル対応: Alacritty, Kitty, WezTerm
- [ ] tmux セッション/ウィンドウ/ペインレベルの特定
- [ ] split pane 対応 (iTerm2, tmux)
- [ ] Codex: プロセスツリー検索によるターミナル特定

### 3.5 設定 UI
- [ ] フルパネルに Settings タブ追加
  - 一般: 自動起動、サウンド ON/OFF、通知設定
  - エージェント: 各エージェントの有効/無効、自動設定
  - テーマ: カラー選択
  - プラグイン: 一覧、有効/無効
  - 価格: モデル別価格の編集
  - アップデート: Sparkle 設定

### 3.6 コスト警告
- [ ] 日次コスト閾値の設定 (デフォルト: $10)
- [ ] 閾値超過時の通知
- [ ] セッション単位のコスト上限設定（オプション）

### 3.7 配布
- [ ] Homebrew Cask 作成
- [ ] GitHub Releases + appcast.xml (Sparkle)
- [ ] README.md + スクリーンショット + GIF
- [ ] Contributing ガイド

**成果物**: 3エージェント対応、プラグイン拡張可能、テーマ/サウンドカスタマイズ、Homebrew 配布

---

## Phase 4: 将来構想（スコープ外だが方向性として）

- Cursor Agent 統合 (ログファイルテーリング)
- Aider / Continue.dev 対応
- チーム利用: コスト集計の共有ダッシュボード
- ウィジェットプラグイン: ポモドーロ、Git 状態、CI ステータス
- Touch Bar 対応（古い MacBook Pro 向け）
- キーボードショートカット

---

## 依存関係グラフ

```
Phase 0.2 (NotchWindow)
    │
    ├── Phase 0.3 (UI シェル)
    │       │
    │       ├── Phase 1.5 (コンパクト UI)
    │       │       │
    │       │       └── Phase 1.6 (展開 UI)
    │       │               │
    │       │               └── Phase 2.7 (フルパネル詳細)
    │       │                       │
    │       │                       └── Phase 2.5 (ダッシュボード)
    │       │
    │       └── Phase 1.7 (権限管理 UI)
    │
    ├── Phase 1.1 (Socket サーバー)
    │       │
    │       └── Phase 1.2 (Hook インストーラー)
    │               │
    │               └── Phase 1.3 (イベントモデル)
    │                       │
    │                       ├── Phase 1.4 (トークン取得)
    │                       │
    │                       ├── Phase 2.3 (Codex パーサー)
    │                       │       │
    │                       │       └── Phase 2.1 (OTLP レシーバー)
    │                       │               │
    │                       │               └── Phase 2.2 (Codex 自動設定)
    │                       │
    │                       └── Phase 3.1 (Gemini 統合)
    │
    ├── Phase 2.4 (SQLite)
    │       │
    │       ├── Phase 2.5 (ダッシュボード)
    │       └── Phase 2.6 (価格テーブル)
    │
    └── Phase 2.8 (ターミナルジャンプ)
            │
            └── Phase 3.4 (ジャンプ拡張)

Phase 3.2 (プラグイン) ── 独立して開発可能
Phase 3.3 (カスタマイズ) ── 独立して開発可能
```

---

## マイルストーン判定基準

| Phase | 完了条件 |
|-------|---------|
| **0** | notch に空パネルが表示され、3段階の展開アニメーションが動作 |
| **1** | Claude Code セッションの状態・ツール・トークンが notch に表示され、権限 Approve/Deny が GUI から動作 |
| **2** | Codex セッションが並列表示され、日次コストダッシュボードが動作。ターミナルジャンプ可能 |
| **3** | Gemini 対応、プラグイン SDK 公開、Homebrew Cask でインストール可能 |
