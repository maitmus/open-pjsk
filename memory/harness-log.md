# harness-log.md — 하네스 엔지니어링 이력

> 운영 중 실수가 발생하면 아래 절차에 따라 이 파일에 기록하고 하네스를 추가한다.
> 새 항목은 **맨 위**에 추가 (최신순).

## 절차

```
1. 실수 발생 확인 (daily 로그, 유저 리포트, Discord 알림 등)
2. 이 파일에 항목 추가:
   - 날짜, 에이전트, 실수 유형, 원인 분석, 삽입한 하네스 위치/내용
3. 해당 프롬프트 파일(SOUL.md / AGENTS.md / HEARTBEAT.md)에 하네스 삽입
4. workspace-sekai 변경사항 workspace/workspace-sekai/에 복사 후 git push
```

---

## 이력

### 2026-04-15 — 초기 하네스 일괄 적용 (예방적)

| # | 실수 유형 | 원인 | 하네스 위치 | 하네스 내용 |
|---|---|---|---|---|
| P0-1 | 라우터 봇 텍스트 직접 출력 | 역할 모호성 | SOUL.md 기본원칙, AGENTS.md 역할 | 매 턴 종료 자문 + 실행가능/불가 표 |
| P0-2 | `--account` 누락 발송 | 파라미터 체크 없음 | SOUL.md 5번, AGENTS.md 6번 | 발송 전 3-체크 게이트 |
| P1 | GRADES.md 미읽고 호칭 추론 | "기억에 의존" 허용 | SOUL.md 3번, AGENTS.md 4번 | "기억나는 것 같다 = 금지" 체크 |
| P2 | 랜덤 선택 모델 직접 판단 | shuf 강제 없음 | SOUL.md 2번, AGENTS.md 라우팅규칙 | shuf 미실행 금지 패턴 명시 |
| P3 | exec 실패 후 재시도 | 실패 처리 로직 없음 | SOUL.md 5번, AGENTS.md 6번 | 재시도 금지 + 로그 기록 |
| H1 | 하트비트 텍스트 출력 | 별도 경로 P0 미적용 | HEARTBEAT.md 상단 | 텍스트 출력 규칙 표 + 자문 |
| H2 | 하트비트 `--account` 누락 | 별도 경로 P0 미적용 | HEARTBEAT.md step 2 | 발송 전 3-체크 게이트 |
| H3 | 리액션 캐릭터 직접 선택 | shuf 강제 없음 | SOUL.md 7번 | 리액션 선택도 shuf 강제 |
| H4 | 대사 형식 탈선 (지문·길이 초과) | 검증 단계 없음 | SOUL.md 4번, AGENTS.md 5번 | 대사 검증 4-체크 |
| H5 | message tool 사용 | exec 강제 없음 | AGENTS.md 대리발화 섹션 | 발송 직전 tool 선택 자문 |

---

<!-- 새 항목을 여기 위에 추가 -->
