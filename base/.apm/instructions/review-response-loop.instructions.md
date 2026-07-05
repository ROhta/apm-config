---
description: PR 作成・push 後に自走でレビュースレッドを検知し resolve まで応答し続けるループ（superpowers / Spec Kit の採用に依存しない共通手順）
applyTo: "**"
---

# PR レビュー応答ループ (AI エージェント向け)

PR を新規作成、または既存ブランチに push した後、**ユーザーからの合図を待たずに** 自走でレビュースレッドの有無を確認し、指摘があれば対応する。**すべてのスレッドが resolve されるまでループを継続する。**

このループは superpowers の有無や Spec Kit 採用の有無に依存しない共通手順。local-dev-workflow（superpowers 系）でも speckit-workflow（Spec Kit 系）でも、PR 作成・push 後はこのルールに従う。

owner / repo は最初に一度だけ動的解決し、以降のコマンドで参照する。GraphQL / REST は `owner` と `repo` を別引数で受け取るため、`nameWithOwner`（`owner/repo` の結合文字列）ではなく別々に解決する。

```bash
OWNER=$(gh repo view --json owner --jq .owner.login)
REPO=$(gh repo view --json name --jq .name)
```

## 1. 起動

`gh pr create` または `git push` の成功直後に本フローを開始する (ユーザー入力を待たない)。

- **即時 1 回**: push 完了から約 2 分 (120 秒) 待機 (Copilot Review の初回反応待ち) し、§2 の検知を 1 回実行する。
- **追跡**: 指摘は遅延することがあるため、さらに約 2 分後にもう 1 回フォローする。即時 + 追跡で **連続 2 回** 新規指摘がなければ追跡を終了する。
  - **Claude Code**: `ScheduleWakeup` で予約する。

    ```text
    ScheduleWakeup({ delaySeconds: 120,
      prompt: "PR #<番号> の Copilot Review 応答ループを再開する。review-response-loop ルールに従い、未 resolve スレッドを検知して処理せよ。",
      reason: "Copilot Review 遅延応答の追跡チェック (push から 2 分後)" })
    ```

  - **それ以外の環境 (Codex CLI / GitHub Copilot 等)**: 手動で約 2 分後に §2 の検知を再実行する。
- **ユーザー復帰時フォールバック**: 次にユーザー入力を受け取ったとき、その入力が PR と無関係に見えても、まず自分の未マージ PR の未 resolve スレッドを 1 回確認する。あれば「PR #<番号> に未対応のレビュースレッドがあります。先に応答しますか？」と確認し、了承されたら §2〜§3 を先に実行する。

## 2. 検知

`gh api graphql` で未 resolve なレビュースレッドを列挙する (`gh pr view --json reviews,comments` は thread の `isResolved` を返さないので使わない)。

レビュースレッド数が 100 を超える場合は、`reviewThreads` の `pageInfo { hasNextPage endCursor }` を見て `hasNextPage: true` の間 `after: $threadsCursor` を渡し、カーソル送りで全スレッドを取得する (下記は初回ページの取得例)。各スレッドの comments が 50 件を超える稀なケースは、そのスレッドを単位に別途ページングする — コメントのカーソルはスレッドごとに異なるため、全スレッド一括の単一カーソルでは正しく辿れない (下記の例では comments 側の cursor 変数は使わず、50 件超の検知だけ `comments.pageInfo.hasNextPage` で行う)。

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
}' -F owner="$OWNER" -F repo="$REPO" -F pr=<number>
```

対象は `isResolved: false` かつ先頭コメント (`comments.nodes[0]`) の author が bot (例: `copilot-pull-request-reviewer`) のスレッドのみとする。

## 3. 妥当性判断と対応

各指摘を次のいずれかに分類する。

- **妥当**: 反映すべき具体的かつ正当な指摘
- **不当**: 文脈を踏まえると採用すべきでない、誤読、二重指摘 等

### 妥当な指摘

1. 指摘に従ってコードを修正する
2. 修正をコミットする
3. 該当インラインコメントに返信する。本文に対応コミットの SHA を **前後に半角空白を入れて** 記載し、GitHub UI でコミットへのリンクとして描画させる。

   ```bash
   gh api repos/"$OWNER"/"$REPO"/pulls/<pr>/comments/<comment_database_id>/replies \
     -f body='対応しました abc1234 '
   ```

   - `<comment_database_id>` は §2 の `databaseId` フィールド (**数値 ID**) を指す。GraphQL Node ID (`PRRC_...`) は REST API では受け付けられない点に注意。
   - 本文は日本語で記述 (pr-review ルール参照)
4. スレッドを resolve する。

   ```bash
   gh api graphql -f query='
   mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { isResolved } } }
   ' -F id=<thread_node_id>
   ```

### 不当と判断した場合

1. コードは変更しない
2. インラインコメントで「不当と判断した理由」を日本語で具体的に記載する
3. スレッドを resolve する (上記 mutation 参照)

## 4. 繰り返し

- 全スレッドを resolve するまで §2〜§3 をループする
- 次の `git push` が発生したら、再度 §2 から実行する

## 関連ルール

- レビュー応答の文章ルールは共通パッケージ `ROhta/apm-config/base` の pr-review ルールから配信。生成物は `.github/instructions/pr-review.instructions.md` / `.claude/rules/pr-review.md`
