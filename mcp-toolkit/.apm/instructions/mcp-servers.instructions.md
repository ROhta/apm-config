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
