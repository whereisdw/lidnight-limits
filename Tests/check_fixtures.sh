#!/bin/bash
# Linux-friendly fixture check (python3 stdlib only). Does NOT run the Swift parser; that needs a Mac (Tests/run.sh).
# Checks: manifest consistency, no orphan fixtures, JSONL/text validity, traits (crlf/ansi/truncated), a tolerant
# reference extraction that must agree with each case's `expect`, the >256 KiB generated files, and that
# docs/parser-cases.md mentions every case id.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GEN="$(mktemp -d)"; trap 'rm -rf "$GEN"' EXIT
python3 -I "$ROOT/Tests/fixtures/gen_big.py" "$GEN"
python3 -I - "$ROOT" "$GEN" <<'PY'
import json, os, re, sys
root, gen = sys.argv[1], sys.argv[2]
fx = os.path.join(root, "Tests", "fixtures")
m = json.load(open(os.path.join(fx, "manifest.json"), encoding="utf-8"))
NOW = m["now"]; errs = []
def err(cid, msg): errs.append(f"{cid}: {msg}")
def path(c): return os.path.join(gen, os.path.basename(c["file"])) if c.get("generated") else os.path.join(fx, c["file"])

ids = [c["id"] for c in m["cases"]]
if len(ids) != len(set(ids)): errs.append("duplicate case ids")
for kind in ("claude", "codex"):
    if sum(c["kind"] == kind for c in m["cases"]) < 5: errs.append(f"fewer than 5 {kind} cases")
listed = {c["file"] for c in m["cases"] if not c.get("generated")}
for d in ("claude", "codex"):
    for f in os.listdir(os.path.join(fx, d)):
        if f"{d}/{f}" not in listed: errs.append(f"orphan fixture not in manifest: {d}/{f}")

ANSI = re.compile(r"\x1b\[[0-9;]*m")
CL = re.compile(r"Current (session|week \(all models\))[^0-9\n]*([0-9.]+)%")
def ref_claude(text):
    out = []
    for mm in CL.finditer(ANSI.sub("", text)):
        out.append({"minutes": 300 if mm.group(1) == "session" else 10080, "used": float(mm.group(2))})
    return out
def parse_ts(s):
    from datetime import datetime, timezone
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
def find_rl(o):
    if isinstance(o, dict):
        if isinstance(o.get("rate_limits"), dict): return o["rate_limits"]
        for v in o.values():
            r = find_rl(v)
            if r: return r
    return None
def num(x):
    try: return float(x)
    except (TypeError, ValueError): return None
def ref_codex(lines):
    best = None
    for ln in lines:
        try: o = json.loads(ln)
        except ValueError: continue
        rl = find_rl(o)
        if not rl: continue
        at = parse_ts(o["timestamp"]); ws = []
        for k in ("primary", "secondary"):
            w = rl.get(k)
            if not isinstance(w, dict): continue
            used, mins = num(w.get("used_percent")), num(w.get("window_minutes"))
            if used is None or mins is None: continue
            ra, ris = num(w.get("resets_at")), num(w.get("resets_in_seconds"))
            if ra is not None and 0 <= ra <= 4e9: reset = ra
            elif ris is not None: reset = at + ris
            else: reset = None
            ws.append({"minutes": int(mins), "used": used, "reset_in_min": None if reset is None else (reset - NOW) / 60})
        if ws and (best is None or at >= best[0]): best = (at, ws)
    return best[1] if best else None

for c in m["cases"]:
    cid, p = c["id"], path(c)
    if c["predicted"] not in ("pass", "fail", "unknown"): err(cid, "bad predicted")
    if c["origin"] not in ("documented-in-source", "synthetic", "hypothetical"): err(cid, "bad origin")
    if not os.path.isfile(p): err(cid, f"missing {p}"); continue
    raw = open(p, "rb").read()
    try: text = raw.decode("utf-8")
    except UnicodeDecodeError: err(cid, "not valid UTF-8"); continue
    tr = set(c.get("traits", []))
    if ("crlf" in tr) != (b"\r\n" in raw): err(cid, "crlf trait mismatch")
    if c["kind"] == "claude":
        if ("ansi" in tr) != (b"\x1b[" in raw): err(cid, "ansi trait mismatch")
        if c["file"].startswith("claude/ko-"): continue  # hypothetical locale: no reference extraction
        got = ref_claude(text); exp = (c["expect"] or {}).get("windows", [])
        if [(w["minutes"], w["used"]) for w in got] != [(w["minutes"], float(w["used"])) for w in exp]: err(cid, f"reference {got} != expect {exp}")
        has_reset = "resets" in ANSI.sub("", text)
        if has_reset != any(w["reset_in_min"] is not None for w in exp): err(cid, "reset presence mismatch")
    else:
        lines = text.replace("\r\n", "\n").split("\n")
        if lines and lines[-1] == "": lines.pop()
        bad = 0
        for ln in lines:
            try: json.loads(ln)
            except ValueError: bad += 1
        if bad != c.get("invalid_lines", 0): err(cid, f"{bad} invalid JSONL lines, manifest says {c.get('invalid_lines', 0)}")
        if "truncated" in tr and text.endswith("\n"): err(cid, "truncated fixture ends with newline")
        got = ref_codex(lines); exp = (c["expect"] or {}).get("windows") if c["expect"] else None
        if (got is None) != (exp is None): err(cid, f"reference {got} vs expect {exp}")
        elif got:
            if len(got) != len(exp): err(cid, "window count differs")
            else:
                for g, e in zip(got, exp):
                    if (g["minutes"], g["used"]) != (e["minutes"], float(e["used"])): err(cid, f"{g} != {e}")
                    gr, er = g["reset_in_min"], e["reset_in_min"]
                    if (gr is None) != (er is None) or (gr is not None and abs(gr - er) > 1): err(cid, f"reset {gr} != {er}")
        if "big" in tr:
            if len(raw) <= 262144: err(cid, "big fixture not larger than 256 KiB")
            in_tail = b'"rate_limits"' in raw[-262144:]
            if (c["predicted"] == "pass") != in_tail: err(cid, f"tail contains rate_limits={in_tail}, predicted={c['predicted']}")

doc = open(os.path.join(root, "docs", "parser-cases.md"), encoding="utf-8").read() if os.path.exists(os.path.join(root, "docs", "parser-cases.md")) else ""
for i in ids:
    if f"`{i}`" not in doc: errs.append(f"docs/parser-cases.md does not mention `{i}`")
if errs:
    print("FAIL"); [print(" -", e) for e in errs]; sys.exit(1)
print(f"OK: {len(m['cases'])} cases ({sum(c['kind']=='claude' for c in m['cases'])} claude, {sum(c['kind']=='codex' for c in m['cases'])} codex)")
PY
