import 'dart:math';

/// 盤面上の座標。row=0 が最上段。
class Cell {
  const Cell(this.row, this.col);

  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      other is Cell && other.row == row && other.col == col;

  @override
  int get hashCode => row * 131 + col;

  @override
  String toString() => '($row,$col)';
}

/// 1枚のブロック。id はアニメーションで同一ブロックを追跡するために使う。
///
/// 通常ブロックは偶奇（＝色）しか持たず、数字は書かれていない。
/// 目標ブロックだけが [requiredLength] を持ち、それが盤面に数字で書かれる。
/// この数字はブロックの「値」ではなく、**消すのに必要なチェインの長さ**。
class Tile {
  const Tile({required this.id, required this.isOdd, this.requiredLength});

  final int id;
  final bool isOdd;

  /// 目標ブロックなら、消すのに必要なチェイン長。通常ブロックは null。
  final int? requiredLength;

  bool get isTarget => requiredLength != null;
}

/// なぞって消したときの結果。演出側はこれを見てエフェクトを出す。
class ClearResult {
  const ClearResult({
    required this.cells,
    required this.cleared,
    required this.requiredLengths,
    required this.isOdds,
    required this.clearedTargets,
    required this.gained,
    required this.endCell,
  });

  /// なぞった順のマス。
  final List<Cell> cells;

  /// [cells] と同じ並びで、そのマスが実際に消えたか。
  /// 長さの足りなかった目標ブロックだけが false になる。
  final List<bool> cleared;

  /// [cells] と同じ並びで、目標ブロックなら必要チェイン長。通常は null。
  final List<int?> requiredLengths;

  /// [cells] と同じ並びの偶奇。演出の色に使う。
  final List<bool> isOdds;

  /// このチェインで消した目標ブロックの数。
  final int clearedTargets;

  /// このチェインで得た点数。
  final int gained;

  /// 演出をどこに出すかだけに使う、なぞり終わりのマス。
  final Cell endCell;

  int get length => cells.length;
}

/// 奇偶チェインの盤面ロジック。UI から独立していてテスト可能。
///
/// ルール:
///  - 上下左右に隣接するブロックを辿ってパスを作る
///  - 連続する2枚は必ず偶奇が交互になっていること
///  - [minPathLength] 枚以上でチェイン成立
///  - パス上の通常ブロックは必ず消える
///  - 目標ブロックは、チェイン長がその [Tile.requiredLength] 以上のときだけ消える。
///    足りなければその場に残る
///  - 何ひとつ消えないチェイン（全部が要求未達の目標ブロック）は不成立
///  - 消えた跡は重力で詰め、上から新しい通常ブロックが降ってくる
///  - 目標ブロックは補充されない。ステージ開始時に置かれたものが全て
class Board {
  Board({
    this.rows = 8,
    this.cols = 6,
    this.oddChance = 0.65,
    Random? rng,
  }) : _rng = rng ?? Random() {
    grid = List.generate(rows, (_) => List<Tile?>.filled(cols, null));
  }

  /// チェイン成立に必要な最低枚数。
  static const int minPathLength = 3;

  /// 目標ブロックに書ける数字の範囲。
  ///
  /// 下限は [minPathLength] と同じで「成立すれば必ず消える」入門用。
  /// 上限 8 は、シミュレーションで成立率が保てる限界。9 以上にすると
  /// 盤面によっては通るパスが無く、運任せになる。
  static const int minRequired = minPathLength;
  static const int maxRequired = 8;

  /// 目標ブロックの数から手数を決める。
  ///
  /// シミュレーション（目標の周辺を崩して周囲を入れ替える打ち方）で、
  /// この手数のときクリア率が 78〜93% になる。×2+2 だと 69% まで落ちて
  /// 理不尽寄り、×4+2 にしても 86% 止まりで緩めた分だけ間延びする。
  static int movesFor(int targetCount) => targetCount * 3 + 2;

  final int rows;
  final int cols;

  /// 補充時に奇数が出る確率。
  ///
  /// 合計値の条件が無くなったので、この値の影響は以前より小さい
  /// （0.5 と 0.8 でクリア率の差は 6 ポイント程度）。偶奇バーの見た目と
  /// 「偶数は貴重」という手触りを保つために 0.65 を据え置いている。
  final double oddChance;

  final Random _rng;
  late final List<List<Tile?>> grid;
  int _nextId = 0;

  Tile? tileAt(Cell c) {
    if (c.row < 0 || c.row >= rows || c.col < 0 || c.col >= cols) return null;
    return grid[c.row][c.col];
  }

  Tile _spawn([double? oddBias]) {
    final bias = oddBias ?? oddChance;
    return Tile(id: _nextId++, isOdd: _rng.nextDouble() < bias);
  }

  /// ステージを1つ作る。通常ブロックを敷いてから目標ブロックを置く。
  ///
  /// [targetCount] 個の目標ブロックに、[minRequired]〜[maxRequired] の
  /// 範囲で数字を割り振る。
  void buildStage({required int targetCount, required int maxRequiredLength}) {
    _fillInitial();
    _placeTargets(targetCount, maxRequiredLength);
  }

  /// 初期盤面は偶奇を五分五分で敷く（開幕から詰んでいると理不尽なため）。
  void _fillInitial() {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        grid[r][c] = _spawn(0.5);
      }
    }
    var guard = 0;
    while (!hasAnyChain() && guard++ < 50) {
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          grid[r][c] = _spawn(0.5);
        }
      }
    }
  }

  void _placeTargets(int count, int maxRequiredLength) {
    final cells = <Cell>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        cells.add(Cell(r, c));
      }
    }
    cells.shuffle(_rng);
    final cap = maxRequiredLength.clamp(minRequired, maxRequired);
    for (final cell in cells.take(count)) {
      final base = grid[cell.row][cell.col]!;
      final need = minRequired + _rng.nextInt(cap - minRequired + 1);
      grid[cell.row][cell.col] =
          Tile(id: base.id, isOdd: base.isOdd, requiredLength: need);
    }
  }

  Iterable<Cell> neighborsOf(Cell c) sync* {
    if (c.row > 0) yield Cell(c.row - 1, c.col);
    if (c.row < rows - 1) yield Cell(c.row + 1, c.col);
    if (c.col > 0) yield Cell(c.row, c.col - 1);
    if (c.col < cols - 1) yield Cell(c.row, c.col + 1);
  }

  /// [from] から [to] へ繋げられるか（隣接かつ偶奇が交互）。
  bool canExtend(Cell from, Cell to) {
    final a = tileAt(from);
    final b = tileAt(to);
    if (a == null || b == null) return false;
    if ((from.row - to.row).abs() + (from.col - to.col).abs() != 1) return false;
    return a.isOdd != b.isOdd;
  }

  /// 長さ [length] のチェインを打ったとき、[cell] のブロックが消えるか。
  bool clearsAt(Cell cell, int length) {
    final t = tileAt(cell);
    if (t == null) return false;
    return (t.requiredLength ?? 0) <= length;
  }

  /// パスを打ったとき、どのマスが消えるか。[path] と同じ並びで返す。
  List<bool> clearMaskFor(List<Cell> path) =>
      [for (final c in path) clearsAt(c, path.length)];

  /// 隣接と偶奇だけを見た、パスとしての正しさ。
  bool isConnected(List<Cell> path) {
    if (path.length < minPathLength) return false;
    final seen = <Cell>{};
    for (final c in path) {
      if (tileAt(c) == null) return false;
      if (!seen.add(c)) return false;
    }
    for (var i = 0; i + 1 < path.length; i++) {
      if (!canExtend(path[i], path[i + 1])) return false;
    }
    return true;
  }

  /// チェインとして成立するか。
  ///
  /// 何ひとつ消えないチェインは成立させない。通常ブロックが1枚でも
  /// 混じっていれば必ず何か消えるので、これに当たるのは「全部が要求未達の
  /// 目標ブロック」という稀な場合だけ。手数を丸損させないための例外。
  bool isValidPath(List<Cell> path) {
    if (!isConnected(path)) return false;
    return clearMaskFor(path).any((x) => x);
  }

  /// 長さ [length]、目標を [clearedTargets] 個消したチェインの得点。
  static int scoreFor(int length, int clearedTargets) {
    final multiplier = length - minPathLength + 1;
    return length * multiplier * 10 + clearedTargets * 100;
  }

  /// パスを適用する。重力と補充は呼び出し側で行う。
  ClearResult applyPath(List<Cell> path) {
    assert(isValidPath(path));
    final mask = clearMaskFor(path);
    final requiredLengths = <int?>[];
    final isOdds = <bool>[];
    var clearedTargets = 0;
    for (var i = 0; i < path.length; i++) {
      final t = tileAt(path[i])!;
      requiredLengths.add(t.requiredLength);
      isOdds.add(t.isOdd);
      if (mask[i] && t.isTarget) clearedTargets++;
    }
    for (var i = 0; i < path.length; i++) {
      if (mask[i]) grid[path[i].row][path[i].col] = null;
    }
    return ClearResult(
      cells: List.unmodifiable(path),
      cleared: List.unmodifiable(mask),
      requiredLengths: List.unmodifiable(requiredLengths),
      isOdds: List.unmodifiable(isOdds),
      clearedTargets: clearedTargets,
      gained: scoreFor(path.length, clearedTargets),
      endCell: path.last,
    );
  }

  void applyGravity() {
    for (var c = 0; c < cols; c++) {
      var write = rows - 1;
      for (var r = rows - 1; r >= 0; r--) {
        final t = grid[r][c];
        if (t == null) continue;
        grid[r][c] = null;
        grid[write][c] = t;
        write--;
      }
    }
  }

  /// 空きマスを上から補充する。戻り値は新しく生まれたブロックの id 集合。
  /// 補充されるのは通常ブロックだけ。目標ブロックは降ってこない。
  Set<int> refill() {
    final added = <int>{};
    for (var c = 0; c < cols; c++) {
      for (var r = 0; r < rows; r++) {
        if (grid[r][c] == null) {
          final t = _spawn();
          grid[r][c] = t;
          added.add(t.id);
        }
      }
    }
    return added;
  }

  /// 盤面に残っている目標ブロック。
  List<Cell> get targetCells {
    final list = <Cell>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (grid[r][c]?.isTarget ?? false) list.add(Cell(r, c));
      }
    }
    return list;
  }

  int get remainingTargets => targetCells.length;

  /// [through] を通る、長さ [need] 以上の成立パスを1本返す。無ければ空。
  ///
  /// パスを [through] で2本の腕に割って探す。腕はどちらも [through] から
  /// 偶奇が交互に伸びるので、繋ぎ直しても接合部の交互性は自動的に満たされる。
  ///
  /// 交互の制約が強い枝刈りになるので、盤面が枯れているほど速く終わる。
  /// 8x6 盤・[need] が 10 でも、存在しないと答える最悪ケースで 750 ノード程度。
  List<Cell> findPathThrough(Cell through, int need) {
    if (tileAt(through) == null) return const [];
    final seen = <Cell>{through};
    final arm1 = <Cell>[through];
    final arm2 = <Cell>[through];
    var found = <Cell>[];

    bool extend2(Cell head) {
      if (arm1.length + arm2.length - 1 >= need) {
        found = [...arm1.reversed.take(arm1.length - 1), ...arm2];
        return true;
      }
      for (final n in neighborsOf(head)) {
        if (seen.contains(n) || !canExtend(head, n)) continue;
        seen.add(n);
        arm2.add(n);
        if (extend2(n)) return true;
        arm2.removeLast();
        seen.remove(n);
      }
      return false;
    }

    bool extend1(Cell head) {
      if (extend2(through)) return true;
      for (final n in neighborsOf(head)) {
        if (seen.contains(n) || !canExtend(head, n)) continue;
        seen.add(n);
        arm1.add(n);
        if (extend1(n)) return true;
        arm1.removeLast();
        seen.remove(n);
      }
      return false;
    }

    if (!extend1(through)) return const [];
    return isValidPath(found) ? found : const [];
  }

  /// [cell] の目標ブロックを、いまの盤面で消せるか。
  bool canClearTarget(Cell cell) {
    final t = tileAt(cell);
    if (t == null || !t.isTarget) return false;
    return findPathThrough(cell, t.requiredLength!).isNotEmpty;
  }

  /// 成立する手が1つでも残っているか。無ければ手詰まり。
  bool hasAnyChain() {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (findPathThrough(Cell(r, c), minPathLength).isNotEmpty) return true;
      }
    }
    return false;
  }

  /// ヒント。目標ブロックを消せる手があればそれを、無ければ適当な成立手を返す。
  List<Cell> findHint() {
    for (final cell in targetCells) {
      final t = tileAt(cell)!;
      final p = findPathThrough(cell, t.requiredLength!);
      if (p.isNotEmpty) return p;
    }
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final p = findPathThrough(Cell(r, c), minPathLength);
        if (p.isNotEmpty) return p;
      }
    }
    return const [];
  }

  /// 盤面に残っている奇数ブロックの数。偶数との比率を見せるのに使う。
  int get oddCount => _count((t) => t.isOdd);

  /// 盤面に残っている偶数ブロックの数。これが尽きると長いチェインが組めない。
  int get evenCount => _count((t) => !t.isOdd);

  int _count(bool Function(Tile) test) {
    var n = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final t = grid[r][c];
        if (t != null && test(t)) n++;
      }
    }
    return n;
  }

  int get tileCount => rows * cols;
}
