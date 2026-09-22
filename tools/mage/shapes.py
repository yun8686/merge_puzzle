"""魔導士の姿を正規化座標(0..1)で持つ。ここが唯一の定義で、
プレビュー(Pillow)と Dart の CustomPainter の両方がこれを読む。

敵（tools/foe/shapes.py）と同じ3つの描画しか使わない。Flutter の Canvas に
そのまま移せるものに絞ってある:
  ('poly',   layer, [(x,y), ...])      閉じた多角形を塗る
  ('circle', layer, (cx, cy, r))       円を塗る
  ('line',   layer, [(x,y), ...], w)   折れ線を太さ w・丸端で引く

layer: 'fill' = 本体の色, 'hole' = くり抜き, 'glow' = 明るい色
描画順は fill → hole → glow。

敵と違って**魔導士の姿は人ではなく、その力そのもの**を描く。22px まで縮む
場所（編成の相の丸の隣）に出るので、人の形では潰れて誰だか分からない。
炎・滴・稲妻のような一目で分かる形を、相ごとに揃えてある。

見習いは枠を小さく使い、招ける魔導士は大きく使う。敵の「格の梯子」と同じ考え。
"""
import math

MAGES = {}


# ---- 形の部品 ---------------------------------------------------------

def flame(cx, cy, w, h, layer='fill'):
    """炎。尖端まで細く絞り、左にもう一つ小さな舌を立てる。

    滴（[drop]）と同じ輪郭にならないよう、左右を非対称にしてある。
    丸い腹に尖った頭、では滴と見分けがつかない。
    """
    return ('poly', layer, [
        (cx + 0.10 * w, cy - 1.00 * h),   # 尖端
        (cx + 0.34 * w, cy - 0.56 * h),
        (cx + 0.70 * w, cy - 0.06 * h),
        (cx + 0.98 * w, cy + 0.40 * h),
        (cx + 0.92 * w, cy + 0.70 * h),
        (cx + 0.68 * w, cy + 0.90 * h),
        (cx + 0.34 * w, cy + 1.00 * h),
        (cx - 0.02 * w, cy + 1.02 * h),
        (cx - 0.40 * w, cy + 0.96 * h),
        (cx - 0.72 * w, cy + 0.79 * h),
        (cx - 0.92 * w, cy + 0.50 * h),
        (cx - 0.96 * w, cy + 0.14 * h),
        (cx - 0.72 * w, cy - 0.36 * h),   # 左の小さな舌
        (cx - 0.52 * w, cy + 0.02 * h),   # そのくびれ
        (cx - 0.20 * w, cy - 0.44 * h),
    ])


def drop(cx, cy, r, layer='fill'):
    """滴。丸い腹に三角の頭。炎と違って左右対称にしてある。"""
    return [
        ('circle', layer, (cx, cy + 0.34 * r, 0.66 * r)),
        ('poly', layer, [
            (cx, cy - 1.00 * r),
            (cx + 0.60 * r, cy + 0.45 * r),
            (cx - 0.60 * r, cy + 0.45 * r),
        ]),
    ]


def bolt(cx, cy, w, h, layer='fill'):
    """稲妻。折れは2回まで。3回以上にすると小さいとき潰れる。"""
    return ('poly', layer, [
        (cx + 0.38 * w, cy - 1.00 * h),
        (cx - 1.00 * w, cy + 0.16 * h),
        (cx - 0.14 * w, cy + 0.16 * h),
        (cx - 0.48 * w, cy + 1.00 * h),
        (cx + 1.00 * w, cy - 0.20 * h),
        (cx + 0.10 * w, cy - 0.20 * h),
    ])


def snowflake(cx, cy, r, w, layer='fill'):
    """六花。3本の軸と、その先の枝。"""
    ops = []
    for k in range(3):
        a = math.radians(90 + k * 60)
        dx, dy = math.cos(a) * r, -math.sin(a) * r
        ops.append(('line', layer, [(cx - dx, cy - dy), (cx + dx, cy + dy)], w))
    for k in range(6):
        a = math.radians(90 + k * 60)
        bx = cx + math.cos(a) * r * 0.60
        by = cy - math.sin(a) * r * 0.60
        for s in (1, -1):
            b = a + s * math.radians(52)
            ops.append(('line', layer, [
                (bx, by),
                (bx + math.cos(b) * r * 0.36, by - math.sin(b) * r * 0.36),
            ], w * 0.82))
    return ops


def gust(cx, cy, r, w, layer='fill'):
    """風。左から吹き抜けて、右で渦に巻き込む一本線。

    渦だけだと丸に見えるので、巻く前の直線の尾を付けて「流れている」ことを
    出している。
    """
    n = 30
    pts = [(cx - 1.48 * r, cy + 0.34 * r)]
    for i in range(n + 1):
        t = i / n
        a = math.radians(160) + t * 1.45 * 2 * math.pi
        rr = r * (1.0 - 0.80 * t)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    return ('line', layer, pts, w)


def cloud(cx, cy, w, h, layer='fill'):
    """雲。丸を3つ重ねて底を平らに埋める。"""
    return [
        ('circle', layer, (cx - 0.52 * w, cy + 0.10 * h, 0.48 * h)),
        ('circle', layer, (cx + 0.50 * w, cy + 0.14 * h, 0.42 * h)),
        ('circle', layer, (cx, cy - 0.16 * h, 0.66 * h)),
        ('poly', layer, [
            (cx - 0.98 * w, cy + 0.10 * h), (cx + 0.96 * w, cy + 0.14 * h),
            (cx + 0.96 * w, cy + 0.56 * h), (cx - 0.98 * w, cy + 0.56 * h),
        ]),
    ]


# ---- 赤 ---------------------------------------------------------------

# 見習いは**輪郭だけ**。塗り潰した招ける魔導士と、同じ相でも一目で分かれる。
# 敵の「格の梯子」と同じで、格の差を形で出す。
MAGES['squireRed'] = ('赤の見習い', [
    flame(0.50, 0.53, 0.27, 0.33),
    flame(0.50, 0.545, 0.150, 0.185, 'hole'),
])

MAGES['ember'] = ('焔の魔導士', [
    flame(0.50, 0.50, 0.34, 0.42),
    ('circle', 'glow', (0.50, 0.63, 0.115)),
])

MAGES['blaze'] = ('烈火の魔導士', [
    # 脇の2本は細く高く。低く太くすると山並みに見える。
    flame(0.19, 0.58, 0.145, 0.30),
    flame(0.81, 0.58, 0.145, 0.30),
    flame(0.50, 0.50, 0.265, 0.42),
    ('circle', 'glow', (0.50, 0.64, 0.100)),
])

MAGES['gale'] = ('風の魔導士', [
    ('line', 'fill', [(0.14, 0.20), (0.60, 0.20)], 0.080),
    gust(0.55, 0.56, 0.29, 0.090),
])

# ---- 青 ---------------------------------------------------------------

MAGES['squireBlue'] = ('青の見習い', [
    *drop(0.50, 0.50, 0.32),
    *drop(0.50, 0.515, 0.175, 'hole'),
])

MAGES['rime'] = ('氷雨の魔導士', [
    *drop(0.28, 0.36, 0.20),
    *drop(0.70, 0.44, 0.17),
    *drop(0.48, 0.70, 0.24),
    ('circle', 'glow', (0.48, 0.78, 0.075)),
])

MAGES['frost'] = ('霜の魔導士', [
    *snowflake(0.50, 0.50, 0.40, 0.070),
    ('circle', 'glow', (0.50, 0.50, 0.085)),
])

# ---- 紫 ---------------------------------------------------------------

MAGES['squireViolet'] = ('紫の見習い', [
    bolt(0.50, 0.52, 0.225, 0.325),
    bolt(0.50, 0.52, 0.105, 0.155, 'hole'),
])

MAGES['storm'] = ('雷の魔導士', [
    *cloud(0.50, 0.28, 0.32, 0.24),
    bolt(0.50, 0.72, 0.21, 0.25),
])

MAGES['aegis'] = ('盾の魔導士', [
    # くり抜くと「U」に見えるので、塗り潰した盾に印を1つ載せる。
    ('poly', 'fill', [
        (0.17, 0.19), (0.83, 0.19), (0.83, 0.53), (0.50, 0.89), (0.17, 0.53),
    ]),
    ('line', 'glow', [(0.32, 0.45), (0.50, 0.62), (0.68, 0.45)], 0.085),
])

# 並び順。名簿と同じ（見習いが先、招ける魔導士が後）。
ORDER = [
    'squireRed', 'squireBlue', 'squireViolet',
    'ember', 'blaze', 'gale', 'rime', 'frost', 'storm', 'aegis',
]

# 相。色はここから引く。
PHASE = {
    'squireRed': 'red', 'ember': 'red', 'blaze': 'red', 'gale': 'red',
    'squireBlue': 'blue', 'rime': 'blue', 'frost': 'blue',
    'squireViolet': 'violet', 'storm': 'violet', 'aegis': 'violet',
}

# Palette.baseFor(phase) と同じ色。
PHASE_COLORS = {'red': '#FFA83D', 'blue': '#45DBFF', 'violet': '#C9A6FF'}
