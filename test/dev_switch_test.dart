import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/dev_switch.dart';
import 'package:parity_chain/game/dungeon.dart';
import 'package:parity_chain/game/party.dart';
import 'package:parity_chain/game/progress.dart';

void main() {
  group('試用の口', () {
    test('?all が付いているときだけ開く', () {
      const base = 'https://yun8686.github.io/merge_puzzle/';
      expect(unlockAllIn(Uri.parse(base)), isFalse, reason: '遊ぶ側の URL');
      expect(unlockAllIn(Uri.parse('$base?all')), isTrue);
      expect(unlockAllIn(Uri.parse('$base?all=1')), isTrue);
      expect(unlockAllIn(Uri.parse('$base?other=1')), isFalse);
    });

    test('# 付きの URL でも拾う', () {
      // flutter web は既定で `#` 付きの URL を使う。
      const base = 'https://yun8686.github.io/merge_puzzle/';
      expect(unlockAllIn(Uri.parse('$base#/?all')), isTrue);
      expect(unlockAllIn(Uri.parse('$base#/')), isFalse);
    });

    test('端末のアプリでは開かない', () {
      // web でないときの [Uri.base] は file の URL で、問い合わせは無い。
      expect(unlockAllIn(Uri.parse('file:///data/user/0/app/')), isFalse);
    });
  });

  group('全部開いた記録', () {
    test('名簿は全員、ダンジョンは全部踏破済み', () {
      final progress = unlockedProgress();
      for (final mage in Mage.roster) {
        expect(progress.owned, contains(mage.kind), reason: mage.name);
      }
      expect(progress.unowned, isEmpty, reason: 'ガチャで引く相手が残らない');
      for (final dungeon in Dungeons.all) {
        // 「前の1本を踏破すると開く」決まりを、踏破の印で外している。
        expect(progress.hasCleared(dungeon.id), isTrue, reason: dungeon.name);
      }
      expect(progress.partyIsValid, isTrue);
    });

    test('稽古は通した扱い。保存しないので、でなければ毎回出る', () {
      final progress = unlockedProgress();
      expect(progress.taughtTutorial, isTrue);
      expect(progress.taughtPrism, isTrue);
    });

    test('書いて読み直しても開いたまま', () {
      // 手元の箱は encode した文字列を持つので、往復で落ちないこと。
      final back = Progress.decode(unlockedProgress().encode());
      expect(back.owned.length, Mage.roster.length);
      expect(back.cleared.length, Dungeons.all.length);
      expect(back.shards, 999);
    });
  });
}
