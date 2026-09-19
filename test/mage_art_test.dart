import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/party.dart';
import 'package:parity_chain/ui/mage_art.dart';

void main() {
  testWidgets('名簿の全員に姿がある', (tester) async {
    // 姿は MageKind で引いている。魔導士を足して tools/mage/ を走らせ忘れると
    // 実機で落ちるので、ここで全員ぶん描いて確かめる。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              for (final kind in MageKind.values)
                MagePortrait(kind: kind, size: 38),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MagePortrait), findsNWidgets(MageKind.values.length));
    expect(tester.takeException(), isNull);
  });

  testWidgets('小さく描いても落ちない', (tester) async {
    // 一党の帯では 21px まで縮む。線の太さは相対値なので潰れはするが、
    // 例外にはならないこと。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              for (final kind in MageKind.values)
                MagePortrait(kind: kind, size: 12),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
