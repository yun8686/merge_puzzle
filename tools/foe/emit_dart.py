"""shapes.py から lib/ui/foe_art.dart を生成する。

プレビュー(Pillow)とアプリ(Flutter)が同じ座標を読むようにするための橋渡し。
Dart 側を手で書き写さない。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from shapes import FOES  # noqa: E402

LAYER = {'fill': '_Layer.fill', 'hole': '_Layer.hole', 'glow': '_Layer.glow'}
VAR = {3: '_imp', 4: '_bones', 5: '_shade', 6: '_golem', 7: '_beast', 8: '_wyrm'}


def pts(seq, indent):
    """点は3つずつ折り返す。1行に詰めると dart format の幅を超えて読めない。"""
    items = [f'Offset({x:.3f}, {y:.3f})' for x, y in seq]
    if len(items) <= 2:
        return '[' + ', '.join(items) + ']'
    pad = ' ' * (indent + 2)
    rows = [", ".join(items[i:i+2]) for i in range(0, len(items), 2)]
    return '[\n' + ''.join(f'{pad}{r},\n' for r in rows) + ' ' * indent + ']'


def ops_of(ops):
    out = []
    for op in ops:
        kind, layer = op[0], LAYER[op[1]]
        if kind == 'poly':
            out.append(f'  _Poly({layer}, {pts(op[2], 2)}),')
        elif kind == 'circle':
            cx, cy, r = op[2]
            out.append(f'  _Circle({layer}, Offset({cx:.3f}, {cy:.3f}), {r:.3f}),')
        elif kind == 'line':
            out.append(f'  _Line({layer}, {pts(op[2], 2)}, {op[3]:.3f}),')
    return '\n'.join(out)


HEAD = '''import 'package:flutter/material.dart';

import '../game/board.dart';
import 'theme.dart';

// このファイルの座標は tools/foe/shapes.py から生成している。手で直さないこと。
// 形を変えるときは shapes.py を直し、tools/foe/preview.py で確かめてから
// tools/foe/emit_dart.py を走らせる。
//
// 盤面での敵は六角の封印と数字で、そこに姿を描き込む余地は無い（マスは実機で
// 40〜50px しかなく、守りの数字と体力の粒で既に埋まっている）。姿は盤面の外、
// 決着画面でだけ見せる。

/// 描画の層。[fill] を塗り、[hole] でくり抜き、[glow] を上に載せる。
///
/// くり抜きは背景色で塗るのではなく [BlendMode.clear] で抜いている。
/// どの色のパネルの上に置いても、穴が背景とずれない。
enum _Layer { fill, hole, glow }

sealed class _Op {
  const _Op(this.layer);
  final _Layer layer;
}

class _Poly extends _Op {
  const _Poly(super.layer, this.points);
  final List<Offset> points;
}

class _Circle extends _Op {
  const _Circle(super.layer, this.center, this.radius);
  final Offset center;
  final double radius;
}

class _Line extends _Op {
  const _Line(super.layer, this.points, this.width);
  final List<Offset> points;
  final double width;
}
'''

TAIL = '''
/// 敵の姿。守りの厚さがそのまま格になっていて、厚い敵ほど枠を使い切る。
class _FoeArt {
  const _FoeArt(this.name, this.ops);

  final String name;
  final List<_Op> ops;
}

const _byWard = <int, _FoeArt>{
%(MAP)s
};

_FoeArt _artFor(int ward) => _byWard[ward.clamp(Board.minWard, Board.maxWard)]!;

/// 守り [ward] の敵の呼び名。
String foeNameFor(int ward) => _artFor(ward).name;

/// 敵の姿を1体描く。色は [Palette.wardColorFor] から取るので、
/// 盤面に出ている封印の色と必ず揃う。
class FoePortrait extends StatelessWidget {
  const FoePortrait({
    super.key,
    required this.ward,
    required this.size,
    this.faded = false,
  });

  final int ward;
  final double size;

  /// 討ち取った敵。沈めて「もう居ない」ことを見せる。
  final bool faded;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _FoePainter(
          art: _artFor(ward),
          tint: Palette.wardColorFor(ward),
          faded: faded,
        ),
      ),
    );
  }
}

class _FoePainter extends CustomPainter {
  const _FoePainter({
    required this.art,
    required this.tint,
    required this.faded,
  });

  final _FoeArt art;
  final Color tint;
  final bool faded;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final alpha = faded ? 0.3 : 1.0;
    final body = Color.lerp(tint, Palette.background, 0.2)!;
    final glow = Color.lerp(tint, Colors.white, 0.45)!;

    // くり抜きのために層を切る。これが無いと clear が背面のパネルまで抜く。
    canvas.saveLayer(Offset.zero & size, Paint());
    _run(canvas, s, _Layer.fill, body.withValues(alpha: alpha));
    _run(canvas, s, _Layer.hole, const Color(0x00000000), BlendMode.clear);
    canvas.restore();

    _run(canvas, s, _Layer.glow, glow.withValues(alpha: alpha));
  }

  void _run(
    Canvas canvas,
    double s,
    _Layer layer,
    Color color, [
    BlendMode mode = BlendMode.srcOver,
  ]) {
    Paint base() => Paint()
      ..isAntiAlias = true
      ..color = color
      ..blendMode = mode;

    for (final op in art.ops) {
      if (op.layer != layer) continue;
      switch (op) {
        case _Poly(:final points):
          canvas.drawPath(
            Path()..addPolygon([for (final p in points) p * s], true),
            base(),
          );
        case _Circle(:final center, :final radius):
          canvas.drawCircle(center * s, radius * s, base());
        case _Line(:final points, :final width):
          final path = Path()..moveTo(points.first.dx * s, points.first.dy * s);
          for (final p in points.skip(1)) {
            path.lineTo(p.dx * s, p.dy * s);
          }
          canvas.drawPath(
            path,
            base()
              ..style = PaintingStyle.stroke
              ..strokeWidth = width * s
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
      }
    }
  }

  @override
  bool shouldRepaint(_FoePainter old) =>
      old.art != art || old.tint != tint || old.faded != faded;
}
'''

parts = [HEAD]
for ward in sorted(FOES):
    name, ops = FOES[ward]
    parts.append(f'\n/// 守り{ward}・{name}。\nconst {VAR[ward]} = <_Op>[\n{ops_of(ops)}\n];\n')

mapping = '\n'.join(
    f"  {w}: _FoeArt('{FOES[w][0]}', {VAR[w]})," for w in sorted(FOES)
)
parts.append(TAIL % {'MAP': mapping})

# リポジトリのどこから呼ばれても、置き場所は1つに決める。
out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   '..', '..', 'lib', 'ui', 'foe_art.dart')
out = os.path.normpath(out)
with open(out, 'w') as f:
    f.write(''.join(parts))
print('書き出した:', out)
