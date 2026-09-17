import 'dart:math';

import 'package:flutter/material.dart';

/// 消したときに飛び散る粒。爽快感の主役なので軽くて数が出せる実装にする。
class Particle {
  Particle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.size,
    required this.life,
    this.spark = false,
  }) : age = 0;

  Offset position;
  Offset velocity;
  Color color;
  double size;
  double life;
  double age;

  /// 白く光る芯を持つ粒。数を絞って混ぜると、粒の塊に芯が生まれる。
  final bool spark;

  double get t => (age / life).clamp(0.0, 1.0);
  bool get dead => age >= life;
}

/// 消えた位置から広がる輪。粒より先に視界に入るので、
/// 「弾けた」瞬間の手応えはほぼこれが作っている。
class Shockwave {
  Shockwave({
    required this.center,
    required this.color,
    required this.maxRadius,
    required this.life,
    required this.width,
  }) : age = 0;

  final Offset center;
  final Color color;
  final double maxRadius;
  final double life;
  final double width;
  double age;

  double get t => (age / life).clamp(0.0, 1.0);
  bool get dead => age >= life;
}

class ParticleField {
  final List<Particle> particles = <Particle>[];
  final List<Shockwave> waves = <Shockwave>[];
  final Random _rng = Random();

  bool get isEmpty => particles.isEmpty && waves.isEmpty;

  void burst(Offset at, Color color, {int count = 8, double power = 140}) {
    for (var i = 0; i < count; i++) {
      // 角度を等分してから散らす。完全な乱数だと粒が偏って穴が空く。
      final angle = (i / count) * pi * 2 + _rng.nextDouble() * (pi * 2 / count);
      final speed = power * (0.35 + _rng.nextDouble() * 1.1);
      final spark = i % 4 == 0;
      particles.add(
        Particle(
          position: at,
          velocity: Offset(cos(angle), sin(angle)) * speed,
          color: color,
          size: spark
              ? 2.0 + _rng.nextDouble() * 2.5
              : 2.5 + _rng.nextDouble() * 5.0,
          life: 0.45 + _rng.nextDouble() * 0.5,
          spark: spark,
        ),
      );
    }
  }

  void shockwave(
    Offset at,
    Color color, {
    required double radius,
    double life = 0.42,
    double width = 4,
  }) {
    waves.add(
      Shockwave(
        center: at,
        color: color,
        maxRadius: radius,
        life: life,
        width: width,
      ),
    );
  }

  void update(double dt) {
    const gravity = 620.0;
    const drag = 1.9;
    for (final p in particles) {
      p.age += dt;
      p.velocity = Offset(
        p.velocity.dx * (1 - drag * dt),
        p.velocity.dy * (1 - drag * dt) + gravity * dt,
      );
      p.position += p.velocity * dt;
    }
    particles.removeWhere((p) => p.dead);

    for (final w in waves) {
      w.age += dt;
    }
    waves.removeWhere((w) => w.dead);
  }

  void clear() {
    particles.clear();
    waves.clear();
  }
}

class ParticlePainter extends CustomPainter {
  ParticlePainter(this.field) : super(repaint: null);

  final ParticleField field;

  @override
  void paint(Canvas canvas, Size size) {
    // 加算合成。粒が重なるほど白く飽和して、中心が光って見える。
    final paint = Paint()..blendMode = BlendMode.plus;

    for (final w in field.waves) {
      final t = Curves.easeOutCubic.transform(w.t);
      final fade = (1 - w.t) * (1 - w.t);
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = w.width * (1 - t * 0.75)
        ..color = w.color.withValues(alpha: fade.clamp(0.0, 1.0));
      canvas.drawCircle(w.center, w.maxRadius * t, paint);
    }

    paint
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;
    for (final p in field.particles) {
      final fade = (1 - p.t).clamp(0.0, 1.0);
      final radius = p.size * (0.4 + fade * 0.8);
      // 速度方向に伸ばして描く。静止した丸より、飛んでいる感じが出る。
      final tail = p.position - p.velocity * 0.018;
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 2
        ..color = p.color.withValues(alpha: fade * 0.85);
      canvas.drawLine(tail, p.position, paint);

      if (p.spark) {
        paint
          ..style = PaintingStyle.fill
          ..color = Colors.white.withValues(alpha: fade * fade);
        canvas.drawCircle(p.position, radius * 0.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ParticlePainter oldDelegate) => true;
}
