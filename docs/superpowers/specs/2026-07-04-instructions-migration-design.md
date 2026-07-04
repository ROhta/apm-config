# 設計: bingo instructions の apm-config 移行と全リポジトリ配信

- 日付: 2026-07-04
- ステータス: レビュー待ち
- 対象リポジトリ: apm-config / bingo / bingo_next / wine_record / bingo_mcp / company_analysis

## 1. 背景と目的

bingo の `.apm/instructions/` にある 5 ファイル（apm-plugins / apm-workflow / dev-workflow /
local-dev-workflow / mcp-servers）は内容の大半が全リポジトリ共通の運用ルールだが、
リポジトリごとにコピーが分岐している。

- bingo_next / wine_record は同名ファイルの独自進化版を保持（自走レビュー応答ループ等の改良が
  bingo に還流されていない）
- wine_record は機能開発を Spec Kit で進める方針で、superpowers 前提の記述と衝突
- pin 更新やルール修正のたびに N リポジトリへ同じ変更を撒く必要がある

これらを apm-config に一元化し、consumer 各リポジトリは `apm.yml` の依存指定だけで
instructions を受け取る（同内容のローカルコピーは git 管理しない）状態にする。

## 2. 決定事項（ユーザー確認済み）

| 論点 | 決定 |
| --- | --- |
| 分岐版の扱い | 共通版に統一を強制。bingo_next / wine_record の分岐版は削除し共通版に置き換える |
| Spec Kit フロー | base / mcp-toolkit とは別の新パッケージ `speckit/` として配信。wine_record の該当指示は新パッケージの配信物に置き換える |
| 統一版 local-dev-workflow | 各リポジトリ版の良いとこ取り統合（superpowers 4 スキル駆動 + 自走レビュー応答ループ） |
| dev-workflow の前提 | 全リポジトリに `.github/release.yml` とラベル体系を整備して統一 |
| mcp-servers の配置 | mcp-toolkit パッケージに置く（MCP 採用リポジトリだけに届く） |

## 3. apm-config のパッケージ構成

```text
apm-config/
├── base/                        # v1.0.0 → v1.1.0
│   └── .apm/instructions/
│       ├── language.instructions.md            (既存)
│       ├── pr-review.instructions.md           (既存)
│       ├── apm-plugins.instructions.md         ★新規（汎用化）
│       ├── apm-workflow.instructions.md        ★新規（汎用化）
│       ├── dev-workflow.instructions.md        ★新規（汎用化）
│       └── local-dev-workflow.instructions.md  ★新規（統合版）
├── mcp-toolkit/                 # v1.0.0 → v1.1.0
│   └── .apm/instructions/
│       └── mcp-servers.instructions.md         ★新規（汎用化）
└── speckit/                     # ★新規パッケージ v1.0.0
    └── .apm/instructions/
        └── speckit-workflow.instructions.md    ★新規（wine_record 由来）
```

設計原則: **パッケージ = 採用の単位**。APM の `includes: auto` は選択的除外ができないため、
「全 consumer に届いてよいか」がファイルの置き場所を決める唯一の基準になる。

- base — 全リポジトリに届いてよい指示
- mcp-toolkit — 共通 MCP セット採用リポジトリ（bingo / bingo_mcp / company_analysis）のみ
- speckit — Spec Kit 採用リポジトリ（現状 wine_record のみ）

`mcp-toolkit` は現在 apm.yml のみのパッケージだが、`.apm/instructions/` を追加すれば
base と同じ仕組みで instructions が配信される。

`speckit/` の内容: Spec Kit の正規フロー（`speckit-constitution` →
`speckit-specify` → `speckit-plan` → `speckit-tasks` →（任意 `speckit-taskstoissues`）→
`speckit-implement`）、`specs/<NNN-feature>/` 配置規約、`.specify/memory/constitution.md` の位置づけ、
「小さな雑務は Spec Kit を通さず直接 PR でよい」の判断基準、および Spec Kit × APM の連携運用
（`agent-context-config.yml` の `context_file` を `.apm/instructions/spec-context.instructions.md` に
向け、specify / plan 実行後に `apm compile` を 1 回回す運用。wine_record の
apm-workflow.instructions.md から移設）。

なお `spec-context.instructions.md` は Spec Kit の hook（`speckit.agent-context.update`）が
自動更新する動的・リポジトリ固有のプランポインタ（現在の `plan.md` を指す）であり、内容が
リポジトリ・機能ごとに異なるため speckit パッケージの**配信物には含めない**（ツリーに
speckit-workflow しか載っていないのはこのため）。各リポジトリにローカル保持し
（§5 で wine_record が「spec-context は残す」としているのはこれ）、Spec Kit hook が生成・更新する。
冒頭の「同内容のローカルコピーは git 管理しない」方針の対象外＝そもそも共通の同一内容ではない。

## 4. 各ファイルの内容方針（汎用化の境界線）

### 4.1 base/apm-plugins.instructions.md

- 残す: SoT 宣言（`apm.yml` の `dependencies.apm`）、プラグイン bundle / 単一プリミティブの
  2 形態、vendor-neutral 方針、SHA ピン必須、marketplace / 直接指定の追加手順、削除手順、
  生成物の場所テーブル
- 抜く: `pnpm apm-install` ラッパー節（bingo / bingo_mcp 固有。§6 参照）、「配信される
  プラグイン」のリポジトリ固有依存一覧表（「各リポジトリの `apm.yml` を参照」に置換）

### 4.2 base/apm-workflow.instructions.md

- 残す: 「`.apm/instructions/` = リポジトリ固有指示の SoT、共通指示は apm-config が SoT」の
  二層宣言、mise による APM CLI バージョン管理（全 5 リポジトリで mise 採用確認済み）、
  ファイル管理方針テーブル（汎用形）、ローカル作業手順、Copilot Code Review への指示伝達
  （`.github/instructions/{pr-review,language}.instructions.md` のみ追跡例外とする方針を含む）
- 変更: `pnpm apm-install` 参照を `apm install` に一般化
- 移設: wine_record 版にある Spec Kit context 連携の記述 → speckit パッケージへ

### 4.3 base/dev-workflow.instructions.md

- 残す: PR ラベル付与ルール（release.yml 統一が前提。§5 参照）、署名タグ手順、
  リリースノート作成・再生成手順（コマンドは `gh repo view` による動的解決済みで汎用）
- 変更: 「自動デプロイ」ステップ → 「マージ後は各リポジトリの CI/CD に従う」に一般化

### 4.4 base/local-dev-workflow.instructions.md（統合版）

各リポジトリ版は「PR フロー（共通化可能）」と「機能開発手法（リポジトリごとに異なる）」の
直交する 2 関心の混在だった。統合版は前者のみをスコープとする。

| 節 | 採用元 |
| --- | --- |
| 前提: superpowers 存在確認 | bingo 版 |
| ブランチとコミット規約 | wine_record 版 §1 |
| 実装完了 → PR 作成（superpowers 4 スキル駆動: verification-before-completion → requesting-code-review → receiving-code-review → finishing-a-development-branch） | bingo 版 §1 |
| PR テンプレート項目・チェックボックス規律・Conventional Commits タイトル・assignee `@me` | bingo_next / wine_record の改良点 |
| PR レビュー応答ループ（自走起動: 2 分待機 + ScheduleWakeup 追跡 + ユーザー復帰時フォールバック） | wine_record 版 §3 |
| GraphQL ページネーション（`pageInfo` / `hasNextPage`） | bingo 版 §2.1 |

- owner / repo のハードコード（wine_record 版に残存）は動的解決
  （`gh repo view --json nameWithOwner`）に書き換える
- 品質ゲートの具体コマンド列はリポジトリ固有のため含めない（各リポジトリの setup / lint
  instructions が定義し、verification-before-completion スキルがそれを実行する）
- Spec Kit との整合: base 版は「実装完了後の PR フロー」、speckit は「機能開発の進め方
  （仕様→実装）」がスコープなので矛盾しない。wine_record は両方受け取って整合する

### 4.5 mcp-toolkit/mcp-servers.instructions.md

- 残す: mcp-toolkit が共通 MCP セットの SoT であること、ピンの一元管理方針、
  APM レジストリ不使用方針（self-defined 固定）、開発者の前提ランタイム（uv / Node.js）、
  生成物の場所（`.mcp.json` / `.vscode/mcp.json` / `.codex/config.toml`）
- 修正: サーバー一覧表を mcp-toolkit の実配信内容（context7 / serena / chrome-devtools /
  deepwiki）に合わせる。現行 bingo 版は semgrep を含み deepwiki を欠くが、これは実態と
  ズレている
- 追加: chrome-devtools はプラグイン経由の transitive MCP のため consumer では
  `apm install --trust-transitive-mcp` が必要である旨（apm-config README の記述を instructions
  にも反映）
- 抜く: 末尾「APM の他のプリミティブとの違い」のリポジトリ固有依存列挙

## 5. consumer 側の変更（5 リポジトリ）

| リポジトリ | apm.yml | 削除するローカル instructions | release.yml |
| --- | --- | --- | --- |
| bingo | base / mcp-toolkit の pin を新 SHA に更新 | 対象 5 ファイル（残: feature-spec, github-ops, lint, setup, styling, typescript） | あり（変更なし） |
| bingo_next | **base を新規追加**（mcp-toolkit は追加しない = MCP 非使用の判断維持） | apm-workflow, local-dev-workflow, pr-review（base 配信と重複） | あり（変更なし） |
| wine_record | base の `#main` を SHA ピンに修正 + **speckit を追加** | apm-workflow, local-dev-workflow（spec-context, setup は残す） | **新規整備** |
| bingo_mcp | pin 更新 | apm.instructions.md（base の apm-workflow / apm-plugins 相当）、workflow.instructions.md（dev-workflow / local-dev-workflow 相当）。残: architecture, development, widget | **新規整備** |
| company_analysis | pin 更新 | agents-workflow.instructions.md を縮小改訂: base と重複する共通部分（SoT 宣言・mise・ファイル管理方針）を削り、`.apm/agents/*.agent.md` サブエージェント運用などリポジトリ固有部分のみ残す | **新規整備** |

- release.yml 統一: bingo / bingo_next のラベル体系（`enhance-1 破壊的変更` / `enhance-2 新機能` /
  `enhance-3 ドキュメント` / `bug-1 重大バグ` / `bug-2 バグ` / `bug-3 改善` / `dependencies` /
  `refactor`）を標準として、wine_record / bingo_mcp / company_analysis に `.github/release.yml` と
  GitHub ラベル（`gh label create`）を作成する
- 配信された instructions の生成物（`.claude/rules/` / `.github/instructions/`）について、
  **追跡例外は増やさない**（pr-review / language のみ維持）。今回の 5 ファイルはコードレビュー
  指示ではないため、クラウド Copilot Code Review への経路は不要
- bingo_next が base に依存すると superpowers も transitive に届く（base の `dependencies.apm` に
  `obra/superpowers` があるため）。bingo_next 側で重複依存にならないよう `apm.yml` を確認する

## 6. bingo の dedupe ラッパーの扱い

`pnpm apm-install`（`scripts/dedupe-apm-lock.mjs`）は APM CLI v0.14.1 の `deployed_files:` 重複
不具合への対応だが、bingo は現在 0.18.0。**bingo_mcp（0.19.0）も同名ラッパーを使用している**ため
両リポジトリで、実装時に素の `apm install` で重複が再現するか検証する。

- 直っていれば → ラッパーと dedupe スクリプトを撤去（package.json の `apm-install` スクリプト含む）
- 残っていれば → 当該リポジトリ固有の instructions ファイル（例: `apm-local.instructions.md`）に
  記述を残す

いずれの場合も共通版 instructions にはラッパーの記述を含めない。

## 7. ロールアウト順序と検証

1. **apm-config** に PR（base v1.1.0 / mcp-toolkit v1.1.0 / speckit v1.0.0）→ マージ SHA を取得
2. **bingo**（参照実装）: pin 更新 + 5 ファイル削除 + dedupe ラッパー検証 →
   `apm install && apm compile`
3. **wine_record**: speckit 置き換え + `#main` ピン修正 + release.yml 整備
4. **bingo_next**: base 新規導入 + 分岐版削除
5. **bingo_mcp / company_analysis**: pin 更新 + release.yml 整備 + 重複精査

各リポジトリでの検証項目:

- 配信ファイルが `.claude/rules/` / `.github/instructions/` に展開されること
- `apm compile` 後の `AGENTS.md` / `CLAUDE.md` に共通指示が組み込まれること
- 削除したローカル instructions 由来の旧生成物が残っていないこと（オーファン掃除）
- mcp-toolkit 依存リポジトリでは `--trust-transitive-mcp` 付きで MCP 4 サーバーが展開されること
- wine_record では Spec Kit の constitution 込み `apm compile` が引き続き成立すること

## 8. リスクと対処

| リスク | 対処 |
| --- | --- |
| apm バージョン差（0.18 / 0.19 / 0.23）で配信挙動が異なる | 各リポジトリの実バージョンで検証。差異が出たら当該リポジトリの mise.toml 更新を個別判断 |
| 統一版 local-dev-workflow が bingo_next の詳細な自走チェック記述（231 行版）より簡素になり運用が変わる | wine_record 版（bingo_next 版を簡潔化した後継）をベースにするため実質的な機能後退はない。懸念があれば bingo_next のレビューで差分を確認 |
| release.yml 未整備リポジトリでラベル運用が形骸化する | ラベル作成を release.yml 整備と同一 PR で行い、dev-workflow 指示の前提を PR マージ時点で満たす |

## 9. スコープ外

- apm CLI バージョン（mise.toml）の 5 リポジトリ統一（必要なら別途提案）
- bingo に残る 6 ファイル（feature-spec, github-ops, lint, setup, styling, typescript）の共通化
- mcp-toolkit の MCP セット構成変更
