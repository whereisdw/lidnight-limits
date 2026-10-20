// Lidnight Limits — Claude Code and Codex usage limits in the macOS menu bar.
// MIT License. https://github.com/whereisdw/lidnight-limits
//
// Where the numbers come from (nothing leaves your Mac, no account, no analytics):
// - Claude: the official Claude Code CLI's `/usage` command (`claude -p /usage`). It reads your own subscription
//   status and does not call a model, so it doesn't use your limit. Run with no session file and no settings/hooks.
// - Codex: the `rate_limits` field Codex writes into its own session logs (~/.codex/sessions/**/rollout-*.jsonl).
import AppKit
import ServiceManagement

struct Window: Equatable {
    var usedPercent: Double
    var minutes: Int
    var resetsAt: Date?
    /// The window already reset after this reading (old Codex logs): nothing is used now.
    func didReset(_ now: Date = Date()) -> Bool { resetsAt.map { $0 <= now } ?? false }
    func current(_ now: Date = Date()) -> Double { didReset(now) ? 0 : usedPercent }
    var name: String {
        switch minutes {
        case 300: return "5-hour"
        case 10080: return "Weekly"
        default: return minutes % 60 == 0 ? "\(minutes / 60)-hour" : "\(minutes)-min"
        }
    }
}

struct Limits: Equatable {
    var windows: [Window]
    var observedAt: Date
    var worst: Window? { windows.max { $0.current() < $1.current() } }
}

// MARK: - Claude (official CLI /usage)

enum Claude {
    static func binary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Takes a few seconds; call off the main thread. nil if not installed / not a subscription / unreadable.
    static func fetch() -> Limits? {
        guard let bin = binary() else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["-p", "/usage", "--no-session-persistence", "--setting-sources", ""]
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { if p.isRunning { p.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// "Current session: 4% used · resets Sep 28 at 10:40am (Asia/Seoul)"
    /// "Current week (all models): 49% used · resets Oct 3 at 2am (Asia/Seoul)"
    static func parse(_ text: String, now: Date = Date()) -> Limits? {
        var ws: [Window] = []
        let re = try! NSRegularExpression(pattern: #"^Current (session|week \(all models\)):\s*([0-9.]+)% used(?:\s*·\s*resets\s+(.+?)\s*\(([^)]+)\))?"#)
        for raw in text.split(separator: "\n") {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
            func g(_ i: Int) -> String? { Range(m.range(at: i), in: line).map { String(line[$0]) } }
            guard let kind = g(1), let pct = g(2).flatMap(Double.init) else { continue }
            let reset = g(3).flatMap { resetDate($0, tz: g(4), now: now) }
            ws.append(Window(usedPercent: pct, minutes: kind == "session" ? 300 : 10080, resetsAt: reset))
        }
        return ws.isEmpty ? nil : Limits(windows: ws, observedAt: now)
    }

    /// "Oct 3 at 2am" · "Sep 28 at 10:40am" · "10:40am" (today) → the next such time
    static func resetDate(_ s: String, tz: String?, now: Date) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz.flatMap(TimeZone.init(identifier:)) ?? .current
        f.amSymbol = "am"; f.pmSymbol = "pm"
        f.defaultDate = now
        for fmt in ["MMM d 'at' h:mma", "MMM d 'at' ha", "MMM d, h:mma", "MMM d", "h:mma", "ha"] {
            f.dateFormat = fmt
            guard var d = f.date(from: s) else { continue }
            var cal = Calendar(identifier: .gregorian); cal.timeZone = f.timeZone
            if fmt.hasPrefix("MMM") {
                if d < now.addingTimeInterval(-86400) { d = cal.date(byAdding: .year, value: 1, to: d) ?? d }
            } else if d < now {
                d = cal.date(byAdding: .day, value: 1, to: d) ?? d
            }
            return d
        }
        return nil
    }
}

// MARK: - Codex (session logs)

enum Codex {
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")

    /// Newest `rate_limits` from session logs changed in the last 8 days (reads only the tail of each file).
    static func fetch(now: Date = Date()) -> Limits? {
        var files: [(URL, Date)] = []
        let cal = Calendar.current
        for back in 0..<8 {
            guard let d = cal.date(byAdding: .day, value: -back, to: now) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: d)
            let dir = root.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
            let list = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for f in list where f.pathExtension == "jsonl" {
                if let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate { files.append((f, m)) }
            }
        }
        for (f, _) in files.sorted(by: { $0.1 > $1.1 }).prefix(40) {
            if let l = parse(tail(f)) { return l }
        }
        return nil
    }

    static func tail(_ url: URL) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        let end = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: end > 262_144 ? end - 262_144 : 0)
        return String(decoding: (try? h.readToEnd()) ?? Data(), as: UTF8.self)
    }

    static func parse(_ text: String) -> Limits? {
        var best: Limits?
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for line in text.split(separator: "\n") where line.contains("\"rate_limits\"") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let p = obj["payload"] as? [String: Any], let rl = p["rate_limits"] as? [String: Any] else { continue }
            let at = (obj["timestamp"] as? String).flatMap(iso.date(from:)) ?? Date.distantPast
            func win(_ k: String) -> Window? {
                guard let w = rl[k] as? [String: Any], let used = (w["used_percent"] as? NSNumber)?.doubleValue, used.isFinite,
                      let mins = (w["window_minutes"] as? NSNumber)?.intValue else { return nil }
                let reset = (w["resets_at"] as? NSNumber).map(\.doubleValue).flatMap { $0.isFinite && (0...4e9).contains($0) ? $0 : nil }
                    .map { Date(timeIntervalSince1970: $0) }
                    ?? (w["resets_in_seconds"] as? NSNumber).map(\.doubleValue).flatMap { $0.isFinite && abs($0) < 1e8 ? at.addingTimeInterval($0) : nil }
                return Window(usedPercent: min(max(used, 0), 1000), minutes: mins, resetsAt: reset)
            }
            let ws = [win("primary"), win("secondary")].compactMap { $0 }
            if !ws.isEmpty, at >= (best?.observedAt ?? .distantPast) { best = Limits(windows: ws, observedAt: at) }
        }
        return best
    }
}

// MARK: - Text

enum Fmt {
    static func until(_ d: Date, now: Date = Date()) -> String {
        let s = max(0, Int(d.timeIntervalSince(now)))
        let dd = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if dd > 0 { return "\(dd)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(max(1, m))m"
    }
    static func ago(_ d: Date, now: Date = Date()) -> String {
        let m = Int(now.timeIntervalSince(d) / 60)
        if m < 1 { return "just now" }
        if m < 60 { return "\(m)m ago" }
        if m < 1440 { return "\(m / 60)h ago" }
        return "\(m / 1440)d ago"
    }
    static func line(_ w: Window, now: Date = Date()) -> String {
        if w.didReset(now) { return "\(w.name)  reset since then" }
        var s = "\(w.name)  \(Int(w.usedPercent.rounded()))% used"
        if let r = w.resetsAt, r > now { s += " · resets in \(until(r, now: now))" }
        return s
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var claude: Limits?
    private var codex: Limits?
    private var claudeAt = Date.distantPast
    private var fetchingClaude = false
    private var timer: Timer?
    private let lidnight = URL(string: "https://lidnight.app/en/?ref=limits")!

    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.title = "…"
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh(force: false) }
    }

    func menuWillOpen(_ menu: NSMenu) {
        build(menu)
        if Date().timeIntervalSince(claudeAt) > 120 { refresh(force: true) }
    }

    /// Codex every minute (cheap file read). Claude every 10 minutes (spawns the CLI), or on demand.
    private func refresh(force: Bool) {
        DispatchQueue.global(qos: .utility).async {
            let cx = Codex.fetch()
            DispatchQueue.main.async { self.codex = cx; self.render() }
        }
        guard !fetchingClaude, force || Date().timeIntervalSince(claudeAt) > 600 else { return }
        fetchingClaude = true
        DispatchQueue.global(qos: .utility).async {
            let cl = Claude.fetch()
            DispatchQueue.main.async {
                if let cl { self.claude = cl }
                self.claudeAt = Date(); self.fetchingClaude = false; self.render()
                if let m = self.item.menu { self.build(m) }
            }
        }
    }

    private func render() {
        var parts: [String] = []
        if let w = claude?.worst { parts.append("✳︎ \(Int(w.current().rounded()))%") }
        if let w = codex?.worst { parts.append("◇ \(Int(w.current().rounded()))%") }
        item.button?.title = parts.isEmpty ? "Limits" : parts.joined(separator: "  ")
        item.button?.toolTip = "Claude Code and Codex usage limits (highest window shown)"
    }

    private func build(_ menu: NSMenu) {
        menu.removeAllItems()
        func header(_ t: String) { let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false
            i.attributedTitle = NSAttributedString(string: t, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]); menu.addItem(i) }
        func row(_ t: String) { let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i) }
        header("Claude Code")
        if let c = claude {
            c.windows.forEach { row(Fmt.line($0)) }
            row("Checked \(Fmt.ago(c.observedAt))")
        } else {
            row(fetchingClaude ? "Checking…" : (Claude.binary() == nil ? "Claude Code CLI not found" : "No subscription limits found"))
        }
        menu.addItem(.separator())
        header("Codex")
        if let c = codex {
            c.windows.forEach { row(Fmt.line($0)) }
            row("From your last Codex turn, \(Fmt.ago(c.observedAt))")
        } else {
            row("No recent Codex sessions")
        }
        menu.addItem(.separator())
        let r = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r"); r.target = self; menu.addItem(r)
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: ""); login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off; menu.addItem(login)
        menu.addItem(.separator())
        let ln = NSMenuItem(title: "Keep agents running with the lid closed → Lidnight", action: #selector(openLidnight), keyEquivalent: "")
        ln.target = self; ln.toolTip = "Lidnight (by the same developer) keeps your Mac awake while Claude Code or Codex works, lid closed and on battery, shows every session, and lets you approve from your phone."
        menu.addItem(ln)
        let q = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); menu.addItem(q)
    }

    @objc private func refreshNow() { refresh(force: true) }
    @objc private func openLidnight() { NSWorkspace.shared.open(lidnight) }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }
    }
}

if CommandLine.arguments.contains("--print") {
    // For scripts and testing: print what the menu would show, then exit.
    let cl = Claude.fetch(), cx = Codex.fetch()
    print("Claude:", cl.map { $0.windows.map { Fmt.line($0) }.joined(separator: " | ") } ?? "none")
    print("Codex:", cx.map { $0.windows.map { Fmt.line($0) }.joined(separator: " | ") } ?? "none")
    exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
