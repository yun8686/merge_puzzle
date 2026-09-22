part of 'party.dart';

// アクティブスキルの中身。**増やすのはこのファイルだけ。**
//
// [Active] を1つ継いで、[Active.cast] に「[ActiveStage] のどの動詞を呼ぶか」を
// 書く。名簿（roster.dart）で魔導士に持たせれば、それで終わり――進行
// （game_controller.dart）も画面（game_screen.dart）も触らない。
//
// [ActiveStage] に無いことをしたくなったら、あちらに動詞を1つ足すこと。
// 進行の側に「この力ならこうする」という分岐を書くと、力が増えるたびに
// 進行が太っていく。

/// いまの盤面で、敵にいちばん深く届く道を1本だけ見せる。
///
/// **盤面を変えない。** 手数の制限が無くなってからは、値段を払うのは体力
/// だけなので、道を1本知ったところで1手ぶんの反撃は必ず払う。教えるのは
/// 「どこを通れば一番効くか」であって、無料の1手ではない。
final class Foresee extends Active {
  const Foresee();

  @override
  String get name => '先読み';

  @override
  String describe(Phase phase) => '敵にいちばん大きなダメージを与えられるルートを1本表示する';

  @override
  bool cast(ActiveStage stage, Phase phase) => stage.revealBestRoute();
}

/// **次の1本だけ、自分の相だけでチェインをつなげるようにする。**
///
/// **いまは盤面の振る舞いを変えない。** つなぐときに色を見なくなったので、
/// 同じ色どうしは元からつながる（README 第22段階）。立って下りる配線だけが
/// 残っていて、効き目は無い。**説明文も画面に出たままなので、ここを直すか
/// スキルを差し替えるかは決まりを入れ直すときに決める。**
///
/// 色の決まりがあった頃は「盤面でいちばん多い相を、1本にまとめて吐き出す
/// 力」だった。満ちるマナは人数の多い相に寄るので（`Board._weights`）、
/// 烈火の赤はたいてい盤面の過半を占めていて、そこを一続きに辿れば普段より
/// 大きく伸びる。烈火のパッシブ（自分の相を5枚以上つないだチェインは威力
/// +2）とも重なっていた。
final class Spread extends Active {
  const Spread();

  @override
  String get name => '延焼';

  @override
  String describe(Phase phase) => '次の1チェインだけ、${phase.label}どうしをつなげるようになる';

  @override
  bool cast(ActiveStage stage, Phase phase) => stage.spread(phase);
}
