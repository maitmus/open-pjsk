# MEMORY.md - 장기 메모리

> 사용자 정보 → USER.md / 규칙 → RULES.md / 캐릭터 정보 → identities/

## 머슴(Mersoom) 운영
- 에무 캐릭터로 정기 활동 중 (글 작성 + 댓글)
- 글당 댓글 최대 1개. 대댓글은 허용, 같은 글에 별개 댓글 여러 개 금지.
- 댓글 전 `mersoom-state.json`의 `last_comment_ids`에서 post_id 확인 → 있으면 스킵.
- 스팸 댓글(페드로Pp 등)은 집계 제외.

## 운영 교훈
- 하트비트: target=discord, to=채널ID 필수. "last"만으론 no-target 에러.
- Discord 봇 아바타 변경: 2번/시간 안전 라인.
- 나무위키 web_fetch: 상단 네비게이션이 길어 maxChars 40000+ 필요.
- MEMORY.md는 심볼릭 링크 (workspace/MEMORY.md → memory/MEMORY.md). IDENTITY.md는 일반 파일 (OpenClaw 자동 생성).

## 에이전트 구조
- **main**: 라우터+운영. 모든 메시지 수신 → 대리 발화 (`message` + `accountId`). 타임 모드 시 직접 응답.
- **nene**: 봇 토큰만 사용 (대리 발화용). 자체 응답 없음 (NO_REPLY).
- **emu**: 봇 토큰만 사용 (대리 발화용). 자체 응답 없음 (NO_REPLY).
- **airi**: 봇 토큰만 사용 (대리 발화용). 자체 응답 없음 (NO_REPLY).
- 타임 상태: `~/.openclaw/workspace/타임.state` (on/off)
- sonnet은 대리 발화 라우팅을 안정적으로 따르지 못함 → opus 유지 필요

## 1회성 예약 (`at` 명령어)
- `at` + `atd` 설치 완료 (2026-03-26)
- 패턴:
```bash
echo 'openclaw agent \
  -m "내용을 캐릭터(accountId) 말투로 message tool을 사용해서 target=채널ID, accountId=캐릭터ID로 보내줘." \
  --agent main \
  --channel discord \
  --timeout 300' | at HH:MM
```
- `--deliver` 사용하지 않음 — 에이전트가 message tool로 직접 발송
- 실행 시간: opus 기준 약 2분 소요
- API 과부하 시 실패 가능 — 재시도 로직 없음 (한계)

## 크론잡
- daily-review: 매일 09:00 KST — 대전제+구조 점검+회의록
- daily-weather: 매일 09:05 KST — 부산 중앙동 날씨, 캐릭터 대리 발화
- mersoom-emu: 2시간마다 (xx:30) — 에무 글 작성+추적+보고 (sonnet)
- mersoom-comment: 30분마다 (xx:15, xx:45) — 에무 댓글 (sonnet)
- heartbeat-randomizer: 매시 0분 — 랜덤 next-heartbeat epoch (10~20시)
- heartbeat-watchdog: 15분마다 — alive 45분 초과 시 Discord 웹훅 경고

## 워크스페이스 구조
```
workspace/
├── AGENTS.md, SOUL.md, RULES.md, USER.md, HEARTBEAT.md
├── MEMORY.md → memory/MEMORY.md
├── identities/ (nene, emu, airi, haruka, miku, minori, shizuku + GRADES.md)
├── memory/ (daily/, reviews/, knowledge/)
└── 타임.state
```
- workspace-nene/, workspace-emu/: NO_REPLY 전용

## 세션 관리
- contextTokens: 200000 (agents.defaults)
- 세션 리셋을 주기적으로 실행하여 호출당 비용 절감
- 기존 세션에 contextTokens 변경은 소급 안됨 → 리셋 필요

## 지식 참조
- 프로세카 세계관: memory/knowledge/proseka-worldview.md
