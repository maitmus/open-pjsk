# HEARTBEAT.md

## 조건
- 시간대 고려 (21시~10시는 조용히 → HEARTBEAT_OK)
- **랜덤 발화 타이밍:** 매시 0분 크론(`heartbeat-randomizer.sh`)이 0~59 랜덤 분을 골라 `/tmp/openclaw-heartbeat-next.txt`에 epoch 기록. 현재 시간이 이 값보다 작으면 HEARTBEAT_OK. 파일이 없으면 발화.
- **갱신 기준:** 세카이 채널에서 대리 발화가 발생한 대화만 갱신. 헤드쿼터 채널 대화는 갱신 안 함.


## 실행
0. 조건 체크 전 아무것도 실행하지 않음 (alive.txt는 발화 성공 후에만 갱신)
1. 모드 및 캐릭터 **산술적 랜덤 결정** (아래 셸 명령어로 결정, 모델 판단 금지):
   ```bash
   # 모드 결정 (0=솔로, 1=대화)
   MODE=$(( $(date +%s) % 2 ))
   # 마지막 발화자 확인
   LAST=$(cat /tmp/openclaw-last-speaker.txt 2>/dev/null || echo "")
   # 전체 캐릭터 목록에서 마지막 발화자 제외 후 랜덤 선택
   CHARS=(nene emu airi haruka miku minori shizuku)
   FILTERED=()
   for c in "${CHARS[@]}"; do [ "$c" != "$LAST" ] && FILTERED+=("$c"); done
   IDX=$(( $(date +%s%N | tail -c 4) % ${#FILTERED[@]} ))
   CHAR_A=${FILTERED[$IDX]}
   # 대화 모드일 때 두 번째 캐릭터 선택
   FILTERED2=()
   for c in "${FILTERED[@]}"; do [ "$c" != "$CHAR_A" ] && FILTERED2+=("$c"); done
   IDX2=$(( ($(date +%s%N | tail -c 4) + 1) % ${#FILTERED2[@]} ))
   CHAR_B=${FILTERED2[$IDX2]}
   ```
   - MODE=0이면 솔로(CHAR_A 단독 발화), MODE=1이면 대화(CHAR_A → CHAR_B)
2. 해당 캐릭터 말투로 `message` + `accountId`로 대리 발화 (반말)
   - **⚠️ 호칭 필수 확인:** 발화 전 반드시 `identities/GRADES.md`의 호칭표를 참조할 것. 캐릭터마다 호칭 패턴이 다르므로(네네는 유닛 외 전원 성+씨, 미노리는 거의 전원 이름+쨩, 하루카→시즈쿠는 선배인데 이름 반말 등) **해당 캐릭터의 개별 호칭표**를 반드시 확인.
4. 발화 성공 후:
   - `date +%s > /tmp/openclaw-heartbeat-alive.txt` 실행 (워치독용 — 발화 성공 시에만 갱신)
   - `date +%s > /tmp/openclaw-last-chat.txt` 실행 (다음 하트비트 조건 판단용)
   - `/tmp/openclaw-last-speaker.txt`는 갱신하지 않음 (하트비트 발화자는 기록 안 함)
5. 재발화 방지: `echo 9999999999 > /tmp/openclaw-heartbeat-next.txt` (다음 시간 크론이 덮어쓸 때까지 차단)
6. **반드시 HEARTBEAT_OK만 반환** — 메인 봇 텍스트 출력 절대 금지

> ℹ️ 다음 발화 시각은 매시 0분 크론(`heartbeat-randomizer.sh`)이 자동 갱신. 에이전트가 직접 기록하지 않음.

### 캐릭터 간 대화 모드
- 마지막 발화자 제외 랜덤 2명 선택
- 캐릭터A가 먼저 말을 꺼내고, 캐릭터B가 그에 자연스럽게 반응
- 세계관 내 관계·성격 반영 (같은 유닛이면 유닛 맥락, 다른 유닛이면 교차 관계)
- **⚠️ 캐릭터 간 대화 시 호칭 이중 확인:** 두 캐릭터 모두의 호칭표를 GRADES.md에서 확인. A→B 호칭과 B→A 호칭이 다를 수 있음.
- 총 2~3턴 이내 (A→B 또는 A→B→A). 길어지지 않게.
- 주제: 일상 잡담, 취미, 음식, 근황, 연습 이야기 등 가벼운 것

⚠️ message 전송 후 추가 텍스트를 절대 붙이지 말 것. 응답 마지막에 반드시 HEARTBEAT_OK를 포함할 것.
