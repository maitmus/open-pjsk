#!/bin/bash
# mersoom-dashboard.sh — 머슴 일간 리포트를 헤드쿼터 채널에 발송
# 크론: 0 21 * * * (매일 21:00 KST, 하루 활동 마감 후)
# LLM 호출 없이 API + jq로 데이터 집계 → openclaw message로 직접 발송

set -euo pipefail

STATE_FILE="$HOME/.openclaw/workspace/mersoom-state.json"
API_BASE="https://mersoom.com/api"
HQ_CHANNEL="1489156511497326705"
TODAY=$(date +%Y-%m-%d)

# --- 1. 포인트 조회 ---
AUTH_ID=$(jq -r '.auth.auth_id' "$STATE_FILE")
PASSWORD=$(jq -r '.auth.password' "$STATE_FILE")

POINTS_RES=$(curl -sLf -H "X-Mersoom-Auth-Id: $AUTH_ID" \
  -H "X-Mersoom-Password: $PASSWORD" \
  "$API_BASE/points/me" 2>/dev/null || echo '{"points":"조회실패"}')
POINTS=$(echo "$POINTS_RES" | jq -r '.points // "N/A"')

# --- 2. 오늘 글/댓글 수 집계 (mersoom-state.json 기반) ---
POST_COUNT=$(jq -r '.last_post_ids | length' "$STATE_FILE")
COMMENT_COUNT=$(jq -r --arg today "$TODAY" \
  '[.last_comment_ids[] | select(.timestamp | startswith($today))] | length' \
  "$STATE_FILE")

# --- 3. 관계 집계 ---
FRIENDS_LIST=$(jq -r '.friends // [] | join(", ")' "$STATE_FILE")
AVOID_LIST=$(jq -r '.avoid // [] | join(", ")' "$STATE_FILE")
FIXED_FRIENDS_LIST=$(jq -r '[.fixed_friends // [] | .[].name] | join(", ")' "$STATE_FILE")
FIXED_AVOID_LIST=$(jq -r '[.fixed_avoid // [] | .[].name] | join(", ")' "$STATE_FILE")
[ -z "$FRIENDS_LIST" ] && FRIENDS_LIST="없음"
[ -z "$AVOID_LIST" ] && AVOID_LIST="없음"
[ -z "$FIXED_FRIENDS_LIST" ] && FIXED_FRIENDS_LIST="없음"
[ -z "$FIXED_AVOID_LIST" ] && FIXED_AVOID_LIST="없음"

# --- 4. 광고 현황 ---
AD_INFO=$(jq -r '.ad_ids // [] | map("  - ID: \(.id) | 잔여: \(.impressions)회") | join("\n")' "$STATE_FILE")
if [ -z "$AD_INFO" ]; then
  AD_INFO="  없음"
fi

# --- 5. 리포트 조립 ---
REPORT="📊 **머슴 일간 리포트** (${TODAY})
━━━━━━━━━━━━━━━━━━
**활동**
- 글 작성 (누적): ${POST_COUNT}건
- 오늘 댓글: ${COMMENT_COUNT}건

**포인트**: ${POINTS}pt

**관계**
- 절친: ${FIXED_FRIENDS_LIST}
- 친구: ${FRIENDS_LIST}
- 차단: ${FIXED_AVOID_LIST}
- 경계: ${AVOID_LIST}

**광고**
${AD_INFO}

**요약**: $(jq -r '.summary // "없음"' "$STATE_FILE")"

# --- 6. 헤드쿼터 채널에 발송 ---
openclaw message send \
  --channel discord \
  --target "$HQ_CHANNEL" \
  --message "$REPORT"
