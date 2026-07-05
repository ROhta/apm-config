---
description: Spec Kit 採用リポジトリの開発フロー（機能開発・PR 作成・レビュー応答）と Spec Kit × APM の連携運用
applyTo: "**"
---

# Spec Kit ワークフロー

## 機能開発は Spec Kit で進める

新機能や大きめの変更は **Spec Kit** のフローで進める (superpowers 系の実装フローとは別)。

`speckit-constitution` (必要時) → `speckit-specify` → `speckit-plan` → `speckit-tasks` →
(任意 `speckit-taskstoissues`) → `speckit-implement`。

- 仕様・計画・タスクは `specs/<NNN-feature>/` に置かれる (パスは Spec Kit が管理。手で別所へ動かさない)。
- プロジェクト原則は `.specify/memory/constitution.md`。
- ドキュメント・設定・依存更新などの小さな雑務は、Spec Kit を通さずブランチ + PR で直接進めてよい。

## Spec Kit × APM の連携

Spec Kit と APM はどちらも CLAUDE.md / AGENTS.md を生成しようとするため、素朴に併用すると
生成物を奪い合う。これを避けるため、Spec Kit の動的なプランポインタは APM の instructions
経由で畳み込む。

- `agent-context-config.yml` の `context_file` を `.apm/instructions/spec-context.instructions.md`
  に向ける。Spec Kit の `speckit.agent-context.update` (after_specify / after_plan hook) が
  このファイルを自動更新する。
- `apm compile` が `spec-context.instructions.md` を含む `.apm/instructions/` を CLAUDE.md /
  AGENTS.md / `.github/instructions` に畳み込む。**speckit の specify / plan を実行したら
  `apm compile` を 1 回回して反映する。**
- `apm compile` は既定で Spec Kit の constitution ブロックを取り込む (`--with-constitution`)。

## spec-context.instructions.md の扱い（重要）

`spec-context.instructions.md` は Spec Kit hook が自動更新する **動的・リポジトリ固有の
プランポインタ** (現在の `plan.md` を指す) であり、内容がリポジトリ・機能ごとに異なる。
そのため本 speckit パッケージの **配信物には含めない**。各リポジトリがローカルに保持し
(Spec Kit hook が生成・更新する)、`.apm/instructions/` の追跡対象として管理する。
マーカー間は hook が自動更新するので手で編集しない。

## ブランチとコミット

- **`main` に直接コミットしない**。作業ごとにブランチを切る (例: `chore/...`、`NNN-feature-...`)。
- コミットメッセージは Conventional Commits 形式 (`<type>(<scope>): <説明>`)、本文は日本語。
- コミット末尾のトレーラ (`Co-Authored-By:` / `Claude-Session:`) は環境が自動付与する場合がある。リポジトリの方針に従い、付与しない運用なら手で削除する。

## 実装完了 → PR 作成

実装が完了したと判断したら、順に実行する。**前ステップが完了するまで次に進まない**（superpowers 系スキルは使わない）。

1. **品質ゲートを完遂する**: typecheck / lint / format / test / build 等。具体的なコマンドは各リポジトリの setup 系 instructions に従う。失敗したら根本原因を解決してから次へ。
2. ブランチを push し、PR を作成する。
   - PR 本文は `.github/PULL_REQUEST_TEMPLATE.md` が存在すればその項目を埋める。
   - チェックボックスはコミット前に検証済みの項目のみ `[x]`、Preview デプロイ待ちなど未確認のものは `[ ]` のまま残す。
   - PR タイトルは Conventional Commits 形式で、本文と同じく日本語で書く。
   - PR の assignee に、現在の `gh` CLI 認証ユーザーを設定する (`gh pr create --assignee @me`、または作成後に `gh pr edit <pr> --add-assignee @me`)。

## PR レビュー応答ループ (PR 作成 / push 毎)

PR を新規作成、または既存ブランチに push した後、**ユーザーからの合図を待たずに** 自走でレビュースレッドの有無を確認し、指摘があれば対応する。**すべてのスレッドが resolve されるまでループを継続する。** owner / repo は `gh repo view --json nameWithOwner --jq .nameWithOwner` で動的に解決する。

### 起動

`gh pr create` または `git push` の成功直後に本フローを開始する (ユーザー入力を待たない)。

- **即時 1 回**: push 完了から約 2 分 (120 秒) 待機 (Copilot Review の初回反応待ち) し、下記の検知を 1 回実行する。
- **追跡 (Claude Code)**: 指摘は遅延することがあるため、`ScheduleWakeup` でさらに 2 分後にもう 1 回フォローする。即時 + 追跡で **連続 2 回** 新規指摘がなければ追跡を終了する。
- **ユーザー復帰時フォールバック**: 次にユーザー入力を受け取ったとき、その入力が PR と無関係に見えても、まず自分の未マージ PR の未 resolve スレッドを 1 回確認する。あれば「PR #<番号> に未対応のレビュースレッドがあります。先に応答しますか？」と確認し、了承されたら先に処理する。

### 検知

`gh api graphql` で未 resolve なレビュースレッドを列挙する (`gh pr view --json reviews` は `isResolved` を返さないので使わない)。

```bash
gh api graphql -f query='
query($owner:String!,$repo:String!,$pr:Int!){
  repository(owner:$owner,name:$repo){ pullRequest(number:$pr){
    reviewThreads(first:100){ nodes{
      id            # resolveReviewThread の threadId に渡す Node ID
      isResolved
      comments(first:50){ nodes{
        databaseId  # REST の comment_id（返信先）に渡す数値 ID
        author{login} body path line
      } }
    } } } }
}' -F owner=<owner> -F repo=<repo> -F pr=<番号>
```

対象は `isResolved: false` かつ先頭コメント (`comments.nodes[0]`) の `author.login` が bot (例: `copilot-pull-request-reviewer`) のスレッドのみ。

### 対応

各指摘を「妥当（反映すべき）」「不当（誤読・二重指摘等）」に分類する。

- **妥当**: コードを修正 → コミット → 該当インラインコメントに日本語で返信 (対応コミットの SHA を**前後に半角空白を入れて**記載) → スレッドを resolve。

  ```bash
  gh api repos/<owner>/<repo>/pulls/<pr>/comments/<databaseId>/replies -f body='対応しました abc1234 '
  gh api graphql -f query='mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ isResolved } } }' -F id=<thread_node_id>
  ```

  `<databaseId>` は数値 ID（GraphQL Node ID `PRRC_...` は REST で受け付けられない）。
- **不当**: コードは変更せず、理由を日本語で具体的に記載してスレッドを resolve。

全スレッドを resolve するまで繰り返し、次の `git push` で再度検知から実行する。

## 関連ルール

- レビュー応答の文章ルール: 共通パッケージ `ROhta/apm-config/base` の pr-review ルールから配信。生成物は `.github/instructions/pr-review.instructions.md` / `.claude/rules/pr-review.md`。
- 環境構築・コマンドは各リポジトリの setup 系 instructions を参照。
