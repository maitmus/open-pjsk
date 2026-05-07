# Sekai Router Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** OpenClaw 기반 sekai-router 에이전트의 라우팅 기능을 Spring Boot + JDA + Anthropic Java SDK로 재구현. 단일 채널에서 OpenClaw와 병행 운영하며 8개 검증 시나리오 통과 시 Phase 1 종료.

**Architecture:** Spring Boot 단일 프로세스가 라우터 봇 1개 + 캐릭터 봇 7개의 JDA 인스턴스를 관리. 라우터 봇이 메시지를 받으면 Anthropic SDK 단일 호출로 라우팅 결정과 대사 생성을 동시에 받아(JSON 출력) 캐릭터 봇 토큰으로 대리 발화. 컨텍스트는 인메모리 ConcurrentHashMap에 채널별 최근 N개 발화로 보관.

**Tech Stack:**
- Java 24, Spring Boot 3.4.x, Gradle Kotlin DSL
- JDA 5.x (Discord), Anthropic Java SDK (`com.anthropic:anthropic-java`)
- Lombok (`@RequiredArgsConstructor`, `@Slf4j`)
- JUnit 5 + Mockito + AssertJ
- 인메모리 메모리 (Redis는 Phase 2 이후)
- 모델: Haiku 4.5 (`claude-haiku-4-5`) — 저비용 우선, 정확도는 Phase 2에서 측정

**Spec 참조:** `migration-handoff.md` (commit 8e3167d 이후) — 특히 라우팅 규칙(line 78~107), 운영 매커니즘(typing/sekai-all-speak/last-speaker), 8개 검증 시나리오.

**프로젝트 위치:** 별도 GitHub 리포(`maitmus/open-pjsk-spring-migration`)에 생성. 페르소나 파일은 OpenClaw 워크스페이스(`~/.openclaw/workspace/identities/`)를 환경변수로 참조 — Spring Boot가 이 경로의 파일을 read-only로 사용.

---

## File Structure

```
open-pjsk-spring-migration/
├── README.md
├── .gitignore
├── .env.example
├── build.gradle.kts
├── settings.gradle.kts
├── src/main/java/com/maitmus/sekairouter/
│   ├── SekaiRouterApplication.java         # @SpringBootApplication
│   ├── config/
│   │   ├── DiscordProperties.java          # @ConfigurationProperties("discord")
│   │   ├── AnthropicProperties.java        # @ConfigurationProperties("anthropic")
│   │   ├── PersonaProperties.java          # @ConfigurationProperties("persona")
│   │   └── DiscordConfig.java              # 라우터 봇 + 7개 캐릭터 봇 JDA Bean
│   ├── persona/
│   │   ├── CharacterId.java                # enum: AIRI/EMU/HARUKA/MIKU/MINORI/NENE/SHIZUKU
│   │   ├── Persona.java                    # record(id, displayName, content)
│   │   ├── PersonaLoader.java              # identities/*.md 파싱
│   │   ├── PersonaRegistry.java            # 로드된 페르소나 캐시
│   │   └── PersonaWatcher.java             # mtime 변경 감지 + 캐시 무효화
│   ├── routing/
│   │   ├── RoutingDecision.java            # sealed interface (Single, Multi, NoReply)
│   │   ├── PersonaResponse.java            # record(character, message)
│   │   ├── RouterRequest.java              # record(channelId, recentTurns, newMessage)
│   │   ├── RouterService.java              # Anthropic 호출 + JSON 파싱
│   │   ├── SystemPromptBuilder.java        # 정적 시스템 프롬프트 생성 (캐시 대상)
│   │   └── RandomCharacterSelector.java    # last-speaker 제외 산술 랜덤
│   ├── memory/
│   │   ├── ConversationTurn.java           # record(speaker, content, timestampSec)
│   │   └── ConversationMemory.java         # 채널별 최근 N개 인메모리 캐시
│   ├── proxy/
│   │   ├── ProxySpeechService.java         # 캐릭터 봇 토큰으로 발화
│   │   ├── TypingIndicatorService.java     # JDA sendTyping 주기 호출
│   │   └── LastSpeakerStore.java           # 채널별 직전 발화자 인메모리 저장
│   └── discord/
│       └── RouterEventListener.java        # 메시지 수신 → 라우팅 → 발화 통합
├── src/main/resources/
│   ├── application.yml
│   └── prompts/
│       ├── router-base-instructions.md      # 라우팅 규칙 정적 부분
│       └── output-schema.md                 # JSON 출력 스키마 명세
└── src/test/java/com/maitmus/sekairouter/
    ├── persona/
    │   ├── PersonaLoaderTest.java
    │   └── PersonaWatcherTest.java
    ├── routing/
    │   ├── RouterServiceTest.java
    │   ├── SystemPromptBuilderTest.java
    │   └── RandomCharacterSelectorTest.java
    ├── memory/
    │   └── ConversationMemoryTest.java
    └── proxy/
        └── LastSpeakerStoreTest.java
```

**파일 분할 원칙:** 클래스당 단일 책임, 라우터 결정 로직(`RouterService`)과 발화(`ProxySpeechService`) 분리, 페르소나 로더와 시스템 프롬프트 빌더 분리(LLM 모델 변경 시 빌더만 교체 가능).

---

## Task 1: GitHub 리포 초기화

**Files:**
- Create: `~/projects/open-pjsk-spring-migration/README.md`
- Create: `~/projects/open-pjsk-spring-migration/.gitignore`

**Manual prerequisite:** 사용자가 GitHub에서 `maitmus/open-pjsk-spring-migration` 리포 생성 (Private/Public 자유). 빈 리포여야 함.

- [ ] **Step 1: 로컬 디렉토리 생성**

```bash
mkdir -p ~/projects/open-pjsk-spring-migration && cd ~/projects/open-pjsk-spring-migration
```

- [ ] **Step 2: README.md 작성**

```markdown
# open-pjsk-spring-migration

OpenClaw 기반 sekai-router 에이전트의 Spring Boot 마이그레이션. Discord 메시지를 받아 Project Sekai 캐릭터로 라우팅 + 대리 발화.

## 개요
- 라우터 봇 1개 (LLM 호출) + 캐릭터 봇 7개 (대리 발화 대상)
- Anthropic Claude Haiku 4.5
- 자세한 마이그레이션 컨텍스트: [open-pjsk/migration-handoff.md](https://github.com/maitmus/open-pjsk/blob/main/migration-handoff.md)

## 빌드
```
./gradlew build
```

## 실행
```
./gradlew bootRun
```
```

- [ ] **Step 3: .gitignore 작성**

```gitignore
# Gradle
.gradle/
build/
!gradle/wrapper/gradle-wrapper.jar
!**/src/main/**/build/
!**/src/test/**/build/

# IDE
.idea/
*.iml
.vscode/

# Spring Boot
HELP.md

# Env
.env
.env.local

# OS
.DS_Store
```

- [ ] **Step 4: 첫 commit + GitHub 연결**

```bash
git init -b main
git add README.md .gitignore
git commit -m "init: 리포지토리 초기화"
git remote add origin git@github.com:maitmus/open-pjsk-spring-migration.git
git push -u origin main
```

Expected: GitHub에 `main` 브랜치로 푸시 성공.

---

## Task 2: Gradle Kotlin DSL + Spring Boot 골격

**Files:**
- Create: `settings.gradle.kts`
- Create: `build.gradle.kts`
- Create: `gradle/wrapper/gradle-wrapper.properties`

- [ ] **Step 1: Gradle wrapper 생성**

```bash
cd ~/projects/open-pjsk-spring-migration
gradle wrapper --gradle-version 8.10
```

(Gradle이 시스템에 없으면 `sdk install gradle 8.10` 또는 zip 다운로드)

Expected: `gradlew`, `gradlew.bat`, `gradle/wrapper/gradle-wrapper.jar`, `gradle/wrapper/gradle-wrapper.properties` 생성됨.

- [ ] **Step 2: settings.gradle.kts 작성**

```kotlin
rootProject.name = "open-pjsk-spring-migration"
```

- [ ] **Step 3: build.gradle.kts 작성**

```kotlin
plugins {
    java
    id("org.springframework.boot") version "3.4.1"
    id("io.spring.dependency-management") version "1.1.7"
}

group = "com.maitmus"
version = "0.0.1-SNAPSHOT"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(24)
    }
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.springframework.boot:spring-boot-starter")
    implementation("org.springframework.boot:spring-boot-starter-validation")

    // Discord
    implementation("net.dv8tion:JDA:5.2.1")

    // Anthropic
    implementation("com.anthropic:anthropic-java:0.8.0")

    // JSON
    implementation("com.fasterxml.jackson.module:jackson-module-parameter-names")

    // Lombok
    compileOnly("org.projectlombok:lombok")
    annotationProcessor("org.projectlombok:lombok")

    // Spring Config
    annotationProcessor("org.springframework.boot:spring-boot-configuration-processor")

    // Test
    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation("org.assertj:assertj-core")
    testImplementation("org.mockito:mockito-junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.withType<Test> {
    useJUnitPlatform()
}
```

- [ ] **Step 4: 빌드 확인**

```bash
./gradlew build --no-daemon
```

Expected: BUILD SUCCESSFUL (테스트 0개, 컴파일 0 클래스).

- [ ] **Step 5: Commit**

```bash
git add settings.gradle.kts build.gradle.kts gradlew gradlew.bat gradle/
git commit -m "build: Gradle Kotlin DSL + Spring Boot 3.4 + JDA + Anthropic SDK 의존성"
```

---

## Task 3: 메인 애플리케이션 클래스 + application.yml

**Files:**
- Create: `src/main/java/com/maitmus/sekairouter/SekaiRouterApplication.java`
- Create: `src/main/resources/application.yml`
- Create: `.env.example`

- [ ] **Step 1: SekaiRouterApplication.java 작성**

```java
package com.maitmus.sekairouter;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@ConfigurationPropertiesScan
@EnableScheduling
public class SekaiRouterApplication {
    public static void main(String[] args) {
        SpringApplication.run(SekaiRouterApplication.class, args);
    }
}
```

- [ ] **Step 2: application.yml 작성**

```yaml
spring:
  application:
    name: open-pjsk-spring-migration
  main:
    web-application-type: none

logging:
  level:
    root: INFO
    com.maitmus.sekairouter: DEBUG
    net.dv8tion.jda: WARN

discord:
  router-token: ${DISCORD_ROUTER_TOKEN:}
  sekai-channel-id: ${SEKAI_CHANNEL_ID:}
  character-tokens:
    AIRI: ${DISCORD_AIRI_TOKEN:}
    EMU: ${DISCORD_EMU_TOKEN:}
    HARUKA: ${DISCORD_HARUKA_TOKEN:}
    MIKU: ${DISCORD_MIKU_TOKEN:}
    MINORI: ${DISCORD_MINORI_TOKEN:}
    NENE: ${DISCORD_NENE_TOKEN:}
    SHIZUKU: ${DISCORD_SHIZUKU_TOKEN:}

anthropic:
  api-key: ${ANTHROPIC_API_KEY:}
  model: ${ANTHROPIC_MODEL:claude-haiku-4-5}
  max-tokens: ${ANTHROPIC_MAX_TOKENS:1000}

persona:
  dir: ${PERSONA_DIR:/home/maitmus/.openclaw/workspace/identities}
  watch-interval-ms: 60000
```

- [ ] **Step 3: .env.example 작성**

```env
# Anthropic
ANTHROPIC_API_KEY=sk-ant-...
ANTHROPIC_MODEL=claude-haiku-4-5
ANTHROPIC_MAX_TOKENS=1000

# Discord
DISCORD_ROUTER_TOKEN=...
DISCORD_AIRI_TOKEN=...
DISCORD_EMU_TOKEN=...
DISCORD_HARUKA_TOKEN=...
DISCORD_MIKU_TOKEN=...
DISCORD_MINORI_TOKEN=...
DISCORD_NENE_TOKEN=...
DISCORD_SHIZUKU_TOKEN=...

# Phase 1 PoC: 테스트용 별도 채널 ID 권장 (실제 세카이 채널은 OpenClaw가 처리 중)
SEKAI_CHANNEL_ID=...

# 페르소나 파일 위치 (OpenClaw 워크스페이스 단일 소스)
PERSONA_DIR=/home/maitmus/.openclaw/workspace/identities
```

- [ ] **Step 4: 빌드 + 실행 확인**

```bash
./gradlew bootRun
```

Expected: Spring Boot 시작 → "Started SekaiRouterApplication" 로그 출력 → Ctrl+C로 종료.

- [ ] **Step 5: Commit**

```bash
git add src/main/java src/main/resources .env.example
git commit -m "feat: Spring Boot 메인 애플리케이션 + application.yml + .env.example"
```

---

## Task 4: CharacterId enum + ConfigurationProperties

**Files:**
- Create: `src/main/java/com/maitmus/sekairouter/persona/CharacterId.java`
- Create: `src/main/java/com/maitmus/sekairouter/config/DiscordProperties.java`
- Create: `src/main/java/com/maitmus/sekairouter/config/AnthropicProperties.java`
- Create: `src/main/java/com/maitmus/sekairouter/config/PersonaProperties.java`

- [ ] **Step 1: CharacterId enum 작성**

```java
package com.maitmus.sekairouter.persona;

import java.util.Arrays;
import java.util.Optional;

public enum CharacterId {
    AIRI, EMU, HARUKA, MIKU, MINORI, NENE, SHIZUKU;

    public String fileName() {
        return name().toLowerCase() + ".md";
    }

    public static Optional<CharacterId> fromString(String s) {
        if (s == null) return Optional.empty();
        return Arrays.stream(values())
                .filter(c -> c.name().equalsIgnoreCase(s))
                .findFirst();
    }
}
```

- [ ] **Step 2: DiscordProperties.java 작성**

```java
package com.maitmus.sekairouter.config;

import com.maitmus.sekairouter.persona.CharacterId;
import jakarta.validation.constraints.NotBlank;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

import java.util.Map;

@Validated
@ConfigurationProperties("discord")
public record DiscordProperties(
        @NotBlank String routerToken,
        @NotBlank String sekaiChannelId,
        Map<CharacterId, String> characterTokens
) {}
```

- [ ] **Step 3: AnthropicProperties.java 작성**

```java
package com.maitmus.sekairouter.config;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

@Validated
@ConfigurationProperties("anthropic")
public record AnthropicProperties(
        @NotBlank String apiKey,
        @NotBlank String model,
        @Positive int maxTokens
) {}
```

- [ ] **Step 4: PersonaProperties.java 작성**

```java
package com.maitmus.sekairouter.config;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

@Validated
@ConfigurationProperties("persona")
public record PersonaProperties(
        @NotBlank String dir,
        @Positive long watchIntervalMs
) {}
```

- [ ] **Step 5: 빌드 + 실행 확인 (검증 작동 확인)**

```bash
unset DISCORD_ROUTER_TOKEN ANTHROPIC_API_KEY
./gradlew bootRun
```

Expected: 검증 실패 → "discord.routerToken: must not be blank" 등 메시지로 시작 거부됨.

- [ ] **Step 6: Commit**

```bash
git add src/main/java/com/maitmus/sekairouter/persona/CharacterId.java
git add src/main/java/com/maitmus/sekairouter/config/
git commit -m "feat: CharacterId enum + 검증된 ConfigurationProperties (Discord/Anthropic/Persona)"
```

---

## Task 5: PersonaLoader + Persona record

**Files:**
- Create: `src/main/java/com/maitmus/sekairouter/persona/Persona.java`
- Create: `src/main/java/com/maitmus/sekairouter/persona/PersonaLoader.java`
- Create: `src/test/java/com/maitmus/sekairouter/persona/PersonaLoaderTest.java`
- Create: `src/test/resources/persona-fixtures/airi.md`
- Create: `src/test/resources/persona-fixtures/emu.md`

- [ ] **Step 1: Persona record 작성**

```java
package com.maitmus.sekairouter.persona;

public record Persona(
        CharacterId id,
        String displayName,
        String content
) {}
```

- [ ] **Step 2: PersonaLoaderTest 작성 (failing test)**

테스트 픽스처 먼저 — `src/test/resources/persona-fixtures/airi.md`:
```markdown
# IDENTITY - 모모이 아이리

- **Name:** 모모이 아이리 (Airi Momoi)
- **Aliases:** 아이리, 모모이, Airi

## Character Notes
- 당당하고 기 셈
```

`src/test/resources/persona-fixtures/emu.md`:
```markdown
# IDENTITY - 오오토리 에무

- **Name:** 오오토리 에무 (Emu Otori)
- **Aliases:** 에무, 오오토리, Emu
```

`PersonaLoaderTest.java`:
```java
package com.maitmus.sekairouter.persona;

import org.junit.jupiter.api.Test;

import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class PersonaLoaderTest {

    @Test
    void loadAll_returnsAllPersonasInDirectory() throws Exception {
        Path fixtureDir = Paths.get("src/test/resources/persona-fixtures");
        PersonaLoader loader = new PersonaLoader();

        Map<CharacterId, Persona> personas = loader.loadAll(fixtureDir);

        assertThat(personas).containsOnlyKeys(CharacterId.AIRI, CharacterId.EMU);
        assertThat(personas.get(CharacterId.AIRI).displayName()).isEqualTo("모모이 아이리");
        assertThat(personas.get(CharacterId.AIRI).content()).contains("당당하고 기 셈");
        assertThat(personas.get(CharacterId.EMU).displayName()).isEqualTo("오오토리 에무");
    }

    @Test
    void loadAll_skipsNonCharacterFiles() throws Exception {
        Path fixtureDir = Paths.get("src/test/resources/persona-fixtures");
        PersonaLoader loader = new PersonaLoader();

        // GRADES.md, quick-ref.md 등은 CharacterId 매칭 안 됨 → 스킵
        Map<CharacterId, Persona> personas = loader.loadAll(fixtureDir);

        assertThat(personas).hasSize(2);  // airi + emu만
    }
}
```

- [ ] **Step 3: 테스트 실행 → 실패 확인**

```bash
./gradlew test --tests PersonaLoaderTest
```

Expected: FAIL — `PersonaLoader` 클래스 없음.

- [ ] **Step 4: PersonaLoader 구현**

```java
package com.maitmus.sekairouter.persona;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.EnumMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

@Slf4j
@Component
public class PersonaLoader {

    private static final Pattern NAME_PATTERN = Pattern.compile(
            "^- \\*\\*Name:\\*\\*\\s*([^(]+?)\\s*(?:\\(.*\\))?\\s*$",
            Pattern.MULTILINE
    );

    public Map<CharacterId, Persona> loadAll(Path dir) throws IOException {
        Map<CharacterId, Persona> personas = new EnumMap<>(CharacterId.class);
        try (Stream<Path> stream = Files.list(dir)) {
            stream.filter(p -> p.toString().endsWith(".md"))
                  .forEach(p -> loadOne(p).ifPresent(persona ->
                          personas.put(persona.id(), persona)));
        }
        return personas;
    }

    private java.util.Optional<Persona> loadOne(Path file) {
        String fileName = file.getFileName().toString();
        String idPart = fileName.replace(".md", "");
        return CharacterId.fromString(idPart).flatMap(id -> {
            try {
                String content = Files.readString(file);
                String displayName = extractDisplayName(content).orElse(id.name());
                return java.util.Optional.of(new Persona(id, displayName, content));
            } catch (IOException e) {
                log.error("Failed to read persona file {}", file, e);
                return java.util.Optional.empty();
            }
        });
    }

    private java.util.Optional<String> extractDisplayName(String content) {
        Matcher m = NAME_PATTERN.matcher(content);
        return m.find() ? java.util.Optional.of(m.group(1).trim()) : java.util.Optional.empty();
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
./gradlew test --tests PersonaLoaderTest
```

Expected: PASS — 두 테스트 모두 성공.

- [ ] **Step 6: Commit**

```bash
git add src/main/java/com/maitmus/sekairouter/persona/Persona.java
git add src/main/java/com/maitmus/sekairouter/persona/PersonaLoader.java
git add src/test/
git commit -m "feat: PersonaLoader — identities/*.md 파일 → Persona record 매핑"
```

---

## Task 6: PersonaRegistry + PersonaWatcher (mtime 감지)

**Files:**
- Create: `src/main/java/com/maitmus/sekairouter/persona/PersonaRegistry.java`
- Create: `src/main/java/com/maitmus/sekairouter/persona/PersonaWatcher.java`
- Create: `src/test/java/com/maitmus/sekairouter/persona/PersonaWatcherTest.java`

- [ ] **Step 1: PersonaRegistry 구현 (단순 캐시)**

```java
package com.maitmus.sekairouter.persona;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.EnumMap;
import java.util.Map;

@Slf4j
@Component
@RequiredArgsConstructor
public class PersonaRegistry {

    private volatile Map<CharacterId, Persona> personas = new EnumMap<>(CharacterId.class);

    public Map<CharacterId, Persona> all() {
        return personas;
    }

    public Persona get(CharacterId id) {
        Persona p = personas.get(id);
        if (p == null) {
            throw new IllegalStateException("Persona not loaded: " + id);
        }
        return p;
    }

    public void replace(Map<CharacterId, Persona> next) {
        log.info("Persona registry replaced — {} entries", next.size());
        this.personas = Map.copyOf(next);
    }
}
```

- [ ] **Step 2: PersonaWatcherTest 작성**

```java
package com.maitmus.sekairouter.persona;

import com.maitmus.sekairouter.config.PersonaProperties;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

class PersonaWatcherTest {

    @Test
    void onStart_loadsAllPersonas(@TempDir Path tmp) throws IOException {
        Files.writeString(tmp.resolve("emu.md"), """
                # IDENTITY - 오오토리 에무
                - **Name:** 오오토리 에무 (Emu Otori)
                - **Aliases:** 에무
                """);
        PersonaProperties props = new PersonaProperties(tmp.toString(), 60_000);
        PersonaRegistry registry = new PersonaRegistry();
        PersonaWatcher watcher = new PersonaWatcher(props, new PersonaLoader(), registry);

        watcher.loadInitial();

        assertThat(registry.all()).containsKey(CharacterId.EMU);
    }

    @Test
    void detectsModification_reloads(@TempDir Path tmp) throws Exception {
        Path emuFile = tmp.resolve("emu.md");
        Files.writeString(emuFile, """
                # IDENTITY - 오오토리 에무
                - **Name:** 오오토리 에무 (Emu Otori)
                """);
        PersonaProperties props = new PersonaProperties(tmp.toString(), 60_000);
        PersonaRegistry registry = new PersonaRegistry();
        PersonaWatcher watcher = new PersonaWatcher(props, new PersonaLoader(), registry);
        watcher.loadInitial();
        String before = registry.get(CharacterId.EMU).content();

        Thread.sleep(1100);  // mtime 해상도 보장
        Files.writeString(emuFile, """
                # IDENTITY - 오오토리 에무
                - **Name:** 오오토리 에무 (Emu Otori)
                - 새 내용 추가
                """);
        watcher.checkAndReload();

        assertThat(registry.get(CharacterId.EMU).content()).isNotEqualTo(before);
        assertThat(registry.get(CharacterId.EMU).content()).contains("새 내용 추가");
    }
}
```

- [ ] **Step 3: 테스트 실행 → 실패 확인**

```bash
./gradlew test --tests PersonaWatcherTest
```

Expected: FAIL — `PersonaWatcher` 없음.

- [ ] **Step 4: PersonaWatcher 구현**

```java
package com.maitmus.sekairouter.persona;

import com.maitmus.sekairouter.config.PersonaProperties;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Map;
import java.util.stream.Stream;

@Slf4j
@Component
@RequiredArgsConstructor
public class PersonaWatcher {

    private final PersonaProperties properties;
    private final PersonaLoader loader;
    private final PersonaRegistry registry;

    private volatile long lastMaxMtime = -1;

    @PostConstruct
    public void loadInitial() throws IOException {
        Path dir = Paths.get(properties.dir());
        Map<CharacterId, Persona> personas = loader.loadAll(dir);
        registry.replace(personas);
        lastMaxMtime = currentMaxMtime(dir);
        log.info("Initial persona load — {} entries", personas.size());
    }

    @Scheduled(fixedDelayString = "${persona.watch-interval-ms}")
    public void checkAndReload() throws IOException {
        Path dir = Paths.get(properties.dir());
        long current = currentMaxMtime(dir);
        if (current > lastMaxMtime) {
            Map<CharacterId, Persona> personas = loader.loadAll(dir);
            registry.replace(personas);
            lastMaxMtime = current;
            log.info("Persona reload triggered (mtime change detected) — {} entries", personas.size());
        }
    }

    private long currentMaxMtime(Path dir) throws IOException {
        try (Stream<Path> stream = Files.list(dir)) {
            return stream.filter(p -> p.toString().endsWith(".md"))
                         .mapToLong(this::mtime)
                         .max()
                         .orElse(0);
        }
    }

    private long mtime(Path p) {
        try {
            return Files.getLastModifiedTime(p).toMillis();
        } catch (IOException e) {
            return 0;
        }
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
./gradlew test --tests PersonaWatcherTest
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/main/java/com/maitmus/sekairouter/persona/PersonaRegistry.java
git add src/main/java/com/maitmus/sekairouter/persona/PersonaWatcher.java
git add src/test/java/com/maitmus/sekairouter/persona/PersonaWatcherTest.java
git commit -m "feat: PersonaRegistry + PersonaWatcher mtime 감지로 페르소나 캐시 무효화"
```

---

## Task 7: Routing 도메인 모델 (sealed RoutingDecision + records)

**Files:**
- Create: `src/main/java/com/maitmus/sekairouter/routing/PersonaResponse.java`
- Create: `src/main/java/com/maitmus/sekairouter/routing/RoutingDecision.java`
- Create: `src/main/java/com/maitmus/sekairouter/memory/ConversationTurn.java`
- Create: `src/main/java/com/maitmus/sekairouter/routing/RouterRequest.java`

- [ ] **Step 1: PersonaResponse record**

```java
package com.maitmus.sekairouter.routing;

import com.maitmus.sekairouter.persona.CharacterId;

public record PersonaResponse(CharacterId character, String message) {
    public PersonaResponse {
        if (character == null) throw new IllegalArgumentException("character required");
        if (message == null || message.isBlank()) throw new IllegalArgumentException("message required");
    }
}
```

- [ ] **Step 2: RoutingDecision sealed interface**

```java
package com.maitmus.sekairouter.routing;

import java.util.List;

public sealed interface RoutingDecision {

    record Single(PersonaResponse response, String reasoning) implements RoutingDecision {}

    record Multi(List<PersonaResponse> responses, String reasoning) implements RoutingDecision {
        public Multi {
            if (responses == null || responses.size() < 2) {
                throw new IllegalArgumentException("Multi requires 2+ responses");
            }
            responses = List.copyOf(responses);
        }
    }

    record NoReply(String reasoning) implements RoutingDecision {}

    default List<PersonaResponse> responses() {
        return switch (this) {
            case Single s -> List.of(s.response);
            case Multi m -> m.responses;
            case NoReply n -> List.of();
        };
    }
}
```

- [ ] **Step 3: ConversationTurn record**

```java
package com.maitmus.sekairouter.memory;

public record ConversationTurn(
        String speaker,    // "user" 또는 캐릭터 ID 소문자 (예: "emu")
        String content,
        long timestampSec
) {}
```

- [ ] **Step 4: RouterRequest record**

```java
package com.maitmus.sekairouter.routing;

import com.maitmus.sekairouter.memory.ConversationTurn;
import com.maitmus.sekairouter.persona.CharacterId;

import java.util.List;

public record RouterRequest(
        String channelId,
        List<ConversationTurn> recentTurns,
        String newMessage,
        CharacterId lastSpeaker  // null 가능
) {
    public RouterRequest {
        recentTurns = recentTurns == null ? List.of() : List.copyOf(recentTurns);
    }
}
```

- [ ] **Step 5: 빌드 확인**

```bash
./gradlew build -x test
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 6: Commit**

```bash
git add src/main/java/com/maitmus/sekairouter/routing/
git add src/main/java/com/maitmus/sekairouter/memory/ConversationTurn.java
git commit -m "feat: routing 도메인 모델 — sealed RoutingDecision + record"
```

---

## Task 8: ConversationMemory (인메모리)

**Files:**
- Create: `src/main/java/com/maitmus/sekairouter/memory/ConversationMemory.java`
- Create: `src/test/java/com/maitmus/sekairouter/memory/ConversationMemoryTest.java`

- [ ] **Step 1: ConversationMemoryTest 작성**

```java
package com.maitmus.sekairouter.memory;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class ConversationMemoryTest {

    private final ConversationMemory memory = new ConversationMemory(5);

    @Test
    void append_andGetRecent_returnsInOrder() {
        memory.append("ch1", new ConversationTurn("user", "안녕", 1));
        memory.append("ch1", new ConversationTurn("emu", "원더호이~!", 2));

        List<ConversationTurn> turns = memory.getRecent("ch1");

        assertThat(turns).extracting(ConversationTurn::speaker).containsExactly("user", "emu");
    }

    @Test
    void getRecent_capsToLimit() {
        for (int i = 0; i < 10; i++) {
            memory.append("ch1", new ConversationTurn("user", "msg" + i, i));
        }

        List<ConversationTurn> turns = memory.getRecent("ch1");

        assertThat(turns).hasSize(5);
        assertThat(turns.get(0).content()).isEqualTo("msg5");
        assertThat(turns.get(4).content()).isEqualTo("msg9");
    }

    @Test
    void perChannelIsolation() {
        memory.append("ch1", new ConversationTurn("user", "ch1-msg", 1));
        memory.append("ch2", new ConversationTurn("user", "ch2-msg", 1));

        assertThat(memory.getRecent("ch1")).hasSize(1);
        assertThat(memory.getRecent("ch2")).hasSize(1);
        assertThat(memory.getRecent("ch1").get(0).content()).isEqualTo("ch1-msg");
    }
}
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

```bash
./gradlew test --tests ConversationMemoryTest
```

Expected: FAIL — 클래스 없음.

- [ ] **Step 3: ConversationMemory 구현**

```java
package com.maitmus.sekairouter.memory;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

@Component
public class ConversationMemory {

    private final int maxTurnsPerChannel;
    private final ConcurrentMap<String, Deque<ConversationTurn>> store = new ConcurrentHashMap<>();

    public ConversationMemory(@Value("${conversation.max-turns:5}") int maxTurnsPerChannel) {
        this.maxTurnsPerChannel = maxTurnsPerChannel;
    }

    public void append(String channelId, ConversationTurn turn) {
        Deque<ConversationTurn> deque = store.computeIfAbsent(channelId, k -> new ArrayDeque<>());
        synchronized (deque) {
            deque.addLast(turn);
            while (deque.size() > maxTurnsPerChannel) {
                deque.pollFirst();
            }
        }
    }

    public List<ConversationTurn> getRecent(String channelId) {
        Deque<ConversationTurn> deque = store.get(channelId);
        if (deque == null) return List.of();
        synchronized (deque) {
            return new ArrayList<>(deque);
        }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
./gradlew test --tests ConversationMemoryTest
```

Expected: PASS — 3 테스트 모두 성공.

- [ ] **Step 5: Commit**

```bash
git add src/main/java/com/maitmus/sekairouter/memory/ConversationMemory.java
git add src/test/java/com/maitmus/sekairouter/memory/ConversationMemoryTest.java
git commit -m "feat: ConversationMemory — 채널별 최근 N개 인메모리 캐시"
```

---

## Task 9: LastSpeakerStore + RandomCharacterSelector

**Files:**
- Create: `src/main/java/com/maitmus/sekairouter/proxy/LastSpeakerStore.java`
- Create: `src/main/java/com/maitmus/sekairouter/routing/RandomCharacterSelector.java`
- Create: `src/test/java/com/maitmus/sekairouter/proxy/LastSpeakerStoreTest.java`
- Create: `src/test/java/com/maitmus/sekairouter/routing/RandomCharacterSelectorTest.java`

- [ ] **Step 1: LastSpeakerStoreTest 작성**

```java
package com.maitmus.sekairouter.proxy;

import com.maitmus.sekairouter.persona.CharacterId;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class LastSpeakerStoreTest {

    private final LastSpeakerStore store = new LastSpeakerStore();

    @Test
    void recordAndGet() {
        store.record("ch1", CharacterId.EMU);

        assertThat(store.get("ch1")).contains(CharacterId.EMU);
    }

    @Test
    void getEmpty_whenNotRecorded() {
        assertThat(store.get("ch1")).isEmpty();
    }

    @Test
    void perChannelIsolation() {
        store.record("ch1", CharacterId.EMU);
        store.record("ch2", CharacterId.NENE);

        assertThat(store.get("ch1")).contains(CharacterId.EMU);
        assertThat(store.get("ch2")).contains(CharacterId.NENE);
    }
}
```

- [ ] **Step 2: LastSpeakerStore 구현**

```java
package com.maitmus.sekairouter.proxy;

import com.maitmus.sekairouter.persona.CharacterId;
import org.springframework.stereotype.Component;

import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

@Component
public class LastSpeakerStore {

    private final ConcurrentMap<String, CharacterId> store = new ConcurrentHashMap<>();

    public void record(String channelId, CharacterId speaker) {
        store.put(channelId, speaker);
    }

    public Optional<CharacterId> get(String channelId) {
        return Optional.ofNullable(store.get(channelId));
    }
}
```

- [ ] **Step 3: 테스트 통과 확인**

```bash
./gradlew test --tests LastSpeakerStoreTest
```

Expected: PASS.

- [ ] **Step 4: RandomCharacterSelectorTest 작성**

```java
package com.maitmus.sekairouter.routing;

import com.maitmus.sekairouter.persona.CharacterId;
import org.junit.jupiter.api.Test;

import java.util.HashSet;
import java.util.Random;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class RandomCharacterSelectorTest {

    @Test
    void selectsAnyCharacter_whenNoExclusion() {
        RandomCharacterSelector selector = new RandomCharacterSelector(new Random(42L));

        CharacterId picked = selector.pickOne(null);

        assertThat(picked).isIn((Object[]) CharacterId.values());
    }

    @Test
    void excludesLastSpeaker() {
        RandomCharacterSelector selector = new RandomCharacterSelector(new Random(42L));

        Set<CharacterId> picks = new HashSet<>();
        for (int i = 0; i < 100; i++) {
            picks.add(selector.pickOne(CharacterId.EMU));
        }

        assertThat(picks).doesNotContain(CharacterId.EMU);
        assertThat(picks).hasSize(6);  // 7 - 1
    }

    @Test
    void shuffleAll_returnsAllSeven() {
        RandomCharacterSelector selector = new RandomCharacterSelector(new Random(42L));

        var shuffled = selector.shuffleAll();

        assertThat(shuffled).hasSize(7).containsAll(java.util.Arrays.asList(CharacterId.values()));
    }
}
```

- [ ] **Step 5: RandomCharacterSelector 구현**

```java
package com.maitmus.sekairouter.routing;

import com.maitmus.sekairouter.persona.CharacterId;
import org.springframework.stereotype.Component;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Random;
import java.util.concurrent.ThreadLocalRandom;
import java.util.stream.Collectors;

@Component
public class RandomCharacterSelector {

    private final Random random;

    public RandomCharacterSelector() {
        this.random = null;  // Production: ThreadLocalRandom 사용
    }

    // 테스트용 — seed 고정 가능
    RandomCharacterSelector(Random random) {
        this.random = random;
    }

    public CharacterId pickOne(CharacterId exclude) {
        List<CharacterId> pool = Arrays.stream(CharacterId.values())
                .filter(c -> c != exclude)
                .collect(Collectors.toList());
        int idx = (random != null ? random.nextInt(pool.size())
                                  : ThreadLocalRandom.current().nextInt(pool.size()));
        return pool.get(idx);
    }

    public List<CharacterId> shuffleAll() {
        List<CharacterId> all = new java.util.ArrayList<>(Arrays.asList(CharacterId.values()));
        if (random != null) {
            Collections.shuffle(all, random);
        } else {
            Collections.shuffle(all, ThreadLocalRandom.current());
        }
        return all;
    }
}
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
./gradlew test --tests RandomCharacterSelectorTest
```

Expected: PASS — 3 테스트 모두 성공.

- [ ] **Step 7: Commit**

```bash
git add src/main/java/com/maitmus/sekairouter/proxy/LastSpeakerStore.java
git add src/main/java/com/maitmus/sekairouter/routing/RandomCharacterSelector.java
git add src/test/java/com/maitmus/sekairouter/proxy/LastSpeakerStoreTest.java
git add src/test/java/com/maitmus/sekairouter/routing/RandomCharacterSelectorTest.java
git commit -m "feat: LastSpeakerStore + RandomCharacterSelector (산술 랜덤, last-speaker 제외)"
```

---

## Task 10: SystemPromptBuilder + 정적 프롬프트 리소스

**Files:**
- Create: `src/main/resources/prompts/router-base-instructions.md`
- Create: `src/main/resources/prompts/output-schema.md`
- Create: `src/main/java/com/maitmus/sekairouter/routing/SystemPromptBuilder.java`
- Create: `src/test/java/com/maitmus/sekairouter/routing/SystemPromptBuilderTest.java`

- [ ] **Step 1: router-base-instructions.md 작성**

`src/main/resources/prompts/router-base-instructions.md`:
```markdown
# 라우터 봇 지시문

당신은 Discord 채널의 메시지를 받아 Project Sekai 캐릭터 봇 7명 중 누가 응답할지 결정하고 캐릭터 톤으로 대사를 생성하는 라우터입니다.

## 캐릭터 7명
- airi (모모이 아이리, MORE MORE JUMP!)
- emu (오오토리 에무, Wonderlands × Showtime)
- haruka (키리타니 하루카, MORE MORE JUMP!)
- miku (하츠네 미쿠, Virtual Singer)
- minori (하나사토 미노리, MORE MORE JUMP!)
- nene (쿠사나기 네네, Wonderlands × Showtime)
- shizuku (히노모리 시즈쿠, MORE MORE JUMP!)

## 라우팅 규칙

**기명 호출** (캐릭터 이름·별칭 명시): 해당 캐릭터로 응답.

**무기명 호출**:
- 직전 발화자 정보가 주어지고 새 메시지가 그 대화의 자연스러운 연속이면 같은 캐릭터로 응답
- 새 화제·맥락 단절이면 시스템이 미리 산출한 후보 캐릭터(`suggestedCharacter`)로 응답
- 절대 본인이 임의로 캐릭터를 선택하지 말 것 — 호출 명시 없으면 `suggestedCharacter` 사용

**다중 호명** (2명 이상 명시): 호명된 전원 응답. `responses` 배열에 각각.

**전원 호명** ("다들/모두/전원/다같이"): `suggestedOrder` 순서대로 7명 전원 응답.

**리액션 발화 (depth 최대 2)**:
- 다른 캐릭터를 언급했거나 유닛 동료가 반응할 만한 화제(음식·취미·연습·공연 등)인 경우 추가 발화 가능
- depth 최대 2 (응답 한 캐릭터 + 리액션 한 캐릭터까지). 절대 3개 초과 금지
- 리액션 캐릭터는 직전 응답자와 다른 캐릭터여야 함
- 무관한 사적 질문에는 리액션 미적용

**NO_REPLY**:
- 봇과 무관한 일반 채팅
- 스티커 전용 메시지
- 응답이 부적절한 컨텍스트

## 대사 작성 규칙

- 1~3문장
- 지문·설명·괄호 해설 금지 (예: "(쑥스러운 듯)" 같은 것)
- 캐릭터 1인칭 준수 (emu→"에무", 나머지→"나")
- 존댓말/반말 캐릭터별 설정대로
- 호칭은 페르소나 정의에 따름
```

- [ ] **Step 2: output-schema.md 작성**

`src/main/resources/prompts/output-schema.md`:
```markdown
## 출력 JSON 스키마 (반드시 이 형식)

```json
{
  "decision": "single | multi | no_reply",
  "responses": [
    { "character": "<캐릭터id>", "message": "<대사 1~3문장>" }
  ],
  "reasoning": "<라우팅 결정 이유, 1줄>"
}
```

- `decision`: `single` (1명), `multi` (2~7명), `no_reply` (응답 안 함)
- `responses`: `no_reply`면 빈 배열, `single`이면 1개, `multi`면 2~7개
- `character`: 7개 ID 중 하나 (소문자) — `airi/emu/haruka/miku/minori/nene/shizuku`
- 절대 캐릭터 ID 외 다른 값 사용 금지
- 텍스트만 출력. 출력 전후에 markdown 코드 펜스 또는 다른 텍스트 추가 금지

```

- [ ] **Step 3: SystemPromptBuilderTest 작성**

```java
package com.maitmus.sekairouter.routing;

import com.maitmus.sekairouter.persona.CharacterId;
import com.maitmus.sekairouter.persona.Persona;
import com.maitmus.sekairouter.persona.PersonaRegistry;
import org.junit.jupiter.api.Test;

import java.util.EnumMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class SystemPromptBuilderTest {

    @Test
    void build_includesAllPersonasAndInstructions() {
        Map<CharacterId, Persona> personas = new EnumMap<>(CharacterId.class);
        personas.put(CharacterId.EMU, new Persona(CharacterId.EMU, "오오토리 에무", "에무 페르소나 본문"));
        personas.put(CharacterId.NENE, new Persona(CharacterId.NENE, "쿠사나기 네네", "네네 페르소나 본문"));
        PersonaRegistry registry = mock(PersonaRegistry.class);
        when(registry.all()).thenReturn(personas);

        SystemPromptBuilder builder = new SystemPromptBuilder(registry);
        String prompt = builder.build();

        assertThat(prompt).contains("라우팅 규칙");
        assertThat(prompt).contains("에무 페르소나 본문");
        assertThat(prompt).contains("네네 페르소나 본문");
        assertThat(prompt).contains("출력 JSON 스키마");
    }
}
```

- [ ] **Step 4: SystemPromptBuilder 구현**

```java
package com.maitmus.sekairouter.routing;

import com.maitmus.sekairouter.persona.Persona;
import com.maitmus.sekairouter.persona.PersonaRegistry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

@Slf4j
@Component
@RequiredArgsConstructor
public class SystemPromptBuilder {

    private final PersonaRegistry registry;

    @Value("classpath:prompts/router-base-instructions.md")
    private Resource baseInstructions;

    @Value("classpath:prompts/output-schema.md")
    private Resource outputSchema;

    public String build() {
        StringBuilder sb = new StringBuilder();
        sb.append(loadResource(baseInstructions)).append("\n\n");
        sb.append("## 페르소나 정의\n\n");
        registry.all().values().forEach(p -> appendPersona(sb, p));
        sb.append("\n").append(loadResource(outputSchema));
        return sb.toString();
    }

    private void appendPersona(StringBuilder sb, Persona p) {
        sb.append("### ").append(p.id().name().toLowerCase())
          .append(" — ").append(p.displayName()).append("\n\n")
          .append(p.content()).append("\n\n");
    }

    private String loadResource(Resource resource) {
        try (var is = resource.getInputStream()) {
            return new String(is.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new IllegalStateException("Failed to load prompt resource: " + resource.getFilename(), e);
        }
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
./gradlew test --tests SystemPromptBuilderTest
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/main/resources/prompts/
git add src/main/java/com/maitmus/sekairouter/routing/SystemPromptBuilder.java
git add src/test/java/com/maitmus/sekairouter/routing/SystemPromptBuilderTest.java
git commit -m "feat: SystemPromptBuilder + router-base-instructions/output-schema 리소스"
```

---

## Task 11: RouterService — Anthropic 호출 + JSON 파싱

**Files:**
- Create: `src/main/java/com/maitmus/sekairouter/routing/RouterService.java`
- Create: `src/test/java/com/maitmus/sekairouter/routing/RouterServiceTest.java`

- [ ] **Step 1: RouterServiceTest 작성 (mock Anthropic 응답)**

```java
package com.maitmus.sekairouter.routing;

import com.maitmus.sekairouter.persona.CharacterId;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class RouterServiceTest {

    @Test
    void parseSingle_decision() {
        AnthropicClientWrapper client = mock(AnthropicClientWrapper.class);
        when(client.completeJson(org.mockito.ArgumentMatchers.anyString(), org.mockito.ArgumentMatchers.anyString()))
                .thenReturn("""
                        {"decision":"single","responses":[{"character":"emu","message":"안녕!"}],"reasoning":"기명 호출"}
                        """);
        SystemPromptBuilder promptBuilder = mock(SystemPromptBuilder.class);
        when(promptBuilder.build()).thenReturn("system prompt");

        RouterService service = new RouterService(client, promptBuilder);

        RouterRequest request = new RouterRequest("ch1", List.of(), "에무 안녕", null);
        RoutingDecision decision = service.route(request, null);

        assertThat(decision).isInstanceOf(RoutingDecision.Single.class);
        RoutingDecision.Single single = (RoutingDecision.Single) decision;
        assertThat(single.response().character()).isEqualTo(CharacterId.EMU);
        assertThat(single.response().message()).isEqualTo("안녕!");
    }

    @Test
    void parseMulti_decision() {
        AnthropicClientWrapper client = mock(AnthropicClientWrapper.class);
        when(client.completeJson(org.mockito.ArgumentMatchers.anyString(), org.mockito.ArgumentMatchers.anyString()))
                .thenReturn("""
                        {"decision":"multi","responses":[
                          {"character":"emu","message":"안녕!"},
                          {"character":"nene","message":"...왔구나"}
                        ],"reasoning":"다중 호명"}
                        """);
        SystemPromptBuilder promptBuilder = mock(SystemPromptBuilder.class);
        when(promptBuilder.build()).thenReturn("system prompt");

        RouterService service = new RouterService(client, promptBuilder);

        RoutingDecision decision = service.route(new RouterRequest("ch1", List.of(), "에무랑 네네 안녕", null), null);

        assertThat(decision).isInstanceOf(RoutingDecision.Multi.class);
        assertThat(decision.responses()).hasSize(2);
    }

    @Test
    void parseNoReply_decision() {
        AnthropicClientWrapper client = mock(AnthropicClientWrapper.class);
        when(client.completeJson(org.mockito.ArgumentMatchers.anyString(), org.mockito.ArgumentMatchers.anyString()))
                .thenReturn("""
                        {"decision":"no_reply","responses":[],"reasoning":"무관한 채팅"}
                        """);
        SystemPromptBuilder promptBuilder = mock(SystemPromptBuilder.class);
        when(promptBuilder.build()).thenReturn("system prompt");

        RouterService service = new RouterService(client, promptBuilder);

        RoutingDecision decision = service.route(new RouterRequest("ch1", List.of(), "오늘 날씨 좋네", null), null);

        assertThat(decision).isInstanceOf(RoutingDecision.NoReply.class);
        assertThat(decision.responses()).isEmpty();
    }
}
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

```bash
./gradlew test --tests RouterServiceTest
```

Expected: FAIL — `AnthropicClientWrapper`/`RouterService` 없음.

- [ ] **Step 3: AnthropicClientWrapper 구현 (Anthropic SDK 호출)**

```java
package com.maitmus.sekairouter.routing;

import com.anthropic.client.AnthropicClient;
import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import com.anthropic.models.messages.Message;
import com.anthropic.models.messages.MessageCreateParams;
import com.anthropic.models.messages.Model;
import com.maitmus.sekairouter.config.AnthropicProperties;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class AnthropicClientWrapper {

    private final AnthropicProperties properties;
    private AnthropicClient client;

    @PostConstruct
    void init() {
        this.client = AnthropicOkHttpClient.builder()
                .apiKey(properties.apiKey())
                .build();
    }

    public String completeJson(String systemPrompt, String userPrompt) {
        MessageCreateParams params = MessageCreateParams.builder()
                .model(Model.of(properties.model()))
                .maxTokens(properties.maxTokens())
                .system(systemPrompt)  // 캐시 대상
                .addUserMessage(userPrompt)
                .build();

        Message response = client.messages().create(params);
        String text = response.content().stream()
                .filter(block -> block.text().isPresent())
                .map(block -> block.text().get().text())
                .findFirst()
                .orElseThrow(() -> new IllegalStateException("No text content in response"));
        log.debug("Anthropic response: {}", text);
        return text;
    }
}
```

> **참고**: Anthropic SDK 0.8.0의 정확한 API 형태는 호출 시점에 SDK 문서로 재확인 필요. `system()` 파라미터에 `cache_control: ephemeral` 적용은 `system().cacheControl(...)` 또는 별도 빌더 — SDK 버전별 차이 있음. Phase 2에서 캐시 적중률 측정 시 정확한 형태 확정.

- [ ] **Step 4: RouterService 구현**

```java
package com.maitmus.sekairouter.routing;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.maitmus.sekairouter.persona.CharacterId;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class RouterService {

    private final AnthropicClientWrapper anthropic;
    private final SystemPromptBuilder promptBuilder;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public RoutingDecision route(RouterRequest request, CharacterId suggestedCharacter) {
        String systemPrompt = promptBuilder.build();
        String userPrompt = buildUserPrompt(request, suggestedCharacter);

        String json = anthropic.completeJson(systemPrompt, userPrompt);
        return parse(json);
    }

    private String buildUserPrompt(RouterRequest request, CharacterId suggested) {
        StringBuilder sb = new StringBuilder();
        sb.append("## 채널 최근 발화\n");
        if (request.recentTurns().isEmpty()) {
            sb.append("(없음 — 새 대화)\n");
        } else {
            request.recentTurns().forEach(t ->
                    sb.append(t.speaker()).append(": ").append(t.content()).append("\n"));
        }
        if (request.lastSpeaker() != null) {
            sb.append("\n직전 응답자: ").append(request.lastSpeaker().name().toLowerCase()).append("\n");
        }
        if (suggested != null) {
            sb.append("\nsuggestedCharacter: ").append(suggested.name().toLowerCase()).append("\n");
        }
        sb.append("\n## 새 메시지\n").append(request.newMessage()).append("\n\n## 판단 요청\n위 라우팅 규칙대로 출력 JSON 스키마 형식으로만 응답하세요.");
        return sb.toString();
    }

    private RoutingDecision parse(String json) {
        try {
            String cleaned = stripCodeFence(json);
            RawDecision raw = objectMapper.readValue(cleaned, RawDecision.class);
            return switch (raw.decision()) {
                case "single" -> {
                    if (raw.responses().size() != 1) {
                        throw new IllegalArgumentException("single must have 1 response, got " + raw.responses().size());
                    }
                    yield new RoutingDecision.Single(raw.responses().get(0).toModel(), raw.reasoning());
                }
                case "multi" -> {
                    if (raw.responses().size() < 2) {
                        throw new IllegalArgumentException("multi must have 2+ responses");
                    }
                    yield new RoutingDecision.Multi(
                            raw.responses().stream().map(RawResponse::toModel).toList(),
                            raw.reasoning());
                }
                case "no_reply" -> new RoutingDecision.NoReply(raw.reasoning());
                default -> throw new IllegalArgumentException("Unknown decision: " + raw.decision());
            };
        } catch (Exception e) {
            log.error("Failed to parse routing decision JSON: {}", json, e);
            return new RoutingDecision.NoReply("parse error: " + e.getMessage());
        }
    }

    private String stripCodeFence(String s) {
        String trimmed = s.trim();
        if (trimmed.startsWith("```")) {
            int firstNewline = trimmed.indexOf('\n');
            int lastFence = trimmed.lastIndexOf("```");
            if (firstNewline > 0 && lastFence > firstNewline) {
                return trimmed.substring(firstNewline + 1, lastFence).trim();
            }
        }
        return trimmed;
    }

    private record RawDecision(String decision, List<RawResponse> responses, String reasoning) {}

    private record RawResponse(@JsonProperty("character") String character,
                               @JsonProperty("message") String message) {
        PersonaResponse toModel() {
            CharacterId id = CharacterId.fromString(character)
                    .orElseThrow(() -> new IllegalArgumentException("Unknown character: " + character));
            return new PersonaResponse(id, message);
        }
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
./gradlew test --tests RouterServiceTest
```

Expected: PASS — 3 테스트 성공.

- [ ] **Step 6: Commit**

```bash
git add src/main/java/com/maitmus/sekairouter/routing/AnthropicClientWrapper.java
git add src/main/java/com/maitmus/sekairouter/routing/RouterService.java
git add src/test/java/com/maitmus/sekairouter/routing/RouterServiceTest.java
git commit -m "feat: RouterService — Anthropic 호출 + JSON 응답 → RoutingDecision 파싱"
```

---

## Task 12: PersonaBotRegistry + DiscordConfig (JDA Bean 8개)

**Files:**
- Create: `src/main/java/com/maitmus/sekairouter/discord/PersonaBotRegistry.java`
- Create: `src/main/java/com/maitmus/sekairouter/config/DiscordConfig.java`

- [ ] **Step 1: PersonaBotRegistry 구현**

```java
package com.maitmus.sekairouter.discord;

import com.maitmus.sekairouter.persona.CharacterId;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import net.dv8tion.jda.api.JDA;
import org.springframework.stereotype.Component;

import java.util.Map;

@Slf4j
@Component
@RequiredArgsConstructor
public class PersonaBotRegistry {

    private final Map<CharacterId, JDA> bots;

    public JDA get(CharacterId id) {
        JDA jda = bots.get(id);
        if (jda == null) {
            throw new IllegalStateException("No JDA registered for character: " + id);
        }
        return jda;
    }

    public Map<CharacterId, JDA> all() {
        return bots;
    }
}
```

- [ ] **Step 2: DiscordConfig 구현 (라우터 + 7개 캐릭터 봇)**

```java
package com.maitmus.sekairouter.config;

import com.maitmus.sekairouter.persona.CharacterId;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import net.dv8tion.jda.api.JDA;
import net.dv8tion.jda.api.JDABuilder;
import net.dv8tion.jda.api.requests.GatewayIntent;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.EnumMap;
import java.util.Map;

@Slf4j
@Configuration
@RequiredArgsConstructor
public class DiscordConfig {

    private final DiscordProperties properties;

    @Bean(name = "routerJda", destroyMethod = "shutdown")
    public JDA routerJda() throws InterruptedException {
        log.info("Starting router bot JDA...");
        return JDABuilder.createDefault(properties.routerToken())
                .enableIntents(GatewayIntent.GUILD_MESSAGES, GatewayIntent.MESSAGE_CONTENT)
                .build()
                .awaitReady();
    }

    @Bean
    public Map<CharacterId, JDA> characterJdas() throws InterruptedException {
        Map<CharacterId, JDA> map = new EnumMap<>(CharacterId.class);
        for (Map.Entry<CharacterId, String> entry : properties.characterTokens().entrySet()) {
            String token = entry.getValue();
            if (token == null || token.isBlank()) {
                log.warn("No token for {} — skipping", entry.getKey());
                continue;
            }
            log.info("Starting character bot {} JDA...", entry.getKey());
            JDA jda = JDABuilder.createDefault(token)
                    .enableIntents(GatewayIntent.GUILD_MESSAGES)
                    .build()
                    .awaitReady();
            map.put(entry.getKey(), jda);
        }
        return map;
    }
}
```

- [ ] **Step 3: 빌드 + bootRun (모든 봇 연결 확인)**

```bash
./gradlew bootRun
```

Expected: 8개 JDA 인스턴스 connect 로그. 라우터 봇 + 7개 캐릭터 봇 모두 "JDA Status: CONNECTED" 도달. Ctrl+C로 종료.

> **사용자 확인 필요**: 8개 봇이 모두 같은 길드에 가입되어 있어야 채널 접근 가능. 한 봇이라도 길드에 없으면 해당 캐릭터 발화 시 실패. Discord 개발자 포털에서 각 봇의 OAuth2 URL로 길드 초대 필수.

- [ ] **Step 4: Commit**

```bash
git add src/main/java/com/maitmus/sekairouter/discord/PersonaBotRegistry.java
git add src/main/java/com/maitmus/sekairouter/config/DiscordConfig.java
git commit -m "feat: 라우터 봇 + 7개 캐릭터 봇 JDA Bean (총 8개 인스턴스)"
```

---

## Task 13: ProxySpeechService + TypingIndicatorService

**Files:**
- Create: `src/main/java/com/maitmus/sekairouter/proxy/TypingIndicatorService.java`
- Create: `src/main/java/com/maitmus/sekairouter/proxy/ProxySpeechService.java`

- [ ] **Step 1: TypingIndicatorService 구현**

```java
package com.maitmus.sekairouter.proxy;

import com.maitmus.sekairouter.discord.PersonaBotRegistry;
import com.maitmus.sekairouter.persona.CharacterId;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import net.dv8tion.jda.api.entities.channel.concrete.TextChannel;
import org.springframework.stereotype.Service;

import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;

@Slf4j
@Service
@RequiredArgsConstructor
public class TypingIndicatorService {

    private static final long INTERVAL_SECONDS = 5L;

    private final PersonaBotRegistry registry;
    private final ScheduledExecutorService scheduler;
    private final ConcurrentMap<String, ScheduledFuture<?>> active = new ConcurrentHashMap<>();

    public void start(CharacterId character, String channelId) {
        String key = key(character, channelId);
        TextChannel channel = registry.get(character).getTextChannelById(channelId);
        if (channel == null) {
            log.warn("Channel {} not found for {}", channelId, character);
            return;
        }
        ScheduledFuture<?> task = scheduler.scheduleAtFixedRate(
                () -> channel.sendTyping().queue(
                        success -> {},
                        err -> log.debug("typing failed: {}", err.getMessage())),
                0, INTERVAL_SECONDS, java.util.concurrent.TimeUnit.SECONDS);
        active.put(key, task);
    }

    public void stop(CharacterId character, String channelId) {
        ScheduledFuture<?> task = active.remove(key(character, channelId));
        if (task != null) task.cancel(false);
    }

    private String key(CharacterId c, String ch) {
        return c.name() + ":" + ch;
    }
}
```

- [ ] **Step 2: ScheduledExecutorService Bean 추가 — DiscordConfig.java 수정**

```java
@Bean(destroyMethod = "shutdown")
public java.util.concurrent.ScheduledExecutorService typingScheduler() {
    return java.util.concurrent.Executors.newScheduledThreadPool(4);
}
```

`DiscordConfig.java`에 Bean 메서드 추가.

- [ ] **Step 3: ProxySpeechService 구현**

```java
package com.maitmus.sekairouter.proxy;

import com.maitmus.sekairouter.discord.PersonaBotRegistry;
import com.maitmus.sekairouter.persona.CharacterId;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import net.dv8tion.jda.api.entities.channel.concrete.TextChannel;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
public class ProxySpeechService {

    private final PersonaBotRegistry registry;
    private final TypingIndicatorService typing;

    public boolean send(CharacterId character, String channelId, String message) {
        TextChannel channel = registry.get(character).getTextChannelById(channelId);
        if (channel == null) {
            log.error("Channel {} not visible to character bot {}", channelId, character);
            typing.stop(character, channelId);
            return false;
        }
        try {
            channel.sendMessage(message).complete();
            log.info("Sent as {} on {}: {}", character, channelId, abbreviate(message));
            return true;
        } catch (Exception e) {
            log.error("Failed to send as {} on {}: {}", character, channelId, e.getMessage());
            return false;
        } finally {
            typing.stop(character, channelId);
        }
    }

    private String abbreviate(String s) {
        return s.length() > 60 ? s.substring(0, 57) + "..." : s;
    }
}
```

- [ ] **Step 4: 빌드 확인**

```bash
./gradlew build -x test
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 5: Commit**

```bash
git add src/main/java/com/maitmus/sekairouter/proxy/
git add src/main/java/com/maitmus/sekairouter/config/DiscordConfig.java
git commit -m "feat: ProxySpeechService + TypingIndicatorService (typing → 발화 → typing 종료)"
```

---

## Task 14: RouterEventListener — 메시지 수신 → 라우팅 → 발화 통합

**Files:**
- Create: `src/main/java/com/maitmus/sekairouter/discord/RouterEventListener.java`
- Modify: `src/main/java/com/maitmus/sekairouter/config/DiscordConfig.java` (라우터 봇에 리스너 등록)

- [ ] **Step 1: RouterEventListener 구현**

```java
package com.maitmus.sekairouter.discord;

import com.maitmus.sekairouter.config.DiscordProperties;
import com.maitmus.sekairouter.memory.ConversationMemory;
import com.maitmus.sekairouter.memory.ConversationTurn;
import com.maitmus.sekairouter.persona.CharacterId;
import com.maitmus.sekairouter.proxy.LastSpeakerStore;
import com.maitmus.sekairouter.proxy.ProxySpeechService;
import com.maitmus.sekairouter.proxy.TypingIndicatorService;
import com.maitmus.sekairouter.routing.PersonaResponse;
import com.maitmus.sekairouter.routing.RandomCharacterSelector;
import com.maitmus.sekairouter.routing.RouterRequest;
import com.maitmus.sekairouter.routing.RouterService;
import com.maitmus.sekairouter.routing.RoutingDecision;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import net.dv8tion.jda.api.entities.Message;
import net.dv8tion.jda.api.events.message.MessageReceivedEvent;
import net.dv8tion.jda.api.hooks.ListenerAdapter;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.List;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

@Slf4j
@Component
@RequiredArgsConstructor
public class RouterEventListener extends ListenerAdapter {

    private static final long INTER_MESSAGE_DELAY_MS = 1500;

    private final DiscordProperties properties;
    private final RouterService routerService;
    private final ConversationMemory memory;
    private final LastSpeakerStore lastSpeaker;
    private final RandomCharacterSelector randomSelector;
    private final ProxySpeechService proxy;
    private final TypingIndicatorService typing;
    private final ScheduledExecutorService scheduler;

    @Override
    public void onMessageReceived(MessageReceivedEvent event) {
        if (!properties.sekaiChannelId().equals(event.getChannel().getId())) {
            return;  // Phase 1은 단일 채널만
        }
        if (event.getAuthor().isBot()) {
            return;  // 봇 메시지(자기 자신/캐릭터 봇) 무시
        }

        Message message = event.getMessage();
        String content = message.getContentDisplay();
        if (content.isBlank()) {
            return;  // 스티커 전용 등
        }

        String channelId = event.getChannel().getId();
        memory.append(channelId, new ConversationTurn("user", content, Instant.now().getEpochSecond()));

        CharacterId last = lastSpeaker.get(channelId).orElse(null);
        CharacterId suggested = randomSelector.pickOne(last);

        RouterRequest request = new RouterRequest(channelId, memory.getRecent(channelId), content, last);

        try {
            RoutingDecision decision = routerService.route(request, suggested);
            handleDecision(channelId, decision);
        } catch (Exception e) {
            log.error("Routing failed for message on {}: {}", channelId, e.getMessage(), e);
        }
    }

    private void handleDecision(String channelId, RoutingDecision decision) {
        log.info("Routing decision for {}: {} ({})", channelId, decision.getClass().getSimpleName(),
                reasoningOf(decision));

        List<PersonaResponse> responses = decision.responses();
        if (responses.isEmpty()) {
            return;
        }

        for (int i = 0; i < responses.size(); i++) {
            PersonaResponse r = responses.get(i);
            long delay = (long) i * INTER_MESSAGE_DELAY_MS;
            scheduler.schedule(() -> {
                typing.start(r.character(), channelId);
                boolean ok = proxy.send(r.character(), channelId, r.message());
                if (ok) {
                    memory.append(channelId,
                            new ConversationTurn(r.character().name().toLowerCase(),
                                    r.message(), Instant.now().getEpochSecond()));
                    lastSpeaker.record(channelId, r.character());
                }
            }, delay, TimeUnit.MILLISECONDS);
        }
    }

    private String reasoningOf(RoutingDecision d) {
        return switch (d) {
            case RoutingDecision.Single s -> s.reasoning();
            case RoutingDecision.Multi m -> m.reasoning();
            case RoutingDecision.NoReply n -> n.reasoning();
        };
    }
}
```

- [ ] **Step 2: DiscordConfig에서 라우터 JDA에 리스너 등록 — Bean 수정**

`DiscordConfig.java`의 `routerJda()` 메서드 수정:

```java
@Bean(name = "routerJda", destroyMethod = "shutdown")
public JDA routerJda(RouterEventListener listener) throws InterruptedException {
    log.info("Starting router bot JDA...");
    return JDABuilder.createDefault(properties.routerToken())
            .enableIntents(GatewayIntent.GUILD_MESSAGES, GatewayIntent.MESSAGE_CONTENT)
            .addEventListeners(listener)
            .build()
            .awaitReady();
}
```

(import 추가: `com.maitmus.sekairouter.discord.RouterEventListener`)

- [ ] **Step 3: 빌드 확인**

```bash
./gradlew build -x test
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit**

```bash
git add src/main/java/com/maitmus/sekairouter/discord/RouterEventListener.java
git add src/main/java/com/maitmus/sekairouter/config/DiscordConfig.java
git commit -m "feat: RouterEventListener — 메시지 수신 → 라우팅 → 순차 발화 통합"
```

---

## Task 15: 통합 — bootRun으로 PoC 실제 동작 확인 (수동 테스트)

**Files:** (수정 없음, 환경 설정만)

> **이 task는 수동 검증.** 코드 변경 없이 환경변수로 테스트 채널 설정 후 직접 메시지 입력하여 8개 시나리오를 한 채널에서 검증.

- [ ] **Step 1: 테스트용 Discord 채널 준비**

- 사용자: 기존 세카이 채널(`1485510333115273339`)이 아닌 별도 테스트 채널 생성 (개인 길드의 빈 채널)
- 라우터 봇 + 7개 캐릭터 봇 모두 해당 길드에 가입되어 있어야 함
- 테스트 채널 ID 복사 (Discord 개발자 모드 → 채널 우클릭 → Copy ID)

- [ ] **Step 2: .env 작성**

`~/projects/open-pjsk-spring-migration/.env`:
```env
ANTHROPIC_API_KEY=sk-ant-...
ANTHROPIC_MODEL=claude-haiku-4-5
ANTHROPIC_MAX_TOKENS=1000

DISCORD_ROUTER_TOKEN=...
DISCORD_AIRI_TOKEN=...
DISCORD_EMU_TOKEN=...
DISCORD_HARUKA_TOKEN=...
DISCORD_MIKU_TOKEN=...
DISCORD_MINORI_TOKEN=...
DISCORD_NENE_TOKEN=...
DISCORD_SHIZUKU_TOKEN=...

SEKAI_CHANNEL_ID=<테스트 채널 ID>
PERSONA_DIR=/home/maitmus/.openclaw/workspace/identities
```

- [ ] **Step 3: 환경변수 로드 후 실행**

```bash
cd ~/projects/open-pjsk-spring-migration
export $(cat .env | xargs)
./gradlew bootRun
```

Expected: 8개 JDA 인스턴스 모두 CONNECTED, "Initial persona load — 7 entries" 로그 출력.

- [ ] **Step 4: 시나리오 1~8 수동 검증**

테스트 채널에 다음 메시지 순서대로 입력 후 응답 확인 — 각 시나리오 결과를 `~/projects/open-pjsk-spring-migration/scenario-log.md`에 기록:

```
시나리오 1 (기명 단발): "에무, 안녕"
기대: 에무 봇이 ~인 거에요/원더호이~ 톤으로 응답
결과: ____

시나리오 2 (무기명 첫 대화): "안녕"
기대: 7명 중 랜덤 1명 응답 (직전 발화 기록 없음)
결과: ____

시나리오 3 (무기명 멀티턴): (시나리오 2 직후) "뭐 해?"
기대: 시나리오 2 응답자가 같은 캐릭터로 이어서 응답
결과: ____

시나리오 4 (캐릭터 전환): "네네, 너는?"
기대: 네네 봇이 응답
결과: ____

시나리오 5 (다중 호명): "에무랑 네네, 안녕"
기대: 에무 + 네네 둘 다 응답 (1.5초 간격)
결과: ____

시나리오 6 (전원 호명): "다들 안녕"
기대: 7명 전원 셔플 순서로 응답
결과: ____

시나리오 7 (리액션): "오늘 연습 힘들었어"
기대: 1명 응답 후 다른 캐릭터가 자연스럽게 리액션 (depth ≤ 2)
결과: ____

시나리오 8 (NO_REPLY): "오늘 날씨 예보 알려줘"
기대: 라우터가 NO_REPLY로 결정. 어떤 캐릭터도 응답 안 함
결과: ____
```

> **알려진 LLM 한계**: Haiku 4.5가 시나리오 6(전원 호명) 또는 시나리오 7(리액션 depth)을 일관되게 처리 못 할 가능성. 실패 시 시스템 프롬프트(`router-base-instructions.md`) 보강하거나 Sonnet 4.6으로 전환 검토 — 그 결정은 Phase 2.

- [ ] **Step 5: scenario-log.md 작성 + commit (테스트 결과 기록)**

```bash
cd ~/projects/open-pjsk-spring-migration
# scenario-log.md 작성 (위 시나리오 결과 채움)
git add scenario-log.md
git commit -m "test: Phase 1 시나리오 1~8 수동 검증 결과 기록"
git push origin main
```

---

## Task 16: Baseline 측정 (마이그레이션 전 OpenClaw 비용 데이터)

**Files:** (코드 변경 없음, 데이터 수집)

> **이 task도 수동 — 사용자가 Anthropic 콘솔 작업.** Phase 2 비교 측정의 기준점.

- [ ] **Step 1: Anthropic 콘솔에서 최근 7일 토큰 사용량 캡처**

- URL: https://console.anthropic.com/settings/usage
- 기간: 최근 7일
- 다운로드: CSV 또는 스크린샷 — 사용자 자료실에 저장

- [ ] **Step 2: 분리 측정 — 라우터 봇 / 세카이 봇 / 하트비트**

OpenClaw가 에이전트별 분리 통계를 직접 제공하지 않으면 다음으로 추정:
- 라우터 봇 = 가장 호출 빈도 높은 모델 사용 라인 (`sekai-router` API key 또는 시간대별 분포)
- 세카이 봇 = 헤드쿼터 채널 활동 시간대
- 하트비트 = 현재 비활성이므로 0

- [ ] **Step 3: baseline.md 작성**

`~/projects/open-pjsk-spring-migration/baseline.md`:
```markdown
# OpenClaw Baseline 비용 (마이그레이션 전)

측정 기간: 2026-04-30 ~ 2026-05-06 (7일)

## 일일 평균
- 총 호출: ___ 회/일
- Input 토큰: ___ M/일 (uncached: ___ / cached: ___)
- Output 토큰: ___ M/일
- 일일 비용: $___

## 메시지당 평균 (라우터 봇 추정)
- 시스템 프롬프트: ___ 토큰
- 사용자 프롬프트: ___ 토큰
- 출력: ___ 토큰

## Phase 2 목표
- Spring Boot 라우터 메시지당 비용을 baseline 대비 5배 이상 절감
```

- [ ] **Step 4: Commit**

```bash
cd ~/projects/open-pjsk-spring-migration
git add baseline.md
git commit -m "docs: OpenClaw baseline 비용 측정 기록 (Phase 2 비교 기준점)"
git push origin main
```

---

## Task 17: Phase 1 완료 보고서

**Files:**
- Create: `~/projects/open-pjsk-spring-migration/phase1-report.md`

- [ ] **Step 1: 보고서 작성**

`~/projects/open-pjsk-spring-migration/phase1-report.md`:
```markdown
## Phase 1 완료 보고

### 완료된 작업
- 별도 GitHub 리포(`maitmus/open-pjsk-spring-migration`) 생성
- Spring Boot 3.4 + JDA 5 + Anthropic SDK 의존성 셋업
- 라우터 봇 + 7개 캐릭터 봇 JDA 인스턴스 (총 8개)
- PersonaLoader/Watcher (mtime 감지로 캐시 무효화)
- RouterService (Anthropic Haiku 4.5 호출 + JSON 출력 파싱)
- ConversationMemory (인메모리, 채널별 최근 5개)
- LastSpeakerStore + RandomCharacterSelector (산술 랜덤 + last-speaker 제외)
- ProxySpeechService + TypingIndicatorService
- RouterEventListener 통합 (수신 → 라우팅 → 순차 발화)
- 단위 테스트 (PersonaLoader/Watcher/Memory/LastSpeaker/RandomSelector/Router/PromptBuilder)

### 검증 결과
- 8개 시나리오 통과 여부 — `scenario-log.md` 참조
- Baseline 비용 데이터 — `baseline.md` 참조 (Phase 2 비교 기준점)
- 알려진 이슈:
  - Anthropic SDK 캐시 적용 형태가 SDK 0.8.0에서 어떤 빌더 메서드인지 확정 필요 → Phase 2 캐시 적중률 측정 시 해결
  - Haiku 4.5의 라우팅 정확도가 GRADES.md 호칭 매트릭스를 처리할 수 있는지 검증 필요 → 시나리오 결과로 판단

### 다음 Phase 준비 (Phase 2 대비)
- 사용자 결정 필요 사항:
  - Sonnet 4.6 전환 여부 (정확도 vs 비용)
  - quick-ref.md를 시스템 프롬프트에 포함할지 (호칭 정확도 vs 토큰)
  - Redis 도입 시점 (단일 인스턴스라면 인메모리로 충분)

### 남은 작업 (Phase 2)
- 양 시스템 (OpenClaw vs Spring Boot) 응답 품질 평가 (블라인드 테스트)
- 메시지당 토큰 사용량 비교
- 라우팅 정확도 측정 (8개 시나리오 + 추가 엣지 케이스)
- 비용 절감 정량화
```

- [ ] **Step 2: Commit + push**

```bash
cd ~/projects/open-pjsk-spring-migration
git add phase1-report.md
git commit -m "docs: Phase 1 완료 보고서"
git push origin main
```

---

## Self-Review Checklist

Plan 작성 후 spec(`migration-handoff.md`)과 대조하여 누락 점검:

**Spec 커버리지:**
- ✅ 라우터 봇 LLM 호출 (Task 11)
- ✅ JDA 라우터 + 7개 캐릭터 봇 (Task 12)
- ✅ 페르소나 로더 + mtime watcher (Task 5, 6)
- ✅ 컨텍스트 메모리 (Task 8)
- ✅ 대리 발화 + typing indicator (Task 13)
- ✅ Last-speaker.txt 상당의 인메모리 store (Task 9)
- ✅ 산술 랜덤 캐릭터 선택 (Task 9)
- ✅ JSON 출력 스키마 (Task 10, 11)
- ✅ 시스템 프롬프트 정적/동적 분리 (Task 10)
- ✅ 8개 검증 시나리오 (Task 15)
- ✅ Baseline 측정 (Task 16)
- ✅ 단일 채널 PoC 병행 운영 (Task 15)
- ✅ 환경 변수 정정사항(`PERSONA_DIR`, `SEKAI_CHANNEL_ID`, 캐릭터 7명 토큰) (Task 3)
- ⚠ **세카이 봇/main 에이전트는 Phase 4까지 OpenClaw 그대로** — 본 plan 범위 외 (의도)
- ⚠ **하트비트는 Phase 3.5까지 OpenClaw 그대로** — 본 plan 범위 외 (의도)
- ⚠ **`sekai-all-speak.sh`의 1~3초 간격은 plan에서 1.5초 고정** — Task 14 `INTER_MESSAGE_DELAY_MS = 1500` (단순화)
- ⚠ **GRADES.md/quick-ref.md를 시스템 프롬프트에 포함하지 않음** — Phase 1은 페르소나 7개만. 호칭 정확도가 떨어지면 Phase 2에서 quick-ref.md 추가 검토

**Placeholder/모호함 점검:** 없음. 모든 step에 코드 또는 정확한 명령 포함.

**타입 일관성:** `CharacterId` enum, `RoutingDecision` sealed interface, `PersonaResponse` record가 task 4/7/11에서 일관됨.

**Anthropic SDK 캐시 컨트롤**: Task 11의 SDK 빌더 메서드는 SDK 0.8.0 문서 재확인이 필요한 부분 — 명시적으로 `참고` 노트로 표기됨.

---

**Plan 종료. Phase 1 완료 시 Phase 2로 진행.**
