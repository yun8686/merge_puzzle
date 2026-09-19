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
  final List<_ChainFlash> _flashes = <_ChainFlash>[];

  /// 敵の id ごとの「討たれずに残った回数」。値が変わったフレームで
  /// そのブロックを揺らす。消えずに残ったことを、その場で伝えるため。
  final Map<int, int> _resists = <int, int>{};

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _shake = 0;
  double _shakeTime = 0;

  /// 盤面の枠が消した色に光る量（0〜1）。フレーム全体が反応すると、
  /// 消えたのが盤面上の一部でも「盤ごと鳴った」感じになる。
  double _frameGlow = 0;
  Color _frameColor = Palette.evenA;

  /// 長いチェインのときだけ焚く盤面全体のフラッシュ。
  double _screenFlash = 0;
  Color _screenFlashColor = Palette.evenA;

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
    _frameGlow = _frameGlow > 0.01 ? _frameGlow * exp(-5.5 * dt) : 0;
    _screenFlash = _screenFlash > 0.004 ? _screenFlash * exp(-9 * dt) : 0;

    if (_particles.isEmpty &&
        _shake == 0 &&
        _frameGlow == 0 &&
        _screenFlash == 0) {
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

  /// なぞった順に弾けていく間隔。1枚ずつ順に消えたと分かる程度に空けつつ、
  /// 長いチェインでは詰めて、全体の尺が伸びすぎないようにする。
  static Duration _staggerFor(int length) =>
      Duration(milliseconds: (600 ~/ length).clamp(65, 120));

  /// 最後の1枚が弾けてから盤面を詰めるまでの間。短すぎると消えきる前に
  /// 新しいタイルが降ってきて順番が埋もれるが、長いと手が止まって間延びする。
  static const Duration _settleTail = Duration(milliseconds: 225);

  void _onPanEnd(DragEndDetails d) {
    final result = widget.controller.commitPath();
    if (result == null) return;

    final stagger = _staggerFor(result.length);

    if (result.power >= 8) {
      HapticFeedback.heavyImpact();
    } else if (result.power >= 5) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }

    // 消えたマスだけ弾けさせる。討ち取れなかった敵はその場に残るので、
    // 弾ける代わりに揺らす。弾かれたのか、傷はついたのかは封印の側で見せる。
    for (var i = 0; i < result.cells.length; i++) {
      final cell = result.cells[i];
      if (!result.cleared[i]) {
        final tile = widget.controller.board.tileAt(cell);
        if (tile != null) {
          _resists[tile.id] = (_resists[tile.id] ?? 0) + 1;
        }
        continue;
      }
      _pops.add(
        _Pop(
          id: _seq++,
          ward: result.wards[i],
          isOdd: result.isOdds[i],
          center: _centerOf(cell),
          delay: stagger * i,
        ),
      );
    }

    // 雷に討たれた敵は鎖の外なので、最後の1枚と同じ間で一緒に弾けさせる。
    for (final fall in result.bolt) {
      _pops.add(
        _Pop(
          id: _seq++,
          ward: fall.ward,
          isOdd: fall.isOdd,
          center: _centerOf(fall.cell),
          delay: stagger * (result.length - 1),
        ),
      );
    }

    // 最後の1枚が弾けたら盤面を詰める。ここまで盤面は穴が開いたまま止まる。
    Future<void>.delayed(stagger * (result.length - 1) + _settleTail, () {
      if (!mounted) return;
      widget.controller.settle();
    });

    // なぞった線が、弾ける位置に合わせて先頭から焼き切れていく。
    // どの順で消えたのかが線そのもので分かる。
    final endIsOdd = result.isOdds.last;
    _flashes.add(
      _ChainFlash(
        id: _seq++,
        points: result.cells.map(_centerOf).toList(),
        color: Palette.glowFor(endIsOdd),
        stagger: stagger,
      ),
    );

    // 終端から大きな輪を1つ。長いチェインほど大きく広がる。
    _particles.shockwave(
      _centerOf(result.endCell),
      Palette.glowFor(endIsOdd),
      radius: (_cell * (1.4 + result.power * 0.3)).clamp(0.0, _cell * 5),
      life: 0.5,
      width: 7,
    );

    _frameGlow = (result.power / 6).clamp(0.45, 1.0);
    _frameColor = Palette.glowFor(endIsOdd);
    if (result.power >= 8) {
      // 強くすると盤面が白飛びして、何が消えたのか読めなくなる。
      // あくまで枠の発光を後押しする程度に留める。
      _screenFlash = (result.power / 60).clamp(0.0, 0.2);
      _screenFlashColor = Palette.glowFor(endIsOdd);
    }

    _popups.add(
      _Popup(
        id: _seq++,
        center: _centerOf(result.endCell),
        gained: result.gained,
        power: result.power,
      ),
    );

    final rank = ChainRank.of(result.power);
    if (rank != null) {
      _rank = _Rank(id: _seq++, rank: rank);
    }

    _shake = (result.power * 3.0).clamp(4.0, 32.0);
    _shakeTime = 0;
    _ensureTicking();
    setState(() {});
  }

  void _burstAt(Offset center, bool isOdd) {
    _particles.burst(
      center,
      Palette.baseFor(isOdd),
      count: 16,
      power: _cell * 5.0,
    );
    _particles.shockwave(
      center,
      Palette.glowFor(isOdd),
      radius: _cell * 1.15,
      life: 0.34,
      width: 3.5,
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
              // Stack の子は並び順で古い要素と突き合わされる。消えるタイルが
              // 1枚ずつ減ると後ろの子の位置がずれるので、キーを中の
              // ウィジェットではなく直接の子に付けておかないと State ごと
              // 作り直され、スコア表示などのアニメーションが頭から流れ直す。
              children: [
                Positioned(
                  key: const ValueKey('board-bg'),
                  left: _originX - cell * 0.12,
                  top: _originY - cell * 0.12,
                  width: boardW + cell * 0.24,
                  height: boardH + cell * 0.24,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Palette.boardBg,
                      borderRadius: BorderRadius.circular(cell * 0.45),
                      border: Border.all(
                        color: Color.lerp(
                          Palette.panelBorder,
                          _frameColor,
                          _frameGlow,
                        )!,
                        width: 1.5,
                      ),
                      boxShadow: [
                        const BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 24,
                          offset: Offset(0, 8),
                        ),
                        if (_frameGlow > 0)
                          BoxShadow(
                            color: _frameColor.withValues(
                              alpha: 0.55 * _frameGlow,
                            ),
                            blurRadius: 26 + 30 * _frameGlow,
                            spreadRadius: 2 * _frameGlow,
                          ),
                      ],
                    ),
                  ),
                ),
                // 空きマスのくぼみ。タイルが「受け皿に乗っている」ように見せる。
                Positioned.fill(
                  key: const ValueKey('wells'),
                  child: CustomPaint(
                    painter: _WellPainter(
                      rows: board.rows,
                      cols: board.cols,
                      cell: cell,
                      originX: _originX,
                      originY: _originY,
                    ),
                  ),
                ),
                if (controller.hintPath.isNotEmpty)
                  Positioned.fill(
                    key: const ValueKey('hint-path'),
                    child: CustomPaint(
                      painter: _RibbonPainter(
                        points: controller.hintPath.map(_centerOf).toList(),
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
                    key: const ValueKey('drag-path'),
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
                    key: ValueKey('pop-${pop.id}'),
                    left: pop.center.dx - cell / 2,
                    top: pop.center.dy - cell / 2,
                    width: cell,
                    height: cell,
                    child: _PopTile(
                      ward: pop.ward,
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
                for (final flash in _flashes)
                  Positioned.fill(
                    key: ValueKey('flash-${flash.id}'),
                    child: IgnorePointer(
                      child: _ChainFlashView(
                        points: flash.points,
                        color: flash.color,
                        stagger: flash.stagger,
                        width: cell * 0.15,
                        onDone: () {
                          _flashes.removeWhere((f) => f.id == flash.id);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ),
                if (_screenFlash > 0)
                  Positioned.fill(
                    key: const ValueKey('screen-flash'),
                    child: IgnorePointer(
                      child: ClipPath(
                        clipper: _BoardClipper(
                          left: _originX - cell * 0.12,
                          top: _originY - cell * 0.12,
                          width: boardW + cell * 0.24,
                          height: boardH + cell * 0.24,
                          radius: cell * 0.45,
                        ),
                        child: ColoredBox(
                          color: _screenFlashColor.withValues(
                            alpha: _screenFlash,
                          ),
                        ),
                      ),
                    ),
                  ),
                // 粒と輪は盤面の中に閉じ込める。外に出るとヘッダーの上を
                // 横切って、何が起きたのか読み取れなくなる。
                Positioned.fill(
                  key: const ValueKey('particles'),
                  child: IgnorePointer(
                    child: ClipPath(
                      clipper: _BoardClipper(
                        left: _originX - cell * 0.12,
                        top: _originY - cell * 0.12,
                        width: boardW + cell * 0.24,
                        height: boardH + cell * 0.24,
                        radius: cell * 0.45,
                      ),
                      child: CustomPaint(
                        painter: ParticlePainter(_particles),
                      ),
                    ),
                  ),
                ),
                for (final popup in _popups)
                  Positioned(
                    key: ValueKey('popup-${popup.id}'),
                    left: popup.center.dx - cell * 1.5,
                    top: popup.center.dy - cell * 0.9,
                    width: cell * 3,
                    height: cell * 1.2,
                    child: IgnorePointer(
                      child: _ScorePopup(
                        gained: popup.gained,
                        power: popup.power,
                        onDone: () {
                          _popups.removeWhere((p) => p.id == popup.id);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ),
                if (_rank != null)
                  Positioned(
                    key: ValueKey('rank-${_rank!.id}'),
                    left: _originX,
                    top: _originY + boardH * 0.34,
                    width: boardW,
                    child: IgnorePointer(
                      child: _RankBanner(
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
              willFell: controller.willFell(at),
              willHurt: controller.willHurt(at),
              resistCount: _resists[tile.id] ?? 0,
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

/// 盤面の枠と同じ角丸で切り抜く。演出を盤の中だけに閉じ込めるため。
class _BoardClipper extends CustomClipper<Path> {
  const _BoardClipper({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.radius,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final double radius;

  @override
  Path getClip(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width, height),
        Radius.circular(radius),
      ),
    );

  @override
  bool shouldReclip(_BoardClipper old) =>
      old.left != left ||
      old.top != top ||
      old.width != width ||
      old.height != height ||
      old.radius != radius;
}

/// なぞった線を白く光らせてから消す演出のデータ。
class _ChainFlash {
  _ChainFlash({
    required this.id,
    required this.points,
    required this.color,
    required this.stagger,
  });

  final int id;
  final List<Offset> points;
  final Color color;

  /// 1枚ずつ弾ける間隔。線が焼き切れる速さをこれに合わせる。
  final Duration stagger;
}

/// なぞった経路が、弾ける位置に合わせて先頭から焼き切れていく。
/// タイルが1枚ずつ弾けるのと同じ順・同じ速さで線が短くなるので、
/// 「どの順でなぞって、どの順で消えたのか」が線そのもので読める。
class _ChainFlashView extends StatefulWidget {
  const _ChainFlashView({
    required this.points,
    required this.color,
    required this.stagger,
    required this.width,
    required this.onDone,
  });

  final List<Offset> points;
  final Color color;
  final Duration stagger;
  final double width;
  final VoidCallback onDone;

  @override
  State<_ChainFlashView> createState() => _ChainFlashViewState();
}

class _ChainFlashViewState extends State<_ChainFlashView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final int _burnMs;

  @override
  void initState() {
    super.initState();
    _burnMs = widget.stagger.inMilliseconds * (widget.points.length - 1);
    _c = AnimationController(
      vsync: this,
      // 焼き切ったあと、残り香が消えるまでの分を足しておく。
      duration: Duration(milliseconds: _burnMs + 350),
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

  /// 先頭から [head] 枚ぶん焼けた状態の、残っている線。
  List<Offset> _remaining(double head) {
    final pts = widget.points;
    final i = head.floor();
    if (i >= pts.length - 1) return const <Offset>[];
    final next = Offset.lerp(pts[i], pts[i + 1], head - i)!;
    return <Offset>[next, ...pts.sublist(i + 1)];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final elapsed = _c.value * _c.duration!.inMilliseconds;
        final head = _burnMs == 0
            ? widget.points.length.toDouble()
            : (elapsed / widget.stagger.inMilliseconds);
        final points = _remaining(head);
        if (points.length < 2) return const SizedBox.shrink();
        // 焼け残りは最後に向かって薄くなる。
        final fade = _burnMs == 0
            ? 1.0
            : (1 - (elapsed - _burnMs) / 350).clamp(0.0, 1.0);
        return CustomPaint(
          painter: _RibbonPainter(
            points: points,
            core: Colors.white.withValues(alpha: fade),
            glow: widget.color.withValues(alpha: fade * 0.9),
            width: widget.width * 1.8,
          ),
        );
      },
    );
  }
}

/// 空きマスのくぼみ。タイルと同じ位置・同じ角丸で敷いておくと、
/// タイルが消えた瞬間に「穴」ではなく「受け皿」が見える。
class _WellPainter extends CustomPainter {
  const _WellPainter({
    required this.rows,
    required this.cols,
    required this.cell,
    required this.originX,
    required this.originY,
  });

  final int rows;
  final int cols;
  final double cell;
  final double originX;
  final double originY;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Palette.boardWell;
    final inset = cell * 0.06;
    final radius = Radius.circular(cell * 0.28);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final rect = Rect.fromLTWH(
          originX + c * cell + inset,
          originY + r * cell + inset,
          cell - inset * 2,
          cell - inset * 2,
        );
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_WellPainter old) =>
      old.rows != rows ||
      old.cols != cols ||
      old.cell != cell ||
      old.originX != originX ||
      old.originY != originY;
}

class _Pop {
  _Pop({
    required this.id,
    required this.ward,
    required this.isOdd,
    required this.center,
    required this.delay,
  });

  final int id;

  /// 敵なら書かれていた守り。マナのマスは null。
  final int? ward;
  final bool isOdd;
  final Offset center;
  final Duration delay;
}

class _Popup {
  _Popup({
    required this.id,
    required this.center,
    required this.gained,
    required this.power,
  });

  final int id;
  final Offset center;
  final int gained;
  final int power;
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
    required this.willFell,
    required this.willHurt,
    required this.resistCount,
  });

  final Tile tile;
  final double size;
  final bool selected;
  final bool candidate;
  final bool fresh;

  /// 敵が、いまなぞっている威力で討ち取れるか。
  /// パスに入っていないブロックでは常に false。
  final bool willFell;

  /// 敵に、いまなぞっている威力で傷がつくか。討ち取れなくても体力は削れる。
  final bool willHurt;

  /// このブロックが「討ち取られずに耐えた」回数。
  /// 増えたフレームで揺らす。
  final int resistCount;

  @override
  State<TileWidget> createState() => _TileWidgetState();
}

class _TileWidgetState extends State<TileWidget>
    with TickerProviderStateMixin {
  late final AnimationController _entry;
  late final AnimationController _resist;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _resist = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    if (widget.fresh) {
      _entry.forward();
    } else {
      _entry.value = 1;
    }
  }

  @override
  void didUpdateWidget(TileWidget old) {
    super.didUpdateWidget(old);
    if (widget.resistCount != old.resistCount) {
      _resist.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    _resist.dispose();
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
          borderRadius: BorderRadius.circular(size * 0.28),
          boxShadow: [
            BoxShadow(
              color: glow.withValues(alpha: widget.selected ? 0.8 : 0.32),
              blurRadius: widget.selected ? size * 0.55 : size * 0.24,
              spreadRadius: widget.selected ? size * 0.05 : 0,
            ),
            BoxShadow(
              color: const Color(0x73000000),
              blurRadius: size * 0.12,
              offset: Offset(0, size * 0.05),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 上面のツヤ。これだけで平面がふくらんで見える。
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: Palette.gloss,
                borderRadius: BorderRadius.circular(size * 0.28),
              ),
              child: const SizedBox.expand(),
            ),
            if (widget.selected)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 0.28),
                  border: Border.all(color: Colors.white, width: size * 0.06),
                ),
              ),
            if (widget.candidate && !widget.selected)
              _CandidatePulse(size: size),
            // 数字が書かれているのは敵だけ。マナのマスは相の色しか持たない。
            if (widget.tile.isFoe)
              _FoeFace(
                ward: widget.tile.ward!,
                hp: widget.tile.hp,
                maxHp: widget.tile.maxHp,
                size: size,
                willFall: widget.willFell,
                willHurt: widget.willHurt,
              ),
          ],
        ),
      ),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_entry, _resist]),
      builder: (context, child) {
        final e = Curves.easeOutCubic.transform(_entry.value);
        // 耐えたときの横揺れ。減衰する正弦で「弾かれずに踏みとどまった」感じを出す。
        final r = _resist.isAnimating || _resist.value > 0
            ? sin(_resist.value * pi * 6) * (1 - _resist.value) * size * 0.16
            : 0.0;
        // 落ちている間だけ縦に伸ばす。着地で 1.0 に戻るので跳ねて見える。
        return Transform.translate(
          offset: Offset(r, (1 - e) * -size * 2.6),
          child: Transform.scale(
            scaleX: 1 - (1 - e) * 0.16,
            scaleY: 1 + (1 - e) * 0.28,
            child: Opacity(opacity: e.clamp(0.0, 1.0), child: child),
          ),
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

/// 敵を包む「守り」。書かれている数字は、傷をつけるのに要る鎖の威力。
/// マナのマスと読み違えられないよう、六角の封印で囲って別物に見せる。
/// いま編んでいる鎖で討ち取れるなら、封印が金色に灯る。
///
/// 体力が 2 以上の敵だけ、封印の下に体力の粒が並ぶ。1 の敵には出さない。
/// 「守りを上回れば一撃」という読み方をそのまま残すため。
class _FoeFace extends StatelessWidget {
  const _FoeFace({
    required this.ward,
    required this.hp,
    required this.maxHp,
    required this.size,
    required this.willFall,
    required this.willHurt,
  });

  final int ward;
  final int hp;
  final int maxHp;
  final double size;

  /// いま指を離せばこの敵を討ち取れるか。
  final bool willFall;

  /// いま指を離せば傷だけはつくか。討てなくても体力は削れる。
  final bool willHurt;

  @override
  Widget build(BuildContext context) {
    // 討てるときは金、そうでなければ守りの厚さの色。数字を読む前に
    // 「硬そうか」が伝わる。
    final tint = willFall ? Palette.ward : Palette.wardColorFor(ward);
    // 粒を並べる敵は、その分だけ封印を小さくして場所を空ける。
    final sealSize = maxHp > 1 ? size * 0.62 : size * 0.78;
    final seal = SizedBox(
      width: sealSize,
      height: sealSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _WardPainter(color: tint, lit: willFall),
            ),
          ),
          Padding(
            // 封印の内側に取る余白。封印の大きさに比例させて、
            // 粒が出ても数字と環の間隔が変わらないようにする。
            padding: EdgeInsets.all(sealSize * 0.26),
            child: FittedBox(
              child: Text(
                '$ward',
                style: AppFont.number(size * 0.4, color: tint),
              ),
            ),
          ),
        ],
      ),
    );

    if (maxHp <= 1) return Center(child: seal);

    // 粒のぶんだけ封印を持ち上げる。下端に寄ると窮屈に見える。
    return Stack(
      alignment: Alignment.center,
      children: [
        Align(alignment: const Alignment(0, -0.42), child: seal),
        Align(
          alignment: const Alignment(0, 0.88),
          child: _HpPips(
            hp: hp,
            maxHp: maxHp,
            size: size,
            // 傷がつく威力が乗っているときは粒も灯して、
            // 「討てないが削れる」状態をその場で見せる。
            color: willHurt ? Palette.ward : tint,
          ),
        ),
      ],
    );
  }
}

/// 敵の残り体力。菱形の粒を最大体力ぶん並べ、残っている数だけ塗る。
class _HpPips extends StatelessWidget {
  const _HpPips({
    required this.hp,
    required this.maxHp,
    required this.size,
    required this.color,
  });

  final int hp;
  final int maxHp;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pip = size * 0.1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < maxHp; i++)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.028),
            child: Transform.rotate(
              angle: pi / 4,
              child: Container(
                width: pip,
                height: pip,
                decoration: BoxDecoration(
                  color: i < hp ? color : Colors.transparent,
                  border: Border.all(
                    color: color.withValues(alpha: 0.7),
                    width: size * 0.016,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x99000000), blurRadius: 3),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 六角の封印。外郭を一枚、内側に30度ずらした環をもう一枚重ねて、
/// 「閉じた結界」に見せる。破れる威力が乗っているときだけ外郭が滲む。
class _WardPainter extends CustomPainter {
  const _WardPainter({required this.color, required this.lit});

  final Color color;
  final bool lit;

  Path _hex(Offset center, double radius, double rotation) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = rotation + i * pi / 3;
      final p = Offset(
        center.dx + cos(a) * radius,
        center.dy + sin(a) * radius,
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final outer = _hex(center, r * 0.94, -pi / 2);

    // 中を暗く沈めて、下のマナの色から数字を浮かせる。
    canvas.drawPath(
      outer,
      Paint()..color = const Color(0xA607070F),
    );

    if (lit) {
      canvas.drawPath(
        outer,
        Paint()
          ..color = color.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.3
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.32),
      );
    }

    canvas.drawPath(
      outer,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.14
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawPath(
      _hex(center, r * 0.6, 0),
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_WardPainter old) =>
      old.color != color || old.lit != lit;
}

/// 消える瞬間のタイル。膨らんでから弾ける。
class _PopTile extends StatefulWidget {
  const _PopTile({
    required this.ward,
    required this.isOdd,
    required this.size,
    required this.delay,
    required this.onBurst,
    required this.onDone,
  });

  final int? ward;
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
      duration: const Duration(milliseconds: 230),
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
        final scale = t < 0.28
            ? 1 + (t / 0.28) * 0.6
            : 1.6 * (1 - ((t - 0.28) / 0.72)).clamp(0.0, 1.0);
        // 弾け始めの白飛び。色が一度飛ぶと、破裂の瞬間が立つ。
        final flash = _started ? (1 - t / 0.25).clamp(0.0, 1.0) : 0.0;
        return Opacity(
          opacity: _started ? (1 - t * t).clamp(0.0, 1.0) : 1.0,
          child: Transform.scale(
            scale: _started ? scale : 1.0,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                child!,
                if (flash > 0)
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.all(widget.size * 0.06),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: flash),
                          borderRadius: BorderRadius.circular(
                            widget.size * 0.28,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
        child: widget.ward == null
            ? null
            : Center(
                child: Padding(
                  padding: EdgeInsets.all(size * 0.18),
                  child: FittedBox(
                    child: Text(
                      '${widget.ward}',
                      style: AppFont.number(size * 0.56, color: Colors.white),
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
    required this.gained,
    required this.power,
    required this.onDone,
  });

  final int gained;
  final int power;
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
        // 出た瞬間だけ大きく、すぐ等倍に戻る。数字が飛び出して見える。
        final pop = _c.value < 0.18
            ? Curves.easeOutBack.transform(_c.value / 0.18)
            : 1.0;
        return Transform.translate(
          offset: Offset(0, -t * 52),
          child: Transform.scale(
            scale: 0.6 + pop * 0.55,
            child: Opacity(
              opacity: (1 - t * t).clamp(0.0, 1.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '+${widget.gained}',
                    textAlign: TextAlign.center,
                    style: AppFont.number(28, color: const Color(0xFFFFF0B8)),
                  ),
                  Text(
                    'POWER ${widget.power}',
                    style: AppFont.label(12, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RankBanner extends StatefulWidget {
  const _RankBanner({required this.rank, required this.onDone});

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
        final pop = t < 0.25 ? Curves.easeOutBack.transform(t / 0.25) : 1.0;
        return Opacity(
          opacity: t > 0.7 ? (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0) : 1.0,
          child: Transform.scale(
            scale: 0.6 + pop * 0.4,
            child: Text(
              widget.rank.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFont.display,
                color: widget.rank.color,
                fontWeight: FontWeight.w800,
                fontSize: 42,
                height: 1.0,
                letterSpacing: 1.5,
                shadows: [
                  const Shadow(color: Colors.black, blurRadius: 12),
                  Shadow(
                    color: widget.rank.color.withValues(alpha: 0.7),
                    blurRadius: 24,
                  ),
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
