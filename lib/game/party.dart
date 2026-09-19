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

  /// 説明文の前半。[Boon.describe] と繋げて1文になる。
  String describe(Phase phase);
}

/// 自分の相を [need] 枚以上継いだ鎖。
final class SamePhase extends Trigger {
  const SamePhase(this.need);

  final int need;

  @override
  bool met(Phase phase, ChainTally tally) => tally.countOf(phase) >= need;

  @override
  String describe(Phase phase) => '${phase.label}を$need枚以上継いだ鎖';
}

/// [need] 枚以上継いだ鎖。相は問わない。
final class ChainLength extends Trigger {
  const ChainLength(this.need);

  final int need;

  @override
  bool met(Phase phase, ChainTally tally) => tally.length >= need;

  @override
  String describe(Phase phase) => '$need枚以上継いだ鎖';
}

/// 自分の相から継ぎ始めた鎖。枚数を寄せる編み方とは噛み合わない。
final class StartsWith extends Trigger {
  const StartsWith();

  @override
  bool met(Phase phase, ChainTally tally) => tally.startPhase == phase;

  @override
  String describe(Phase phase) => '${phase.label}から継ぎ始めた鎖';
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

/// 使った手を返す。
final class TurnBack extends Boon {
  const TurnBack(this.amount);

  final int amount;

  @override
  String describe() => 'はターンを $amount 返す';
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

/// 階層を落としたときの痛手を半分にする（切り上げ）。
/// 重ねれば重ねただけ半分になっていく。
final class Guard extends Boon {
  const Guard();

  @override
  String describe() => '階層を落としたときの痛手が半分になる';
}

/// 能力ひとつ。**条件と効き目の組でしか書けない。**
///
/// 説明文は組から作る。手で書いた文と数値がずれることが無い。
class Ability {
  const Ability(this.when, this.then);

  final Trigger when;
  final Boon then;

  bool firesOn(Phase phase, ChainTally tally) => when.met(phase, tally);

  String describe(Phase phase) => '${when.describe(phase)}${then.describe()}';
}

enum MageKind {
  /// 相を1つ持つだけの従者。特殊な力は無い。始まりの3人。
  squireHeat,
  squireCold,
  squireBolt,
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
/// 熱や冷の枚数を条件にすると、交互ルールのせいで実質「長さ＋どちらの相から
/// 始めたか」になる。長さ N の鎖に含まれる熱は、熱から始めれば ⌈N/2⌉、
/// 冷から始めれば ⌊N/2⌋。つまり**開始する相の選択**に初めて意味が生まれる。
/// これまで開始相は繋がりやすさ以外どうでもよかったので、ここが新しい判断になる。
class Mage {
  const Mage._(this.kind, this.phase, this.name, this.sigil, [this.ability]);

  final MageKind kind;

  /// この魔導士の相。**編成に入れた相だけが盤面に敷かれる。**
  /// 能力が「自分の相を N 枚以上」という形なのは、連れていく顔ぶれと
  /// 盤面の色がひと続きになるようにするため。
  final Phase phase;

  final String name;

  /// 一党の並びに出す一文字。
  final String sigil;

  /// この魔導士の能力。持たない者は null。
  ///
  /// **[Party] は能力の中身で分岐しない。** ここに [Ability] を1つ置けば、
  /// 集計は [Boon] の種類だけで回る。魔導士を増やすときに触るのは、この
  /// 名簿と [MageKind] だけ。
  final Ability? ability;

  /// 能力の説明。画面にそのまま出す。能力から作るので、数値とずれない。
  String get effect => ability?.describe(phase) ?? '特殊な力は持たない';

  /// 始まりの3人。相を1つ持つだけで、特殊な力は無い。
  /// 3人とも別の相なので、開幕から盤面は3色になる。
  static const squireHeat = Mage._(
    MageKind.squireHeat,
    Phase.heat,
    '熱の従者',
    '熱',
  );
  static const squireCold = Mage._(
    MageKind.squireCold,
    Phase.cold,
    '冷の従者',
    '冷',
  );
  static const squireBolt = Mage._(
    MageKind.squireBolt,
    Phase.bolt,
    '雷の従者',
    '雷',
  );

  static const ember = Mage._(
    MageKind.ember,
    Phase.heat,
    '焔の魔導士',
    '焔',
    Ability(SamePhase(emberSame), PowerUp(1)),
  );
  static const blaze = Mage._(
    MageKind.blaze,
    Phase.heat,
    '烈火の魔導士',
    '烈',
    Ability(SamePhase(blazeSame), PowerUp(2)),
  );
  static const gale = Mage._(
    MageKind.gale,
    Phase.heat,
    '風の魔導士',
    '風',
    Ability(ChainLength(galeChain), TurnBack(1)),
  );
  static const rime = Mage._(
    MageKind.rime,
    Phase.cold,
    '氷雨の魔導士',
    '氷',
    Ability(SamePhase(rimeSame), Mend(1)),
  );
  static const frost = Mage._(
    MageKind.frost,
    Phase.cold,
    '霜の魔導士',
    '霜',
    Ability(StartsWith(), PowerUp(1)),
  );
  static const storm = Mage._(
    MageKind.storm,
    Phase.bolt,
    '雷の魔導士',
    '電',
    Ability(ChainLength(stormChain), Strike(1)),
  );
  static const aegis = Mage._(
    MageKind.aegis,
    Phase.bolt,
    '盾の魔導士',
    '盾',
    Ability(Always(), Guard()),
  );

  /// 始まりの3人。ガチャの対象にはならない。
  static const List<Mage> squires = [squireHeat, squireCold, squireBolt];

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

/// 烈火が応える、自分の相の枚数。焔の上に重ねて乗る。
const int blazeSame = 5;

/// 風がターンを返す枚数。ここを下げると、長い鎖を編めるうちは
/// ターンが減らなくなって階層の制限が意味を失う。少ない側の相を
/// 食い潰す長さに置いてあるのは、枯渇そのものが歯止めになるため。
const int galeChain = 7;

/// 雷が落ちる枚数。ここだけ威力ではなく**継いだ枚数**で見る。
///
/// 焔の補正が乗ると 7 枚でも威力 8 になるが、それでは落とさない。
/// 「8枚つなぐ」は盤面を見ながら数えられるのに対し、「威力 8」は補正が
/// 乗るかどうかを頭の中で足さないと分からず、狙って出せない。
const int stormChain = 8;

/// 階層を制圧したときに選ぶ祝福。
///
/// 仲間は増えない。誰を連れていくかは潜る前の編成で決まっていて、道中で
/// 変わらない。ここで増えるのは体力と最大体力だけ。
enum Blessing { heal, vigor }

/// 祝福の1択ぶん。中身は選ぶ時点の一党によって変わる。
class BlessingOffer {
  const BlessingOffer({
    required this.blessing,
    required this.title,
    required this.detail,
  });

  final Blessing blessing;
  final String title;
  final String detail;
}

/// 一党。階層をまたいで持ち越す。
class Party {
  Party({required this.members, required this.hp, required this.maxHp});

  /// 始まりは相を1つずつ持つ従者3人。3色の盤面になる。
  Party.initial()
    : members = List<Mage>.of(Mage.squires),
      hp = startingHp,
      maxHp = startingHp;

  /// 初期体力。
  ///
  /// 体力が減るのは階層を落としたときだけで、その痛手は討ち漏らした敵の
  /// 守りの合計。守り 5 の敵を2体残せば 10 なので、30 あれば2〜4回の
  /// 取りこぼしに耐える。README のクリア率（階層あたり 78〜93%）と合わせると、
  /// 何度か落としながらじわじわ削られていく速さになる。
  static const int startingHp = 30;

  /// 加護1回で増える最大体力。
  static const int vigorGain = 4;

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
  /// 焔（自分の相3枚以上 +1）と烈火（同5枚以上 +2）は同時に乗るので、熱を
  /// 5枚継げば +3。霜は開始相だけを見るので、枚数を寄せる編み方とは
  /// 噛み合わない。「同じ相を長く継ぐ」か「決まった相から始める」かで
  /// 育て方が割れる。
  int powerBonusFor(ChainTally tally) =>
      _total<PowerUp>(tally, (b) => b.amount);

  /// 鎖が返すターン。
  int turnGainFor(ChainTally tally) =>
      _total<TurnBack>(tally, (b) => b.amount);

  /// 鎖が戻す体力。
  int healFor(ChainTally tally) => _total<Mend>(tally, (b) => b.amount);

  /// 階層の敵すべてに落ちる打点。0 なら落ちない。
  /// 見るのは威力ではなく継いだ枚数（[ChainLength]）。
  int boltFor(ChainTally tally) => _total<Strike>(tally, (b) => b.amount);

  /// 階層を落としたときに実際に受ける痛手。[Guard] ひとつにつき半分
  /// （切り上げ）になる。鎖を見ない能力なので [ChainTally.none] で数える。
  int backlashFor(int threat) {
    var taken = threat;
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

  /// いま選べる祝福。仲間が揃っていれば「同行」は出ない。
  List<BlessingOffer> offers() => [
    BlessingOffer(
      blessing: Blessing.heal,
      title: '癒やし',
      detail: '体力を ${(maxHp * 0.4).round()} 戻す',
    ),
    BlessingOffer(
      blessing: Blessing.vigor,
      title: '加護',
      detail: '最大体力 +$vigorGain',
    ),
  ];

  void grant(Blessing blessing) {
    switch (blessing) {
      case Blessing.heal:
        heal((maxHp * 0.4).round());
      case Blessing.vigor:
        maxHp += vigorGain;
        heal(vigorGain);
    }
  }
}
