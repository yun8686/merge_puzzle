import 'package:flutter/material.dart';

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
// 従者は輪郭だけ、招ける魔導士は塗り潰し。同じ相でも格の差が形で出る。
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

/// 熱の従者。
const _squireHeat = <_Op>[
  _Poly(_Layer.fill, [
    Offset(0.527, 0.200), Offset(0.592, 0.345),
    Offset(0.689, 0.510), Offset(0.765, 0.662),
    Offset(0.748, 0.761), Offset(0.684, 0.827),
    Offset(0.592, 0.860), Offset(0.495, 0.867),
    Offset(0.392, 0.847), Offset(0.306, 0.791),
    Offset(0.252, 0.695), Offset(0.241, 0.576),
    Offset(0.306, 0.411), Offset(0.360, 0.537),
    Offset(0.446, 0.385),
  ]),
  _Poly(_Layer.hole, [
    Offset(0.515, 0.360), Offset(0.551, 0.441),
    Offset(0.605, 0.534), Offset(0.647, 0.619),
    Offset(0.638, 0.675), Offset(0.602, 0.712),
    Offset(0.551, 0.730), Offset(0.497, 0.734),
    Offset(0.440, 0.723), Offset(0.392, 0.691),
    Offset(0.362, 0.638), Offset(0.356, 0.571),
    Offset(0.392, 0.478), Offset(0.422, 0.549),
    Offset(0.470, 0.464),
  ]),
];

/// 冷の従者。
const _squireCold = <_Op>[
  _Circle(_Layer.fill, Offset(0.500, 0.609), 0.211),
  _Poly(_Layer.fill, [
    Offset(0.500, 0.180), Offset(0.692, 0.644),
    Offset(0.308, 0.644),
  ]),
  _Circle(_Layer.hole, Offset(0.500, 0.575), 0.115),
  _Poly(_Layer.hole, [
    Offset(0.500, 0.340), Offset(0.605, 0.594),
    Offset(0.395, 0.594),
  ]),
];

/// 雷の従者。
const _squireBolt = <_Op>[
  _Poly(_Layer.fill, [
    Offset(0.586, 0.195), Offset(0.275, 0.572),
    Offset(0.468, 0.572), Offset(0.392, 0.845),
    Offset(0.725, 0.455), Offset(0.522, 0.455),
  ]),
  _Poly(_Layer.hole, [
    Offset(0.540, 0.365), Offset(0.395, 0.545),
    Offset(0.485, 0.545), Offset(0.450, 0.675),
    Offset(0.605, 0.489), Offset(0.510, 0.489),
  ]),
];

/// 焔の魔導士。
const _ember = <_Op>[
  _Poly(_Layer.fill, [
    Offset(0.534, 0.080), Offset(0.616, 0.265),
    Offset(0.738, 0.475), Offset(0.833, 0.668),
    Offset(0.813, 0.794), Offset(0.731, 0.878),
    Offset(0.616, 0.920), Offset(0.493, 0.928),
    Offset(0.364, 0.903), Offset(0.255, 0.832),
    Offset(0.187, 0.710), Offset(0.174, 0.559),
    Offset(0.255, 0.349), Offset(0.323, 0.508),
    Offset(0.432, 0.315),
  ]),
  _Circle(_Layer.glow, Offset(0.500, 0.630), 0.115),
];

/// 烈火の魔導士。
const _blaze = <_Op>[
  _Poly(_Layer.fill, [
    Offset(0.205, 0.280), Offset(0.239, 0.412),
    Offset(0.291, 0.562), Offset(0.332, 0.700),
    Offset(0.323, 0.790), Offset(0.289, 0.850),
    Offset(0.239, 0.880), Offset(0.187, 0.886),
    Offset(0.132, 0.868), Offset(0.086, 0.817),
    Offset(0.057, 0.730), Offset(0.051, 0.622),
    Offset(0.086, 0.472), Offset(0.115, 0.586),
    Offset(0.161, 0.448),
  ]),
  _Poly(_Layer.fill, [
    Offset(0.825, 0.280), Offset(0.859, 0.412),
    Offset(0.912, 0.562), Offset(0.952, 0.700),
    Offset(0.943, 0.790), Offset(0.909, 0.850),
    Offset(0.859, 0.880), Offset(0.807, 0.886),
    Offset(0.752, 0.868), Offset(0.706, 0.817),
    Offset(0.677, 0.730), Offset(0.671, 0.622),
    Offset(0.706, 0.472), Offset(0.735, 0.586),
    Offset(0.781, 0.448),
  ]),
  _Poly(_Layer.fill, [
    Offset(0.526, 0.080), Offset(0.590, 0.265),
    Offset(0.685, 0.475), Offset(0.760, 0.668),
    Offset(0.744, 0.794), Offset(0.680, 0.878),
    Offset(0.590, 0.920), Offset(0.495, 0.928),
    Offset(0.394, 0.903), Offset(0.309, 0.832),
    Offset(0.256, 0.710), Offset(0.246, 0.559),
    Offset(0.309, 0.349), Offset(0.362, 0.508),
    Offset(0.447, 0.315),
  ]),
  _Circle(_Layer.glow, Offset(0.500, 0.640), 0.100),
];

/// 風の魔導士。
const _gale = <_Op>[
  _Line(_Layer.fill, [Offset(0.140, 0.200), Offset(0.600, 0.200)], 0.080),
  _Line(_Layer.fill, [
    Offset(0.121, 0.659), Offset(0.277, 0.659),
    Offset(0.268, 0.573), Offset(0.285, 0.490),
    Offset(0.324, 0.418), Offset(0.382, 0.363),
    Offset(0.452, 0.329), Offset(0.526, 0.318),
    Offset(0.598, 0.329), Offset(0.661, 0.361),
    Offset(0.710, 0.409), Offset(0.741, 0.467),
    Offset(0.753, 0.529), Offset(0.745, 0.590),
    Offset(0.720, 0.644), Offset(0.682, 0.685),
    Offset(0.634, 0.712), Offset(0.583, 0.723),
    Offset(0.534, 0.718), Offset(0.491, 0.699),
    Offset(0.457, 0.669), Offset(0.435, 0.632),
    Offset(0.427, 0.592), Offset(0.430, 0.554),
    Offset(0.445, 0.521), Offset(0.467, 0.496),
    Offset(0.495, 0.481), Offset(0.523, 0.475),
    Offset(0.550, 0.479), Offset(0.572, 0.490),
    Offset(0.587, 0.506), Offset(0.596, 0.524),
  ], 0.090),
];

/// 氷雨の魔導士。
const _rime = <_Op>[
  _Circle(_Layer.fill, Offset(0.280, 0.428), 0.132),
  _Poly(_Layer.fill, [
    Offset(0.280, 0.160), Offset(0.400, 0.450),
    Offset(0.160, 0.450),
  ]),
  _Circle(_Layer.fill, Offset(0.700, 0.498), 0.112),
  _Poly(_Layer.fill, [
    Offset(0.700, 0.270), Offset(0.802, 0.516),
    Offset(0.598, 0.516),
  ]),
  _Circle(_Layer.fill, Offset(0.480, 0.782), 0.158),
  _Poly(_Layer.fill, [
    Offset(0.480, 0.460), Offset(0.624, 0.808),
    Offset(0.336, 0.808),
  ]),
  _Circle(_Layer.glow, Offset(0.480, 0.780), 0.075),
];

/// 霜の魔導士。
const _frost = <_Op>[
  _Line(_Layer.fill, [Offset(0.500, 0.900), Offset(0.500, 0.100)], 0.070),
  _Line(_Layer.fill, [Offset(0.846, 0.700), Offset(0.154, 0.300)], 0.070),
  _Line(_Layer.fill, [Offset(0.846, 0.300), Offset(0.154, 0.700)], 0.070),
  _Line(_Layer.fill, [Offset(0.500, 0.260), Offset(0.387, 0.171)], 0.057),
  _Line(_Layer.fill, [Offset(0.500, 0.260), Offset(0.613, 0.171)], 0.057),
  _Line(_Layer.fill, [Offset(0.292, 0.380), Offset(0.159, 0.434)], 0.057),
  _Line(_Layer.fill, [Offset(0.292, 0.380), Offset(0.272, 0.237)], 0.057),
  _Line(_Layer.fill, [Offset(0.292, 0.620), Offset(0.272, 0.763)], 0.057),
  _Line(_Layer.fill, [Offset(0.292, 0.620), Offset(0.159, 0.566)], 0.057),
  _Line(_Layer.fill, [Offset(0.500, 0.740), Offset(0.613, 0.829)], 0.057),
  _Line(_Layer.fill, [Offset(0.500, 0.740), Offset(0.387, 0.829)], 0.057),
  _Line(_Layer.fill, [Offset(0.708, 0.620), Offset(0.841, 0.566)], 0.057),
  _Line(_Layer.fill, [Offset(0.708, 0.620), Offset(0.728, 0.763)], 0.057),
  _Line(_Layer.fill, [Offset(0.708, 0.380), Offset(0.728, 0.237)], 0.057),
  _Line(_Layer.fill, [Offset(0.708, 0.380), Offset(0.841, 0.434)], 0.057),
  _Circle(_Layer.glow, Offset(0.500, 0.500), 0.085),
];

/// 雷の魔導士。
const _storm = <_Op>[
  _Circle(_Layer.fill, Offset(0.334, 0.304), 0.115),
  _Circle(_Layer.fill, Offset(0.660, 0.314), 0.101),
  _Circle(_Layer.fill, Offset(0.500, 0.242), 0.158),
  _Poly(_Layer.fill, [
    Offset(0.186, 0.304), Offset(0.807, 0.314),
    Offset(0.807, 0.414), Offset(0.186, 0.414),
  ]),
  _Poly(_Layer.fill, [
    Offset(0.580, 0.470), Offset(0.290, 0.760),
    Offset(0.471, 0.760), Offset(0.399, 0.970),
    Offset(0.710, 0.670), Offset(0.521, 0.670),
  ]),
];

/// 盾の魔導士。
const _aegis = <_Op>[
  _Poly(_Layer.fill, [
    Offset(0.170, 0.190), Offset(0.830, 0.190),
    Offset(0.830, 0.530), Offset(0.500, 0.890),
    Offset(0.170, 0.530),
  ]),
  _Line(_Layer.glow, [
    Offset(0.320, 0.450), Offset(0.500, 0.620),
    Offset(0.680, 0.450),
  ], 0.085),
];

const _byKind = <MageKind, List<_Op>>{
  MageKind.squireHeat: _squireHeat,
  MageKind.squireCold: _squireCold,
  MageKind.squireBolt: _squireBolt,
  MageKind.ember: _ember,
  MageKind.blaze: _blaze,
  MageKind.gale: _gale,
  MageKind.rime: _rime,
  MageKind.frost: _frost,
  MageKind.storm: _storm,
  MageKind.aegis: _aegis,
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
