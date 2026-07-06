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

die(){ echo "ERROR: $*" >&2; exit 3; }
count(){ grep -oE "$1" "$2" 2>/dev/null | wc -l | tr -d ' '; }

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

cmd_update(){
  local dry=0; [ "${1:-}" = "--dry-run" ] && dry=1

  # fail-fast(1): 各 anchor はちょうど 1 回マッチすること
  [ "$(count "$CONTEXT7_RE" "$MCP_FILE")" = "1" ] || die "context7 anchor not found exactly once in $MCP_FILE"
  [ "$(count "$SERENA_RE" "$MCP_FILE")" = "1" ] || die "serena anchor not found exactly once in $MCP_FILE"

  # fail-fast(2): 最新版の解決失敗は silent skip せず非ゼロ終了
  local c7 sr
  c7="$(resolve_context7)"; [ -n "$c7" ] || die "failed to resolve context7 version (npm view)"
  sr="$(resolve_serena)"; [ -n "$sr" ] || die "failed to resolve serena sha (gh api)"

  local work; work="$(mktemp)"; cp "$MCP_FILE" "$work"
  perl -i -pe 's{(\@upstash/context7-mcp\@)[0-9]+\.[0-9]+\.[0-9]+}{${1}'"$c7"'}g' "$work"
  perl -i -pe 's{(github\.com/oraios/serena\@)[0-9a-f]{40}}{${1}'"$sr"'}g' "$work"

  if [ "$dry" = "1" ]; then
    diff -u "$MCP_FILE" "$work" || true
    rm -f "$work"
  else
    mv "$work" "$MCP_FILE"
  fi
}

cmd_bump_version(){
  local file="$1" before="$2"
  if diff -q <(grep -v '^version:' "$before") <(grep -v '^version:' "$file") >/dev/null; then
    return 0   # version 行以外に差分なし → bump しない
  fi
  local cur; cur="$(grep -E '^version:[[:space:]]*[0-9]' "$file" | head -1 | sed -E 's/^version:[[:space:]]*//')"
  local MA MI PA; IFS=. read -r MA MI PA <<<"$cur"
  local new="$MA.$MI.$((PA+1))"
  perl -i -pe 'BEGIN{$d=0} if(!$d && /^version:\s*\S+/){s/^version:\s*\S+/version: '"$new"'/; $d=1}' "$file"
}

case "${1:-}" in
  update) shift; cmd_update "$@";;
  bump-version) shift; cmd_bump_version "$@";;
  *) die "usage: apm-pins.sh update [--dry-run]";;
esac
