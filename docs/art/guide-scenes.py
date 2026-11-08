"""Beacon placement guide scenes, in the 1.1 picture-book style.

Each scene is a 390x470 SVG rendered at 3x (1170x1410) into App/Assets.xcassets/Guide*.imageset.
Render: python3 docs/art/guide-scenes.py <out-dir>, then screenshot each SVG at 1170x1410
(Playwright: page.setContent(svg); page.screenshot(clip=...)).

Hardware is drawn to match the real Blue Charm beacons: the BC-U1 is a tiny black USB nub
(smaller than a US quarter) that disappears into a USB wall charger; the BC05 is a white puck
about two inches across with a square QR label on top.
"""
import math
import pathlib
import sys

G, DOT, FLOOR, Y, R, NIGHT, CREAM, INK, BLUSH, MOTION = (
    "#2F6B45", "#265939", "#8E2A20", "#F2C849", "#C23B2E", "#1D2B45", "#F7EFDD", "#23302A", "#DF9E8E", "#CFD4BE")
WHITE, NUB, METAL, COIN, SHADE = "#FFFCF5", "#2B302D", "#C9CCC5", "#B9BCB4", "#1E4A30"
SW = 3  # outline width at 1x
FONT = 'font-family="Avenir Next, Helvetica" font-weight="700"'


def frame(body, floor=True, rug=True):
    dots = "".join(f'<circle cx="{x}" cy="{y}" r="4.5" fill="{DOT}"/>' for x, y in
                   [(30, 90), (300, 70), (365, 40), (30, 220), (350, 150), (280, 180), (20, 340), (330, 250)])
    fl = (f'<rect x="0" y="392" width="390" height="78" fill="{FLOOR}"/>'
          f'<line x1="0" y1="392" x2="390" y2="392" stroke="{INK}" stroke-width="{SW}"/>') if floor else ""
    rg = (f'<ellipse cx="96" cy="436" rx="80" ry="17" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
          f'<ellipse cx="96" cy="436" rx="56" ry="10" fill="none" stroke="{R}" stroke-width="2.5"/>') if rug else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 390 470" width="1170" height="1410">'
            f'<rect width="390" height="470" fill="{G}"/>{dots}{fl}{rg}{body}</svg>')


def arcs(cx, cy, radii, start=200, end=340, width=3.5):
    """Yellow signal arcs that fade as they widen, like BeaconScene."""
    out = []
    for i, r in enumerate(radii):
        a0, a1 = math.radians(start), math.radians(end)
        x0, y0 = cx + r * math.cos(a0), cy + r * math.sin(a0)
        x1, y1 = cx + r * math.cos(a1), cy + r * math.sin(a1)
        large = 1 if (end - start) % 360 > 180 else 0
        op = max(0.25, 1 - i * 0.22)
        out.append(f'<path d="M{x0:.1f},{y0:.1f} A{r},{r} 0 {large} 1 {x1:.1f},{y1:.1f}" fill="none" '
                   f'stroke="{Y}" stroke-opacity="{op:.2f}" stroke-width="{width}" stroke-linecap="round"/>')
    return "".join(out)


def phone(x, y, s=1.0, mood="sleep", legs=True):
    """The phone character; (x, y) is its top-left at scale s (1.0 = 86x152 like BeaconScene)."""
    face = {
        "sleep": f'<path d="M23,62 q6,6 12,0 M51,62 q6,6 12,0" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>'
                 f'<path d="M31,92 q12,6 24,0" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>',
        "awake": f'<circle cx="30" cy="64" r="4.5" fill="{INK}"/><circle cx="56" cy="64" r="4.5" fill="{INK}"/>'
                 f'<path d="M31,90 q12,8 24,0" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>',
        "sly": f'<circle cx="32" cy="64" r="4.5" fill="{INK}"/><circle cx="58" cy="64" r="4.5" fill="{INK}"/>'
               f'<path d="M24,54 l12,4 M50,58 l12,-4" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>'
               f'<path d="M33,92 q14,4 24,-6" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>',
    }[mood]
    lg = (f'<path d="M30,150 l-5,40 h-12 M58,150 l6,40 h12" fill="none" stroke="{INK}" stroke-width="5" '
          f'stroke-linecap="round" stroke-linejoin="round"/>') if legs else ""
    return (f'<g transform="translate({x},{y}) scale({s})">{lg}'
            f'<rect x="1.5" y="1.5" width="83" height="149" rx="22" fill="{NIGHT}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<rect x="10" y="14" width="66" height="120" rx="10" fill="{CREAM}"/>'
            f'<circle cx="25" cy="76" r="4.5" fill="{BLUSH}"/><circle cx="61" cy="76" r="4.5" fill="{BLUSH}"/>{face}</g>')


def nub(x, y, s=1.0, loose=False):
    """The BC-U1: a black cap; loose shows its silver USB plug below it. (x, y) is the cap's center."""
    plug = (f'<rect x="-9" y="7" width="18" height="24" rx="1.5" fill="{METAL}" stroke="{INK}" stroke-width="2"/>'
            f'<rect x="-5.5" y="12" width="3.5" height="3.5" fill="{INK}"/><rect x="2" y="12" width="3.5" height="3.5" fill="{INK}"/>'
            ) if loose else ""
    return (f'<g transform="translate({x},{y}) scale({s})">{plug}'
            f'<rect x="-11" y="-9" width="22" height="18" rx="3.5" fill="{NUB}" stroke="{INK}" stroke-width="2.5"/>'
            f'<path d="M-7,-5 h8" stroke="#4A524D" stroke-width="2" stroke-linecap="round"/></g>')


def charger(x, y, s=1.0, with_nub=True):
    """A white USB wall charger, front view, with the BC-U1 in its bottom port. (x, y) is the brick's center."""
    n = nub(0, 29, 0.9) if with_nub else f'<rect x="-8" y="21" width="16" height="4" rx="1" fill="{INK}"/>'
    return (f'<g transform="translate({x},{y}) scale({s})">'
            f'<rect x="-21" y="-23" width="42" height="46" rx="9" fill="{WHITE}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<path d="M-12,-12 h24" stroke="#D9D3C6" stroke-width="2" stroke-linecap="round"/>{n}</g>')


def outlet(x, y, w=26, h=34):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="4" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>'
            f'<rect x="{x + w/2 - 5}" y="{y + h*0.26}" width="2.5" height="{h*0.2}" fill="{INK}"/>'
            f'<rect x="{x + w/2 + 2.5}" y="{y + h*0.26}" width="2.5" height="{h*0.2}" fill="{INK}"/>'
            f'<circle cx="{x + w/2}" cy="{y + h*0.7}" r="2.2" fill="{INK}"/>')


def plate(cx, cy, w=58, h=96):
    """A two-socket wall plate centered on (cx, cy)."""
    return (f'<rect x="{cx - w/2}" y="{cy - h/2}" width="{w}" height="{h}" rx="8" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>'
            + outlet(cx - 16, cy - h/2 + 8, 32, 36) + outlet(cx - 16, cy + h/2 - 44, 32, 36))


def puck(x, y, r=17):
    """The BC05: white puck, square QR label, twist notch near the bottom edge."""
    q = r * 0.62
    cells = "".join(
        f'<rect x="{x - q/2 + q*fx:.1f}" y="{y - q/2 - r*0.08 + q*fy:.1f}" width="{q*0.26:.1f}" height="{q*0.26:.1f}" fill="{INK}"/>'
        for fx, fy in [(0.06, 0.06), (0.68, 0.06), (0.06, 0.68)])
    bits = "".join(
        f'<rect x="{x - q/2 + q*fx:.1f}" y="{y - q/2 - r*0.08 + q*fy:.1f}" width="{q*0.12:.1f}" height="{q*0.12:.1f}" fill="{INK}"/>'
        for fx, fy in [(0.45, 0.2), (0.45, 0.48), (0.7, 0.55), (0.8, 0.78), (0.5, 0.8), (0.3, 0.45)]) if r > 30 else ""
    return (f'<circle cx="{x}" cy="{y}" r="{r}" fill="{WHITE}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<rect x="{x - q/2:.1f}" y="{y - q/2 - r*0.08:.1f}" width="{q:.1f}" height="{q:.1f}" rx="{r*0.04:.1f}" fill="#FFFFFF" stroke="#CFC8BA" stroke-width="1.2"/>'
            f'{cells}{bits}'
            f'<path d="M{x - r*0.45:.1f},{y + r*0.72:.1f} q{r*0.45:.1f},{-r*0.16:.1f} {r*0.9:.1f},0" fill="none" stroke="#CFC8BA" stroke-width="{max(1.2, r*0.04):.1f}" stroke-linecap="round"/>')


def coin(x, y, r):
    return (f'<circle cx="{x}" cy="{y}" r="{r}" fill="{COIN}" stroke="{INK}" stroke-width="2.5"/>'
            f'<circle cx="{x}" cy="{y}" r="{r*0.8}" fill="none" stroke="#9A9E95" stroke-width="2"/>')


def tape(x, y, w, h, angle):
    return (f'<rect x="{x - w/2}" y="{y - h/2}" width="{w}" height="{h}" rx="2" fill="{Y}" fill-opacity="0.92" '
            f'stroke="{INK}" stroke-width="2" transform="rotate({angle} {x} {y})"/>')


def badge(x, y, ok, r=19):
    if ok:
        mark = f'<path d="M{x - r*0.45},{y + r*0.02} l{r*0.32},{r*0.34} l{r*0.6},{-r*0.68}" fill="none" stroke="{G}" stroke-width="{r*0.28}" stroke-linecap="round" stroke-linejoin="round"/>'
        return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>{mark}'
    d = r * 0.38
    mark = (f'<path d="M{x - d},{y - d} L{x + d},{y + d} M{x + d},{y - d} L{x - d},{y + d}" stroke="{CREAM}" '
            f'stroke-width="{r*0.26}" stroke-linecap="round"/>')
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{R}" stroke="{INK}" stroke-width="{SW}"/>{mark}'


_clip = [0]


def callout(cx, cy, r, inner, tx, ty, bg=G):
    """A round close-up at (cx, cy), with a pointer back to (tx, ty). `inner` is drawn around (0, 0)."""
    _clip[0] += 1
    cid = f"zoom{_clip[0]}"
    ang = math.atan2(ty - cy, tx - cx)
    ex, ey = cx + r * math.cos(ang), cy + r * math.sin(ang)
    return (f'<line x1="{ex:.1f}" y1="{ey:.1f}" x2="{tx}" y2="{ty}" stroke="{CREAM}" stroke-width="3" stroke-dasharray="2 6" stroke-linecap="round"/>'
            f'<circle cx="{tx}" cy="{ty}" r="13" fill="none" stroke="{CREAM}" stroke-width="3"/>'
            f'<defs><clipPath id="{cid}"><circle cx="{cx}" cy="{cy}" r="{r}"/></clipPath></defs>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{bg}"/>'
            f'<g clip-path="url(#{cid})"><g transform="translate({cx},{cy})">{inner}</g></g>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{CREAM}" stroke-width="7"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{r + 3.5}" fill="none" stroke="{INK}" stroke-width="{SW}"/>')


def zz(x, y):
    return (f'<text x="{x}" y="{y}" {FONT} font-size="17" fill="{CREAM}">z</text>'
            f'<text x="{x + 12}" y="{y - 14}" {FONT} font-size="12" fill="{CREAM}">z</text>')


def bed_side(dx=0, mood="sleep"):
    """A bed from the side, headboard on the right, phone on the pillow. dx shifts it left/right."""
    return (f'<g transform="translate({dx},0)">'
            f'<rect x="300" y="170" width="22" height="222" rx="5" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<rect x="40" y="290" width="282" height="26" rx="5" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<rect x="48" y="316" width="14" height="76" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<rect x="40" y="246" width="262" height="44" rx="10" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<ellipse cx="258" cy="236" rx="36" ry="14" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>'
            + phone(228, 200, 0.36, mood=mood, legs=False) +
            f'<path d="M34,240 h220 q8,0 8,10 v44 h-228 z" fill="{R}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<path d="M44,262 q100,6 210,0 M44,276 q100,6 210,0" fill="none" stroke="{Y}" stroke-width="3" stroke-linecap="round"/>'
            '</g>')


def bed_front():
    """A bed seen from the foot, tall legs, with the phone tucked in on the pillows."""
    return (
        f'<rect x="64" y="176" width="262" height="170" rx="20" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
        f'<rect x="84" y="194" width="222" height="56" rx="12" fill="none" stroke="{INK}" stroke-width="2.5"/>'
        f'<ellipse cx="140" cy="270" rx="44" ry="17" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>'
        f'<ellipse cx="250" cy="270" rx="44" ry="17" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>'
        + phone(181, 238, 0.33, legs=False) +
        f'<path d="M44,280 h302 v52 q-151,10 -302,0 z" fill="{R}" stroke="{INK}" stroke-width="{SW}"/>'
        f'<path d="M44,280 h302 v10 h-302 z" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>'
        f'<path d="M50,306 q145,8 290,0 M50,320 q145,8 290,0" fill="none" stroke="{Y}" stroke-width="3" stroke-linecap="round"/>'
        f'<rect x="56" y="334" width="13" height="58" rx="3" fill="{INK}"/>'
        f'<rect x="321" y="334" width="13" height="58" rx="3" fill="{INK}"/>'
        + zz(230, 232)
    )


# MARK: - Scenes

def scene_hardware():
    """What the two beacons look like, with a quarter for scale: the USB nub and where it goes, and the puck."""
    card = (f'<rect x="22" y="30" width="346" height="410" rx="24" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<line x1="44" y1="236" x2="346" y2="236" stroke="#D6CDBA" stroke-width="3" stroke-dasharray="3 8" stroke-linecap="round"/>')
    # Top: the BC-U1 loose (true scale next to the quarter), then plugged into a charger.
    top = (nub(66, 98, 2.0, loose=True) + coin(136, 132, 29) +
           f'<path d="M176,150 q22,-34 52,-30" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>'
           f'<path d="M218,112 l12,8 l-13,7" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>'
           + plate(290, 132, 82, 150).replace(f'fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"', f'fill="#EFE6D3" stroke="{INK}" stroke-width="{SW}"', 1)
           + charger(290, 94, 1.15))
    # Bottom: the BC05 puck next to the same quarter.
    bottom = puck(140, 336, 58) + coin(270, 360, 29)
    return frame(card + top + bottom, floor=False, rug=False)


def scene_nightstand():
    """The mistake: beacon on the nightstand outlet, in easy reach from bed."""
    stand = (f'<rect x="268" y="300" width="104" height="92" rx="6" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
             f'<line x1="278" y1="344" x2="362" y2="344" stroke="{INK}" stroke-width="2.5"/>'
             f'<circle cx="320" cy="322" r="5" fill="{INK}"/><circle cx="320" cy="366" r="5" fill="{INK}"/>')
    gear = outlet(303, 216, 34, 46) + charger(320, 240, 0.85)
    sig = arcs(320, 266, [42, 62, 82], start=-60, end=60, width=3)
    reach = (f'<path d="M222,214 q30,-36 74,-4" fill="none" stroke="{CREAM}" stroke-width="3" stroke-dasharray="2 7" stroke-linecap="round"/>'
             f'<path d="M286,202 l12,9 l-14,5" fill="none" stroke="{CREAM}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>')
    return frame(bed_side(-70, mood="sly") + stand + sig + gear + reach + badge(40, 40, False), rug=False)


def scene_under_bed():
    """USB beacon on a charger low on the wall, in the dark gap under the bed, with a close-up."""
    under = f'<rect x="69" y="337" width="252" height="55" fill="{INK}" opacity="0.35"/>'
    gear = outlet(226, 346, 28, 38) + charger(240, 360, 0.5)
    close = plate(0, 6, 70, 116) + charger(0, -18, 1.2)
    rug = (f'<ellipse cx="96" cy="436" rx="80" ry="17" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
           f'<ellipse cx="96" cy="436" rx="56" ry="10" fill="none" stroke="{R}" stroke-width="2.5"/>')
    return frame(under + gear + bed_front() + rug + callout(306, 98, 66, close, 240, 366) + badge(40, 40, True), rug=False)


def scene_cover():
    """Close-up: charger and beacon shut inside a childproof outlet box, behind a dresser's edge."""
    wall_plate = (f'<rect x="138" y="128" width="124" height="200" rx="14" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>'
                  + outlet(176, 270, 48, 44))
    gear = charger(200, 186, 1.4)
    box = (f'<rect x="150" y="138" width="100" height="126" rx="16" fill="{CREAM}" fill-opacity="0.38" '
           f'stroke="{INK}" stroke-width="{SW}"/>'
           f'<rect x="190" y="130" width="20" height="14" rx="4" fill="{Y}" stroke="{INK}" stroke-width="2.5"/>'
           f'<path d="M196,130 v-6 a4,4 0 0 1 8,0 v6" fill="none" stroke="{INK}" stroke-width="2.5"/>')
    signal = (arcs(200, 200, [72, 100, 128], start=-50, end=50, width=3.5)
              + arcs(200, 200, [72, 100, 128], start=130, end=230, width=3.5))
    dresser = (f'<rect x="-20" y="150" width="120" height="242" rx="8" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
               f'<line x1="-20" y1="270" x2="88" y2="270" stroke="{INK}" stroke-width="2.5"/>'
               f'<circle cx="50" cy="210" r="6" fill="{INK}"/><circle cx="50" cy="330" r="6" fill="{INK}"/>')
    return frame(signal + wall_plate + gear + box + dresser + badge(40, 40, True), rug=False)


def scene_puck():
    """The battery puck taped under the bed frame, seen from the side, with a close-up of the tape."""
    shade = f'<rect x="62" y="316" width="238" height="76" fill="{INK}" opacity="0.3"/>'
    p = puck(150, 334, 16) + tape(150, 318, 44, 9, -4)
    rings = arcs(150, 334, [26, 40, 54], start=20, end=160, width=3)
    close = (f'<rect x="-90" y="-90" width="180" height="46" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
             + puck(0, 0, 44) + tape(-30, -38, 26, 64, -18) + tape(30, -38, 26, 64, 18))
    return frame(shade + bed_side() + zz(276, 196) + rings + p
                 + callout(112, 124, 62, close, 150, 334, bg="#2A5E3E") + badge(40, 40, True), rug=False)


def scene_plan():
    """Top-down plan: beacon at the far wall, signal fading before the door; not by the door."""
    room = (f'<defs><clipPath id="room"><rect x="34" y="40" width="322" height="318"/></clipPath></defs>'
            f'<rect x="34" y="40" width="322" height="318" fill="{FLOOR}"/>'
            f'<ellipse cx="120" cy="296" rx="62" ry="40" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<ellipse cx="120" cy="296" rx="42" ry="24" fill="none" stroke="{R}" stroke-width="2.5"/>'
            f'<g clip-path="url(#room)">'
            f'<circle cx="96" cy="58" r="230" fill="{Y}" fill-opacity="0.13"/>'
            f'<circle cx="96" cy="58" r="160" fill="{Y}" fill-opacity="0.13"/>'
            f'<circle cx="96" cy="58" r="90" fill="{Y}" fill-opacity="0.16"/></g>')
    bed = (f'<rect x="120" y="46" width="130" height="176" rx="10" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>'
           f'<rect x="132" y="56" width="48" height="30" rx="10" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>'
           f'<rect x="190" y="56" width="48" height="30" rx="10" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>'
           f'<rect x="120" y="98" width="130" height="124" rx="10" fill="{R}" stroke="{INK}" stroke-width="{SW}"/>'
           f'<path d="M120,112 h130" stroke="{CREAM}" stroke-width="8"/>'
           f'<path d="M134,150 v66 M236,150 v66" stroke="{Y}" stroke-width="3" stroke-linecap="round"/>'
           f'<rect x="56" y="46" width="56" height="44" rx="6" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
           f'<circle cx="84" cy="68" r="5" fill="{INK}"/>')
    good = nub(100, 56, 0.8) + badge(74, 112, True, r=14)
    bad = nub(322, 280, 0.8) + badge(322, 250, False, r=14)
    walls = (f'<path d="M244,358 H34 V40 H356 V358 H310" fill="none" stroke="{CREAM}" stroke-width="12" stroke-linejoin="round"/>'
             f'<path d="M244,358 H34 V40 H356 V358 H310" fill="none" stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round"/>'
             f'<path d="M244,358 A66,66 0 0 1 310,292" fill="none" stroke="{CREAM}" stroke-width="2.5" stroke-dasharray="5 5"/>'
             f'<line x1="244" y1="358" x2="310" y2="292" stroke="{CREAM}" stroke-width="5" stroke-linecap="round"/>')
    hall = (phone(262, 380, 0.42, mood="awake") +
            "".join(f'<line x1="{x}" y1="{y}" x2="{x + 26}" y2="{y}" stroke="{MOTION}" stroke-width="4" stroke-linecap="round"/>'
                    for x, y in [(214, 398), (206, 412), (216, 426)]))
    return frame(room + bed + walls + good + bad + hall, floor=False, rug=False)


def scene_hub():
    """A spare iPad on the dresser, plugged in, standing in for the beacon."""
    dresser = (f'<rect x="212" y="300" width="148" height="92" rx="6" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
               f'<line x1="222" y1="340" x2="350" y2="340" stroke="{INK}" stroke-width="2.5"/>'
               f'<circle cx="286" cy="320" r="5" fill="{INK}"/><circle cx="286" cy="362" r="5" fill="{INK}"/>')
    ipad = (f'<path d="M262,300 l10,-20 h28 l10,20" fill="{INK}"/>'
            f'<rect x="236" y="168" width="100" height="128" rx="12" fill="{NIGHT}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<rect x="245" y="178" width="82" height="108" rx="6" fill="{NIGHT}" stroke="{CREAM}" stroke-width="1.5" stroke-opacity="0.4"/>'
            f'<circle cx="286" cy="226" r="20" fill="{Y}"/><circle cx="296" cy="218" r="18" fill="{NIGHT}"/>'
            f'<circle cx="262" cy="196" r="1.8" fill="{Y}"/><circle cx="312" cy="262" r="1.8" fill="{Y}"/>'
            f'<path d="M300,296 q10,10 -10,12 h-60 q-20,0 -20,20 v18 h-10" fill="none" stroke="{INK}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>'
            + outlet(178, 330) + f'<rect x="196" y="338" width="16" height="16" rx="3" fill="{WHITE}" stroke="{INK}" stroke-width="2.5"/>')
    signal = arcs(286, 226, [70, 100, 130], start=200, end=340)
    return frame(signal + dresser + ipad + phone(62, 196, 0.95, mood="sleep"))


SCENES = {
    "GuideHardware": scene_hardware,
    "GuideNightstand": scene_nightstand,
    "GuideUnderBed": scene_under_bed,
    "GuideOutletCover": scene_cover,
    "GuidePuck": scene_puck,
    "GuideFloorPlan": scene_plan,
    "GuideHub": scene_hub,
}

if __name__ == "__main__":
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "guide-scenes")
    out.mkdir(parents=True, exist_ok=True)
    for name, fn in SCENES.items():
        (out / f"{name}.svg").write_text(fn())
    print("\n".join(SCENES))
