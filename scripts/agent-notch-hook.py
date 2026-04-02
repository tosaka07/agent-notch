#!/usr/bin/env python3
"""Agent Notch hook script for Claude Code. Reads JSON from stdin, forwards to Unix socket."""
import json, os, socket, struct, subprocess, sys

SOCKET_PATH = f"/tmp/agent-notch-{os.environ.get('USER', 'unknown')}.sock"


def get_tty():
    try:
        ppid = os.getppid()
        result = subprocess.run(
            ["ps", "-p", str(ppid), "-o", "tty="],
            capture_output=True,
            text=True,
            timeout=2,
        )
        return result.stdout.strip()
    except Exception:
        return ""


def send_to_socket(data):
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.connect(SOCKET_PATH)
        payload = json.dumps(data).encode("utf-8")
        header = struct.pack("<I", len(payload))
        sock.sendall(header + payload)
        resp_header = sock.recv(4)
        if len(resp_header) == 4:
            resp_len = struct.unpack("<I", resp_header)[0]
            resp_data = sock.recv(resp_len)
            sock.close()
            return json.loads(resp_data)
        sock.close()
    except (ConnectionRefusedError, FileNotFoundError):
        pass
    except Exception:
        pass
    return None


def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    input_data["_pid"] = os.getppid()
    input_data["_tty"] = get_tty()

    response = send_to_socket(input_data)
    if response:
        json.dump(response, sys.stdout)
    else:
        json.dump({}, sys.stdout)


if __name__ == "__main__":
    main()
