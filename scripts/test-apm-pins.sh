#!/usr/bin/env bash
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/apm-pins.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ echo "ok - $1"; pass=$((pass+1)); }
ng(){ echo "NOT OK - $1"; fail=$((fail+1)); }

make_mcp(){ cat > "$1" <<'YAML'
name: apm-config-mcp-toolkit
version: 1.2.0
dependencies:
  apm:
    - ChromeDevTools/chrome-devtools-mcp#913308263bdc8042af74924b68dc39a374ad071d
  mcp:
    - name: context7
      command: npx
      args:
        - -y
        - "@upstash/context7-mcp@3.2.0"
    - name: serena
      command: uvx
      args:
        - --from
        - git+https://github.com/oraios/serena@acee002dc498e5f4c368eb9d45ab67e480d77832
        - serena
        - start-mcp-server
YAML
}
NEWSHA=1111111111111111111111111111111111111111

# 1. 置換が効く
f="$TMP/mcp1.yml"; make_mcp "$f"
APM_MCP_FILE="$f" APM_PINS_CONTEXT7_VERSION=9.9.9 APM_PINS_SERENA_SHA=$NEWSHA "$SCRIPT" update >/dev/null
grep -q '@upstash/context7-mcp@9.9.9' "$f" && grep -q "oraios/serena@$NEWSHA" "$f" && ok "replaces context7+serena" || ng "replaces context7+serena"

# 2. 冪等（2回目は差分ゼロ）
before="$(cat "$f")"
APM_MCP_FILE="$f" APM_PINS_CONTEXT7_VERSION=9.9.9 APM_PINS_SERENA_SHA=$NEWSHA "$SCRIPT" update >/dev/null
[ "$before" = "$(cat "$f")" ] && ok "idempotent" || ng "idempotent"

# 3. dry-run はファイルを変えない
f2="$TMP/mcp2.yml"; make_mcp "$f2"; b2="$(cat "$f2")"
APM_MCP_FILE="$f2" APM_PINS_CONTEXT7_VERSION=8.8.8 APM_PINS_SERENA_SHA=$NEWSHA "$SCRIPT" update --dry-run >/dev/null
[ "$b2" = "$(cat "$f2")" ] && ok "dry-run no write" || ng "dry-run no write"

# 4. fail-fast: context7 anchor を壊すと非ゼロ
f3="$TMP/mcp3.yml"; make_mcp "$f3"
perl -i -pe 's/\@upstash\/context7-mcp\@3\.2\.0/BROKEN/' "$f3"
if APM_MCP_FILE="$f3" APM_PINS_CONTEXT7_VERSION=9.9.9 APM_PINS_SERENA_SHA=$NEWSHA "$SCRIPT" update >/dev/null 2>&1; then
  ng "fail-fast on missing anchor"
else ok "fail-fast on missing anchor"; fi

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
