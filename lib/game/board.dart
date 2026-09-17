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

/// 1枚のタイル。id はアニメーションで同一タイルを追跡するために使う。
class Tile {
  const Tile({required this.id, required this.value});

  final int id;
  final int value;

  bool get isOdd => value.isOdd;
}

/// なぞって消したときの結果。演出側はこれを見てエフェクトを出す。
class ClearResult {
  const ClearResult({
    required this.cells,
    required this.values,
    required this.total,
    required this.gained,
    required this.endCell,
  });

  final List<Cell> cells;
  final List<int> values;

  /// なぞったタイルの合計値。[Board.requiredTotal] 以上でないと成立しない。
  final int total;

  /// このチェインで得た点数。
  final int gained;

  /// 演出をどこに出すかだけに使う、なぞり終わりのマス。
  final Cell endCell;

  int get length => cells.length;
}

/// 奇偶チェインの盤面ロジック。UI から独立していてテスト可能。
///
/// ルール:
///  - 上下左右に隣接するタイルを辿ってパスを作る
///  - 連続する2枚は必ず偶奇が交互になっていること
///  - [minPathLength] 枚以上、かつ合計が [requiredTotal] 以上でチェイン成立
///  - 成立するとパス上の全タイルが消える
///  - 消えた跡は重力で詰め、上から新しいタイルが降ってくる
///  - 補充は奇数に偏っているため、偶数は枯れていく希少資源になる
///  - 消した合計値が積み上がるほど [requiredTotal] が上がり、いずれ盤面が
///    追いつかなくなって必ず詰む
class Board {
  Board({
    this.rows = 8,
    this.cols = 6,
    this.oddChance = 0.65,
    Random? rng,
  }) : _rng = rng ?? Random() {
    grid = List.generate(rows, (_) => List<Tile?>.filled(cols, null));
  }

  static const int minPathLength = 3;
  static const List<int> _oddValues = [1, 3, 5];
  static const List<int> _evenValues = [2, 4, 6];

  /// チェイン成立に必要な合計値の初期値。
  static const int baseRequiredTotal = 6;

  /// 消した合計値がこれだけ積み上がるごとに [requiredTotal] が1上がる。
  /// 小さくすると早く終わる。200 だと、毎回いちばん長いチェインを取る打ち方で
  /// 1ゲーム 18〜60手（中央 34手）になる。
  static const int requiredTotalStep = 200;

  final int rows;
  final int cols;

  /// 補充時に奇数が出る確率。高いほど偶数が枯れやすく、難しくなる。
  final double oddChance;

  final Random _rng;
  late final List<List<Tile?>> grid;
  int _nextId = 0;

  /// これまでに消したタイルの合計値。進行度そのもの。
  int clearedTotal = 0;

  /// いまチェイン成立に必要な合計値。消すほど上がっていく。
  /// タイルは1〜6しか出ないので合計値には天井があり、これを上げ続ければ
  /// どこかで必ず手が無くなる（＝無限に遊べない）。
  int get requiredTotal =>
      baseRequiredTotal + clearedTotal ~/ requiredTotalStep;

  Tile? tileAt(Cell c) {
    if (c.row < 0 || c.row >= rows || c.col < 0 || c.col >= cols) return null;
    return grid[c.row][c.col];
  }

  Tile _spawn([double? oddBias]) {
    final bias = oddBias ?? oddChance;
    final pool = _rng.nextDouble() < bias ? _oddValues : _evenValues;
    return Tile(id: _nextId++, value: pool[_rng.nextInt(pool.length)]);
  }

  /// 初期盤面は偶奇を五分五分で敷く（開幕から詰んでいると理不尽なため）。
  void fillInitial() {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        grid[r][c] = _spawn(0.5);
      }
    }
    // 万一開幕から手がない盤面が出たら引き直す。
    var guard = 0;
    while (!hasAnyPath() && guard++ < 50) {
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          grid[r][c] = _spawn(0.5);
        }
      }
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

  /// パス上のタイルの合計値。空マスを含むときは 0 を返す。
  int totalOf(List<Cell> path) {
    var total = 0;
    for (final c in path) {
      final t = tileAt(c);
      if (t == null) return 0;
      total += t.value;
    }
    return total;
  }

  bool isValidPath(List<Cell> path) {
    if (path.length < minPathLength) return false;
    final seen = <Cell>{};
    for (final c in path) {
      if (tileAt(c) == null) return false;
      if (!seen.add(c)) return false;
    }
    for (var i = 0; i + 1 < path.length; i++) {
      if (!canExtend(path[i], path[i + 1])) return false;
    }
    return totalOf(path) >= requiredTotal;
  }

  /// 長さ [length] のチェインの得点。
  /// 長いほど1枚あたりの価値が上がるが、指数で伸ばすと数手で桁が壊れるので
  /// 倍率は線形に留める（3枚=等倍、12枚=10倍）。
  static int scoreFor(int total, int length) {
    final multiplier = length - minPathLength + 1;
    return total * length * multiplier;
  }

  /// パス上のタイルを消す。重力と補充は呼び出し側で行う。
  ClearResult applyPath(List<Cell> path) {
    assert(isValidPath(path));
    final values = <int>[];
    var total = 0;
    for (final c in path) {
      final t = tileAt(c)!;
      values.add(t.value);
      total += t.value;
    }
    for (final c in path) {
      grid[c.row][c.col] = null;
    }
    clearedTotal += total;
    return ClearResult(
      cells: List.unmodifiable(path),
      values: List.unmodifiable(values),
      total: total,
      gained: scoreFor(total, path.length),
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

  /// 空きマスを上から補充する。戻り値は新しく生まれたタイルの id 集合。
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

  /// 成立する手が1つでも残っているか。無ければゲームオーバー。
  ///
  /// 合計値の条件が入ったので、隣接の有無を見るだけでは判定できない。
  /// 見つかった時点で打ち切るので、手が残っている普通の局面では数手分しか
  /// 辿らずに済む。予算を使い切るのは詰みかけの局面だけ。
  bool hasAnyPath() => _search(stopAtFirst: true, budget: 200000).isNotEmpty;

  /// ヒント用。探索予算の範囲で見つかった一番長い成立パスを返す。
  List<Cell> findBestPath({int budget = 30000, int cap = 16}) =>
      _search(stopAtFirst: false, budget: budget, cap: cap);

  /// [minPathLength] 枚以上かつ合計 [requiredTotal] 以上のパスを深さ優先で探す。
  ///
  /// 値の大きいマスから辿り、残りを盤面の最大値で埋めても届かない枝は切る。
  /// 必要合計値が高いほど枝刈りが効くので、詰み判定が重くなる局面ほど速く
  /// 終わる。
  List<Cell> _search({
    required bool stopAtFirst,
    int budget = 30000,
    int cap = 16,
  }) {
    var best = <Cell>[];
    var remaining = budget;
    final path = <Cell>[];
    final seen = <Cell>{};
    final maxValue = _maxTileValue();

    // 探索を打ち切るときだけ true を返す。
    bool dfs(Cell head, int total) {
      if (remaining-- <= 0) return true;
      if (path.length >= minPathLength && total >= requiredTotal) {
        if (stopAtFirst) {
          best = List.of(path);
          return true;
        }
        if (path.length > best.length) best = List.of(path);
      }
      if (path.length >= cap) return false;
      if (total + (cap - path.length) * maxValue < requiredTotal) {
        return false;
      }
      for (final n in _neighborsByValue(head)) {
        if (seen.contains(n) || !canExtend(head, n)) continue;
        seen.add(n);
        path.add(n);
        final stop = dfs(n, total + tileAt(n)!.value);
        path.removeLast();
        seen.remove(n);
        if (stop) return true;
      }
      return false;
    }

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final start = Cell(r, c);
        final tile = tileAt(start);
        if (tile == null) continue;
        path.add(start);
        seen.add(start);
        final stop = dfs(start, tile.value);
        path.removeLast();
        seen.remove(start);
        if (stop) return best;
      }
    }
    return best;
  }

  int _maxTileValue() {
    var maxValue = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final t = grid[r][c];
        if (t != null && t.value > maxValue) maxValue = t.value;
      }
    }
    return maxValue;
  }

  /// 合計値を早く稼げる順、つまり値の大きい隣から見る。
  List<Cell> _neighborsByValue(Cell c) {
    final list = neighborsOf(c).toList();
    list.sort((a, b) => (tileAt(b)?.value ?? 0) - (tileAt(a)?.value ?? 0));
    return list;
  }

  /// 盤面に残っている偶数タイルの数。これが尽きると詰む。
  int get evenCount {
    var n = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final t = grid[r][c];
        if (t != null && !t.isOdd) n++;
      }
    }
    return n;
  }

  int get tileCount => rows * cols;
}
