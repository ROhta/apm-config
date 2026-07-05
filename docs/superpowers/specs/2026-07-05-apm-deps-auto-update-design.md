# 設計: apm 依存 pin の CI 自動更新（apm action の追加）

- 日付: 2026-07-05
- ステータス: レビュー待ち
- 対象 Issue: #7「apm actionの追加」（CI で apm を自動更新し PR を作成する）
- 対象リポジトリ: apm-config（producer / カタログ側）

## 1. 背景と目的

apm-config は各 consumer リポジトリへ配る APM 設定の SoT であり、上流依存を
`apm.yml` に**厳密固定（SHA ピン必須）**している。現状これらの pin 更新は
README「更新フロー」に記載のとおり**手動**（上流の最新版を見て SHA / バージョンを
手書き）で、追従が属人的・後追いになりやすい。

本設計は、この手動追従を CI で自動化し、更新がある場合に PR を自動作成する。
カタログ側の pin が新鮮に保たれることで、下流 consumer が `apm update` した際に
最新の共通ツール群を受け取れる。

## 2. 対象となる 4 依存と定義場所

| 依存 | 現在の pin | 定義場所 | 追従源 | 「最新」の定義 |
| --- | --- | --- | --- | --- |
| superpowers | `obra/superpowers#<sha>` | `base/apm.yml` `dependencies.apm` | GitHub release | 最新 release tag → commit SHA |
| chrome-devtools | `ChromeDevTools/chrome-devtools-mcp#<sha>` | `mcp-toolkit/apm.yml` `dependencies.apm` | GitHub release | 最新 release tag（`chrome-devtools-mcp-vX.Y.Z`）→ commit SHA |
| serena | `git+https://github.com/oraios/serena@<sha>`（uvx args 埋め込み） | `mcp-toolkit/apm.yml` `dependencies.mcp` | GitHub release | 最新 release tag（`vX.Y.Z`）→ commit SHA |
| context7 | `@upstash/context7-mcp@X.Y.Z`（npx args 埋め込み） | `mcp-toolkit/apm.yml` `dependencies.mcp` | npm registry | `npm view` の最新版 |

- deepwiki はホスト型リモート MCP で pin 対象なし → 自動更新の対象外。
- speckit は外部依存を持たない → 対象外。
- apm-config 自身は apm CLI バージョンを pin していない（mise.toml 等なし）→
  「apm CLI 版の更新」は本設計のスコープ外。

### 非対称性（設計の要）

`dependencies.apm`（superpowers / chrome-devtools）は APM 純正の
`apm outdated` / `apm update` が扱えるが、`dependencies.mcp` の context7 / serena は
**`command` / `args` 文字列に版が埋め込まれ**、APM 純正コマンドの管理対象外。
この 2 依存はどの方式でも独自処理が不可避なため、4 依存すべてを**統一ロジックの
独自スクリプト**で扱う（split-brain を避ける）。

## 3. 決定事項（ユーザー確認済み）

| 論点 | 決定 |
| --- | --- |
| 実装方式 | **独自 GitHub Actions ワークフロー（スクリプト方式）**。Renovate / 純正 `apm outdated`+`update` は不採用 |
| pin 形式 | **SHA ピンを維持**（README の「SHA ピン必須」ポリシー継続） |
| 「最新」の定義 | **最新 release tag を commit SHA に解決**して書き換え（main HEAD 追従はしない＝未リリースの気まぐれ変更を取り込まない） |
| トリガー頻度 | 週次（cron）+ 手動実行 |
| version bump | 依存が変わったサブパッケージの `version:` を patch 上げ |

### 3.1 不採用案とその理由

- **Renovate（self-hosted）**: 成熟し changelog / auto-merge を持つが、4 pin の小規模
  カタログには過剰。token / GitHub App 準備が要り、args 埋め込み版は customManager
  (regex) が必要で結局特殊対応が残る。PR 内での apm 解決検証も別途。
- **純正 `apm outdated` + `apm update --yes`**: (1) 各サブパッケージへ lockfile 新規導入が
  必要（現状ゼロ）、(2) context7 / serena は原理的に対象外で独自処理を併用＝split-brain、
  (3) SHA pin を tag / semver ref へ緩める必要があり「SHA ピン必須」ポリシーと衝突。

## 4. コンポーネント

| 追加物 | 役割 |
| --- | --- |
| `.github/workflows/apm-update.yml` | トリガー・権限・PR 作成のオーケストレーション |
| `scripts/update-apm-pins.sh` | 4 依存の最新解決 + `apm.yml` 書き換え + PR 本文生成。ローカル実行・`--dry-run` 対応 |
| （リポジトリ設定）Actions の "Allow GitHub Actions to create and approve pull requests" 有効化 | bot による PR 作成の前提 |
| （リポジトリ設定）`dependencies` ラベルの作成（`gh label create dependencies`） | apm-config は現状デフォルトラベルのみで `dependencies` 未作成。PR 付与前に一度だけ作成する前提。作成しない場合は §6 のラベル付与を外す |

- ロジックは workflow にベタ書きせずスクリプトへ分離（レビュー容易・ローカル検証可能・冪等性テスト可能）。
- ランタイム追加は不要。ubuntu-latest 同梱の `gh` / `node`（`npm view`）/ `perl` のみ使用。
  apm-config に初めて `scripts/` を置くが、自動化ロジックの置き場所として妥当。

## 5. 解決ロジック（依存ごと「最新 release → commit SHA」）

スクリプトは依存を宣言的テーブルで保持し、各依存に対し次を行う。

1. **superpowers**（github dep）
   - `tag=$(gh api repos/obra/superpowers/releases/latest --jq .tag_name)`
   - `sha=$(gh api repos/obra/superpowers/commits/$tag --jq .sha)`
   - `base/apm.yml` の `obra/superpowers#<40hex>` を新 SHA に置換。
2. **chrome-devtools**（github dep, monorepo tag naming）
   - `tag=$(gh api repos/ChromeDevTools/chrome-devtools-mcp/releases/latest --jq .tag_name)`（例 `chrome-devtools-mcp-v1.5.0`）
   - `sha=$(gh api repos/ChromeDevTools/chrome-devtools-mcp/commits/$tag --jq .sha)`
   - `mcp-toolkit/apm.yml` の `chrome-devtools-mcp#<40hex>` を置換。
   - 併せてコメント `chrome-devtools-mcp@X.Y.Z` を tag から導出した版へ同期更新。
3. **serena**（git sha in uvx args）
   - `tag=$(gh api repos/oraios/serena/releases/latest --jq .tag_name)`（例 `v1.5.3`）
   - `sha=$(gh api repos/oraios/serena/commits/$tag --jq .sha)`
   - `mcp-toolkit/apm.yml` の `git+https://github.com/oraios/serena@<40hex>` を置換。
4. **context7**（npm）
   - `ver=$(npm view @upstash/context7-mcp version)`
   - `mcp-toolkit/apm.yml` の `@upstash/context7-mcp@X.Y.Z` を置換。

### 5.1 堅牢性

- `/commits/<ref>` エンドポイントで解決するため annotated / lightweight tag の差を吸収
  （常に ref が指す commit SHA を返す）。
- `releases/latest` は prerelease / draft を除外（安定版のみ追従）。release が存在しない
  依存は skip + warn（現状 4 依存はすべて release あり）。
- 置換は **anchored regex（perl）で対象文字列のみ外科的に**行い、コメント・整形・
  他の行を完全保持する。`yq` 等での全体再整形はコメント churn を招くため使わない。

## 6. 変更検知と PR

- 書き換え後 `git diff --quiet -- base/apm.yml mcp-toolkit/apm.yml` で判定。
  - 差分なし → 何もせず正常終了（ログのみ）。
  - 差分あり → 下記で PR 作成 / 更新。
- **`peter-evans/create-pull-request@v6`** を使用。
  - `branch: chore/apm-deps-update`（固定ブランチ＝毎回同じ PR をローリング更新）。
  - `commit-message` / `title`: `chore(deps): apm 依存 pin を更新`（日本語 + Conventional Commits＝リポジトリ規約準拠）。
  - `labels: dependencies`（§4 の前提で一度だけ作成するラベル。ROhta の他リポジトリで使う依存更新ラベルの慣行に揃える）。
  - `body`: 依存ごと old→new（版 + short SHA）＋ release / npm リンクの表を
    スクリプトが生成し `body-path` で渡す。
  - `delete-branch: true`。
- version bump: 依存が変わったサブパッケージの `version:` を patch 上げ（例:
  context7 / chrome-devtools / serena いずれか変化で `mcp-toolkit` を +patch、
  superpowers 変化で `base` を +patch）。スクリプトが該当ファイルの `version:` 行のみ更新。

## 7. トークン・権限・トリガー

```yaml
on:
  schedule:
    - cron: "0 0 * * 1"   # 毎週月曜 00:00 UTC
  workflow_dispatch: {}   # 手動実行
permissions:
  contents: write
  pull-requests: write
```

- 既定 `GITHUB_TOKEN` で PR 作成。
- **注記（既知の挙動）**: `GITHUB_TOKEN` が作成した PR は `on: pull_request` /
  `on: push` の Actions を再帰的に起動しない（無限ループ防止のため）。ただし
  CodeRabbit は GitHub App（webhook 駆動）で App はこの制限を受けないため、
  bot PR でもレビューは走る。将来 Actions ベースの PR CI を追加し、それを bot PR でも
  起動したい場合は PAT / GitHub App token に切り替える（設計上の拡張点）。
- 前提設定: リポジトリの Settings → Actions → General → Workflow permissions で
  "Allow GitHub Actions to create and approve pull requests" を有効化する。

## 8. 任意機能: 解決検証ジョブ

- 変更後に `mcp-toolkit` で `apm install --trust-transitive-mcp`、`base` で `apm install`
  を実行し、新 pin が解決することの smoke test を行える。
- SHA は実 release tag から解決済みで、npm 版も `npm view` で存在確認済みのため、
  refs は構成上ほぼ known-good。したがってこの検証は**任意ジョブ**とする
  （追加保証。導入コストと相談で後付け可）。

## 9. テスト観点

- **ローカル dry-run**: `./scripts/update-apm-pins.sh --dry-run` で書き換え差分を表示。
  現時点で **context7 `3.2.0 → 3.2.2` が検知される**（検証可能な実ケース）。
- **冪等性**: 更新適用後に再実行して差分ゼロを確認。
- **release 不在時**: 対象を skip し他依存の処理を継続すること。
- **PR ローリング**: 2 回目以降の実行が新規 PR を乱立させず `chore/apm-deps-update`
  の既存 PR を更新すること。

## 10. リスクと対処

| リスク | 対処 |
| --- | --- |
| 上流が release を出さず main のみ進む依存が将来現れる | 現状 4 依存はすべて release あり。release 不在なら skip + warn し、必要になった時点で追従源を個別に見直す |
| 置換 regex が上流の記法変更で外れる | anchored regex を各依存の一意な文字列に固定。dry-run のローカルテストと冪等性テストで検知。外れた場合は差分ゼロ（=見逃し）になり得るため、将来 `apm outdated` 併用での二重チェックを検討 |
| `GITHUB_TOKEN` 製 PR で Actions ベース CI が起動しない | 現状 PR CI は CodeRabbit（App）のみで影響なし。Actions CI 追加時に PAT / App token へ切替 |
| 自動 version bump が過剰と感じる場合 | patch 上げのみ。不要なら該当ステップを外せる（設計上の分離済み） |

## 11. スコープ外

- deepwiki（ホスト型・pin なし）/ speckit（外部依存なし）の更新。
- apm CLI 本体バージョンの更新（apm-config は CLI を pin していない）。
- consumer リポジトリ側の自動 `apm update`（本設計は producer 側の pin 追従のみ）。
- 純正 `apm outdated` / `apm update` の導入（§3.1 の理由で不採用。将来の二重チェック
  用途として §10 に含みを残すのみ）。
