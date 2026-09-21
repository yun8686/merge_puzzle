part of 'party.dart';

// 押して使う力の中身。**増やすのはこのファイルだけ。**
//
// [Spell] を1つ継いで、[Spell.cast] に「[SpellStage] のどの動詞を呼ぶか」を
// 書く。名簿（roster.dart）で魔導士に持たせれば、それで終わり――進行
// （game_controller.dart）も画面（game_screen.dart）も触らない。
//
// [SpellStage] に無いことをしたくなったら、あちらに動詞を1つ足すこと。
// 進行の側に「この力ならこうする」という分岐を書くと、力が増えるたびに
// 進行が太っていく。

/// いまの盤面で、敵にいちばん深く届く道を1本だけ見せる。
///
/// **盤面を変えない。** 手数の制限が無くなってからは、値段を払うのは体力
/// だけなので、道を1本知ったところで1手ぶんの反撃は必ず払う。教えるのは
/// 「どこを通れば一番効くか」であって、無料の1手ではない。
final class Foresee extends Spell {
  const Foresee();

  @override
  String get label => '先読み';

  @override
  String describe() => 'いまの盤面で、敵にいちばん深く届く道を1本見せる';

  @override
  bool cast(SpellStage stage) => stage.revealBestRoute();
}
