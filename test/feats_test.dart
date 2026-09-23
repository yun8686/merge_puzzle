import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/dungeon.dart';
import 'package:parity_chain/game/feats.dart';
import 'package:parity_chain/game/party.dart';
import 'package:parity_chain/game/progress.dart';

/// 戦果を組む。書かなかった項目は、どの課題にも引っかからない控えめな値。
DiveReport report({
  List<Mage> party = const [Mage.squireRed, Mage.squireBlue],
  int score = 100,
  int bestChain = 3,
  int moves = 99,
  int hpLeft = 1,
  int maxHp = 90,
}) => DiveReport(
  party: party,
  score: score,
  bestChain: bestChain,
  moves: moves,
  hpLeft: hpLeft,
  maxHp: maxHp,
);

void main() {
  group('課題の見張り', () {
    test('どのダンジョンにも課題がある', () {
      for (final dungeon in Dungeons.all) {
        expect(Feats.of(dungeon.id), isNotEmpty, reason: dungeon.name);
      }
    });

    test('表に書いた id はどれも実在するダンジョン', () {
      // 書き間違えると、その課題はどこにも出てこないまま黙って消える。
      final ids = {for (final d in Dungeons.all) d.id};
      for (final id in Feats.dungeonIds) {
        expect(ids, contains(id), reason: id);
      }
    });

    test('1本の中で課題の id も文も被らない', () {
      for (final dungeon in Dungeons.all) {
        final feats = Feats.of(dungeon.id);
        expect(
          {for (final f in feats) f.id}.length,
          feats.length,
          reason: dungeon.name,
        );
        expect(
          {for (final f in feats) f.label}.length,
          feats.length,
          reason: dungeon.name,
        );
        for (final f in feats) {
          expect(f.id, isNot(contains('/')), reason: '保存の鍵の区切りと被る');
          expect(f.label, endsWith('クリア'), reason: f.id);
        }
      }
    });
  });

  group('課題の条件', () {
    test('威力は1回でも届けばよい', () {
      expect(const MinChain(8).passes(report(bestChain: 8)), isTrue);
      expect(const MinChain(8).passes(report(bestChain: 7)), isFalse);
    });

    test('見習いだけ', () {
      expect(const SquiresOnly().passes(report()), isTrue);
      expect(
        const SquiresOnly().passes(
          report(party: const [Mage.squireRed, Mage.ember]),
        ),
        isFalse,
      );
    });

    test('人数と色の数', () {
      expect(const MaxMembers(2).passes(report()), isTrue);
      final three = report(
        party: const [Mage.squireRed, Mage.squireBlue, Mage.squireViolet],
      );
      expect(const MaxMembers(2).passes(three), isFalse);
      expect(const PartyPhases(3).passes(three), isTrue);
      expect(const PartyPhases(3).passes(report()), isFalse);
    });

    test('残した体力は割合で見る', () {
      expect(report(hpLeft: 63, maxHp: 90).hpPercent, 70);
      expect(const HpLeft(70).passes(report(hpLeft: 63, maxHp: 90)), isTrue);
      expect(const HpLeft(70).passes(report(hpLeft: 62, maxHp: 90)), isFalse);
    });

    test('果たした課題は二度出てこない', () {
      final progress = Progress();
      final strong = report(bestChain: 99);
      final first = Feats.newlyMet(progress, 'hollow', strong);
      expect(first.map((f) => f.id), contains('chain8'));

      for (final feat in first) {
        expect(progress.recordFeat('hollow', feat.id), Progress.featReward);
      }
      expect(Feats.newlyMet(progress, 'hollow', strong), isEmpty);
    });
  });

  group('★', () {
    final hollow = Dungeons.all.first;

    test('手数の目安は階層ごとに「敵の体力の合計＋1」', () {
      var par = 0;
      for (final floor in hollow.floors) {
        par += floor.totalFoeHp + 1;
      }
      expect(hollow.par, par);
    });

    test('3つは別の条件で、クリアしていなければ1つも灯らない', () {
      for (final star in Star.values) {
        expect(Stars.lit(star, hollow, cleared: false), isFalse);
      }
      // 古い保存：クリアの印はあるが、自己ベストが無い。
      expect(Stars.lit(Star.clear, hollow, cleared: true), isTrue);
      expect(Stars.lit(Star.hp, hollow, cleared: true), isFalse);
      expect(Stars.lit(Star.moves, hollow, cleared: true), isFalse);

      final record = DungeonRecord(
        score: 0,
        chain: 0,
        moves: hollow.par,
        hpPercent: Stars.hpPercent,
      );
      expect(
        Stars.lit(Star.hp, hollow, cleared: true, record: record),
        isTrue,
      );
      expect(
        Stars.lit(Star.moves, hollow, cleared: true, record: record),
        isTrue,
        reason: '目安ちょうどは取れる',
      );
      final slow = DungeonRecord(
        score: 0,
        chain: 0,
        moves: hollow.par + 1,
        hpPercent: Stars.hpPercent - 1,
      );
      expect(Stars.lit(Star.hp, hollow, cleared: true, record: slow), isFalse);
      expect(
        Stars.lit(Star.moves, hollow, cleared: true, record: slow),
        isFalse,
      );
    });
  });
}
