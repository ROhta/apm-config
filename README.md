# apm-config

ROhta の各リポジトリで共通する [APM](https://microsoft.github.io/apm/) 設定
（AI エージェント向け instructions・MCP サーバー・依存 pin）を一元管理する
カタログ型リポジトリ。各 consumer リポジトリは `apm.yml` の `dependencies.apm`
から、必要なサブパッケージだけをサブパス参照する。

## 構成（レイヤー別サブパッケージ）

1 リポジトリ内にレイヤーごとのサブパッケージを置き、各 consumer が必要な層だけ
取り込む。サブディレクトリは自前の `apm.yml` を持つ独立した APM パッケージ。

| サブパッケージ | 内容 | 主な利用先 |
| --- | --- | --- |
| `base/` | 言語ルール・PR レビュー観点の共通 instructions | 全リポジトリ |
| `mcp-toolkit/` | context7 / semgrep / serena / chrome-devtools の MCP pin を一元管理 | MCP を使うリポジトリ |

## consumer 側の使い方

`apm.yml` の `dependencies.apm` にサブパス参照を追加する。

```yaml
dependencies:
  apm:
    - ROhta/apm-config/base#main
    - ROhta/apm-config/mcp-toolkit#main   # MCP が必要なリポジトリのみ
  mcp:
    - # リポジトリ固有の MCP はここに個別記載（例: storybook）
```

その後 consumer 側で以下を実行する。

```bash
apm install   # 依存を apm_modules/ に取得し .github/instructions/・.claude/rules/・.mcp.json 等へ展開
apm compile   # AGENTS.md 等を生成
```

- 参照は `#main` を推奨。`apm.lock.yaml`（consumer 側でコミット）が解決済み
  コミット SHA を固定するため、`apm update` を実行するまで内容は変わらない。
- 共通化した instructions は consumer ローカルの `.apm/instructions/` から削除する
  （ローカルの同名ファイルは依存より優先されるため、残すと共通化が効かない）。

## 更新フロー

1. 本リポジトリの `base/` や `mcp-toolkit/` を編集し、ブランチ + PR でマージ。
2. 各 consumer で `apm update && apm compile` を実行し、`apm.lock.yaml` の差分を
   コミットする。

## pin ポリシー（mcp-toolkit）

MCP サーバーのバージョン/コミットはリポジトリ間で不揃いになりやすいため、
本リポジトリで newer 側へ統一して一元管理する。
