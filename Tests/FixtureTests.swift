// Appended to the instrumented copy of Sources/main.swift by Tests/run.sh (not a separate module).
// Reads Tests/fixtures/manifest.json; FIXTURES / FIXTURES_GEN env vars give the fixture and generated-file directories.
// PASS = matches `expect`. XFAIL = mismatch that the manifest predicted. FAIL = unpredicted mismatch (exit 1).
// XPASS / INFO = prediction was wrong or "unknown": informational, does not fail the run.
func runFixtureTests() {
    let env = ProcessInfo.processInfo.environment
    guard let dir = env["FIXTURES"], let gen = env["FIXTURES_GEN"],
          let data = FileManager.default.contents(atPath: dir + "/manifest.json"),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cases = root["cases"] as? [[String: Any]], let nowSec = (root["now"] as? NSNumber)?.doubleValue else {
        print("FAIL fixtures: manifest unreadable (FIXTURES/FIXTURES_GEN not set?)"); exit(1)
    }
    let now = Date(timeIntervalSince1970: nowSec)
    var fails = 0
    for c in cases {
        guard let id = c["id"] as? String, let kind = c["kind"] as? String, let file = c["file"] as? String else { continue }
        let isGen = (c["generated"] as? Bool) ?? false
        let url = URL(fileURLWithPath: (isGen ? gen + "/" + (file as NSString).lastPathComponent : dir + "/" + file))
        let limits: Limits? = kind == "claude"
            ? Claude.parse(String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self), now: now)
            : Codex.parse(Codex.tail(url))
        var ok: Bool
        if let exp = (c["expect"] as? [String: Any])?["windows"] as? [[String: Any]] {
            ok = limits?.windows.count == exp.count
            if ok, let l = limits {
                for (w, e) in zip(l.windows, exp) {
                    let mins = (e["minutes"] as? NSNumber)?.intValue, used = (e["used"] as? NSNumber)?.doubleValue
                    ok = ok && w.minutes == mins && w.usedPercent == used
                    if let r = (e["reset_in_min"] as? NSNumber)?.doubleValue {
                        ok = ok && w.resetsAt.map { abs($0.timeIntervalSince(now) / 60 - r) <= 1 } == true
                    } else { ok = ok && w.resetsAt == nil }
                }
            }
        } else { ok = limits == nil }
        let predicted = c["predicted"] as? String ?? "pass"
        switch (ok, predicted) {
        case (true, "fail"): print("XPASS", id, "(predicted to fail but passed)")
        case (true, _): print("PASS ", id)
        case (false, "fail"): print("XFAIL", id)
        case (false, "unknown"): print("INFO ", id, "(unknown → mismatch)")
        default: print("FAIL ", id); fails += 1
        }
    }
    if fails > 0 { exit(1) }
}
