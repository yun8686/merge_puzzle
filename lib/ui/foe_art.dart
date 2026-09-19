import 'package:flutter/material.dart';

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

/// 守り3・小鬼。
const _imp = <_Op>[
  _Poly(_Layer.fill, [
    Offset(0.350, 0.340), Offset(0.270, 0.150),
    Offset(0.450, 0.270),
  ]),
  _Poly(_Layer.fill, [
    Offset(0.650, 0.340), Offset(0.730, 0.150),
    Offset(0.550, 0.270),
  ]),
  _Poly(_Layer.fill, [
    Offset(0.310, 0.400), Offset(0.150, 0.490),
    Offset(0.320, 0.550),
  ]),
  _Poly(_Layer.fill, [
    Offset(0.690, 0.400), Offset(0.850, 0.490),
    Offset(0.680, 0.550),
  ]),
  _Circle(_Layer.fill, Offset(0.500, 0.450), 0.210),
  _Poly(_Layer.fill, [
    Offset(0.390, 0.600), Offset(0.610, 0.600),
    Offset(0.670, 0.900), Offset(0.330, 0.900),
  ]),
  _Circle(_Layer.hole, Offset(0.430, 0.430), 0.050),
  _Circle(_Layer.hole, Offset(0.570, 0.430), 0.050),
  _Circle(_Layer.glow, Offset(0.430, 0.430), 0.026),
  _Circle(_Layer.glow, Offset(0.570, 0.430), 0.026),
];

/// 守り4・骸。
const _bones = <_Op>[
  _Circle(_Layer.fill, Offset(0.500, 0.400), 0.300),
  _Poly(_Layer.fill, [
    Offset(0.310, 0.600), Offset(0.690, 0.600),
    Offset(0.650, 0.880), Offset(0.350, 0.880),
  ]),
  _Circle(_Layer.hole, Offset(0.380, 0.380), 0.095),
  _Circle(_Layer.hole, Offset(0.620, 0.380), 0.095),
  _Poly(_Layer.hole, [
    Offset(0.500, 0.480), Offset(0.445, 0.580),
    Offset(0.555, 0.580),
  ]),
  _Line(_Layer.hole, [Offset(0.440, 0.620), Offset(0.440, 0.880)], 0.035),
  _Line(_Layer.hole, [Offset(0.560, 0.620), Offset(0.560, 0.880)], 0.035),
  _Line(_Layer.hole, [Offset(0.330, 0.740), Offset(0.670, 0.740)], 0.030),
  _Circle(_Layer.glow, Offset(0.380, 0.380), 0.034),
  _Circle(_Layer.glow, Offset(0.620, 0.380), 0.034),
];

/// 守り5・影。
const _shade = <_Op>[
  _Poly(_Layer.fill, [
    Offset(0.500, 0.040), Offset(0.720, 0.170),
    Offset(0.800, 0.440), Offset(0.900, 0.960),
    Offset(0.720, 0.860), Offset(0.600, 0.960),
    Offset(0.500, 0.860), Offset(0.400, 0.960),
    Offset(0.280, 0.860), Offset(0.100, 0.960),
    Offset(0.200, 0.440), Offset(0.280, 0.170),
  ]),
  _Circle(_Layer.hole, Offset(0.500, 0.340), 0.175),
  _Circle(_Layer.glow, Offset(0.430, 0.330), 0.042),
  _Circle(_Layer.glow, Offset(0.570, 0.330), 0.042),
];

/// 守り6・石像。
const _golem = <_Op>[
  _Poly(_Layer.fill, [
    Offset(0.360, 0.050), Offset(0.640, 0.050),
    Offset(0.660, 0.270), Offset(0.340, 0.270),
  ]),
  _Poly(_Layer.fill, [
    Offset(0.430, 0.260), Offset(0.570, 0.260),
    Offset(0.570, 0.370), Offset(0.430, 0.370),
  ]),
  _Poly(_Layer.fill, [
    Offset(0.060, 0.350), Offset(0.940, 0.350),
    Offset(0.940, 0.670), Offset(0.790, 0.670),
    Offset(0.790, 0.970), Offset(0.210, 0.970),
    Offset(0.210, 0.670), Offset(0.060, 0.670),
  ]),
  _Poly(_Layer.hole, [
    Offset(0.420, 0.130), Offset(0.470, 0.130),
    Offset(0.470, 0.220), Offset(0.420, 0.220),
  ]),
  _Poly(_Layer.hole, [
    Offset(0.530, 0.130), Offset(0.580, 0.130),
    Offset(0.580, 0.220), Offset(0.530, 0.220),
  ]),
  _Line(_Layer.hole, [
    Offset(0.550, 0.420), Offset(0.460, 0.600),
    Offset(0.570, 0.780), Offset(0.520, 0.970),
  ], 0.032),
  _Poly(_Layer.glow, [
    Offset(0.420, 0.130), Offset(0.470, 0.130),
    Offset(0.470, 0.220), Offset(0.420, 0.220),
  ]),
  _Poly(_Layer.glow, [
    Offset(0.530, 0.130), Offset(0.580, 0.130),
    Offset(0.580, 0.220), Offset(0.530, 0.220),
  ]),
];

/// 守り7・獣。
const _beast = <_Op>[
  _Poly(_Layer.fill, [
    Offset(0.220, 0.360), Offset(0.080, 0.020),
    Offset(0.440, 0.180),
  ]),
  _Poly(_Layer.fill, [
    Offset(0.780, 0.360), Offset(0.920, 0.020),
    Offset(0.560, 0.180),
  ]),
  _Circle(_Layer.fill, Offset(0.500, 0.440), 0.290),
  _Poly(_Layer.fill, [
    Offset(0.370, 0.580), Offset(0.630, 0.580),
    Offset(0.590, 0.840), Offset(0.410, 0.840),
  ]),
  _Poly(_Layer.fill, [
    Offset(0.410, 0.820), Offset(0.480, 0.820),
    Offset(0.445, 0.980),
  ]),
  _Poly(_Layer.fill, [
    Offset(0.590, 0.820), Offset(0.520, 0.820),
    Offset(0.555, 0.980),
  ]),
  _Poly(_Layer.hole, [
    Offset(0.280, 0.330), Offset(0.460, 0.410),
    Offset(0.280, 0.460),
  ]),
  _Poly(_Layer.hole, [
    Offset(0.720, 0.330), Offset(0.540, 0.410),
    Offset(0.720, 0.460),
  ]),
  _Circle(_Layer.hole, Offset(0.465, 0.680), 0.026),
  _Circle(_Layer.hole, Offset(0.535, 0.680), 0.026),
  _Poly(_Layer.glow, [
    Offset(0.320, 0.360), Offset(0.440, 0.410),
    Offset(0.320, 0.440),
  ]),
  _Poly(_Layer.glow, [
    Offset(0.680, 0.360), Offset(0.560, 0.410),
    Offset(0.680, 0.440),
  ]),
];

/// 守り8・竜。
const _wyrm = <_Op>[
  _Poly(_Layer.fill, [
    Offset(0.330, 0.300), Offset(0.000, 0.040),
    Offset(0.360, 0.170),
  ]),
  _Poly(_Layer.fill, [
    Offset(0.670, 0.300), Offset(1.000, 0.040),
    Offset(0.640, 0.170),
  ]),
  _Poly(_Layer.fill, [
    Offset(0.300, 0.400), Offset(0.040, 0.340),
    Offset(0.300, 0.500),
  ]),
  _Poly(_Layer.fill, [
    Offset(0.700, 0.400), Offset(0.960, 0.340),
    Offset(0.700, 0.500),
  ]),
  _Poly(_Layer.fill, [
    Offset(0.300, 0.220), Offset(0.500, 0.120),
    Offset(0.700, 0.220), Offset(0.840, 0.460),
    Offset(0.660, 0.580), Offset(0.640, 0.860),
    Offset(0.500, 0.980), Offset(0.360, 0.860),
    Offset(0.340, 0.580), Offset(0.160, 0.460),
  ]),
  _Poly(_Layer.hole, [
    Offset(0.260, 0.340), Offset(0.460, 0.440),
    Offset(0.260, 0.480),
  ]),
  _Poly(_Layer.hole, [
    Offset(0.740, 0.340), Offset(0.540, 0.440),
    Offset(0.740, 0.480),
  ]),
  _Circle(_Layer.hole, Offset(0.455, 0.740), 0.030),
  _Circle(_Layer.hole, Offset(0.545, 0.740), 0.030),
  _Poly(_Layer.glow, [
    Offset(0.300, 0.380), Offset(0.430, 0.440),
    Offset(0.300, 0.460),
  ]),
  _Poly(_Layer.glow, [
    Offset(0.700, 0.380), Offset(0.570, 0.440),
    Offset(0.700, 0.460),
  ]),
];

/// 敵の姿。守りの厚さがそのまま格になっていて、厚い敵ほど枠を使い切る。
class _FoeArt {
  const _FoeArt(this.name, this.ops);

  final String name;
  final List<_Op> ops;
}

const _byWard = <int, _FoeArt>{
  3: _FoeArt('小鬼', _imp),
  4: _FoeArt('骸', _bones),
  5: _FoeArt('影', _shade),
  6: _FoeArt('石像', _golem),
  7: _FoeArt('獣', _beast),
  8: _FoeArt('竜', _wyrm),
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
