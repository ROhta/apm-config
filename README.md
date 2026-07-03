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
| `base/` | 言語ルール・PR レビュー観点の共通 instructions と superpowers スキル | 全リポジトリ |
| `mcp-toolkit/` | context7 / semgrep / serena / chrome-devtools を marketplace プラグインとして一元 pin | MCP を使うリポジトリ |

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
# mcp-toolkit を参照する場合は --trust-transitive-mcp が必須。
# 依存プラグインが同梱する MCP サーバーはデフォルトでブロックされるため。
apm install --trust-transitive-mcp   # 依存を apm_modules/ に取得し .github/instructions/・.claude/rules/・.claude/settings.json・.agents/skills/ 等へ展開
apm compile                          # AGENTS.md 等を生成
```

- 参照は `#main` を推奨。`apm.lock.yaml`（consumer 側でコミット）が解決済み
  コミット SHA を固定するため、`apm update` を実行するまで内容は変わらない。
- 共通化した instructions は consumer ローカルの `.apm/instructions/` から削除する
  （ローカルの同名ファイルは依存より優先されるため、残すと共通化が効かない）。
- `--trust-transitive-mcp` は apm.yml / apm.lock.yaml に永続化されない。素の
  `apm install` を打つと mcp-toolkit の MCP がクライアント設定に展開されないため、
  ラッパースクリプト（Makefile 等）でフラグ込みのコマンドを標準化することを推奨。
- mcp-toolkit を使う場合、ユーザーレベルに同名プラグイン（context7 / serena /
  semgrep / chrome-devtools）が残っていると MCP サーバーが二重起動する。プロジェクト
  側に一本化するならユーザーレベルのプラグインをアンインストールすること。

## 更新フロー

1. 本リポジトリの `base/` や `mcp-toolkit/` を編集し、ブランチ + PR でマージ。
   - プラグインの pin を上げる際は、公式 marketplace
     （`anthropics/claude-plugins-official`）の該当コミット SHA に合わせる。
2. 各 consumer で `apm update --trust-transitive-mcp && apm compile` を実行し、
   `apm.lock.yaml` の差分をコミットする。

## pin ポリシー（mcp-toolkit）

共通開発ツールの MCP は marketplace プラグインとして参照し、プラグインリポジトリの
コミット SHA で pin する。ただし pin できる範囲はプラグインの manifest 次第で異なる。

| プラグイン | pin される範囲 | MCP サーバー本体 |
| --- | --- | --- |
| context7 | プラグイン（skills 等） | ✗ 未 pin（`npx -y @upstash/context7-mcp` で毎回 latest） |
| serena | プラグイン | ✗ 未 pin（`uvx --from git+.../serena` で main HEAD 追従） |
| chrome-devtools | プラグイン | ✓ pin される（manifest が `chrome-devtools-mcp@x.y.z` を指定） |
| semgrep | プラグイン | ⚠ `${CLAUDE_PLUGIN_ROOT}` 依存。Claude Code 以外では動かない可能性 |

context7 / serena の MCP サーバー本体まで pin したい場合は、この 2 つのみ
`dependencies.mcp` への自前定義（command / args / バージョン直書き）に切り替える。
