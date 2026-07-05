---
description: ローカル開発時のフロー (実装完了から PR 作成) を superpowers 系スキルで定義。PR レビュー応答ループは review-response-loop ルールに委譲
applyTo: "**"
---

# ローカル開発ワークフロー (AI エージェント向け)

このリポジトリでローカル開発を進める AI エージェントは、以下のワークフローに従う。

## 適用対象

本ワークフローは **superpowers 系スキルを用いるリポジトリ**向けの手順。**Spec Kit 採用リポジトリ**は、本ファイルではなく **speckit-workflow の開発フロー**に従い、以下の superpowers ベースの手順（存在確認・§2 のスキル駆動 PR 作成）は使わない。

判定（いずれかが真なら Spec Kit 採用リポジトリ）:

- `apm.yml` の `dependencies.apm` が `ROhta/apm-config/speckit` を参照している
- `speckit-workflow` 指示の生成物が存在する（例: `.github/instructions/speckit-workflow.instructions.md` または `.claude/rules/speckit-workflow.md`）

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

PR 作成・push 後の自走レビュー応答ループ（検知 → 妥当性判断 → 対応 → resolve まで繰り返し）は **review-response-loop ルール**に従う。このループは superpowers の有無に依存しない共通手順として base から配信される（`.github/instructions/review-response-loop.instructions.md` / `.claude/rules/review-response-loop.md`）。

## 関連ルール

- PR 作成・push 後の自走レビュー応答ループは review-response-loop ルールを参照
- レビュー応答の文章ルールは共通パッケージ `ROhta/apm-config/base` の pr-review ルールから配信。生成物は `.github/instructions/pr-review.instructions.md` / `.claude/rules/pr-review.md`
- 開発フロー (ブランチ〜マージ〜リリース) の高レベル順序は dev-workflow ルールを参照
