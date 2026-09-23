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

  /// **手数の目安。** ★の3つ目（この手数以内でクリア）の線。
  ///
  /// 階層ごとに「敵の体力の合計＋1手」。体力1につき1本で削り、階層ごとに
  /// 1本だけ外してよい、という勘定。2体を1本でまとめて倒せば縮められるので、
  /// 届かない数字ではない。階層を書き換えれば目安も一緒に動く。
  int get par {
    var n = 0;
    for (final floor in floors) {
      n += floor.totalFoeHp + 1;
    }
    return n;
  }

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

  /// はじまりの洞窟。**遊び方を通した直後の2人（体力 90）で通るように組む。**
  /// 守りは3から、体力持ちは最後の階層に1体だけ。ここで詰まると、編成も
  /// ガチャも試す前に終わってしまう。
  static const hollow = Dungeon(
    id: 'hollow',
    name: 'はじまりの洞窟',
    floors: [
      FloorSpec([FoeSpec(3)]),
      FloorSpec([FoeSpec(3), FoeSpec(3)]),
      FloorSpec([FoeSpec(4)]),
      FloorSpec([FoeSpec(4), FoeSpec(3)]),
      // 主。守り4・体力2は、6枚つなげば1本で倒せる。
      FloorSpec([FoeSpec(4, hp: 2), FoeSpec(3)]),
    ],
  );

  /// 忘却の坑道。守り5と、道中の体力2が出てくる2本目。
  /// 始まりの2人でも通るが、ここから魔晶を貯めて3人目を考えはじめる。
  static const cavern = Dungeon(
    id: 'cavern',
    name: '忘却の坑道',
    floors: [
      FloorSpec([FoeSpec(3), FoeSpec(3)]),
      FloorSpec([FoeSpec(4), FoeSpec(3)]),
      FloorSpec([FoeSpec(4, hp: 2)]),
      FloorSpec([FoeSpec(5), FoeSpec(3), FoeSpec(3)]),
      FloorSpec([FoeSpec(5, hp: 2), FoeSpec(4)]),
      FloorSpec([FoeSpec(5, hp: 2), FoeSpec(4), FoeSpec(3)]),
    ],
  );

  /// 氷結の回廊。体力の厚い敵を並べて、殴る回数＝ターンを要求する。
  /// 守り6がここで初めて出る（攻撃力2の敵＝1手の値段が倍）。
  static const corridor = Dungeon(
    id: 'corridor',
    name: '氷結の回廊',
    floors: [
      FloorSpec([FoeSpec(4), FoeSpec(4)]),
      FloorSpec([FoeSpec(5), FoeSpec(4)]),
      FloorSpec([FoeSpec(5, hp: 2), FoeSpec(4)]),
      FloorSpec([FoeSpec(6), FoeSpec(4), FoeSpec(3)]),
      FloorSpec([FoeSpec(5, hp: 2), FoeSpec(5, hp: 2)]),
      FloorSpec([FoeSpec(6, hp: 2), FoeSpec(4)]),
      FloorSpec([FoeSpec(6, hp: 2), FoeSpec(5), FoeSpec(4)]),
    ],
  );

  /// 静寂の遺跡。体力2が当たり前になり、守り7が顔を出す。
  /// 始まりの2人（90）では届かない。3人目を入れるかどうかの分かれ目。
  static const ruins = Dungeon(
    id: 'ruins',
    name: '静寂の遺跡',
    floors: [
      FloorSpec([FoeSpec(5), FoeSpec(5)]),
      FloorSpec([FoeSpec(6), FoeSpec(4), FoeSpec(4)]),
      FloorSpec([FoeSpec(6, hp: 2), FoeSpec(5)]),
      FloorSpec([FoeSpec(5, hp: 2), FoeSpec(5, hp: 2), FoeSpec(4)]),
      FloorSpec([FoeSpec(7), FoeSpec(5, hp: 2)]),
      FloorSpec([FoeSpec(6, hp: 2), FoeSpec(6, hp: 2), FoeSpec(4)]),
      FloorSpec([FoeSpec(7, hp: 2), FoeSpec(5, hp: 2), FoeSpec(5)]),
    ],
  );

  /// 雷鳴の塔。体力3がここから出る。威力を底上げするスキルか、
  /// 受けを減らすスキル（盾・氷雨）が無いと手数のぶんだけ削られる。
  static const tower = Dungeon(
    id: 'tower',
    name: '雷鳴の塔',
    floors: [
      FloorSpec([FoeSpec(6), FoeSpec(5)]),
      FloorSpec([FoeSpec(6, hp: 2), FoeSpec(5), FoeSpec(5)]),
      FloorSpec([FoeSpec(7, hp: 2), FoeSpec(6)]),
      FloorSpec([FoeSpec(6, hp: 2), FoeSpec(6, hp: 2)]),
      FloorSpec([FoeSpec(7, hp: 2), FoeSpec(6, hp: 2), FoeSpec(5)]),
      FloorSpec([FoeSpec(7, hp: 2), FoeSpec(6), FoeSpec(5)]),
      // 主。体力3はここで初めて出る。
      FloorSpec([FoeSpec(7, hp: 3), FoeSpec(6, hp: 2), FoeSpec(6)]),
    ],
  );

  /// 竜の巣。守りが厚く、1本のチェインに要る枚数が大きい。
  /// 威力を底上げする魔導士が揃っていないと、そもそもダメージが通らない。
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
      // 竜。守り8・体力3は1本で倒すのに威力10が要る。
      FloorSpec([FoeSpec(8, hp: 3), FoeSpec(7, hp: 2), FoeSpec(7, hp: 2)]),
    ],
  );

  /// 挑む順。**前の1本をクリアすると次が解放される**ので、この並びが
  /// そのまま難易度の梯子になる。急な段差を作らないこと。
  static const List<Dungeon> all = [
    hollow,
    cavern,
    corridor,
    ruins,
    tower,
    lair,
  ];

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
