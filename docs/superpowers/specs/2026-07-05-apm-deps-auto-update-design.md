# 設計: apm 依存 pin の CI 自動更新（apm action の追加）

- 日付: 2026-07-05
- 改訂: 2026-07-06（apm CLI 0.24.0 標準化を受け、`microsoft/apm-action` を用いた
  ハイブリッド方式へ再設計。旧版＝独自スクリプト単独方式は §3.1 に不採用理由を記載）
- ステータス: レビュー待ち
- 対象 Issue: #7「apm actionの追加」（CI で apm を自動更新し PR を作成する）
- 対象リポジトリ: apm-config（producer / カタログ側）

## 1. 背景と目的

apm-config は各 consumer リポジトリへ配る APM 設定の SoT であり、上流依存を
`apm.yml` に**厳密固定**している（git 依存 = superpowers / chrome-devtools / serena は
commit SHA ピン、context7 は npm の exact version ピン）。現状これらの pin 更新は
README「更新フロー」に記載のとおり**手動**（上流の最新版を見て SHA / バージョンを
手書き）で、追従が属人的・後追いになりやすい。

本設計は、この手動追従を CI で自動化し、更新がある場合に PR を自動作成する。
カタログ側の pin が新鮮に保たれることで、下流 consumer が `apm update` した際に
最新の共通ツール群を受け取れる。

apm CLI 本体は #14 で全リポジトリ共通の統一バージョンが **0.24.0** に更新された。
本ワークフローもこの 0.24.0 を明示 pin して使う（§3・§7）。0.24.0 では `apm update` が
**SHA ピンを最新 release tag のコミットへ自動書き換えする**（0.20.0 / #1738）ため、
git 依存の追従を `microsoft/apm-action` に委ねられる点が再設計の起点となる。

## 2. 対象となる 4 依存と更新手段

| 依存 | 現在の pin | 定義場所 | 更新手段 | 「最新」の定義 |
| --- | --- | --- | --- | --- |
| superpowers | `obra/superpowers#<sha>` | `base/apm.yml` `dependencies.apm` | **apm-action `update:true`** | 最新 release tag → commit SHA（apm が自動書換） |
| chrome-devtools | `ChromeDevTools/chrome-devtools-mcp#<sha>` | `mcp-toolkit/apm.yml` `dependencies.apm` | **apm-action `update:true`** | 最新 release tag（`chrome-devtools-mcp-vX.Y.Z`）→ commit SHA |
| serena | `git+https://github.com/oraios/serena@<sha>`（uvx args 埋め込み） | `mcp-toolkit/apm.yml` `dependencies.mcp` | **独自スクリプト** | 最新 release tag（`vX.Y.Z`）→ commit SHA |
| context7 | `@upstash/context7-mcp@X.Y.Z`（npx args 埋め込み） | `mcp-toolkit/apm.yml` `dependencies.mcp` | **独自スクリプト** | `npm view` の最新版 |

- deepwiki（ホスト型・pin なし）/ speckit（外部依存なし＝`dependencies` が空）は対象外。
- apm-config 自身は apm CLI バージョンを pin していない（mise.toml 等なし）→
  「apm CLI 版の更新」は本設計のスコープ外（統一版は base の apm-workflow instructions が SSoT）。

### 非対称性（ハイブリッドの根拠）

`dependencies.apm` の 2 件（superpowers / chrome-devtools）は git ref なので
**0.24.0 の `apm update` がネイティブに最新 release tag へ追従**でき、SHA ピンのまま
維持される。一方 `dependencies.mcp` の context7 / serena は **version が `command` /
`args` 文字列に埋め込まれた self-defined MCP** で、`apm update` は ref を解決するだけ、
これらの版文字列は 0.24.0 でも一切触らない。したがって:

- git ref 2 件 → **apm-action `update:true`（apm 純正）**
- command/args 埋め込み 2 件 → **独自スクリプト**

の**ハイブリッド**が唯一整合する形になる。

## 3. 決定事項（ユーザー確認済み）

| 論点 | 決定 |
| --- | --- |
| 実装方式 | **apm-action ハイブリッド**: `dependencies.apm` 2 件を apm-action `update:true`、`dependencies.mcp` 2 件を独自スクリプト、PR は `peter-evans/create-pull-request` |
| apm CLI 版 | apm-action の `apm-version` を **0.24.0** に明示 pin（base の apm-workflow instructions の統一版を SSoT として追従。既定 0.14.0 のまま使わない） |
| pin 形式 | git 依存は commit SHA ピンを維持（0.24.0 の apm update が最新 release tag → SHA に自動書換）。context7 は npm の exact version ピンを維持（独自スクリプト） |
| **lockfile** | `apm update` は `apm.lock.yaml` を生成・更新するため、**base/ と mcp-toolkit/ に `apm.lock.yaml` を新規導入しコミットする**（現状「lockfile ゼロ」からの構成変更。**ユーザー承認済み 2026-07-06**） |
| 展開物 | `apm update` の post-install（compile/deploy）が生成する依存 primitive の展開ツリーはコミットしない。**コミット対象を `apm.yml` + `apm.lock.yaml` に限定** |
| 「最新」の定義 | git 依存は最新 release tag を commit SHA に解決（main HEAD 追従はしない）。context7 は `npm view` の最新版 |
| トリガー頻度 | 週次（cron）+ 手動実行 |
| version bump | 依存が変わったサブパッケージの `version:` を patch 上げ |

### 3.1 不採用案とその理由

- **独自スクリプト単独（本 spec 旧版, 2026-07-05）**: 0.24.0 では `apm update` が
  SHA ピンを最新 release tag へ自動追従できるため、apm 純正で扱える `dependencies.apm`
  2 件まで自前解決するのは車輪の再発明。ただし context7 / serena は原理的に純正対象外
  なので、独自スクリプトを完全には捨てられず**ハイブリッド**に落ち着く。
- **Renovate（self-hosted）**: 4 pin の小規模カタログには過剰。token / GitHub App 準備、
  args 埋め込み版の customManager 対応が必要で、apm 純正の SHA 追従とも二重になる。
- **純正 `apm outdated` + `apm update` だけで全 4 件**: context7 / serena は
  command/args 埋め込みで純正の管理対象外。全件は不可能。

## 4. コンポーネント

| 追加物 | 役割 |
| --- | --- |
| `.github/workflows/apm-update.yml` | トリガー・権限・apm-action 呼び出し・独自スクリプト実行・PR 作成のオーケストレーション |
| `scripts/apm-pins.sh` | **context7 / serena のみ**の最新解決 + `mcp-toolkit/apm.yml` 書き換え + PR 本文断片生成。ローカル実行・`--dry-run` 対応 |
| `base/apm.lock.yaml` / `mcp-toolkit/apm.lock.yaml` | apm-action `update:true` が生成・更新する lockfile。初回にコミットして以降追跡 |
| （リポジトリ設定）Actions の "Allow GitHub Actions to create and approve pull requests" 有効化 | bot による PR 作成の前提 |
| （リポジトリ設定）`dependencies` ラベルの作成（`gh label create dependencies`） | apm-config は現状デフォルトラベルのみ。PR 付与前に一度だけ作成する前提 |

- 独自スクリプトは旧版の 4 依存から **2 依存（context7 / serena）に縮小**。
- ランタイム追加は不要。ubuntu-latest 同梱の `gh` / `node`（`npm view`）/ `perl` のみ使用。

## 5. 更新ロジック

### 5.0 実行順序（重要 — lockfile 整合のため固定）

`mcp-toolkit/` は **apm-action 管理（chrome-devtools）と独自管理（context7 / serena）が
同一ファイル・同一 lockfile に同居**する。`apm update` は実行時点の `apm.yml` から
`apm.lock.yaml` を生成するため、順序を誤ると lockfile が古い pin を捕捉して apm.yml と
ドリフトする。したがって順序を次に固定する:

1. **独自スクリプト（§5.2）を先に実行** — `mcp-toolkit/apm.yml` の context7 / serena を書き換える。
2. **その後 apm-action `update:true`（§5.1）** を base/ と mcp-toolkit/ で実行 — 更新後の
   `apm.yml` から `apm.lock.yaml` を生成し、chrome-devtools / superpowers の SHA も追従する。

これにより mcp-toolkit の lockfile が context7 / serena の新 pin を捕捉し、
apm.yml ↔ lockfile の整合が保たれる（base は独自対象なしのため順序非依存）。

### 5.1 apm-action による `dependencies.apm` 更新（superpowers / chrome-devtools）

`base/` と `mcp-toolkit/` それぞれで `microsoft/apm-action` を `update: true` で実行する
（`working-directory` で切り替え。2 ステップまたは matrix）。Action は §7 のとおり
commit SHA で固定する（下の例はバージョン可読性のため tag 表記）。

```yaml
- uses: microsoft/apm-action@<sha>   # v1.x を SHA 固定（§7）
  with:
    working-directory: base          # と mcp-toolkit を別ステップ/matrix で
    apm-version: "0.24.0"
    update: "true"
```

- `update: true` は `apm update --yes` を実行し、**SHA ピンを最新 annotated release tag の
  コミットへ書き換え、`apm.lock.yaml` を更新**する（0.20.0 / #1738）。SHA ピンのまま維持。
- chrome-devtools の monorepo tag（`chrome-devtools-mcp-vX.Y.Z`）も `apm outdated`/`update`
  が認識する（0.18.0 / 0.23.0）。
- 前提: 対象上流が **annotated release tag を publish している**こと（superpowers /
  chrome-devtools はいずれも GitHub Releases あり）。
- 副作用: `update:true` は post-install（audit / compile / deploy）まで走り、依存 primitive の
  展開ツリー（`.github/` / `.claude/` 等）が生成され得る。→ §6 でコミット対象を限定し
  展開物は含めない。apm-action は展開なしの `apm lock` 相当を公開しないため、この
  コミット限定で対処する。
- 検証ポイント（初回 CI）: chrome-devtools は marketplace プラグイン参照だが
  `dependencies.apm` の git ref として apm update が解決・追従することを最初の
  `workflow_dispatch` 実行で確認する。

### 5.2 独自スクリプトによる command/args 埋め込み版更新（context7 / serena）

`scripts/apm-pins.sh` が `mcp-toolkit/apm.yml` の 2 件を更新する。

1. **context7**（npm）
   - `ver=$(npm view @upstash/context7-mcp version)`
   - `@upstash/context7-mcp@X.Y.Z` を新版へ置換。
2. **serena**（git sha in uvx args）
   - `tag=$(gh api repos/oraios/serena/releases/latest --jq .tag_name)`
   - `sha=$(gh api repos/oraios/serena/commits/$tag --jq .sha)`
   - `git+https://github.com/oraios/serena@<40hex>` を新 SHA へ置換。

堅牢性:

- `/commits/<ref>` エンドポイント解決で annotated / lightweight tag の差を吸収。
- 置換は **anchored regex（perl）で対象文字列のみ外科的に**行い、コメント・整形を完全保持。
- **異常は fail-fast（すべて非ゼロ終了）**: (1) 書き換え前に現在の pin（anchor）が対象ファイルに
  **ちょうど 1 回**マッチすることを検証し、0 回 / 複数回なら manifest 形状変化と見なし失敗。
  (2) context7 / serena の最新版（`npm view` / `gh api`）が**取得できない場合も skip せず失敗**する。
  context7 / serena は常に存在するため、解決失敗は実障害（ネットワーク / API 断）であり、
  silent に更新が止まるのを防ぐため CI を赤くして再実行・通知に繋げる。「regex が外れても
  差分ゼロで成功扱い」「ソース断で無言スキップ」という見逃しを両方排除する。

## 6. 変更検知と PR

- apm-action（§5.1）と独自スクリプト（§5.2）を実行後、`apm.yml` + `apm.lock.yaml` の
  diff で判定。
  - 差分なし → 何もせず正常終了（ログのみ）。
  - 差分あり → 下記で PR 作成 / 更新。
  - §5.2 の anchor 不一致で失敗した場合はここに到達せず job が失敗する（見逃し防止）。
- **コミット対象を `base/apm.yml` / `mcp-toolkit/apm.yml` / 各 `apm.lock.yaml` に限定**。
  apm update が展開した依存 primitive ツリーは add しない（`.gitignore` もしくは
  `git add` の明示指定で除外）。
- **`peter-evans/create-pull-request`** を使用（§7 のとおり commit SHA 固定、v8.x）。
  - `branch: chore/apm-deps-update`（固定ブランチ＝毎回同じ PR をローリング更新）。
  - `commit-message` / `title`: `chore(deps): apm 依存 pin を更新`（日本語 + Conventional Commits）。
  - `labels: dependencies`（§4 の前提で作成するラベル）。
  - `body`: apm-action の更新結果（superpowers / chrome-devtools の old→new SHA）と
    独自スクリプトが生成する断片（context7 / serena の old→new）を結合した表を `body-path` で渡す。
  - `delete-branch: true`。
- version bump: 依存が変わったサブパッケージの `version:` を patch 上げ（context7 /
  chrome-devtools / serena いずれか変化で `mcp-toolkit`、superpowers 変化で `base`）。

## 7. トークン・権限・トリガー

```yaml
on:
  schedule:
    - cron: "0 0 * * 1"   # 毎週月曜 00:00 UTC
  workflow_dispatch: {}
permissions:
  contents: write
  pull-requests: write
```

- apm-action は `apm-version: "0.24.0"` を明示 pin（base の apm-workflow instructions の
  統一版に追従。統一版が上がったらこの pin も追従して更新する）。
- **サードパーティ Action は commit SHA で固定**する。`microsoft/apm-action` /
  `peter-evans/create-pull-request` を major tag（`@v1` / `@v8`）のまま使わず、解決済み
  commit SHA に pin し対応バージョン（`apm-action v1.x` / `create-pull-request v8.x`）を
  コメント併記する。本リポジトリの「依存は SHA ピン」方針と揃え、upstream 更新で PR 自動
  生成挙動が変わる余地を排除する。SHA の更新は本ワークフローの対象外（手動 / 別途 Dependabot）。
- 既定 `GITHUB_TOKEN` で PR 作成。`GITHUB_TOKEN` 製 PR は `on: pull_request` を再帰起動しないが、
  CodeRabbit は GitHub App（webhook 駆動）なのでレビューは走る。将来 Actions ベースの PR CI を
  bot PR でも起動したい場合は PAT / GitHub App token へ切替（拡張点）。
- 前提設定: §4 のリポジトリ設定 2 点。

## 8. MCP trust（0.24.0 の executable-trust）

- 0.22.0 の Executable Trust Governance で trust モデルが刷新され、MCP 等の executable は
  **永続 `apm approve <pkg>` の事前シード**方式に移行した（旧 `--trust-*` 系フラグは廃止方向）。
  apm-action に approve / trust の input は無い。
- **更新ジョブ（ref / lockfile 更新）では非ブロッキング**: 未承認の transitive MCP
  （chrome-devtools）は lockfile に `exec_status: gated_pending_approval` として記録されるだけで、
  `apm update` 自体は失敗しない。pin 追従に必要な ref 解決は成立する。
- **実展開の検証（§9）で chrome-devtools を実際に deploy したい場合のみ**、apm-action の前に
  直叩き `apm approve` を挟む必要がある（apm-action では代替不可）。

## 9. 任意機能: 解決検証

- 別ジョブで `microsoft/apm-action@v1`（`update: false` = install）を回し、書き換え後の pin が
  解決・展開できることを smoke test できる。chrome-devtools の実展開まで見るなら §8 の
  `apm approve` 事前シードが要る。
- SHA は release tag から、npm 版は `npm view` から解決済みで構成上ほぼ known-good のため、
  この検証は**任意ジョブ**とする（追加保証）。

## 10. テスト観点

- **独自スクリプト dry-run**: `./scripts/apm-pins.sh update --dry-run` で書き換え差分を表示。
  現時点で **context7 `3.2.0 → 3.2.2` が検知される**（検証可能な実ケース）。
- **anchor 不一致時の fail-fast**: managed 依存の anchor をわざと変えた fixture でスクリプトが
  非ゼロ終了すること。
- **冪等性**: 更新適用後の再実行で差分ゼロ（スクリプト・apm-action とも）。
- **apm-action の初回確認**: `workflow_dispatch` で手動実行し、(1) `base` / `mcp-toolkit` の
  `apm.lock.yaml` が生成されること、(2) superpowers / chrome-devtools の SHA が最新 release tag へ
  書き換わること、(3) 展開物がコミット対象に混ざらないことを確認する。
- **PR ローリング**: 2 回目以降が新規 PR を乱立させず `chore/apm-deps-update` の既存 PR を更新すること。

## 11. リスクと対処

| リスク | 対処 |
| --- | --- |
| 上流が annotated release を出さず main のみ進む依存が将来現れる | 現状 4 依存はすべて GitHub Releases あり。apm update / 独自スクリプトとも release 起点。解決不能時は**非ゼロ終了で可視化**し、必要時に追従源を個別再検討（silent skip はしない） |
| `apm update` の展開物が誤ってコミットされる | コミット対象を `apm.yml` + `apm.lock.yaml` に限定（§6）。初回 CI で展開物が混ざらないことを確認（§10） |
| apm-action が独自スクリプトの後に `mcp-toolkit/apm.yml` を再整形しコメントが churn する | 実行順序を §5.0 で固定（独自 → apm-action）済みで**値の整合は保たれる**。コメント保持は apm update の manifest 再書き込み挙動次第のため、初回 CI で mcp-toolkit のコメント差分を確認し、churn するなら許容 / 別途対処（値は正）を判断 |
| 独自スクリプトの regex が上流記法変更で外れる | §5.2 の fail-fast（anchor が 1 回マッチしなければ非ゼロ終了）で「差分ゼロ成功」の見逃しを防ぐ。dry-run / 冪等性テストでも検知 |
| chrome-devtools（transitive MCP）の trust 未承認で検証が不完全 | 更新ジョブ自体は非ブロッキング（§8）。実展開検証を入れる場合のみ `apm approve` を事前シード |
| lockfile 導入で consumer 側に影響 | apm-config の lockfile は producer 内部の解決記録。consumer は従来どおり自リポジトリの lockfile で解決するため影響なし |
| `GITHUB_TOKEN` 製 PR で Actions ベース CI が起動しない | 現状 PR CI は CodeRabbit（App）のみで影響なし。Actions CI 追加時に PAT / App token へ切替 |

## 12. スコープ外

- deepwiki（ホスト型・pin なし）/ speckit（外部依存なし）の更新。
- apm CLI 本体バージョンの更新（統一版は base の apm-workflow instructions が SSoT）。
- consumer リポジトリ側の自動 `apm update`（本設計は producer 側の pin 追従のみ）。
- README の trust フラグ記述（`--trust-transitive-mcp`）を 0.24.0 の `apm approve` 方式へ
  整合させる作業（別 Issue / 別 PR）。#14 で CLI 版のみ 0.24.0 に上げた際に未追従の箇所。
