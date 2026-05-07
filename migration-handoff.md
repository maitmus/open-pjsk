# Sekai Router 마이그레이션 핸드오프

## 미션

`open-pjsk` 리포지토리의 OpenClaw 기반 라우터 시스템을 **Spring Boot + JDA + Anthropic Java SDK** 기반으로 점진 마이그레이션. 최종 목표는 OpenClaw 의존성 완전 제거 및 운영 비용 80~90% 절감.

## 용어 정의 (필독)

핸드오프 전체에서 "세카이"라는 단어가 채널/봇/에이전트 의미로 혼용되므로 다음 정의를 기준으로 해석할 것.

- **세카이 채널** — 봇들이 대리 발화하는 Discord 채널 (ID: `1485510333115273339`)
- **세카이 봇** — Discord 봇 닉네임이 "세카이"인 봇. **OpenClaw 에이전트 이름은 `main`.** 헤드쿼터 채널에서 LLM 호출로 메타 분석 + 페르소나 편집 담당
- **헤드쿼터 채널** — 세카이 봇과 MaiT가 메타 분석/디버깅하는 별도 Discord 채널 (세카이 채널과 다름)
- **라우터 봇** — 세카이 채널의 메시지를 받아 캐릭터로 라우팅하는 Discord 봇. OpenClaw 에이전트 이름은 `sekai-router`
- **캐릭터 봇 7개** — airi/emu/haruka/miku/minori/nene/shizuku. Discord 봇 토큰만 보유, LLM 호출 없음. 대리 발화 대상

본 마이그레이션의 LLM 호출 지점은 라우터 봇 / 세카이 봇 / 하트비트 3가지.

## 배경 (왜 이 작업이 필요한가)

### 현재 시스템의 비용 문제

OpenClaw 2026.4.22로 라우터 봇 + 세카이 봇 + 7개 캐릭터 봇 운영 중. 매 Discord 메시지마다 시스템 프롬프트 약 15,000~30,000 토큰이 주입되어 비용이 비효율적 (운영 추정치 — 마이그레이션 전 baseline 재측정 필수). 실제 라우팅 작업의 본질적 입력은 2,000 토큰이면 충분함에도 OpenClaw가 자동 주입하는 컨텍스트(메모리 검색, tool schema, 채널 정보 등)가 비대화의 원인.

### 시스템의 진짜 가치

이 시스템은 일반 챗봇이 아니라 **자기 개선 캐릭터 봇 시스템**. OpenClaw를 도입한 이유는 프레임워크의 추상화가 아니라 **파일 시스템 접근**이었음. 세카이 봇(= main 에이전트)이 OpenClaw 환경의 LLM 파일시스템 접근 능력으로 페르소나 파일(identities/*.md)을 직접 편집해서 라우터 응답 품질을 개선하는 메타 레벨 루프가 핵심.

## 시스템 구조

### 두 종류의 발화

**1. 응답 발화 (Reactive Speech)**
- 사용자가 Discord에 메시지 → 라우터가 분석 → 캐릭터로 라우팅 → 대리 발화

**2. 하트비트 발화 (Autonomous Speech)**
- 사용자 입력 없이 캐릭터들이 자율적으로 발화
- 캐릭터 간 대화도 가능 (2명 이상이 서로 응답)
- 특정 날짜/이벤트(생일 등)에 트리거되는 발화도 포함
- `HEARTBEAT.md` 정의 + `events.json` 트리거

이 두 종류 모두 **라우터 봇/세카이 봇을 제외한 7개 캐릭터 봇이 발화 주체**. 7개 캐릭터 봇은 LLM 호출 없이 Discord 토큰만 가지고 있고, 라우터 봇/세카이 봇/하트비트 시스템이 메시지 텍스트를 생성해서 해당 봇 토큰으로 전송.

### 9개 봇 정확한 구성

```
[라우터 봇]      — OpenClaw 에이전트: sekai-router. 세카이 채널 메시지 받아 캐릭터 결정 + 응답 생성 (LLM 호출)
[세카이 봇]      — OpenClaw 에이전트: main. 헤드쿼터 채널에서 메타 분석 + 페르소나 편집 (LLM 호출)
[캐릭터 봇 7개]  — 대리 발화 + 하트비트 발화 대상 (LLM 호출 없음, Discord 토큰만)
  ├─ airi    (모모이 아이리, MORE MORE JUMP!)
  ├─ emu     (오오토리 에무, Wonderlands × Showtime)
  ├─ haruka  (키리타니 하루카, MORE MORE JUMP!)
  ├─ miku    (하츠네 미쿠, Virtual Singer)
  ├─ minori  (하나사토 미노리, MORE MORE JUMP!)
  ├─ nene    (쿠사나기 네네, Wonderlands × Showtime)
  └─ shizuku (히노모리 시즈쿠, MORE MORE JUMP!)
```

※ 위 9개 외에 `cron-worker` 에이전트(Mersoom 글·댓글 자동화)가 OpenClaw에 별도로 존재. Discord 봇이 아닌 머슴 플랫폼 전용 → **본 마이그레이션 범위 외**. 인벤토리 명시 목적으로만 기재.

※ OpenClaw에는 `workspace-emu`, `workspace-nene` 워크스페이스도 존재하지만 둘 다 OpenClaw 기본 SOUL.md 템플릿만 보유한 빈 워크스페이스 — 캐릭터 봇은 토큰만 사용하는 게 맞고 LLM 활성 에이전트가 아님.

### 두 개의 LLM 호출 지점

**1. 라우터 봇 (트래픽 90%+)**
- 세카이 채널 모든 Discord 메시지 처리
- 사용자 메시지 + 채널 컨텍스트 분석
- 호명된 캐릭터 또는 맥락상 적절한 캐릭터로 라우팅
- 해당 캐릭터의 Discord 봇 토큰으로 대리 발화
- 라우터 봇 자체는 NO_REPLY

**2. 세카이 봇 (= main 에이전트, 헤드쿼터 채널, 트래픽 낮음)**
- 라우터/캐릭터 응답 품질 분석
- identities/*.md 등 페르소나 파일 직접 편집
- GRADES.md, events.json, quick-ref.md 등 메타 파일 관리
- 자기 개선 루프

### 라우팅 규칙 (정확히 구현 필요)

캐릭터 이름을 명시적으로 부르는 호출을 "기명", 부르지 않는 호출을 "무기명"이라 함.

**최초 대화가 무기명 호출**:
1. 랜덤으로 캐릭터 하나 결정 후 대리 발화 — **반드시 산술적 랜덤(`shuf` 또는 동등) 사용. LLM이 직접 고르는 것 금지**
2. 이후 대화는 '맥락상 같은 캐릭터를 호출하고 있는 것 같으면' 같은 캐릭터 유지 (멀티턴)
3. 명시적으로 대화 중간에 다른 캐릭터 호출하면 캐릭터 변경 후 대리 발화

**최초 대화가 기명 호출**:
1. 해당 캐릭터로 대리 발화
2. 이후 무기명과 동일 (멀티턴 유지)

**공통**:
- 2명 이상을 동시에 호출한 것 같으면 2명 전부 응답
- "다들/모두/전원/다같이" 호출 → 전체 캐릭터 전원 각각 발화 (순서 셔플)
- 스티커 전용 메시지 → NO_REPLY

**리액션 발화 (선택적 추가)**:
- 캐릭터 A 응답 후 다른 캐릭터 B가 자연스럽게 리액션 가능
- 다른 캐릭터를 언급하거나 유닛 동료가 반응할 만한 화제(음식·취미·연습·공연 등)일 때만
- **depth 최대 2** (리액션에 또 리액션은 1회까지)
- 무관한 사적 질문, 개인 일상 질문에는 미적용
- 리액션도 다른 `--account`(다른 캐릭터)로 발송 — 같은 캐릭터 연속 두 번 금지

**멀티턴 매커니즘 (구현 디테일)**:
- 직전 발화자는 `/tmp/openclaw-last-speaker.txt`에 기록
- 무기명 호출 시 shuf 풀에서 직전 발화자 제외 (연속 발화 방지)
- "맥락상 같은 캐릭터" 판단은 LLM이 메시지 의미를 보고 결정. 시간 임계값(예: 30분 후 새 대화) 같은 명시적 cutoff 없음 — 채널 최근 발화 N개와 새 메시지의 의미적 연결성으로만 판단
- 마이그레이션 시 Spring Boot에서는 Redis(또는 인메모리) + 채널 최근 발화 N개 + 라우터 LLM 판단으로 동일 효과

### 캐릭터 봇 7개 — 대리 발화 대상

라우터 봇 + 세카이 봇을 제외한 7개 캐릭터 봇은 LLM 호출 없이 **대리 발화 대상**(Discord 봇 토큰만 보유). 라우터 LLM이 응답 텍스트를 생성하고, 해당 캐릭터의 Discord 토큰으로 메시지를 전송하는 구조.

### 프로젝트 컨텍스트: Project Sekai (PJSK)

`open-pjsk`는 일본 모바일 리듬 게임 **Project Sekai: Colorful Stage feat. Hatsune Miku** 캐릭터를 페르소나로 사용. 게임은 5개 유닛 × 4명 + Virtual Singer로 구성.

### 페르소나 파일 인벤토리 (`identities/` 폴더)

캐릭터 정의 파일:
- `airi.md` — 모모이 아이리 (MORE MORE JUMP!)
- `emu.md` — 오오토리 에무 (Wonderlands × Showtime, "원더호이~!")
- `haruka.md` — 키리타니 하루카 (MORE MORE JUMP!)
- `miku.md` — 하츠네 미쿠 (Virtual Singer)
- `minori.md` — 하나사토 미노리 (MORE MORE JUMP!)
- `nene.md` — 쿠사나기 네네 (Wonderlands × Showtime)
- `shizuku.md` — 히노모리 시즈쿠 (MORE MORE JUMP!)

캐릭터 파일은 위 7개로 확정 (2026-05-07 인벤토리 검증).

메타데이터 파일 (페르소나 아님):
- `GRADES.md` — **2명 이상의 하트비트 발화 시 캐릭터 간 호칭 + 반말/존댓말 매트릭스**. 7명 캐릭터 간 관계 정의. 예: 미쿠가 에무 부를 때 호칭, 어떤 톤인지 등.
- `events.json` — **날짜 기반 하트비트 트리거**. 캐릭터 생일 등 특정 날짜에 자동 발화 정의.
- `quick-ref.md` — **GRADES.md의 압축 요약본**. Haiku 모델이 GRADES.md 같은 매트릭스 형태 데이터를 정확히 파싱하지 못해서 만들어진 우회용 참조. 모델 능력 한계 보완용.

**중요한 설계 인사이트**: `quick-ref.md`의 존재는 "**모델 능력에 맞춘 시스템 프롬프트 설계**"가 필요함을 의미. Sonnet 4.6 vs Haiku 4.5 능력 차이 고려해서 정보 표현 방식 다르게. 마이그레이션 시 이 노하우 유지/개선 필수.

**중요**: Phase 1 시작 시 `identities/` 폴더 전체를 읽어서 페르소나 정의 다시 확인 후 시스템 프롬프트 구조 결정.

### 캐릭터 페르소나 로딩 전략

7개 캐릭터 페르소나 파일을 시스템 프롬프트에 통합 시 토큰 비용 고려:

```
페르소나 파일 1개 추정 사이즈: 500~1500 토큰
7개 통합: 3500~10500 토큰
+ 라우터 규칙 + 출력 스키마: ~2000 토큰
─────────────────────────────────────
시스템 프롬프트 합계: 5500~12500 토큰
```

캐시 적중 시 비용 영향 작지만, 페르소나 파일 변경되면 캐시 무효화. 세카이 봇이 자주 편집하면 캐시 효율 저하 위험.

**최적화 방향**: 페르소나 파일을 "정적 정의" + "동적 학습 메모"로 분리해서 정적 부분만 시스템 프롬프트에 넣고, 동적 부분은 별도 처리. 단 이건 Phase 4 이후 최적화 단계.

### 하트비트 시스템 (별도 마이그레이션 단위)

이 시스템은 라우터 봇/세카이 봇 외에 **하트비트(Heartbeat)** 라는 세 번째 LLM 사용 지점이 있음. `HEARTBEAT.md` + `events.json` + `GRADES.md` + `quick-ref.md`가 이 시스템의 입력.

> **상태 (2026-05-07)**: 본 하트비트 시스템은 **과거 실제 운영된 구현**이며 현재 일시 비활성 상태. 두 워크스페이스(`workspace`, `workspace-sekai`)의 `HEARTBEAT.md`는 빈 템플릿으로 되돌아가 있음. 아래 묘사는 활성 시점의 운영 데이터 기반이며 신뢰 가능. **Phase 3.5에서 재가동 + 마이그레이션 대상**.

**하트비트 동작**:
- 주기적 또는 이벤트 기반 트리거 (cron 비슷)
- 1명 또는 2명+ 캐릭터가 자율 발화
- 2명+일 때 GRADES.md의 호칭/존댓말 매트릭스 따라야 함
- events.json의 날짜 트리거 (생일 등)

#### 하트비트 시스템의 정교한 설계

활성 시점의 `HEARTBEAT.md`를 기준으로, 단순 cron이 아니라 다음 컴포넌트로 구성:

**1. 트리거 메커니즘 (절대 시각 기반)**

매 시간 정확히 1회 발화 보장 + 발화 시각은 매시 랜덤. 동작:

```
매시 0분: randomizer 크론이 0~59 사이 랜덤 N 결정
         → /tmp/openclaw-heartbeat-threshold.txt에 저장

매 1분: checker 크론이 현재 분(M) 체크
         → M >= N이면 발화 실행
         → 발화 후 threshold를 999로 오버라이드 (같은 시간 중복 차단)

매시 0분 다시: 새 N 결정 (자동 리셋)
```

예시 (N=47인 시간):
```
13:00 randomizer: N=47 결정
13:01~13:46: M < 47, 발화 안 함
13:47: M >= 47, 발화! threshold를 999로 오버라이드
13:48~13:59: M >= 47이지만 N=999, 발화 안 함
14:00: randomizer: 새 N 결정 (예: 23)
14:23: 발화!
```

**이 설계의 장점**:
- 시간당 발화 횟수가 정확히 예측됨 (비용 예측 쉬움)
- 누적 드리프트 없음 (매 시간 리셋)
- 발화 시각이 인간에게 자연스럽게 분산됨
- 999 오버라이드로 같은 시간 중복 발화 명시적 차단

**상태 파일**:
- `/tmp/openclaw-heartbeat-threshold.txt` — 현재 시간의 N 값 (또는 999)
- `/tmp/openclaw-last-speaker.txt` — 마지막 발화자 (반복 방지용)
- `/tmp/openclaw-heartbeat-alive.txt` — 워치독용 생존 신호

**2. 비활성 시간**
- 21시 ~ 10시 KST: 발화 안 함 (수면 시간)
- 21시 ~ 11:04 KST: 워치독 체크 안 함

**3. 산술 랜덤 (모델 판단 금지)**
- 모드: `$(date +%s) % 2` → 솔로(0) / 대화(1)
- 캐릭터: shell `shuf` 명령으로 진짜 랜덤 (`/dev/urandom` 기반)
- 마지막 발화자 제외 (`/tmp/openclaw-last-speaker.txt`)
- LLM에게 랜덤 결정 맡기지 않음 (LLM의 "랜덤"은 토큰 분포 편향)

**`shuf` 사용 이유 (참고)**:
- 이전에 `date +%s%N | tail -c 4` 방식 시도했으나 분포 편향 문제 발견
- 운영 중 검증되어 `shuf`로 회귀
- Java 마이그레이션 시 `ThreadLocalRandom.current().nextInt()` 또는 `SecureRandom` 사용 가능

**4. 출력 통제 (핵심)**
- LLM은 단일 토큰 `HEARTBEAT_OK`만 반환
- "발화했습니다" 같은 chatty 응답 절대 금지
- LLM 출력이 메인 봇 채널에 노출되지 않게 차단

**5. 워치독 (`heartbeat-watchdog.sh`, */15분 cron)**
- 실패 판단: 일정 기준 충족 시 게이트웨이 재시작
- 1~2회차: 경고만
- 3회차: 게이트웨이 자동 재시작 + 상태 리셋 + 알림

**6. 캐릭터 간 대화 모드**
- 캐릭터 A → B 순서로 2~3턴 이내
- GRADES.md의 호칭/존댓말 매트릭스 적용 (A→B와 B→A 다를 수 있음)
- 같은 유닛이면 유닛 맥락, 다른 유닛이면 교차 관계
- 주제: 일상 잡담, 취미, 음식, 근황 등

**마이그레이션 우선순위**: 하트비트는 **Phase 3 이후**로 미룸. 이유:
- 사용자 트래픽 직접 영향 없음 (background 작업)
- 라우터 마이그레이션 검증 후 안전하게 작업 가능
- 라우터의 시스템 프롬프트 설계가 검증되면 하트비트는 비슷한 패턴으로 빠르게 구현 가능

Phase 1~3에서는 OpenClaw 하트비트를 그대로 두고, 라우터만 Spring Boot로. 라우터가 안정되면 Phase 3.5 또는 4에서 하트비트 분리 검토.

#### Phase 3.5에서 하트비트 마이그레이션 시 핵심 변환

OpenClaw에서 LLM이 shell exec로 모든 작업하던 패턴을 **Java가 결정 로직 담당, LLM은 텍스트 생성만**으로 변환:

```java
@Service
@RequiredArgsConstructor
public class HeartbeatService {
    
    private final RandomGenerator random;
    private final HeartbeatStateStore state;       // Redis 기반
    private final GradesMatrix grades;              // GRADES.md 파싱 결과
    private final EventsCalendar events;            // events.json 파싱 결과
    private final ClaudeClient claude;
    private final ProxySpeechService proxySpeech;
    private final HeartbeatNotifier notifier;       // 워치독 알림
    
    /**
     * 매시 0분: 다음 한 시간 동안의 발화 시각(분) 결정
     * 0~59 사이 랜덤 값. 999면 이미 이번 시간 발화 완료.
     */
    @Scheduled(cron = "0 0 * * * *", zone = "Asia/Seoul")
    public void rerollThreshold() {
        int n = random.nextInt(0, 60);  // 0~59
        state.setThreshold(n);
        log.info("New heartbeat threshold for this hour: {}", n);
    }
    
    /**
     * 매 분: 현재 분이 threshold 이상이면 발화
     * 발화 후 threshold를 999로 오버라이드 (같은 시간 중복 차단)
     */
    @Scheduled(cron = "0 * * * * *", zone = "Asia/Seoul")
    public void heartbeatCheck() {
        if (isQuietHours()) return;       // 21~10시 KST
        
        int threshold = state.getThreshold();  // 현재 시간의 N
        int currentMinute = LocalTime.now(KST).getMinute();
        
        if (currentMinute < threshold) return;  // 아직 발화 시각 아님
        if (threshold == 999) return;            // 이미 발화 완료
        
        // 이벤트 오버라이드 체크 (생일 등)
        EventOverride override = events.todayOverride();
        if (override != null) {
            executeOverride(override);
            state.setThreshold(999);  // 중복 차단
            return;
        }
        
        executeNormalHeartbeat();
        state.setThreshold(999);  // 중복 차단
    }
    
    /**
     * 매 15분: 워치독
     */
    @Scheduled(cron = "0 */15 * * * *", zone = "Asia/Seoul")
    public void watchdog() {
        if (isWatchdogQuietHours()) return;
        WatchdogStatus status = computeStatus();
        if (status.isFailed()) handleFailure(status);
    }
    
    private void executeNormalHeartbeat() {
        boolean dialogue = random.nextBoolean();
        Character speaker = pickSpeaker(state.getLastSpeaker());
        Character partner = dialogue ? pickPartner(speaker) : null;
        
        String message = claude.generateUtterance(
            speaker, 
            partner == null ? null : grades.howAddresses(speaker, partner),
            UtteranceContext.casual()
        );
        
        proxySpeech.sendAs(speaker, SEKAI_CHANNEL_ID, message);
        
        if (dialogue) {
            String reply = claude.generateUtterance(
                partner,
                grades.howAddresses(partner, speaker),
                UtteranceContext.replyTo(message)
            );
            proxySpeech.sendAs(partner, SEKAI_CHANNEL_ID, reply);
        }
        
        state.markFired(speaker);  // alive.txt + last-speaker 갱신
    }
    
    private boolean isQuietHours() {
        int hour = LocalTime.now(KST).getHour();
        return hour >= 21 || hour < 10;
    }
}
```

**핵심 변환 원칙**:
- shell script 로직 → Java/Spring Boot
- `/tmp/*.txt` 상태 파일 → Redis key (또는 DB)
- shell `shuf`/`$RANDOM` → `ThreadLocalRandom` 또는 `SecureRandom`
- LLM은 캐릭터 대사 생성만 (1회당 ~200~500 토큰)
- 출력 검증 강화: `HEARTBEAT_OK` 같은 단일 토큰 반환 안 시키고, 그냥 string 반환받아서 Java가 검증

**예상 비용 (Sonnet 4.6 기준 — 추정치, 실제 가격표 재확인 필수)**:
- 시스템 프롬프트 5,000 토큰 (캐시): $0.0015
- 사용자 프롬프트 500 토큰: $0.0015
- 출력 200 토큰: $0.003
- 1회 호출: ~$0.006

**일일 호출 횟수**:
- 활성 시간: 10시~21시 = 11시간
- 시간당 1회 발화 (절대 시각 기반)
- 솔로 모드: 1회 호출, 대화 모드: 2회 호출 (50:50 가정 시 평균 1.5회)
- 일일 평균: 11 × 1.5 = ~16.5회

**총 비용 (추정치)**: 16.5회 × $0.006 = **$0.10/일 ≈ $3/월**

절대 시각 기반 트리거라 빈도가 명확히 예측 가능한 게 장점. 단, 위 단가·총액은 모두 추정치 — 마이그레이션 전 Anthropic 콘솔에서 실측치로 baseline 확보 필수.

#### GRADES.md 매트릭스 파싱

하트비트 마이그레이션의 가장 큰 도전. 7명 × 6명 = 42개 호칭 관계 정확히 적용해야:

```java
public record AddressForm(
    String addressTerm,    // 예: "에무쨩", "아이리"
    SpeechLevel level,      // POLITE, CASUAL
    String tonality         // 예: "장난스럽게", "차분하게"
) {}

@Component
@RequiredArgsConstructor
public class GradesMatrix {
    
    private final Path gradesFile = Path.of(Constants.IDENTITIES_DIR, "GRADES.md");
    private volatile Map<String, AddressForm> matrix;
    private long lastModified;
    
    @PostConstruct
    public void load() throws IOException {
        reload();
    }
    
    @Scheduled(fixedDelay = 60_000)
    public void watchForChanges() throws IOException {
        long current = Files.getLastModifiedTime(gradesFile).toMillis();
        if (current > lastModified) {
            reload();
            log.info("GRADES.md reloaded at {}", Instant.now());
        }
    }
    
    public AddressForm howAddresses(Character from, Character to) {
        return matrix.get(key(from, to));
    }
    
    private void reload() throws IOException {
        // GRADES.md 마크다운 표 파싱
        // 행: from 캐릭터, 열: to 캐릭터, 셀: 호칭 정보
        // 이 파싱 로직이 GRADES.md 형식에 따라 다름
    }
}
```

**파싱 전략**: GRADES.md를 직접 읽고 형식 확인 후 결정. 단순 마크다운 표면 정규식, 복잡하면 commonmark-java 같은 라이브러리.

## 마이그레이션 전략

### 전체 그림

```
[Phase 1] 라우터 봇 PoC (1주)
  → 1개 채널만 병행 운영, 기능 검증
  → OpenClaw 하트비트/세카이 봇은 그대로

[Phase 2] 라우터 봇 비교 운영 (1~2주)
  → 응답 품질 + 비용 + 라우팅 정확도 측정

[Phase 3] 라우터 봇 전체 컷오버 (1~2주)
  → 채널별 점진 전환
  → OpenClaw에서 sekai-router 에이전트만 비활성화 (main 에이전트/하트비트 유지)

[Phase 3.5] 하트비트 분리 (선택, 1~2주)
  → events.json 기반 cron 스케줄 직접 구현
  → GRADES.md 매트릭스 파서
  → 자율 발화 시스템 프롬프트 분리

[Phase 4] 세카이 봇 분리 (선택, 2~4주)
  → main 에이전트 → Spring Boot 이전
  → Anthropic Tool use로 파일 편집 도구 직접 구현
  → identities/, GRADES.md, events.json, quick-ref.md 모두 편집 가능

[Phase 5] OpenClaw 완전 제거 (1주)
  → 잔여 정리, 모니터링 도구 마무리
```

### Phase별 성공 기준

**Phase 1 완료 조건**:
- Spring Boot 앱이 단일 채널에서 라우터 봇으로 동작
- 기명 호출 정확히 라우팅
- 무기명 호출 시 랜덤 + 멀티턴 동작
- 다중 호명 시 다중 응답

**Phase 2 완료 조건**:
- OpenClaw 라우터 vs Spring Boot 라우터 응답 품질 비교 데이터 확보
- 메시지당 토큰 사용량 비교 (Anthropic 콘솔 데이터 기반)
- 라우팅 정확도 차이 측정
- 비용 절감 정량화 (목표: 5배 이상)

**Phase 3 완료 조건**:
- 모든 채널이 Spring Boot 라우터로 전환
- OpenClaw의 sekai-router 에이전트 비활성화
- 1주 이상 무중단 운영

**Phase 4 완료 조건**:
- 세카이 봇(= main 에이전트)이 Spring Boot에서 동작
- File edit tool이 sandboxing과 함께 작동
- 페르소나 변경이 라우터 봇에 반영되는 루프 검증

**Phase 5 완료 조건**:
- OpenClaw 프로세스 종료
- 모든 봇이 Spring Boot 인스턴스로 운영
- 모니터링/알림 체계 구축

## Phase 1 상세 (먼저 이것부터 완료)

### 사용 기술 스택

- **Java 24** (사이드 프로젝트 기본, MaiT 선호)
- **Spring Boot 3.x**
- **JDA 5.x** (Discord API)
- **Anthropic Java SDK** (`com.anthropic:anthropic-java`)
- **Redis** (대화 컨텍스트 캐싱, 옵션이지만 권장)
- **Gradle Kotlin DSL**
- **GitLab** (회사에서 자체 호스팅 GitLab 사용 - 사이드 프로젝트도 동일하게 사용 가능)

### 프로젝트 구조

```
sekai-router/
├── build.gradle.kts
├── settings.gradle.kts
├── .env.example
├── src/main/java/com/maitmus/sekairouter/
│   ├── SekaiRouterApplication.java
│   ├── config/
│   │   ├── DiscordConfig.java       # JDA Bean 설정 (라우터 봇 + 7개 캐릭터 봇)
│   │   ├── AnthropicConfig.java     # Anthropic SDK 설정
│   │   └── RedisConfig.java         # 대화 컨텍스트 Redis 설정
│   ├── discord/
│   │   ├── RouterEventListener.java # 라우터 봇 메시지 수신
│   │   └── PersonaBotRegistry.java  # 7개 캐릭터 봇 인스턴스 관리
│   ├── routing/
│   │   ├── RouterService.java       # 핵심 라우팅 로직
│   │   ├── RoutingDecision.java     # 라우팅 결과 DTO
│   │   ├── RoutingDecision$Mode.java # SINGLE, MULTI, NO_REPLY
│   │   └── PersonaResponse.java     # 캐릭터 + 응답 메시지
│   ├── persona/
│   │   ├── PersonaLoader.java       # identities/*.md 파일 로드
│   │   ├── PersonaWatcher.java      # 파일 변경 감지 + 캐시 무효화
│   │   └── SystemPromptBuilder.java # 라우터 시스템 프롬프트 생성
│   ├── memory/
│   │   ├── ConversationMemory.java  # Redis 기반 채널별 대화 저장
│   │   └── ConversationTurn.java    # 발화 단위
│   └── proxy/
│       └── ProxySpeechService.java  # 페르소나 봇 토큰으로 대리 발화
├── src/main/resources/
│   ├── application.yml
│   └── prompts/
│       └── router-base.md            # 라우터 정적 시스템 프롬프트 (캐릭터 정의 제외)
└── src/test/java/...
```

### 핵심 구현 가이드라인

**1. 시스템 프롬프트 분리 전략**

비용 효율의 핵심. 정적 부분(캐시됨) + 동적 부분(매번 다름) 명확히 분리.

```
[시스템 프롬프트 - 캐시됨, ~8000 토큰]
- 라우터 역할 정의
- 라우팅 규칙 (기명/무기명/멀티턴/다중/리액션 depth 2)
- 7개 캐릭터 페르소나 (identities/*.md 통합)
- 출력 JSON 스키마

[유저 프롬프트 - 매번 다름, ~500 토큰]
- 채널의 최근 발화 5개
- 새 메시지
- 판단 요청
```

페르소나 파일은 시작 시 로드 + 파일 변경 감지로 무효화. 매 호출마다 파일 읽지 말 것.

**2. 라우팅 출력 형식**

LLM이 한 번의 호출로 라우팅 결정 + 응답 생성을 동시에 하도록 JSON 출력:

```json
{
  "decision": "single | multi | no_reply",
  "responses": [
    {
      "character": "emu",
      "message": "에무는 잘 모르는 거에요!"
    }
  ],
  "reasoning": "이전 대화에서 에무가 응답 중이었고, 새 메시지가 화제 이어짐"
}
```

`responses`는 빈 배열 가능 (no_reply 케이스), 1개 (single), 2개+ (multi).

**3. 멀티턴 컨텍스트 관리**

Redis로 채널별 최근 발화 N개 (권장 5~10개) 보관:

- TTL은 메모리 관리 목적으로만 사용 (예: 24시간). 시간 기반 "새 대화" 컷오버 없음 — `last-speaker.txt` 상당의 직전 발화자 키 + 라우터 LLM의 맥락 판단으로 멀티턴/전환 결정
- 발화자 표시: `user`, `emu`, `nene` 등 (실제 캐릭터 7명 중 하나)
- 컨텍스트 길이 제한 (토큰 비용)

**4. 대리 발화 구현**

각 캐릭터 봇의 JDA 인스턴스를 미리 로드해두고, 채널 ID 매칭으로 메시지 전송:

```java
// PersonaBotRegistry에 7개 JDA 인스턴스 보관 (airi/emu/haruka/miku/minori/nene/shizuku)
// 라우터가 메시지 받은 채널과 같은 채널을 캐릭터 봇에서 찾아서 sendMessage
```

**중요**: 캐릭터 봇이 해당 Discord 길드에 가입되어 있어야 채널 접근 가능. 라우터 봇 + 7개 캐릭터 봇 모두 같은 길드에 있어야 함.

**4-1. 운영 매커니즘 (OpenClaw 현행 운영에서 이전)**

OpenClaw에서 실제로 운영 중인 다음 매커니즘들은 마이그레이션 시 동등 기능을 제공해야 함:

- **Typing indicator**: 발화 직전 백그라운드로 typing 표시 시작, 발화 완료 시 종료. OpenClaw에서는 lock 파일(`/tmp/sekai-typing-lock-<id>`) + `sekai-typing-loop.sh`로 구현. JDA에서는 `channel.sendTyping().queue()`를 발화 생성 동안 주기적으로(약 5초마다) 호출해서 동등 효과
- **전원 발화 ("다들/모두/전원/다같이")**: OpenClaw에서는 `sekai-all-speak.sh`가 캐릭터 순서를 `shuf`로 셔플 + 캐릭터별 typing 시작 + 1~3초 간격 순차 발화. Spring Boot에서는 동일 흐름을 코드로 (`Collections.shuffle()` + `ScheduledExecutorService`로 간격 발화 + JDA typing API 병행)
- **연속 발화 방지**: 직전 발화자를 채널별 상태로 기록(Redis key 권장). 다음 무기명 호출 시 캐릭터 풀에서 제외하고 산술적 랜덤(`ThreadLocalRandom` 또는 `SecureRandom`) 선택. **LLM에게 무작위 선택 시키지 말 것** — 토큰 분포 편향 (RULES.md P2.3 참조)
- **발송 실패 시 재시도 금지**: 중복 발화 위험 → 실패 로그만 남기고 NO_REPLY (OpenClaw SOUL.md와 동일 정책)

**5. JDA 인텐트 설정**

```java
JDABuilder.createDefault(token)
    .enableIntents(GatewayIntent.GUILD_MESSAGES, GatewayIntent.MESSAGE_CONTENT)
    .build();
```

`MESSAGE_CONTENT`는 Discord 개발자 포털에서도 활성화 필요 (privileged intent).

**6. 환경 변수**

```env
ANTHROPIC_API_KEY=sk-ant-...

DISCORD_ROUTER_TOKEN=...
DISCORD_AIRI_TOKEN=...
DISCORD_EMU_TOKEN=...
DISCORD_HARUKA_TOKEN=...
DISCORD_MIKU_TOKEN=...
DISCORD_MINORI_TOKEN=...
DISCORD_NENE_TOKEN=...
DISCORD_SHIZUKU_TOKEN=...

# 페르소나 파일 단일 소스 — workspace/identities가 본체, workspace-sekai/identities는 심볼릭 링크
PERSONA_DIR=/home/maitmus/.openclaw/workspace/identities

# 라우터가 처리할 세카이 채널 (Phase 1에서는 단일 채널 PoC)
SEKAI_CHANNEL_ID=1485510333115273339

REDIS_HOST=localhost
REDIS_PORT=6379

ANTHROPIC_MODEL=claude-haiku-4-5
ANTHROPIC_MAX_TOKENS=500
```

**7. 토큰 안전 처리**

`auth-profiles.json`에서 토큰 가져오지 말고, `.env` 또는 외부 secrets manager 사용. OpenClaw config를 직접 참조하면 안 됨.

### Phase 1 검증 시나리오

다음 케이스가 모두 통과해야 함 (캐릭터 예시는 실제 7명 중에서 사용):

```
시나리오 1: 기명 단발
입력: "에무, 안녕"
기대: 에무 봇이 응답

시나리오 2: 무기명 첫 대화
입력: "안녕"
기대: 랜덤 캐릭터가 응답 (last-speaker 제외 풀에서 산술적 랜덤)

시나리오 3: 무기명 멀티턴
이전: 에무가 응답 중
입력: "뭐 해?"
기대: 에무가 계속 응답 (직전 발화자 + 맥락 판단)

시나리오 4: 캐릭터 전환
이전: 에무가 응답 중
입력: "네네, 너는?"
기대: 네네가 응답

시나리오 5: 다중 호명
입력: "에무랑 네네, 안녕"
기대: 둘 다 응답

시나리오 6: 전원 호명
입력: "다들 안녕"
기대: 7명 전원이 셔플된 순서로 각각 응답

시나리오 7: 리액션 발화 (depth 2)
입력: "오늘 연습 힘들었어"
기대: 캐릭터 A 응답 후 다른 캐릭터 B가 자연스럽게 리액션 (유닛 동료가 반응할 만한 화제). depth 2 초과 금지

시나리오 8: NO_REPLY
입력: 봇과 무관한 일반 채팅 / 스티커 전용
기대: 라우터가 응답 안 함
```

### Phase 1에서 절대 하지 말 것

- 세카이 봇 기능 구현 (Phase 4 내용)
- 페르소나 파일 편집 기능 (Phase 4 내용)
- 모든 채널을 Spring Boot로 컷오버 (Phase 3 내용 — Phase 1은 단일 채널 PoC만)
- OpenClaw 종료 (Phase 5 내용)
- 모니터링/메트릭 시스템 과도한 구축 (검증 단계)

병행 운영이 핵심. 한 채널만 Spring Boot로, 나머지는 OpenClaw 그대로.

## 비용 측정 방법

### Baseline 측정 (마이그레이션 전 — 필수)

핸드오프 본문의 비용 수치(메시지당 15K~30K 토큰, 절감 목표 80~90%, 하트비트 $3/월 등)는 모두 **운영 추정치**. 마이그레이션 정당화를 위해 Phase 1 시작 전 일주일간 OpenClaw 실측 비용 데이터를 확보해 baseline을 고정해야 함:

1. Anthropic 콘솔 (https://console.anthropic.com/settings/usage) 일일 토큰 사용량 기록
2. 메시지당 평균 토큰 계산 (라우터 봇 / 세카이 봇 / 하트비트 분리 측정)
3. 캐시 적중률 확인
4. Input vs Output 비율

baseline이 없으면 Phase 2 비교 측정 단계에서 "절감했다"는 주장이 검증 불가능 → 마이그레이션 ROI 평가 자체가 불가.

### 비교 측정 (Phase 2 중)

Spring Boot 라우터 채널과 OpenClaw 라우터 채널의 메시지당 비용 비교:

```
메시지당 비용 = (input_uncached × $1/MTok) + (input_cached × $0.10/MTok) + (output × $5/MTok)
```

(Haiku 4.5 기준)

목표: Spring Boot가 OpenClaw 대비 **5배 이상 저렴**.

## 위험 요소 및 대응

### 위험 1: 라우팅 정확도 저하

**원인**: OpenClaw의 풀 컨텍스트 vs Spring Boot의 압축 컨텍스트
**대응**: Phase 2에서 정확도 측정, 시스템 프롬프트 점진 개선

### 위험 2: 페르소나 일관성 저하

**원인**: 7개 캐릭터 페르소나가 한 시스템 프롬프트에 들어가면 LLM이 혼동 가능
**대응**: 각 페르소나의 핵심 특징을 명확하게 구조화 (예: `### emu | 일인칭: 에무 | 말투: ~인 거에요`)

### 위험 3: JDA 라이브러리 한계

**원인**: 라우터 봇 + 7개 캐릭터 봇 = 8개 JDA 인스턴스 동시 운영의 메모리/리소스 부담
**대응**: 캐릭터 봇은 응답 전송에만 쓰니까 lazy 로드 검토. 또는 Discord HTTP API 직접 사용 (JDA 없이 webhook style).

### 위험 4: 세카이 봇의 자기 개선 중단

**원인**: 라우터 분리 시 세카이 봇이 라우터 응답을 못 보면 분석 불가
**대응**: 세카이 봇이 보는 헤드쿼터 채널은 OpenClaw에 그대로 두고, 라우터 봇만 분리. 둘 다 같은 세카이 채널을 보면 OK (라우터 봇 응답이 세카이 채널에 캐릭터 봇 이름으로 노출 → 세카이 봇이 헤드쿼터에서 해당 채널 읽기 가능).

### 위험 5: identities/*.md 동시 편집 충돌

**원인**: 세카이 봇이 OpenClaw에서 파일 편집 중에 Spring Boot 라우터가 같은 파일 읽으려 할 때
**대응**: PersonaWatcher가 파일 mtime 감지로 캐시 무효화. 짧은 시간(분 단위)의 비동기 갱신 허용. 본체는 `~/.openclaw/workspace/identities/`이고 `workspace-sekai/identities`는 심볼릭 링크라 단일 소스 → 동시 쓰기 충돌 자체는 atomic write 패턴(임시파일 → rename)으로 회피 가능.

### 위험 6: 하트비트와 라우터의 페르소나 일관성

**원인**: 하트비트는 OpenClaw에서, 라우터 봇은 Spring Boot에서 돌면 페르소나 정의를 다르게 해석할 수 있음
**대응**: 둘 다 같은 `identities/*.md` 파일 읽으니까 정의는 같음. 다만 시스템 프롬프트 구성 방식이 다르면 응답 톤이 미묘하게 달라질 수 있음. Phase 2에서 모니터링 항목으로 추가.

### 위험 8: 공유 상태 파일 분리 (last-speaker)

**원인**: `/tmp/openclaw-last-speaker.txt`는 라우터 봇과 하트비트가 공유하는 상태 파일. 라우터 봇이 Spring Boot로 옮긴 뒤(Phase 3) 하트비트는 OpenClaw에 남아있는 상태에서, 두 시스템이 같은 캐릭터를 연속 발화시킬 위험.
**대응 (전환 기간)**:
- Phase 3 동안 Spring Boot 라우터 봇이 발화 후 동일 파일에 마지막 발화자를 기록하도록 호환 유지 (단순 텍스트 파일이라 구현 비용 작음)
- Phase 3.5에서 하트비트도 마이그레이션되면 양쪽 모두 Redis key로 통합
- 또는 Phase 3 시작 시 즉시 Redis key를 도입하고, OpenClaw 하트비트가 Redis를 읽고 쓰도록 작은 어댑터 추가

### 위험 7: GRADES.md 매트릭스 파싱

**원인**: Haiku가 GRADES.md 직접 못 읽어서 quick-ref.md가 만들어진 사례 = 모델 능력 한계 명확
**대응**: 
- 라우터가 Haiku 4.5라면 quick-ref.md만 시스템 프롬프트에 포함
- Sonnet 4.6이라면 GRADES.md 직접 사용 가능
- 모델 변경 시 어떤 메타 파일을 시스템 프롬프트에 넣을지 재검토 필요

## 코드 작성 시 따를 원칙

1. **Lombok 사용 OK**: `@RequiredArgsConstructor`, `@Slf4j` 등 회사 코드 스타일 따라감
2. **Records 활용**: Java 24니까 DTO는 `record` 우선
3. **Sealed types**: 라우팅 결과 같은 닫힌 enum은 sealed interface 검토
4. **테스트 우선**: 라우팅 규칙 8개 시나리오(기명/무기명/멀티턴/전환/다중/전원/리액션/NO_REPLY)는 단위 테스트로 작성
5. **에러 처리**: Anthropic API 실패, Discord API 실패 시 graceful degradation
6. **로깅**: 라우팅 결정마다 reasoning 로그 (디버깅 + 비용 분석)
7. **Spring Boot 표준**: `@Service`, `@Component`, `@ConfigurationProperties` 등 회사 코드 패턴

## 시작 시 첫 작업

이 핸드오프를 받으면 다음 순서로 작업:

1. **현재 OpenClaw 시스템 이해**

   OpenClaw 워크스페이스 구조:
   - `~/.openclaw/workspace/` — `main` 에이전트(= 세카이 봇) 워크스페이스. `identities/` 본체 보유
   - `~/.openclaw/workspace-sekai/` — `sekai-router` 에이전트(= 라우터 봇) 워크스페이스. `identities`는 위 본체로의 심볼릭 링크
   - `~/.openclaw/workspace-cron-worker/` — `cron-worker` 에이전트(머슴 자동화). 마이그레이션 범위 외
   - `~/.openclaw/workspace-emu/`, `~/.openclaw/workspace-nene/` — OpenClaw 기본 템플릿만 보유한 빈 워크스페이스 (캐릭터 봇은 토큰만 사용, LLM 비활성)

   확인 명령:
   - `cat ~/.openclaw/openclaw.json | jq '.agents'` 로 에이전트 정의 확인 (`main` / `sekai-router` / `cron-worker` 등)
   - `cat ~/.openclaw/openclaw.json | jq '.channels.discord'` 로 Discord 설정 확인 (라우터 봇 + 세카이 봇 + 캐릭터 7명 토큰)
   - `ls -la ~/.openclaw/workspace/identities/` 로 페르소나 파일 정확한 인벤토리 작성
   - `~/.openclaw/workspace/identities/*.md` 모두 읽기 (페르소나 정의 파악 — 7개)
   - `~/.openclaw/workspace/identities/GRADES.md` 읽기 — **캐릭터 간 호칭/존댓말 매트릭스** (하트비트 발화 시 필수)
   - `~/.openclaw/workspace/identities/events.json` 읽기 — **날짜 기반 하트비트 트리거**
   - `~/.openclaw/workspace/identities/quick-ref.md` 읽기 — **GRADES.md의 Haiku용 압축 요약본**
   - `~/.openclaw/workspace-sekai/SOUL.md`, `AGENTS.md` 읽기 — 라우터 봇의 실제 라우팅 절차 (typing-loop, sekai-all-speak.sh, last-speaker.txt 등)
   - `~/.openclaw/workspace/SOUL.md`, `RULES.md`, `AGENTS.md` 읽기 — 세카이 봇의 자기 개선 메커니즘
   - `~/.openclaw/workspace-sekai/HEARTBEAT.md` 읽기 — 현재는 빈 템플릿. 활성 시점의 정의는 본 핸드오프 "하트비트 시스템의 정교한 설계" 섹션 참조
   - 위 파일들을 통해 **3개 LLM 사용 지점**(라우터 봇, 세카이 봇, 하트비트) 각각의 시스템 프롬프트 구조 파악

2. **베이스라인 측정 시작**
   - Anthropic 콘솔에서 최근 7일 토큰 사용량 기록 요청 (사용자에게)
   - 측정용 스프레드시트 또는 JSON 파일 준비
   - **이 단계 없이는 Phase 2 비교 측정이 무의미** → 마이그레이션 ROI 검증 불가

3. **Spring Boot 프로젝트 골격 생성**
   - `start.spring.io` 또는 직접 build.gradle.kts 작성
   - 의존성 추가 (Spring Boot, JDA, Anthropic, Redis)
   - 기본 디렉토리 구조

4. **단일 봇 PoC 동작 확인**
   - 라우터 봇 토큰만으로 JDA 연결
   - 메시지 받으면 콘솔 출력만
   - 이게 되면 다음 단계

5. **Anthropic SDK 호출 테스트**
   - 하드코딩된 시스템 프롬프트로 분류 작업 1번
   - 응답 파싱 (JSON 출력 형식)

6. **점진 기능 추가**
   - 페르소나 로더 (7개 캐릭터)
   - 컨텍스트 메모리 (인메모리부터, Redis는 나중에)
   - 대리 발화 + typing indicator
   - 8개 시나리오 검증

## 사용자(MaiT)와의 소통

- **Korean (한국어)** 사용
- **명확한 단계 보고**: 각 단계 시작/완료 시 한 줄 요약
- **결정 필요 시 질문**: 라이브러리 선택, 디자인 결정 등
- **막혔을 때**: 에러 메시지 + 시도한 것 보여주고 도움 요청
- **MaiT의 회사 환경**: Java 8 (Spring Boot 백엔드)이지만 사이드 프로젝트는 Java 17+ (주로 24)
- **MaiT의 인프라**: 자체 호스팅 GitLab (회사용), Pi 5 (개인 OpenClaw 운영), 회사 맥 M3 Pro 18GB

## 참고 자료

- Anthropic Java SDK: https://github.com/anthropics/anthropic-sdk-java
- JDA 5.x: https://github.com/discord-jda/JDA
- Anthropic Prompt Caching: https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching
- Anthropic Tool Use: https://docs.anthropic.com/en/docs/build-with-claude/tool-use

## 작업 완료 보고 형식

각 Phase 완료 시 다음 형식으로 보고:

```markdown
## Phase X 완료 보고

### 완료된 작업
- ...

### 검증 결과
- 8개 시나리오 통과 여부
- 비용 측정 데이터 (있으면)
- 알려진 이슈

### 다음 Phase 준비
- 사용자 결정 필요 사항
- 추가 정보 요청

### 남은 작업
- ...
```

---

**핸드오프 종료. Phase 1부터 시작.**
