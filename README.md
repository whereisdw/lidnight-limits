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

### 0.2 roadmap (proposed, not promised)

- Reset clock time next to the countdown, plus a one-line "at this pace you hit the limit at HH:MM" estimate (history stays on your Mac, still no network).
- Optional notifications at 80% and 95%, off by default.
- More robust parsing of both tools' output, and an Intel (universal) build.

Details and open questions: [docs/0.2-design.md](docs/0.2-design.md). Known parser edge cases: [docs/parser-cases.md](docs/parser-cases.md).

### Contributing

Bug reports with the exact output are the most useful thing: if the numbers look wrong or stop appearing, open an issue with the text of `claude -p /usage --no-session-persistence --setting-sources ""` (or a few `rate_limits` lines from a `~/.codex/sessions/**/rollout-*.jsonl`, with anything private removed). To add a case, put the sample under `Tests/fixtures/`, list it in `Tests/fixtures/manifest.json` and `docs/parser-cases.md`, and run `bash Tests/check_fixtures.sh` (any OS); on a Mac `./Tests/run.sh` runs the Swift parser against it. Pull requests welcome; please keep it one dependency-free Swift file with no network calls.

## Build from source

```
./build.sh        # swiftc → build/Lidnight Limits.app (signs/notarizes if you have a Developer ID)
./Tests/run.sh    # parser tests
build/Lidnight\ Limits.app/Contents/MacOS/LidnightLimits --print   # print once and exit
```

One Swift file (`Sources/main.swift`), no dependencies.

## Related

I made this as the free, standalone part of [Lidnight](https://lidnight.app/en/), a paid menu bar app (same developer) that keeps your Mac awake while Claude Code or Codex works — lid closed, on battery — shows every session, and lets you approve permission prompts from the notch or your phone. You don't need it to use Lidnight Limits.

## 한국어

Claude Code와 Codex의 사용 한도를 macOS 메뉴바에 보여 주는 무료 오픈소스(MIT) 앱입니다. 숫자는 `claude -p /usage`의 출력과 Codex가 `~/.codex/sessions/**/rollout-*.jsonl`에 남기는 `rate_limits`에서만 읽으며, 네트워크 호출·계정·분석 도구가 없습니다.

### 0.2 로드맵 (제안이며 약속은 아닙니다)

- 리셋 카운트다운 옆에 리셋 시각을 표시하고, "이 속도면 HH:MM에 한도" 한 줄 예측을 추가합니다(기록은 내 Mac에만 저장, 네트워크 없음).
- 80%·95% 알림(기본 꺼짐).
- 두 도구 출력에 대한 파싱 견고성 개선과 Intel(universal) 빌드.

자세한 내용: [docs/0.2-design.md](docs/0.2-design.md), 알려진 파서 엣지 케이스: [docs/parser-cases.md](docs/parser-cases.md).

### 기여하기

숫자가 이상하거나 표시되지 않으면 `claude -p /usage --no-session-persistence --setting-sources ""`의 출력 텍스트(또는 `rollout-*.jsonl`의 `rate_limits` 줄 몇 개, 개인 정보는 지우고)를 붙여 이슈를 열어 주세요. 케이스를 추가하려면 샘플을 `Tests/fixtures/`에 넣고 `Tests/fixtures/manifest.json`과 `docs/parser-cases.md`에 등록한 뒤 `bash Tests/check_fixtures.sh`(어느 OS에서나)를 실행하세요. Mac에서는 `./Tests/run.sh`가 Swift 파서를 그 케이스로 돌립니다. PR 환영합니다. 의존성 없는 Swift 파일 하나, 네트워크 호출 없음 원칙을 지켜 주세요.

## License

MIT
