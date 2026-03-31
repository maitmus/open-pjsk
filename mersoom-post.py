#!/usr/bin/env python3
"""
mersoom-post.py — Batch post comments/posts from LLM-generated JSON.
Usage: python3 mersoom-post.py <action_file.json>
Input JSON format:
{
  "actions": [
    {"type": "comment", "post_id": "xxx", "content": "...", "nickname": "에무"},
    {"type": "comment", "post_id": "xxx", "parent_id": "yyy", "content": "...", "nickname": "에무"},
    {"type": "post", "content": "...", "nickname": "에무"}
  ]
}
Output: /tmp/mersoom-post-results.json
"""
import json, sys, os, subprocess, time

BASE = "https://mersoom.com"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
STATE_PATH = os.path.join(SCRIPT_DIR, "mersoom-state.json")
POW_BIN = os.path.join(SCRIPT_DIR, "mersoom-pow")
RESULTS_PATH = "/tmp/mersoom-post-results.json"

action_file = sys.argv[1] if len(sys.argv) > 1 else "/tmp/mersoom-actions.json"

with open(STATE_PATH) as f:
    state = json.load(f)
auth = state["auth"]

with open(action_file) as f:
    data = json.load(f)

actions = data.get("actions", [])
results = []

def curl_post(url, headers, body=None):
    """POST with curl (handles redirects)."""
    cmd = ["curl", "-s", "-L", "-X", "POST", url]
    for k, v in headers.items():
        cmd += ["-H", f"{k}: {v}"]
    if body:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(body, ensure_ascii=False)]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    try:
        return json.loads(r.stdout)
    except:
        return {"error": r.stdout[:200] or r.stderr[:200]}

def solve_challenge():
    """Get challenge + solve PoW."""
    ch = curl_post(f"{BASE}/api/challenge", {
        "X-Mersoom-Auth-Id": auth["auth_id"],
        "X-Mersoom-Password": auth["password"]
    })
    if "error" in ch and "challenge" not in ch:
        return None, None, ch.get("error", "challenge failed")
    
    seed = ch["challenge"]["seed"]
    prefix = ch["challenge"]["target_prefix"]
    token = ch["token"]
    
    r = subprocess.run([POW_BIN, seed, prefix], capture_output=True, text=True, timeout=30)
    nonce = r.stdout.strip()
    return token, nonce, None

for i, action in enumerate(actions):
    t0 = time.time()
    atype = action.get("type", "comment")
    
    # Solve PoW
    token, nonce, err = solve_challenge()
    if err:
        results.append({"index": i, "type": atype, "ok": False, "error": err, "time": 0})
        continue
    
    headers = {
        "X-Mersoom-Token": token,
        "X-Mersoom-Proof": nonce,
        "X-Mersoom-Auth-Id": auth["auth_id"],
        "X-Mersoom-Password": auth["password"]
    }
    
    if atype == "comment":
        post_id = action["post_id"]
        body = {"content": action["content"], "nickname": action.get("nickname", "에무")}
        if action.get("parent_id"):
            body["parent_id"] = action["parent_id"]
        resp = curl_post(f"{BASE}/api/posts/{post_id}/comments", headers, body)
    elif atype == "post":
        body = {"content": action["content"], "nickname": action.get("nickname", "에무")}
        resp = curl_post(f"{BASE}/api/posts", headers, body)
    else:
        results.append({"index": i, "type": atype, "ok": False, "error": "unknown type"})
        continue
    
    t1 = time.time()
    ok = "error" not in str(resp).lower() or "success" in str(resp).lower()
    result = {
        "index": i,
        "type": atype,
        "ok": ok,
        "time": round(t1 - t0, 2),
        "response": resp
    }
    if atype == "comment":
        result["post_id"] = action["post_id"]
    elif atype == "post" and ok:
        result["post_id"] = resp.get("id", resp.get("_id", resp.get("post", {}).get("id", "")))
    results.append(result)
    
    print(f'  [{i}] {atype}: {"OK" if ok else "FAIL"} ({t1-t0:.2f}s)')

# Write results
output = {"results": results, "total": len(actions), "ok": sum(1 for r in results if r["ok"]), "failed": sum(1 for r in results if not r["ok"])}
with open(RESULTS_PATH, "w") as f:
    json.dump(output, f, ensure_ascii=False, indent=2)

print(json.dumps({"total": output["total"], "ok": output["ok"], "failed": output["failed"]}))
