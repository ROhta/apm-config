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

### chrome-devtools の初回導入時の挙動

新規 consumer で `apm install --trust-transitive-mcp` を実行すると、**1 回目はプラグイン
`chrome-devtools-mcp` の解決のみで、`.mcp.json` 等への設定は 2 回目の実行で確定する**ことがある
（transitive プラグインの解決とサーバー設定が別パスのため）。導入時は
`apm install --trust-transitive-mcp` を 2 回実行し、`.mcp.json` に chrome-devtools を含む
4 サーバーが揃うことを確認する。上記ラッパースクリプトで 2 回実行を含めておくと確実。

なお chrome-devtools のコマンドは上流プラグインの manifest が定義する (`npx chrome-devtools-mcp@<pin>`、
`-y` 無し) ため、初回 `npx` 実行時にインストール確認プロンプトが出うる。CI/エージェント実行では
`npx` が非対話で進むよう環境を整えるか、事前に一度手動実行しておく。

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

### 登録方式: APM レジストリ優先、担保できない場合のみ self-defined

MCP サーバーは **APM 公式レジストリ (`apm mcp install <registry-id>`) を優先** して登録する。
ただし本 toolkit は「版を固定して再現性を担保する」ことを最優先とするため、レジストリ経由で
次のいずれかに該当し挙動を担保できない場合に限り、**self-defined** にフォールバックする。
ここで `<registry-id>` はレジストリ項目 ID (例: `io.github.upstash/context7`)、
`<name>` は self-defined 時に付ける任意のローカル登録名 (例: `context7`) を指す。

- **版を固定できない**: レジストリ項目に固定可能なバージョンが無い (`apm mcp show <registry-id>` の
  Version が Unknown 等)。本 toolkit は `@latest` を禁じ具体版 / コミット SHA で固定するため、
  `--mcp-version` で固定できないものは self-defined にする。
- **解決結果が意図と異なる**: レジストリが別パッケージ・別ソース・別トランスポートに解決する
  (例: 期待する git コミット固定ではなく PyPI 版になる / streamable-http ではなく SSE になる 等)。
- **不要な認証・前提を要求する**: レジストリ項目が self-defined では不要な API キー等を要求し、
  非対話 (CI / エージェント) 実行を妨げる。

self-defined の登録形式はトランスポートで異なる。**stdio** は
`apm mcp install <name> -- <command> [args...]` (`apm.yml` では `transport: stdio` + `command` / `args`)、
**リモート (http / sse / streamable-http)** は `apm mcp install <name> --transport <t> --url <url>`
(`apm.yml` では `transport: <t>` + `url`。例: deepwiki は `transport: http` +
`url: https://mcp.deepwiki.com/mcp`)。いずれも `apm.yml` では `registry: false` を付ける。

レジストリで登録する場合も `--mcp-version` で必ず版を固定する (固定不可なら上記により self-defined)。
登録前に `apm mcp show <registry-id>` で「解決先パッケージ・トランスポート・版・要求 env」を確認すること。

#### 現行サーバーの登録方式 (2026-07 時点、apm 0.24.x の `apm mcp show` で検証)

`context7` / `serena` / `deepwiki` はレジストリでは上記の担保要件を満たせないため self-defined を維持し、`chrome-devtools` はプラグイン manifest の pin を利用する (レジストリ登録の対象外)。

| サーバー          | 方式          | レジストリを採らない理由 |
| ----------------- | ------------- | ------------------------ |
| `context7`        | self-defined  | レジストリ項目 `io.github.upstash/context7` は版が Unknown で固定不可、かつ `CONTEXT7_API_KEY` を要求して非対話実行が中断する。self-defined (`npx -y @upstash/context7-mcp@<ver>`) はキー不要で版固定可。 |
| `serena`          | self-defined  | レジストリ項目 `oraios/serena` は PyPI 版 (`uvx serena`) に解決し版固定不可。本 toolkit は git コミット SHA (`git+https://github.com/oraios/serena@<sha>`) で byte 単位の再現性を担保する。(かつてレジストリが `uvx ide-assistant` へ誤解決した経緯があるが現在は解消済み。) |
| `deepwiki`        | self-defined  | レジストリ項目 `cognitionai/deepwiki` は SSE エンドポイント (`/sse`) を返す。本 toolkit は streamable-http (`/mcp`) を使う (Codex アダプタが SSE を受理しないため)。 |
| `chrome-devtools` | プラグイン経由 | `ChromeDevTools/chrome-devtools-mcp` プラグインの manifest が MCP 本体を pin するため、レジストリ登録の対象外。 |

## 生成物の場所

`apm install` が以下のファイルを生成する。すべて `.gitignore` 対象。

| パス                 | 対応 IDE                    |
| -------------------- | --------------------------- |
| `.mcp.json`          | Claude Code (project scope) |
| `.vscode/mcp.json`   | GitHub Copilot in VS Code   |
| `.codex/config.toml` | Codex CLI                   |
