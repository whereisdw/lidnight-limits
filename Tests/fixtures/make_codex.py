# One-off helper that wrote Tests/fixtures/codex/*.jsonl (kept so the fixtures can be regenerated). Not run in CI.
import json, os, sys
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "codex")
def ev(ts, payload, typ="event_msg"): return json.dumps({"timestamp": ts, "type": typ, "payload": payload}, separators=(",", ":"))
def rl(p=None, s=None, **extra): return {"primary": p, "secondary": s, **extra}
def w(used, mins, **k): return {"used_percent": used, "window_minutes": mins, **k}
meta = ev("2027-01-15T07:00:00.000Z", {"id": "abc", "cwd": "/tmp/x"}, "session_meta")
msg = ev("2027-01-15T07:01:00.000Z", {"type": "agent_message", "message": "hello"})
def tc(ts, r, **extra): return ev(ts, {"type": "token_count", "info": {"total_token_usage": {"input_tokens": 100}}, "rate_limits": r, **extra})
P = lambda used: w(used, 300, resets_at=1800003600)
S = lambda used: w(used, 10080, resets_at=1800345600)
def put(name, text):
    with open(os.path.join(out, name), "w", newline="") as f: f.write(text)
L = "\n".join
put("basic.jsonl", L([meta, msg, tc("2027-01-15T07:10:00.000Z", rl(P(10), S(30))), msg, tc("2027-01-15T07:58:00.000Z", rl(P(12.5), S(40))), msg]) + "\n")
put("no-rate-limits.jsonl", L([meta, msg, ev("2027-01-15T07:10:00.000Z", {"type": "token_count", "info": None}),
    tc("2027-01-15T07:11:00.000Z", None), tc("2027-01-15T07:12:00.000Z", rl(None, None)), msg]) + "\n")
put("extra-fields.jsonl", L([meta, tc("2027-01-15T07:58:00.000Z", rl(
    w(12.5, 300, resets_at=1800003600, label="five_hour", resets_in_seconds=3600),
    w(40, 10080, resets_at=1800345600, label="weekly"),
    tertiary=w(5, 43200, resets_at=1802592000), credits={"has_credits": True, "balance": "12.00"}, plan_type="plus"), turn_id="t1")]) + "\n")
good = tc("2027-01-15T07:58:00.000Z", rl(P(12.5), S(40)))
put("truncated-last-line.jsonl", L([meta, good, (lambda t: t[:t.index('"used_percent":13') + 20])(tc("2027-01-15T07:59:00.000Z", rl(P(13), S(41))))]))
put("midline-start.jsonl", 'ens":{"total_tokens":42}},"rate_limits":{"primary":{"used_percent":99,"window_minutes":300}}}\n' + good + "\n")
put("ts-no-fraction.jsonl", L([meta, tc("2027-01-15T07:59:00Z", rl(w(12.5, 300, resets_in_seconds=3660), w(40, 10080, resets_in_seconds=345660)))]) + "\n")
put("resets-at-millis.jsonl", L([meta, tc("2027-01-15T07:59:00.000Z", rl(w(12.5, 300, resets_at=1800003600000, resets_in_seconds=3660), w(40, 10080, resets_at=1800345600000, resets_in_seconds=345660)))]) + "\n")
put("string-numbers.jsonl", L([meta, tc("2027-01-15T07:58:00.000Z", rl(w("12.5", "300", resets_at=1800003600), w("40", "10080", resets_at=1800345600)))]) + "\n")
put("nested-info.jsonl", L([meta, ev("2027-01-15T07:58:00.000Z", {"type": "token_count", "info": {"rate_limits": rl(P(12.5), S(40))}})]) + "\n")
put("crlf.jsonl", "\r\n".join([meta, msg, good]) + "\r\n")
