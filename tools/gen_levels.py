"""Make assets/levels/levels.json: 6 worlds x 10 levels.

python tools/gen_levels.py
Then calibrate moves and star scores with the autoplayer:
godot --path . -- --calibrate   (rewrites levels.json with "moves" tuned and "stars" filled)

Map legend: '.' cell, ' ' hole, 'i' ice, 'I' double ice, 's' stone, 'S' double stone.
Gem kinds: 0 ruby 1 topaz 2 citrine 3 emerald 4 sapphire 5 amethyst 6 diamond 7 rose.
"""
import json, os

ROOT = os.path.join(os.path.dirname(__file__), "..")

SHAPES = {
    "full": ["........"] * 8,
    "full7": ["......."] * 8,
    "full9": [".........."[:9]] * 9,
    "diamond": ["  ....  ", " ...... ", "........", "........", "........", "........", " ...... ", "  ....  "],
    "heart": [" .. ..  ".replace("  ", "  "), "........", "........", "........", " ...... ", "  ....  ", "   ..   ", "        "],
    "cross": ["  ....  ", "  ....  ", "........", "........", "........", "........", "  ....  ", "  ....  "],
    "hourglass": ["........", " ...... ", "  ....  ", "   ..   ", "  ....  ", " ...... ", "........", "........"],
    "rings": ["........", "........", "..    ..", "..    ..", "..    ..", "..    ..", "........", "........"],
    "pillars": ["........", "........", ". .. . .", "........", "........", ". . .. .", "........", "........"],
    "corners": ["  ....  ", "  ....  ", "........", "........", "........", "........", "  ....  ", "  ....  "],
    "temple": ["   ..   ", "  ....  ", " ...... ", "........", "........", "........", "........", "........"],
    "crown": [". . . . ", "........", "........", "........", "........", "........", " ...... ", "  ....  "],
    "star9": ["    .    ", "   ...   ", ".........", " ....... ", "  .....  ", " ....... ", ".........", "   ...   ", "    .    "],
    "wide9": [".........", ".........", ".........", ".........", ".........", ".........", ".........", "........."],
    "arch": ["........", "........", "........", "........", "........", "...  ...", "...  ...", "...  ..."],
}
# fix the heart: two lobes on top
SHAPES["heart"] = [" ..  .. ", "........", "........", "........", "........", " ...... ", "  ....  ", "   ..   "]


def paint(shape, pattern, ch):
    """Overlay obstacles: pattern is a list of strings where 'x' marks a cell (only on playable cells)."""
    rows = [list(r) for r in shape]
    for y, pr in enumerate(pattern):
        for x, c in enumerate(pr):
            if c == "x" and y < len(rows) and x < len(rows[y]) and rows[y][x] != " ":
                rows[y][x] = ch
    return ["".join(r) for r in rows]


def rows_pattern(h, ys, w=9):
    return ["x" * w if y in ys else "" for y in range(h)]


def block(h, x0, y0, x1, y1, w=9):
    out = []
    for y in range(h):
        out.append("".join("x" if (x0 <= x <= x1 and y0 <= y <= y1) else "." for x in range(w)))
    return out


def ring(h, w=8, inset=0):
    out = []
    for y in range(h):
        out.append("".join("x" if (y in (inset, h - 1 - inset) or x in (inset, w - 1 - inset)) and inset <= y <= h - 1 - inset and inset <= x <= w - 1 - inset else "." for x in range(w)))
    return out


def checker(h, w=8, parity=0, rows=None):
    return ["".join("x" if (x + y) % 2 == parity and (rows is None or y in rows) else "." for x in range(w)) for y in range(h)]


def score(n):
    return {"type": "score", "n": n}


def collect(c, n):
    return {"type": "collect", "color": c, "n": n}


ICE = {"type": "ice"}
STONE = {"type": "stone"}

W1 = [0, 2, 3, 4, 5]
W2 = [0, 2, 3, 4, 5, 6]
W3 = [0, 1, 2, 3, 4, 5, 6]
W4 = [0, 1, 2, 3, 4, 5, 6, 7]


def pick(pool, n, k):
    """n gem kinds from pool, rotating with level index k, always including the newest gem in the pool."""
    newest = pool[-1]
    rest = [c for c in pool if c != newest]
    start = (k * 2) % len(rest)
    sel = [rest[(start + i) % len(rest)] for i in range(n - 1)]
    return sorted(sel + [newest])


L = []


def add(shape, goals, moves, colors, ice=None, ice_ch="i", stone=None, stone_ch="s", tut=None, new_gem=None):
    m = SHAPES[shape] if isinstance(shape, str) else shape
    if ice:
        m = paint(m, ice, ice_ch)
    if stone:
        m = paint(m, stone, stone_ch)
    lv = {"w": max(len(r) for r in m), "h": len(m), "map": m, "goals": goals, "moves": moves, "colors": colors}
    if tut:
        lv["tut"] = tut
    if new_gem is not None:
        lv["new_gem"] = new_gem
    L.append(lv)


# ---------------------------------------------------------------- World 1: Crystal Caves
add("full7", [score(1200)], 18, [0, 2, 3, 4, 5], tut="swap")
add("full", [collect(2, 15)], 20, [0, 2, 3, 4, 5])
add("full", [score(2500)], 20, [0, 2, 3, 4, 5], tut="line")
add("diamond", [collect(0, 18), collect(3, 18)], 22, [0, 2, 3, 4, 5])
add("full", [score(4000)], 20, [0, 2, 3, 4, 5], tut="bomb")
add("cross", [collect(4, 28)], 22, [0, 2, 3, 4, 5])
add("heart", [score(5000)], 22, [0, 2, 3, 4, 5])
add("full", [collect(5, 30)], 22, [0, 2, 3, 4, 5], tut="prism")
add("diamond", [collect(2, 22), collect(4, 22)], 24, [0, 2, 3, 4, 5], tut="combo")
add("wide9", [score(9000)], 24, [0, 2, 3, 4, 5])

# ---------------------------------------------------------------- World 2: Sunken Temple (ice, Star Diamond)
add("full", [ICE], 22, [0, 2, 3, 4, 6], ice=block(8, 2, 2, 5, 5), tut="ice", new_gem=6)
add("full", [ICE, collect(6, 15)], 24, [2, 3, 4, 5, 6], ice=rows_pattern(8, [6, 7]))
add("diamond", [ICE], 24, [0, 3, 4, 5, 6], ice=ring(8))
add("full", [score(6000), ICE], 24, [0, 2, 4, 5, 6], ice=checker(8, rows=[3, 4, 5, 6, 7]))
add("cross", [ICE], 26, [0, 2, 3, 5, 6], ice=block(8, 2, 2, 5, 5), ice_ch="I")
add("heart", [collect(0, 25), ICE], 26, [0, 2, 3, 4, 6], ice=rows_pattern(8, [1, 2]))
add("full", [ICE], 26, [2, 3, 4, 5, 6], ice=checker(8), ice_ch="i")
add("wide9", [ICE, score(8000)], 26, [0, 2, 3, 4, 6], ice=rows_pattern(8, [0, 7]), ice_ch="I")
add("hourglass", [ICE], 26, [0, 3, 4, 5, 6], ice=block(8, 0, 6, 8, 7))
add("full", [ICE, collect(6, 22), collect(4, 22)], 28, [0, 2, 3, 4, 6], ice=ring(8, inset=1))

# ---------------------------------------------------------------- World 3: Golden Dunes (shapes, Fire Topaz)
add("temple", [collect(1, 20)], 22, [0, 1, 2, 3, 4], tut=None, new_gem=1)
add("pillars", [score(7000)], 24, [1, 2, 3, 4, 6])
add("rings", [ICE], 24, [0, 1, 3, 4, 5], ice=rows_pattern(8, [0, 1]), ice_ch="I")
add("crown", [collect(1, 25), collect(2, 25)], 26, [0, 1, 2, 4, 6])
add("star9", [score(8000)], 24, [0, 1, 3, 4, 5])
add("arch", [ICE], 26, [1, 2, 3, 5, 6], ice=rows_pattern(8, [6, 7]))
add("hourglass", [collect(6, 22), ICE], 26, [0, 1, 3, 4, 6], ice=rows_pattern(8, [3, 4]), ice_ch="I")
add("temple", [score(10000)], 26, [0, 1, 2, 3, 4, 5])
add("rings", [collect(0, 25), collect(1, 25)], 28, [0, 1, 2, 4, 6])
add("star9", [ICE, score(9000)], 28, [0, 1, 2, 3, 6], ice=block(9, 3, 3, 5, 5))

# ---------------------------------------------------------------- World 4: Firefly Forest (stones, Rose Heart)
add("full", [STONE], 22, [0, 3, 4, 5, 7], stone=rows_pattern(8, [7]), tut="stone", new_gem=7)
add("full", [collect(7, 22), STONE], 24, [1, 3, 4, 6, 7], stone=block(8, 3, 3, 4, 4))
add("diamond", [STONE, ICE], 26, [0, 2, 3, 5, 7], stone=block(8, 2, 6, 5, 6), ice=rows_pattern(8, [7, 5]))
add("cross", [score(9000)], 24, [0, 1, 3, 4, 7], stone=block(8, 0, 2, 0, 5) + [], )
add("full", [STONE], 26, [2, 3, 4, 6, 7], stone=checker(8, rows=[6, 7]))
add("heart", [collect(7, 30), STONE], 26, [0, 3, 4, 5, 7], stone=block(8, 3, 4, 4, 5))
add("wide9", [STONE, ICE], 28, [0, 1, 3, 4, 7], stone=rows_pattern(8, [3]), ice=rows_pattern(8, [6, 7]))
add("pillars", [STONE], 28, [1, 2, 3, 5, 7], stone=ring(8, inset=2))
add("full", [score(12000), STONE], 28, [0, 2, 3, 4, 5, 7], stone=checker(8, parity=1, rows=[0, 1]))
add("temple", [STONE, ICE, collect(3, 20)], 30, [0, 1, 3, 4, 7], stone=rows_pattern(8, [7]), ice=block(8, 2, 3, 5, 5))

# ---------------------------------------------------------------- World 5: Fire Forge
add("full", [ICE], 26, [0, 1, 2, 4, 7], ice=checker(8), ice_ch="i")
add("crown", [STONE, collect(1, 25)], 28, [0, 1, 3, 4, 6], stone=rows_pattern(8, [7]))
add("star9", [ICE], 28, [0, 1, 2, 3, 5], ice=block(9, 2, 2, 6, 6), ice_ch="I")
add("rings", [STONE], 28, [1, 2, 4, 6, 7], stone=rows_pattern(8, [1, 6]))
add("full", [score(10000)], 26, [0, 1, 2, 3, 4])
add("hourglass", [STONE, ICE], 30, [0, 1, 3, 5, 7], stone=rows_pattern(8, [3]), ice=rows_pattern(8, [6, 7]))
add("wide9", [collect(0, 30), collect(1, 30)], 30, [0, 1, 2, 4, 6])
add("diamond", [STONE], 30, [1, 2, 3, 6, 7], stone=ring(8, inset=1))
add("arch", [ICE, STONE], 30, [0, 2, 3, 4, 7], ice=rows_pattern(8, [0, 1, 2]), stone=rows_pattern(8, [7]))
add("full9", [score(11000), ICE], 30, [0, 1, 2, 3, 6], ice=ring(9, w=9))

# ---------------------------------------------------------------- World 6: Star Crown
add("star9", [collect(6, 35), collect(7, 35)], 30, [1, 3, 5, 6, 7])
add("full", [STONE, ICE], 30, [0, 1, 2, 6, 7], stone=checker(8, rows=[7]), stone_ch="S", ice=checker(8, parity=1, rows=[3, 4, 5, 6, 7]))
add("heart", [score(11000)], 28, [0, 1, 2, 3, 7])
add("cross", [ICE], 30, [0, 2, 4, 6, 7], ice=block(8, 0, 0, 7, 7))
add("rings", [STONE, collect(5, 22)], 30, [1, 2, 3, 5, 7], stone=rows_pattern(8, [0, 7]))
add("crown", [ICE, STONE], 32, [0, 1, 3, 6, 7], ice=rows_pattern(8, [2, 3, 4]), stone=rows_pattern(8, [6]))
add("full9", [score(14000)], 30, [0, 1, 2, 3, 4, 5])
add("hourglass", [collect(0, 25), collect(4, 25), collect(6, 25)], 32, [0, 2, 4, 6, 7])
add("star9", [ICE, STONE], 32, [0, 1, 2, 6, 7], ice=block(9, 2, 3, 6, 5), ice_ch="I", stone=rows_pattern(9, [0, 8]), stone_ch="S")
add("full9", [score(12000), ICE, STONE], 34, [0, 1, 2, 3, 4, 6], ice=checker(9, w=9), stone=rows_pattern(9, [8]))

assert len(L) == 60, len(L)
os.makedirs(os.path.join(ROOT, "assets", "levels"), exist_ok=True)
with open(os.path.join(ROOT, "assets", "levels", "levels.json"), "w") as f:
    json.dump(L, f, indent=1)
print("levels:", len(L))

# sanity checks
for n, lv in enumerate(L, 1):
    flat = "".join(lv["map"])
    for g in lv["goals"]:
        if g["type"] == "collect":
            assert g["color"] in lv["colors"], (n, g)
        if g["type"] == "ice":
            assert "i" in flat or "I" in flat, n
        if g["type"] == "stone":
            assert "s" in flat or "S" in flat, n
    assert all(len(r) <= lv["w"] for r in lv["map"]), n
print("checks ok")
