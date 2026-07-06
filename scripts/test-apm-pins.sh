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
# base/apm.yml の最小 fixture（superpowers の git ref pin のみ）
make_base(){ cat > "$1" <<'YAML'
name: apm-config-base
version: 1.4.1
dependencies:
  apm:
    - obra/superpowers#d884ae04edebef577e82ff7c4e143debd0bbec99
  mcp: []
YAML
}
NEWSHA=1111111111111111111111111111111111111111       # serena 用
SUPERSHA=2222222222222222222222222222222222222222      # superpowers 用
CHROMESHA=3333333333333333333333333333333333333333     # chrome-devtools 用

# 1. 置換が効く（4 pin すべて: superpowers / chrome-devtools / context7 / serena）
bf="$TMP/base1.yml"; make_base "$bf"
f="$TMP/mcp1.yml"; make_mcp "$f"
if APM_BASE_FILE="$bf" APM_MCP_FILE="$f" \
   APM_PINS_SUPERPOWERS_SHA=$SUPERSHA APM_PINS_CHROME_SHA=$CHROMESHA \
   APM_PINS_CONTEXT7_VERSION=9.9.9 APM_PINS_SERENA_SHA=$NEWSHA "$SCRIPT" update >/dev/null; then
  if grep -q "obra/superpowers#$SUPERSHA" "$bf" \
    && grep -q "chrome-devtools-mcp#$CHROMESHA" "$f" \
    && grep -q '@upstash/context7-mcp@9.9.9' "$f" \
    && grep -q "oraios/serena@$NEWSHA" "$f"; then
    ok "replaces all four pins (superpowers/chrome-devtools/context7/serena)"
  else
    ng "replaces all four pins (superpowers/chrome-devtools/context7/serena)"
  fi
else
  ng "update command failed unexpectedly (test 1 setup)"
fi

# 2. 冪等（2回目は差分ゼロ、base/mcp 両方）
beforeBase="$(cat "$bf")"; beforeMcp="$(cat "$f")"
if APM_BASE_FILE="$bf" APM_MCP_FILE="$f" \
   APM_PINS_SUPERPOWERS_SHA=$SUPERSHA APM_PINS_CHROME_SHA=$CHROMESHA \
   APM_PINS_CONTEXT7_VERSION=9.9.9 APM_PINS_SERENA_SHA=$NEWSHA "$SCRIPT" update >/dev/null; then
  [ "$beforeBase" = "$(cat "$bf")" ] && [ "$beforeMcp" = "$(cat "$f")" ] && ok "idempotent" || ng "idempotent"
else
  ng "update command failed unexpectedly (test 2 setup)"
fi

# 3. dry-run はファイルを変えない（base/mcp 両方）
bf2="$TMP/base2.yml"; make_base "$bf2"; bb2="$(cat "$bf2")"
f2="$TMP/mcp2.yml"; make_mcp "$f2"; b2="$(cat "$f2")"
if APM_BASE_FILE="$bf2" APM_MCP_FILE="$f2" \
   APM_PINS_SUPERPOWERS_SHA=$SUPERSHA APM_PINS_CHROME_SHA=$CHROMESHA \
   APM_PINS_CONTEXT7_VERSION=8.8.8 APM_PINS_SERENA_SHA=$NEWSHA "$SCRIPT" update --dry-run >/dev/null; then
  [ "$bb2" = "$(cat "$bf2")" ] && [ "$b2" = "$(cat "$f2")" ] && ok "dry-run no write (base+mcp)" || ng "dry-run no write (base+mcp)"
else
  ng "update --dry-run command failed unexpectedly (test 3 setup)"
fi

# 4. fail-fast: context7 anchor を壊すと非ゼロ
bf3="$TMP/base3.yml"; make_base "$bf3"
f3="$TMP/mcp3.yml"; make_mcp "$f3"
perl -i -pe 's/\@upstash\/context7-mcp\@3\.2\.0/BROKEN/' "$f3"
if APM_BASE_FILE="$bf3" APM_MCP_FILE="$f3" APM_PINS_CONTEXT7_VERSION=9.9.9 APM_PINS_SERENA_SHA=$NEWSHA "$SCRIPT" update >/dev/null 2>&1; then
  ng "fail-fast on missing context7 anchor"
else ok "fail-fast on missing context7 anchor"; fi

# 5. fail-fast: superpowers anchor が base fixture で壊れている/無いと非ゼロ
bf4="$TMP/base4.yml"; make_base "$bf4"
perl -i -pe 's/obra\/superpowers#[0-9a-f]{40}/BROKEN/' "$bf4"
f4="$TMP/mcp4.yml"; make_mcp "$f4"
if APM_BASE_FILE="$bf4" APM_MCP_FILE="$f4" APM_PINS_CONTEXT7_VERSION=9.9.9 APM_PINS_SERENA_SHA=$NEWSHA "$SCRIPT" update >/dev/null 2>&1; then
  ng "fail-fast on missing/broken superpowers anchor"
else
  ok "fail-fast on missing/broken superpowers anchor"
fi

# 6. fail-fast: chrome-devtools anchor が mcp fixture で壊れていると非ゼロ
bf5="$TMP/base5.yml"; make_base "$bf5"
f5="$TMP/mcp5.yml"; make_mcp "$f5"
perl -i -pe 's/chrome-devtools-mcp#[0-9a-f]{40}/BROKEN/' "$f5"
if APM_BASE_FILE="$bf5" APM_MCP_FILE="$f5" APM_PINS_CONTEXT7_VERSION=9.9.9 APM_PINS_SERENA_SHA=$NEWSHA "$SCRIPT" update >/dev/null 2>&1; then
  ng "fail-fast on broken chrome-devtools anchor"
else
  ok "fail-fast on broken chrome-devtools anchor"
fi

# 7. bump-version: 変更あり → patch 上げ
fb="$TMP/b_before.yml"; fa="$TMP/b_after.yml"
printf 'name: p\nversion: 1.2.0\nx: old\n' > "$fb"
printf 'name: p\nversion: 1.2.0\nx: new\n' > "$fa"
if "$SCRIPT" bump-version "$fa" "$fb" >/dev/null; then
  grep -q '^version: 1.2.1$' "$fa" && ok "bump on change" || ng "bump on change"
else
  ng "bump-version command failed unexpectedly (test 7 setup)"
fi

# 8. bump-version: 変更なし（version 行以外同一）→ 据え置き
fb2="$TMP/c_before.yml"; fa2="$TMP/c_after.yml"
printf 'name: p\nversion: 3.0.5\nx: same\n' > "$fb2"
printf 'name: p\nversion: 3.0.5\nx: same\n' > "$fa2"
if "$SCRIPT" bump-version "$fa2" "$fb2" >/dev/null; then
  grep -q '^version: 3.0.5$' "$fa2" && ok "no bump when unchanged" || ng "no bump when unchanged"
else
  ng "bump-version command failed unexpectedly (test 8 setup)"
fi

# 9. render-body: 変化した pin だけ表に出る
BD="$TMP/before"; mkdir -p "$BD"
make_mcp "$BD/mcp.apm.yml"
printf 'name: b\nversion: 1.0.0\ndependencies:\n  apm:\n    - obra/superpowers#%s\n' \
  d884ae04edebef577e82ff7c4e143debd0bbec99 > "$BD/base.apm.yml"
# 現在ファイル: context7 のみ更新済み、superpowers は据え置き
curmcp="$TMP/cur_mcp.yml"; curbase="$TMP/cur_base.yml"
make_mcp "$curmcp"; perl -i -pe 's/context7-mcp\@3\.2\.0/context7-mcp\@3.2.2/' "$curmcp"
cp "$BD/base.apm.yml" "$curbase"
if out="$(APM_BASE_FILE="$curbase" APM_MCP_FILE="$curmcp" "$SCRIPT" render-body "$BD")"; then
  echo "$out" | grep -q 'context7' && echo "$out" | grep -q '3.2.0' && echo "$out" | grep -q '3.2.2' && ok "render-body shows changed context7" || ng "render-body shows changed context7"
  echo "$out" | grep -q 'superpowers' && ng "render-body must omit unchanged superpowers" || ok "render-body omits unchanged"
else
  ng "render-body command failed unexpectedly (test 9 setup)"
fi

# 10. render-body: context7 のバージョンが 7 文字超でも切り詰められない（_short() の版数バグ回帰）
BD8="$TMP/before8"; mkdir -p "$BD8"
make_mcp "$BD8/mcp.apm.yml"
printf 'name: b\nversion: 1.0.0\ndependencies:\n  apm:\n    - obra/superpowers#%s\n' \
  d884ae04edebef577e82ff7c4e143debd0bbec99 > "$BD8/base.apm.yml"
curmcp8="$TMP/cur_mcp8.yml"; curbase8="$TMP/cur_base8.yml"
make_mcp "$curmcp8"; perl -i -pe 's/context7-mcp\@3\.2\.0/context7-mcp\@13.20.30/' "$curmcp8"
cp "$BD8/base.apm.yml" "$curbase8"
if out8="$(APM_BASE_FILE="$curbase8" APM_MCP_FILE="$curmcp8" "$SCRIPT" render-body "$BD8")"; then
  if echo "$out8" | grep -qE '`13\.20\.30`' && ! echo "$out8" | grep -qE '`13\.20\.3`'; then
    ok "render-body keeps long version intact (no truncation)"
  else
    ng "render-body keeps long version intact (no truncation)"
  fi
else
  ng "render-body command failed unexpectedly (test 10 setup)"
fi

# 11. fail-fast: npm/gh が空応答でも silent skip せず非ゼロ終了（ネットワーク不要）
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
bf9="$TMP/base9.yml"; make_base "$bf9"
f9="$TMP/mcp9.yml"; make_mcp "$f9"
if ( PATH="$STUBDIR:$PATH"; unset APM_PINS_CONTEXT7_VERSION APM_PINS_SERENA_SHA APM_PINS_SUPERPOWERS_SHA APM_PINS_CHROME_SHA; APM_BASE_FILE="$bf9" APM_MCP_FILE="$f9" "$SCRIPT" update >/dev/null 2>&1 ); then
  ng "fail-fast when resolution is empty (no silent skip)"
else
  ok "fail-fast when resolution is empty (no silent skip)"
fi

# 12. render-body: SHA 系 pin (chrome-devtools) が変化した行だけ出て、SHA は 7 桁に短縮される
BD10="$TMP/before10"; mkdir -p "$BD10"
make_mcp "$BD10/mcp.apm.yml"
printf 'name: b\nversion: 1.0.0\ndependencies:\n  apm:\n    - obra/superpowers#%s\n' \
  d884ae04edebef577e82ff7c4e143debd0bbec99 > "$BD10/base.apm.yml"
SHA_OLD=913308263bdc8042af74924b68dc39a374ad071d
SHA_NEW=4444444444444444444444444444444444444444
curmcp10="$TMP/cur_mcp10.yml"; curbase10="$TMP/cur_base10.yml"
make_mcp "$curmcp10"; perl -i -pe "s/$SHA_OLD/$SHA_NEW/" "$curmcp10"
cp "$BD10/base.apm.yml" "$curbase10"
if out10="$(APM_BASE_FILE="$curbase10" APM_MCP_FILE="$curmcp10" "$SCRIPT" render-body "$BD10")"; then
  if echo "$out10" | grep -qE '\| chrome-devtools \| `9133082` \| `4444444` \|' \
    && ! echo "$out10" | grep -q "$SHA_OLD" \
    && ! echo "$out10" | grep -q "$SHA_NEW"; then
    ok "render-body shows changed SHA pin, 7-char shortened"
  else
    ng "render-body shows changed SHA pin, 7-char shortened"
  fi
else
  ng "render-body command failed unexpectedly (test 12 setup)"
fi

# 13. fail-fast: context7 anchor が 2 回マッチすると非ゼロ終了
bf11="$TMP/base11.yml"; make_base "$bf11"
f11="$TMP/mcp11.yml"; make_mcp "$f11"
printf '\n  # duplicate anchor for test\n  - "@upstash/context7-mcp@3.2.0"\n' >> "$f11"
if APM_BASE_FILE="$bf11" APM_MCP_FILE="$f11" APM_PINS_CONTEXT7_VERSION=9.9.9 APM_PINS_SERENA_SHA=$NEWSHA "$SCRIPT" update >/dev/null 2>&1; then
  ng "fail-fast when context7 anchor matches more than once"
else
  ok "fail-fast when context7 anchor matches more than once"
fi

# 14. fail-fast: context7 が厳密 semver でない値（prerelease 等）に解決されると非ゼロ終了
#     （2 回目の実行で prerelease サフィックスが複製されるバグの回帰テスト。
#      不正値は書き込み前に die するべきで、複製が起きること自体がここでは検知不能な
#      ほど致命的なので、1 回目の update 呼び出しが非ゼロ終了することを確認する）
bf12="$TMP/base12.yml"; make_base "$bf12"
f12="$TMP/mcp12.yml"; make_mcp "$f12"
if APM_BASE_FILE="$bf12" APM_MCP_FILE="$f12" \
   APM_PINS_SUPERPOWERS_SHA=$SUPERSHA APM_PINS_CHROME_SHA=$CHROMESHA \
   APM_PINS_CONTEXT7_VERSION=3.2.2-beta.1 APM_PINS_SERENA_SHA=$NEWSHA "$SCRIPT" update >/dev/null 2>&1; then
  ng "fail-fast on non-strict-semver context7 version"
else
  ok "fail-fast on non-strict-semver context7 version"
fi

# 15. bump-version: version 行が厳密 X.Y.Z でない（例: 1.2）場合は die し、壊れた値を書き込まない
fb13="$TMP/d_before.yml"; fa13="$TMP/d_after.yml"
printf 'name: p\nversion: 1.2\nx: old\n' > "$fb13"
printf 'name: p\nversion: 1.2\nx: new\n' > "$fa13"
if "$SCRIPT" bump-version "$fa13" "$fb13" >/dev/null 2>&1; then
  ng "fail-fast on malformed version line (not strict X.Y.Z)"
else
  ok "fail-fast on malformed version line (not strict X.Y.Z)"
fi

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
