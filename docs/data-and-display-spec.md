# Agent Notch — データ取得仕様 & 表示要件

## 1. エージェント別データ可用性マトリクス

各エージェントから**実際に取得できるデータ**の一覧。

### 凡例

- ✅ イベントで直接取得可能
- 📄 トランスクリプト/ログファイルのパースで取得可能
- ⚡ メトリクスで取得可能（Codex のみ）
- ❌ 取得不可

| データ | Claude Code (Hooks) | Codex (OTLP) | Gemini CLI (Hooks) |
|--------|:---:|:---:|:---:|
| **セッション管理** | | | |
| セッション ID | ✅ 全イベント共通 | ✅ `conversation.id` | ✅ 全イベント共通 |
| セッション開始/終了 | ✅ SessionStart/End | ✅ `conversation_starts` | ✅ SessionStart/End |
| 開始理由 (startup/resume/clear) | ✅ `source` | ❌ | ✅ `source` |
| 終了理由 | ✅ SessionEnd matcher | ❌ | ✅ `reason` |
| **モデル情報** | | | |
| モデル名 | ✅ SessionStart `model` | ✅ 全イベント `model` | ✅ BeforeModel `llm_request.model` |
| パーミッションモード | ✅ 全イベント `permission_mode` | ✅ `approval_policy` | ❌ |
| **ツール実行** | | | |
| ツール名 | ✅ PreToolUse `tool_name` | ✅ `tool_result.tool_name` | ✅ BeforeTool `tool_name` |
| ツール引数 | ✅ PreToolUse `tool_input` | ✅ Log: `arguments` 全文 | ✅ BeforeTool `tool_input` |
| ツール結果 | ✅ PostToolUse `tool_response` | ✅ Log: `output` 全文 | ✅ AfterTool `tool_response` |
| ツール実行時間 | ❌ (Pre/Post 差分で計算可) | ✅ `tool_result.duration_ms` | ❌ (Before/After 差分で計算可) |
| ツール成功/失敗 | ✅ PostToolUse / PostToolUseFailure | ✅ `tool_result.success` | ✅ AfterTool `tool_response.error` |
| ツールエラー内容 | ✅ PostToolUseFailure `error` | ✅ Log: `output` | ✅ AfterTool `tool_response.error` |
| **ツール詳細 (Claude 固有)** | | | |
| Bash コマンド | ✅ `tool_input.command` | ✅ `arguments` | ✅ `tool_input` |
| ファイルパス (Read/Write/Edit) | ✅ `tool_input.file_path` | ✅ `arguments` | ✅ `tool_input` |
| Edit 差分 (old/new) | ✅ `tool_input.old_string/new_string` | ❌ | ❌ |
| 検索パターン (Grep/Glob) | ✅ `tool_input.pattern` | ❌ | ❌ |
| **権限管理** | | | |
| 権限リクエスト | ✅ PermissionRequest | ✅ `tool_decision` (Log のみ) | ✅ Notification (ToolPermission) |
| 権限承認/拒否 | ✅ PermissionRequest 応答 | ✅ `tool_decision.decision` | ❌ (観測のみ、応答不可) |
| GUI から承認/拒否 操作 | ✅ hook stdout で応答可能 | ❌ | ❌ |
| 権限提案 (suggested rules) | ✅ `permission_suggestions` | ❌ | ❌ |
| **トークン & コスト** | | | |
| input トークン | 📄 transcript JSONL | ✅ `sse_event.input_token_count` | ✅ AfterModel `usageMetadata.totalTokenCount` |
| output トークン | 📄 transcript JSONL | ✅ `sse_event.output_token_count` | ❌ (total のみ) |
| cached トークン | 📄 transcript JSONL | ✅ `sse_event.cached_token_count` | ❌ |
| reasoning トークン | 📄 transcript JSONL | ✅ `sse_event.reasoning_token_count` | ❌ |
| API コスト推計 | ❌ (モデル名 + トークン数から計算) | ❌ (同左) | ❌ (同左) |
| **API パフォーマンス** | | | |
| API リクエスト時間 | ❌ | ✅ `api_request.duration_ms` | ❌ |
| TTFT (最初のトークンまでの時間) | ❌ | ⚡ `turn.ttft.duration_ms` | ❌ |
| ターン E2E 時間 | ❌ | ⚡ `turn.e2e_duration_ms` | ❌ |
| **ユーザー入力** | | | |
| ユーザープロンプト | ✅ UserPromptSubmit `prompt` | ✅ `user_prompt.prompt` (設定次第) | ✅ BeforeAgent `prompt` |
| **エージェント応答** | | | |
| 最終応答テキスト | ❌ (📄 transcript) | ❌ | ✅ AfterAgent `prompt_response` |
| **サブエージェント** | | | |
| サブエージェント開始/終了 | ✅ SubagentStart/Stop | ❌ | ❌ |
| サブエージェント種別 | ✅ `agent_type` | ❌ | ❌ |
| サブエージェント最終応答 | ✅ SubagentStop `last_assistant_message` | ❌ | ❌ |
| **通知** | | | |
| 通知メッセージ | ✅ Notification `message` | ❌ | ✅ Notification `message` |
| 通知種別 | ✅ `notification_type` | ❌ | ✅ `notification_type` |
| **タスク管理** | | | |
| タスク作成/完了 | ✅ TaskCreated/Completed | ❌ | ❌ |
| タスク名/説明 | ✅ `task_subject/description` | ❌ | ❌ |
| **コンテキスト圧縮** | | | |
| 圧縮開始 | ✅ PreCompact | ❌ | ✅ PreCompress |
| 圧縮トリガー (auto/manual) | ✅ matcher | ❌ | ✅ `trigger` |
| **プロセス情報** | | | |
| PID / TTY | ✅ hook スクリプトで取得 | ❌ | ✅ hook スクリプトで取得 |
| トランスクリプトパス | ✅ `transcript_path` | ❌ | ✅ `transcript_path` |
| 作業ディレクトリ | ✅ `cwd` | ❌ | ✅ `cwd` |
| **エラー** | | | |
| API エラー種別 | ✅ StopFailure matcher | ✅ `api_request.error.message` | ❌ |
| レートリミット | ✅ StopFailure `rate_limit` | ✅ HTTP 429 | ❌ |

---

## 2. Claude Code トークン取得の補足

Claude Code の hooks API は **トークン数をイベントで直接提供しない**。取得方法:

### 方法 A: transcript JSONL パース（推奨）
- `transcript_path` が全イベントで提供される
- JSONL ファイルに `usage` フィールドが含まれる:
  ```json
  {"type": "assistant", "usage": {"input_tokens": 1234, "output_tokens": 567, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 890}}
  ```
- `Stop` / `PostToolUse` イベント受信時に最終行を読んで集計

### 方法 B: ファイルウォッチャー
- `transcript_path` を FSEvents で監視
- 新しい行が追加されるたびに usage を抽出

**推奨**: 方法 A（Stop イベントごとに末尾を読む）。リアルタイム性と負荷のバランスが良い。

---

## 3. Codex OTLP 受信の注意点

### シグナル別の推奨受信設定

| シグナル | 受信すべきか | 理由 |
|---------|:---:|------|
| **Logs** | ✅ 必須 | ツール名、引数、結果、トークン数、プロンプト等すべてのリッチデータを含む |
| **Metrics** | ✅ 推奨 | ツール実行時間、TTFT、E2E 時間等のパフォーマンスデータ |
| **Traces** | △ オプション | PII 除外版の軽量データ。Logs で十分な場合は不要 |

### 受信エンドポイント

```
POST /v1/logs    → LogRecord[] をデコード
POST /v1/metrics → MetricData[] をデコード
POST /v1/traces  → Span[] をデコード（オプション）
```

protobuf (`binary`) と JSON の両方を受け入れる必要あり。

---

## 4. 統一イベントモデル（Unified Event Model）

3つのエージェントからのデータを正規化する内部モデル:

```swift
// エージェント種別
enum AgentType: String, Codable {
    case claudeCode, codex, geminiCLI, custom
}

// 統一セッション状態
enum SessionStatus: String, Codable {
    case starting      // セッション初期化中
    case idle          // ユーザー入力待ち
    case thinking      // モデル推論中
    case toolRunning   // ツール実行中
    case permissionWaiting  // 権限承認待ち
    case compacting    // コンテキスト圧縮中
    case error         // エラー発生
    case completed     // セッション終了
}

// 統一セッション情報
struct UnifiedSession {
    let id: String
    let agentType: AgentType
    let model: String?
    let cwd: String?
    var status: SessionStatus
    var startedAt: Date
    var endedAt: Date?

    // トークン累計
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var totalCachedTokens: Int
    var estimatedCost: Double

    // ツール統計
    var toolCallCount: Int
    var currentTool: ToolInfo?
    var recentTools: [ToolInfo]  // 直近 N 件

    // 権限キュー
    var pendingPermissions: [PermissionRequest]

    // プロセス情報
    var pid: Int?
    var tty: String?
    var transcriptPath: String?
}

// ツール情報
struct ToolInfo {
    let name: String
    let summary: String      // 引数の要約 (例: "Edit main.swift", "Bash: npm test")
    let startedAt: Date
    var completedAt: Date?
    var status: ToolStatus   // running, succeeded, failed, denied
    var durationMs: Int?
}

// 権限リクエスト
struct PermissionRequest {
    let id: String
    let agentType: AgentType
    let sessionId: String
    let toolName: String
    let toolInput: [String: Any]
    let timestamp: Date
    var canRespond: Bool     // Claude: true, Codex/Gemini: false
}
```

### イベントマッピング

| 統一状態 | Claude Code イベント | Codex OTLP イベント | Gemini CLI イベント |
|---------|---------------------|--------------------|--------------------|
| `starting` | SessionStart | `conversation_starts` | SessionStart |
| `idle` | Stop, Notification(idle_prompt) | (sse_event 完了後の無活動) | AfterAgent |
| `thinking` | UserPromptSubmit | `user_prompt` | BeforeAgent / BeforeModel |
| `toolRunning` | PreToolUse | `tool_result` (開始推定) | BeforeTool |
| `permissionWaiting` | PermissionRequest | `tool_decision` (pending) | Notification(ToolPermission) |
| `compacting` | PreCompact | ❌ | PreCompress |
| `error` | StopFailure, PostToolUseFailure | `api_request` (error) | ❌ |
| `completed` | SessionEnd | (接続切断) | SessionEnd |

---

## 5. 表示要件 — 3段階 UI

### 5.1 コンパクトモード（常時表示 — notch 両サイド）

**表示幅**: notch 左右それぞれ約 100-150px

**表示する情報** (データ可用性: 全エージェント ✅):

```
┌──────────────────────────────────────────────────┐
│  [🟢 C] main.swift  ◼◼◼  [🔵 X] npm test       │
│          ↑                          ↑            │
│     Claude Code                 Codex            │
│     (toolRunning)               (toolRunning)    │
└──────────────────────────────────────────────────┘
```

| 要素 | データソース | 全エージェント対応 |
|------|------------|:-:|
| エージェントアイコン + 色 | アプリ内定義 | ✅ |
| 状態インジケーター (色/アニメーション) | 統一 SessionStatus | ✅ |
| 現在のツール名 or アクティビティ要約 | ToolInfo.summary | ✅ |

**状態別のインジケーター演出**:

| 状態 | 色 | アニメーション | サウンド |
|------|-----|-------------|---------|
| `idle` | グレー | なし (静止) | — |
| `thinking` | 黄/オレンジ パルス | ゆっくり脈動 | — |
| `toolRunning` | 緑 | 左右にスライド | — |
| `permissionWaiting` | 赤/マゼンタ | 速い脈動 | アラートサウンド |
| `compacting` | 紫 | 回転 | — |
| `error` | 赤 | フラッシュ | エラーサウンド |
| `completed` | 青 → フェードアウト | 一瞬フラッシュ | 完了サウンド |

**ツール要約の生成ルール**:

| ツール | 要約形式 | 例 |
|--------|---------|-----|
| Bash | コマンドの先頭 30 文字 | `npm test` |
| Edit | ファイル名 | `main.swift` |
| Write | ファイル名 | `config.json` |
| Read | ファイル名 | `README.md` |
| Grep | パターン | `"TODO"` |
| Glob | パターン | `**/*.ts` |
| WebSearch | クエリの先頭 20 文字 | `"React hooks..."` |
| WebFetch | ドメイン名 | `github.com` |
| Agent (subagent) | エージェントタイプ | `Explore` |
| MCP ツール | サーバー名:ツール名 | `git:status` |

---

### 5.2 展開モード（クリックで展開）

**表示サイズ**: 約 400-500px 幅、300-400px 高さ

```
┌─────────────────────────────────────────────┐
│              Agent Notch                     │
├─────────────────────────────────────────────┤
│                                              │
│  ● Claude Code        opus-4   ⏱ 3m 24s    │
│    ✎ Edit main.swift                        │
│    ↳ 12.4k in / 3.2k out  ~$0.24           │
│    ⚡ 8 tools   📁 ~/project                │
│                                              │
│  ● Codex              o3       ⏱ 1m 05s    │
│    ⚙ Bash: npm test                         │
│    ↳ 5.1k in / 1.8k out  ~$0.09            │
│    ⚡ 3 tools   📁 ~/project                │
│                                              │
│  ⚠ 1 permission waiting         [View]      │
│                                              │
└─────────────────────────────────────────────┘
```

| 表示項目 | データソース | Claude | Codex | Gemini |
|---------|------------|:---:|:---:|:---:|
| エージェント名 + 状態 | UnifiedSession | ✅ | ✅ | ✅ |
| モデル名 | SessionStart / `model` | ✅ | ✅ | ✅ |
| 経過時間 | startedAt からの差分 | ✅ | ✅ | ✅ |
| 現在のツール + 要約 | ToolInfo | ✅ | ✅ | ✅ |
| トークン (in/out) | transcript / OTLP / AfterModel | ✅📄 | ✅ | ✅(totalのみ) |
| コスト推計 | モデル × トークンで計算 | ✅ | ✅ | ✅ |
| ツール実行回数 | toolCallCount | ✅ | ✅ | ✅ |
| 作業ディレクトリ | cwd | ✅ | ❌ | ✅ |
| 権限待ちバッジ | pendingPermissions | ✅ | △ | ✅(観測のみ) |

**Gemini のトークン表示に関する注意**:
- `totalTokenCount` のみ提供（in/out 分離なし）
- 表示: `↳ 15.6k total ~$0.05` の形式にフォールバック

**Codex の cwd に関する注意**:
- OTLP イベントに cwd フィールドなし
- 表示: `📁` を省略、または `~/.codex/config.toml` のプロジェクト設定から推定

---

### 5.3 フルパネルモード（さらにクリックで展開）

**表示サイズ**: 約 600-700px 幅、500-600px 高さ

#### タブ A: セッション詳細

```
┌─────────────────────────────────────────────────┐
│  [Sessions] [Permissions] [Analytics]            │
├─────────────────────────────────────────────────┤
│                                                  │
│  Claude Code Session #a1b2c3                     │
│  Model: claude-opus-4-6  Mode: auto              │
│  Started: 14:32  Duration: 3m 24s                │
│  CWD: ~/workspace/projects/agent-notch           │
│                                                  │
│  ── Recent Activity ──                           │
│  14:35:22  ✎ Edit src/App.swift                 │
│            old: "let x = 1" → new: "let x = 2" │
│  14:35:18  📖 Read src/App.swift (1-50)          │
│  14:35:15  🔍 Grep "TODO" **/*.swift             │
│  14:35:10  ⚙ Bash: swift build (3.2s)           │
│  14:35:02  📖 Read Package.swift                 │
│                                                  │
│  ── Token Usage ──                               │
│  Input: 12,432  Output: 3,218  Cached: 8,901    │
│  Estimated Cost: $0.24                           │
│                                                  │
└─────────────────────────────────────────────────┘
```

| 表示項目 | Claude | Codex | Gemini |
|---------|:---:|:---:|:---:|
| セッション ID | ✅ | ✅ | ✅ |
| モデル名 | ✅ | ✅ | ✅ |
| パーミッションモード | ✅ | ✅ | ❌ |
| 開始時刻/経過時間 | ✅ | ✅ | ✅ |
| 作業ディレクトリ | ✅ | ❌ | ✅ |
| ツール実行履歴 (名前+引数+時刻+結果) | ✅ | ✅ | ✅ |
| Edit 差分プレビュー | ✅ | ❌ | ❌ |
| Bash コマンド + 実行時間 | ✅ (時間は計算) | ✅ (duration_ms) | ✅ (時間は計算) |
| トークン内訳 (in/out/cached) | ✅📄 | ✅ | △(total のみ) |
| コスト推計 | ✅ | ✅ | ✅ |
| サブエージェント一覧 | ✅ | ❌ | ❌ |
| タスク一覧 | ✅ | ❌ | ❌ |

#### タブ B: 権限管理

```
┌─────────────────────────────────────────────────┐
│  [Sessions] [Permissions] [Analytics]            │
├─────────────────────────────────────────────────┤
│                                                  │
│  ⚠ Pending (1)                                  │
│  ┌───────────────────────────────────────────┐  │
│  │ Claude Code wants to run:                  │  │
│  │ Bash: rm -rf node_modules && npm install  │  │
│  │                                            │  │
│  │ [Approve]  [Deny]  [Approve for session]  │  │
│  └───────────────────────────────────────────┘  │
│                                                  │
│  ── History ──                                   │
│  14:35:20  ✅ Approved  Edit src/App.swift      │
│  14:35:15  ✅ Approved  Bash: swift build       │
│  14:34:50  ❌ Denied    Bash: sudo rm -rf /     │
│                                                  │
└─────────────────────────────────────────────────┘
```

| 機能 | Claude | Codex | Gemini |
|------|:---:|:---:|:---:|
| 権限リクエスト表示 | ✅ | ✅(観測のみ) | ✅(観測のみ) |
| GUI から Approve/Deny | ✅ | ❌ | ❌ |
| ツール入力プレビュー | ✅ (全 tool_input) | ✅ (Log: arguments) | ✅ (tool_input) |
| 権限提案 (suggested rules) | ✅ | ❌ | ❌ |
| 承認履歴 | ✅ | ✅ | ❌ |

**重要**: GUI からの Approve/Deny は **Claude Code のみ**対応。
- Claude Code: PermissionRequest の hook stdout で `decision.behavior: "allow"/"deny"` を返却
- Codex: `tool_decision` は観測イベント。CLI 側で承認が必要
- Gemini: Notification は観測のみ、応答不可

→ Codex / Gemini では「ターミナルにジャンプして承認」ボタンを表示

#### タブ C: テレメトリダッシュボード

```
┌─────────────────────────────────────────────────┐
│  [Sessions] [Permissions] [Analytics]            │
├─────────────────────────────────────────────────┤
│                                                  │
│  ── Today ──                                     │
│  Total Cost: $4.52    Sessions: 12               │
│  Tokens: 234k in / 45k out                       │
│  Tool Calls: 187     Avg Duration: 8m 12s        │
│                                                  │
│  ── Cost by Agent ──                             │
│  Claude Code  ████████████████  $3.80 (84%)     │
│  Codex        ████              $0.62 (14%)     │
│  Gemini CLI   █                 $0.10 (2%)      │
│                                                  │
│  ── Cost Trend (7 days) ──                       │
│  Mon ████████  $6.20                             │
│  Tue ██████    $4.80                             │
│  Wed ████      $3.10                             │
│  Thu ██████    $4.52                             │
│                                                  │
│  [Export CSV]  [Export JSON]                      │
│                                                  │
└─────────────────────────────────────────────────┘
```

| メトリクス | Claude | Codex | Gemini |
|-----------|:---:|:---:|:---:|
| セッション数 | ✅ | ✅ | ✅ |
| 合計トークン | ✅📄 | ✅ | ✅(total) |
| 合計コスト | ✅(計算) | ✅(計算) | ✅(計算) |
| ツール実行回数 | ✅ | ✅ | ✅ |
| 平均セッション時間 | ✅ | ✅ | ✅ |
| エージェント別集計 | ✅ | ✅ | ✅ |
| 日次トレンド | ✅(SQLite) | ✅(SQLite) | ✅(SQLite) |
| API レイテンシ | ❌ | ✅ | ❌ |
| TTFT | ❌ | ✅ | ❌ |

---

## 6. コスト計算モデル

全エージェントとも API コストは直接提供されない。モデル名 + トークン数から計算する。

### 価格テーブル (アプリ内に埋め込み、定期更新)

```swift
struct ModelPricing {
    let inputPerMillion: Double   // $/1M input tokens
    let outputPerMillion: Double  // $/1M output tokens
    let cachedPerMillion: Double? // $/1M cached tokens (optional)
}

let pricingTable: [String: ModelPricing] = [
    // Anthropic
    "claude-opus-4-6":   ModelPricing(input: 15.0, output: 75.0, cached: 1.5),
    "claude-sonnet-4-6": ModelPricing(input: 3.0,  output: 15.0, cached: 0.3),
    "claude-haiku-4-5":  ModelPricing(input: 0.8,  output: 4.0,  cached: 0.08),
    // OpenAI
    "o3":                ModelPricing(input: 10.0, output: 40.0, cached: 2.5),
    "o4-mini":           ModelPricing(input: 1.1,  output: 4.4,  cached: 0.275),
    "gpt-4.1":           ModelPricing(input: 2.0,  output: 8.0,  cached: 0.5),
    // Google
    "gemini-2.5-pro":    ModelPricing(input: 1.25, output: 10.0, cached: 0.315),
    "gemini-2.5-flash":  ModelPricing(input: 0.15, output: 0.6,  cached: 0.0375),
]
```

- 価格テーブルは JSON ファイルとして `~/.agent-notch/pricing.json` に保存
- GitHub Releases の appcast と一緒に定期更新
- ユーザーがカスタム価格を追加可能（社内モデル対応）

---

## 7. 通知トリガー条件

| 通知 | トリガー | データソース |
|------|---------|------------|
| タスク完了 | SessionStatus → `completed` | SessionEnd / Stop |
| 権限待ち | SessionStatus → `permissionWaiting` | PermissionRequest / tool_decision / Notification |
| エラー | SessionStatus → `error` | StopFailure / api_request error |
| 長時間アイドル | `idle` 状態が N 分継続 | タイマー |
| コスト警告 | 日次コストが閾値超過 | SQLite 集計 |
| レートリミット | StopFailure `rate_limit` / HTTP 429 | StopFailure / api_request |

---

## 8. エージェント別の機能制限まとめ

| 機能 | Claude Code | Codex | Gemini CLI |
|------|:-----------:|:-----:|:----------:|
| **状態監視** | ◎ 全状態 | ○ 主要状態 | ○ 主要状態 |
| **ツール詳細** | ◎ 全引数+結果 | ○ Log 経由で全データ | ○ 全引数+結果 |
| **GUI 権限操作** | ◎ Approve/Deny | ✗ 観測のみ | ✗ 観測のみ |
| **トークン (in/out)** | ○ transcript パース | ◎ リアルタイム | △ total のみ |
| **API パフォーマンス** | ✗ | ◎ 詳細メトリクス | ✗ |
| **サブエージェント** | ◎ | ✗ | ✗ |
| **タスク管理** | ◎ | ✗ | ✗ |
| **ターミナルジャンプ** | ◎ PID+TTY | △ プロセス検索 | ◎ PID+TTY |
