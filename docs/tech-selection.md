# Agent Notch — 技術選定書

## 1. 開発言語 & UI フレームワーク

### **Swift + SwiftUI（メイン）+ AppKit（ウィンドウ層）**

| 層             | 技術                   | 理由                                                                                                 |
| -------------- | ---------------------- | ---------------------------------------------------------------------------------------------------- |
| ウィンドウ管理 | **AppKit (NSPanel)**   | notch オーバーレイに必須。`NSPanel` のサブクラスで borderless + transparent + `level: .mainMenu + 3` |
| UI レイアウト  | **SwiftUI**            | 宣言的 UI、アニメーション、状態管理。`NSHostingView` で NSPanel に埋め込む                           |
| ブリッジ       | **SwiftUI-Introspect** | SwiftUI から AppKit 内部にアクセスが必要な場合のエスケープハッチ                                     |

**判断根拠**: Claude Island / TheBoringNotch 両方がこの構成。macOS notch アプリのデファクト。

---

## 2. Notch ウィンドウの実装方式

macOS には notch API は存在しない。**透明 NSPanel を notch 上に被せる**手法を採用。

```swift
// 核心パターン（Claude Island / boring.notch 共通）
class NotchPanel: NSPanel {
    level = .mainMenu + 3           // メニューバーより上
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    isMovable = false
    ignoresMouseEvents = true       // クリック透過
    collectionBehavior = [
        .canJoinAllSpaces,          // 全 Space に表示
        .stationary,                // Space 切替で移動しない
        .fullScreenAuxiliary,
        .ignoresCycle               // Cmd+Tab に出ない
    ]
}
```

### Notch ジオメトリ検出

```swift
// macOS 12+ API で notch サイズを計算
let notchHeight = screen.safeAreaInsets.top
let notchWidth = screen.frame.width
    - screen.auxiliaryTopLeftArea!.width
    - screen.auxiliaryTopRightArea!.width + 4
```

### マウスイベント戦略

| 手法                                                     | 採用                            |
| -------------------------------------------------------- | ------------------------------- |
| `ignoresMouseEvents = true`                              | デフォルトでクリック透過        |
| `NSEvent.addGlobalMonitorForEvents`                      | ホバー/クリックをグローバル監視 |
| notch 領域ヒットテストで `ignoresMouseEvents` を動的切替 | 展開時のみインタラクティブに    |

---

## 3. パッケージマネージャー

### **Swift Package Manager (SPM)**

- 2026年時点の標準。Xcode にネイティブ統合
- CocoaPods はメンテナンスモード、Carthage は停滞
- 全依存ライブラリが SPM 対応済み

---

## 4. 依存ライブラリ

### コア依存

| ライブラリ         | バージョン | 用途                                  | 選定理由                                                                                      |
| ------------------ | ---------- | ------------------------------------- | --------------------------------------------------------------------------------------------- |
| **Network.framework** | OS 標準 | Unix socket サーバー | AeroSpace 方式。`NWListener` + `.unix(path:)` で依存ゼロ。Swift Concurrency と自然に統合 |
| **Hummingbird**    | 2.x        | 軽量 HTTP サーバー                    | OTLP/HTTP receiver (port 4318)。Codex 統合用                                                  |
| **swift-protobuf** | 1.x        | Protobuf デコード                     | OTLP メッセージのデシリアライズ。`.proto` から Swift コードを生成                             |
| **sqlite-data** (pointfreeco) | 1.x | SQLite ストレージ + SwiftUI 統合 | `@Table` マクロで型安全スキーマ、`@FetchAll` で DB→SwiftUI 自動反映。内部は GRDB            |
| **swift-structured-queries** (pointfreeco) | 0.x | 型安全 SQL クエリビルダー | sqlite-data の依存。集約クエリ (SUM, GROUP BY) も型安全に記述可能                            |
| **MarkdownUI**     | 2.x        | Markdown レンダリング                 | GFM 完全対応（コードブロック、テーブル、タスクリスト）。チャット履歴・差分プレビューに必要    |
| **Sparkle**        | 2.x        | 自動アップデート                      | macOS アプリのデファクト。GitHub Releases をサーバーに利用可能。OSS に最適                    |

### ユーティリティ依存

| ライブラリ                              | 用途                  | 選定理由                                    |
| --------------------------------------- | --------------------- | ------------------------------------------- |
| **Defaults** (sindresorhus)             | UserDefaults ラッパー | タイプセーフな設定管理。boring.notch で実績 |
| **LaunchAtLogin-Modern** (sindresorhus) | ログイン時自動起動    | SMAppService のラッパー。1行で実装完了      |

### 不採用とした候補

| ライブラリ                       | 不採用理由                                                                  |
| -------------------------------- | --------------------------------------------------------------------------- |
| Core Data / SwiftData            | 分析クエリ（集計、GROUP BY）に不向き。sqlite-data (GRDB) のほうが柔軟      |
| GRDB.swift 単体                  | sqlite-data が GRDB を内包しつつ SwiftUI 統合を提供。直接使う理由がない     |
| SwiftNIO                         | AeroSpace 方式の Network.framework で十分。依存を増やす理由がない           |
| swift-otel / opentelemetry-swift | OTLP **exporter**（送信側）であり receiver ではない。受信には自前実装が必要 |
| Lottie                           | アニメーション用途だが、SwiftUI 標準で十分。不要な依存を避ける              |
| Pow                              | 同上。SwiftUI spring アニメーションで要件カバー可能                         |
| KeyboardShortcuts                | MVP では不要。Phase 2 以降で検討                                            |

---

## 5. 通信アーキテクチャ

### 5.1 Claude Code 統合 — Hooks + Unix Socket

```
Claude Code CLI
    │
    ├── PreToolUse hook ──→ Unix Socket ──→ Agent Notch
    ├── PostToolUse hook ──→ Unix Socket ──→ Agent Notch
    ├── Notification hook ──→ Unix Socket ──→ Agent Notch
    └── ... (17 lifecycle events)
```

- `~/.claude/hooks/` にシェルスクリプトをインストール（初回起動時に自動）
- スクリプトが stdin の JSON を Unix socket に転送
- **AeroSpace 方式**: Network.framework (`NWListener` / `NWConnection`) で socket サーバーを実装
- プロトコル: **4バイト UInt32 長さプレフィックス + JSON ペイロード**（AeroSpace と同じ）
- イベントストリーミング: subscribe パターンで長期接続、サーバーからプッシュ

### 5.2 Codex CLI 統合 — OTLP/HTTP

```
Codex CLI
    │
    └── OTLP/HTTP POST ──→ localhost:4318 ──→ Agent Notch
                              /v1/logs
                              /v1/metrics
                              /v1/traces
```

- `~/.codex/config.toml` に `[otel]` セクションを設定（初回起動時に自動）
- Hummingbird で HTTP サーバーを起動
- swift-protobuf で OTLP メッセージをデコード

### 5.3 Gemini CLI 統合 — Hooks (stdin/stdout JSON)

```
Gemini CLI
    │
    └── Hook (stdin JSON) ──→ Agent Notch adapter ──→ stdout JSON response
```

- `.gemini/settings.json` にフック登録
- stdin/stdout JSON 通信（同期）

### 5.4 統一イベントモデル

全エージェントからのイベントを **Unified Event Bus** で正規化:

```swift
enum AgentEvent {
    case sessionStarted(AgentType, SessionInfo)
    case toolUseStarted(AgentType, ToolInfo)
    case toolUseCompleted(AgentType, ToolResult)
    case permissionRequested(AgentType, PermissionRequest)
    case tokenUsage(AgentType, TokenInfo)
    case sessionCompleted(AgentType, SessionSummary)
    case error(AgentType, ErrorInfo)
}
```

---

## 6. データ永続化

### SQLite (GRDB) スキーマ概要

```sql
-- セッション
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    agent_type TEXT NOT NULL,
    started_at DATETIME NOT NULL,
    ended_at DATETIME,
    status TEXT NOT NULL
);

-- トークン消費
CREATE TABLE token_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT REFERENCES sessions(id),
    timestamp DATETIME NOT NULL,
    input_tokens INTEGER NOT NULL,
    output_tokens INTEGER NOT NULL,
    model TEXT,
    estimated_cost REAL
);

-- ツール実行ログ
CREATE TABLE tool_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT REFERENCES sessions(id),
    timestamp DATETIME NOT NULL,
    tool_name TEXT NOT NULL,
    status TEXT NOT NULL,  -- started, completed, failed, denied
    duration_ms INTEGER,
    metadata TEXT  -- JSON
);

-- 権限アクション
CREATE TABLE permission_actions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT REFERENCES sessions(id),
    timestamp DATETIME NOT NULL,
    action TEXT NOT NULL,  -- approved, denied
    tool_name TEXT NOT NULL,
    details TEXT  -- JSON
);
```

---

## 7. アニメーション戦略

### SwiftUI 標準で実装

| 演出                  | 実装方式                                                                                                |
| --------------------- | ------------------------------------------------------------------------------------------------------- |
| notch 展開/折りたたみ | `NotchShape` の `animatableData` でコーナー半径を補間 + `.spring(response: 0.42, dampingFraction: 0.8)` |
| 状態インジケーター    | `scaleEffect` + `opacity` のループアニメーション                                                        |
| 権限リクエストパルス  | `.repeatForever(autoreverses: true)` で脈動                                                             |
| タスク完了フラッシュ  | `Color.overlay` の opacity を 0→1→0 で遷移                                                              |
| セッション切替        | `matchedGeometryEffect` で共有エレメント遷移                                                            |

### カスタム Shape

```swift
struct NotchShape: Shape {
    var topCornerRadius: CGFloat    // 閉: 6, 開: 19
    var bottomCornerRadius: CGFloat // 閉: 14, 開: 24

    var animatableData: AnimatablePair<CGFloat, CGFloat> { ... }

    func path(in rect: CGRect) -> Path {
        // quadratic curve で notch の丸角を描画
    }
}
```

---

## 8. ターミナルジャンプ

### Accessibility API (AXUIElement)

```swift
// 1. ウィンドウ一覧取得
let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)

// 2. PID からアプリの AX 要素を取得
let appElement = AXUIElementCreateApplication(pid)

// 3. ウィンドウにフォーカス
AXUIElementSetAttributeValue(window, kAXMainAttribute, true)
NSRunningApplication(processIdentifier: pid)?.activate()
```

- **必須**: アクセシビリティ権限（`AXIsProcessTrustedWithOptions`）
- **サンドボックス無効**: App Store 外配布のため問題なし
- 外部ライブラリ不要 — API がシンプルなため自前ラッパーで十分

---

## 9. ビルド & 配布

| 項目             | 選定                                              |
| ---------------- | ------------------------------------------------- |
| ビルドシステム   | Xcode + SPM                                       |
| CI/CD            | GitHub Actions                                    |
| コード署名       | Developer ID (Notarization)                       |
| 配布             | GitHub Releases + Homebrew Cask                   |
| 自動アップデート | Sparkle 2 (appcast.xml on GitHub Pages)           |
| 最小 macOS       | **14.0 (Sonoma)**                                 |
| アーキテクチャ   | Universal Binary (Apple Silicon + Intel)          |
| サンドボックス   | **無効** (Accessibility API / Unix socket に必要) |

---

## 10. 技術スタック全体図

```
┌─────────────────────────────────────────────────────┐
│                    Agent Notch                       │
├─────────────────────────────────────────────────────┤
│                                                      │
│  ┌─────────────────────────────────────────────┐    │
│  │           UI Layer (SwiftUI)                 │    │
│  │  NotchShape / Animations / MarkdownUI       │    │
│  └──────────────────┬──────────────────────────┘    │
│                     │ NSHostingView                  │
│  ┌──────────────────┴──────────────────────────┐    │
│  │        Window Layer (AppKit)                 │    │
│  │  NotchPanel (NSPanel) / EventMonitor        │    │
│  └──────────────────┬──────────────────────────┘    │
│                     │                                │
│  ┌──────────────────┴──────────────────────────┐    │
│  │         Unified Event Bus                    │    │
│  │  AgentEvent enum / Combine publishers       │    │
│  └───┬──────────┬──────────┬───────────────────┘    │
│      │          │          │                         │
│  ┌───┴───┐ ┌───┴───┐ ┌───┴─────┐                   │
│  │Claude │ │Codex  │ │Plugin   │                    │
│  │Adapter│ │Adapter│ │Adapter  │                    │
│  └───┬───┘ └───┬───┘ └───┬─────┘                   │
│      │         │         │                           │
│  Network.fw Hummingbird  Protocol                   │
│  Unix Sock   OTLP/HTTP   (extensible)               │
│                                                      │
│  ┌─────────────────────────────────────────────┐    │
│  │    Persistence (sqlite-data / GRDB)          │    │
│  │  sessions / token_usage / tool_events        │    │
│  └─────────────────────────────────────────────┘    │
│                                                      │
│  ┌──────────────┐  ┌───────────────┐                │
│  │ Accessibility│  │ Sparkle 2     │                │
│  │ (AXUIElement)│  │ (Auto-update) │                │
│  └──────────────┘  └───────────────┘                │
│                                                      │
├─────────────────────────────────────────────────────┤
│  macOS 14+ │ Swift 5.9+ │ SPM │ Universal Binary   │
└─────────────────────────────────────────────────────┘
```
