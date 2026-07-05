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
| `base/` | 言語ルール・PR レビュー観点、APM 運用・プラグイン管理、開発/リリースフロー、ローカル開発ワークフロー・PR レビュー応答ループの共通 instructions と superpowers スキル | 全リポジトリ |
| `mcp-toolkit/` | context7 / serena / deepwiki（`dependencies.mcp` 直接定義）と chrome-devtools（marketplace プラグイン参照）の pin を一元管理、MCP サーバー運用ルール instructions | MCP を使うリポジトリ |
| `speckit/` | Spec Kit 機能開発フローと Spec Kit × APM 連携の instructions | Spec Kit を使うリポジトリ |

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
# chrome-devtools のみプラグイン参照（transitive）のため、mcp-toolkit を使うなら
# --trust-transitive-mcp を付ける。フラグは全 MCP に一括でかかる。
apm install --trust-transitive-mcp   # 依存を apm_modules/ に取得し .github/instructions/・.claude/rules/・.claude/settings.json・.agents/skills/ 等へ展開
apm compile                          # AGENTS.md 等を生成
```

- 参照は `#main` を推奨。`apm.lock.yaml`（consumer 側でコミット）が解決済み
  コミット SHA を固定するため、`apm update` を実行するまで内容は変わらない。
- 共通化した instructions は consumer ローカルの `.apm/instructions/` から削除する
  （ローカルの同名ファイルは依存より優先されるため、残すと共通化が効かない）。
- trust の粒度: `dependencies.mcp` で直接定義した context7 / serena / deepwiki は
  consumer から見て直接依存（depth 1）なので self-defined でも auto-trust され、
  フラグなしで展開される。`--trust-transitive-mcp` が要るのはプラグイン参照の
  chrome-devtools（depth 2）だけ。chrome-devtools を使う限りは install 時にフラグを
  付与する（フラグは apm.yml / apm.lock.yaml に永続化されないため、ラッパー
  スクリプト（Makefile 等）で標準化することを推奨）。
- mcp-toolkit を使う場合、ユーザーレベルに同名の MCP / プラグイン（context7 /
  serena / deepwiki / chrome-devtools）が残っていると MCP サーバーが二重起動する。
  プロジェクト側に一本化するならユーザーレベルのプラグイン・設定をアンインストール
  すること。

## 更新フロー

1. 本リポジトリの `base/` や `mcp-toolkit/` を編集し、ブランチ + PR でマージ。
   - context7 / serena は `dependencies.mcp` のバージョン / コミット SHA を直接編集して pin を上げる。
   - chrome-devtools はプラグイン参照リポジトリ（`ChromeDevTools/chrome-devtools-mcp`）の
     該当コミット SHA に合わせる。
2. 各 consumer で `apm update --trust-transitive-mcp && apm compile` を実行し、
   `apm.lock.yaml` の差分をコミットする。

## pin ポリシー（mcp-toolkit）

共通開発ツールの MCP はリポジトリ間で不揃いになりやすいため、本リポジトリで一元 pin する。
MCP サーバー本体のバージョンまで固定するため、原則 `dependencies.mcp` に直接定義する。

| MCP | 定義方法 | 配布先 | pin 範囲 |
| --- | --- | --- | --- |
| context7 | `dependencies.mcp`（stdio: `npx -y @upstash/context7-mcp@3.2.0`） | claude / codex / copilot | ✓ 本体まで pin |
| serena | `dependencies.mcp`（stdio: `uvx --from git+.../serena@<sha>`） | claude / codex / copilot | ✓ 本体まで pin |
| deepwiki | `dependencies.mcp`（remote http: `https://mcp.deepwiki.com/mcp`） | claude / codex / copilot | ─（ホスト型サービス。pin 対象なし） |
| chrome-devtools | marketplace プラグイン参照（SHA pin） | claude / codex / copilot | ✓ プラグイン manifest が `chrome-devtools-mcp@x.y.z` を pin |

補足:

- **semgrep は本リポジトリでは配布しない。** 上流プラグインの MCP は
  `${CLAUDE_PLUGIN_ROOT}/scripts/hook.sh` と Claude Code 専用 hooks に依存し、
  自動スキャン（Guardian）の本体価値が Claude 固有のため。semgrep が必要な
  リポジトリは、各自 Claude ネイティブプラグインとして個別導入する。
- **deepwiki は streamable-http（`/mcp`）を使う。** SSE ではないため codex にも
  書き込まれる（APM の codex アダプタは SSE リモートのみ拒否する）。
- chrome-devtools を `dependencies.mcp` の直接定義（`npx -y chrome-devtools-mcp@x.y.z`）に
  切り替えれば depth 1 化して `--trust-transitive-mcp` が不要になるが、本 PR では
  上流プラグインの pin 追従を優先してプラグイン参照を維持している。
