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
/// マナのマスは偶奇（＝相）しか持たず、数字は書かれていない。
/// 敵だけが [ward]（守り）と [hp]（体力）を持ち、守りが盤面に数字で書かれる。
///
/// 守りは「この威力までは弾く」しきい値で、上回った分がそのままダメージになる。
/// 体力が 1 なら守りを1でも上回った時点で討ち取れるので、体力を持たなかった
/// 頃のルールと完全に同じ挙動になる。
class Tile {
  const Tile({
    required this.id,
    required this.isOdd,
    this.ward,
    this.hp = 1,
    int? maxHp,
  }) : maxHp = maxHp ?? hp;

  final int id;
  final bool isOdd;

  /// 敵なら守り。マナのマスは null。
  final int? ward;

  /// 敵の残り体力。マナのマスでは使わない。
  final int hp;

  /// 敵の最大体力。減り具合を見せるために持っている。
  final int maxHp;

  bool get isFoe => ward != null;

  /// 威力 [power] の鎖がこの敵に通すダメージ。守り以下なら弾かれて 0。
  int damageFrom(int power) {
    final d = power - ward! + 1;
    return d < 0 ? 0 : d;
  }

  /// この敵に傷をつけるのに要る最低の威力。＝守り。
  int get powerToHurt => ward!;

  /// 1本の鎖で討ち取るのに要る威力。守りを1上回るごとに1ダメージなので、
  /// 残り体力のぶんだけ余分に要る。
  int get powerToFell => ward! + hp - 1;

  /// ダメージを受けて残った姿。id を引き継ぐので演出は同じブロックとして追う。
  Tile hurt(int damage) =>
      Tile(id: id, isOdd: isOdd, ward: ward, hp: hp - damage, maxHp: maxHp);
}

/// 鎖の外で討ち取られた敵。いまは雷の魔導士の追撃だけがこれを作る。
/// 演出に要る情報しか持たない。
class FoeFall {
  const FoeFall({required this.cell, required this.ward, required this.isOdd});

  final Cell cell;
  final int ward;
  final bool isOdd;
}

/// なぞって消したときの結果。演出側はこれを見てエフェクトを出す。
class ClearResult {
  const ClearResult({
    required this.cells,
    required this.cleared,
    required this.wards,
    required this.damages,
    required this.isOdds,
    required this.power,
    required this.felled,
    required this.gained,
    required this.endCell,
    this.bolt = const <FoeFall>[],
    this.boltCells = const <Cell>[],
  });

  /// なぞった順のマス。
  final List<Cell> cells;

  /// [cells] と同じ並びで、そのマスが実際に消えたか。
  /// 討ち取れなかった敵だけが false になる。
  final List<bool> cleared;

  /// [cells] と同じ並びで、敵なら守り。マナのマスは null。
  final List<int?> wards;

  /// [cells] と同じ並びで、敵に通ったダメージ。マナのマスは 0。
  /// 0 なら弾かれている。
  final List<int> damages;

  /// [cells] と同じ並びの偶奇。演出の色に使う。
  final List<bool> isOdds;

  /// この鎖の威力。枚数に魔導士の補正を足したもの。
  final int power;

  /// この鎖で討ち取った敵の数。
  final int felled;

  /// この鎖で得た点数。
  final int gained;

  /// 演出をどこに出すかだけに使う、なぞり終わりのマス。
  final Cell endCell;

  /// 鎖とは別に討ち取られた敵。
  final List<FoeFall> bolt;

  /// 追撃が当たったマス。討ち取れた敵も、削っただけの敵も入る。
  /// [bolt] は討ち取れた敵しか持たないので、演出はこちらを見る。
  /// 削っただけの敵にも雷を落として見せないと、何が起きたのか伝わらない。
  final List<Cell> boltCells;

  int get length => cells.length;

  /// 鎖の外で起きた追撃を足した結果を返す。盤面ロジックは追撃を知らないので、
  /// パーティー側から後付けする。[struck] は落ちる前の敵の位置。
  ClearResult withBolt(List<FoeFall> fallen, List<Cell> struck) => ClearResult(
    cells: cells,
    cleared: cleared,
    wards: wards,
    damages: damages,
    isOdds: isOdds,
    power: power,
    felled: felled + fallen.length,
    gained: gained,
    endCell: endCell,
    bolt: List.unmodifiable(fallen),
    boltCells: List.unmodifiable(struck),
  );
}

/// 盤面ロジック。UI から独立していてテスト可能。
///
/// 世界観では熱の相 / 冷の相、敵、守り、威力と呼んでいるが、実装は偶奇のまま。
/// ここは相の呼び名を持たず、[Tile.isOdd] と数だけで話す。
///
/// ルール:
///  - 上下左右に隣接するブロックを辿ってパスを作る
///  - 連続する2枚は必ず偶奇が交互になっていること
///  - [minPathLength] 枚以上でチェイン成立
///  - パス上のマナのマスは必ず消える
///  - 敵には「威力 − 守り + 1」のダメージが通る。守り以下なら 0 で弾かれる。
///    体力を削り切れば討ち取れ、残れば傷ついたままその場に残る
///  - 何ひとつ起きないチェイン（誰にも傷がつかない）は不成立
///  - 消えた跡は重力で詰め、上から新しいマナが降ってくる
///  - 敵は補充されない。ステージ開始時に置かれたものが全て
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

  /// 敵の守りに書ける数字の範囲。
  ///
  /// 下限は [minPathLength] と同じで「成立すれば必ず傷がつく」入門用。
  /// 上限 8 は、シミュレーションで成立率が保てる限界。9 以上にすると
  /// 盤面によっては通るパスが無く、運任せになる。
  static const int minWard = minPathLength;
  static const int maxWard = 8;

  /// 階層に置かれた敵の体力の合計から手数を決める。
  ///
  /// シミュレーション（敵の周辺を崩して周囲を入れ替える打ち方）で、
  /// この手数のときクリア率が 78〜93% になる。×2+2 だと 69% まで落ちて
  /// 理不尽寄り、×4+2 にしても 86% 止まりで緩めた分だけ間延びする。
  ///
  /// 体力を持つ敵は1体で複数ターンを要求するので、体数ではなく体力の合計で
  /// 数える。全員の体力が 1 なら体数で数えていた頃と同じ値になる。
  static int movesFor(int totalFoeHp) => totalFoeHp * 3 + 2;

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

  /// ステージを1つ作る。マナを敷いてから敵を置く。
  ///
  /// [foeCount] 体の敵に、[minWard]〜[wardCap] の範囲で守りを割り振り、
  /// 体力を 1〜[maxFoeHp] から選ぶ。
  void buildStage({
    required int foeCount,
    required int wardCap,
    int maxFoeHp = 1,
  }) {
    _fillInitial();
    _placeFoes(foeCount, wardCap, maxFoeHp);
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

  void _placeFoes(int count, int wardCap, int maxFoeHp) {
    final cells = <Cell>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        cells.add(Cell(r, c));
      }
    }
    cells.shuffle(_rng);
    final cap = wardCap.clamp(minWard, maxWard);
    final hpCap = maxFoeHp < 1 ? 1 : maxFoeHp;
    for (final cell in cells.take(count)) {
      final base = grid[cell.row][cell.col]!;
      final ward = minWard + _rng.nextInt(cap - minWard + 1);
      // 守りが厚い敵ほど体力は薄く。両方が重なると、1本で討てないうえに
      // 削るのにも何ターンもかかる、ただ長引くだけの敵になる。
      final room = ward >= maxWard - 1 ? 1 : hpCap;
      final hp = 1 + _rng.nextInt(room);
      grid[cell.row][cell.col] =
          Tile(id: base.id, isOdd: base.isOdd, ward: ward, hp: hp);
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

  /// 威力 [power] の鎖が [cell] に通すダメージ。マナのマスは 0。
  int damageAt(Cell cell, int power) {
    final t = tileAt(cell);
    if (t == null || !t.isFoe) return 0;
    return t.damageFrom(power);
  }

  /// 威力 [power] の鎖で [cell] のブロックが盤面から消えるか。
  /// マナのマスは必ず消える。敵は体力を削り切ったときだけ。
  bool fells(Cell cell, int power) {
    final t = tileAt(cell);
    if (t == null) return false;
    if (!t.isFoe) return true;
    return t.damageFrom(power) >= t.hp;
  }

  /// パスを打ったとき、どのマスが消えるか。[path] と同じ並びで返す。
  /// [power] を省くと枚数そのものを威力として扱う。
  List<bool> clearMaskFor(List<Cell> path, {int? power}) {
    final p = power ?? path.length;
    return [for (final c in path) fells(c, p)];
  }

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
  /// 何ひとつ起きないチェインは成立させない。マナのマスが1枚でも混じって
  /// いれば必ず何か消えるので、これに当たるのは「全部が弾かれる敵」という
  /// 稀な場合だけ。手数を丸損させないための例外。
  bool isValidPath(List<Cell> path, {int? power}) {
    if (!isConnected(path)) return false;
    final p = power ?? path.length;
    for (final c in path) {
      final t = tileAt(c)!;
      if (!t.isFoe || t.damageFrom(p) > 0) return true;
    }
    return false;
  }

  /// 威力 [power]、敵を [felled] 体討った鎖の得点。
  static int scoreFor(int power, int felled) {
    final multiplier = power - minPathLength + 1;
    return power * multiplier * 10 + felled * 100;
  }

  /// パスを適用する。重力と補充は呼び出し側で行う。
  /// [power] を省くと枚数そのものを威力として扱う。
  ClearResult applyPath(List<Cell> path, {int? power}) {
    final p = power ?? path.length;
    assert(isValidPath(path, power: p));
    final wards = <int?>[];
    final damages = <int>[];
    final isOdds = <bool>[];
    final cleared = <bool>[];
    var felled = 0;
    for (final cell in path) {
      final t = tileAt(cell)!;
      wards.add(t.ward);
      isOdds.add(t.isOdd);
      if (!t.isFoe) {
        damages.add(0);
        cleared.add(true);
        continue;
      }
      final d = t.damageFrom(p);
      damages.add(d);
      final down = d >= t.hp;
      cleared.add(down);
      if (down) felled++;
    }
    for (var i = 0; i < path.length; i++) {
      final cell = path[i];
      if (cleared[i]) {
        grid[cell.row][cell.col] = null;
      } else if (damages[i] > 0) {
        grid[cell.row][cell.col] = grid[cell.row][cell.col]!.hurt(damages[i]);
      }
    }
    return ClearResult(
      cells: List.unmodifiable(path),
      cleared: List.unmodifiable(cleared),
      wards: List.unmodifiable(wards),
      damages: List.unmodifiable(damages),
      isOdds: List.unmodifiable(isOdds),
      power: p,
      felled: felled,
      gained: scoreFor(p, felled),
      endCell: path.last,
    );
  }

  /// 盤面に残っている敵全員に [damage] を通す。守りは無視する。
  /// 鎖の外からの追撃用。討ち取った敵を返す。
  List<FoeFall> strike(int damage) {
    final fallen = <FoeFall>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final t = grid[r][c];
        if (t == null || !t.isFoe) continue;
        if (damage >= t.hp) {
          grid[r][c] = null;
          fallen.add(
            FoeFall(cell: Cell(r, c), ward: t.ward!, isOdd: t.isOdd),
          );
        } else {
          grid[r][c] = t.hurt(damage);
        }
      }
    }
    return fallen;
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
  /// 補充されるのはマナのマスだけ。敵は降ってこない。
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

  /// 盤面に残っている敵。
  List<Cell> get foeCells {
    final list = <Cell>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (grid[r][c]?.isFoe ?? false) list.add(Cell(r, c));
      }
    }
    return list;
  }

  int get remainingFoes => foeCells.length;

  /// 残っている敵の体力の合計。階層の手数はこれで決まる。
  int get totalFoeHp {
    var n = 0;
    for (final cell in foeCells) {
      n += tileAt(cell)!.hp;
    }
    return n;
  }

  /// 盤面に残っている敵の守り。決着画面に姿を並べるのに使う。
  List<int> get foeWards => [for (final c in foeCells) tileAt(c)!.ward!];

  /// 討ち漏らしたまま階層を落としたときに受ける痛手。
  /// 守りが厚い敵を残すほど高くつく。
  int get foeThreat {
    var n = 0;
    for (final cell in foeCells) {
      n += tileAt(cell)!.ward!;
    }
    return n;
  }

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

  /// [cell] の敵を、いまの盤面で1本の鎖で討ち取れるか。
  ///
  /// 魔導士の威力補正は数に入れない。入れると「補正が乗る鎖が組めるか」まで
  /// 探すことになり、探索が跳ね上がる。見落とす側に倒しても、実際より
  /// 厳しく答えるだけなので嘘にはならない。
  bool canFell(Cell cell) {
    final t = tileAt(cell);
    if (t == null || !t.isFoe) return false;
    return findPathThrough(cell, t.powerToFell).isNotEmpty;
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

  /// ヒント。討ち取れる敵があればその手を、無ければ傷をつけられる手を、
  /// それも無ければ適当な成立手を返す。
  List<Cell> findHint() {
    final foes = foeCells;
    for (final cell in foes) {
      final p = findPathThrough(cell, tileAt(cell)!.powerToFell);
      if (p.isNotEmpty) return p;
    }
    for (final cell in foes) {
      final p = findPathThrough(cell, tileAt(cell)!.powerToHurt);
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
