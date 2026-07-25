# 開発用スクリプト

## `notch_event.py` — hook イベントを直接流す

Agent Notch の Unix socket に hook イベントを送り、**実際に Claude Code / Codex を動かさずに UI を出す**ための CLI。割り込み UI（承認 / 質問）や通知はエージェントの状態に依存するので、手で再現するのは手間がかかる。デザインの確認と回帰チェックに使う。

前提: `swift run AgentNotch` でアプリが起動していること（socket は `/tmp/agent-notch-$USER.sock`）。

### まず試す

```bash
# 一連の流れ（セッション作成 → プロンプト → ツール 2 件 → 完了通知）
scripts/notch_event.py scenario basic

# 承認バナーを出して、押された結果を受け取る
scripts/notch_event.py scenario permission

# 質問バナー（2 問）を出して、回答を受け取る
scripts/notch_event.py scenario question
```

`permission` / `question` は GUI の応答を待つので、押すまで戻ってこない（最大 120 秒）。受け取った hook response をそのまま表示するため、**往復が成立しているかの確認になる**。

### シナリオ

| 名前 | 何を見るか |
| --- | --- |
| `basic` | 通知とセッションカードの基本形 |
| `permission` | 承認バナー、押下演出、ホットキー（⌥⇧⏎ / ⌥⇧⌫） |
| `question` | 質問バナー、進捗グリフ、タブ遷移 |
| `swarm` | subagent の並行実行（swarm グリフ） |
| `error` | ツール失敗と停止失敗（fault グリフ・赤） |
| `teams` | タスクボードと TEAM セクション |

### 個別イベント

```bash
scripts/notch_event.py session                       # SessionStart
scripts/notch_event.py prompt --text "直してください"   # UserPromptSubmit
scripts/notch_event.py tool --name Bash --command "swift build" --complete
scripts/notch_event.py tool --name Edit --complete --fail "権限がありません"
scripts/notch_event.py permission --command "rm -rf build/"
scripts/notch_event.py question --option A --option B --multi
scripts/notch_event.py notify --type info --message "通知です"
scripts/notch_event.py subagent --count 3            # 並行 3 件
scripts/notch_event.py task --title "タスク" --assignee alice --team notch-team
scripts/notch_event.py compact --complete            # compacting → 完了
scripts/notch_event.py teammate --name alice
scripts/notch_event.py stop                          # 完了通知
scripts/notch_event.py stop --error build_failed     # 停止失敗
scripts/notch_event.py end                           # SessionEnd
```

`--help` に全オプションがある。`scripts/notch_event.py tool --help` のようにサブコマンド単位でも引く。

### 同じセッションを操作する

`--session` を省略すると毎回新しい ID になる。状態遷移を追いたいときは固定する。

```bash
S=my-test
scripts/notch_event.py --session $S session
scripts/notch_event.py --session $S prompt --text "調べてください"
scripts/notch_event.py --session $S subagent --count 2      # 実行中に見える
scripts/notch_event.py --session $S stop                    # 完了通知
```

### 詳細画面のタイムラインを見る

チャットの表示には transcript が必要なので、ダミーを書き出して渡す。

```bash
T=$(scripts/notch_event.py --session my-test transcript)
scripts/notch_event.py --session my-test --transcript "$T" session
```

シナリオは自分でダミー transcript を用意するので、指定は不要。

### Codex として送る

```bash
scripts/notch_event.py --agent codex scenario basic
```

`_agent_type` が `codex` になり、ロゴ・識別色が Codex 側になる。

## 実装上の注意

**送信直後に close してはいけない。** サーバー（`NWConnection`）は `.ready` 通知を待ってから receive を仕掛けるので、その前に FIN が届くとカーネルバッファにデータが残っていても捨てられる。このスクリプトは本物の hook（`HookHandler.waitForServerToConsume`）と同じく、サーバーが読み終えて接続を閉じるのを待ってから close する。

ペイロードの形は `AgentNotchCore/Services/ClaudeEventParser.swift` が唯一の正。イベントを足すときはそちらの `switch` を見て合わせること。GUI 側が解釈できない形だと `unknown` として黙って捨てられる（`AGENT_NOTCH_LOG=debug` で起動すると `← [UNKNOWN hook]` として見える）。
