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
  String describe(Phase phase) => 'いまの盤面で、敵にいちばん深く届く道を1本見せる';

  @override
  bool cast(ActiveStage stage, Phase phase) => stage.revealBestRoute();
}

/// **次の1本だけ、自分の相だけで鎖を編めるようにする。**
///
/// 継ぎ方の決まりに、鎖ごとの3本目の選択肢が1本だけ生える――「2色の交互」
/// 「N 色の巡回」に並んで「自分の相だけ」が通る。混ぜれば元の決まりに戻る
/// ので、1本のあいだに緩むのは**その一択ぶん**。
///
/// **盤面でいちばん多い相を、1本にまとめて吐き出す力**として置いてある。
/// 満ちるマナは赤に寄せてあるので（`Board._weights`）、烈火の赤はたいてい
/// 盤面の過半を占めていて、そこを一続きに辿れば普段より大きく伸びる。
/// 烈火の受動（自分の相を5枚以上継いだ鎖は威力 +2）とも重なる。
///
/// **決まりそのものを緩めているので、永く効かせてはいけない。** 常時これが
/// 通ると敵マスを通る最長パスが跳ね上がり、希少な相のジレンマも雷の8枚条件も
/// 意味を失う（README 第8段階）。だから**1本だけ**で、潜り1本に1回だけ。
final class Spread extends Active {
  const Spread();

  @override
  String get name => '延焼';

  @override
  String describe(Phase phase) => '次の1本だけ、${phase.label}どうしを継げるようになる';

  @override
  bool cast(ActiveStage stage, Phase phase) => stage.spread(phase);
}
