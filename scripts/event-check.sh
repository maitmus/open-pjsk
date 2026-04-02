#!/bin/bash
# event-check.sh — 오늘 날짜에 해당하는 캐릭터 이벤트가 있으면 대리 발화 트리거
# 크론: 10 9 * * * (매일 09:10 KST)

set -euo pipefail

EVENTS_FILE="$HOME/.openclaw/workspace/identities/events.json"
TODAY=$(date +%m-%d)

# events.json에서 오늘 매칭 확인
BIRTHDAY=$(jq -r --arg d "$TODAY" '.birthdays[$d] // empty' "$EVENTS_FILE" 2>/dev/null)
ANNIVERSARY=$(jq -r --arg d "$TODAY" '.anniversaries[$d] // empty' "$EVENTS_FILE" 2>/dev/null)

if [ -z "$BIRTHDAY" ] && [ -z "$ANNIVERSARY" ]; then
  exit 0
fi

# 프롬프트 조립
PROMPT=""

if [ -n "$BIRTHDAY" ]; then
  LABEL=$(echo "$BIRTHDAY" | jq -r '.label')
  NAME=$(echo "$BIRTHDAY" | jq -r '.name')
  CHAR=$(echo "$BIRTHDAY" | jq -r '.character')

  if [ "$CHAR" = "null" ]; then
    # 봇 미등록 캐릭터 — 다른 캐릭터들이 언급
    PROMPT="오늘은 ${LABEL}이야. 등록된 캐릭터 중 2~3명이 ${NAME}의 생일을 자연스럽게 축하하는 대화를 세카이 채널(target=1485510333115273339)에 대리 발화해 줘. 캐릭터 간 관계와 호칭을 반영해서."
  else
    # 봇 등록 캐릭터 — 당사자 제외 다른 캐릭터들이 축하
    PROMPT="오늘은 ${LABEL}이야. ${NAME} 본인을 제외한 등록 캐릭터 중 2~3명이 축하하는 대화를 세카이 채널(target=1485510333115273339)에 대리 발화해 줘. 그 뒤 ${NAME} 본인도 감사 리액션 1회. 캐릭터 간 관계와 호칭(GRADES.md)을 반드시 반영해서."
  fi
fi

if [ -n "$ANNIVERSARY" ]; then
  LABEL=$(echo "$ANNIVERSARY" | jq -r '.label')
  if [ -n "$PROMPT" ]; then
    PROMPT="${PROMPT} 추가로 오늘은 ${LABEL}이기도 해. 생일 축하와 함께 기념일도 언급해 줘."
  else
    PROMPT="오늘은 ${LABEL}이야. 등록된 전체 캐릭터가 기념일을 자연스럽게 언급하는 대화를 세카이 채널(target=1485510333115273339)에 대리 발화해 줘. 캐릭터 간 관계와 호칭(GRADES.md)을 반드시 반영해서."
  fi
fi

# openclaw agent로 트리거
openclaw agent \
  -m "$PROMPT" \
  --agent main \
  --channel discord \
  --timeout 300
