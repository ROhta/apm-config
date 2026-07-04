---
description: Spec Kit による機能開発フローと Spec Kit × APM の連携運用
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
