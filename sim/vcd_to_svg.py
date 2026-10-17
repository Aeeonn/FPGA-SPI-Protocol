"""Render one SPI transaction from a VCD file as an SVG timing diagram.

Usage: python vcd_to_svg.py tb_spi_master.vcd ../docs/spi_read_waveform.svg

Plots the first chip-select window of tb_spi_master and decodes the bytes
sampled on the SCLK rising edges. Standard library only.
"""
import sys

SCOPE = "tb_spi_master"
SIGNALS = [("cs_n", "CS_N"), ("sclk", "SCLK"), ("mosi", "MOSI"), ("miso", "MISO"), ("done", "done")]


def parse_vcd(path, wanted):
    ids, changes, scope, time, unit_ps = {}, {}, [], 0, 1
    with open(path) as f:
        tokens_mode = None
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if line.startswith("$timescale"):
                tokens_mode = "timescale"
                rest = line[len("$timescale"):].replace("$end", "").strip()
                if rest:
                    unit_ps = _timescale_ps(rest)
                    tokens_mode = None
                continue
            if tokens_mode == "timescale":
                if line != "$end":
                    unit_ps = _timescale_ps(line)
                tokens_mode = None
                continue
            if line.startswith("$scope"):
                scope.append(line.split()[2])
            elif line.startswith("$upscope"):
                scope.pop()
            elif line.startswith("$var"):
                parts = line.split()
                code, name = parts[3], parts[4]
                if scope == [SCOPE] and name in wanted:
                    ids.setdefault(code, []).append(name)
                    changes[name] = []
            elif line.startswith("#"):
                time = int(line[1:]) * unit_ps
            elif line[0] in "01xzXZ" and line[1:] in ids:
                for name in ids[line[1:]]:
                    changes[name].append((time, line[0].lower()))
            elif line[0] in "bB":
                value, code = line[1:].split()
                if code in ids:
                    for name in ids[code]:
                        changes[name].append((time, value[-1].lower()))
    return changes


def _timescale_ps(text):
    text = text.replace(" ", "")
    for suffix, scale in (("ps", 1), ("ns", 1000), ("us", 1_000_000), ("ms", 1_000_000_000)):
        if text.endswith(suffix):
            return int(text[: -len(suffix)]) * scale
    return 1


def value_at(trace, t):
    v = "x"
    for ct, cv in trace:
        if ct > t:
            break
        v = cv
    return v


def main(vcd_path, svg_path):
    tr = parse_vcd(vcd_path, {s for s, _ in SIGNALS})
    cs_fall = next(t for t, v in tr["cs_n"] if v == "0" and t > 0)
    cs_rise = next(t for t, v in tr["cs_n"] if v == "1" and t > cs_fall)
    idle_since = next(t for t, v in tr["cs_n"] if v == "1")
    t0 = max(cs_fall - 2_000_000, idle_since)
    t1 = cs_rise + 2_000_000

    rises = [t for t, v in tr["sclk"] if v == "1" and cs_fall < t < cs_rise]
    mosi_bits = [value_at(tr["mosi"], t) for t in rises]
    miso_bits = [value_at(tr["miso"], t) for t in rises]

    def to_byte(bits):
        return int("".join(b if b in "01" else "0" for b in bits), 2)

    cmd, rx = to_byte(mosi_bits[:8]), to_byte(miso_bits[8:16])

    left, right, row_h, top = 70, 20, 66, 50
    width = 1100
    plot_w = width - left - right
    height = top + row_h * len(SIGNALS) + 10

    def x(t):
        return left + (t - t0) * plot_w / (t1 - t0)

    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" font-family="Consolas, monospace" font-size="13">',
        f'<rect width="{width}" height="{height}" fill="#ffffff"/>',
        f'<text x="{left}" y="22" font-size="15" font-weight="bold" fill="#222">'
        f"SPI mode 3 read of DEVID (simulated): MOSI 0x{cmd:02X} = read reg 0x{cmd & 0x3F:02X}, "
        f"MISO returns 0x{rx:02X}</text>",
    ]
    for t in rises:
        out.append(f'<line x1="{x(t):.1f}" y1="{top - 8}" x2="{x(t):.1f}" '
                   f'y2="{top + row_h * len(SIGNALS) - 12}" stroke="#e3e3e3"/>')

    for row, (sig, label) in enumerate(SIGNALS):
        y_hi = top + row * row_h
        y_lo = y_hi + 30
        y_mid = (y_hi + y_lo) / 2
        out.append(f'<text x="8" y="{y_mid + 4:.1f}" fill="#222" font-weight="bold">{label}</text>')
        trace = [(t0, value_at(tr[sig], t0))] + [(t, v) for t, v in tr[sig] if t0 < t < t1]
        pts = []
        for i, (t, v) in enumerate(trace):
            t_end = trace[i + 1][0] if i + 1 < len(trace) else t1
            if v in "01":
                y = y_hi if v == "1" else y_lo
                x_end = max(x(t_end), x(t) + 3) if v == "1" else x(t_end)
                pts.append(((x(t), y), (x_end, y)))
            else:
                out.append(f'<line x1="{x(t):.1f}" y1="{y_mid:.1f}" x2="{x(t_end):.1f}" y2="{y_mid:.1f}" '
                           f'stroke="#c0392b" stroke-dasharray="4,3"/>')
                pts.append(None)
        path = []
        prev = None
        for seg in pts:
            if seg is None:
                prev = None
                continue
            (xa, ya), (xb, yb) = seg
            path.append(f"{'L' if prev else 'M'}{xa:.1f},{ya:.1f} L{xb:.1f},{yb:.1f}")
            prev = seg
        if path:
            out.append(f'<path d="{" ".join(path)}" fill="none" stroke="#1f5fbf" stroke-width="2"/>')

    def bracket(row, i0, i1, text):
        y = top + row * row_h + 44
        xa, xb = x(rises[i0]) - 10, x(rises[i1]) + 10
        out.append(f'<path d="M{xa:.1f},{y - 4} L{xa:.1f},{y} L{xb:.1f},{y} L{xb:.1f},{y - 4}" '
                   f'fill="none" stroke="#555"/>')
        out.append(f'<text x="{(xa + xb) / 2:.1f}" y="{y + 12}" text-anchor="middle" fill="#555">{text}</text>')

    bracket(2, 0, 7, f"command 0x{cmd:02X}: R/W=1, MB=0, addr 0x{cmd & 0x3F:02X}")
    bracket(3, 8, 15, f"data 0x{rx:02X} (sampled on SCLK rising edges)")
    done_t = next((t for t, v in tr["done"] if v == "1" and t > cs_fall), None)
    if done_t is not None:
        out.append(f'<text x="{x(done_t) - 6:.1f}" y="{top + 4 * row_h + 18}" text-anchor="end" fill="#555">'
                   f"1-cycle done pulse</text>")
    out.append(f'<text x="{left}" y="{height - 8}" fill="#888" font-size="11">'
               f"Icarus Verilog simulation of spi_master.v + ADXL345 model. "
               f"SCLK = {1e9 / (rises[1] - rises[0]):.0f} kHz, gridlines = sample points.</text>")
    out.append("</svg>")

    with open(svg_path, "w", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    print(f"wrote {svg_path}: cmd=0x{cmd:02X} rx=0x{rx:02X}, {len(rises)} SCLK cycles")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
