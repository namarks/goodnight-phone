"""Beacon placement guide scenes, in the 1.1 picture-book style.

Each scene is a 390x470 SVG rendered at 3x (1170x1410) into App/Assets.xcassets/Guide*.imageset.
Render: python3 docs/art/guide-scenes.py <out-dir>, then screenshot each SVG at 1170x1410
(Playwright: page.setContent(svg); page.screenshot(clip=...)).

Hardware is drawn to match the real Blue Charm beacons: the BC-U1 is a tiny black USB nub
(smaller than a US quarter) that disappears into a USB wall charger; the BC05 is a white puck
about two inches across with a square QR label on top.
"""
import pathlib
import sys

G, FLOOR, Y, R, NIGHT, CREAM, INK, BLUSH = (
    "#2F6B45", "#8E2A20", "#F2C849", "#C23B2E", "#1D2B45", "#F7EFDD", "#23302A", "#DF9E8E")
WHITE, NUB, METAL, COIN = "#FFFCF5", "#2B302D", "#C9CCC5", "#B9BCB4"
SW = 3  # outline width at 1x
FONT = 'font-family="Avenir Next, Helvetica" font-weight="700"'


def frame(body, floor=True):
    """Plain wall and floor. Kept deliberately empty so each scene shows one idea."""
    fl = (f'<rect x="0" y="392" width="390" height="78" fill="{FLOOR}"/>'
          f'<line x1="0" y1="392" x2="390" y2="392" stroke="{INK}" stroke-width="{SW}"/>') if floor else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 390 470" width="1170" height="1410">'
            f'<rect width="390" height="470" fill="{G}"/>{fl}{body}</svg>')


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


def hub(x, y, s=1.0):
    """The bedroom hub: a white outlet cube on a wall plate, with the thumbnail-sized XIAO board
    sticking out flat from a side USB-C port on a small adapter. (x, y) is the cube's center."""
    return (f'<g transform="translate({x},{y}) scale({s})">'
            f'<rect x="-30" y="-36" width="60" height="72" rx="10" fill="{WHITE}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<rect x="-14" y="-24" width="3" height="11" fill="{INK}"/><rect x="11" y="-24" width="3" height="11" fill="{INK}"/>'
            f'<rect x="-14" y="10" width="3" height="11" fill="{INK}"/><rect x="11" y="10" width="3" height="11" fill="{INK}"/>'
            f'<rect x="30" y="-6" width="9" height="12" rx="2" fill="{METAL}" stroke="{INK}" stroke-width="2"/>'
            f'<rect x="38" y="-13" width="30" height="26" rx="3" fill="{NIGHT}" stroke="{INK}" stroke-width="2.5"/>'
            f'<rect x="47" y="-8" width="16" height="16" rx="1.5" fill="{METAL}" stroke="{INK}" stroke-width="1.5"/>'
            f'<circle cx="42.5" cy="-8" r="1.6" fill="{Y}"/><circle cx="42.5" cy="8" r="1.6" fill="{Y}"/></g>')


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


def badge(x, y, ok, r=19):
    if ok:
        mark = f'<path d="M{x - r*0.45},{y + r*0.02} l{r*0.32},{r*0.34} l{r*0.6},{-r*0.68}" fill="none" stroke="{G}" stroke-width="{r*0.28}" stroke-linecap="round" stroke-linejoin="round"/>'
        return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>{mark}'
    d = r * 0.38
    mark = (f'<path d="M{x - d},{y - d} L{x + d},{y + d} M{x + d},{y - d} L{x - d},{y + d}" stroke="{CREAM}" '
            f'stroke-width="{r*0.26}" stroke-linecap="round"/>')
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{R}" stroke="{INK}" stroke-width="{SW}"/>{mark}'


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


# MARK: - Scenes
# One idea per scene: the thing to look at is big, everything else is the minimum to place it.

def under_bed(content):
    """Low view under a bed: blanket and frame across the top, legs, shadow; `content` sits in the gap."""
    return (f'<rect x="40" y="150" width="310" height="242" fill="{INK}" opacity="0.28"/>'
            + content +
            f'<path d="M-10,-10 H400 V112 Q195,128 -10,112 Z" fill="{R}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<path d="M-10,82 Q195,98 400,82" fill="none" stroke="{Y}" stroke-width="4" stroke-linecap="round"/>'
            f'<rect x="-10" y="116" width="410" height="34" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<rect x="28" y="150" width="22" height="242" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<rect x="340" y="150" width="22" height="242" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>')


def scene_hardware():
    """What the two beacons look like, next to a quarter: the USB nub going into a charger, and the puck."""
    card = f'<rect x="22" y="30" width="346" height="410" rx="24" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>'
    top = (nub(66, 98, 2.0, loose=True) + coin(136, 132, 29) +
           f'<path d="M176,150 q22,-34 52,-30" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>'
           f'<path d="M218,112 l12,8 l-13,7" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>'
           + plate(290, 132, 82, 150).replace(f'fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"', f'fill="#EFE6D3" stroke="{INK}" stroke-width="{SW}"', 1)
           + charger(290, 94, 1.15))
    either = (f'<line x1="52" y1="236" x2="160" y2="236" stroke="#D6CDBA" stroke-width="3" stroke-linecap="round"/>'
              f'<line x1="230" y1="236" x2="338" y2="236" stroke="#D6CDBA" stroke-width="3" stroke-linecap="round"/>'
              f'<text x="195" y="245" text-anchor="middle" {FONT} font-size="26" fill="{INK}" fill-opacity="0.7">or</text>')
    bottom = puck(140, 336, 58) + coin(270, 360, 29)
    return frame(card + top + either + bottom, floor=False)


def scene_nightstand():
    """The mistake: beacon at the nightstand outlet, in easy reach from bed."""
    stand = (f'<rect x="268" y="300" width="104" height="92" rx="6" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
             f'<line x1="278" y1="344" x2="362" y2="344" stroke="{INK}" stroke-width="2.5"/>'
             f'<circle cx="320" cy="322" r="5" fill="{INK}"/><circle cx="320" cy="366" r="5" fill="{INK}"/>')
    gear = outlet(300, 206, 40, 54) + charger(320, 234, 1.0)
    reach = (f'<path d="M222,214 q30,-40 64,-14" fill="none" stroke="{CREAM}" stroke-width="3.5" stroke-dasharray="2 8" stroke-linecap="round"/>'
             f'<path d="M276,192 l12,10 l-15,4" fill="none" stroke="{CREAM}" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>')
    return frame(bed_side(-70, mood="sly") + stand + gear + reach + badge(40, 40, False))


def scene_under_bed():
    """The charger and beacon at the outlet under the bed, big."""
    gear = plate(195, 300, 66, 104) + charger(195, 274, 1.3)
    return frame(under_bed(gear) + badge(40, 40, True))


def scene_puck():
    """The battery puck stuck to the wall under the bed. The mounting strip behind it isn't drawn:
    a pull tab read as a lollipop stick, and tape read as flimsy. The copy says what to use."""
    p = puck(195, 262, 50)
    return frame(under_bed(p) + badge(40, 40, True))


def scene_plan():
    """Top-down plan: beacon on the far side of the room is good, by the door is not."""
    room = (f'<defs><clipPath id="room"><rect x="34" y="40" width="322" height="318"/></clipPath></defs>'
            f'<rect x="34" y="40" width="322" height="318" fill="{FLOOR}"/>'
            f'<g clip-path="url(#room)"><circle cx="96" cy="58" r="235" fill="{Y}" fill-opacity="0.18"/></g>')
    bed = (f'<rect x="120" y="46" width="130" height="176" rx="10" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>'
           f'<rect x="132" y="56" width="48" height="30" rx="10" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>'
           f'<rect x="190" y="56" width="48" height="30" rx="10" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>'
           f'<rect x="120" y="98" width="130" height="124" rx="10" fill="{R}" stroke="{INK}" stroke-width="{SW}"/>')
    good = nub(86, 60, 1.0) + badge(86, 108, True, r=17)
    bad = nub(322, 300, 1.0) + badge(322, 258, False, r=17)
    walls = (f'<path d="M244,358 H34 V40 H356 V358 H310" fill="none" stroke="{CREAM}" stroke-width="12" stroke-linejoin="round"/>'
             f'<path d="M244,358 H34 V40 H356 V358 H310" fill="none" stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round"/>'
             f'<path d="M244,358 A66,66 0 0 1 310,292" fill="none" stroke="{CREAM}" stroke-width="2.5" stroke-dasharray="5 5"/>'
             f'<line x1="244" y1="358" x2="310" y2="292" stroke="{CREAM}" stroke-width="5" stroke-linecap="round"/>')
    return frame(room + bed + walls + good + bad, floor=False)


def scene_hub():
    """Onboarding "Mark the bedroom": the phone walks in toward the bedroom hub, an outlet cube low
    on the wall with the XIAO board on its side, and the hub's signal reaches out to it. Kept to
    three things (phone, hub, signal) so it reads at a glance."""
    wall = plate(292, 322, 70, 100) + hub(292, 322, 0.95)
    waves = "".join(
        f'<path d="M{262 - r:.0f},{318 - r*0.1:.0f} a{r},{r} 0 0 1 {r*0.5:.0f},{-r*0.82:.0f}" fill="none" '
        f'stroke="{Y}" stroke-opacity="{op}" stroke-width="8" stroke-linecap="round"/>'
        for r, op in [(34, 1), (68, 0.75), (102, 0.5)])
    speed = "".join(f'<line x1="{x1}" y1="{y}" x2="{x2}" y2="{y}" stroke="{CREAM}" stroke-width="4" stroke-linecap="round"/>'
                    for x1, x2, y in [(4, 30, 256), (0, 28, 280), (6, 30, 304)])
    moon = f'<circle cx="318" cy="86" r="34" fill="{Y}"/><circle cx="334" cy="74" r="30" fill="{G}"/>'
    return frame(moon + wall + waves + speed + phone(44, 196, 1.0, mood="sleep"))

SCENES = {
    "HubScene": scene_hub,
    "GuideHardware": scene_hardware,
    "GuideNightstand": scene_nightstand,
    "GuideUnderBed": scene_under_bed,
    "GuidePuck": scene_puck,
    "GuideFloorPlan": scene_plan,
}

if __name__ == "__main__":
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "guide-scenes")
    out.mkdir(parents=True, exist_ok=True)
    for name, fn in SCENES.items():
        (out / f"{name}.svg").write_text(fn())
    print("\n".join(SCENES))
