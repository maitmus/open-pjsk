# HEARTBEAT.md

## 조건
- 시간대 고려 (21시~10시는 조용히 → HEARTBEAT_OK)
- **발화 조건:** 매시 0분 크론(`heartbeat-randomizer.sh`)이 30~90 랜덤 N(분)을 골라 `/tmp/openclaw-heartbeat-threshold.txt`에 저장. 마지막 세카이 채널 발화(`/tmp/openclaw-last-chat.txt`)로부터 N분 이상 경과했으면 발화. 파일이 없으면 발화.
- **갱신 기준:** 세카이 채널에서 대리 발화가 발생한 대화만 갱신. 헤드쿼터 채널 대화는 갱신 안 함.


## 실행
0. 조건 체크:
   ```bash
   HOUR=$(TZ=Asia/Seoul date +%H)
   # 21시~10시는 HEARTBEAT_OK
   if [ "$HOUR" -ge 21 ] || [ "$HOUR" -lt 10 ]; then exit 0; fi
   N=$(cat /tmp/openclaw-heartbeat-threshold.txt 2>/dev/null || echo 60)
   LAST=$(cat /tmp/openclaw-last-chat.txt 2>/dev/null || echo 0)
   NOW=$(date +%s)
   ELAPSED=$(( (NOW - LAST) / 60 ))
   # 경과시간이 N분 미만이면 HEARTBEAT_OK
   if [ $ELAPSED -lt $N ]; then exit 0; fi
   ```
   파일이 없으면(LAST=0) 발화 진행.
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
5. 재발화 방지는 step 4에서 `last-chat.txt` 갱신으로 자동 처리됨 (별도 차단 불필요)
6. **반드시 HEARTBEAT_OK만 반환** — 메인 봇 텍스트 출력 절대 금지

> ℹ️ N(분) 임계값은 매시 0분 크론(`heartbeat-randomizer.sh`)이 30~90 범위에서 자동 갱신.

### 캐릭터 간 대화 모드
- 마지막 발화자 제외 랜덤 2명 선택
- 캐릭터A가 먼저 말을 꺼내고, 캐릭터B가 그에 자연스럽게 반응
- 세계관 내 관계·성격 반영 (같은 유닛이면 유닛 맥락, 다른 유닛이면 교차 관계)
- **⚠️ 캐릭터 간 대화 시 호칭 이중 확인:** 두 캐릭터 모두의 호칭표를 GRADES.md에서 확인. A→B 호칭과 B→A 호칭이 다를 수 있음.
- 총 2~3턴 이내 (A→B 또는 A→B→A). 길어지지 않게.
- 주제: 일상 잡담, 취미, 음식, 근황, 연습 이야기 등 가벼운 것

⚠️ message 전송 후 추가 텍스트를 절대 붙이지 말 것. 응답 마지막에 반드시 HEARTBEAT_OK를 포함할 것.
