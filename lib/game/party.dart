/// 盤面の上に乗る「一党」。階層をまたいで持ち越す唯一の状態で、
/// ここだけがステージを越えて残る。
///
/// 魔導士は盤面に置かない。編んだ鎖の戦果（[ChainTally]）だけを見て反応する。
/// 盤面ロジックに触らないので、検証済みのパズルの数値はそのまま生きている。
library;

import 'phase.dart';

// 名簿（誰が居るか）と、アクティブスキルの中身は別のファイルに置いてある。
// **ここは仕組みだけ**――名簿が100人に増えても、この上下は1行も変わらない。
part 'roster.dart';
part 'actives.dart';

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

  /// 鎖が1本も無い状態。鎖を見ないスキル（[Always]）を数えるときに渡す。
  static const none = ChainTally(
    length: 0,
    counts: <Phase, int>{},
    startPhase: null,
  );
}

/// パッシブスキルが応える条件。**見るのは鎖の戦果と、その魔導士自身の相だけ。**
///
/// 盤面も一党も見ないので、条件を1つ足しても他に波及しない。魔導士を
/// 増やすときは、ここにある条件と [Boon] を組み合わせるだけで済む。
sealed class Trigger {
  const Trigger();

  bool met(Phase phase, ChainTally tally);

  /// 「〜な」まで。[Passive.describe] が「鎖」を足して1文にする。
  /// 条件を重ねたとき（[Every]）に前から順に繋がるよう、ここでは
  /// 「チェイン」を書かない。
  String describe(Phase phase);
}

/// 自分の相を [need] 枚以上継いだ鎖。
final class SamePhase extends Trigger {
  const SamePhase(this.need);

  final int need;

  @override
  bool met(Phase phase, ChainTally tally) => tally.countOf(phase) >= need;

  @override
  String describe(Phase phase) => '${phase.label}を$need枚以上つないだ';
}

/// [need] 枚以上継いだ鎖。相は問わない。
final class ChainLength extends Trigger {
  const ChainLength(this.need);

  final int need;

  @override
  bool met(Phase phase, ChainTally tally) => tally.length >= need;

  @override
  String describe(Phase phase) => '$need枚以上つないだ';
}

/// 自分の相から継ぎ始めた鎖。枚数を寄せる編み方とは噛み合わない。
final class StartsWith extends Trigger {
  const StartsWith();

  @override
  bool met(Phase phase, ChainTally tally) => tally.startPhase == phase;

  @override
  String describe(Phase phase) => '${phase.label}から始めた';
}

/// [need] 種類以上の相を含む鎖。
///
/// 色の決まりがあった頃は、これは**盤面が何色か**とほぼ同じ意味だった
/// （長さ3以上の鎖は必ず3色を含んだ）。決まりが無くなってからは
/// **狙って3色を通す条件**になっている。3色で編成していることに加えて、
/// その3色を1本の中に入れる道を選ぶ必要がある（README 第22段階）。
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
  String describe() => 'のターンは反撃を受けない';
}

/// 一党の体力を戻す。
final class Mend extends Boon {
  const Mend(this.amount);

  final int amount;

  @override
  String describe() => 'で体力が $amount 回復';
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
  String describe() => '受けるダメージが半分になる';
}

/// アクティブスキルが触れられること。**盤面そのものは渡さない。**
///
/// 一党が盤面を読まない線は、ここでも引いてある。渡すのは**やってほしいこと
/// の名前**だけで、どう実現するかは盤面を持っている側（`GameController`）の
/// 仕事になる。だから `party.dart` は `board.dart` を import しないままでいる。
///
/// **力を増やすときは、ここに動詞を1つ足すか、既にある動詞を使う。**
/// 進行の側に「この力ならこうする」という分岐を書かない――それをやると、
/// 力が増えるたびに `GameController` が太っていく。
abstract interface class ActiveStage {
  /// 敵にいちばん深く届く道を探して、お手本として盤面に出す。
  ///
  /// 1でも届く道が無ければ false。**そのときは何も起きていない**ので、
  /// 呼んだ側は回数を減らさない。
  bool revealBestRoute();

  /// **次の1本だけ、[phase] だけでつないだチェインを通す。**
  ///
  /// 色の決まりが無くなったいまは、立てても盤面の振る舞いは変わらない
  /// （README 第22段階）。決まりを入れ直すときの緩め先として残してある。
  ///
  /// その相だけで3枚つながるところが盤面に無ければ false。**立てても何も
  /// 変わらない**ので、呼んだ側は回数を減らさない。
  bool spread(Phase phase);
}

/// **アクティブスキル。** 鎖を見ない。一党の帯から手で使う。
///
/// [Passive] が鎖の戦果に勝手に応えるのに対して、こちらは押して使う。
/// **1本の潜りで [Party.activeUses] 回だけ**（[Party.canUse]）。回数を
/// 持つのは [Party] で、潜るたびに組み直されるので、数えるところは1つで済む。
///
/// **sealed にしていない。** 何をするかは [cast] が自分で言うので、呼ぶ側に
/// 型で分岐する場所が無い。力が100種類に増えても、増えるのはこの下の実体
/// （`actives.dart`）だけで、進行も画面も名簿も変わらない。
abstract class Active {
  const Active();

  /// 札に出す名前。**手で付ける。**
  ///
  /// 効き目の文（[describe]）は型と相から作れるが、名前はそこからは出て
  /// こない。呼び名が無いと、画面でも会話でも「風のあれ」としか指せない。
  String get name;

  /// 何が起きるか。説明文も型から作るので、手で書いた文とずれない。
  ///
  /// [phase] は持ち主の相。[Trigger.describe] と同じで、**力の側は誰の
  /// ものかを知らない**――相を受け取るから、同じ力を別の相の魔導士にも
  /// 持たせられる。
  String describe(Phase phase);

  /// 使う。**何も起きなければ false**（呼んだ側は回数を減らさない）。
  bool cast(ActiveStage stage, Phase phase);
}

/// **パッシブスキル。** 鎖を編むたび、条件を満たせば勝手に効く。
///
/// **条件（[Trigger]）と効き目（[Boon]）の組でしか書けない。** [Party] は
/// 効き目の種類ごとに足し合わせるだけなので、名簿を増やしてもそこは変わらない。
///
/// 説明文は組から作る（[describe]）。手で書いた文と数値がずれることが無い。
/// **名前だけは手で付ける**――組からは出てこないし、呼び名が無いと画面でも
/// 会話でも指せない。
class Passive {
  const Passive(this.name, this.when, this.then);

  /// 札に出す名前。[Active.name] と同じ扱い。
  final String name;

  final Trigger when;
  final Boon then;

  bool firesOn(Phase phase, ChainTally tally) => when.met(phase, tally);

  /// 「〜なチェインは威力 +1」のように、条件と効き目を繋いだ1文。
  /// [Always] のように鎖を見ない条件は空文字を返すので、「チェイン」も付けない。
  String describe(Phase phase) {
    final clause = when.describe(phase);
    final boon = then.describe();
    return clause.isEmpty ? boon : '$clauseチェイン$boon';
  }
}

/// 一党。階層をまたいで持ち越す。
class Party {
  Party({required this.members, required this.hp, required this.maxHp});

  /// 連れていく面々から組む。**体力は顔ぶれの合計。**
  Party.of(Iterable<Mage> members)
    : members = List<Mage>.of(members),
      hp = poolFor(members),
      maxHp = poolFor(members);

  /// 始まりは相を1つずつ持つ見習い3人。3色の盤面になる。
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

  /// 1本の潜りで、[Active] を1人につき何回使えるか。
  ///
  /// **潜る前に決まって道中では増えない**のは体力と同じ。使い切った先は
  /// 編成をやり直すか、潜り直すかしかない。
  static const int activeUses = 1;

  /// この潜りで押した力を、誰が何回使ったか。
  ///
  /// [Party] は潜るたびに組み直される（`GameController._freshParty`）ので、
  /// **ここに置くだけで「1ダンジョンに1回」になる**。階層をまたいでも
  /// 戻らないのは体力と同じ扱い。
  final Map<MageKind, int> activesSpent = <MageKind, int>{};

  /// [kind] のアクティブスキルが、まだ残っているか。
  /// 連れていない者、力を持たない者は false。
  bool canUse(MageKind kind) =>
      activeOf(kind) != null && usesLeft(kind) > 0;

  /// [kind] に残っている回数。持たない者は 0。
  int usesLeft(MageKind kind) => activeOf(kind) == null
      ? 0
      : activeUses - (activesSpent[kind] ?? 0);

  /// 連れている [kind] のアクティブスキル。連れていなければ null。
  Active? activeOf(MageKind kind) => memberOf(kind)?.active;

  /// 1回ぶん使う。残っていなければ false（何も減らさない）。
  bool spendUse(MageKind kind) {
    if (!canUse(kind)) return false;
    activesSpent[kind] = (activesSpent[kind] ?? 0) + 1;
    return true;
  }

  bool has(MageKind kind) => members.any((m) => m.kind == kind);

  /// 連れている [kind]。連れていなければ null。
  Mage? memberOf(MageKind kind) {
    for (final mage in members) {
      if (mage.kind == kind) return mage;
    }
    return null;
  }

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
      final passive = mage.passive;
      if (passive == null || passive.then is! T) continue;
      if (!passive.firesOn(mage.phase, tally)) continue;
      yield passive.then as T;
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
  /// なる。鎖を見ないスキルなので [ChainTally.none] で数える。
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
