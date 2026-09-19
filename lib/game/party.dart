/// 盤面の上に乗る「一党」。階層をまたいで持ち越す唯一の状態で、
/// ここだけがステージを越えて残る。
///
/// 魔導士は盤面に置かない。編んだ鎖の戦果（[ChainTally]）だけを見て反応する。
/// 盤面ロジックに触らないので、検証済みのパズルの数値はそのまま生きている。
library;

/// 鎖1本の戦果。魔導士が見るのはこれだけ。
class ChainTally {
  const ChainTally({
    required this.length,
    required this.heat,
    required this.frost,
  });

  /// 継いだ枚数。
  final int length;

  /// そのうち熱の相（奇数）の枚数。
  final int heat;

  /// そのうち冷の相（偶数）の枚数。
  final int frost;
}

enum MageKind { ember, rime, storm }

/// 一党に加わる魔導士。能力は「鎖の戦果への反応」として書く。
///
/// 熱や冷の枚数を条件にすると、交互ルールのせいで実質「長さ＋どちらの相から
/// 始めたか」になる。長さ N の鎖に含まれる熱は、熱から始めれば ⌈N/2⌉、
/// 冷から始めれば ⌊N/2⌋。つまり**開始する相の選択**に初めて意味が生まれる。
/// これまで開始相は繋がりやすさ以外どうでもよかったので、ここが新しい判断になる。
class Mage {
  const Mage._(this.kind, this.name, this.sigil, this.effect);

  final MageKind kind;
  final String name;

  /// 一党の並びに出す一文字。
  final String sigil;

  /// 能力の説明。画面にそのまま出す。
  final String effect;

  static const ember = Mage._(
    MageKind.ember,
    '焔の魔導士',
    '焔',
    '熱を3枚以上継いだ鎖は威力 +1',
  );
  static const rime = Mage._(
    MageKind.rime,
    '氷雨の魔導士',
    '氷',
    '冷を3枚以上継いだ鎖で体力を 1 戻す',
  );
  static const storm = Mage._(
    MageKind.storm,
    '雷の魔導士',
    '雷',
    '8枚以上継いだ鎖は階層の敵すべてに 1 ダメージ',
  );

  /// 加入する順番。制圧の祝福で1人ずつ増える。
  static const List<Mage> roster = [ember, rime, storm];
}

/// 熱の相を何枚継げば焔が応えるか。
const int emberHeat = 3;

/// 冷の相を何枚継げば氷雨が応えるか。
const int rimeFrost = 3;

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

  /// 始まりは焔の魔導士ひとり。
  Party.initial()
    : members = <Mage>[Mage.ember],
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

  /// 焔の威力補正。
  int powerBonusFor(ChainTally tally) =>
      has(MageKind.ember) && tally.heat >= emberHeat ? 1 : 0;

  /// 氷雨の回復量。
  int healFor(ChainTally tally) =>
      has(MageKind.rime) && tally.frost >= rimeFrost ? 1 : 0;

  /// 雷が落ちるか。見るのは威力ではなく継いだ枚数。
  bool boltFor(int length) => has(MageKind.storm) && length >= stormChain;

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
