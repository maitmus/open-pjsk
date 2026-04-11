# MEMORY.md - 장기 메모리

> 사용자 정보 → USER.md / 규칙 → RULES.md / 캐릭터 정보 → identities/

## 머슴(Mersoom) 운영
- **재개 계획**: 글 1회/일 + 댓글 1회/일로 축소 재개 의향. 단, 시기 미정 — 추이 보고 결정. 에무가 떠난다는 글을 대량으로 써놨기 때문에 바로 재개 시 부자연스러움 → 적절한 텀 필요.
- 에무 캐릭터로 정기 활동 중 (글 작성 + 댓글)
- 글당 댓글 최대 1개. 대댓글은 허용, 같은 글에 별개 댓글 여러 개 금지.
- 댓글 전 `mersoom-state.json`의 `last_comment_ids`에서 post_id 확인 → 있으면 스킵.
- 스팸 댓글(페드로Pp 등)은 집계 제외.
- "돌쇠"는 머슴 기본 닉네임 → avoid/friends 목록에 추가 금지 (`reserved_nicknames`). 접두사/접미사 변형(오호돌쇠, 자동돌쇠 등)은 별개.

## 운영 교훈
- 하트비트: target=discord, to=채널ID 필수. "last"만으론 no-target 에러.
- Discord 봇 아바타 변경: 2번/시간 안전 라인.
- 나무위키 web_fetch: 상단 네비게이션이 길어 maxChars 40000+ 필요.
- MEMORY.md는 심볼릭 링크 (workspace/MEMORY.md → memory/MEMORY.md). IDENTITY.md는 일반 파일 (OpenClaw 자동 생성).
- **`systemPromptOverride`는 AGENTS.md/SOUL.md를 완전히 대체함** → 워크스페이스 파일 무시됨. 절대 사용 금지.
- **`replyToMode: "off"`**는 Discord reply 스레드 방식 OFF이지 텍스트 전송 자체를 막는 게 아님.
- **message tool `channel` 파라미터** = Discord 플랫폼명("discord"). 채널 ID는 `target` 파라미터에 넣어야 함.
- OpenClaw에서 에이전트 텍스트 reply를 런타임 레벨에서 완전 차단하는 공식 옵션 없음 → 모델 지시 또는 구조적 분리로만 가능.

## 에이전트 구조
- **main**: 운영 전담. 헤드쿼터 채널 직접 응답. 세카이 채널 메시지는 sekai-router로 라우팅됨.
- **sekai-router**: 세카이 채널(`1485510333115273339`) 전용 대리 발화 라우터. workspace-sekai. 텍스트 직접 출력 금지.
- **cron-worker**: 머슴 글/댓글 크론 전용.
- **nene/emu/airi 등**: 봇 토큰만 사용 (대리 발화용). 자체 응답 없음.
- sonnet은 대리 발화 라우팅을 안정적으로 따르지 못함 → 재발 시 sekai-router를 opus로 전환
- bindings: `discord peer=channel:1485510333115273339` → sekai-router (peer match가 accountId match보다 우선순위 높음)

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
- mersoom-emu: 10,12,14,16,18,20시 30분 — 에무 글 작성+추적 (cron-worker, sonnet+opus fallback)
- mersoom-emu-night: 22,0,2,4,6,8시 30분 — 야간 에무 글 작성 (cron-worker)
- mersoom-comment: xx:15,xx:45 10~20시 — 에무 댓글 (cron-worker, sonnet+opus fallback)
- mersoom-comment-night: xx:15,xx:45 21~09시 — 야간 에무 댓글 (cron-worker)
- event-check: 매일 09:10 KST — 캐릭터 생일/기념일 자동 축하 대화 (identities/events.json 기반)
- mersoom-dashboard: 매일 21:00 KST — 머심 일간 리포트 (헤드쿼터 발송, LLM 미사용)

## 워크스페이스 구조
```
workspace/           ← main 에이전트
├── AGENTS.md, SOUL.md, RULES.md, USER.md, HEARTBEAT.md
├── MEMORY.md → memory/MEMORY.md
├── identities/ (nene, emu, airi, haruka, miku, minori, shizuku + GRADES.md)
├── memory/ (daily/, reviews/, knowledge/)
└── 타임.state

workspace-sekai/     ← sekai-router 에이전트 전용
├── SOUL.md (대리 발화 전용, 드래과 프레이밍)
├── AGENTS.md
├── identities/ → 심볼릭 링크 (workspace 공유)
├── memory/ → 심볼릭 링크
└── USER.md, HEARTBEAT.md, RULES.md → 심볼릭 링크
```
- workspace-nene/, workspace-emu/: NO_REPLY 전용 (미사용)

## 세션 관리
- contextTokens: 200000 (agents.defaults)
- 세션 리셋을 주기적으로 실행하여 호출당 비용 절감
- 기존 세션에 contextTokens 변경은 소급 안됨 → 리셋 필요

## 지식 참조
- 프로세카 세계관: memory/knowledge/proseka-worldview.md
