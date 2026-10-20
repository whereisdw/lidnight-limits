# Lidnight Limits

Your **Claude Code** and **Codex** usage limits in the macOS menu bar. Free and open source (MIT).

```
✳︎ 43%  ◇ 31%
```

Click it for the details:

```
Claude Code
  5-hour   18% used · resets in 1h 39m
  Weekly   43% used · resets in 3d 5h
Codex
  5-hour   reset since then
  Weekly   31% used · resets in 3d 3h
```

The menu bar shows the higher of each tool's windows (5-hour or weekly), so you see the one that will stop you first.

## Install

- Download `LidnightLimits-x.y.z.zip` from [Releases](https://github.com/whereisdw/lidnight-limits/releases), unzip, move **Lidnight Limits.app** to Applications and open it. It's signed with a Developer ID and notarized by Apple.
- Or with Homebrew: `brew install --cask whereisdw/tap/lidnight-limits`

Apple Silicon, macOS 13 or later. Turn on **Open at Login** from its menu if you want it to stay.

## Where the numbers come from

Nothing leaves your Mac. No account, no analytics, no network calls of its own.

- **Claude:** the official Claude Code CLI's `/usage` command (`claude -p /usage --no-session-persistence --setting-sources ""`). Claude Code checks your own subscription; no model is called, so it doesn't use your limit. Runs every 10 minutes and when you open the menu. Needs the `claude` CLI installed and signed in to a subscription.
- **Codex:** the `rate_limits` that Codex writes into its own session logs (`~/.codex/sessions/**/rollout-*.jsonl`) after each turn. Read every minute, only the end of recent files. If a 5-hour window has reset since your last Codex turn, it shows as reset rather than an old number.

Both are formats the tools don't promise to keep stable, so a future update may need a fix here.

## Build from source

```
./build.sh        # swiftc → build/Lidnight Limits.app (signs/notarizes if you have a Developer ID)
./Tests/run.sh    # parser tests
build/Lidnight\ Limits.app/Contents/MacOS/LidnightLimits --print   # print once and exit
```

One Swift file (`Sources/main.swift`), no dependencies.

## Related

I made this as the free, standalone part of [Lidnight](https://lidnight.app/en/), a paid menu bar app (same developer) that keeps your Mac awake while Claude Code or Codex works — lid closed, on battery — shows every session, and lets you approve permission prompts from the notch or your phone. You don't need it to use Lidnight Limits.

## License

MIT
