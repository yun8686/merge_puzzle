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
  }) : age = 0;

  Offset position;
  Offset velocity;
  Color color;
  double size;
  double life;
  double age;

  double get t => (age / life).clamp(0.0, 1.0);
  bool get dead => age >= life;
}

class ParticleField {
  final List<Particle> particles = <Particle>[];
  final Random _rng = Random();

  bool get isEmpty => particles.isEmpty;

  void burst(Offset at, Color color, {int count = 8, double power = 140}) {
    for (var i = 0; i < count; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = power * (0.35 + _rng.nextDouble() * 0.9);
      particles.add(
        Particle(
          position: at,
          velocity: Offset(cos(angle), sin(angle)) * speed,
          color: color,
          size: 2.5 + _rng.nextDouble() * 4.5,
          life: 0.45 + _rng.nextDouble() * 0.45,
        ),
      );
    }
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
  }

  void clear() => particles.clear();
}

class ParticlePainter extends CustomPainter {
  ParticlePainter(this.field) : super(repaint: null);

  final ParticleField field;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..blendMode = BlendMode.plus;
    for (final p in field.particles) {
      final fade = 1 - p.t;
      paint.color = p.color.withValues(alpha: fade.clamp(0.0, 1.0));
      canvas.drawCircle(p.position, p.size * (0.4 + fade * 0.8), paint);
    }
  }

  @override
  bool shouldRepaint(covariant ParticlePainter oldDelegate) => true;
}
