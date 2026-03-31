#!/usr/bin/env python3
"""
mersoom-collect.py — Pre-collect mersoom data for LLM consumption.
Usage: python3 mersoom-collect.py [comment|emu]
Output: /tmp/mersoom-collected.json

Reduces LLM turns by batching all API reads into one script execution.
"""
import json, sys, os, urllib.request

BASE = "https://mersoom.com"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
STATE_PATH = os.path.join(SCRIPT_DIR, "mersoom-state.json")
OUT_PATH = "/tmp/mersoom-collected.json"

mode = sys.argv[1] if len(sys.argv) > 1 else "comment"

# Load state
with open(STATE_PATH) as f:
    state = json.load(f)

last_post_ids = state.get("last_post_ids", [])
last_comment_ids_raw = state.get("last_comment_ids", [])
last_comment_ids = [
    x["post_id"] if isinstance(x, dict) else x
    for x in last_comment_ids_raw
]
friends = state.get("friends", [])
avoid = state.get("avoid", [])
context_notes = state.get("context_notes", {})
auth = state.get("auth", {})

def api_get(path):
    try:
        req = urllib.request.Request(f"{BASE}{path}")
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.loads(r.read())
    except Exception as e:
        return {"error": str(e)}

# 1. Get recent posts
posts_raw = api_get("/api/posts?limit=8")
if isinstance(posts_raw, list):
    all_posts = posts_raw
else:
    all_posts = posts_raw.get("posts", posts_raw.get("data", []))

# 2. Categorize posts
other_posts = []
my_posts = []
for p in all_posts:
    pid = p.get("id", p.get("_id", ""))
    if pid in last_post_ids:
        my_posts.append(p)
    else:
        other_posts.append(p)

# 3. Fetch comments for commentable posts (skip already commented)
commentable = []
skipped = 0
for p in other_posts:
    pid = p.get("id", p.get("_id", ""))
    if pid in last_comment_ids:
        skipped += 1
        continue
    comments_raw = api_get(f"/api/posts/{pid}/comments")
    if isinstance(comments_raw, list):
        comments = comments_raw
    else:
        comments = comments_raw.get("comments", comments_raw.get("data", []))
    commentable.append({"post": p, "comments": comments})

# 4. Fetch comments on my recent posts (reply tracking)
my_tracked = []
for p in my_posts[:3]:
    pid = p.get("id", p.get("_id", ""))
    comments_raw = api_get(f"/api/posts/{pid}/comments")
    if isinstance(comments_raw, list):
        comments = comments_raw
    else:
        comments = comments_raw.get("comments", comments_raw.get("data", []))
    my_tracked.append({"post": p, "comments": comments})

# 5. Build output
result = {
    "mode": mode,
    "collected_at": __import__("datetime").datetime.now().isoformat(),
    "other_posts": commentable,
    "my_posts": my_tracked,
    "friends": friends,
    "avoid": avoid,
    "context_notes": context_notes,
    "auth": auth,
    "stats": {
        "total_fetched": len(all_posts),
        "commentable": len(commentable),
        "already_commented_skipped": skipped,
        "my_posts_tracked": len(my_tracked),
    }
}

with open(OUT_PATH, "w") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)

# Print stats summary for LLM
print(json.dumps(result["stats"], ensure_ascii=False))
