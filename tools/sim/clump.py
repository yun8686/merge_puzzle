"""手を重ねると、同じ相が底に溜まるかを測る。

交互の決まりでは、同じ相が固まった場所はどの鎖も通れない（**死にマス**）。
鎖は色の混ざった場所ばかり消していくので、固まりだけが残って重力で沈み、
底に溜まる。下にいる敵に届かなくなるのが、遊ぶ側から見た「詰み」になる。

2色の盤面（8行×6列）で、毎手「ランダムに選んだ1マスを通るいちばん長い鎖」を
消し、重力で詰めて補充する。それを 40 手重ねて、次を数える。

  - 下2段のうち、死にマス（3枚の鎖がどう引いても通らないマス）の割合
  - 下2段に置いた敵に通せる鎖の長さ（0 は3枚すら届かない）
  - 手詰まり（盤面ぜんぶが死にマス）になった割合。起きたら敷き直す

補充の決まりは `Board.refill` と同じ。**真下のマスと同じ相の重みを
`STACK_DAMPING` 分の1にする**（1 なら何もしない、昔の補充）。

    python3 tools/sim/clump.py

README 第23段階の表はこれで出した。標準ライブラリだけで動く。
"""
import random

ROWS, COLS = 8, 6
CAP = 9  # 守りの上限 8 を破れば足りる
TURNS = 40
RUNS = 150
STACK_DAMPING = 6  # lib/game/board.dart の Board.stackDamping


def nb(r, c):
    if r > 0:
        yield (r - 1, c)
    if r < ROWS - 1:
        yield (r + 1, c)
    if c > 0:
        yield (r, c - 1)
    if c < COLS - 1:
        yield (r, c + 1)


def longest_through(g, s, budget=4000):
    """s を通る交互の鎖のうち、いちばん長いもの（CAP で打ち切り）。

    s から片側へ伸ばし切ってから、その先端を起点にもう一度伸ばす。完全な
    探索ではないが、控えめに答えるだけなので比べるには足りる。
    """
    best, n = [s], [0]

    def ext(path, seen):
        nonlocal best
        if len(path) > len(best):
            best = list(path)
        if len(best) >= CAP or n[0] > budget:
            return
        tip = path[-1]
        for q in nb(*tip):
            if q in seen or g[q[0]][q[1]] == g[tip[0]][tip[1]]:
                continue
            n[0] += 1
            seen.add(q)
            path.append(q)
            ext(path, seen)
            path.pop()
            seen.discard(q)

    ext([s], {s})
    one_way = best
    if len(one_way) < CAP:
        n[0] = 0
        ext(list(reversed(one_way)), set(one_way))
    return best if len(best) >= 3 else []


def dead(g, r, c):
    """3枚の鎖がどう引いても通らないか。"""
    me = g[r][c]
    other = [q for q in nb(r, c) if g[q[0]][q[1]] != me]
    if len(other) >= 2:
        return False
    for q in other:
        for w in nb(*q):
            if w != (r, c) and g[w[0]][w[1]] == me:
                return False
    return True


def spawn(rng, weights, below, damping):
    w = [x if below is None or i != below else x / damping
         for i, x in enumerate(weights)]
    return 0 if rng.random() < w[0] / sum(w) else 1


def run(weights, damping, seed):
    rng = random.Random(seed)
    g = [[rng.randrange(2) for _ in range(COLS)] for _ in range(ROWS)]
    rows, stuck = [], 0
    for _ in range(TURNS):
        bottom = [(r, c) for r in (ROWS - 2, ROWS - 1) for c in range(COLS)]
        dead_share = sum(dead(g, *x) for x in bottom) / len(bottom)
        reach = len(longest_through(g, rng.choice(bottom)))
        rows.append((dead_share, reach))

        path = longest_through(g, (rng.randrange(ROWS), rng.randrange(COLS)))
        if not path:
            live = [(r, c) for r in range(ROWS) for c in range(COLS)
                    if not dead(g, r, c)]
            if not live:
                # 手詰まり。敷き直す（Board.reshuffle）。
                stuck += 1
                g = [[rng.randrange(2) for _ in range(COLS)]
                     for _ in range(ROWS)]
                continue
            path = longest_through(g, rng.choice(live))
        for r, c in path:
            g[r][c] = None
        for c in range(COLS):
            col = [g[r][c] for r in range(ROWS) if g[r][c] is not None]
            col = [None] * (ROWS - len(col)) + col
            for r in range(ROWS):
                g[r][c] = col[r]
            for r in range(ROWS - 1, -1, -1):  # 下から埋める
                if g[r][c] is None:
                    below = g[r + 1][c] if r + 1 < ROWS else None
                    g[r][c] = spawn(rng, weights, below, damping)
    return rows, stuck


def report(weights, damping):
    runs = [run(weights, damping, seed) for seed in range(RUNS)]
    label = '補充そのまま' if damping == 1 else f'真下と同じ相を 1/{damping}'
    print(f'--- {weights[0]}:{weights[1]}  {label}')
    print('   手  下2段の死にマス  下の敵に届く長さ  3枚も届かない')
    for t in (0, 10, 20, TURNS - 1):
        xs = [rows[t] for rows, _ in runs]
        share = sum(x[0] for x in xs) / len(xs)
        reach = sum(x[1] for x in xs) / len(xs)
        zero = sum(x[1] == 0 for x in xs) / len(xs)
        print(f'  {t + 1:3d}   {share:6.1%}         {reach:5.2f} 枚         {zero:6.1%}')
    stuck = sum(s for _, s in runs)
    print(f'  手詰まり（敷き直し） {stuck} 回 / {RUNS * TURNS} 手')


if __name__ == '__main__':
    for weights in ((1, 1), (2, 1)):
        for damping in (1, STACK_DAMPING):
            report(weights, damping)
