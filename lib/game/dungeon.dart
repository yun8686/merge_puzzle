import 'board.dart';

/// ダンジョン1本ぶんの定義。階層を順に降りて、最後の階層を制圧すれば踏破。
///
/// 階層は**手で書く**。以前は階層番号から敵の数と守りを自動で決めていたが、
/// 決め打ちのダンジョンでは「B3F で初めて2回殴らされる」のような段取りを
/// 作れない。自動生成の側（[Board.buildStage] の `foeCount` 側）は消して
/// いないので、無限に潜る遊び方を足したくなったらそちらを使う。
///
/// ここは盤面の値（守り・体力）しか持たない。UI も一党も読まない。
class Dungeon {
  const Dungeon({required this.id, required this.name, required this.floors});

  /// 保存に使う識別子。表示名を変えても進捗が飛ばないよう、別に持つ。
  final String id;

  final String name;

  /// 1階層目から順に。
  final List<FloorSpec> floors;

  /// 階層の数。
  int get depth => floors.length;

  /// [floor] は1から数える。範囲外は端に丸める。
  FloorSpec floorAt(int floor) => floors[(floor - 1).clamp(0, depth - 1)];

  /// 最下層でいちばん守りの厚い敵。ダンジョンの顔として札に出す。
  int get bossWard {
    var ward = 0;
    for (final foe in floors.last.foes) {
      if (foe.ward > ward) ward = foe.ward;
    }
    return ward;
  }
}

/// 階層1つぶん。
class FloorSpec {
  const FloorSpec(this.foes);

  /// 置く敵。並びは置く順で、場所は毎回変わる。
  final List<FoeSpec> foes;

  /// この階層の敵の体力の合計。**この階層に何手かかるかの目安**で、
  /// 1手ごとに殴られる以上そのまま痛手の見積もりになる
  /// （`tools/sim/damage.py`）。
  int get totalFoeHp {
    var n = 0;
    for (final f in foes) {
      n += f.hp;
    }
    return n;
  }
}

/// 用意してあるダンジョン。並びがそのまま挑む順になる。
///
/// 増やすときはここに足すだけでよい。階層数は7に揃えているが、[Dungeon] は
/// `floors` の長さしか見ていないので、揃っていなくても動く。
class Dungeons {
  const Dungeons._();

  /// 忘れられた坑道。焔ひとりでも踏破できる想定の1本目。
  /// 守りは薄いところから始め、B3F で初めて体力2の敵に当たる。
  static const cavern = Dungeon(
    id: 'cavern',
    name: '忘れられた坑道',
    floors: [
      FloorSpec([FoeSpec(3)]),
      FloorSpec([FoeSpec(3), FoeSpec(4)]),
      FloorSpec([FoeSpec(4, hp: 2)]),
      FloorSpec([FoeSpec(5), FoeSpec(3), FoeSpec(3)]),
      FloorSpec([FoeSpec(5, hp: 2), FoeSpec(4)]),
      FloorSpec([FoeSpec(6), FoeSpec(5), FoeSpec(3)]),
      // 主。守り6・体力3は1本で討つのに威力8が要る。取り巻きが手数を食う。
      FloorSpec([FoeSpec(6, hp: 3), FoeSpec(3), FoeSpec(3)]),
    ],
  );

  /// 凍てついた回廊。体力の厚い敵を並べて、殴る回数＝ターンを要求する。
  /// 青の相が枯れると立て直せないので、氷雨や風のような後続が効く。
  static const corridor = Dungeon(
    id: 'corridor',
    name: '凍てついた回廊',
    floors: [
      FloorSpec([FoeSpec(4), FoeSpec(4)]),
      FloorSpec([FoeSpec(5, hp: 2)]),
      FloorSpec([FoeSpec(5, hp: 2), FoeSpec(5, hp: 2)]),
      FloorSpec([FoeSpec(6, hp: 2), FoeSpec(4, hp: 2)]),
      FloorSpec([FoeSpec(5, hp: 3), FoeSpec(3), FoeSpec(3)]),
      FloorSpec([FoeSpec(6, hp: 2), FoeSpec(6, hp: 2), FoeSpec(4)]),
      FloorSpec([FoeSpec(7, hp: 3), FoeSpec(5, hp: 2), FoeSpec(5, hp: 2)]),
    ],
  );

  /// 竜の巣。守りが厚く、1本の鎖に要る枚数が大きい。
  /// 威力を底上げする魔導士が揃っていないと、そもそも傷がつかない。
  static const lair = Dungeon(
    id: 'lair',
    name: '竜の巣',
    floors: [
      FloorSpec([FoeSpec(6), FoeSpec(6)]),
      FloorSpec([FoeSpec(7), FoeSpec(4), FoeSpec(4)]),
      FloorSpec([FoeSpec(7, hp: 2), FoeSpec(6)]),
      FloorSpec([FoeSpec(6, hp: 2), FoeSpec(6, hp: 2), FoeSpec(6, hp: 2)]),
      FloorSpec([FoeSpec(7, hp: 2), FoeSpec(7, hp: 2), FoeSpec(5)]),
      FloorSpec([FoeSpec(8), FoeSpec(7, hp: 2), FoeSpec(6)]),
      // 竜。守り8・体力3は1本で討つのに威力10が要る。
      FloorSpec([FoeSpec(8, hp: 3), FoeSpec(7, hp: 2), FoeSpec(7, hp: 2)]),
    ],
  );

  static const List<Dungeon> all = [cavern, corridor, lair];

  /// [id] のダンジョン。見つからなければ1本目。
  static Dungeon byId(String id) {
    for (final d in all) {
      if (d.id == id) return d;
    }
    return all.first;
  }

  /// [dungeon] の次の1本。最後なら null。
  static Dungeon? after(Dungeon dungeon) {
    final i = all.indexWhere((d) => d.id == dungeon.id);
    if (i < 0 || i + 1 >= all.length) return null;
    return all[i + 1];
  }
}
