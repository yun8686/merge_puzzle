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

## 見た目の確認は利用者がやる

**ブラウザでの動作確認はこちらでやらない。** push したら CI の完了（成否）だけ報告して、
そこで手を止めること。公開ページを開いて見た目や演出を確かめるのは利用者の側。
1手ずつ自動で打って階層を進めるような確認は、1手 20 秒かかって時間を食うわりに、
結局は人が見ないと良し悪しが決まらない。

頼まれたときだけ開く。そのときのために、分かっていることを残しておく。

- 実行環境のネットワークポリシーが `yun8686.github.io` を遮断していることがある
  （CONNECT に 403）。その場合は回避策を探さず、確認できない旨を報告すること。
- 通っていても Playwright の Chromium はプロキシの CA を読まないので、公開ページに
  直接は繋がらない（`ERR_CERT_AUTHORITY_INVALID`）。`curl` でビルド成果物を手元に
  落として `http-server` で配ると、TLS を切らずに開ける。アセットは `assets/` の下に
  もう一段 `assets/` が付く（`assets/assets/fonts/...`）。
- `flutter_service_worker.js` は「更新あり」でページを勝手に再読み込みして進行を
  巻き戻すので、確認中は握り潰すこと。日本語は CanvasKit が gstatic から取りに行くので、
  遮断されている環境では手元の IPA ゴシックを返してやる。
- CanvasKit 描画なので `page.screenshot()` は1枚2秒以上かかり、数百 ms の演出には
  間に合わない。Playwright の `recordVideo` で録画して、ffmpeg でフレームを抜くこと。

## ビルドできないときの見た目の詰め方

作業コンテナに Flutter SDK が無いと、変更した見た目を手元で描けない。push して公開を
待つと1往復 5 分かかるので、当てずっぽうで push しない。

盤面のマスのような小さな絵は、**ブラウザの canvas に同じものを描いたモックを作って
実寸で見比べる**のが速い。配色は `theme.dart`、敵の形は `tools/foe/shapes.py` を
JSON に落とせばそのまま読める。案を並べて落とした理由まで見えるので、README に残す
材料にもなる。
