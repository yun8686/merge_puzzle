import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/board.dart';
import '../game/game_controller.dart';
import 'particles.dart';
import 'theme.dart';

/// なぞり入力と、消したときの演出をまとめて持つ盤面ウィジェット。
/// 座標計算がここにしか無いので、エフェクトも全部ここで鳴らす。
class BoardView extends StatefulWidget {
  const BoardView({super.key, required this.controller});

  final GameController controller;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> with TickerProviderStateMixin {
  final ParticleField _particles = ParticleField();
  final List<_Pop> _pops = <_Pop>[];
  final List<_Popup> _popups = <_Popup>[];

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _shake = 0;
  double _shakeTime = 0;

  double _cell = 0;
  double _originX = 0;
  double _originY = 0;

  int _seq = 0;
  _Rank? _rank;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _ensureTicking() {
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    var dt = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    dt = dt.clamp(0.0, 0.05);

    _particles.update(dt);
    if (_shake > 0.2) {
      _shakeTime += dt;
      _shake *= exp(-9 * dt);
    } else {
      _shake = 0;
    }

    if (_particles.isEmpty && _shake == 0) {
      _ticker.stop();
    }
    if (mounted) setState(() {});
  }

  Offset _centerOf(Cell c) => Offset(
        _originX + (c.col + 0.5) * _cell,
        _originY + (c.row + 0.5) * _cell,
      );

  Cell? _cellAt(Offset local) {
    if (_cell <= 0) return null;
    final x = local.dx - _originX;
    final y = local.dy - _originY;
    final board = widget.controller.board;
    if (x < 0 || y < 0 || x >= _cell * board.cols || y >= _cell * board.rows) {
      return null;
    }
    final col = (x / _cell).floor();
    final row = (y / _cell).floor();
    // マスの中心付近でのみ反応させ、境界をなぞったときのチラつきを防ぐ。
    final dx = x - (col + 0.5) * _cell;
    final dy = y - (row + 0.5) * _cell;
    if (sqrt(dx * dx + dy * dy) > _cell * 0.46) return null;
    return Cell(row, col);
  }

  void _onPanStart(DragStartDetails d) {
    final c = _cellAt(d.localPosition);
    if (c == null) return;
    widget.controller.beginPath(c);
    HapticFeedback.selectionClick();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final c = _cellAt(d.localPosition);
    if (c == null) return;
    if (widget.controller.extendPath(c)) {
      HapticFeedback.selectionClick();
    }
  }

  void _onPanEnd(DragEndDetails d) {
    final result = widget.controller.commitPath();
    if (result == null) return;

    if (result.length >= 8) {
      HapticFeedback.heavyImpact();
    } else if (result.length >= 5) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }

    for (var i = 0; i < result.cells.length; i++) {
      final cell = result.cells[i];
      final value = result.values[i];
      _pops.add(
        _Pop(
          id: _seq++,
          value: value,
          isOdd: value.isOdd,
          center: _centerOf(cell),
          delay: Duration(milliseconds: 26 * i),
        ),
      );
    }

    _popups.add(
      _Popup(
        id: _seq++,
        center: _centerOf(result.endCell),
        gained: result.gained,
        length: result.length,
      ),
    );

    final rank = ChainRank.of(result.length);
    if (rank != null) {
      _rank = _Rank(id: _seq++, rank: rank);
    }

    _shake = (result.length * 2.4).clamp(3.0, 26.0);
    _shakeTime = 0;
    _ensureTicking();
    setState(() {});
  }

  void _burstAt(Offset center, bool isOdd) {
    _particles.burst(
      center,
      Palette.baseFor(isOdd),
      count: 9,
      power: _cell * 4.2,
    );
    _ensureTicking();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final board = controller.board;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = min(
          constraints.maxWidth / board.cols,
          constraints.maxHeight / board.rows,
        );
        final boardW = cell * board.cols;
        final boardH = cell * board.rows;
        _cell = cell;
        _originX = (constraints.maxWidth - boardW) / 2;
        _originY = (constraints.maxHeight - boardH) / 2;

        final shakeOffset = _shake == 0
            ? Offset.zero
            : Offset(
                sin(_shakeTime * 71) * _shake,
                cos(_shakeTime * 59) * _shake * 0.65,
              );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onPanCancel: controller.cancelPath,
          child: Transform.translate(
            offset: shakeOffset,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: _originX - cell * 0.08,
                  top: _originY - cell * 0.08,
                  width: boardW + cell * 0.16,
                  height: boardH + cell * 0.16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Palette.boardBg,
                      borderRadius: BorderRadius.circular(cell * 0.4),
                    ),
                  ),
                ),
                if (controller.hintPath.isNotEmpty)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RibbonPainter(
                        points:
                            controller.hintPath.map(_centerOf).toList(),
                        core: Colors.white.withValues(alpha: 0.35),
                        glow: Colors.white.withValues(alpha: 0.2),
                        width: cell * 0.18,
                      ),
                    ),
                  ),
                ..._buildTiles(controller, cell),
                // 経路はタイルの上に細く引く。下に敷くとタイルの隙間しか見えず、
                // どの順でなぞったのかが読み取れなくなる。
                if (controller.path.length >= 2)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _RibbonPainter(
                          points: controller.path.map(_centerOf).toList(),
                          core: const Color(0xD9FFF7E0),
                          glow: Palette.glowFor(
                            board.tileAt(controller.path.last)?.isOdd ?? true,
                          ),
                          width: cell * 0.15,
                        ),
                      ),
                    ),
                  ),
                for (final pop in _pops)
                  Positioned(
                    left: pop.center.dx - cell / 2,
                    top: pop.center.dy - cell / 2,
                    width: cell,
                    height: cell,
                    child: _PopTile(
                      key: ValueKey('pop-${pop.id}'),
                      value: pop.value,
                      isOdd: pop.isOdd,
                      size: cell,
                      delay: pop.delay,
                      onBurst: () => _burstAt(pop.center, pop.isOdd),
                      onDone: () {
                        _pops.removeWhere((p) => p.id == pop.id);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: ParticlePainter(_particles)),
                  ),
                ),
                for (final popup in _popups)
                  Positioned(
                    left: popup.center.dx - cell * 1.5,
                    top: popup.center.dy - cell * 0.9,
                    width: cell * 3,
                    height: cell * 1.2,
                    child: IgnorePointer(
                      child: _ScorePopup(
                        key: ValueKey('popup-${popup.id}'),
                        gained: popup.gained,
                        length: popup.length,
                        onDone: () {
                          _popups.removeWhere((p) => p.id == popup.id);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ),
                if (_rank != null)
                  Positioned(
                    left: _originX,
                    top: _originY + boardH * 0.34,
                    width: boardW,
                    child: IgnorePointer(
                      child: _RankBanner(
                        key: ValueKey('rank-${_rank!.id}'),
                        rank: _rank!.rank,
                        onDone: () {
                          _rank = null;
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildTiles(GameController controller, double cell) {
    final board = controller.board;
    final widgets = <Widget>[];
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        final tile = board.grid[r][c];
        if (tile == null) continue;
        final at = Cell(r, c);
        widgets.add(
          AnimatedPositioned(
            key: ValueKey('tile-${tile.id}'),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: _originX + c * cell,
            top: _originY + r * cell,
            width: cell,
            height: cell,
            child: TileWidget(
              tile: tile,
              size: cell,
              selected: controller.isSelected(at),
              candidate: controller.isCandidate(at),
              fresh: controller.freshTileIds.contains(tile.id),
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

class _Pop {
  _Pop({
    required this.id,
    required this.value,
    required this.isOdd,
    required this.center,
    required this.delay,
  });

  final int id;
  final int value;
  final bool isOdd;
  final Offset center;
  final Duration delay;
}

class _Popup {
  _Popup({
    required this.id,
    required this.center,
    required this.gained,
    required this.length,
  });

  final int id;
  final Offset center;
  final int gained;
  final int length;
}

class _Rank {
  _Rank({required this.id, required this.rank});

  final int id;
  final ChainRank rank;
}

/// 通常のタイル。降ってくる登場アニメーションを自前で持つ。
class TileWidget extends StatefulWidget {
  const TileWidget({
    super.key,
    required this.tile,
    required this.size,
    required this.selected,
    required this.candidate,
    required this.fresh,
  });

  final Tile tile;
  final double size;
  final bool selected;
  final bool candidate;
  final bool fresh;

  @override
  State<TileWidget> createState() => _TileWidgetState();
}

class _TileWidgetState extends State<TileWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    if (widget.fresh) {
      _entry.forward();
    } else {
      _entry.value = 1;
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final isOdd = widget.tile.isOdd;
    final glow = Palette.glowFor(isOdd);

    final face = AnimatedScale(
      scale: widget.selected ? 1.1 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutBack,
      child: Container(
        margin: EdgeInsets.all(size * 0.06),
        decoration: BoxDecoration(
          gradient: Palette.gradientFor(isOdd),
          borderRadius: BorderRadius.circular(size * 0.26),
          boxShadow: [
            BoxShadow(
              color: glow.withValues(alpha: widget.selected ? 0.8 : 0.3),
              blurRadius: widget.selected ? size * 0.55 : size * 0.22,
              spreadRadius: widget.selected ? size * 0.05 : 0,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.selected)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 0.26),
                  border: Border.all(
                    color: Colors.white,
                    width: size * 0.06,
                  ),
                ),
              ),
            if (widget.candidate && !widget.selected)
              _CandidatePulse(size: size),
            Padding(
              padding: EdgeInsets.all(size * 0.2),
              child: FittedBox(
                child: Text(
                  '${widget.tile.value}',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.5,
                    height: 1,
                    shadows: const [
                      Shadow(color: Color(0x66000000), blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _entry,
      builder: (context, child) {
        final e = Curves.easeOutCubic.transform(_entry.value);
        return Transform.translate(
          offset: Offset(0, (1 - e) * -size * 2.6),
          child: Opacity(opacity: e.clamp(0.0, 1.0), child: child),
        );
      },
      child: face,
    );
  }
}

/// 次に繋げられるマスを示す、静かに脈打つリング。ルールを説明しなくても伝わる。
class _CandidatePulse extends StatefulWidget {
  const _CandidatePulse({required this.size});

  final double size;

  @override
  State<_CandidatePulse> createState() => _CandidatePulseState();
}

class _CandidatePulseState extends State<_CandidatePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.size * 0.26),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25 + 0.45 * t),
              width: widget.size * 0.045,
            ),
          ),
        );
      },
    );
  }
}

/// 消える瞬間のタイル。膨らんでから弾ける。
class _PopTile extends StatefulWidget {
  const _PopTile({
    super.key,
    required this.value,
    required this.isOdd,
    required this.size,
    required this.delay,
    required this.onBurst,
    required this.onDone,
  });

  final int value;
  final bool isOdd;
  final double size;
  final Duration delay;
  final VoidCallback onBurst;
  final VoidCallback onDone;

  @override
  State<_PopTile> createState() => _PopTileState();
}

class _PopTileState extends State<_PopTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    Future<void>.delayed(widget.delay, () {
      if (!mounted) return;
      setState(() => _started = true);
      widget.onBurst();
      _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        // 一瞬膨らんでから消える。溜めがあると弾けた感じが出る。
        final scale = t < 0.3
            ? 1 + (t / 0.3) * 0.35
            : 1.35 * (1 - ((t - 0.3) / 0.7)).clamp(0.0, 1.0);
        return Opacity(
          opacity: _started ? (1 - t * t).clamp(0.0, 1.0) : 1.0,
          child: Transform.scale(scale: _started ? scale : 1.0, child: child),
        );
      },
      child: Container(
        margin: EdgeInsets.all(size * 0.06),
        decoration: BoxDecoration(
          gradient: Palette.gradientFor(widget.isOdd),
          borderRadius: BorderRadius.circular(size * 0.26),
          boxShadow: [
            BoxShadow(
              color: Palette.glowFor(widget.isOdd).withValues(alpha: 0.7),
              blurRadius: size * 0.5,
            ),
          ],
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(size * 0.2),
            child: FittedBox(
              child: Text(
                '${widget.value}',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.5,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScorePopup extends StatefulWidget {
  const _ScorePopup({
    super.key,
    required this.gained,
    required this.length,
    required this.onDone,
  });

  final int gained;
  final int length;
  final VoidCallback onDone;

  @override
  State<_ScorePopup> createState() => _ScorePopupState();
}

class _ScorePopupState extends State<_ScorePopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..forward();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Transform.translate(
          offset: Offset(0, -t * 46),
          child: Opacity(
            opacity: (1 - t * t).clamp(0.0, 1.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '+${widget.gained}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFF0B8),
                    fontWeight: FontWeight.w900,
                    fontSize: 26,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
                Text(
                  '${widget.length} CHAIN',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.6,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RankBanner extends StatefulWidget {
  const _RankBanner({super.key, required this.rank, required this.onDone});

  final ChainRank rank;
  final VoidCallback onDone;

  @override
  State<_RankBanner> createState() => _RankBannerState();
}

class _RankBannerState extends State<_RankBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..forward();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final pop = t < 0.25
            ? Curves.easeOutBack.transform(t / 0.25)
            : 1.0;
        return Opacity(
          opacity: t > 0.7 ? (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0) : 1.0,
          child: Transform.scale(
            scale: 0.6 + pop * 0.4,
            child: Text(
              widget.rank.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.rank.color,
                fontWeight: FontWeight.w900,
                fontSize: 40,
                letterSpacing: 2,
                shadows: const [
                  Shadow(color: Colors.black, blurRadius: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter({
    required this.points,
    required this.core,
    required this.glow,
    required this.width,
  });

  final List<Offset> points;
  final Color core;
  final Color glow;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width * 1.9
      ..color = glow.withValues(alpha: 0.5)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.75);
    canvas.drawPath(path, glowPaint);

    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width
      ..color = core;
    canvas.drawPath(path, corePaint);
  }

  @override
  bool shouldRepaint(covariant _RibbonPainter old) =>
      old.points != points || old.core != core || old.glow != glow;
}
