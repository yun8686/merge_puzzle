# CLAUDE.md

Claude Code がこのリポジトリで作業するときの約束事。ゲームのルールと設計判断の経緯は
`README.md` にあるので、そちらを読むこと。ここには書かない。

## 作業フロー

**`main` で直接作業して `main` に push する。** ブランチを切らない。PR も作らない
（明示的に頼まれたときだけ作る）。

```
git checkout main && git pull origin main
# 変更
git commit
git push -u origin main
```

セッションのコンテナは毎回作り直され、HEAD が detached な状態で始まることがある。
その場合は作業前に `git checkout main` すること。

## push は即デプロイ

`.github/workflows/deploy-pages.yml` が push のたびに走り、**デフォルトブランチのときだけ**
GitHub Pages に公開する。公開先は https://yun8686.github.io/merge_puzzle/ 。

CI は `flutter analyze` → `flutter test` → `flutter build web` の順で、どれかが落ちると
公開されない。`main` に直接 push する運用なので、**壊れたコミットはそのまま公開ページを
止める**。push 前に手元で確認すること。

ただし作業コンテナに Flutter SDK が入っていないことがある。その場合 `flutter analyze` も
`flutter test` も手元では実行できない。無理にセットアップせず、変更の影響範囲を自分で
読み切ったうえで push し、CI の結果で確認する。

## 構成

| パス | 中身 |
|---|---|
| `lib/game/board.dart` | 盤面とチェイン判定。UI に依存しない |
| `lib/game/game_controller.dart` | 進行、スコア、なぞり中の経路の状態 |
| `lib/game/party.dart` | 一党。階層をまたぐ体力と魔導士。盤面を読まない |
| `lib/ui/board_view.dart` | 盤面の描画と、消える演出のタイミング |
| `lib/ui/game_screen.dart` | 画面全体。SCORE / TURNS / FOES / 偶奇バー / 一党 / 決着画面 |
| `lib/ui/foe_art.dart` | 敵の姿。**生成物**。`tools/foe/` から作るので手で直さない |
| `lib/ui/particles.dart`, `lib/ui/theme.dart` | エフェクトと配色 |
| `tools/foe/` | 敵の姿の定義とプレビュー。Python（Pillow）。詳細は `tools/foe/README.md` |
| `test/` | `board_test.dart` / `game_controller_test.dart` / `board_view_test.dart` |

`party.dart` は `board.dart` を import しない。魔導士は鎖の戦果（枚数と熱冷の内訳）
だけを見る。ここを繋ぐと、README に書いてある検証済みの数値が意味を失う。

## 消える演出のテンポ

何度も調整している箇所なので、触る前に現状を把握すること。`lib/ui/board_view.dart` の
`_staggerFor`（なぞった順に1枚ずつ弾ける間隔）と `_settleTail`（最後の1枚が弾けてから
盤面が詰まるまで）が全体の尺を決めている。

指を離してから盤面が詰まるまでは `stagger * (枚数 - 1) + _settleTail`。`_staggerFor` の
基準値と clamp の上下限は同じ倍率で動かすこと。片方だけ変えると、clamp に当たる短い
チェインと長いチェインで比率が崩れる。

線が焼き切れる速さ（`_ChainFlashView`）は `stagger` から算出しているので自動で追従するが、
焼き切ったあとの残り香の長さだけは固定値なので、尺を変えるときは一緒に見ること。

## 演出の確認

実機確認はブラウザで公開ページを開くしかないが、**実行環境のネットワークポリシーが
`yun8686.github.io` を遮断していることがある**（CONNECT に 403）。その場合は回避策を
探さず、確認できない旨を報告すること。

確認できる場合、CanvasKit 描画なので `page.screenshot()` は1枚2秒以上かかり、数百 ms の
演出には間に合わない。Playwright の `recordVideo` で録画して、ffmpeg でフレームを抜くこと。
