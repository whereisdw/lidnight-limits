#!/bin/bash
# Parser tests: compiles main.swift with a test entry and checks Claude /usage text and a Codex rate_limits line.
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
sed 's/^let app = NSApplication.shared$/runTests(); exit(0)\nlet app = NSApplication.shared/' Sources/main.swift > "$T/main.swift"
cat >> "$T/main.swift" <<'SW'
func runTests() {
    var fails = 0
    func check(_ ok: Bool, _ name: String) { print(ok ? "PASS" : "FAIL", name); if !ok { fails += 1 } }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let cl = Claude.parse("Current session: 18% used · resets 10:40pm (Asia/Seoul)\nCurrent week (all models): 43% used · resets Oct 24 at 2am (Asia/Seoul)\n", now: now)
    check(cl?.windows.count == 2 && cl?.windows[0].usedPercent == 18 && cl?.windows[1].minutes == 10080, "Claude /usage: session + week")
    check(cl?.worst?.usedPercent == 43, "worst window is the highest")
    check(Claude.parse("not a subscription") == nil, "Claude: no limits text → nil")
    let line = #"{"timestamp":"2026-10-20T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12.5,"window_minutes":300,"resets_at":1800003600},"secondary":{"used_percent":40,"window_minutes":10080,"resets_in_seconds":3600}}}}"#
    let cx = Codex.parse(line)
    check(cx?.windows.count == 2 && cx?.windows[0].usedPercent == 12.5 && cx?.windows[1].name == "Weekly", "Codex rate_limits: primary + secondary")
    let nulls = #"{"timestamp":"2026-10-20T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":null,"secondary":null}}}"#
    check(Codex.parse(nulls) == nil, "Codex: empty windows → nil")
    let old = Window(usedPercent: 100, minutes: 300, resetsAt: now.addingTimeInterval(-60))
    check(old.current(now) == 0 && Fmt.line(old, now: now).contains("reset"), "a window whose reset passed counts as 0%")
    check(Limits(windows: [old, Window(usedPercent: 31, minutes: 10080, resetsAt: now.addingTimeInterval(86400))], observedAt: now).windows.map { $0.current(now) }.max() == 31, "worst ignores a reset window")
    check(Fmt.until(now.addingTimeInterval(3 * 86400 + 5 * 3600), now: now) == "3d 5h", "format: days and hours")
    if fails > 0 { exit(1) }
}
SW
swiftc -O "$T/main.swift" -o "$T/t" && "$T/t"
rm -rf "$T"
