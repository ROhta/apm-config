---
description: ローカル開発時のフロー (実装完了から PR 作成、PR レビュー応答ループ) を superpowers 系スキルで定義
applyTo: "**"
---

# ローカル開発ワークフロー (AI エージェント向け)

このリポジトリでローカル開発を進める AI エージェントは、以下のワークフローに従う。

## 適用対象

本ワークフローは **superpowers 系スキルを用いるリポジトリ**向けの手順。**Spec Kit 採用リポジトリ**（`speckit-workflow` 指示が配信されている＝`ROhta/apm-config/speckit` に依存している）は、本ファイルではなく **speckit-workflow の開発フロー**に従い、以下の superpowers ベースの手順（存在確認・§2 のスキル駆動 PR 作成）は使わない。

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

レビュースレッド数が 100 を超える場合は、`reviewThreads` の `pageInfo { hasNextPage endCursor }` を見て `hasNextPage: true` の間 `after: $threadsCursor` を渡し、カーソル送りで全スレッドを取得する (下記は初回ページの取得例)。各スレッドの comments が 50 件を超える稀なケースは、そのスレッドを単位に別途ページングする — コメントのカーソルはスレッドごとに異なるため、全スレッド一括の単一 `commentsCursor` では正しく辿れない (下記の例では comments 側の cursor 変数は使わず、50 件超の検知だけ `comments.pageInfo.hasNextPage` で行う)。

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!, $threadsCursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100, after: $threadsCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id            # GraphQL Node ID — resolveReviewThread mutation の threadId に渡す
          isResolved
          comments(first: 50) {
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
