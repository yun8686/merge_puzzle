import 'dungeon.dart';
import 'party.dart';
import 'progress.dart';

/// クリアした1本の戦果。拠点が盤面の画面から受け取った結末と、連れていった
/// 顔ぶれから組む。**★も課題もここだけを見て決まる**――盤面は読まない。
class DiveReport {
  const DiveReport({
    required this.party,
    required this.score,
    required this.bestChain,
    required this.moves,
    required this.hpLeft,
    required this.maxHp,
  });

  /// 連れていった魔導士。
  final List<Mage> party;

  final int score;

  /// いちばん強かったチェインの威力。
  final int bestChain;

  /// 使った手数（つないだ本数）。
  final int moves;

  /// クリアしたときに残っていた体力。
  final int hpLeft;
  final int maxHp;

  /// 残っていた体力の割合（0〜100、切り捨て）。
  int get hpPercent => maxHp <= 0 ? 0 : (hpLeft * 100 ~/ maxHp).clamp(0, 100);

  /// 自己ベストに重ねる形。
  DungeonRecord get record => DungeonRecord(
    score: score,
    chain: bestChain,
    moves: moves,
    hpPercent: hpPercent,
  );
}

/// ダンジョンごとの★。**3つとも別の条件**で、どの回で取ってもよい。
///
/// 1回で3つ揃える必要は無い。「体力を残す回」と「手早く抜ける回」は
/// 編成も打ち方も違うので、1回に両方を求めると同じ編成で押し切るだけに
/// なる。★は自己ベスト（[DungeonRecord]）から割り出すので保存しない。
enum Star { clear, hp, moves }

class Stars {
  const Stars._();

  /// ★の2つ目。クリアしたときに、この割合以上の体力が残っていること。
  static const int hpPercent = 50;

  static bool lit(
    Star star,
    Dungeon dungeon, {
    required bool cleared,
    DungeonRecord? record,
  }) => switch (star) {
    Star.clear => cleared,
    Star.hp => record != null && record.hpPercent >= hpPercent,
    Star.moves => record != null && record.moves <= dungeon.par,
  };

  /// 札に並べる言葉。★の横に出すので短く。
  static String label(Star star, Dungeon dungeon) => switch (star) {
    Star.clear => 'クリア',
    Star.hp => '体力半分以上',
    Star.moves => '${dungeon.par}手以内',
  };

  /// 帰ってきたときの知らせに出す言葉。
  static String earned(Star star, Dungeon dungeon) => switch (star) {
    Star.clear => '★ クリア',
    Star.hp => '★ 体力を半分以上残してクリア',
    Star.moves => '★ ${dungeon.par}手以内でクリア',
  };
}

/// 課題の条件。**クリアした1本の戦果だけを見る**（[DiveReport]）。
///
/// パッシブスキルの条件（`Trigger`）と同じ考え方で、課題ごとに分岐を
/// 書かずに、条件の種類を増やして組み合わせる。
abstract class FeatRule {
  const FeatRule();

  bool passes(DiveReport report);

  /// 画面に出す文。「〜でクリア」まで言い切る。
  String get describe;
}

/// 威力 [power] 以上のチェインを1回でも出した。
class MinChain extends FeatRule {
  const MinChain(this.power);

  final int power;

  @override
  bool passes(DiveReport report) => report.bestChain >= power;

  @override
  String get describe => '威力$power以上のチェインを出してクリア';
}

/// 見習いだけで挑んだ。スキル無しで、威力＝つないだ枚数のまま。
class SquiresOnly extends FeatRule {
  const SquiresOnly();

  @override
  bool passes(DiveReport report) =>
      report.party.every((m) => Mage.squires.contains(m));

  @override
  String get describe => '見習いだけでクリア';
}

/// [count] 人以下で挑んだ。体力の合計が薄くなる。
class MaxMembers extends FeatRule {
  const MaxMembers(this.count);

  final int count;

  @override
  bool passes(DiveReport report) => report.party.length <= count;

  @override
  String get describe => '$count人以下でクリア';
}

/// [count] 色以上の編成で挑んだ。
class PartyPhases extends FeatRule {
  const PartyPhases(this.count);

  final int count;

  @override
  bool passes(DiveReport report) =>
      {for (final m in report.party) m.phase}.length >= count;

  @override
  String get describe => '$count色の編成でクリア';
}

/// 体力を [percent]% 以上残した。
class HpLeft extends FeatRule {
  const HpLeft(this.percent);

  final int percent;

  @override
  bool passes(DiveReport report) => report.hpPercent >= percent;

  @override
  String get describe => '体力を$percent%以上残してクリア';
}

/// 課題1つ。[id] は保存に乗る（`Progress.featKey`）ので、**出したら変えない**。
class Feat {
  const Feat(this.id, this.rule);

  final String id;
  final FeatRule rule;

  String get label => rule.describe;
}

/// ダンジョンごとの課題。**クリアしたときにだけ**見る。
///
/// 課題は★と別の軸にする。★は「体力を残す」「手早く抜ける」という打ち方の
/// 話で、課題は「誰を連れていくか」「どこまで伸ばすか」という編成と盤面の
/// 話。初めのほうのダンジョンは、次に試すとよいこと（3色、長いチェイン）へ
/// 誘う課題にしてある。
///
/// 増やすのはこの表だけ。**ダンジョンの id と課題の id は保存に乗る。**
/// どのダンジョンにも課題があるか、id が被っていないかは `feats_test.dart`
/// が見張る。
class Feats {
  const Feats._();

  static List<Feat> of(String dungeonId) => _table[dungeonId] ?? const [];

  /// 課題を持っているダンジョンの id。表の書き間違いを見張るのに使う。
  static Iterable<String> get dungeonIds => _table.keys;

  /// ダンジョンの id から引く表。
  ///
  /// 手の届く範囲に置くこと。見習い3人の体力は 135、2人なら 90。
  /// `python3 tools/sim/damage.py` の「きつい」がその体力を超える
  /// ダンジョンに、見習いだけ・2人以下を置くと、ほぼ取れない課題になる。
  static const Map<String, List<Feat>> _table = {
    'hollow': [
      Feat('chain8', MinChain(8)),
      Feat('prism', PartyPhases(3)),
    ],
    'cavern': [
      Feat('chain10', MinChain(10)),
      Feat('hp70', HpLeft(70)),
    ],
    'corridor': [
      Feat('duo', MaxMembers(2)),
      Feat('chain10', MinChain(10)),
    ],
    'ruins': [
      Feat('duo', MaxMembers(2)),
      Feat('squires', SquiresOnly()),
    ],
    'tower': [
      Feat('squires', SquiresOnly()),
      Feat('chain12', MinChain(12)),
    ],
    'lair': [
      Feat('squires', SquiresOnly()),
      Feat('chain12', MinChain(12)),
    ],
  };

  /// この戦果で**初めて**果たした課題。まだ記録には書かない。
  static List<Feat> newlyMet(
    Progress progress,
    String dungeonId,
    DiveReport report,
  ) => [
    for (final feat in of(dungeonId))
      if (!progress.hasFeat(dungeonId, feat.id) && feat.rule.passes(report))
        feat,
  ];
}
