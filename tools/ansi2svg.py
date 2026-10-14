#!/usr/bin/env python3
"""Convert ANSI-colored text (stdin) to a dark-terminal SVG (stdout). Supports SGR 0, 1, 38;5;N."""
import re, sys, unicodedata
from xml.sax.saxutils import escape

def xterm(n):
    if n < 16:
        base = ["000000","cd0000","00cd00","cdcd00","0000ee","cd00cd","00cdcd","e5e5e5",
                "7f7f7f","ff0000","00ff00","ffff00","5c5cff","ff00ff","00ffff","ffffff"]
        return "#" + base[n]
    if n >= 232:
        v = 8 + (n - 232) * 10
        return "#%02x%02x%02x" % (v, v, v)
    n -= 16
    lv = [0, 95, 135, 175, 215, 255]
    return "#%02x%02x%02x" % (lv[n // 36], lv[(n // 6) % 6], lv[n % 6])

def width(s):
    return sum(2 if unicodedata.east_asian_width(c) in "WF" or ord(c) >= 0x1F300 else 1 for c in s)

FG, BG, CW, LH, PAD = "#d4d4d4", "#1e1e1e", 8.4, 22, 14
tok = re.compile(r"\x1b\[([0-9;]*)m")
lines = sys.stdin.read().rstrip("\n").split("\n")
out, maxw = [], 0
for i, line in enumerate(lines):
    color, bold, pos, spans, plain = FG, False, 0, [], ""
    for m in list(tok.finditer(line)) + [None]:
        end = m.start() if m else len(line)
        seg = line[pos:end]
        if seg:
            spans.append('<tspan fill="%s"%s>%s</tspan>' % (color, ' font-weight="bold"' if bold else "", escape(seg)))
            plain += seg
        if m is None:
            break
        pos = m.end()
        p = [int(x) if x else 0 for x in m.group(1).split(";")]
        if p == [0]: color, bold = FG, False
        elif p == [1]: bold = True
        elif p[:2] == [38, 5]: color = xterm(p[2])
    maxw = max(maxw, width(plain))
    out.append('<text x="%d" y="%d" xml:space="preserve">%s</text>' % (PAD, PAD + LH * (i + 1) - 6, "".join(spans)))
w, h = int(maxw * CW + PAD * 2), LH * len(lines) + PAD * 2
print('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" '
      'font-family="DejaVu Sans Mono, Menlo, Consolas, monospace" font-size="14">' % (w, h, w, h))
print('<rect width="100%%" height="100%%" rx="8" fill="%s"/>' % BG)
print("\n".join(out))
print("</svg>")
