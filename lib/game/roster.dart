part of 'party.dart';

// 名簿。**誰が居るかはここだけ。**
//
// 仕組み（party.dart）は名簿の中身を知らない。能力は条件と効き目の組で、
// 押して使う力は [Spell] の実体で書くので、ここに1人足しても [Party] も
// 進行も画面も変わらない。**100人に増えても伸びるのはこのファイルだけ。**
//
// 1人足すときは4つ。MageKind に1つ／下の const を1つ／[Mage.roster] に
// 並べる／tools/mage/shapes.py に姿を足して emit_dart.py を走らせる。
// 並べ忘れ・重複・姿の欠けは party_test.dart の「名簿の見張り」が捕まえる。

/// 魔導士の種類。**保存にそのまま書かれる**（`Progress.toJson`）ので、
/// 一度出した名前は変えないこと。変えるなら `Progress` に読み替えを足す。
///
/// 並び順は意味を持たない（見せる順は [Mage.roster]）。
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
  /// **名前付きで渡す。** 100人並ぶ表なので、位置で読ませると
  /// `Mage._(k, p, n, 40, ability, spell)` の 40 が何なのか分からなくなる。
  const Mage._({
    required this.kind,
    required this.phase,
    required this.name,
    required this.hp,
    this.ability,
    this.spell,
    this.starting = false,
  });

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
  /// 集計は [Boon] の種類だけで回る。
  final Ability? ability;

  /// 押して使う力。持たない者は null。**潜り1本に1回だけ**。
  ///
  /// [ability] と違って鎖を見ないので、条件と効き目の組には収まらない。
  /// 増やすときは `spells.dart` に [Spell] を1つ足して、ここで持たせる
  /// だけ――呼ぶ側に分岐は増えない。
  final Spell? spell;

  /// 最初から持っている従者か。
  ///
  /// **[squires] と [summonable] はここから割る。** 名簿を1本にしておけば、
  /// 並べ忘れて「所持しているのにガチャにも出る」ような食い違いが起きない。
  final bool starting;

  /// 能力の説明。画面にそのまま出す。能力から作るので、数値とずれない。
  String get effect => ability?.describe(phase) ?? '特殊な力は持たない';

  /// 押して使う力の説明。持たない者は null。
  /// **相はここで埋める**ので、力の側は誰のものかを知らないままでいられる。
  String? get spellEffect => spell?.describe(phase);

  /// 従者の体力。**名簿でいちばん厚い。** 特殊な力が無いぶんここで返す。
  /// 始まりの2人で 90 あり、1本目のダンジョンはこれで通る。
  static const int squireHp = 45;

  // ---- 始まりの3人 -----------------------------------------------------
  // 相を1つ持つだけで、特殊な力は無い。3人とも別の相。

  static const squireRed = Mage._(
    kind: MageKind.squireRed,
    phase: Phase.red,
    name: '赤の従者',
    hp: squireHp,
    starting: true,
  );
  static const squireBlue = Mage._(
    kind: MageKind.squireBlue,
    phase: Phase.blue,
    name: '青の従者',
    hp: squireHp,
    starting: true,
  );
  static const squireViolet = Mage._(
    kind: MageKind.squireViolet,
    phase: Phase.violet,
    name: '紫の従者',
    hp: squireHp,
    starting: true,
  );

  // ---- 招ける魔導士 ----------------------------------------------------

  static const ember = Mage._(
    kind: MageKind.ember,
    phase: Phase.red,
    name: '焔の魔導士',
    hp: 40,
    ability: Ability(SamePhase(emberSame), PowerUp(1)),
  );
  static const blaze = Mage._(
    kind: MageKind.blaze,
    phase: Phase.red,
    name: '烈火の魔導士',
    hp: 30,
    ability: Ability(SamePhase(blazeSame), PowerUp(2)),
    spell: Spread(),
  );
  static const gale = Mage._(
    kind: MageKind.gale,
    phase: Phase.red,
    name: '風の魔導士',
    hp: 35,
    ability: Ability(ChainLength(galeChain), Evade()),
    spell: Foresee(),
  );
  static const rime = Mage._(
    kind: MageKind.rime,
    phase: Phase.blue,
    name: '氷雨の魔導士',
    hp: 45,
    ability: Ability(SamePhase(rimeSame), Mend(rimeMend)),
  );
  static const frost = Mage._(
    kind: MageKind.frost,
    phase: Phase.blue,
    name: '霜の魔導士',
    hp: 40,
    ability: Ability(StartsWith(), PowerUp(1)),
  );
  static const storm = Mage._(
    kind: MageKind.storm,
    phase: Phase.violet,
    name: '雷の魔導士',
    hp: 30,
    ability: Ability(
      Every([DistinctPhases(stormPhases), ChainLength(stormChain)]),
      Strike(1),
    ),
  );
  static const aegis = Mage._(
    kind: MageKind.aegis,
    phase: Phase.violet,
    name: '盾の魔導士',
    hp: 40,
    ability: Ability(Always(), Guard()),
  );

  /// 名簿。**この並びがそのまま画面に出る順**で、従者が先。
  ///
  /// 1人足したらここに並べること。並べ忘れると [of] が落ちるが、
  /// party_test.dart の「名簿の見張り」がその前に捕まえる。
  static const List<Mage> roster = [
    squireRed,
    squireBlue,
    squireViolet,
    ember,
    blaze,
    gale,
    rime,
    frost,
    storm,
    aegis,
  ];

  /// 始まりの3人。ガチャの対象にはならない。[roster] から割る。
  static final List<Mage> squires = List.unmodifiable([
    for (final mage in roster)
      if (mage.starting) mage,
  ]);

  /// ガチャで増える面々。[roster] から割る。
  static final List<Mage> summonable = List.unmodifiable([
    for (final mage in roster)
      if (!mage.starting) mage,
  ]);

  /// 種類から引く表。**名簿を舐めない。**
  ///
  /// 相の色（`Palette.mageColor`）や編成の読み直し（`Progress`）から1フレーム
  /// に何度も呼ばれるので、100人並んだ名簿を毎回頭から探すわけにいかない。
  static final Map<MageKind, Mage> _byKind = Map.unmodifiable({
    for (final mage in roster) mage.kind: mage,
  });

  /// [kind] の魔導士。名簿に並べ忘れた種類は無いので、必ず見つかる。
  static Mage of(MageKind kind) => _byKind[kind]!;
}
// ---- 調整の定数 ------------------------------------------------------
// 能力の説明文はここから作られるので、数値を変えれば画面の文も動く。

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
