#!/usr/bin/env bash
# apm.yml の pin 操作 CLI。APM 純正が触れない command/args 埋め込み版
# (context7 / serena) の更新、version patch bump、PR 本文生成を行う。
# 設計: docs/superpowers/specs/2026-07-05-apm-deps-auto-update-design.md
set -euo pipefail

MCP_FILE="${APM_MCP_FILE:-mcp-toolkit/apm.yml}"
BASE_FILE="${APM_BASE_FILE:-base/apm.yml}"

# anchors (ERE)
CONTEXT7_RE='@upstash/context7-mcp@[0-9]+\.[0-9]+\.[0-9]+'
SERENA_RE='github\.com/oraios/serena@[0-9a-f]{40}'
CHROME_RE='chrome-devtools-mcp#[0-9a-f]{40}'
SUPER_RE='obra/superpowers#[0-9a-f]{40}'
# chrome-devtools のバージョンを書き添えた人間向けコメント（fail-fast 対象外・best-effort 同期）
CHROME_COMMENT_RE='chrome-devtools-mcp@[0-9]+\.[0-9]+\.[0-9]+'

die(){ echo "ERROR: $*" >&2; exit 3; }
# grep は 0 マッチで exit 1 になるため、set -euo pipefail 下でも中断しないよう吸収する
count(){ { grep -oE "$1" "$2" 2>/dev/null || true; } | wc -l | tr -d ' '; }

resolve_context7(){
  if [ -n "${APM_PINS_CONTEXT7_VERSION:-}" ]; then echo "$APM_PINS_CONTEXT7_VERSION"; return; fi
  npm view @upstash/context7-mcp version 2>/dev/null || true
}
resolve_serena(){
  if [ -n "${APM_PINS_SERENA_SHA:-}" ]; then echo "$APM_PINS_SERENA_SHA"; return; fi
  local tag; tag="$(gh api repos/oraios/serena/releases/latest --jq .tag_name 2>/dev/null || true)"
  [ -z "$tag" ] && return
  gh api "repos/oraios/serena/commits/$tag" --jq .sha 2>/dev/null || true
}
resolve_superpowers(){
  if [ -n "${APM_PINS_SUPERPOWERS_SHA:-}" ]; then echo "$APM_PINS_SUPERPOWERS_SHA"; return; fi
  local tag; tag="$(gh api repos/obra/superpowers/releases/latest --jq .tag_name 2>/dev/null || true)"
  [ -z "$tag" ] && return
  gh api "repos/obra/superpowers/commits/$tag" --jq .sha 2>/dev/null || true
}
# chrome-devtools-mcp は lightweight tag（annotated ではない）で release されているため
# `gh api .../commits/<tag>` で tag 種別非依存に解決する。tag 自体も返す
# ("<tag>\t<sha>" 形式) のは、コメント中のバージョン表記(chrome-devtools-mcp@X.Y.Z) を
# best-effort で同期するため（呼び出し元はコマンド置換のサブシェルを経由するので、
# ここでグローバル変数に代入しても呼び出し元には伝播しない）。
resolve_chrome(){
  if [ -n "${APM_PINS_CHROME_SHA:-}" ]; then printf '\t%s\n' "$APM_PINS_CHROME_SHA"; return; fi
  local tag; tag="$(gh api repos/ChromeDevTools/chrome-devtools-mcp/releases/latest --jq .tag_name 2>/dev/null || true)"
  [ -z "$tag" ] && { printf '\t\n'; return; }
  local sha; sha="$(gh api "repos/ChromeDevTools/chrome-devtools-mcp/commits/$tag" --jq .sha 2>/dev/null || true)"
  printf '%s\t%s\n' "$tag" "$sha"
}

cmd_update(){
  local dry=0; [ "${1:-}" = "--dry-run" ] && dry=1

  # fail-fast(1): 各 anchor はちょうど 1 回マッチすること
  [ "$(count "$SUPER_RE" "$BASE_FILE")" = "1" ] || die "superpowers anchor not found exactly once in $BASE_FILE"
  [ "$(count "$CHROME_RE" "$MCP_FILE")" = "1" ] || die "chrome-devtools anchor not found exactly once in $MCP_FILE"
  [ "$(count "$CONTEXT7_RE" "$MCP_FILE")" = "1" ] || die "context7 anchor not found exactly once in $MCP_FILE"
  [ "$(count "$SERENA_RE" "$MCP_FILE")" = "1" ] || die "serena anchor not found exactly once in $MCP_FILE"

  # fail-fast(2): 最新版の解決失敗は silent skip せず非ゼロ終了
  local sp chrome_out chrome_tag ch c7 sr
  sp="$(resolve_superpowers)"; [ -n "$sp" ] || die "failed to resolve superpowers sha (gh api)"
  chrome_out="$(resolve_chrome)"
  chrome_tag="${chrome_out%%$'\t'*}"
  ch="${chrome_out#*$'\t'}"
  [ -n "$ch" ] || die "failed to resolve chrome-devtools sha (gh api)"
  c7="$(resolve_context7)"; [ -n "$c7" ] || die "failed to resolve context7 version (npm view)"
  sr="$(resolve_serena)"; [ -n "$sr" ] || die "failed to resolve serena sha (gh api)"

  # fail-fast(3): 解決値の形式検証（不正値で apm.yml を汚さない）
  printf '%s' "$sp" | grep -qE '^[0-9a-f]{40}$' || die "resolved superpowers sha has unexpected format: $sp"
  printf '%s' "$ch" | grep -qE '^[0-9a-f]{40}$' || die "resolved chrome-devtools sha has unexpected format: $ch"
  printf '%s' "$c7" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || die "resolved context7 version has unexpected format: $c7"
  printf '%s' "$sr" | grep -qE '^[0-9a-f]{40}$' || die "resolved serena sha has unexpected format: $sr"

  local base_work mcp_work
  base_work="$(mktemp)"; cp "$BASE_FILE" "$base_work"
  mcp_work="$(mktemp)"; cp "$MCP_FILE" "$mcp_work"

  perl -i -pe 's{(obra/superpowers#)[0-9a-f]{40}}{${1}'"$sp"'}g' "$base_work"
  perl -i -pe 's{(chrome-devtools-mcp#)[0-9a-f]{40}}{${1}'"$ch"'}g' "$mcp_work"
  perl -i -pe 's{(\@upstash/context7-mcp\@)[0-9]+\.[0-9]+\.[0-9]+}{${1}'"$c7"'}g' "$mcp_work"
  perl -i -pe 's{(github\.com/oraios/serena\@)[0-9a-f]{40}}{${1}'"$sr"'}g' "$mcp_work"

  # chrome-devtools のバージョンコメント同期 (best-effort): tag から X.Y.Z を抽出できて、
  # かつコメントの anchor が存在する場合のみ置換。どちらか欠けても fail-fast せず no-op
  if [ -n "$chrome_tag" ]; then
    local chrome_ver
    chrome_ver="$(printf '%s' "$chrome_tag" | sed -E 's/.*v//')"
    if printf '%s' "$chrome_ver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
      && grep -qE "$CHROME_COMMENT_RE" "$mcp_work"; then
      perl -i -pe 's{(chrome-devtools-mcp\@)[0-9]+\.[0-9]+\.[0-9]+}{${1}'"$chrome_ver"'}g' "$mcp_work"
    fi
  fi

  if [ "$dry" = "1" ]; then
    diff -u "$BASE_FILE" "$base_work" || true
    diff -u "$MCP_FILE" "$mcp_work" || true
    rm -f "$base_work" "$mcp_work"
  else
    mv "$base_work" "$BASE_FILE"
    mv "$mcp_work" "$MCP_FILE"
  fi
}

cmd_bump_version(){
  local file="$1" before="$2"
  if diff -q <(grep -v '^version:' "$before") <(grep -v '^version:' "$file") >/dev/null; then
    return 0   # version 行以外に差分なし → bump しない
  fi
  local cur; cur="$(grep -E '^version:[[:space:]]*[0-9]' "$file" | head -1 | sed -E 's/^version:[[:space:]]*//' || true)"
  printf '%s' "$cur" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || die "version line in $file has unexpected format: '$cur'"
  local MA MI PA; IFS=. read -r MA MI PA <<<"$cur"
  local new="$MA.$MI.$((PA+1))"
  perl -i -pe 'BEGIN{$d=0} if(!$d && /^version:\s*\S+/){s/^version:\s*\S+/version: '"$new"'/; $d=1}' "$file"
}

# 指定ファイル群から 4 pin を "key<TAB>value" で出力
_pins(){ # base-file mcp-file
  local bf="$1" mf="$2"
  local s c ct se
  # 各抽出パイプラインは grep の no-match(exit 1) や head の SIGPIPE で
  # set -euo pipefail 下で中断し得るため、`|| true` で吸収し未検出は空文字に倒す
  s="$(grep -oE "$SUPER_RE" "$bf" 2>/dev/null | grep -oE '[0-9a-f]{40}' | head -1 || true)"
  c="$(grep -oE "$CHROME_RE" "$mf" 2>/dev/null | grep -oE '[0-9a-f]{40}' | head -1 || true)"
  ct="$(grep -oE "$CONTEXT7_RE" "$mf" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  se="$(grep -oE "$SERENA_RE" "$mf" 2>/dev/null | grep -oE '[0-9a-f]{40}' | head -1 || true)"
  printf 'superpowers\t%s\nchrome-devtools\t%s\ncontext7\t%s\nserena\t%s\n' "$s" "$c" "$ct" "$se"
}
_short(){ if printf '%s' "$1" | grep -qE '^[0-9a-f]{40}$'; then printf '%.7s' "$1"; else printf '%s' "$1"; fi; }

cmd_render_body(){
  local bd="$1"
  local before after key ov nv rows=""
  before="$(_pins "$bd/base.apm.yml" "$bd/mcp.apm.yml")"
  after="$(_pins "$BASE_FILE" "$MCP_FILE")"
  while IFS=$'\t' read -r key ov; do
    nv="$(echo "$after" | awk -F'\t' -v k="$key" '$1==k{print $2}')"
    if [ "$ov" != "$nv" ]; then
      rows="$rows| $key | \`$(_short "$ov")\` | \`$(_short "$nv")\` |
"
    fi
  done <<<"$before"
  if [ -z "$rows" ]; then echo "apm 依存 pin の更新はありません。"; return; fi
  printf '## apm 依存 pin 更新\n\n| 依存 | 変更前 | 変更後 |\n| --- | --- | --- |\n%s' "$rows"
}

case "${1:-}" in
  update) shift; cmd_update "$@";;
  bump-version) shift; cmd_bump_version "$@";;
  render-body) shift; cmd_render_body "$@";;
  *) die "usage: apm-pins.sh update [--dry-run] | bump-version <file> <before-file> | render-body <before-dir>";;
esac
