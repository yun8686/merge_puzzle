"""shapes.py の定義を、ゲームと同じ暗い背景の上に並べて描く。
アンチエイリアスのために4倍で描いて縮小する。"""
import sys
from PIL import Image, ImageDraw
from shapes import FOES, WARD_COLORS

BG = (15, 15, 28)        # Palette.boardBg
PANEL = (20, 20, 36)
SS = 4                   # スーパーサンプリング

def hex2rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

def draw_foe(size, ops, tint, bg):
    img = Image.new('RGB', (size*SS, size*SS), bg)
    d = ImageDraw.Draw(img)
    S = size * SS
    body = mix(bg, tint, 0.78)
    glow = mix(tint, (255, 255, 255), 0.45)
    colors = {'fill': body, 'hole': bg, 'glow': glow}
    for layer in ('fill', 'hole', 'glow'):
        for op in ops:
            if op[1] != layer:
                continue
            c = colors[layer]
            if op[0] == 'poly':
                d.polygon([(x*S, y*S) for x, y in op[2]], fill=c)
            elif op[0] == 'circle':
                cx, cy, r = op[2]
                d.ellipse([(cx-r)*S, (cy-r)*S, (cx+r)*S, (cy+r)*S], fill=c)
            elif op[0] == 'line':
                pts = [(x*S, y*S) for x, y in op[2]]
                w = max(1, round(op[3]*S))
                d.line(pts, fill=c, width=w, joint='curve')
                for (px, py) in pts:      # 丸端
                    d.ellipse([px-w/2, py-w/2, px+w/2, py+w/2], fill=c)
    return img.resize((size, size), Image.LANCZOS)

def sheet(cell, path, bg=BG):
    wards = sorted(FOES)
    pad = cell // 8
    W = len(wards) * (cell + pad) + pad
    H = cell + pad * 2
    out = Image.new('RGB', (W, H), PANEL)
    for i, w in enumerate(wards):
        name, ops = FOES[w]
        out.paste(draw_foe(cell, ops, hex2rgb(WARD_COLORS[w]), bg),
                  (pad + i * (cell + pad), pad))
    out.save(path)
    print(path, out.size, ' '.join(f'{w}:{FOES[w][0]}' for w in wards))

if __name__ == '__main__':
    sheet(
        int(sys.argv[1]) if len(sys.argv) > 1 else 160,
        sys.argv[2] if len(sys.argv) > 2 else 'sheet.png',
    )
