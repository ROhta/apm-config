---
description: Spec Kit 採用リポジトリの開発フロー（機能開発・PR 作成・レビュー応答）と Spec Kit × APM の連携運用
applyTo: "**"
---

# Spec Kit ワークフロー

## 機能開発は Spec Kit で進める

新機能や大きめの変更は **Spec Kit** のフローで進める (superpowers 系の実装フローとは別。どの superpowers スキルを使わず・どれは使ってよいかは後述「superpowers スキルとの使い分け」を参照)。

`speckit-constitution` (必要時) → `speckit-specify` → `speckit-plan` → `speckit-tasks` →
(任意 `speckit-taskstoissues`) → `speckit-implement`。

- 仕様・計画・タスクは `specs/<NNN-feature>/` に置かれる (パスは Spec Kit が管理。手で別所へ動かさない)。
- プロジェクト原則は `.specify/memory/constitution.md`。
- ドキュメント・設定・依存更新などの小さな雑務は、Spec Kit を通さずブランチ + PR で直接進めてよい。

## superpowers スキルとの使い分け

本リポジトリは base を併用する前提であり、superpowers スキルは **base 経由** で配布される（superpowers は base の依存。speckit パッケージ自身は依存に持たないため、`apm.yml` に重複記載しない）。Spec Kit 採用リポジトリでは superpowers を **全面禁止するのではなく、Spec Kit と競合する範囲だけ** を使わない。

- **使わない（Spec Kit と競合する前半のオーケストレーション）**: `brainstorming` / `writing-plans` / `executing-plans` など「アイデア→仕様→計画→実装」を駆動するスキル。この役割は Spec Kit の `speckit-specify` → `speckit-plan` → `speckit-tasks` → `speckit-implement` が担う。二重に走らせると成果物の置き場（`specs/` と `docs/superpowers/`）と CLAUDE.md / AGENTS.md を奪い合う。
- **使わない（PR 作成フロー）**: 実装完了後の PR 作成は、base の local-dev-workflow（superpowers 4 スキル駆動: `verification-before-completion` → `requesting-code-review` → `receiving-code-review` → `finishing-a-development-branch`）ではなく、本ファイルの「実装完了 → PR 作成」手順に従う。
- **使ってよい（Spec Kit がカバーしない直交スキル）**: `systematic-debugging`（バグ・テスト失敗・想定外挙動に直面したとき）や `test-driven-development`（実装フェーズでテストを先行させるとき）など、開発規律を補うスキル。Spec Kit の `speckit-implement` はこれらを規定しないため、Spec Kit フローの内側で併用してよい。

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

## ファイル管理（Spec Kit 固有）

base の apm-workflow「ファイルの管理方針」を基本としつつ、Spec Kit 採用リポジトリでは以下を **上書き** する。

- `.claude/skills/` は **混在** する。Spec Kit が管理するスキル（`speckit-*` 等）は **追跡する**（APM 生成物ではない）。一方 `apm install` が展開する APM スキル（superpowers 等）は生成物なので **追跡しない**（base の表が「追跡しない」として指すのはこちら）。両者が同じディレクトリに同居する点に注意。
- したがって `.gitignore` は `.claude/` を丸ごと無視せず、生成物 `.claude/rules/` を無視しつつ、`.claude/skills/` は Spec Kit スキルを残して APM 展開分のみ無視するよう調整する。
- `spec-context.instructions.md`: 追跡する（動的だがローカル保持。上記「spec-context.instructions.md の扱い」参照）。
- `CLAUDE.md` / `AGENTS.md`: `apm compile` が生成する生成物（追跡しない。`CLAUDE.md` は constitution 込み `--with-constitution`）。

## ブランチとコミット

- **`main` に直接コミットしない**。作業ごとにブランチを切る (例: `chore/...`、`NNN-feature-...`)。
- コミットメッセージは Conventional Commits 形式 (`<type>(<scope>): <説明>`)、本文は日本語。
- コミット末尾のトレーラ (`Co-Authored-By:` / `Claude-Session:`) は環境が自動付与する場合がある。リポジトリの方針に従い、付与しない運用なら手で削除する。

## 実装完了 → PR 作成

実装が完了したと判断したら、順に実行する。**前ステップが完了するまで次に進まない**（PR 作成は base の superpowers 駆動フローではなく本手順に従う。実装中のデバッグ・テスト先行に superpowers の直交スキルを使うことは妨げない。「superpowers スキルとの使い分け」参照）。

1. **品質ゲートを完遂する**: typecheck / lint / format / test / build 等。具体的なコマンドは各リポジトリの setup 系 instructions に従う。失敗したら根本原因を解決してから次へ。
2. ブランチを push し、PR を作成する。
   - PR 本文は `.github/PULL_REQUEST_TEMPLATE.md` が存在すればその項目を埋める。
   - チェックボックスはコミット前に検証済みの項目のみ `[x]`、Preview デプロイ待ちなど未確認のものは `[ ]` のまま残す。
   - PR タイトルは Conventional Commits 形式で、本文と同じく日本語で書く。
   - PR の assignee に、現在の `gh` CLI 認証ユーザーを設定する (`gh pr create --assignee @me`、または作成後に `gh pr edit <pr> --add-assignee @me`)。

## PR レビュー応答ループ (PR 作成 / push 毎)

PR 作成・push 後の自走レビュー応答ループ（検知 → 妥当性判断 → 対応 → resolve まで繰り返し）は **review-response-loop ルール**に従う。このループは Spec Kit 採用の有無に依存しない共通手順として base から配信される（`.github/instructions/review-response-loop.instructions.md` / `.claude/rules/review-response-loop.md`）。

## 関連ルール

- PR 作成・push 後の自走レビュー応答ループは review-response-loop ルールを参照
- レビュー応答の文章ルール: 共通パッケージ `ROhta/apm-config/base` の pr-review ルールから配信。生成物は `.github/instructions/pr-review.instructions.md` / `.claude/rules/pr-review.md`。
- 環境構築・コマンドは各リポジトリの setup 系 instructions を参照。
