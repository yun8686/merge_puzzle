"""shapes.py の定義を、ゲームと同じ暗い背景の上に並べて描く。
アンチエイリアスのために4倍で描いて縮小する（tools/foe/preview.py と同じ）。"""
import sys
from PIL import Image, ImageDraw
from shapes import MAGES, ORDER, PHASE, PHASE_COLORS

BG = (7, 7, 15)          # Palette.background
PANEL = (20, 20, 36)
SS = 4


def hex2rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def draw_mage(size, ops, tint, bg):
    img = Image.new('RGB', (size*SS, size*SS), bg)
    d = ImageDraw.Draw(img)
    S = size * SS
    body = mix(bg, tint, 0.86)
    glow = mix(tint, (255, 255, 255), 0.55)
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
                for (px, py) in pts:
                    d.ellipse([px-w/2, py-w/2, px+w/2, py+w/2], fill=c)
    return img.resize((size, size), Image.LANCZOS)


def sheet(cell, path, bg=BG):
    pad = max(2, cell // 8)
    W = len(ORDER) * (cell + pad) + pad
    H = cell + pad * 2
    out = Image.new('RGB', (W, H), PANEL)
    for i, key in enumerate(ORDER):
        _, ops = MAGES[key]
        tint = hex2rgb(PHASE_COLORS[PHASE[key]])
        out.paste(draw_mage(cell, ops, tint, bg), (pad + i * (cell + pad), pad))
    out.save(path)
    print(path, out.size, ' '.join(f'{k}:{MAGES[k][0]}' for k in ORDER))


if __name__ == '__main__':
    sheet(
        int(sys.argv[1]) if len(sys.argv) > 1 else 160,
        sys.argv[2] if len(sys.argv) > 2 else 'sheet.png',
    )
