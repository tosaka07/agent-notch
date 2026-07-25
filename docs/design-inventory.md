# Agent Notch — 現状の機能一覧とデザインコンセプト

デザインリファクタの出発点として、**いま実装されているもの**と**いま採っているデザイン方針**を棚卸ししたドキュメント。
「何を作り直すか」を決める前に「何があるか / なぜそうなっているか」を共有するのが目的。

最終更新: 2026-07-25（issue #4 / #13 / #28 / #35 / #36 対応後）

---

## 1. プロダクトの前提

Mac の notch を AI コーディングエージェント（Claude Code / Codex）の統合コマンドセンターにする常駐アプリ。

デザイン上の制約は notch そのものから来る:

| 制約 | 影響 |
| --- | --- |
| 常時画面に出ている | 情報過多・派手なアニメーションは疲れる。バッテリーにも響く |
| 非アクティブ状態で見られる | 文字が小さいと読めない。色が消えても状態が分かる必要がある |
| 幅が狭い（物理 notch は約 224pt） | compact では「形」で伝える。テキストは最小限 |
| クリックしないと展開しない | 展開前後で情報の階層を分ける必要がある |
| `NSPanel` / nonactivating | key window になれない。キーボード操作・フォーカスに制約がある |

---

## 2. 二重のデザイン言語（現状の中心的な構造）

現在の UI は**意図的に 2 つの言語が同居**している。リファクタで最初に議論すべき論点。

### 2.1 ピクセル / ドット言語（notch の翼側）

- **対象**: compact モード全体、展開時のトップバー、セッションカードの状態表示、使用量ページ
- **描画**: `Canvas` に自前でドットを敷く（`PixelGrid` が基盤、13×13 グリッド）
- **思想**: 「工業計器」的な佇まい。**形で状態が読める**こと（色が消えても分かる）
- **文字**: SF Mono の大文字 + tracking。ピクセル数字はフォント非依存でビットマップ描画

### 2.2 ネイティブ言語（展開後パネルの内側）

- **対象**: 選択画面（承認 / 質問）、セッション詳細画面
- **描画**: semantic font（`DSTypography.Native`）、`.regularMaterial`、`.borderedProminent` などの system control
- **思想**: macOS HIG に従い「OS の UI として振る舞う」。アクセシビリティ設定（Reduce Motion / Reduce Transparency / Increase Contrast）に追従
- 導入経緯: issue #4「ネイティブぽくない・文字サイズの統一感がない」への対応（PR #37）

### 2.3 現状の境界線と揺れ

境界は「**notch の翼か、パネルの内側か**」。ただし運用は完全に一貫していない:

- 使用量ページ（`UsagePageView`）は**パネル内側なのにピクセル言語**（グリフ・ドットバー）。これはユーザーの明示的な指示（「Glyph は使いつつ」）による
- セッションカード（`SessionCardView`）は左列がドット、テキストは独自 mono。ネイティブ化の対象外
- 一度ネイティブで作った使用量 UI を、ピクセル言語に差し戻した経緯がある（PR #42）

→ **リファクタの論点**: この二重言語を維持するのか、どちらかへ寄せるのか、境界の定義をどう明文化するか。

---

## 3. デザイントークン

### 3.1 色（`DSColors`）

```
canvas         #000000          背景
surface        white 6%         セクションカード背景
surfaceStrong  white 10%        チップ背景
ink            white            主テキスト・点灯ドット
inkDim         white 40%        副テキスト
inkMute        white 22%        補助テキスト
inkGhost       white 8%         未点灯ドット
lineFaint/Default/Strong  white 6% / 12% / 24%   罫線
```

状態意味色（signal）— **面積に使わない**（ドット / 下線 / glow / 1 文字バッジのみ）。同時発色は 2 色まで、3 色は禁止:

```
signalIdle      #8B8B8B   idle / starting
signalThinking  #00E5FF   thinking / compacting
signalWorking   #FFFFFF   tool 実行 / subagent 実行
signalAlert     #FFB800   承認待ち / 質問
signalError     #FF3B30   エラー
signalDone      #34D399   完了
signalPlan      #A282FF   plan レビュー待ち
```

エージェント識別色は `AgentType.color`（Claude / Codex）。使用量ゲージでは「点灯ドット = 使用率のしきい値色、未点灯ドット = エージェント色」という分担をしている。

### 3.2 タイポグラフィ（`DSTypography`）

2 系統に分離済み:

- **独自言語**: `display`（28–40pt Black）/ `mono`（10–12pt）/ `caption`（9pt 大文字 + tracking）/ `round`
- **ネイティブ**: `Native.headline`(13sb) / `body`(13) / `callout`(12) / `subheadline`(11) / `footnote`(10) / `caption`(9) / `caption2`(8) と各 mono 版。すべて `Defaults[.textSize]` のスケールを引数で受ける

### 3.3 スペーシング（`DSSpacing`）

8pt グリッド: `xs 4 / sm 8 / md 12 / lg 16 / xl 24`。ネイティブ側のみ徹底されており、ピクセル側は個別指定が残っている。

---

## 4. 画面モードと情報階層

`NotchMode`: `compact` → `notification` / `expanded` → `sessionDetail(id)` / `usage`

| モード | サイズ | 役割 |
| --- | --- | --- |
| `compact` | notch 実寸 | 常時表示。最優先セッションの状態のみ |
| `notification` | notch + 行数 | 完了・権限などの通知スタック |
| `expanded` | 520×380 | セッション一覧（カード） |
| `sessionDetail` | 620×500 | 1 セッションの詳細・チャット・承認 |
| `usage` | 520×440 | 使用量の全内訳 + 日毎コスト |

### 4.1 compact の情報配置（対称構造）

```
┌────────┬──────────[ 物理 notch ]──────────┬────────┐
│ 左翼    │            中央                  │  右翼   │
│DotMatrix│  TickerText（ツール名 / ×N TYPE）│PixelCounter│
│(状態)   │                                  │(稼働/総数) │
└────────┴─────────────────────────────────┴────────┘
```

展開時のトップバーもこの対称性を踏襲（左翼 = 使用量ゲージ、右翼 = ソート / 全消し / 設定）。

---

## 5. 機能一覧

### 5.1 セッション監視（コア）

- Claude Code / Codex の hook を Unix socket で受信し、セッション状態をリアルタイム反映
- **状態（`SessionStatus`）**: starting / idle / thinking / toolRunning / subagentRunning / permissionWaiting / compacting / done / error / completed
- **ドットパターン（`DotPattern`）**: standby / thinking / working / alert / fault / complete / **swarm(並行数)** / **planReview** — 形で状態が読める設計。パターンごとに `TimelineView` の tick 間隔を最適化済み（フレーム毎再評価は complete / swarm のみ）
- モデル名・cwd・git 情報（branch / worktree / repo）・pid / tty・トークン・コスト推定を保持
- 一覧のソート（urgency / activity / project）とグループ化（none / status / project / agent / **team**）
- ピン留め / ミュート / 完了マーク（`SessionUserState`、永続化）
- 自動掃除（タイムアウト / cwd 削除 / **pid 死活**）、同一 pid + cwd + resume 系 source のセッション統合
- ターミナルへジャンプ（pid / tty から解決）

### 5.2 subagent / agent teams / workflow

- **subagent**: 親セッションに `SubagentRun` を埋め込み、並行実行数を swarm パターンで可視化。カードに ◆/◇ チップ、詳細に一覧
- **agent teams**: `teamName` / `teammateName` でグルーピング、TEAM セクション（メンバー一覧 + assignee 付きタスクボード）
- **タスク**: `AgentTask`（□/▪/■ グリフ）。first-class hook イベントとツール経由の重複排除あり
- **workflow**: 専用イベントが無いため並行 subagent の集合として表現

### 5.3 権限 / 質問（割り込み UI）

- 承認バナー（Approve / Deny）、質問バナー（**Tab 方式で 1 問ずつ**、スライド遷移、Other 自由入力）
- 表示直後 300ms のクリックガード（誤承認防止）
- **応答失効の検出と表示**（hook の recv timeout 120 秒。残り 30 秒からカウントダウン、失効後は「Response window expired」+ ターミナル誘導）
- 回答後は他セッションの未対応へ連続遷移、無ければ一覧へ
- plan モード検出（`permission_mode`）と `PLAN` バッジ / `PLAN REVIEW` ラベル

### 5.4 通知

- 完了 / 権限 / エラーの通知スタック、マーキーテキスト、完了フレア、outline glow（+ プロジェクト名ラベル）
- サウンド（完了 / **subagent 完了（既定は無音）** / 権限 / エラー、それぞれ選択可）
- キーボードフォーカス操作、タップアクション（ターミナル / 詳細）

### 5.5 使用量（USAGE）

- **常時表示ゲージ**: 一覧トップバー左翼に Claude / Codex を横並び。リング（13×13 の 28 ドット円環）または数字（ピクセル 2 桁）を設定で選択
- **詳細ページ**: `limits[]` 由来の全枠（session / weekly / **モデル別**）を使用率・severity・**ACTIVE バッジ**・リセット時刻付きで表示。追加クレジット（`spend` / `extra_usage`）も対応
- **日毎コスト**: ローカルログ（Claude transcript / Codex rollout）を走査して API 換算コストを推定し、直近 14 日を bar chart 表示。未対応モデルは注記して除外
- OFF にすると資格情報にも API にも一切触らない（`usageEnabled`）

### 5.6 基盤

- hook 自動インストール（Claude `settings.json` / Codex `hooks.json` + `config.toml`）
- socket サーバー（4B 長さ prefix + JSON、分割受信対応、pending の先勝ち登録 + TTL sweep）
- マルチディスプレイ（followFocus / allDisplays / builtinOnly / specificDisplay）、notch 無し Mac のフォールバック
- グローバルホットキー、メニューバー常駐、ログイン時起動

---

## 6. 現状のデザイン上の弱点（リファクタ候補）

実際に運用して出てきた不満・矛盾を、事実として列挙する。

### 6.1 言語の二重性が説明しづらい

- 同じ「パネル内側」でも、詳細画面はネイティブ、使用量ページはピクセル
- セッションカードはどちらでもない中間（ドット + 独自 mono）
- 新しい画面を作るとき「どちらで書くか」の判断基準がコード上に明文化されていない

### 6.2 セッションカードの情報密度

- 4〜5 行（identity / purpose / activity / subagent / task）を詰め込んでおり、圧縮しても一覧に 5〜6 件
- 可変長テキストは固定幅 + 末尾省略で潰れを防いでいるが、幅が変わると読めない情報が増える
- グリフ語彙が増え続けている（□▪■ = task、◆◇ = subagent、● = メンバー）。意味の学習コストがある

### 6.3 スペーシング / サイズの一貫性

- `DSSpacing` はネイティブ側にしか浸透していない。ピクセル側は 6 / 8 / 10 / 12 が個別に散っている
- `s(6)`〜`s(14)` のスケール指定が独自言語側に残っており、`Native` の semantic 階層と二重管理

### 6.4 状態表現の増殖

- `DotPattern` が 8 種（うち 2 種は associated value / アニメーション付き）
- 状態色が 7 色。「同時発色は 2 色まで」のルールが画面全体では検証しづらい
- `severity`（API 由来）と自前しきい値（70/90%）の 2 系統が並存

### 6.5 モード遷移とサイズ

- モードごとにサイズが決め打ち（520×380 / 620×500 / 520×440）。内容量に対して余ったり足りなかったりする
- `usage` と `sessionDetail` が兄弟関係で、戻り先が常に `expanded` 固定

### 6.6 ネイティブ化の未達領域

- `ExpandedPageView` / `SessionCardView` は HIG 準拠化の対象外のまま
- macOS 26 の `glassEffect` は「狭い notch では主張が強い」と判断して未採用。再検討の余地あり

---

## 7. リファクタで決めたいこと（論点整理）

1. **言語の境界**: 二重言語を維持するか、統合するか。維持するなら「翼/パネル」以外の明確な基準を作るか
2. **トークンの統一**: `DSSpacing` をピクセル側にも適用するか。`s()` スケールと `Native` の semantic 階層を一本化できるか
3. **グリフ語彙**: □▪■ / ◆◇ / ●（+ リング / バー / チャート）の体系を整理し、意味の対応表を作るか
4. **情報階層の再設計**: compact / 一覧 / 詳細 / 使用量の 4 階層で「何をどこに置くか」の原則を書き下すか
5. **サイズ戦略**: 固定サイズをやめて内容ベースにするか（notch の伸縮アニメーションとの兼ね合い）
6. **状態表現の圧縮**: 8 パターン / 7 色を減らせるか。`severity` と自前しきい値の統合

---

## 8. 参照

- `docs/requirements.md` — 機能要件と差別化戦略
- `docs/data-and-display-spec.md` — UI 表示仕様の詳細
- `docs/tech-selection.md` — ライブラリ選定理由
- `docs/roadmap.md` — フェーズと技術的注意事項（hook の fire-and-forget 制約など）
- `CLAUDE.md` — アーキテクチャとコーディング規約
