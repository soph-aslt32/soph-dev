# PLUGINS

本ツールで作成されたディストリビューションでも，利用が推奨・可能とされるプラグインのドキュメントです．

## Superpowers

コーディングエージェントに「設計 → 計画 → TDD で実装 → レビュー」という規律ある開発フローを守らせる、スキル集＋開発方法論のプラグイン。いきなりコードを書かせず、ブレインストーミングと計画から始めさせるのが特徴。

### 基本情報

| 項目 | 内容 |
|---|---|
| 作者 | Jesse Vincent（obra）/ Prime Radiant |
| ライセンス | MIT |
| 種別 | Claude Code プラグイン（スキル集） |
| 公式ディレクトリ | 「Anthropic verified」表示あり。インストール数 約101万（2026年11月時点） |
| 対応エージェント | Claude Code のほか、Codex、Cursor、Gemini CLI、GitHub Copilot CLI、OpenCode など |

### 公式リンク

- GitHub: <https://github.com/obra/superpowers>
- Claude 公式プラグインページ: <https://claude.com/plugins/superpowers>
- 紹介記事（作者ブログ）: <https://blog.fsck.com/2025/10/09/superpowers/>
- Superpowers マーケットプレイス: <https://github.com/obra/superpowers-marketplace>
- Claude Code プラグインの導入方法（公式ドキュメント）: <https://code.claude.com/docs/en/plugins/install>

### インストール（Claude Code）

Claude Code のセッション内で実行する。

```bash
/plugin install superpowers@claude-plugins-official
```

Superpowers 独自のマーケットプレイスから入れる場合:

```bash
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

インストール時にスコープ（ユーザー / プロジェクト / ローカル）を選ぶ。公式マーケットプレイス経由なら自動更新が既定で有効。

### 開発フロー

スキルは状況に応じて自動で起動する。標準的な流れは次のとおり。

1. **brainstorming**: 対話で要件を明確にし、実装前に設計をまとめる
2. **using-git-worktrees**: 隔離された作業ブランチを作り、テストが通る状態を確認する
3. **writing-plans**: ファイルパス・コード・検証手順つきの小さなタスクに分解する
4. **subagent-driven-development / executing-plans**: タスクごとに新しいサブエージェントで実行する（または一括実行＋最終レビュー）
5. **test-driven-development**: red → green → refactor を強制する
6. **requesting-code-review**: タスクの合間に、計画と照らしてレビューする
7. **finishing-a-development-branch**: テストを確認し、マージ / PR / 保持 / 破棄を選んで後片付けする

ほかに `systematic-debugging`（修正前に根本原因を調査）、`verification-before-completion`（完了宣言前の検証）、`writing-skills`（独自スキルの作成）などを含む。

### 注意点

- 有効にしている間、毎セッション一定のトークンを常時消費する（約840トークン、2026年9月時点の計測）。
- Spec Kit などの仕様駆動開発ツールと、同じ変更に対して併用しない（手順の拠り所が二重になるため）。
