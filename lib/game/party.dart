/// 盤面の上に乗る「一党」。階層をまたいで持ち越す唯一の状態で、
/// ここだけがステージを越えて残る。
///
/// 魔導士は盤面に置かない。編んだ鎖の戦果（[ChainTally]）だけを見て反応する。
/// 盤面ロジックに触らないので、検証済みのパズルの数値はそのまま生きている。
library;

import 'phase.dart';

/// 鎖1本の戦果。魔導士が見るのはこれだけ。
class ChainTally {
  const ChainTally({
    required this.length,
    required this.counts,
    required this.startPhase,
  });

  /// 継いだ枚数。
  final int length;

  /// 相ごとの枚数。
  final Map<Phase, int> counts;

  /// 継ぎ始めた相。空の鎖なら null。
  ///
  /// 決まりのせいで、長さが同じでも開始相だけで各相の枚数が1枚ずれる。
  /// **開始相そのものを条件にする魔導士**が居るので、枚数とは別に持つ。
  final Phase? startPhase;

  int countOf(Phase phase) => counts[phase] ?? 0;

  /// 鎖が1本も無い状態。鎖を見ない能力（[Always]）を数えるときに渡す。
  static const none = ChainTally(
    length: 0,
    counts: <Phase, int>{},
    startPhase: null,
  );
}

/// 能力が応える条件。**見るのは鎖の戦果と、その魔導士自身の相だけ。**
///
/// 盤面も一党も見ないので、条件を1つ足しても他に波及しない。魔導士を
/// 増やすときは、ここにある条件と [Boon] を組み合わせるだけで済む。
sealed class Trigger {
  const Trigger();

  bool met(Phase phase, ChainTally tally);

  /// 「〜な」まで。[Ability.describe] が「鎖」を足して1文にする。
  /// 条件を重ねたとき（[Every]）に前から順に繋がるよう、ここでは
  /// 「鎖」を書かない。
  String describe(Phase phase);
}

/// 自分の相を [need] 枚以上継いだ鎖。
final class SamePhase extends Trigger {
  const SamePhase(this.need);

  final int need;

  @override
  bool met(Phase phase, ChainTally tally) => tally.countOf(phase) >= need;

  @override
  String describe(Phase phase) => '${phase.label}を$need枚以上継いだ';
}

/// [need] 枚以上継いだ鎖。相は問わない。
final class ChainLength extends Trigger {
  const ChainLength(this.need);

  final int need;

  @override
  bool met(Phase phase, ChainTally tally) => tally.length >= need;

  @override
  String describe(Phase phase) => '$need枚以上継いだ';
}

/// 自分の相から継ぎ始めた鎖。枚数を寄せる編み方とは噛み合わない。
final class StartsWith extends Trigger {
  const StartsWith();

  @override
  bool met(Phase phase, ChainTally tally) => tally.startPhase == phase;

  @override
  String describe(Phase phase) => '${phase.label}から継ぎ始めた';
}

/// [need] 種類以上の相を含む鎖。
///
/// 継ぎ方の決まり（N 枚ぶんの窓に同じ相は二度出ない）のせいで、これは
/// **盤面が何色か**とほぼ同じ意味になる。3色の盤面では長さ3以上の鎖は
/// 必ず3色を含み、2色の盤面ではどう編んでも3色にはならない。つまり
/// `DistinctPhases(3)` は「3色で編成したときだけ効く」と読める。
final class DistinctPhases extends Trigger {
  const DistinctPhases(this.need);

  final int need;

  @override
  bool met(Phase phase, ChainTally tally) =>
      tally.counts.values.where((n) => n > 0).length >= need;

  @override
  String describe(Phase phase) => '$need色を含む';
}

/// 並べた条件を全部満たした鎖。説明文は前から順に繋げる。
final class Every extends Trigger {
  const Every(this.all);

  final List<Trigger> all;

  @override
  bool met(Phase phase, ChainTally tally) =>
      all.every((t) => t.met(phase, tally));

  @override
  String describe(Phase phase) => all.map((t) => t.describe(phase)).join();
}

/// 鎖を見ない。連れているだけで効く。
final class Always extends Trigger {
  const Always();

  @override
  bool met(Phase phase, ChainTally tally) => true;

  @override
  String describe(Phase phase) => '';
}

/// 条件が満たされたときの効き目。
///
/// **種類がそのまま集計先になる。** [Party] は「[PowerUp] を全部足す」
/// としか書いていないので、[PowerUp] を持つ魔導士が何人増えても
/// [Party.powerBonusFor] は変わらない。
sealed class Boon {
  const Boon();

  /// 説明文の後半。[Trigger.describe] の続きとして読める形にする。
  String describe();
}

/// 鎖の威力に足す。
final class PowerUp extends Boon {
  const PowerUp(this.amount);

  final int amount;

  @override
  String describe() => 'は威力 +$amount';
}

/// その手の反撃を受けない。
///
/// 手数の制限があった頃は「使った手を返す」だった（`TurnBack`）。手数を
/// やめて**1手の値段が体力になった**ので、同じ意味を体力で書き直してある。
/// 手が1つ戻るということは、**その手のぶんの痛手を払わずに済む**ということ。
final class Evade extends Boon {
  const Evade();

  @override
  String describe() => 'を編んだ手は反撃を受けない';
}

/// 一党の体力を戻す。
final class Mend extends Boon {
  const Mend(this.amount);

  final int amount;

  @override
  String describe() => 'で体力を $amount 戻す';
}

/// 階層に残っている敵すべてを打つ。
final class Strike extends Boon {
  const Strike(this.amount);

  final int amount;

  @override
  String describe() => 'は階層の敵すべてに $amount ダメージ';
}

/// 受ける痛手を半分にする（切り上げ）。重ねれば重ねただけ半分になっていく。
///
/// 敵が毎ターン殴ってくるようになってから、痛手の大半はそちらで積み上がる。
/// 階層を落としたときの反撃だけに効かせると、盾がほとんど死に札になる。
final class Guard extends Boon {
  const Guard();

  @override
  String describe() => '受ける痛手が半分になる';
}

/// 能力ひとつ。**条件と効き目の組でしか書けない。**
///
/// 説明文は組から作る。手で書いた文と数値がずれることが無い。
class Ability {
  const Ability(this.when, this.then);

  final Trigger when;
  final Boon then;

  bool firesOn(Phase phase, ChainTally tally) => when.met(phase, tally);

  /// 「〜な鎖は威力 +1」のように、条件と効き目を繋いだ1文。
  /// [Always] のように鎖を見ない条件は空文字を返すので、「鎖」も付けない。
  String describe(Phase phase) {
    final clause = when.describe(phase);
    final boon = then.describe();
    return clause.isEmpty ? boon : '$clause鎖$boon';
  }
}

enum MageKind {
  /// 相を1つ持つだけの従者。特殊な力は無い。始まりの3人。
  squireRed,
  squireBlue,
  squireViolet,
  ember,
  rime,
  storm,
  frost,
  gale,
  aegis,
  blaze,
}

/// 一党に加わる魔導士。能力は「鎖の戦果への反応」として書く。
///
/// 赤や青の枚数を条件にすると、交互ルールのせいで実質「長さ＋どちらの相から
/// 始めたか」になる。長さ N の鎖に含まれる赤は、赤から始めれば ⌈N/2⌉、
/// 青から始めれば ⌊N/2⌋。つまり**開始する相の選択**に初めて意味が生まれる。
/// これまで開始相は繋がりやすさ以外どうでもよかったので、ここが新しい判断になる。
class Mage {
  const Mage._(this.kind, this.phase, this.name, this.hp, [this.ability]);

  final MageKind kind;

  /// この魔導士の相。**編成に入れた相だけが盤面に敷かれる。**
  /// 能力が「自分の相を N 枚以上」という形なのは、連れていく顔ぶれと
  /// 盤面の色がひと続きになるようにするため。
  final Phase phase;

  final String name;

  /// この魔導士の体力。**一党の体力は連れていく面々の合計**（[Party.poolFor]）。
  ///
  /// **強い力を持つ者ほど薄い。** 能力を持たない従者がいちばん厚く、盤面を
  /// ひっくり返す力（威力+2、階層の敵すべてに一撃）を持つ者は薄い。連れて
  /// いく顔ぶれが、そのまま「何手ぶん耐えられるか」になる。
  final int hp;

  /// この魔導士の能力。持たない者は null。
  ///
  /// **[Party] は能力の中身で分岐しない。** ここに [Ability] を1つ置けば、
  /// 集計は [Boon] の種類だけで回る。魔導士を増やすときに触るのは、この
  /// 名簿と [MageKind] だけ。
  final Ability? ability;

  /// 能力の説明。画面にそのまま出す。能力から作るので、数値とずれない。
  String get effect => ability?.describe(phase) ?? '特殊な力は持たない';

  /// 従者の体力。**名簿でいちばん厚い。** 特殊な力が無いぶんここで返す。
  /// 始まりの2人で 90 あり、1本目のダンジョンはこれで通る。
  static const int squireHp = 45;

  /// 始まりの3人。相を1つ持つだけで、特殊な力は無い。
  /// 3人とも別の相なので、開幕から盤面は3色になる。
  static const squireRed = Mage._(
    MageKind.squireRed,
    Phase.red,
    '赤の従者',
    squireHp,
  );
  static const squireBlue = Mage._(
    MageKind.squireBlue,
    Phase.blue,
    '青の従者',
    squireHp,
  );
  static const squireViolet = Mage._(
    MageKind.squireViolet,
    Phase.violet,
    '紫の従者',
    squireHp,
  );

  static const ember = Mage._(
    MageKind.ember,
    Phase.red,
    '焔の魔導士',
    40,
    Ability(SamePhase(emberSame), PowerUp(1)),
  );
  static const blaze = Mage._(
    MageKind.blaze,
    Phase.red,
    '烈火の魔導士',
    30,
    Ability(SamePhase(blazeSame), PowerUp(2)),
  );
  static const gale = Mage._(
    MageKind.gale,
    Phase.red,
    '風の魔導士',
    35,
    Ability(ChainLength(galeChain), Evade()),
  );
  static const rime = Mage._(
    MageKind.rime,
    Phase.blue,
    '氷雨の魔導士',
    45,
    Ability(SamePhase(rimeSame), Mend(rimeMend)),
  );
  static const frost = Mage._(
    MageKind.frost,
    Phase.blue,
    '霜の魔導士',
    40,
    Ability(StartsWith(), PowerUp(1)),
  );
  static const storm = Mage._(
    MageKind.storm,
    Phase.violet,
    '雷の魔導士',
    30,
    Ability(
      Every([DistinctPhases(stormPhases), ChainLength(stormChain)]),
      Strike(1),
    ),
  );
  static const aegis = Mage._(
    MageKind.aegis,
    Phase.violet,
    '盾の魔導士',
    40,
    Ability(Always(), Guard()),
  );

  /// 始まりの3人。ガチャの対象にはならない。
  static const List<Mage> squires = [squireRed, squireBlue, squireViolet];

  /// ガチャで増える7人。
  static const List<Mage> summonable = [
    ember,
    blaze,
    gale,
    rime,
    frost,
    storm,
    aegis,
  ];

  /// 名簿。従者が先、招ける魔導士が後。
  static const List<Mage> roster = [...squires, ...summonable];

  /// [kind] の魔導士。名簿に無い種類は無いので、必ず見つかる。
  static Mage of(MageKind kind) => roster.firstWhere((m) => m.kind == kind);
}

/// 焔が応える、**自分の相**の枚数。
const int emberSame = 3;

/// 氷雨が応える、自分の相の枚数。
const int rimeSame = 3;

/// 氷雨が1本の鎖で戻す体力。
///
/// 毎ターンの反撃が 2〜6 なので、条件を満たした手では半分ほど打ち消す。
/// 全部打ち消すと敵を放置して延々と編めてしまい、討ち急ぐ理由が消える。
const int rimeMend = 3;

/// 烈火が応える、自分の相の枚数。焔の上に重ねて乗る。
const int blazeSame = 5;

/// 風が反撃を凌ぐ枚数。ここを下げると、長い鎖を編めるうちは一度も殴られ
/// なくなって、**早く討つ理由が消える**。少ない側の相を食い潰す長さに
/// 置いてあるのは、枯渇そのものが歯止めになるため。7枚を毎手続けることは
/// できない。
const int galeChain = 7;

/// 雷が落ちる枚数。ここだけ威力ではなく**継いだ枚数**で見る。
///
/// 焔の補正が乗ると 7 枚でも威力 8 になるが、それでは落とさない。
/// 「8枚つなぐ」は盤面を見ながら数えられるのに対し、「威力 8」は補正が
/// 乗るかどうかを頭の中で足さないと分からず、狙って出せない。
const int stormChain = 8;

/// 雷が要る相の数。**3色で編成したときにしか落ちない。**
///
/// 3色の盤面は継ぎ先が薄くなるぶん鎖が短くなる（最長の中央値 9・8枚以上
/// 77%。2色なら 11・89%。README 第7段階）。それまで3色にする理由がどこにも
/// 無かったので、いちばん派手な能力をここに結んだ。雷は「3色にしてでも
/// 8枚編む」ための報酬で、2色の編成に入れても一度も落ちない。
const int stormPhases = 3;

/// 一党。階層をまたいで持ち越す。
class Party {
  Party({required this.members, required this.hp, required this.maxHp});

  /// 連れていく面々から組む。**体力は顔ぶれの合計。**
  Party.of(Iterable<Mage> members)
    : members = List<Mage>.of(members),
      hp = poolFor(members),
      maxHp = poolFor(members);

  /// 始まりは相を1つずつ持つ従者3人。3色の盤面になる。
  Party.initial() : this.of(Mage.squires);

  /// 一党の体力。**連れていく魔導士の体力の合計**（[Mage.hp]）。
  ///
  /// 潜る前の編成が、そのまま「何手ぶん耐えられるか」になる。力のある者ほど
  /// 薄いので、**厚さを取るか力を取るか**が編成の判断に乗る。人数でも変わる
  /// （3人目を入れれば厚くなるが、盤面は3色になって継ぎ方の決まりが変わる）。
  ///
  /// **敵は毎ターン殴ってくる。** 残っている敵の攻撃力の合計だけ、1手ごとに
  /// 削れる。だから階層あたりの痛手は「攻撃力の合計 × その階層に使った手数」で
  /// 積み上がり、体力は1本の潜りを通した資源になる。
  ///
  /// 竜の巣を通すと、手探りで打てば 165、最短で打っても 114 は浴びる
  /// （`python3 tools/sim/damage.py`。名簿と階層の中身から出すので、どちらを
  /// いじっても数字が動く）。**道中で戻る手立ては氷雨の回復だけ**なので、
  /// 深いところは名簿の体力か `Board.attackFor` で詰め直すことになる。
  static int poolFor(Iterable<Mage> members) =>
      members.fold(0, (sum, mage) => sum + mage.hp);

  final List<Mage> members;
  int hp;
  int maxHp;

  bool has(MageKind kind) => members.any((m) => m.kind == kind);

  /// まだ仲間になっていない次の魔導士。全員揃っていれば null。
  /// 道中では増えないので、いまはガチャ側が未所持を数えるのに使う。
  Mage? get nextRecruit {
    for (final m in Mage.roster) {
      if (!has(m.kind)) return m;
    }
    return null;
  }

  bool get isDown => hp <= 0;

  /// 連れている相。**盤面に敷かれるのはこれだけ。**
  /// 同じ相の魔導士が複数居れば、その相が多く降ってくる。
  List<Phase> get phases {
    final seen = <Phase>[];
    for (final m in members) {
      if (!seen.contains(m.phase)) seen.add(m.phase);
    }
    return seen;
  }

  /// [phases] と同じ並びの人数。補充の比率になる。
  List<int> get phaseWeights => [
    for (final phase in phases)
      members.where((m) => m.phase == phase).length,
  ];

  /// この鎖に応えた [T] 型の効き目を全部。
  ///
  /// **ここから下に魔導士の名前は出てこない。** 誰が居るかではなく、
  /// どの効き目が応えたかだけを数える。名簿に何人足しても変わらない。
  Iterable<T> _boons<T extends Boon>(ChainTally tally) sync* {
    for (final mage in members) {
      final ability = mage.ability;
      if (ability == null || ability.then is! T) continue;
      if (!ability.firesOn(mage.phase, tally)) continue;
      yield ability.then as T;
    }
  }

  int _total<T extends Boon>(ChainTally tally, int Function(T) amount) =>
      _boons<T>(tally).fold(0, (sum, boon) => sum + amount(boon));

  /// 威力補正。重ねて乗る。
  ///
  /// 焔（自分の相3枚以上 +1）と烈火（同5枚以上 +2）は同時に乗るので、赤を
  /// 5枚継げば +3。霜は開始相だけを見るので、枚数を寄せる編み方とは
  /// 噛み合わない。「同じ相を長く継ぐ」か「決まった相から始める」かで
  /// 育て方が割れる。
  int powerBonusFor(ChainTally tally) =>
      _total<PowerUp>(tally, (b) => b.amount);

  /// この鎖を編んだ手が、敵の反撃を受けずに済むか。
  ///
  /// 量ではないので足し合わせない。**1人でも応えれば、その手は痛手を
  /// 受けない。** 階層を落としたときの締めの痛手には効かない（あれは手の
  /// 値段ではなく、討ち漏らしの代償）。
  bool evadesFor(ChainTally tally) => _boons<Evade>(tally).isNotEmpty;

  /// 鎖が戻す体力。
  int healFor(ChainTally tally) => _total<Mend>(tally, (b) => b.amount);

  /// 階層の敵すべてに落ちる打点。0 なら落ちない。
  /// 見るのは威力ではなく継いだ枚数（[ChainLength]）。
  int boltFor(ChainTally tally) => _total<Strike>(tally, (b) => b.amount);

  /// [raw] の痛手を実際に受ける量。[Guard] ひとつにつき半分（切り上げ）に
  /// なる。鎖を見ない能力なので [ChainTally.none] で数える。
  ///
  /// 毎ターンの反撃にも、階層を落としたときの痛手にも同じものを通す。
  int damageFor(int raw) {
    var taken = raw;
    for (var i = _boons<Guard>(ChainTally.none).length; i > 0; i--) {
      taken = (taken + 1) ~/ 2;
    }
    return taken;
  }

  /// 実際に戻った体力を返す（満タンなら 0）。
  int heal(int amount) {
    final before = hp;
    hp = (hp + amount).clamp(0, maxHp);
    return hp - before;
  }

  void takeDamage(int amount) {
    hp -= amount;
    if (hp < 0) hp = 0;
  }
}
