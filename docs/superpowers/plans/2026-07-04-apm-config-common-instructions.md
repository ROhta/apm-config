# apm-config 共通 instructions パッケージ整備 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** apm-config に共通 instructions を 3 パッケージ（base 4 ファイル追加 / mcp-toolkit 1 ファイル追加 / speckit 新規）として整備し、consumer 5 リポジトリが `apm.yml` 依存だけで受け取れる状態の土台を作る。

**Architecture:** これは設計ドキュメント（`docs/superpowers/specs/2026-07-04-instructions-migration-design.md`）§7 の **フェーズ 1（apm-config パッケージ著作）** のみを対象とする。フェーズ 2〜5（consumer 各リポジトリの移行）は、この PR がマージされてマージ SHA が確定し、参照実装 bingo で apm 0.23.1 の配信挙動が確認できた後に、別計画として作成する。理由: consumer の apm.yml ピンはこの PR のマージ SHA を必要とし、consumer の検証は 0.23.1 実挙動の確認に依存するため。

**Tech Stack:** APM（microsoft/apm）instructions パッケージ、Markdown + YAML frontmatter、`apm.yml` マニフェスト。apm-config はドキュメント/設定リポジトリでありユニットテスト基盤を持たないため、各タスクの「テスト」は `grep` による内容包含/除外アサーションと `apm.yml` の構造アサーション（普遍的に実行可能なシェルコマンド）で行う。実 `apm install` による配信挙動確認はフェーズ 2（bingo 参照実装）に委ねる。

## Global Constraints

すべてのタスクの要件に、以下が暗黙に含まれる（spec から逐語）。

- **パッケージ = 採用の単位**。APM の `includes: auto` は選択的除外ができないため「全 consumer に届いてよいか」が置き場所を決める。base = 全リポジトリ / mcp-toolkit = MCP 採用リポジトリ / speckit = Spec Kit 採用リポジトリ。
- パッケージバージョン: **base v1.1.0 / mcp-toolkit v1.1.0 / speckit v1.0.0**。
- 全パッケージの `apm.yml` は `targets: [claude, codex, copilot]` と `includes: auto` を持つ。
- ROhta 全リポジトリの apm CLI は **0.23.1** に揃える（instructions 本文にもこのバージョンを記載）。
- 生成物の**追跡例外は増やさない**（`.github/instructions/{pr-review,language}.instructions.md` のみ）。今回の instructions はコードレビュー指示ではないためクラウド Copilot 経路は不要。
- `dependencies.apm` は SHA ピン必須、vendor-neutral 方針（ベンダー組織リポジトリを直接指定しない）。
- 自然言語（説明・コメント）はすべて **日本語**（Conventional Commits の `<type>(<scope>):` は英語のまま）。
- **instructions 間の相互参照は相対パスリンクを使わずプレーンな名前で prose に書く**。配信後は同一ファイルが `.claude/rules/<name>.md` と `.github/instructions/<name>.instructions.md` の異なる名前で展開され、単一の相対リンクが両方で成立しないため（bingo 原本の `./x.instructions.md` リンクを踏襲しない）。
- 既存の `base/apm.yml` の `dependencies.apm`（`obra/superpowers` の pin）は変更しない。バージョン行のみ上げる。
- 作業ブランチ: `feat/common-instructions-packages`（`main` から分岐）。この実装は spec/plan の PR (#8) とは別 PR とする。

---

## 事前準備

- [ ] **Step 0: 実装ブランチを作成（計画ファイルがツリーに存在する起点から切る）**

この計画ファイルは spec と同じブランチ `docs/instructions-migration-design`（PR #8、未マージ）にしか存在しない。subagent 駆動実行は `docs/superpowers/plans/...` を読むため、計画ファイルが disk にある起点から分岐する必要がある。

**推奨**: PR #8（spec + plan、docs のみ）を先に main へマージしてから main を起点にする。consumer フェーズが依存するのは本 PR ではなく**実装 PR** のマージ SHA なので、PR #8 を先にマージしても後続に悪影響はない。

```bash
cd /home/ore/codes/apm-config
git fetch origin
git switch main && git pull --ff-only          # PR #8 マージ後の main を取得（計画ファイルを含む）
git switch -c feat/common-instructions-packages
```

**フォールバック**（PR #8 をまだマージしたくない場合）: 計画ファイルを含む PR #8 のブランチを起点にする。ただし実装 PR に spec/plan コミットが混ざる点に注意。

```bash
cd /home/ore/codes/apm-config
git fetch origin
git switch docs/instructions-migration-design && git pull --ff-only
git switch -c feat/common-instructions-packages
```

期待: `Switched to a new branch 'feat/common-instructions-packages'`

---

## Task 1: base/apm-plugins.instructions.md

**Files:**
- Create: `base/.apm/instructions/apm-plugins.instructions.md`

**Interfaces:**
- Produces: base パッケージに配信される「APM プラグイン管理ルール」。他ファイルからは「apm-plugins ルール」として名前参照される。

- [ ] **Step 1: ファイルを作成**

以下を全文書き込む（bingo 原本から「配信されるプラグイン」表と `pnpm apm-install` インストール手順節を除去し、リポジトリ固有依存の列挙を「各リポジトリの apm.yml を参照」に置換したもの）。

````markdown
---
description: APM (Agent Project Manager) を介した依存パッケージ (プラグイン bundle / 単一プリミティブ) の運用ルール
applyTo: "apm.yml"
---

# APM プラグイン管理ルール

## Source of Truth

`apm.yml` の `dependencies.apm` がこのリポジトリで使う APM 依存パッケージの Source of Truth。扱える形態は 2 種類:

- **プラグイン bundle**: Skills (SKILL.md) / commands / prompts / hooks / instructions / agents 等を 1 リポジトリにまとめたもの (例: `obra/superpowers`)
- **単一プリミティブ (virtual file)**: 既存リポジトリ内の特定の `*.instructions.md` / `*.prompt.md` / `SKILL.md` などを 1 ファイル単位で取り込むもの (例: `github/awesome-copilot/instructions/code-review-generic.instructions.md`)

`apm install` を実行すると、ここに宣言された依存が `apm_modules/` にダウンロードされ、各ターゲット向けに `.claude/rules/`, `.claude/skills/`, `.claude/commands/`, `.claude/hooks/`, `.agents/skills/`, `.github/instructions/`, `.github/prompts/`, `.github/hooks/` 等へ展開される (内容に応じて配信先が変わる)。Codex 向けには専用の配信先を持たない代わりに、`apm compile` 時に instructions / skills 内容が `AGENTS.md` に組み込まれる。

## 現在どのプラグインを使っているか

各リポジトリで実際に採用しているプラグイン (共通パッケージ `ROhta/apm-config/*`・汎用スキル・単一プリミティブ) は、そのリポジトリの `apm.yml` の `dependencies.apm` を参照する。共通パッケージ (base / mcp-toolkit / speckit) の内容を変えたい場合は提供元 apm-config を編集する。

### vendor-neutral 方針

`dependencies.apm` には特定 AI ベンダー (anthropics 等) 組織配下のリポジトリを直接指定せず、コミュニティ curated marketplace (`github/awesome-copilot`) や中立 OSS 作者リポジトリ (`obra/superpowers`) を経由する。理由: ベンダー組織のプラグインは「そのベンダーのランタイム前提」 (例: Claude Code の Stop hook + subagent 機構) で書かれていることが多く、Codex などのターゲットに同等機能が配信されないため。

## SHA ピン

`dependencies.apm` のエントリは **必ず `#<sha>` でピンする**。`apm install` で `unpinned -- add #tag or #sha to prevent drift` という警告が出るため気付ける。

```yaml
dependencies:
  apm:
    - github/awesome-copilot/instructions/code-review-generic.instructions.md#5b049e4e196c10aab8ddfd9e492323d08cf985b0
    - obra/superpowers#f2cbfbefebbfef77321e4c9abc9e949826bea9d7
```

理由: ピンしないと `apm install` 毎に上流の `main` を引いてしまい、各メンバーの開発体験が静かにドリフトする (ドリフト防止方針は apm-workflow ルールを参照)。

## プラグインの追加

### marketplace 経由 (推奨。検索用)

```bash
# 1. marketplace を一時的に register (global config のみ。apm.yml には影響しない)
apm marketplace add <owner>/<repo>
# 2. plugin を install (apm.yml に追記される)
apm install <plugin>@<marketplace-name>
# 3. unpinned 警告が出るので apm.lock.yaml の resolved_commit を見て #sha でピン
```

### 直接 GitHub から (marketplace 未登録のプラグイン)

```bash
apm install <owner>/<repo>#<sha>
# または path 指定 (プラグイン bundle のサブディレクトリ)
apm install <owner>/<repo>/<path>#<sha>
# または単一プリミティブファイル (instructions / prompts / skills など 1 ファイル指定)
apm install <owner>/<repo>/<path-to-file>.<ext>.md#<sha>
```

`apm.yml` に `<owner>/<repo>[/<path>]#<sha>` 形式が直接書ければ、global の marketplace 登録は **不要**。チームメイトは `git clone` 後 `apm install` だけで同じプラグインを取得できる。

`<path-to-file>.instructions.md` のように **末尾がファイル名** の場合、APM は単一プリミティブ (virtual file) として取り込む。プラグイン全体を取り込まずに必要な 1 ファイルだけを依存にしたい時 (例: 汎用 instructions のみが欲しいケース) に使う。

## プラグインの削除

`apm.yml` の `dependencies.apm` 配下から該当行を削除した後、`apm install` を再実行する。 `apm_modules/<owner>/<repo>/` と展開済みファイルが残った場合は手動で掃除する。(`apm uninstall <package>` の動作は未検証)

## 生成物の場所

`apm install` がプラグインを展開する先。原則すべて `.gitignore` 対象（例外は `.github/instructions/{pr-review,language}.instructions.md` のみ。クラウド Copilot 経路確保のため追跡）。

| パス                          | 由来                                                                         |
| ----------------------------- | ---------------------------------------------------------------------------- |
| `apm_modules/<owner>/<repo>/` | 依存のソースコピー (cache)                                                   |
| `.claude/rules/`              | Claude Code 用 instructions (virtual file の `*.instructions.md` 等の展開先) |
| `.claude/skills/`             | Claude Code Skills (SKILL.md)                                                |
| `.agents/skills/`             | クロスクライアント Skills (Cursor / Codex / Gemini 等が読む)                 |
| `.claude/commands/`           | Claude Code スラッシュコマンド                                               |
| `.claude/hooks/`              | Claude Code フックスクリプト                                                 |
| `.claude/apm-hooks.json`      | APM がフック登録に用いる索引                                                 |
| `.claude/settings.json`       | フック有効化等のクライアント設定                                             |
| `.github/instructions/`       | GitHub Copilot 用 instructions (`*.instructions.md`)。うち base 由来の pr-review / language のみ追跡 |
| `.github/prompts/`            | GitHub Copilot プロンプト (`*.prompt.md`)                                    |
| `.github/hooks/`              | GitHub 用フック (Copilot CLI 等)                                             |

`.claude/settings.json` を ignore しているのは、APM がプラグインのフック有効化のために絶対パスを書き込むため (リポジトリで共有しても各環境でパスが食い違って意味がない)。個人の Claude Code 設定はユーザースコープ (`~/.claude/settings.json`) または `.claude/settings.local.json` (Claude Code の慣習で per-user 扱い) に置くこと。
````

- [ ] **Step 2: 内容アサーションを実行**

```bash
cd /home/ore/codes/apm-config
F=base/.apm/instructions/apm-plugins.instructions.md
head -1 "$F" | grep -qx -- '---' && echo "frontmatter OK"
grep -q '^applyTo:' "$F" && echo "applyTo OK"
grep -q 'vendor-neutral 方針' "$F" && echo "keep vendor-neutral OK"
grep -q 'SHA ピン' "$F" && echo "keep SHA-pin OK"
! grep -q 'pnpm apm-install' "$F" && echo "removed pnpm apm-install OK"
! grep -q 'dedupe-apm-lock' "$F" && echo "removed dedupe OK"
! grep -q '配信されるプラグイン' "$F" && echo "removed plugin table OK"
```

期待: 7 行すべて `... OK` が出力される（`grep` 失敗があれば該当行が出ない → 修正）。

- [ ] **Step 3: コミット**

```bash
git add base/.apm/instructions/apm-plugins.instructions.md
git commit -m "feat(base): 汎用化した apm-plugins instructions を追加"
```

---

## Task 2: base/apm-workflow.instructions.md

**Files:**
- Create: `base/.apm/instructions/apm-workflow.instructions.md`

**Interfaces:**
- Consumes: apm-plugins ルール（名前参照）、mcp-servers ルール（名前参照）。
- Produces: base 配信の「APM 運用ルール」。他ファイルから「apm-workflow ルール」として名前参照される。

- [ ] **Step 1: ファイルを作成**

以下を全文書き込む（bingo 原本から `pnpm apm-install` / dedupe 参照を除去し `apm install` に一般化、apm 0.23.1 を明記、相対リンクをプレーン名参照に置換。Spec Kit 連携は含めない — speckit パッケージへ）。

````markdown
---
description: APM (Agent Project Manager) を介した AI エージェント指示の運用ルール
applyTo: ".apm/**"
---

# APM 運用ルール

## Source of Truth

`.apm/instructions/*.instructions.md` がリポジトリ固有の AI エージェント向け指示の Source of Truth。ここを編集することで、Claude Code / Codex CLI / GitHub Copilot すべてに同じ指示が届く。

全リポジトリ共通の指示 (言語ルール・PR レビュー観点・開発/リリースフロー) は `apm.yml` の `dependencies.apm` で参照する共通パッケージ [`ROhta/apm-config/base`](https://github.com/ROhta/apm-config) が、共通 MCP サーバーセットは [`ROhta/apm-config/mcp-toolkit`](https://github.com/ROhta/apm-config) が Source of Truth。共通ルールを直したい場合は本リポジトリではなく apm-config を編集し、`apm update` で取り込む。

## APM CLI 本体のバージョン

APM CLI 本体 (`apm` バイナリ) のバージョンは `mise.toml` (`github:microsoft/apm`) を SSoT として管理する。更新は `mise.toml` の version を上げて `mise install` する。`apm self-update` や `apm doctor` の更新催促には従わない (mise 管理外のグローバルインストールを増やさないため)。ROhta の各リポジトリは apm **0.23.1** で揃える。

## ファイルの管理方針

| パス | 役割 | リポジトリ追跡 |
| --- | --- | --- |
| `.apm/instructions/*.instructions.md` | **Source of Truth (instructions 用、人間が編集する)** | ✅ 追跡する |
| `apm.yml` の `dependencies.mcp` | リポジトリ固有 MCP 用 (人間が編集)。共通 MCP セットの SoT は apm-config/mcp-toolkit | ✅ 追跡する |
| `apm.yml` の `dependencies.apm` | **Source of Truth (APM パッケージ用、人間が編集する)** | ✅ 追跡する |
| `.github/copilot-instructions.md` | Copilot Code Review に SoT への参照を伝えるスタブ | ✅ 追跡する |
| `.github/instructions/pr-review.instructions.md` / `language.instructions.md` | `apm install` で生成 (base 由来)。クラウドの Copilot Code Review 用に例外的に追跡 | ✅ 追跡する |
| `.github/instructions/` のその他 (`*.instructions.md`) | `apm install` で生成。SoT は `.apm/` にあり重複のため追跡しない | ❌ 追跡しない |
| `.claude/rules/*.md` | `apm install` で生成 (Claude Code 補助) | ❌ 追跡しない |
| `CLAUDE.md` / `AGENTS.md` (各所) | `apm compile` で生成 | ❌ 追跡しない |
| `apm.lock.yaml` | `apm install` で生成 (整合性検証・オーファン検出・厳密な再現性のため例外的に追跡) | ✅ 追跡する |
| `.mcp.json` | `apm install` で生成 (Claude Code MCP 設定) | ❌ 追跡しない |
| `.vscode/mcp.json` | `apm install` で生成 (GitHub Copilot in VS Code MCP 設定) | ❌ 追跡しない |
| `.codex/config.toml` | `apm install` で生成 (Codex CLI MCP 設定) | ❌ 追跡しない |
| `apm_modules/`, `.agents/skills/`, `.claude/skills/`, `.claude/commands/`, `.claude/hooks/`, `.claude/settings.json`, `.claude/apm-hooks.json`, `.github/prompts/`, `.github/hooks/` | `apm install` で生成 (APM プラグイン展開先) | ❌ 追跡しない |

## ローカルでの作業

`.apm/instructions/` または `apm.yml` を編集後、ローカルで以下を実行することで生成物が更新される (任意)。

```bash
apm install   # 全プリミティブを再デプロイ (.github/instructions/, .claude/rules/, .mcp.json, .vscode/mcp.json, .codex/config.toml) + apm.lock.yaml 更新
apm compile   # CLAUDE.md / AGENTS.md を更新
```

mcp-toolkit を参照する (chrome-devtools を含む) リポジトリでは、transitive MCP を信頼するため `apm install --trust-transitive-mcp` を使う (詳細は mcp-servers ルール)。

生成物のうち `apm.lock.yaml` と `.github/instructions/{pr-review,language}.instructions.md` (クラウド Copilot 経路確保のための base 由来例外) は追跡対象としてコミットする。それ以外の生成物 (`.github/instructions/` の他ファイル・`CLAUDE.md` / `AGENTS.md` / `.claude/rules/` など) は `.gitignore` 対象のためコミットには含まれない。

MCP サーバーの追加・運用手順は mcp-servers ルールを、APM プラグイン (Skills / commands 等) の追加・運用手順は apm-plugins ルールを参照。

## GitHub Copilot Code Review への指示伝達

GitHub Copilot Code Review エージェントは `AGENTS.md` を読まず、`.github/copilot-instructions.md` または `.github/instructions/*.instructions.md` のみを読む仕様。

共通指示 (pr-review / language) を apm-config/base へ移したため、その生成物 `.github/instructions/pr-review.instructions.md` / `language.instructions.md` のみ追跡対象にしてクラウド経路へ届ける (第三者依存や重複生成物は追跡しない。`.gitignore` 参照)。あわせて `.github/copilot-instructions.md` をスタブとして配置し、生成済みの `.github/instructions/pr-review.instructions.md` を参照する形式で Copilot Code Review に指示の所在を伝える。

参考:

- <https://docs.github.com/copilot/how-tos/configure-custom-instructions/add-repository-instructions>
- <https://github.com/orgs/community/discussions/174058>
````

- [ ] **Step 2: 内容アサーションを実行**

```bash
cd /home/ore/codes/apm-config
F=base/.apm/instructions/apm-workflow.instructions.md
head -1 "$F" | grep -qx -- '---' && echo "frontmatter OK"
grep -q 'Source of Truth' "$F" && echo "keep SoT OK"
grep -q '0.23.1' "$F" && echo "apm 0.23.1 記載 OK"
! grep -q 'pnpm apm-install' "$F" && echo "一般化 apm install OK"
! grep -q 'dedupe-apm-lock' "$F" && echo "removed dedupe OK"
! grep -q 'spec-context' "$F" && echo "Spec Kit 連携なし OK"
! grep -q 'Spec Kit' "$F" && echo "Spec Kit 記述なし OK"
```

期待: 7 行すべて `... OK`。

- [ ] **Step 3: コミット**

```bash
git add base/.apm/instructions/apm-workflow.instructions.md
git commit -m "feat(base): 汎用化した apm-workflow instructions を追加"
```

---

## Task 3: base/dev-workflow.instructions.md

**Files:**
- Create: `base/.apm/instructions/dev-workflow.instructions.md`

**Interfaces:**
- Produces: base 配信の「開発の流れ」。`.github/release.yml` のラベル体系が各 consumer に存在することを前提にする。

- [ ] **Step 1: ファイルを作成**

以下を全文書き込む（bingo 原本のステップ 6「自動デプロイ」を「各リポジトリの CI/CD に従う」に一般化。タグ/リリース手順は `gh repo view` 動的解決済みでそのまま）。

````markdown
---
description: 開発フロー (開発者向け・リポジトリ管理者向け) のステップ定義
applyTo: "**"
---

# 開発の流れ

## 開発者

1. ブランチ作成
2. 開発
3. PR 作成
   - **必ず `.github/release.yml` の `changelog.categories` に対応するラベルを付与** (例: `bug-3 改善`, `enhance-2 新機能`, `enhance-1 破壊的変更`, `bug-1 重大バグ`, `bug-2 バグ`, `enhance-3 ドキュメント`, `dependencies`, `refactor`)
   - ラベル未付与の PR はリリースノートに出てこない (GitHub auto-generated changelog の挙動)
4. PR レビュー
5. PR マージ
6. マージ後は各リポジトリの CI/CD 設定に従ってデプロイされる (デプロイの有無・方式はリポジトリごと)

## リポジトリ管理者のみ

7. 必要と判断した場合、main ブランチでセマンティックバージョンによるタグ付け
   - 署名必須
   - annotation は 1 行目に件名 `メジャー・マイナー・パッチバージョンアップの理由`、2 行目を空行、3 行目以降にバージョンアップ理由を bullet (`- ` 始まり) で列挙
   - heredoc で annotation を `-F -` (stdin) に渡してコマンド実行:

     ```bash
     # 今回打つタグを変数に束ねる (シェル glob 展開回避 + 全コマンドで同一値参照)
     TAG=v2.0.2   # 例。実際の値に置き換える

     git tag -s -a "$TAG" -F - <<'EOF'
     メジャー・マイナー・パッチバージョンアップの理由

     - <バージョンアップ理由>
     EOF
     git push origin "$TAG"
     ```

8. 自動生成機能を用いてリリースノート作成 → ヘッダ表記を `変更点` に揃える

   ```bash
   # 8-1. release を作成 (notes は --generate-notes で auto-generate)
   gh release create "$TAG" --title "$TAG" --generate-notes --latest --verify-tag

   # 8-2. デフォルトヘッダ "What's Changed" を "変更点" に置換
   #      (GitHub の release.yml は header field の上書きを公式サポートしないため自前で sed)
   gh release view "$TAG" --json body --jq '.body' \
     | sed 's/^## What.s Changed$/## 変更点/' > /tmp/release-notes.md
   gh release edit "$TAG" --notes-file /tmp/release-notes.md
   ```

   ラベル未付与の PR がリリースに出なかったことに後で気付いた場合は、PR にラベルを付けてから以下で再生成可能:

   ```bash
   PREV_TAG=v2.0.1   # 例。直前リリースのタグに置き換える

   gh api "repos/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/releases/generate-notes" -X POST \
     -f "tag_name=$TAG" -f "previous_tag_name=$PREV_TAG" \
     --jq '.body' | sed 's/^## What.s Changed$/## 変更点/' > /tmp/release-notes.md
   gh release edit "$TAG" --notes-file /tmp/release-notes.md
   ```
````

- [ ] **Step 2: 内容アサーションを実行**

```bash
cd /home/ore/codes/apm-config
F=base/.apm/instructions/dev-workflow.instructions.md
head -1 "$F" | grep -qx -- '---' && echo "frontmatter OK"
grep -q 'release.yml' "$F" && echo "keep label rule OK"
grep -q 'git tag -s' "$F" && echo "keep signed tag OK"
grep -q '各リポジトリの CI/CD' "$F" && echo "一般化デプロイ OK"
```

期待: 4 行すべて `... OK`。

- [ ] **Step 3: コミット**

```bash
git add base/.apm/instructions/dev-workflow.instructions.md
git commit -m "feat(base): 汎用化した dev-workflow instructions を追加"
```

---

## Task 4: base/local-dev-workflow.instructions.md（統合版）+ base バージョン 1.1.0

**Files:**
- Create: `base/.apm/instructions/local-dev-workflow.instructions.md`
- Modify: `base/apm.yml`（`version: 1.0.0` → `1.1.0`）

**Interfaces:**
- Consumes: pr-review ルール（名前参照）、dev-workflow ルール（名前参照）。
- Produces: base 配信の統合版「ローカル開発ワークフロー」。base パッケージの完成（4 ファイル + バージョン 1.1.0）をこのタスクで確定する。

- [ ] **Step 1: ファイルを作成**

以下を全文書き込む（spec §4.4 のマッピング: superpowers 存在確認 + ブランチ/コミット規約 + superpowers 4 スキル駆動 + PR テンプレート/assignee + 自走レビュー応答ループ + GraphQL ページネーション。owner/repo は動的解決、リポジトリ固有の品質ゲートコマンドは含めない）。

````markdown
---
description: ローカル開発時のフロー (実装完了から PR 作成、PR レビュー応答ループ) を superpowers 系スキルで定義
applyTo: "**"
---

# ローカル開発ワークフロー (AI エージェント向け)

このリポジトリでローカル開発を進める AI エージェントは、以下のワークフローに従う。

## 前提: superpowers の存在確認

本ワークフローは [superpowers](https://github.com/obra/superpowers) 系スキル
(`verification-before-completion` / `requesting-code-review` / `receiving-code-review`
/ `finishing-a-development-branch`) が利用可能であることを前提とする。

- **Claude Code**: 上記 4 つのスキルが `Skill` ツールから呼び出せることを起動時に確認する
- **Codex CLI / GitHub Copilot 等**: 同等のスキル集が読み込まれているかを確認する

利用できない場合は、ユーザーに次のように案内し、本ワークフローの実行をその場で中断する。

> superpowers が見つかりません。
> 当リポジトリのローカル開発フローを実行するには superpowers のインストールが必要です。
> インストール後に再度同じ指示をお願いします。

## 1. ブランチとコミット

- **`main` に直接コミットしない**。作業ごとにブランチを切る (例: `chore/...`、`feat/...`)。
- コミットメッセージは Conventional Commits 形式 (`<type>(<scope>): <説明>`)、本文は日本語。
- コミット末尾のトレーラ (`Co-Authored-By:` / `Claude-Session:`) は環境が自動付与する場合がある。リポジトリの方針に従い、付与しない運用なら手で削除する。

## 2. 実装完了から PR 作成まで

実装が完了したと判断した時点で、以下を順に実行する。**前ステップが完了するまで次に進まない。**

1. `verification-before-completion` を起動し、検証 (lint / typecheck / 実機動作) を完遂する。品質ゲートの具体的なコマンドは各リポジトリの setup / lint 系 instructions に従う
2. 検証が通ったら `requesting-code-review` を起動し、レビュー依頼側ワークフローを開始する
3. レビュー結果が返ってきたら `receiving-code-review` を起動してフィードバックに対応する
4. 対応が完了したら `finishing-a-development-branch` を起動し、選択肢「2」を選んで PR を作成する

各ステップで失敗した場合は次に進まず、失敗の根本原因を解決してから再実行する。

PR 作成時は以下を守る。

- PR 本文は `.github/PULL_REQUEST_TEMPLATE.md` が存在すればその項目を埋める形で記載する。`finishing-a-development-branch` スキルが提案する独自構成 (`## Summary` / `## Test plan` 等) は採用しない
- チェックボックスはコミット前に検証済みの項目のみ `[x]`、Preview デプロイ待ちなど未確認のものは `[ ]` のまま残す
- PR タイトルは Conventional Commits 形式で、本文と同じく日本語で書く
- PR の assignee には、コミットを作成した人間のユーザー (= 現在の `gh` CLI 認証ユーザー) を設定する。AI エージェントは GitHub アカウントを持たないため、`gh pr create --assignee @me`、または作成後に `gh pr edit <pr> --add-assignee @me` を使う

## 3. PR レビュー応答ループ (PR 作成 / push 毎)

PR を新規作成、または既存ブランチに push した後、**ユーザーからの合図を待たずに** 自走でレビュースレッドの有無を確認し、指摘があれば対応する。**すべてのスレッドが resolve されるまでループを継続する。**

### 3.0 起動

`gh pr create` または `git push` の成功直後に本フローを開始する (ユーザー入力を待たない)。

- **即時 1 回**: push 完了から約 2 分 (120 秒) 待機 (Copilot Review の初回反応待ち) し、§3.1 を 1 回実行する。
- **追跡 (Claude Code)**: 指摘は遅延することがあるため、`ScheduleWakeup` でさらに 2 分後にもう 1 回フォローする。即時 + 追跡で **連続 2 回** 新規指摘がなければ追跡を終了する。

  ```text
  ScheduleWakeup({ delaySeconds: 120,
    prompt: "PR #<番号> の Copilot Review 応答ループを再開する。local-dev-workflow §3 に従い、未 resolve スレッドを検知して処理せよ。",
    reason: "Copilot Review 遅延応答の追跡チェック (push から 2 分後)" })
  ```

- **ユーザー復帰時フォールバック**: 次にユーザー入力を受け取ったとき、その入力が PR と無関係に見えても、まず自分の未マージ PR の未 resolve スレッドを 1 回確認する。あれば「PR #<番号> に未対応のレビュースレッドがあります。先に応答しますか？」と確認し、了承されたら §3.1〜3.3 を先に実行する。

### 3.1 検知

`gh api graphql` で未 resolve なレビュースレッドを列挙する (`gh pr view --json reviews,comments` は thread の `isResolved` を返さないので使わない)。owner / repo は `gh repo view --json nameWithOwner --jq .nameWithOwner` で動的に解決する。

レビュースレッド数が 100 を、または各スレッドのコメント数が 50 を超える可能性がある場合は、`pageInfo { hasNextPage endCursor }` を取得し、`hasNextPage: true` の間は `after: $cursor` を渡してカーソル送りで全件取得する (下記は初回ページの取得例)。

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!, $threadsCursor: String, $commentsCursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100, after: $threadsCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id            # GraphQL Node ID — resolveReviewThread mutation の threadId に渡す
          isResolved
          comments(first: 50, after: $commentsCursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id          # GraphQL Node ID
              databaseId  # 数値 ID — REST API /pulls/comments/{comment_id}/replies の comment_id に渡す
              author { login }
              body
              path
              line
            }
          }
        }
      }
    }
  }
}' -F owner=<owner> -F repo=<repo> -F pr=<number>
```

対象は `isResolved: false` かつ先頭コメント (`comments.nodes[0]`) の author が bot (例: `copilot-pull-request-reviewer`) のスレッドのみとする。

### 3.2 妥当性判断

各指摘について次のいずれかに分類する。

- **妥当**: 反映すべき具体的かつ正当な指摘
- **不当**: 文脈を踏まえると採用すべきでない、誤読、二重指摘 等

### 3.3 対応

#### 妥当な指摘

1. 指摘に従ってコードを修正する
2. 修正をコミットする
3. 該当インラインコメントに返信する。本文に対応コミットの SHA を **前後に半角空白を入れて** 記載し、GitHub UI でコミットへのリンクとして描画させる。

   ```bash
   gh api repos/<owner>/<repo>/pulls/<pr>/comments/<comment_database_id>/replies \
     -f body='対応しました abc1234 '
   ```

   - `<comment_database_id>` は §3.1 の `databaseId` フィールド (**数値 ID**) を指す。GraphQL Node ID (`PRRC_...`) は REST API では受け付けられない点に注意。
   - 本文は日本語で記述 (pr-review ルール参照)
   - SHA の前後を必ず半角空白で挟む
4. スレッドを resolve する。

   ```bash
   gh api graphql -f query='
   mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { isResolved } } }
   ' -F id=<thread_node_id>
   ```

#### 不当と判断した場合

1. コードは変更しない
2. インラインコメントで「不当と判断した理由」を日本語で具体的に記載する
3. スレッドを resolve する (上記 mutation 参照)

### 3.4 繰り返し

- 全スレッドを resolve するまで 3.1〜3.3 をループする
- 次の `git push` が発生したら、再度 3.1 から実行する

## 関連ルール

- レビュー応答の文章ルールは共通パッケージ `ROhta/apm-config/base` の pr-review ルールから配信。生成物は `.github/instructions/pr-review.instructions.md` / `.claude/rules/pr-review.md`
- 開発フロー (ブランチ〜マージ〜リリース) の高レベル順序は dev-workflow ルールを参照
````

- [ ] **Step 2: base/apm.yml のバージョンを 1.1.0 に上げる**

`base/apm.yml` の `version: 1.0.0` を `version: 1.1.0` に変更する（他の行は変更しない。特に `dependencies.apm` の `obra/superpowers` pin は触らない）。

- [ ] **Step 3: 内容アサーションを実行**

```bash
cd /home/ore/codes/apm-config
F=base/.apm/instructions/local-dev-workflow.instructions.md
head -1 "$F" | grep -qx -- '---' && echo "frontmatter OK"
grep -q 'superpowers' "$F" && echo "keep superpowers OK"
grep -q 'ScheduleWakeup' "$F" && echo "自走ループ OK"
grep -q 'nameWithOwner' "$F" && echo "owner/repo 動的解決 OK"
grep -q 'assignee' "$F" && echo "assignee 規律 OK"
! grep -q 'repo=wine_record' "$F" && echo "ハードコード repo なし OK"
! grep -q 'pnpm run typecheck && pnpm run lint' "$F" && echo "固有品質ゲートなし OK"
grep -qx 'version: 1.1.0' base/apm.yml && echo "base 1.1.0 OK"
grep -q 'obra/superpowers' base/apm.yml && echo "superpowers dep 温存 OK"
```

期待: 9 行すべて `... OK`。

- [ ] **Step 4: コミット**

```bash
git add base/.apm/instructions/local-dev-workflow.instructions.md base/apm.yml
git commit -m "feat(base): 統合版 local-dev-workflow を追加し base を v1.1.0 に更新"
```

---

## Task 5: mcp-toolkit/mcp-servers.instructions.md + mcp-toolkit バージョン 1.1.0

**Files:**
- Create: `mcp-toolkit/.apm/instructions/mcp-servers.instructions.md`
- Modify: `mcp-toolkit/apm.yml`（`version: 1.0.0` → `1.1.0`）

**Interfaces:**
- Produces: mcp-toolkit 配信の「MCP サーバー管理ルール」。配信サーバー一覧を実態（context7 / serena / chrome-devtools / deepwiki）に一致させる。

- [ ] **Step 1: ディレクトリとファイルを作成**

`mcp-toolkit/.apm/instructions/` を作成し、以下を全文書き込む（bingo 原本の semgrep を除去し deepwiki を追加、chrome-devtools の transitive / `--trust-transitive-mcp` を明記、末尾「APM の他のプリミティブとの違い」節を除去）。

````markdown
---
description: APM (Agent Project Manager) を介した MCP サーバーの運用ルール
applyTo: "apm.yml"
---

# MCP サーバー管理ルール

## Source of Truth

共通の MCP サーバーセット (context7 / serena / chrome-devtools / deepwiki) は、共有パッケージ
[`ROhta/apm-config/mcp-toolkit`](https://github.com/ROhta/apm-config) が Source of Truth。
本リポジトリは `apm.yml` の `dependencies.apm` からこれを参照する。`apm install` を実行すると、
mcp-toolkit に宣言された MCP サーバーが Claude Code / Codex CLI / GitHub Copilot (in VS Code) の
各 IDE 設定に展開される。

リポジトリ固有の MCP サーバーが必要な場合のみ、`apm.yml` の `dependencies.mcp` に個別に追記する。

## 配信される MCP サーバー

| 名前              | 用途                                                     | 必要な前提                             | trust |
| ----------------- | -------------------------------------------------------- | -------------------------------------- | ----- |
| `context7`        | ライブラリ公式ドキュメントの最新版を取得                 | `node` (`npx`)                         | 直接依存 (auto-trust) |
| `serena`          | LSP ベースのシンボル指向コード探索・編集                 | `uv` (`uvx`)                           | 直接依存 (auto-trust) |
| `deepwiki`        | GitHub リポジトリの AI ドキュメント (リモート streamable-http) | なし (ホスト型)                    | 直接依存 (auto-trust) |
| `chrome-devtools` | Chrome DevTools 経由のブラウザ自動化・パフォーマンス計測 | `node` (Chrome は実行時にダウンロード) | **transitive (要 `--trust-transitive-mcp`)** |

## trust の粒度

`dependencies.mcp` で直接定義した context7 / serena / deepwiki は consumer から見て
直接依存 (depth 1) なので self-defined でも auto-trust され、フラグなしで展開される。
`chrome-devtools` だけはプラグイン参照 (`ChromeDevTools/chrome-devtools-mcp`) 経由の
transitive MCP (depth 2) のため、consumer 側で `apm install --trust-transitive-mcp` が必要。
フラグは全 MCP に一括でかかり、`apm.yml` / `apm.lock.yaml` には永続化されないため、
ラッパースクリプト (Makefile 等) で標準化することを推奨する。

## バージョン固定方針

再現性確保のため、各サーバーの具体バージョン / コミット SHA によるピンは
**mcp-toolkit 側で一元管理** する (`@latest` や git ブランチ HEAD は使わない)。
pin を更新するときは本リポジトリではなく apm-config を編集し、`apm update` で取り込む。
これにより、従来リポジトリごとに pin がドリフトしていた問題を解消する。

## 開発者の前提条件

以下のランタイムが PATH にあれば全 MCP サーバーが動作する。

- [uv](https://docs.astral.sh/uv/) (`uvx` を経由して PyPI / git ソースの Python パッケージを実行)
- [Node.js](https://nodejs.org/) (`npx` 経由)

deepwiki は認証不要のホスト型リモート MCP のため追加ランタイム不要。

## サーバーの追加・削除・pin 更新

共通セットの変更は apm-config/mcp-toolkit で行い、本リポジトリで `apm update` を実行する。
リポジトリ固有サーバーを足す場合は `apm.yml` の `dependencies.mcp` を編集して `apm install` する。

### APM レジストリは使わないこと

APM 公式レジストリ (`apm mcp search` / `apm mcp install <registry-name>`) は解決結果が
不正なケースがある (例: `oraios/serena` が `uvx ide-assistant` という別物に展開される)。
このため **すべて self-defined (`-- <command> [args...]` 指定)** で登録する (mcp-toolkit 側も同方針)。

## 生成物の場所

`apm install` が以下のファイルを生成する。すべて `.gitignore` 対象。

| パス                 | 対応 IDE                    |
| -------------------- | --------------------------- |
| `.mcp.json`          | Claude Code (project scope) |
| `.vscode/mcp.json`   | GitHub Copilot in VS Code   |
| `.codex/config.toml` | Codex CLI                   |
````

- [ ] **Step 2: mcp-toolkit/apm.yml のバージョンを 1.1.0 に上げる**

`mcp-toolkit/apm.yml` の `version: 1.0.0` を `version: 1.1.0` に変更する（`dependencies` の MCP 定義・chrome-devtools 参照は変更しない）。

- [ ] **Step 3: 内容アサーションを実行**

```bash
cd /home/ore/codes/apm-config
F=mcp-toolkit/.apm/instructions/mcp-servers.instructions.md
head -1 "$F" | grep -qx -- '---' && echo "frontmatter OK"
grep -q 'deepwiki' "$F" && echo "deepwiki 追加 OK"
grep -q 'trust-transitive-mcp' "$F" && echo "trust フラグ明記 OK"
! grep -q 'semgrep' "$F" && echo "semgrep 除去 OK"
! grep -q 'APM の他のプリミティブとの違い' "$F" && echo "末尾固有節 除去 OK"
grep -qx 'version: 1.1.0' mcp-toolkit/apm.yml && echo "mcp-toolkit 1.1.0 OK"
grep -q 'chrome-devtools' mcp-toolkit/apm.yml && echo "chrome-devtools 温存 OK"
```

期待: 7 行すべて `... OK`。

- [ ] **Step 4: コミット**

```bash
git add mcp-toolkit/.apm/instructions/mcp-servers.instructions.md mcp-toolkit/apm.yml
git commit -m "feat(mcp-toolkit): mcp-servers instructions を追加し実配信内容へ修正、v1.1.0 に更新"
```

---

## Task 6: speckit パッケージ（新規）

**Files:**
- Create: `speckit/apm.yml`
- Create: `speckit/.apm/instructions/speckit-workflow.instructions.md`

**Interfaces:**
- Produces: 新規 speckit パッケージ（v1.0.0）。Spec Kit 採用リポジトリ（現状 wine_record のみ）が依存する。`spec-context.instructions.md` は動的・リポジトリ固有のため配信物に含めない旨を明記する。

- [ ] **Step 1: speckit/apm.yml を作成**

以下を全文書き込む（base/apm.yml と同じ構造。依存は空）。

```yaml
name: apm-config-speckit
version: 1.0.0
description: Spec Kit 採用リポジトリ向けの機能開発フロー instructions（Spec Kit × APM 連携）
author: ROhta
license: GPL-3.0-or-later
type: instructions
targets:
  - claude
  - codex
  - copilot
includes: auto
dependencies:
  apm: []
  mcp: []
```

- [ ] **Step 2: speckit/.apm/instructions/speckit-workflow.instructions.md を作成**

以下を全文書き込む。

````markdown
---
description: Spec Kit による機能開発フローと Spec Kit × APM の連携運用
applyTo: "**"
---

# Spec Kit ワークフロー

## 機能開発は Spec Kit で進める

新機能や大きめの変更は **Spec Kit** のフローで進める (superpowers 系の実装フローとは別)。

`speckit-constitution` (必要時) → `speckit-specify` → `speckit-plan` → `speckit-tasks` →
(任意 `speckit-taskstoissues`) → `speckit-implement`。

- 仕様・計画・タスクは `specs/<NNN-feature>/` に置かれる (パスは Spec Kit が管理。手で別所へ動かさない)。
- プロジェクト原則は `.specify/memory/constitution.md`。
- ドキュメント・設定・依存更新などの小さな雑務は、Spec Kit を通さずブランチ + PR で直接進めてよい。

## Spec Kit × APM の連携

Spec Kit と APM はどちらも CLAUDE.md / AGENTS.md を生成しようとするため、素朴に併用すると
生成物を奪い合う。これを避けるため、Spec Kit の動的なプランポインタは APM の instructions
経由で畳み込む。

- `agent-context-config.yml` の `context_file` を `.apm/instructions/spec-context.instructions.md`
  に向ける。Spec Kit の `speckit.agent-context.update` (after_specify / after_plan hook) が
  このファイルを自動更新する。
- `apm compile` が `spec-context.instructions.md` を含む `.apm/instructions/` を CLAUDE.md /
  AGENTS.md / `.github/instructions` に畳み込む。**speckit の specify / plan を実行したら
  `apm compile` を 1 回回して反映する。**
- `apm compile` は既定で Spec Kit の constitution ブロックを取り込む (`--with-constitution`)。

## spec-context.instructions.md の扱い（重要）

`spec-context.instructions.md` は Spec Kit hook が自動更新する **動的・リポジトリ固有の
プランポインタ** (現在の `plan.md` を指す) であり、内容がリポジトリ・機能ごとに異なる。
そのため本 speckit パッケージの **配信物には含めない**。各リポジトリがローカルに保持し
(Spec Kit hook が生成・更新する)、`.apm/instructions/` の追跡対象として管理する。
マーカー間は hook が自動更新するので手で編集しない。
````

- [ ] **Step 3: 内容アサーションを実行**

```bash
cd /home/ore/codes/apm-config
M=speckit/apm.yml
F=speckit/.apm/instructions/speckit-workflow.instructions.md
grep -qx 'name: apm-config-speckit' "$M" && echo "package name OK"
grep -qx 'version: 1.0.0' "$M" && echo "speckit 1.0.0 OK"
grep -qx 'includes: auto' "$M" && echo "includes auto OK"
head -1 "$F" | grep -qx -- '---' && echo "frontmatter OK"
grep -q 'speckit-specify' "$F" && echo "Spec Kit フロー OK"
grep -q '配信物には含めない' "$F" && echo "spec-context 非配信明記 OK"
```

期待: 6 行すべて `... OK`。

- [ ] **Step 4: コミット**

```bash
git add speckit/apm.yml speckit/.apm/instructions/speckit-workflow.instructions.md
git commit -m "feat(speckit): Spec Kit 採用リポジトリ向けパッケージを新規追加"
```

---

## Task 7: 横断検証と README 追記・PR 作成

**Files:**
- Modify: `README.md`（構成表に speckit 行を追加）

**Interfaces:**
- Consumes: Task 1〜6 で作成した全ファイル。
- Produces: フェーズ 1 完了。マージ後、consumer 移行計画（フェーズ 2〜5）がこの PR のマージ SHA を参照できる。

- [ ] **Step 1: 全パッケージの構造を一括検証**

```bash
cd /home/ore/codes/apm-config
# base: 6 instructions（既存 2 + 追加 4）
ls base/.apm/instructions/*.instructions.md | wc -l | grep -qx 6 && echo "base 6 files OK"
# mcp-toolkit: 1 instructions
ls mcp-toolkit/.apm/instructions/*.instructions.md | wc -l | grep -qx 1 && echo "mcp-toolkit 1 file OK"
# speckit: 1 instructions + manifest
ls speckit/.apm/instructions/*.instructions.md | wc -l | grep -qx 1 && echo "speckit 1 file OK"
# 全 instructions に frontmatter がある
for f in $(find base mcp-toolkit speckit -name '*.instructions.md'); do head -1 "$f" | grep -qx -- '---' || echo "NG frontmatter: $f"; done; echo "frontmatter 走査 完了"
# バージョン
grep -qx 'version: 1.1.0' base/apm.yml && grep -qx 'version: 1.1.0' mcp-toolkit/apm.yml && grep -qx 'version: 1.0.0' speckit/apm.yml && echo "versions OK"
```

期待: `base 6 files OK` / `mcp-toolkit 1 file OK` / `speckit 1 file OK` / `frontmatter 走査 完了`（NG 行が出ないこと）/ `versions OK`。

- [ ] **Step 2: README.md の構成表に speckit を追記**

`README.md` の「構成（レイヤー別サブパッケージ）」の表に、`mcp-toolkit/` 行の下へ次の行を追加する。

```markdown
| `speckit/` | Spec Kit 機能開発フローと Spec Kit × APM 連携の instructions | Spec Kit を使うリポジトリ |
```

- [ ] **Step 3: README のコミットとブランチ push**

push しておくと、次の Step 4 で subpath パッケージを `#<sha>` 参照で解決できる。

```bash
git add README.md
git commit -m "docs(readme): 構成表に speckit サブパッケージを追記"
git push -u origin feat/common-instructions-packages
```

- [ ] **Step 4: speckit パッケージの実配信スモークテスト（重要）**

**なぜこのタスクにこのテストが要るか**: フェーズ 2（bingo）は base と mcp-toolkit を pull するため、base の新規 instructions と mcp-toolkit の新規 instructions 配信はそこで実 install 検証される。しかし **speckit を pull するのは wine_record（フェーズ 3）だけ**で、speckit は今回初めて作る subpath パッケージ。「新規 subpath パッケージが解決・配信されるか」という最もリスクの高い前提が、検証しないと最も複雑なリポジトリ（Spec Kit + 憲章）で初めて露見する。それをフェーズ 1 のうちに潰す。

base は既存で実績があり、mcp-toolkit はフェーズ 2 で検証されるため、ここでは **base + speckit**（どちらも instruction のみで MCP ランタイム依存なし＝高速・堅牢）を使い分け捨てディレクトリへ実 install して配信を確認する。

```bash
cd /home/ore/codes/apm-config
SHA=$(git rev-parse HEAD)
if command -v apm >/dev/null 2>&1; then
  TMP=$(mktemp -d)
  cat > "$TMP/apm.yml" <<YML
name: smoke-test
version: 0.0.0
type: instructions
targets: [claude, codex, copilot]
includes: auto
dependencies:
  apm:
    - ROhta/apm-config/base#${SHA}
    - ROhta/apm-config/speckit#${SHA}
  mcp: []
YML
  ( cd "$TMP" && apm install )
  # 判定は本文の文言ではなく「配信されたファイル名」で行う。ファイル名はパッケージ契約
  # （ソースファイル名由来）で安定するため、instructions 本文を微修正しても偽陰性にならない。
  # 配信先: .claude/rules/<name>.md（.instructions 除去）/ .github/instructions/<name>.instructions.md
  ( cd "$TMP" && find .claude .github -name 'speckit-workflow*' 2>/dev/null | grep -q . ) \
    && echo "speckit 実配信 OK（speckit-workflow が展開された）" || echo "NG: speckit の配信物が見つからない"
  ( cd "$TMP" && find .claude .github -name 'local-dev-workflow*' 2>/dev/null | grep -q . ) \
    && echo "base 実配信 OK（local-dev-workflow が展開された）" || echo "NG: base 配信物が見つからない"
  rm -rf "$TMP"
else
  echo "apm 未導入のためフェーズ 1 スモークをスキップ。この場合 speckit の初回実配信検証はフェーズ 3 (wine_record) が初出になる点に注意（base/mcp-toolkit はフェーズ 2 bingo で検証される）。"
fi
```

期待: apm があれば `speckit 実配信 OK（…）` と `base 実配信 OK（…）` の 2 行。`NG:` が出たら subpath 解決・frontmatter・`includes: auto`、または配信先パス命名を疑う。apm 未導入ならスキップ理由が表示される。

- [ ] **Step 5: PR を作成**

```bash
cd /home/ore/codes/apm-config
gh pr create --assignee @me --label enhancement \
  --title "feat: 共通 instructions を base/mcp-toolkit/speckit パッケージに整備" \
  --body "$(cat <<'BODY'
## 概要

設計 (docs/superpowers/specs/2026-07-04-instructions-migration-design.md) のフェーズ 1。
bingo の instructions を共通化し、base に 4 ファイル追加・mcp-toolkit に 1 ファイル追加・
speckit を新規追加する。consumer 移行 (フェーズ 2〜5) は本 PR マージ後に別 PR で進める。

## 変更点

- base v1.1.0: apm-plugins / apm-workflow / dev-workflow / local-dev-workflow を追加
- mcp-toolkit v1.1.0: mcp-servers を追加（配信サーバーを実態 context7/serena/chrome-devtools/deepwiki に修正）
- speckit v1.0.0: speckit-workflow を新規追加（spec-context は動的のため非配信）

## 見てほしいところ

- 統合版 local-dev-workflow の内容（superpowers 4 スキル駆動 + 自走レビュー応答ループ）
- mcp-servers の配信サーバー一覧が mcp-toolkit の実 apm.yml と一致しているか
- speckit で spec-context を配信物から外した判断

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
```

期待: PR URL が出力される。

---

## Self-Review

（計画作成者による確認結果。実装者向けの参考。）

**Spec coverage:**
- §3 パッケージ構成 → Task 1〜6（base 4 / mcp-toolkit 1 / speckit 1）+ Task 4,5,6 のバージョン。✅
- §4.1〜4.5 各ファイルの内容方針 → 各 Task の Step 1 全文 + Step 2 アサーション。✅
- §4.4 統合版マッピング → Task 4。✅
- §5 consumer 変更 / release.yml 統一 / apm 0.23.1 → **フェーズ 2〜5（別計画）**。本計画のスコープ外である旨を Architecture に明記。✅
- §8 リスク（0.23.1 挙動）→ base/mcp-toolkit の実 install 検証はフェーズ 2（bingo）。speckit は初回消費がフェーズ 3 になり検証が遅れるため、Task 7 Step 4 でフェーズ 1 スモークテスト（base + speckit の実配信）を先行実施。✅

**Placeholder scan:** 各ファイルは全文を記載。`<owner>` `<repo>` `<sha>` `<番号>` はテンプレート内のプレースホルダ（instructions の意図的な可変部）であり計画の欠落ではない。✅

**Type consistency:** パッケージ名 `apm-config-speckit`、バージョン（base/mcp-toolkit=1.1.0, speckit=1.0.0）、ファイル名（`*.instructions.md`）、相互参照のプレーン名（apm-plugins / apm-workflow / dev-workflow / mcp-servers / pr-review）を全 Task で統一。✅
