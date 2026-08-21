#!/usr/bin/env python3
"""
Canton-S provenance diagram: custody, propagation, and public deposition
of Canton-S lineages across stock centers and labs, drawn to a real
calendar-year scale from 2002 onward. The 1987-2002 interval is
compressed (Canton-S's arrival at Bloomington has no precise date) and
marked by a break in the Bloomington line itself, rather than being
drawn at its true 15-year width.

This is a hand-curated illustration, not a pipeline output -- there is
no input data file. Geometry is expressed in terms of calendar years
and named lanes (year_x(), LANE_Y) rather than bare pixel literals, so
adding or moving an event means changing a year/lane, not hunting
coordinates.
"""
import argparse

PALETTE = {
    "ink": "#1E2422",
    "muted": "#6C766F",
    "rule": "#C9D0CB",
    "marker_fill": "#FFFFFF",
    "caltech": "#B9821A",
    "bloomington": "#2C4A88",
    "kyoto": "#9C2438",
    "dspr": "#B85A1E",
    "wierzbicki": "#8C3E82",
    "liu": "#2E7D4F",
    "dlpd": "#1E8286",
}

LANE_Y = {
    "caltech": 490,
    "bloomington": 320,
    "kyoto": 150,
    "dspr": 570,
    "wierzbicki": 230,
    "liu": 410,
    "dlpd": 70,
}

# Real calendar-year scale from 2002 onward; 1987 is pinned near the
# left edge and connected via a compressed/broken interval, not drawn
# at its true position.
PX_PER_YEAR = 34
YEAR_2002_X = 280
YEAR_1987_X = 140


def year_x(year):
    if year == 1987:
        return YEAR_1987_X
    return YEAR_2002_X + PX_PER_YEAR * (year - 2002)


GRID_YEARS = [1987, 2002, 2006, 2016, 2018, 2020, 2023, 2024, 2025]

GRID_Y0, GRID_Y1 = 45, 612

# (x1, y1, x2, y2, color_key, style) -- style in {solid, dashed, fade-in, fade-out}
SEGMENTS = [
    (60, LANE_Y["caltech"], year_x(1987), LANE_Y["caltech"], "caltech", "fade-in"),
    (year_x(2002), LANE_Y["bloomington"], year_x(2006), LANE_Y["bloomington"], "bloomington", "solid"),
    (year_x(2006), LANE_Y["bloomington"], 716, LANE_Y["bloomington"], "bloomington", "solid"),
    (716, LANE_Y["bloomington"], year_x(2016), LANE_Y["bloomington"], "bloomington", "dashed"),
    (year_x(2016), LANE_Y["bloomington"], year_x(2018), LANE_Y["bloomington"], "bloomington", "solid"),
    (year_x(2018), LANE_Y["bloomington"], year_x(2023), LANE_Y["bloomington"], "bloomington", "solid"),
    (year_x(2023), LANE_Y["bloomington"], 1220, LANE_Y["bloomington"], "bloomington", "fade-out"),
    (year_x(2002), LANE_Y["kyoto"], year_x(2016), LANE_Y["kyoto"], "kyoto", "solid"),
    (year_x(2016), LANE_Y["kyoto"], 880, LANE_Y["kyoto"], "kyoto", "fade-out"),
    (year_x(2006), LANE_Y["dspr"], year_x(2018), LANE_Y["dspr"], "dspr", "solid"),
    (year_x(2018), LANE_Y["wierzbicki"], year_x(2020), LANE_Y["wierzbicki"], "wierzbicki", "solid"),
    (year_x(2018), LANE_Y["liu"], year_x(2025), LANE_Y["liu"], "liu", "solid"),
    (year_x(2023), LANE_Y["dlpd"], year_x(2024), LANE_Y["dlpd"], "dlpd", "solid"),
]

# The 1987-2002 break is drawn as a single zigzag jog in the
# Bloomington line itself (a "resistor diagram" squiggle) -- there is
# deliberately no separate double-slash tick mark; the jog alone is
# enough to read as a break.
BLOOMINGTON_JOG = (
    f"M{year_x(1987)},{LANE_Y['bloomington']} "
    f"L185,{LANE_Y['bloomington']} L197,308 L209,332 L221,308 L233,{LANE_Y['bloomington']} "
    f"L{year_x(2002)},{LANE_Y['bloomington']}"
)

# (x, y_from, y_to, color_key) -- always vertical, so a stock transfer
# is never confused with a (horizontal) propagation line.
TRANSFERS = [
    (year_x(1987), 481, LANE_Y["bloomington"] + 9, "caltech"),
    (year_x(2002), LANE_Y["bloomington"] - 9, LANE_Y["kyoto"] + 9, "bloomington"),
    (year_x(2006), LANE_Y["bloomington"] + 9, LANE_Y["dspr"] - 9, "bloomington"),
    (year_x(2016), LANE_Y["kyoto"] + 9, LANE_Y["bloomington"] - 9, "kyoto"),
    (year_x(2018), LANE_Y["bloomington"] - 9, LANE_Y["wierzbicki"] + 9, "bloomington"),
    (year_x(2018), LANE_Y["bloomington"] + 9, LANE_Y["liu"] - 9, "bloomington"),
    (year_x(2023), LANE_Y["bloomington"] - 9, LANE_Y["dlpd"] + 9, "bloomington"),
]

# Institution/lab custody markers (circles).
MARKERS = [
    (year_x(1987), LANE_Y["caltech"], "caltech"),
    (year_x(1987), LANE_Y["bloomington"], "bloomington"),
    (year_x(2002), LANE_Y["bloomington"], "bloomington"),
    (year_x(2006), LANE_Y["bloomington"], "bloomington"),
    (year_x(2016), LANE_Y["bloomington"], "bloomington"),
    (year_x(2018), LANE_Y["bloomington"], "bloomington"),
    (year_x(2023), LANE_Y["bloomington"], "bloomington"),
    (year_x(2002), LANE_Y["kyoto"], "kyoto"),
    (year_x(2016), LANE_Y["kyoto"], "kyoto"),
    (year_x(2006), LANE_Y["dspr"], "dspr"),
    (year_x(2018), LANE_Y["wierzbicki"], "wierzbicki"),
    (year_x(2018), LANE_Y["liu"], "liu"),
    (year_x(2023), LANE_Y["dlpd"], "dlpd"),
]

# Public-deposition markers (squares), one per downstream lab/project.
DEPOSITS = [
    (year_x(2018), LANE_Y["dspr"], "dspr"),
    (year_x(2020), LANE_Y["wierzbicki"], "wierzbicki"),
    (year_x(2025), LANE_Y["liu"], "liu"),
    (year_x(2024), LANE_Y["dlpd"], "dlpd"),
]

# label-inst: bold lane/lab name. label-sub: small italic caption.
INST_LABELS = [
    (128, LANE_Y["kyoto"] + 4, "kyoto", "end", "Kyoto"),
    (128, LANE_Y["bloomington"] + 4, "bloomington", "end", "Bloomington"),
    (128, LANE_Y["caltech"] - 14, "caltech", "end", "Caltech"),
    (year_x(2018) + 25, LANE_Y["dspr"] + 4, "dspr", "start", "DSPR"),
    (year_x(2018) + 68, LANE_Y["wierzbicki"] + 23, "wierzbicki", "middle", "Wierzbicki"),
    (year_x(2025) + 25, LANE_Y["liu"] + 4, "liu", "start", "Liu"),
    (year_x(2024) + 25, LANE_Y["dlpd"] + 4, "dlpd", "start", "DLPD"),
]

# (x, y, anchor, fill_key, text, rotation_degrees) -- rotation is 0 for all
# but "contaminated"; negative = counterclockwise (SVG's y-down convention).
SUB_LABELS = [
    (65, LANE_Y["caltech"] + 17, "start", None, "undated origin", 0),
    # hand-placed next to the Bloomington break jog; doesn't reduce to a lane/year offset
    (260, 356, "middle", None, "1987–2002 compressed", 0),
    (1225, LANE_Y["bloomington"] + 12, "end", None, "present", 0),
    # anchored (text-anchor=end) just left of the 2016 institution marker, below
    # the line, tilted 35 deg ccw so the word reads climbing away from that
    # point rather than sitting directly under it or the transfer arrow above
    (730, LANE_Y["bloomington"] + 16, "end", None, "contaminated", -35),
    (year_x(2006), LANE_Y["dspr"] + 22, "middle", None, "T. D. Long, 2006", 0),
    (year_x(2018), LANE_Y["wierzbicki"] - 16, "middle", None, "R. Kofler, 2018", 0),
    (year_x(2018), LANE_Y["liu"] + 20, "middle", None, "Y. Zhong, 2018", 0),
    (year_x(2023), LANE_Y["dlpd"] - 16, "middle", None, "M. Chakraborty, 2023", 0),
    (year_x(2025) + 25, LANE_Y["liu"] + 18, "start", None, "focal assembly", 0),
    (year_x(2024) + 25, LANE_Y["dlpd"] + 18, "start", None, "unpublished", 0),
]

GRADIENTS = [
    ("fadeInGold", 60, year_x(1987), "caltech", "in"),
    ("fadeOutBlue", year_x(2023), 1220, "bloomington", "out"),
    ("fadeOutRed", year_x(2016), 880, "kyoto", "out"),
]


def render(width=1260, height=700):
    p = PALETTE
    parts = []
    a = parts.append

    a(f'<svg viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg" '
      'role="img" aria-label="Lineage diagram, drawn to a real calendar-year scale '
      'except for the 1987-2002 interval, which is compressed and marked with a break '
      'in the Bloomington line: Caltech transfers Canton-S to Bloomington in 1987; '
      'Bloomington sends it to Kyoto in 2002 and to the DSPR project in 2006; '
      "Bloomington's own stock is contaminated from shortly after 2006 to 2016; "
      'Kyoto sends a clean stock back to Bloomington in 2016; Bloomington supplies '
      'the Wierzbicki and Liu labs in 2018 and the DLPD project in 2023; DSPR, '
      'Wierzbicki, Liu, and DLPD each culminate in a public data deposition.">')

    a('<defs>')
    a(f'<style>'
      f'.label-inst{{font-family:-apple-system,"Helvetica Neue",Arial,sans-serif;'
      f'font-weight:600;font-size:15px;}}'
      f'.label-sub{{font-family:-apple-system,"Helvetica Neue",Arial,sans-serif;'
      f'font-weight:400;font-size:11px;fill:{p["muted"]};font-style:italic;}}'
      f'.label-year{{font-family:"Charter",Georgia,serif;'
      f'font-variant-numeric:tabular-nums;font-size:13px;fill:{p["muted"]};}}'
      f'.legend-text{{font-family:-apple-system,"Helvetica Neue",Arial,sans-serif;'
      f'font-size:13px;fill:{p["ink"]};}}'
      f'</style>')
    for name, color_key in [("gold", "caltech"), ("blue", "bloomington"), ("red", "kyoto"), ("ink", "ink")]:
        a(f'<marker id="arrow-{name}" viewBox="0 0 10 10" refX="9" refY="5" '
          f'markerWidth="6" markerHeight="6" orient="auto">'
          f'<polygon points="0,0 0,10 10,5" fill="{p[color_key]}" /></marker>')
    for grad_id, x1, x2, color_key, direction in GRADIENTS:
        color = p[color_key]
        stops = ('<stop offset="0" stop-color="{c}" stop-opacity="0" />'
                 '<stop offset="1" stop-color="{c}" stop-opacity="1" />').format(c=color) \
            if direction == "in" else \
            ('<stop offset="0" stop-color="{c}" stop-opacity="1" />'
             '<stop offset="0.4" stop-color="{c}" stop-opacity="1" />'
             '<stop offset="1" stop-color="{c}" stop-opacity="0" />').format(c=color)
        a(f'<linearGradient id="{grad_id}" gradientUnits="userSpaceOnUse" '
          f'x1="{x1}" y1="0" x2="{x2}" y2="0">{stops}</linearGradient>')
    a('</defs>')

    # year grid
    a(f'<g stroke="{p["rule"]}" stroke-width="1" stroke-dasharray="2 5">')
    for year in GRID_YEARS:
        x = year_x(year)
        a(f'<line x1="{x}" y1="{GRID_Y0}" x2="{x}" y2="{GRID_Y1}" />')
    a('</g>')
    a('<g class="label-year" text-anchor="middle">')
    for year in GRID_YEARS:
        a(f'<text x="{year_x(year)}" y="30">{year}</text>')
    a('</g>')

    # propagation lines
    fade_map = {"fadeInGold": None}
    for x1, y1, x2, y2, color_key, style in SEGMENTS:
        color = p[color_key]
        if style == "solid":
            a(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="3.5" />')
        elif style == "dashed":
            a(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" '
              f'stroke-width="3.5" stroke-dasharray="2 6" />')
        elif style == "fade-in":
            a(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="url(#fadeInGold)" stroke-width="3.5" />')
        elif style == "fade-out":
            grad = "fadeOutBlue" if color_key == "bloomington" else "fadeOutRed"
            a(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="url(#{grad})" stroke-width="3.5" />')

    # Bloomington's 1987-2002 break jog (drawn on top of/instead of the
    # plain segment for that span)
    a(f'<path d="{BLOOMINGTON_JOG}" stroke="{p["bloomington"]}" stroke-width="3.5" fill="none" />')

    # stock transfers (always vertical)
    arrow_for = {"caltech": "arrow-gold", "bloomington": "arrow-blue", "kyoto": "arrow-red"}
    for x, y1, y2, color_key in TRANSFERS:
        a(f'<line x1="{x}" y1="{y1}" x2="{x}" y2="{y2}" stroke="{p[color_key]}" '
          f'stroke-width="3.5" marker-end="url(#{arrow_for[color_key]})" />')

    # institution markers (circles)
    a(f'<g fill="{p["marker_fill"]}" stroke-width="2">')
    for x, y, color_key in MARKERS:
        a(f'<circle cx="{x}" cy="{y}" r="6.5" stroke="{p[color_key]}" />')
    a('</g>')

    # public deposition markers (squares)
    a(f'<g fill="{p["marker_fill"]}" stroke-width="2">')
    for x, y, color_key in DEPOSITS:
        a(f'<rect x="{x - 6.5}" y="{y - 6.5}" width="13" height="13" stroke="{p[color_key]}" />')
    a('</g>')

    # labels
    for x, y, color_key, anchor, text in INST_LABELS:
        a(f'<text class="label-inst" x="{x}" y="{y}" text-anchor="{anchor}" fill="{p[color_key]}">{text}</text>')
    for x, y, anchor, color_key, text, rotation in SUB_LABELS:
        fill = f' fill="{p[color_key]}"' if color_key else ''
        # rotate(angle, x, y) turns the text about its own anchor point, so the
        # anchored end stays put and the rest of the word swings around it
        transform = f' transform="rotate({rotation} {x} {y})"' if rotation else ''
        a(f'<text class="label-sub" x="{x}" y="{y}" text-anchor="{anchor}"{fill}{transform}>{text}</text>')

    # legend: stock-transfer swatch is vertical, distinct from the
    # horizontal propagation swatch
    a('<g transform="translate(140, 650)">')
    a(f'<line x1="13" y1="14" x2="13" y2="-13" stroke="{p["ink"]}" stroke-width="3" marker-end="url(#arrow-ink)" />')
    a('<text class="legend-text" x="30" y="4">Stock transfer</text>')
    a(f'<line x1="170" y1="0" x2="196" y2="0" stroke="{p["ink"]}" stroke-width="3" />')
    a('<text class="legend-text" x="204" y="4">Propagation</text>')
    a(f'<line x1="340" y1="0" x2="366" y2="0" stroke="{p["ink"]}" stroke-width="3" stroke-dasharray="2 6" />')
    a('<text class="legend-text" x="374" y="4">Contamination</text>')
    a(f'<circle cx="565" cy="0" r="6.5" fill="{p["marker_fill"]}" stroke="{p["ink"]}" stroke-width="2" />')
    a('<text class="legend-text" x="580" y="4">Institution</text>')
    a(f'<rect x="713.5" y="-6.5" width="13" height="13" fill="{p["marker_fill"]}" stroke="{p["ink"]}" stroke-width="2" />')
    a('<text class="legend-text" x="734" y="4">Public deposition</text>')
    a('</g>')

    a('</svg>')
    return "\n".join(parts)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("-o", "--output", default="figures/canton_s_provenance.svg",
                     help="Output SVG path (default: figures/canton_s_provenance.svg)")
    args = ap.parse_args()
    with open(args.output, "w") as f:
        f.write(render())
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
