"""Placement-guide scenes in the 1.1 picture-book style (390x470 viewBox, rendered at 3x)."""
import pathlib

G, DOT, FLOOR, Y, R, NIGHT, CREAM, INK, BLUSH, MOTION = (
    "#2F6B45", "#265939", "#8E2A20", "#F2C849", "#C23B2E", "#1D2B45", "#F7EFDD", "#23302A", "#DF9E8E", "#CFD4BE")
SW = 3  # outline width at 1x

def frame(body, floor=True, rug=True):
    dots = "".join(f'<circle cx="{x}" cy="{y}" r="4.5" fill="{DOT}"/>' for x, y in
                   [(30, 90), (300, 70), (365, 40), (30, 220), (350, 150), (280, 180), (20, 340), (330, 250)])
    fl = (f'<rect x="0" y="392" width="390" height="78" fill="{FLOOR}"/>'
          f'<line x1="0" y1="392" x2="390" y2="392" stroke="{INK}" stroke-width="{SW}"/>') if floor else ""
    rg = (f'<ellipse cx="120" cy="432" rx="96" ry="20" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
          f'<ellipse cx="120" cy="432" rx="70" ry="12" fill="none" stroke="{R}" stroke-width="2.5"/>'
          f'<ellipse cx="120" cy="432" rx="40" ry="6" fill="none" stroke="{G}" stroke-width="2.5"/>') if rug else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 390 470" width="1170" height="1410">'
            f'<rect width="390" height="470" fill="{G}"/>{dots}{fl}{rg}{body}</svg>')

def arcs(cx, cy, radii, start=200, end=340, width=3.5):
    """Yellow signal arcs that fade as they widen, like BeaconScene."""
    import math
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
        "awake": f'<circle cx="30" cy="64" r="4" fill="{INK}"/><circle cx="56" cy="64" r="4" fill="{INK}"/>'
                 f'<path d="M31,90 q12,8 24,0" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>',
    }[mood]
    lg = (f'<path d="M30,150 l-5,40 h-12 M58,150 l6,40 h12" fill="none" stroke="{INK}" stroke-width="5" '
          f'stroke-linecap="round" stroke-linejoin="round"/>') if legs else ""
    return (f'<g transform="translate({x},{y}) scale({s})">{lg}'
            f'<rect x="1.5" y="1.5" width="83" height="149" rx="22" fill="{NIGHT}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<rect x="10" y="14" width="66" height="120" rx="10" fill="{CREAM}"/>'
            f'<circle cx="25" cy="76" r="4.5" fill="{BLUSH}"/><circle cx="61" cy="76" r="4.5" fill="{BLUSH}"/>{face}</g>')

def beacon(x, y, s=1.0):
    """The BC-U1 as drawn in BeaconScene: a cream square with a red dot; (x, y) is its center."""
    return (f'<g transform="translate({x},{y}) scale({s})"><rect x="-19" y="-15" width="38" height="30" rx="7" '
            f'fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/><circle r="5" fill="{R}"/></g>')

def puck(x, y, s=1.0):
    return (f'<g transform="translate({x},{y}) scale({s})"><circle r="17" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>'
            f'<circle r="5" fill="{R}"/></g>')

def outlet(x, y, w=26, h=34):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="4" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>'
            f'<rect x="{x + w/2 - 5}" y="{y + 9}" width="2.5" height="7" fill="{INK}"/>'
            f'<rect x="{x + w/2 + 2.5}" y="{y + 9}" width="2.5" height="7" fill="{INK}"/>'
            f'<circle cx="{x + w/2}" cy="{y + 24}" r="2.2" fill="{INK}"/>')

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
        f'<text x="230" y="232" font-family="Avenir Next, Helvetica" font-weight="700" font-size="17" fill="{CREAM}">z</text>'
        f'<text x="242" y="218" font-family="Avenir Next, Helvetica" font-weight="700" font-size="12" fill="{CREAM}">z</text>'
    )

def scene_under_bed():
    """USB beacon on a charger low on the wall, in the dark gap under the bed."""
    under = f'<rect x="69" y="337" width="252" height="55" fill="{INK}" opacity="0.35"/>'
    gear = (outlet(236, 350) +
            f'<rect x="232" y="356" width="34" height="26" rx="5" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>'
            + beacon(208, 369, 0.8) +
            f'<rect x="223" y="365" width="10" height="8" fill="{INK}"/>')
    glow = arcs(208, 369, [26, 38], start=210, end=330, width=3)
    rug = (f'<ellipse cx="96" cy="436" rx="80" ry="17" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
           f'<ellipse cx="96" cy="436" rx="56" ry="10" fill="none" stroke="{R}" stroke-width="2.5"/>')
    return frame(under + gear + glow + bed_front(), rug=False) .replace("</svg>", rug + "</svg>")

def scene_cover():
    """Close-up: charger and beacon shut inside a childproof outlet box, behind a dresser's edge."""
    plate = (f'<rect x="138" y="128" width="124" height="200" rx="14" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>'
             + outlet(176, 270, 48, 44))
    charger = (f'<rect x="170" y="150" width="60" height="62" rx="9" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>'
               f'<rect x="192" y="212" width="16" height="10" fill="{INK}"/>'
               + beacon(200, 238, 0.95))
    box = (f'<rect x="150" y="138" width="100" height="126" rx="16" fill="{CREAM}" fill-opacity="0.38" '
           f'stroke="{INK}" stroke-width="{SW}"/>'
           f'<rect x="190" y="130" width="20" height="14" rx="4" fill="{Y}" stroke="{INK}" stroke-width="2.5"/>'
           f'<path d="M196,130 v-6 a4,4 0 0 1 8,0 v6" fill="none" stroke="{INK}" stroke-width="2.5"/>')
    signal = arcs(200, 238, [70, 98, 126], start=-50, end=50, width=3.5) + arcs(200, 238, [70, 98, 126], start=130, end=230, width=3.5)
    dresser = (f'<rect x="-20" y="150" width="120" height="242" rx="8" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
               f'<line x1="-20" y1="270" x2="88" y2="270" stroke="{INK}" stroke-width="2.5"/>'
               f'<circle cx="50" cy="210" r="6" fill="{INK}"/><circle cx="50" cy="330" r="6" fill="{INK}"/>')
    return frame(signal + plate + charger + box + dresser, rug=False)

def scene_puck():
    """The battery puck taped under the bed frame, seen from the side."""
    bed = (f'<rect x="300" y="170" width="22" height="222" rx="5" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
           f'<rect x="40" y="290" width="282" height="26" rx="5" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
           f'<rect x="48" y="316" width="14" height="76" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
           f'<rect x="40" y="246" width="262" height="44" rx="10" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>'
           f'<ellipse cx="258" cy="236" rx="36" ry="14" fill="{CREAM}" stroke="{INK}" stroke-width="{SW}"/>'
           + phone(228, 200, 0.36, legs=False) +
           f'<path d="M34,240 h220 q8,0 8,10 v44 h-228 z" fill="{R}" stroke="{INK}" stroke-width="{SW}"/>'
           f'<path d="M44,262 q100,6 210,0 M44,276 q100,6 210,0" fill="none" stroke="{Y}" stroke-width="3" stroke-linecap="round"/>')
    shade = f'<rect x="62" y="316" width="238" height="76" fill="{INK}" opacity="0.3"/>'
    p = (puck(170, 336) +
         f'<rect x="146" y="314" width="48" height="10" rx="2" fill="{Y}" fill-opacity="0.9" stroke="{INK}" stroke-width="2" '
         f'transform="rotate(-6 170 319)"/>')
    rings = arcs(170, 336, [28, 42, 56], start=20, end=160, width=3)
    zz = (f'<text x="276" y="196" font-family="Avenir Next, Helvetica" font-weight="700" font-size="17" fill="{CREAM}">z</text>'
          f'<text x="290" y="180" font-family="Avenir Next, Helvetica" font-weight="700" font-size="12" fill="{CREAM}">z</text>')
    return frame(shade + bed + rings + p + zz, rug=False)

def scene_plan():
    """Top-down plan: beacon at the far wall, signal fading before the door, phone awake in the hall."""
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
           f'<rect x="64" y="46" width="48" height="44" rx="6" fill="{Y}" stroke="{INK}" stroke-width="{SW}"/>'
           f'<circle cx="88" cy="68" r="5" fill="{INK}"/>' + beacon(96, 58, 0.5))
    walls = (f'<path d="M244,358 H34 V40 H356 V358 H310" fill="none" stroke="{CREAM}" stroke-width="12" stroke-linejoin="round"/>'
             f'<path d="M244,358 H34 V40 H356 V358 H310" fill="none" stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round"/>'
             f'<path d="M244,358 A66,66 0 0 1 310,292" fill="none" stroke="{CREAM}" stroke-width="2.5" stroke-dasharray="5 5"/>'
             f'<line x1="244" y1="358" x2="310" y2="292" stroke="{CREAM}" stroke-width="5" stroke-linecap="round"/>')
    hall = (phone(262, 380, 0.42, mood="awake") +
            "".join(f'<line x1="{x}" y1="{y}" x2="{x + 26}" y2="{y}" stroke="{MOTION}" stroke-width="4" stroke-linecap="round"/>'
                    for x, y in [(214, 398), (206, 412), (216, 426)]))
    return frame(room + bed + walls + hall, floor=False, rug=False)

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
            + outlet(178, 330) + f'<rect x="196" y="338" width="16" height="16" rx="3" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>')
    signal = arcs(286, 226, [70, 100, 130], start=200, end=340)
    return frame(signal + dresser + ipad + phone(62, 196, 0.95, mood="sleep"))

out = pathlib.Path(__file__).parent / "guide"
out.mkdir(exist_ok=True)
for name, fn in {"GuideUnderBed": scene_under_bed, "GuideOutletCover": scene_cover, "GuidePuck": scene_puck,
                 "GuideFloorPlan": scene_plan, "GuideHub": scene_hub}.items():
    (out / f"{name}.svg").write_text(fn())
print("ok")
