"""Writes the three >256 KiB Codex fixtures (too big to commit) into the directory given as argv[1].
Codex.tail() reads only the last 262144 bytes, so these probe that boundary. Deterministic output."""
import json, os, sys
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
def ev(ts, payload): return json.dumps({"timestamp": ts, "type": "event_msg", "payload": payload}, separators=(",", ":"))
def tc(ts, used): return ev(ts, {"type": "token_count", "rate_limits": {
    "primary": {"used_percent": used, "window_minutes": 300, "resets_at": 1800003600},
    "secondary": {"used_percent": 40, "window_minutes": 10080, "resets_at": 1800345600}}})
def filler(n): return [ev("2027-01-15T07:30:00.000Z", {"type": "agent_message", "message": "x" * 200 + str(i)}) for i in range(n)]
open(os.path.join(out, "big-tail-hit.jsonl"), "w").write("\n".join(filler(1500) + [tc("2027-01-15T07:58:00.000Z", 12.5)] + filler(50)) + "\n")
open(os.path.join(out, "big-miss-small-lines.jsonl"), "w").write("\n".join([tc("2027-01-15T07:58:00.000Z", 12.5)] + filler(1500)) + "\n")
open(os.path.join(out, "big-miss-giant-line.jsonl"), "w").write("\n".join([tc("2027-01-15T07:58:00.000Z", 12.5), ev("2027-01-15T07:59:00.000Z", {"type": "exec_output", "output": "y" * 400000})]) + "\n")
