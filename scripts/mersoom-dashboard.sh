#!/bin/bash
# mersoom-dashboard.sh — 머슴 일간 리포트를 헤드쿼터 채널에 발송
# 크론: 0 21 * * * (매일 21:00 KST, 하루 활동 마감 후)
# LLM 호출 없이 API + jq로 데이터 집계 → openclaw message로 직접 발송

set -euo pipefail

STATE_FILE="$HOME/.openclaw/workspace/mersoom-state.json"
SNAPSHOT_DIR="/tmp/mersoom-snapshots"
API_BASE="https://mersoom.com/api"
HQ_CHANNEL="1489156511497326705"
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)

mkdir -p "$SNAPSHOT_DIR"

# --- 1. 포인트 조회 ---
AUTH_ID=$(jq -r '.auth.auth_id' "$STATE_FILE")
PASSWORD=$(jq -r '.auth.password' "$STATE_FILE")

POINTS_RES=$(curl -sLf -H "X-Mersoom-Auth-Id: $AUTH_ID" \
  -H "X-Mersoom-Password: $PASSWORD" \
  "$API_BASE/points/me" 2>/dev/null || echo '{"points":"조회실패"}')
POINTS=$(echo "$POINTS_RES" | jq -r '.points // "N/A"')

# --- 2. 오늘 글/댓글 수 집계 ---
POST_COUNT=$(jq -r '.last_post_ids | length' "$STATE_FILE")
COMMENT_COUNT=$(jq -r --arg today "$TODAY" \
  '[.last_comment_ids[] | select(.timestamp | startswith($today))] | length' \
  "$STATE_FILE")

# --- 3. 관계 인원 수 ---
FIXED_FRIENDS_COUNT=$(jq -r '.fixed_friends // [] | length' "$STATE_FILE")
FRIENDS_COUNT=$(jq -r '.friends // [] | length' "$STATE_FILE")
AVOID_COUNT=$(jq -r '.avoid // [] | length' "$STATE_FILE")
FIXED_AVOID_COUNT=$(jq -r '.fixed_avoid // [] | length' "$STATE_FILE")

# --- 4. 관계 변동 감지 (어제 스냅샷 대비) ---
PREV_SNAPSHOT="$SNAPSHOT_DIR/$YESTERDAY.json"
CHANGES=""

if [ -f "$PREV_SNAPSHOT" ]; then
  # 절친 신규
  NEW_FF=$(jq -r --slurpfile prev "$PREV_SNAPSHOT" \
    '[.fixed_friends // [] | .[].name] - [$prev[0].fixed_friends // [] | .[].name] | .[]' \
    "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$NEW_FF" ]; then
    while IFS= read -r name; do
      reason=$(jq -r --arg n "$name" '.fixed_friends[] | select(.name == $n) | .reason // "사유 없음"' "$STATE_FILE")
      CHANGES="${CHANGES}\n  - ⬆️ 절친 격상: ${name} (${reason})"
    done <<< "$NEW_FF"
  fi

  # 차단 신규
  NEW_FA=$(jq -r --slurpfile prev "$PREV_SNAPSHOT" \
    '[.fixed_avoid // [] | .[].name] - [$prev[0].fixed_avoid // [] | .[].name] | .[]' \
    "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$NEW_FA" ]; then
    while IFS= read -r name; do
      reason=$(jq -r --arg n "$name" '.fixed_avoid[] | select(.name == $n) | .reason // "사유 없음"' "$STATE_FILE")
      CHANGES="${CHANGES}\n  - ⬇️ 차단 격하: ${name} (${reason})"
    done <<< "$NEW_FA"
  fi
fi

# --- 5. 오늘 스냅샷 저장 (내일 비교용) ---
jq '{fixed_friends, fixed_avoid, friends, avoid}' "$STATE_FILE" > "$SNAPSHOT_DIR/$TODAY.json"
# 3일 이상 된 스냅샷 정리
find "$SNAPSHOT_DIR" -name "*.json" -mtime +3 -delete 2>/dev/null || true

# --- 6. 광고 현황 ---
AD_INFO=$(jq -r '.ad_ids // [] | map("  - \(.id | .[0:8])… | 잔여 \(.impressions)회") | join("\n")' "$STATE_FILE")
[ -z "$AD_INFO" ] && AD_INFO="  없음"

# --- 7. 리포트 조립 ---
RELATION_LINE="절친 ${FIXED_FRIENDS_COUNT} / 친구 ${FRIENDS_COUNT} / 경계 ${AVOID_COUNT} / 차단 ${FIXED_AVOID_COUNT}"

REPORT="📊 **머슴 일간 리포트** (${TODAY})
━━━━━━━━━━━━━━━━━━
**활동**
- 글 (누적): ${POST_COUNT}건
- 오늘 댓글: ${COMMENT_COUNT}건

**포인트**: ${POINTS}pt

**관계**: ${RELATION_LINE}"

if [ -n "$CHANGES" ]; then
  REPORT="${REPORT}
**변동**$(echo -e "$CHANGES")"
fi

REPORT="${REPORT}

**광고**
${AD_INFO}

**요약**: $(jq -r '.summary // "없음"' "$STATE_FILE")"

# --- 8. 헤드쿼터 채널에 발송 ---
openclaw message send \
  --channel discord \
  --target "$HQ_CHANNEL" \
  --message "$REPORT"
