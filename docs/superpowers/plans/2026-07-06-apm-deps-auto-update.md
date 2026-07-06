# apm 依存 pin CI 自動更新 実装プラン

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** apm-config の上流依存 pin（superpowers / chrome-devtools / context7 / serena）を週次 + 手動で自動追従し、更新があれば PR を作る CI を追加する。

**Architecture:** ハイブリッド。`dependencies.apm` の git ref 2 件（superpowers / chrome-devtools）は `microsoft/apm-action` の `update:true`（apm 0.24.0 が SHA ピンを最新 release tag へ自動書換）で、`command`/`args` に版が埋め込まれた `dependencies.mcp` 2 件（context7 / serena）は独自スクリプト `scripts/apm-pins.sh` で更新。`apm.lock.yaml` を新規導入し、`peter-evans/create-pull-request` でローリング PR を作る。

**Tech Stack:** GitHub Actions / bash + perl / gh CLI / npm view / microsoft/apm-action / peter-evans/create-pull-request。ubuntu-latest 同梱ツールのみ（新規ランタイム追加なし）。

**設計 spec:** `docs/superpowers/specs/2026-07-05-apm-deps-auto-update-design.md`（本プランは spec に従う。矛盾時は spec 優先）

## Global Constraints

- apm CLI 版は **0.24.0** を明示 pin（apm-action の `apm-version`）。統一版の SSoT は `base/.apm/instructions/apm-workflow.instructions.md`。
- pin 形式: git 依存（superpowers / chrome-devtools / serena）は **commit SHA ピン維持**、context7 は **npm exact version ピン維持**。
- 「最新」の定義: git 依存は**最新 release tag → commit SHA**（main HEAD 追従はしない）。context7 は `npm view` の最新版。
- サードパーティ Action は **commit SHA で固定**（`@v1`/`@v8` の major tag のまま使わない）。対応バージョンをコメント併記。
- 更新順序を固定: **独自スクリプト（context7 / serena）→ apm-action（lockfile 生成）**。逆順は lockfile ドリフトを招く。
- コミット対象を **`base/apm.yml` / `mcp-toolkit/apm.yml` / 各 `apm.lock.yaml` に限定**。apm update の展開物はコミットしない。
- fail-fast: managed 依存の anchor が対象ファイルに 1 回マッチしなければ非ゼロ終了。release / npm 版取得不可のみ skip + warn。
- PR: 固定ブランチ `chore/apm-deps-update`、タイトル `chore(deps): apm 依存 pin を更新`（日本語 + Conventional Commits）、ラベル `dependencies`。
- speckit / deepwiki は対象外。

## File Structure

- `scripts/apm-pins.sh`（新規）— pin 操作 CLI。サブコマンド `update` / `bump-version` / `render-body`。context7 / serena の解決・fail-fast・外科的置換・版 patch bump・PR 本文生成を担う。
- `scripts/test-apm-pins.sh`（新規）— fixture ベースの単体テスト。ネットワーク非依存（解決値を環境変数で注入）。
- `.github/workflows/apm-update.yml`（新規）— トリガー・権限・実行順序・apm-action・PR 作成のオーケストレーション。
- `README.md`（修正）— 「更新フロー」節に自動更新ワークフローを追記。
- リポジトリ設定（コード外）— `dependencies` ラベル作成、Actions の PR 作成許可。
- `base/apm.lock.yaml` / `mcp-toolkit/apm.lock.yaml`（新規）— ワークフロー初回 dispatch 実行が生成し、その PR で導入。

---

### Task 1: `apm-pins.sh` スケルトン + `update`（context7 / serena）

**Files:**
- Create: `scripts/apm-pins.sh`
- Test: `scripts/test-apm-pins.sh`

**Interfaces:**
- Produces:
  - `apm-pins.sh update [--dry-run]` — `mcp-toolkit/apm.yml`（`APM_MCP_FILE` で上書き可）の context7 版と serena SHA を最新へ書換。`--dry-run` は差分表示のみ。解決値は `APM_PINS_CONTEXT7_VERSION` / `APM_PINS_SERENA_SHA` があればそれを使い、無ければ `npm view` / `gh api` で解決。anchor が 1 回マッチしなければ exit 3。**解決値が空（npm/gh 解決失敗）でも exit 3**（context7/serena は常に存在するため空＝実障害。silent skip しない）。

- [ ] **Step 1: 失敗するテストを書く（update の置換・fail-fast・冪等・dry-run）**

Create `scripts/test-apm-pins.sh`:

```bash
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
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `bash scripts/test-apm-pins.sh`
Expected: FAIL（`apm-pins.sh` が無いためエラー）

- [ ] **Step 3: `apm-pins.sh` の `update` を実装**

Create `scripts/apm-pins.sh`:

```bash
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

case "${1:-}" in
  update) shift; cmd_update "$@";;
  *) die "usage: apm-pins.sh update [--dry-run]";;
esac
```

Then: `chmod +x scripts/apm-pins.sh scripts/test-apm-pins.sh`

- [ ] **Step 4: テストが通ることを確認**

Run: `bash scripts/test-apm-pins.sh`
Expected: PASS（`4 passed, 0 failed`）

- [ ] **Step 5: 実データ dry-run で context7 3.2.0→3.2.2 を確認**

Run: `./scripts/apm-pins.sh update --dry-run`
Expected: `mcp-toolkit/apm.yml` の context7 が `3.2.0 → 3.2.x`（現時点 3.2.2）に変わる diff が表示され、ファイルは変更されない（`git diff --quiet mcp-toolkit/apm.yml` が 0）

- [ ] **Step 6: コミット**

```bash
git add scripts/apm-pins.sh scripts/test-apm-pins.sh
git commit -m "feat(scripts): context7/serena pin を更新する apm-pins.sh update を追加"
```

---

### Task 2: `apm-pins.sh bump-version`（変更されたパッケージの patch 上げ）

**Files:**
- Modify: `scripts/apm-pins.sh`
- Modify: `scripts/test-apm-pins.sh`

**Interfaces:**
- Consumes: Task 1 の `apm-pins.sh`。
- Produces: `apm-pins.sh bump-version <file> <before-file>` — `version:` 行を除いた内容が `before-file` と異なれば `<file>` の `version: X.Y.Z` を `X.Y.(Z+1)` に更新。同一なら無変更。

- [ ] **Step 1: 失敗するテストを追記**

`scripts/test-apm-pins.sh` の `echo "== ...` 直前に追記:

```bash
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
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `bash scripts/test-apm-pins.sh`
Expected: FAIL（`bump-version` 未実装で usage エラー→非ゼロ）

- [ ] **Step 3: `bump-version` を実装**

`scripts/apm-pins.sh` の `case` の前に関数を追加:

```bash
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
```

`case` に分岐を追加:

```bash
  bump-version) shift; cmd_bump_version "$@";;
```

- [ ] **Step 4: テストが通ることを確認**

Run: `bash scripts/test-apm-pins.sh`
Expected: PASS（`6 passed, 0 failed`）

- [ ] **Step 5: コミット**

```bash
git add scripts/apm-pins.sh scripts/test-apm-pins.sh
git commit -m "feat(scripts): 変更されたパッケージを patch 上げする bump-version を追加"
```

---

### Task 3: `apm-pins.sh render-body`（PR 本文の差分表を生成）

**Files:**
- Modify: `scripts/apm-pins.sh`
- Modify: `scripts/test-apm-pins.sh`

**Interfaces:**
- Consumes: Task 1/2 の `apm-pins.sh`。before スナップショットのディレクトリ（`base.apm.yml` / `mcp.apm.yml` を含む）。
- Produces: `apm-pins.sh render-body <before-dir>` — before スナップショットと現在の `BASE_FILE`/`MCP_FILE` を比較し、変化した pin（superpowers / chrome-devtools / context7 / serena）を markdown 表で stdout に出力。変化ゼロなら「更新なし」を出力。

- [ ] **Step 1: 失敗するテストを追記**

`scripts/test-apm-pins.sh` の `echo "== ...` 直前に追記:

```bash
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
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `bash scripts/test-apm-pins.sh`
Expected: FAIL（`render-body` 未実装）

- [ ] **Step 3: `render-body` を実装**

`scripts/apm-pins.sh` に関数を追加:

```bash
# 指定ファイル群から 4 pin を "key<TAB>value" で出力
_pins(){ # base-file mcp-file
  local bf="$1" mf="$2"
  local s c ct se
  s="$(grep -oE "$SUPER_RE" "$bf" 2>/dev/null | grep -oE '[0-9a-f]{40}' | head -1)"
  c="$(grep -oE "$CHROME_RE" "$mf" 2>/dev/null | grep -oE '[0-9a-f]{40}' | head -1)"
  ct="$(grep -oE "$CONTEXT7_RE" "$mf" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  se="$(grep -oE "$SERENA_RE" "$mf" 2>/dev/null | grep -oE '[0-9a-f]{40}' | head -1)"
  printf 'superpowers\t%s\nchrome-devtools\t%s\ncontext7\t%s\nserena\t%s\n' "$s" "$c" "$ct" "$se"
}
_short(){ case "$1" in [0-9a-f]*) printf '%.7s' "$1";; *) printf '%s' "$1";; esac; }

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
```

`case` に分岐を追加:

```bash
  render-body) shift; cmd_render_body "$@";;
```

- [ ] **Step 4: テストが通ることを確認**

Run: `bash scripts/test-apm-pins.sh`
Expected: PASS（`9 passed, 0 failed`）

- [ ] **Step 5: コミット**

```bash
git add scripts/apm-pins.sh scripts/test-apm-pins.sh
git commit -m "feat(scripts): PR 本文の差分表を生成する render-body を追加"
```

---

### Task 4: ワークフロー `apm-update.yml`（オーケストレーション）

**Files:**
- Create: `.github/workflows/apm-update.yml`

**Interfaces:**
- Consumes: `scripts/apm-pins.sh` の `update` / `bump-version` / `render-body`。
- Produces: 週次 + 手動で pin を更新し PR を作る CI。初回 `workflow_dispatch` 実行が `apm.lock.yaml` を生成する。

- [ ] **Step 1: サードパーティ Action の commit SHA を解決**

Run（実装時点の最新リリースの SHA を取得。バージョンはコメント併記に使う）:

```bash
gh api repos/actions/checkout/commits/v4 --jq '.sha'
gh api repos/microsoft/apm-action/commits/v1.10.0 --jq '.sha'
gh release view --repo peter-evans/create-pull-request --json tagName --jq '.tagName'   # 最新 v8 を確認
gh api repos/peter-evans/create-pull-request/commits/<上のtag> --jq '.sha'
```

Expected: 各 Action の 40hex SHA を得る（次の Step で `<sha>` に埋める）

- [ ] **Step 2: ワークフローを作成**

Create `.github/workflows/apm-update.yml`（`<sha>` は Step 1 の値に置換、コメントの版も合わせる）:

```yaml
name: apm-update
on:
  schedule:
    - cron: "0 0 * * 1"     # 毎週月曜 00:00 UTC
  workflow_dispatch: {}
permissions:
  contents: write
  pull-requests: write
concurrency:
  group: apm-update
  cancel-in-progress: false
jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha>            # actions/checkout v4

      - name: Snapshot current manifests
        run: |
          mkdir -p "$RUNNER_TEMP/apm-before"
          cp base/apm.yml "$RUNNER_TEMP/apm-before/base.apm.yml"
          cp mcp-toolkit/apm.yml "$RUNNER_TEMP/apm-before/mcp.apm.yml"

      # 順序固定: 独自スクリプト(context7/serena) を先に(§5.0)
      - name: Update command-embedded MCP versions (context7 / serena)
        env:
          GH_TOKEN: ${{ github.token }}
        run: ./scripts/apm-pins.sh update

      # その後 apm-action(update:true) が git ref を追従し apm.lock.yaml を生成
      - name: Refresh dependencies.apm pins + lockfile (base)
        uses: microsoft/apm-action@<sha>        # apm-action v1.10.0
        with:
          working-directory: base
          apm-version: "0.24.0"
          update: "true"

      - name: Refresh dependencies.apm pins + lockfile (mcp-toolkit)
        uses: microsoft/apm-action@<sha>        # apm-action v1.10.0
        with:
          working-directory: mcp-toolkit
          apm-version: "0.24.0"
          update: "true"

      - name: Patch-bump changed packages
        run: |
          ./scripts/apm-pins.sh bump-version base/apm.yml "$RUNNER_TEMP/apm-before/base.apm.yml"
          ./scripts/apm-pins.sh bump-version mcp-toolkit/apm.yml "$RUNNER_TEMP/apm-before/mcp.apm.yml"

      - name: Render PR body
        run: ./scripts/apm-pins.sh render-body "$RUNNER_TEMP/apm-before" > "$RUNNER_TEMP/apm-pr-body.md"

      - name: Create or update PR
        uses: peter-evans/create-pull-request@<sha>   # create-pull-request v8.x
        with:
          branch: chore/apm-deps-update
          delete-branch: true
          title: "chore(deps): apm 依存 pin を更新"
          body-path: ${{ runner.temp }}/apm-pr-body.md
          labels: dependencies
          commit-message: "chore(deps): apm 依存 pin を更新"
          add-paths: |
            base/apm.yml
            base/apm.lock.yaml
            mcp-toolkit/apm.yml
            mcp-toolkit/apm.lock.yaml
```

- [ ] **Step 3: ワークフローの構文検証**

Run（actionlint があれば優先。無ければ YAML パースで代用）:

```bash
actionlint .github/workflows/apm-update.yml || \
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/apm-update.yml')); print('YAML OK')"
```

Expected: エラーなし（`YAML OK` または actionlint 無出力）

- [ ] **Step 4: コミット**

```bash
git add .github/workflows/apm-update.yml
git commit -m "feat(ci): apm 依存 pin を自動追従し PR を作る apm-update ワークフローを追加"
```

- [ ] **Step 5: リポジトリ設定を投入（Task 6 と重複可・PR マージ前に実施）**

Run:

```bash
gh label create dependencies --color 0366d6 --description "依存更新" --repo ROhta/apm-config || echo "label exists"
gh api -X PUT repos/ROhta/apm-config/actions/permissions/workflow \
  -f default_workflow_permissions=write -F can_approve_pull_request_reviews=true
```

Expected: ラベル作成（または既存メッセージ）、権限 API が 204/200

- [ ] **Step 6: 初回 dispatch 実行で lockfile 生成と PR 作成を検証**

Run:

```bash
gh workflow run apm-update.yml --repo ROhta/apm-config
sleep 10 && gh run list --workflow apm-update.yml --repo ROhta/apm-config -L 1
# 完了後、生成 PR を確認
gh pr list --repo ROhta/apm-config --head chore/apm-deps-update --json number,files
```

Expected: 実行成功。PR `chore/apm-deps-update` が作られ、変更ファイルが `base/apm.yml` / `base/apm.lock.yaml` / `mcp-toolkit/apm.yml` / `mcp-toolkit/apm.lock.yaml` **のみ**（apm update の展開物＝`.claude/`・`.github/instructions/` 等が含まれないこと）。context7 は 3.2.2 へ更新されている。

- [ ] **Step 7: 2 回目実行でローリング更新（PR 乱立なし）を検証**

Run: `gh workflow run apm-update.yml --repo ROhta/apm-config` → 完了後 `gh pr list --head chore/apm-deps-update`
Expected: 新規 PR が増えず、既存 PR が更新される（差分がなければ PR 変化なし）

---

### Task 5: README「更新フロー」に自動更新を追記

**Files:**
- Modify: `README.md`（「## 更新フロー」節）

**Interfaces:**
- Consumes: Task 4 のワークフロー名 `apm-update.yml`。

- [ ] **Step 1: 「更新フロー」節に自動更新の記述を追加**

`README.md` の「## 更新フロー」節の先頭（`1. 本リポジトリの ...` の前）に追記:

```markdown
上流依存 pin（superpowers / chrome-devtools / serena / context7）の追従は
`.github/workflows/apm-update.yml` が**週次（月曜）+ 手動**で自動化する。更新があれば
`chore/apm-deps-update` ブランチにローリング PR を作るので、通常は手動編集不要。
手動で追従・確認したい場合は以下の従来手順も使える。
```

- [ ] **Step 2: 記述の整合を確認**

Run: `grep -n "apm-update.yml" README.md`
Expected: 追記した 1 行がヒットし、既存の「更新フロー」手順（context7/serena/chrome-devtools の手動 pin 更新）と矛盾しない（自動が主・手動が補足の位置づけ）

- [ ] **Step 3: コミット**

```bash
git add README.md
git commit -m "docs(readme): 更新フローに apm-update ワークフローによる自動追従を追記"
```

---

### Task 6: 実装 PR の作成（#7）

**Files:** なし（PR 操作のみ）

- [ ] **Step 1: テストを最終確認**

Run: `bash scripts/test-apm-pins.sh`
Expected: PASS（`9 passed, 0 failed`）

- [ ] **Step 2: ブランチを最新 main に追従**

```bash
git fetch origin
git merge origin/main --no-edit
```

Expected: 衝突なし（衝突時は解消してコミット）

- [ ] **Step 3: 実装 PR を作成**

Run:

```bash
gh pr create --base main --assignee @me \
  --title "feat(ci): apm 依存 pin の自動更新ワークフローを追加 (#7)" \
  --body "Closes #7。設計 spec (\`docs/superpowers/specs/2026-07-05-apm-deps-auto-update-design.md\`) に基づく実装。apm-pins.sh(context7/serena) + apm-action(superpowers/chrome-devtools) + peter-evans で週次/手動の pin 追従 PR を作る。lockfile を新規導入。"
```

Expected: PR が作成される（spec PR #13 マージ後に出すなら本 Task を後回しにする）

---

## Self-Review

**1. Spec coverage:**
- §2 対象 4 依存 → Task 1(context7/serena) + Task 4(apm-action で superpowers/chrome-devtools) ✅
- §3 決定事項（実装方式・apm-version 0.24.0・pin 形式・lockfile・順序・version bump） → Global Constraints + Task 2/4 ✅
- §5.0 実行順序 → Task 4 Step 2 のステップ順で固定 ✅
- §5.1 apm-action → Task 4 ✅ / §5.2 独自 → Task 1 ✅
- §6 変更検知・PR・コミット限定・version bump → Task 4（add-paths）+ Task 2 ✅
- §7 権限・トリガー・Action の SHA 固定 → Task 4 Step 1/2/5 ✅
- §8 trust → 更新ジョブは非ブロッキング（apm-action 実行のみ、approve 不要）。実展開検証は入れない（§9 任意を採用せず）→ プラン範囲外で整合 ✅
- §10 テスト観点（dry-run で 3.2.0→3.2.2 / fail-fast / 冪等 / 初回 lockfile / ローリング） → Task 1 Step5, テスト Step, Task 4 Step6/7 ✅
- lockfile 導入 → Task 4 Step6（初回 dispatch が生成） ✅
- リポジトリ設定（ラベル・PR 作成許可） → Task 4 Step5 ✅

**2. Placeholder scan:** `<sha>` は Task 4 Step1 で解決する具体値の差込点であり、手順が明示されているため placeholder ではない（SHA ピン方針上、実装時解決が正しい）。TBD/TODO なし。

**3. Type/シグネチャ整合:** `apm-pins.sh` のサブコマンド名（`update` / `bump-version` / `render-body`）と引数はワークフロー（Task 4）の呼び出しと一致。環境変数 `APM_MCP_FILE` / `APM_BASE_FILE` / `APM_PINS_CONTEXT7_VERSION` / `APM_PINS_SERENA_SHA` はテストと実装で一致。
