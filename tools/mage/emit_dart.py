"""shapes.py から lib/ui/mage_art.dart を生成する。

プレビュー(Pillow)とアプリ(Flutter)が同じ座標を読むようにするための橋渡し。
Dart 側を手で書き写さない。tools/foe/emit_dart.py と同じ作り。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from shapes import MAGES, ORDER  # noqa: E402

LAYER = {'fill': '_Layer.fill', 'hole': '_Layer.hole', 'glow': '_Layer.glow'}


def pts(seq, indent):
    """点は2つずつ折り返す。1行に詰めると dart format の幅を超えて読めない。"""
    items = [f'Offset({x:.3f}, {y:.3f})' for x, y in seq]
    if len(items) <= 2:
        return '[' + ', '.join(items) + ']'
    pad = ' ' * (indent + 2)
    rows = [', '.join(items[i:i+2]) for i in range(0, len(items), 2)]
    return '[\n' + ''.join(f'{pad}{r},\n' for r in rows) + ' ' * indent + ']'


def ops_of(ops):
    out = []
    for op in ops:
        kind, layer = op[0], LAYER[op[1]]
        if kind == 'poly':
            out.append(f'  _Poly({layer}, {pts(op[2], 2)}),')
        elif kind == 'circle':
            cx, cy, r = op[2]
            out.append(
                f'  _Circle({layer}, Offset({cx:.3f}, {cy:.3f}), {r:.3f}),'
            )
        elif kind == 'line':
            out.append(f'  _Line({layer}, {pts(op[2], 2)}, {op[3]:.3f}),')
    return '\n'.join(out)


HEAD = '''import 'package:flutter/material.dart';

import '../game/party.dart';
import 'theme.dart';

// このファイルの座標は tools/mage/shapes.py から生成している。手で直さないこと。
// 形を変えるときは shapes.py を直し、tools/mage/preview.py で確かめてから
// tools/mage/emit_dart.py を走らせる。
//
// **姿は人ではなく、その魔導士の力そのもの**を描いている。編成の枠では 38px、
// 一党の帯では 22px まで縮むので、人の形では誰だか分からなくなる。炎・滴・
// 稲妻のように、輪郭だけで意味が分かる形に寄せてある。
//
// 見習いは輪郭だけ、招ける魔導士は塗り潰し。同じ相でも格の差が形で出る。
//
// 層の3つの型は tools/foe/ が作る foe_art.dart にも同じものがある。どちらも
// 生成物なので、共有せずそれぞれが持つ。片方を直してももう片方は動かない。

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
const _byKind = <MageKind, List<_Op>>{
%(MAP)s
};

/// 魔導士の姿を1つ描く。既定の色は相の色（[Palette.mageColor]）なので、
/// 盤面に敷かれるマナの色と必ず揃う。
class MagePortrait extends StatelessWidget {
  const MagePortrait({
    super.key,
    required this.kind,
    required this.size,
    this.tint,
  });

  final MageKind kind;
  final double size;

  /// 色の上書き。省くと相の色。
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MagePainter(
          ops: _byKind[kind]!,
          tint: tint ?? Palette.mageColor(kind),
        ),
      ),
    );
  }
}

class _MagePainter extends CustomPainter {
  const _MagePainter({required this.ops, required this.tint});

  final List<_Op> ops;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final body = Color.lerp(tint, Palette.background, 0.14)!;
    final glow = Color.lerp(tint, Colors.white, 0.55)!;

    // くり抜きのために層を切る。これが無いと clear が背面のパネルまで抜く。
    canvas.saveLayer(Offset.zero & size, Paint());
    _run(canvas, s, _Layer.fill, body);
    _run(canvas, s, _Layer.hole, const Color(0x00000000), BlendMode.clear);
    canvas.restore();

    _run(canvas, s, _Layer.glow, glow);
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

    for (final op in ops) {
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
  bool shouldRepaint(_MagePainter old) =>
      old.ops != ops || old.tint != tint;
}
'''

parts = [HEAD]
for key in ORDER:
    name, ops = MAGES[key]
    parts.append(f'\n/// {name}。\nconst _{key} = <_Op>[\n{ops_of(ops)}\n];\n')

mapping = '\n'.join(f'  MageKind.{k}: _{k},' for k in ORDER)
parts.append(TAIL % {'MAP': mapping})

# リポジトリのどこから呼ばれても、置き場所は1つに決める。
out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   '..', '..', 'lib', 'ui', 'mage_art.dart')
out = os.path.normpath(out)
with open(out, 'w') as f:
    f.write(''.join(parts))
print('書き出した:', out)
