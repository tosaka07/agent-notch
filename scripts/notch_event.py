#!/usr/bin/env python3
"""Agent Notch の socket に hook イベントを直接流す開発用 CLI。

実際に Claude Code / Codex を動かさなくても UI を出せるので、割り込み UI や通知の
デザイン確認・回帰チェックに使う。ペイロードは `AgentNotchCore/Services/ClaudeEventParser.swift`
が解釈する形に合わせている。

    # 一連の流れを再生（セッション作成 → ツール実行 → 完了通知）
    scripts/notch_event.py scenario basic

    # 承認バナーを出して、押された結果（approve / deny）を受け取る
    scripts/notch_event.py permission --command "rm -rf build/"

    # 個別イベント
    scripts/notch_event.py session
    scripts/notch_event.py prompt --text "テストの依頼"
    scripts/notch_event.py stop

`--session` を省略すると `dev-<乱数>` を使う。同じセッションを続けて操作したいときは
明示的に渡すこと。

# 送信の作法
hook と同じく「サーバーが読み終えて接続を閉じるまで待ってから close」する。
送信直後に close するとイベントが捨てられる（`HookHandler.waitForServerToConsume` 参照）。
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import struct
import sys
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any

SOCKET_PATH = f"/tmp/agent-notch-{os.environ.get('USER', 'unknown')}.sock"

# 応答を待つイベント（GUI の操作結果が hook response として返る経路）。
# `HookHandler.shouldWaitForResponse` と同じ判定。
RESPONSE_TIMEOUT = 120.0
# fire-and-forget でサーバーの読み取りを待つ上限。
CONSUME_TIMEOUT = 0.3


class SocketUnavailable(RuntimeError):
    """socket が無い（アプリが起動していない）。"""


def send(payload: dict[str, Any], *, wait_for_response: bool = False) -> dict[str, Any] | None:
    """1 イベントを送る。`wait_for_response` なら GUI の応答を待って返す。"""
    if not Path(SOCKET_PATH).exists():
        raise SocketUnavailable(
            f"{SOCKET_PATH} がありません。先に `swift run AgentNotch` で起動してください。"
        )

    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.connect(SOCKET_PATH)
    body = json.dumps(payload).encode()
    client.sendall(struct.pack("<I", len(body)) + body)

    if wait_for_response:
        client.settimeout(RESPONSE_TIMEOUT)
        try:
            header = _recv_exactly(client, 4)
            if header is None:
                return None
            length = struct.unpack("<I", header)[0]
            data = _recv_exactly(client, length)
            return json.loads(data) if data else None
        except (TimeoutError, socket.timeout):
            return None
        finally:
            client.close()

    # サーバーが読み終えて閉じるのを待ってから close する（本物の hook と同じ作法）。
    client.settimeout(CONSUME_TIMEOUT)
    try:
        client.recv(16)
    except OSError:
        pass
    client.close()
    return None


def _recv_exactly(client: socket.socket, length: int) -> bytes | None:
    buffer = b""
    while len(buffer) < length:
        chunk = client.recv(length - len(buffer))
        if not chunk:
            return None
        buffer += chunk
    return buffer


def base_payload(args: argparse.Namespace, event: str) -> dict[str, Any]:
    """全イベント共通のフィールド。hook が付ける `_pid` / `_agent_type` も再現する。"""
    payload: dict[str, Any] = {
        "hook_event_name": event,
        "session_id": args.session,
        "cwd": args.cwd,
        # GUI は `_agent_type` で Claude / Codex を見分ける（`EventProcessor.parseMessage`）。
        "_agent_type": args.agent,
        "_pid": os.getpid(),
        "_tty": os.ttyname(sys.stdin.fileno()) if sys.stdin.isatty() else None,
    }
    if args.model:
        payload["model"] = args.model
    if args.transcript:
        payload["transcript_path"] = args.transcript
    return payload


# MARK: - 個別イベント


def cmd_session(args: argparse.Namespace) -> None:
    send({**base_payload(args, "SessionStart"), "source": args.source})
    print(f"SessionStart session={args.session} source={args.source}")


def cmd_prompt(args: argparse.Namespace) -> None:
    send({**base_payload(args, "UserPromptSubmit"), "prompt": args.text})
    print(f"UserPromptSubmit: {args.text}")


def cmd_tool(args: argparse.Namespace) -> None:
    """ツール実行の開始（と、`--complete` なら完了まで）。"""
    tool_use_id = args.tool_use_id or f"tool-{uuid.uuid4().hex[:8]}"
    tool_input = json.loads(args.input) if args.input else {"command": args.command}
    send({
        **base_payload(args, "PreToolUse"),
        "tool_name": args.name,
        "tool_use_id": tool_use_id,
        "tool_input": tool_input,
    })
    print(f"PreToolUse {args.name} id={tool_use_id}")

    if not args.complete:
        return
    time.sleep(args.duration)
    if args.fail:
        send({
            **base_payload(args, "PostToolUseFailure"),
            "tool_name": args.name,
            "tool_use_id": tool_use_id,
            "error": args.fail,
        })
        print(f"PostToolUseFailure {args.name}: {args.fail}")
    else:
        send({
            **base_payload(args, "PostToolUse"),
            "tool_name": args.name,
            "tool_use_id": tool_use_id,
            "tool_response": {"stdout": args.output or ""},
        })
        print(f"PostToolUse {args.name}")


def cmd_permission(args: argparse.Namespace) -> None:
    """承認バナーを出し、押された結果を待って表示する（往復の確認になる）。"""
    tool_input: dict[str, Any] = {"command": args.command}
    if args.description:
        tool_input["description"] = args.description
    payload = {
        **base_payload(args, "PermissionRequest"),
        "tool_name": args.name,
        "tool_input": tool_input,
    }
    print(f"PermissionRequest {args.name}: {args.command}")
    print(f"応答を待っています（最大 {int(RESPONSE_TIMEOUT)} 秒）…")
    response = send(payload, wait_for_response=True)
    _report_response(response)


def cmd_question(args: argparse.Namespace) -> None:
    """質問バナーを出し、回答を待って表示する。"""
    if args.json:
        questions = json.loads(args.json)
    else:
        questions = [
            {
                "question": args.text,
                "header": args.header,
                "multiSelect": args.multi,
                "options": [{"label": label, "description": None} for label in args.option],
            }
        ]
    payload = {
        **base_payload(args, "PermissionRequest"),
        "tool_name": "AskUserQuestion",
        "tool_input": {"questions": questions},
    }
    print(f"AskUserQuestion: {len(questions)} 問")
    print(f"回答を待っています（最大 {int(RESPONSE_TIMEOUT)} 秒）…")
    response = send(payload, wait_for_response=True)
    _report_response(response)


def _report_response(response: dict[str, Any] | None) -> None:
    if response is None:
        print("← 応答なし（タイムアウト、または GUI 側で失効）")
        return
    print("← 応答:")
    print(json.dumps(response, ensure_ascii=False, indent=2))


def cmd_notify(args: argparse.Namespace) -> None:
    send({
        **base_payload(args, "Notification"),
        "type": args.type,
        "message": args.message,
    })
    print(f"Notification[{args.type}]: {args.message}")


def cmd_stop(args: argparse.Namespace) -> None:
    if args.error:
        send({**base_payload(args, "StopFailure"), "error": args.error})
        print(f"StopFailure: {args.error}")
    else:
        send(base_payload(args, "Stop"))
        print("Stop（完了通知が出る）")


def cmd_subagent(args: argparse.Namespace) -> None:
    """subagent の起動（と `--stop` なら終了まで）。並行数は swarm グリフで見える。"""
    for index in range(args.count):
        agent_id = f"sub-{uuid.uuid4().hex[:6]}"
        send({
            **base_payload(args, "SubagentStart"),
            "agent_type": args.type,
            "agent_id": agent_id,
        })
        print(f"SubagentStart {args.type} id={agent_id}")
        if args.stop:
            time.sleep(args.duration)
            send({
                **base_payload(args, "SubagentStop"),
                "agent_type": args.type,
                "agent_id": agent_id,
            })
            print(f"SubagentStop id={agent_id}")
        else:
            time.sleep(0.2)
        _ = index


def cmd_task(args: argparse.Namespace) -> None:
    task_id = args.task_id or f"task-{uuid.uuid4().hex[:6]}"
    if args.complete:
        send({
            **base_payload(args, "TaskCompleted"),
            "task_id": task_id,
            "task_title": args.title,
            "completed_by": args.assignee,
            "team_name": args.team,
        })
        print(f"TaskCompleted {task_id}: {args.title}")
    else:
        send({
            **base_payload(args, "TaskCreated"),
            "task_id": task_id,
            "task_title": args.title,
            "task_description": args.description or "",
            "assigned_to": args.assignee,
            "team_name": args.team,
        })
        print(f"TaskCreated {task_id}: {args.title}")


def cmd_compact(args: argparse.Namespace) -> None:
    send(base_payload(args, "PreCompact"))
    print("PreCompact（compacting 状態）")
    if args.complete:
        time.sleep(args.duration)
        send(base_payload(args, "PostCompact"))
        print("PostCompact")


def cmd_teammate(args: argparse.Namespace) -> None:
    send({
        **base_payload(args, "TeammateIdle"),
        "team_name": args.team,
        "teammate_name": args.name,
        "teammate_session_id": args.teammate_session,
    })
    print(f"TeammateIdle team={args.team} teammate={args.name}")


def cmd_end(args: argparse.Namespace) -> None:
    send(base_payload(args, "SessionEnd"))
    print("SessionEnd")


# MARK: - transcript


def write_transcript(path: Path, turns: list[tuple[str, str]]) -> None:
    """詳細画面のタイムライン確認用に、最小構成の transcript を書く。

    Claude Code の JSONL 形式のうち、`TranscriptReader` / `TranscriptParser` が読む
    フィールドだけを埋めている（type / message.role / message.content）。
    """
    lines = []
    for role, text in turns:
        lines.append(json.dumps({
            "type": role,
            "message": {
                "role": role,
                "content": [{"type": "text", "text": text}],
                # usage はコスト表示の確認用。assistant のときだけ入れる。
                **({"usage": {"input_tokens": 1200, "output_tokens": 320}} if role == "assistant" else {}),
                "model": "claude-opus-4",
            },
        }, ensure_ascii=False))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def cmd_transcript(args: argparse.Namespace) -> None:
    path = Path(args.path or (Path(tempfile.gettempdir()) / f"notch-dev-{args.session}.jsonl"))
    write_transcript(path, [
        ("user", "ダミーの依頼です"),
        ("assistant", "承知しました。ダミーの応答です。"),
        ("user", "もう 1 つ頼みます"),
        ("assistant", "こちらもダミーの応答です。"),
    ])
    print(path)


# MARK: - シナリオ


def scenario_basic(args: argparse.Namespace) -> None:
    """起動 → プロンプト → ツール 2 件 → 完了通知。通知とカードの基本形を見る。"""
    transcript = _prepare_transcript(args)
    args.transcript = str(transcript)

    send({**base_payload(args, "SessionStart"), "source": "startup"})
    send({**base_payload(args, "UserPromptSubmit"), "prompt": "テスト用の依頼です"})
    for name, command, output in [
        ("Read", "AgentNotch/UI/Root/NotchShell.swift", "1..120 行"),
        ("Bash", "swift build", "Build complete!"),
    ]:
        tool_use_id = f"tool-{uuid.uuid4().hex[:8]}"
        send({
            **base_payload(args, "PreToolUse"),
            "tool_name": name,
            "tool_use_id": tool_use_id,
            "tool_input": {"command": command},
        })
        time.sleep(0.6)
        send({
            **base_payload(args, "PostToolUse"),
            "tool_name": name,
            "tool_use_id": tool_use_id,
            "tool_response": {"stdout": output},
        })
    time.sleep(0.3)
    send(base_payload(args, "Stop"))
    print("basic シナリオ完了（完了通知が出る）")


def scenario_permission(args: argparse.Namespace) -> None:
    """承認バナーを出して応答を待つ。押下演出とホットキーの確認に使う。"""
    transcript = _prepare_transcript(args)
    args.transcript = str(transcript)
    send({**base_payload(args, "SessionStart"), "source": "startup"})
    send({**base_payload(args, "UserPromptSubmit"), "prompt": "ビルド成果物を消してください"})
    args.name = "Bash"
    args.command = "rm -rf .build/arm64-apple-macosx/debug"
    args.description = "古いビルド成果物を削除する"
    cmd_permission(args)


def scenario_question(args: argparse.Namespace) -> None:
    """複数問の質問バナーを出して回答を待つ。進捗グリフとタブ遷移の確認に使う。"""
    transcript = _prepare_transcript(args)
    args.transcript = str(transcript)
    send({**base_payload(args, "SessionStart"), "source": "startup"})
    send({**base_payload(args, "UserPromptSubmit"), "prompt": "方針を決めてください"})
    payload = {
        **base_payload(args, "PermissionRequest"),
        "tool_name": "AskUserQuestion",
        "tool_input": {
            "questions": [
                {
                    "question": "どのアプローチで進めますか？",
                    "header": "設計方針",
                    "multiSelect": False,
                    "options": [
                        {"label": "段階的リファクタ", "description": "既存 API を維持しつつ内部を置き換える"},
                        {"label": "全面書き換え", "description": "破壊的変更を許容してまっさらに作り直す"},
                    ],
                },
                {
                    "question": "対象に含めるファイルは？",
                    "header": None,
                    "multiSelect": True,
                    "options": [
                        {"label": "NotchShell.swift", "description": None},
                        {"label": "PermissionBanner.swift", "description": None},
                        {"label": "QuestionBanner.swift", "description": None},
                    ],
                },
            ]
        },
    }
    print("AskUserQuestion: 2 問。回答を待っています…")
    _report_response(send(payload, wait_for_response=True))


def scenario_swarm(args: argparse.Namespace) -> None:
    """subagent を並行で起動して順に終わらせる。swarm グリフと TEAM セクションの確認。"""
    transcript = _prepare_transcript(args)
    args.transcript = str(transcript)
    send({**base_payload(args, "SessionStart"), "source": "startup"})
    send({**base_payload(args, "UserPromptSubmit"), "prompt": "並列で調べてください"})
    agent_ids = []
    for _ in range(4):
        agent_id = f"sub-{uuid.uuid4().hex[:6]}"
        agent_ids.append(agent_id)
        send({
            **base_payload(args, "SubagentStart"),
            "agent_type": "Explore",
            "agent_id": agent_id,
        })
        time.sleep(0.4)
    for agent_id in agent_ids:
        time.sleep(0.8)
        send({
            **base_payload(args, "SubagentStop"),
            "agent_type": "Explore",
            "agent_id": agent_id,
        })
    time.sleep(0.3)
    send(base_payload(args, "Stop"))
    print("swarm シナリオ完了")


def scenario_error(args: argparse.Namespace) -> None:
    """ツール失敗 → 停止失敗。エラー表示（fault グリフ・赤）の確認。"""
    transcript = _prepare_transcript(args)
    args.transcript = str(transcript)
    send({**base_payload(args, "SessionStart"), "source": "startup"})
    send({**base_payload(args, "UserPromptSubmit"), "prompt": "失敗するはずの処理"})
    tool_use_id = f"tool-{uuid.uuid4().hex[:8]}"
    send({
        **base_payload(args, "PreToolUse"),
        "tool_name": "Bash",
        "tool_use_id": tool_use_id,
        "tool_input": {"command": "swift build --broken-flag"},
    })
    time.sleep(0.6)
    send({
        **base_payload(args, "PostToolUseFailure"),
        "tool_name": "Bash",
        "tool_use_id": tool_use_id,
        "error": "error: unknown option '--broken-flag'",
    })
    time.sleep(0.3)
    send({**base_payload(args, "StopFailure"), "error": "build_failed"})
    print("error シナリオ完了")


def scenario_teams(args: argparse.Namespace) -> None:
    """タスクの作成・完了と teammate idle。TEAM セクションとタスクボードの確認。"""
    transcript = _prepare_transcript(args)
    args.transcript = str(transcript)
    send({**base_payload(args, "SessionStart"), "source": "startup"})
    send({**base_payload(args, "UserPromptSubmit"), "prompt": "チームで進めてください"})
    task_ids = []
    for title, assignee in [
        ("パネルの背景を実装する", "alice"),
        ("承認バナーを直す", "bob"),
        ("テストを足す", "carol"),
    ]:
        task_id = f"task-{uuid.uuid4().hex[:6]}"
        task_ids.append((task_id, title, assignee))
        send({
            **base_payload(args, "TaskCreated"),
            "task_id": task_id,
            "task_title": title,
            "task_description": "",
            "assigned_to": assignee,
            "team_name": "notch-team",
        })
        time.sleep(0.3)
    for task_id, title, assignee in task_ids[:2]:
        time.sleep(0.6)
        send({
            **base_payload(args, "TaskCompleted"),
            "task_id": task_id,
            "task_title": title,
            "completed_by": assignee,
            "team_name": "notch-team",
        })
    send({
        **base_payload(args, "TeammateIdle"),
        "team_name": "notch-team",
        "teammate_name": "alice",
        "teammate_session_id": f"{args.session}-alice",
    })
    print("teams シナリオ完了")


SCENARIOS = {
    "basic": scenario_basic,
    "permission": scenario_permission,
    "question": scenario_question,
    "swarm": scenario_swarm,
    "error": scenario_error,
    "teams": scenario_teams,
}


def cmd_scenario(args: argparse.Namespace) -> None:
    SCENARIOS[args.name](args)


def _prepare_transcript(args: argparse.Namespace) -> Path:
    """シナリオ用の transcript を用意する（`--transcript` 指定があればそれを使う）。"""
    if args.transcript:
        return Path(args.transcript)
    path = Path(tempfile.gettempdir()) / f"notch-dev-{args.session}.jsonl"
    write_transcript(path, [
        ("user", "テスト用の依頼です"),
        ("assistant", "承知しました。作業を始めます。"),
    ])
    return path


# MARK: - CLI


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--session", default=f"dev-{uuid.uuid4().hex[:6]}", help="セッション ID")
    parser.add_argument("--cwd", default=str(Path.cwd()), help="セッションの作業ディレクトリ")
    parser.add_argument("--agent", default="claude", choices=["claude", "codex"], help="エージェント種別")
    parser.add_argument("--model", default="claude-opus-4", help="モデル名（コスト計算に使われる）")
    parser.add_argument("--transcript", help="transcript のパス（詳細画面のタイムラインに出る）")

    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("session", help="SessionStart")
    p.add_argument("--source", default="startup", choices=["startup", "resume", "clear", "compact"])
    p.set_defaults(func=cmd_session)

    p = sub.add_parser("prompt", help="UserPromptSubmit")
    p.add_argument("--text", default="テスト用の依頼です")
    p.set_defaults(func=cmd_prompt)

    p = sub.add_parser("tool", help="PreToolUse（+ --complete で PostToolUse まで）")
    p.add_argument("--name", default="Bash")
    p.add_argument("--command", default="swift build")
    p.add_argument("--input", help="tool_input を JSON で直接指定")
    p.add_argument("--tool-use-id")
    p.add_argument("--complete", action="store_true", help="完了イベントまで送る")
    p.add_argument("--fail", help="失敗として終わらせる（エラー文を指定）")
    p.add_argument("--output", help="stdout として返す文字列")
    p.add_argument("--duration", type=float, default=1.0, help="開始から完了までの秒数")
    p.set_defaults(func=cmd_tool)

    p = sub.add_parser("permission", help="PermissionRequest（応答を待つ）")
    p.add_argument("--name", default="Bash")
    p.add_argument("--command", default="rm -rf build/")
    p.add_argument("--description", default="ビルド成果物を削除する")
    p.set_defaults(func=cmd_permission)

    p = sub.add_parser("question", help="AskUserQuestion（回答を待つ）")
    p.add_argument("--text", default="どちらで進めますか？")
    p.add_argument("--header", default="方針")
    p.add_argument("--option", action="append", default=[], help="選択肢（複数指定可）")
    p.add_argument("--multi", action="store_true", help="複数選択にする")
    p.add_argument("--json", help="questions 配列を JSON で直接指定")
    p.set_defaults(func=cmd_question)

    p = sub.add_parser("notify", help="Notification")
    p.add_argument("--type", default="info")
    p.add_argument("--message", default="テスト通知です")
    p.set_defaults(func=cmd_notify)

    p = sub.add_parser("stop", help="Stop（完了通知）/ --error で StopFailure")
    p.add_argument("--error", help="停止失敗として送る")
    p.set_defaults(func=cmd_stop)

    p = sub.add_parser("subagent", help="SubagentStart（+ --stop で終了まで）")
    p.add_argument("--type", default="Explore")
    p.add_argument("--count", type=int, default=1, help="同時に起動する数")
    p.add_argument("--stop", action="store_true")
    p.add_argument("--duration", type=float, default=1.0)
    p.set_defaults(func=cmd_subagent)

    p = sub.add_parser("task", help="TaskCreated / --complete で TaskCompleted")
    p.add_argument("--title", default="ダミーのタスク")
    p.add_argument("--description")
    p.add_argument("--task-id")
    p.add_argument("--assignee")
    p.add_argument("--team")
    p.add_argument("--complete", action="store_true")
    p.set_defaults(func=cmd_task)

    p = sub.add_parser("compact", help="PreCompact（+ --complete で PostCompact）")
    p.add_argument("--complete", action="store_true")
    p.add_argument("--duration", type=float, default=1.5)
    p.set_defaults(func=cmd_compact)

    p = sub.add_parser("teammate", help="TeammateIdle")
    p.add_argument("--team", default="notch-team")
    p.add_argument("--name", default="alice")
    p.add_argument("--teammate-session")
    p.set_defaults(func=cmd_teammate)

    p = sub.add_parser("end", help="SessionEnd")
    p.set_defaults(func=cmd_end)

    p = sub.add_parser("transcript", help="ダミー transcript を書き出してパスを表示")
    p.add_argument("--path")
    p.set_defaults(func=cmd_transcript)

    p = sub.add_parser("scenario", help="一連の流れを再生")
    p.add_argument("name", choices=sorted(SCENARIOS))
    p.set_defaults(func=cmd_scenario)

    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        args.func(args)
    except SocketUnavailable as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\n中断しました", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
