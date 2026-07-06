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

# 5. bump-version: 変更あり → patch 上げ
fb="$TMP/b_before.yml"; fa="$TMP/b_after.yml"
printf 'name: p\nversion: 1.2.0\nx: old\n' > "$fb"
printf 'name: p\nversion: 1.2.0\nx: new\n' > "$fa"
"$SCRIPT" bump-version "$fa" "$fb" >/dev/null
grep -q '^version: 1.2.1$' "$fa" && ok "bump on change" || ng "bump on change"

# 6. bump-version: 変更なし（version 行以外同一）→ 据え置き
fb2="$TMP/c_before.yml"; fa2="$TMP/c_after.yml"
printf 'name: p\nversion: 3.0.5\nx: same\n' > "$fb2"
printf 'name: p\nversion: 3.0.5\nx: same\n' > "$fa2"
"$SCRIPT" bump-version "$fa2" "$fb2" >/dev/null
grep -q '^version: 3.0.5$' "$fa2" && ok "no bump when unchanged" || ng "no bump when unchanged"

# 7. render-body: 変化した pin だけ表に出る
BD="$TMP/before"; mkdir -p "$BD"
make_mcp "$BD/mcp.apm.yml"
printf 'name: b\nversion: 1.0.0\ndependencies:\n  apm:\n    - obra/superpowers#%s\n' \
  d884ae04edebef577e82ff7c4e143debd0bbec99 > "$BD/base.apm.yml"
# 現在ファイル: context7 のみ更新済み、superpowers は据え置き
curmcp="$TMP/cur_mcp.yml"; curbase="$TMP/cur_base.yml"
make_mcp "$curmcp"; perl -i -pe 's/context7-mcp\@3\.2\.0/context7-mcp\@3.2.2/' "$curmcp"
cp "$BD/base.apm.yml" "$curbase"
out="$(APM_BASE_FILE="$curbase" APM_MCP_FILE="$curmcp" "$SCRIPT" render-body "$BD")"
echo "$out" | grep -q 'context7' && echo "$out" | grep -q '3.2.0' && echo "$out" | grep -q '3.2.2' && ok "render-body shows changed context7" || ng "render-body shows changed context7"
echo "$out" | grep -q 'superpowers' && ng "render-body must omit unchanged superpowers" || ok "render-body omits unchanged"

# 8. render-body: context7 のバージョンが 7 文字超でも切り詰められない（_short() の版数バグ回帰）
BD8="$TMP/before8"; mkdir -p "$BD8"
make_mcp "$BD8/mcp.apm.yml"
printf 'name: b\nversion: 1.0.0\ndependencies:\n  apm:\n    - obra/superpowers#%s\n' \
  d884ae04edebef577e82ff7c4e143debd0bbec99 > "$BD8/base.apm.yml"
curmcp8="$TMP/cur_mcp8.yml"; curbase8="$TMP/cur_base8.yml"
make_mcp "$curmcp8"; perl -i -pe 's/context7-mcp\@3\.2\.0/context7-mcp\@13.20.30/' "$curmcp8"
cp "$BD8/base.apm.yml" "$curbase8"
out8="$(APM_BASE_FILE="$curbase8" APM_MCP_FILE="$curmcp8" "$SCRIPT" render-body "$BD8")"
if echo "$out8" | grep -qE '`13\.20\.30`' && ! echo "$out8" | grep -qE '`13\.20\.3`'; then
  ok "render-body keeps long version intact (no truncation)"
else
  ng "render-body keeps long version intact (no truncation)"
fi

# 9. fail-fast: npm/gh が空応答でも silent skip せず非ゼロ終了（ネットワーク不要）
STUBDIR="$TMP/stubbin"; mkdir -p "$STUBDIR"
cat > "$STUBDIR/npm" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$STUBDIR/gh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$STUBDIR/npm" "$STUBDIR/gh"
f9="$TMP/mcp9.yml"; make_mcp "$f9"
if ( PATH="$STUBDIR:$PATH"; unset APM_PINS_CONTEXT7_VERSION APM_PINS_SERENA_SHA; APM_MCP_FILE="$f9" "$SCRIPT" update >/dev/null 2>&1 ); then
  ng "fail-fast when resolution is empty (no silent skip)"
else
  ok "fail-fast when resolution is empty (no silent skip)"
fi

# 10. render-body: SHA 系 pin (chrome-devtools) が変化した行だけ出て、SHA は 7 桁に短縮される
BD10="$TMP/before10"; mkdir -p "$BD10"
make_mcp "$BD10/mcp.apm.yml"
printf 'name: b\nversion: 1.0.0\ndependencies:\n  apm:\n    - obra/superpowers#%s\n' \
  d884ae04edebef577e82ff7c4e143debd0bbec99 > "$BD10/base.apm.yml"
SHA_OLD=913308263bdc8042af74924b68dc39a374ad071d
SHA_NEW=4444444444444444444444444444444444444444
curmcp10="$TMP/cur_mcp10.yml"; curbase10="$TMP/cur_base10.yml"
make_mcp "$curmcp10"; perl -i -pe "s/$SHA_OLD/$SHA_NEW/" "$curmcp10"
cp "$BD10/base.apm.yml" "$curbase10"
out10="$(APM_BASE_FILE="$curbase10" APM_MCP_FILE="$curmcp10" "$SCRIPT" render-body "$BD10")"
if echo "$out10" | grep -qE '\| chrome-devtools \| `9133082` \| `4444444` \|' \
  && ! echo "$out10" | grep -q "$SHA_OLD" \
  && ! echo "$out10" | grep -q "$SHA_NEW"; then
  ok "render-body shows changed SHA pin, 7-char shortened"
else
  ng "render-body shows changed SHA pin, 7-char shortened"
fi

# 11. fail-fast: context7 anchor が 2 回マッチすると非ゼロ終了
f11="$TMP/mcp11.yml"; make_mcp "$f11"
printf '\n  # duplicate anchor for test\n  - "@upstash/context7-mcp@3.2.0"\n' >> "$f11"
if APM_MCP_FILE="$f11" APM_PINS_CONTEXT7_VERSION=9.9.9 APM_PINS_SERENA_SHA=$NEWSHA "$SCRIPT" update >/dev/null 2>&1; then
  ng "fail-fast when context7 anchor matches more than once"
else
  ok "fail-fast when context7 anchor matches more than once"
fi

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
