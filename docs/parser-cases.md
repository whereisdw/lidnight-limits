# 파서 케이스 표

`Sources/main.swift`의 `Claude.parse` / `Codex.parse` / `Codex.tail` / `Codex.fetch`를 **코드 독해만으로** 분석한 결과다.
이 표의 "예측"은 Mac에서 아직 실행하지 않았다(작성 환경이 Linux). `Tests/run.sh`가 `Tests/fixtures/manifest.json`의 같은 케이스를 돌려
`PASS` / `XFAIL`(예측된 실패) / `FAIL`(예측 밖 불일치, 종료 1) / `XPASS`·`INFO`(예측이 틀렸거나 불확실)로 보여 준다.

- `origin`: `documented-in-source` = main.swift 주석에 나온 형식 / `synthetic` = 코드 동작을 찌르려고 만든 입력 / `hypothetical` = 실제 출력이 존재하는지 **미확인**.
  실제 `claude -p /usage`·Codex 로그를 캡처한 픽스처는 하나도 없다. 0.2 첫 단계로 Mac에서 실제 출력을 캡처해 교체해야 한다.
- "기대"는 견고한 파서가 내야 할 값이다. 현재 구현이 그 값을 못 내면 예측은 `실패`.
- Linux 검증(`bash Tests/check_fixtures.sh`)은 픽스처가 유효한지와, 파서와 무관한 느슨한 참조 추출이 manifest의 기대값과 일치하는지만 확인한다. Swift 파서 자체는 검증하지 않는다.

## Claude `/usage` (`Claude.parse`, main.swift:65–77 · `resetDate` 80–98)

정규식(67행): `^Current (session|week \(all models\)):\s*([0-9.]+)% used(?:\s*·\s*resets\s+(.+?)\s*\(([^)]+)\))?`, 입력은 `split(separator: "\n")` 후 줄마다 공백 trim.

| id | 입력 | 예측 | 이유 / 코드 근거 |
|---|---|---|---|
| `claude-en-basic` | 영문 세션+주간 | 통과 | 주석 형식 그대로 |
| `claude-en-weekly-only` | 주간 줄만 | 통과 | 윈도우 1개. `worst`도 정상 |
| `claude-en-percent-0` | 0% | 통과 | `[0-9.]+` |
| `claude-en-percent-100` | 100, 100.0% | 통과 | Claude 쪽은 클램프 없음(Codex만 0…1000, 146행) |
| `claude-en-reset-passed` | 리셋 시각이 24h 이내 과거 | 통과 | 91행은 24h 넘게 과거일 때만 +1년 → 24h 이내는 과거로 남아 `didReset` → 0% 표시 |
| `claude-en-no-reset-time` | resets 없음 | 통과 | 그룹 3·4가 선택적 → `resetsAt=nil` |
| `claude-en-extra-lines` | 제목·빈 줄·탭·`week (Opus)` | 통과 | Opus 줄은 `(all models)` 아니라 무시(설계상 모델별 한도는 안 봄) |
| `claude-en-crlf` | CRLF 줄바꿈 | **실패** | Swift에서 `"\r\n"`은 한 `Character`라 `split(separator: "\n")`이 안 갈라짐 → 첫 줄만 `^`에 매치, 주간 누락(과소 표시) |
| `claude-en-wrapped` | `used`와 `· resets` 사이 줄바꿈 | **실패** | 줄 단위 정규식 → 윈도우는 잡히나 리셋 시각 유실 |
| `claude-en-ansi` | ANSI 색 이스케이프 | **실패** | `^Current` 앞에 `ESC[1m`이 붙어 불일치 → nil. 50행 `NO_COLOR=1`이 항상 지켜진다는 가정에 의존 |
| `claude-en-uppercase-ampm` | `8:30 PM`, `2 AM` | **불확실** | 84행 `amSymbol="am"`; 대소문자·공백(`h:mm a`) 처리를 포맷 목록(86행)이 안 다룸. Mac에서 확인 |
| `claude-en-bar-style` | 막대가 낀 줄 | **실패** | Claude Code 문서는 `/usage`에 "plan usage bars"가 있다고 설명. `Current session:` 뒤에 막대가 오면 불일치. 실제 `-p` 출력 형식 미확인 |
| `claude-ko-localized` | 한국어 로캘 | **실패** | 영문 고정 정규식. 한국어 출력이 실제로 존재하는지부터 미확인 |

코드 독해로 찾았지만 픽스처로 만들지 않은 항목:

- 91행: `"Oct 22 at 2am"`을 Oct 23 오전 10시에 읽으면 32시간 전 → `d < now-86400` 이라 +1년 → "resets in 364d …". 24h 경계가 어긋나면 큰 오표시.
- `"Feb 29 at …"`: `defaultDate` 연도가 평년이면 `DateFormatter`가 nil → 리셋 유실(윤년 외엔 무해).
- 타임존 `(GMT+9)` 같은 비-IANA 표기: `TimeZone(identifier:)`가 nil이면 `.current`로 조용히 대체 → 리셋이 어긋날 수 있음.
- 45–60행 `fetch()`: `standardError` Pipe를 읽지 않아 stderr가 64KB를 넘으면 자식이 막힘(30초 뒤 terminate). 발생 가능성은 낮음.

## Codex `rollout-*.jsonl` (`Codex.parse` 133–152 · `tail` 125–131 · `fetch` 107–123)

| id | 입력 | 예측 | 이유 / 코드 근거 |
|---|---|---|---|
| `codex-basic` | 정상, 여러 token_count | 통과 | `at >= best.observedAt`로 최신 채택(149행) |
| `codex-no-rate-limits` | rate_limits 없음/null/빈 윈도우 | 통과 | 136행 `contains` 필터 + 138행 `as? [String: Any]`(NSNull이면 건너뜀) + 148행 `ws.isEmpty` |
| `codex-extra-fields` | 필드 추가(tertiary, credits…) | 통과 | `primary`/`secondary`만 읽고 나머지 무시 |
| `codex-truncated-last-line` | 잘린 마지막 줄 | 통과 | `try?` JSON 실패 → `continue` → 직전 줄 사용 |
| `codex-midline-start` | 줄 중간에서 시작(tail 시크) | 통과 | 첫 조각 JSON 실패로 건너뜀. 시크가 UTF-8 중간이어도 `String(decoding:)`가 U+FFFD로 대체 |
| `codex-resets-at-millis` | `resets_at`이 ms | 통과 | 143행 범위(0…4e9) 밖이면 `resets_in_seconds`로 폴백 |
| `codex-ts-no-fraction` | 타임스탬프에 소수초 없음 | **실패** | 135행 `.withFractionalSeconds` 필수 → 139행 `distantPast` → `resets_in_seconds`가 0001년 기준 → `didReset` → "reset since then"(0%)로 오표시, "Checked 2000+ d ago" |
| `codex-string-numbers` | 숫자가 문자열 | **실패(가설)** | 141–142행 `as? NSNumber` 실패 → 윈도우 드롭 → nil |
| `codex-nested-info` | `payload.info.rate_limits` | **실패(가설)** | 138행이 `payload["rate_limits"]`만 조회 → nil. 스키마 이동 시 조용히 "No recent Codex sessions" |
| `codex-crlf` | CRLF | **실패** | Claude와 같은 `split` 문제. 전체가 한 덩어리 → JSON 실패 → nil |
| `codex-big-tail-hit` | 480KB, rate_limits가 끝쪽 | 통과 | `tail`이 마지막 262,144바이트만 읽는데 그 안에 있음 |
| `codex-big-miss-small-lines` | 467KB, rate_limits가 앞쪽 | **실패** | 끝 256KiB에 없음 → 이 파일은 nil → `fetch`(119–121행)가 **다른(더 오래된) 파일**의 값을 최신으로 보여 줌 |
| `codex-big-miss-giant-line` | 400KB 한 줄이 끝을 채움 | **실패** | 위와 동일(도구 출력이 큰 세션에서 현실적) |

(`codex-big-*`는 용량 때문에 커밋하지 않고 `Tests/fixtures/gen_big.py`가 생성한다.)

코드 독해로 찾았지만 픽스처로 만들지 않은 항목:

- 110행: 최근 8일치 `YYYY/MM/DD` 디렉터리만 스캔. 9일 전에 시작해 지금도 쓰이는 세션 파일은 못 봄(주간 한도 윈도우보다 길게 사는 세션).
- 119–121행: mtime 최신 파일에서 처음 nil이 아닌 값을 반환할 뿐 `observedAt` 최댓값을 고르지 않음.
- 119행: 값이 없으면 최대 40파일 × 256KB를 매분 읽음(성능, 소량).
- 디렉터리 날짜는 `Calendar.current`(로컬) 기준. Codex가 UTC로 폴더를 만든다면 자정 전후에 하루 어긋남 — 미확인.

## 제안(0.2에서 고칠 우선순위)

1. 줄 분리: `text.split(whereSeparator: \.isNewline)` 로 CRLF 해결 (S).
2. ISO8601: 소수초 있는/없는 두 포매터 시도 (S).
3. `tail`: 끝 256KiB에 없으면 최대 N MB까지 거꾸로 청크 스캔 (M). `fetch`는 파일별 `observedAt` 최댓값 선택 (S).
4. ANSI 제거 + `Current …` 앞의 임의 접두/막대 허용: `^\W*Current …` 형태로 완화 (S).
5. 실제 출력 캡처로 `hypothetical` 케이스를 확정하거나 삭제 (Mac, S).
