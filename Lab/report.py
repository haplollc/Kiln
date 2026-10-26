#!/usr/bin/env python3
"""Turn a Kiln Lab test run into an iteration folder.

report.py <run.xcresult> <bench.json> <out_dir> "<label>" ["<what changed>"]

For every example step it pairs the native screenshot (left) with Kiln's (right),
compares the labels on screen, and writes report.md + summary.json. The folder's
parent gets an index (README.md) with one row per iteration.
"""
import json, os, re, subprocess, sys, tempfile, datetime
from PIL import Image, ImageDraw, ImageFont, ImageChops, ImageStat

xcresult, bench_path, out_dir, label = sys.argv[1:5]
changed = sys.argv[5] if len(sys.argv) > 5 else ""
os.makedirs(out_dir, exist_ok=True)

tmp = tempfile.mkdtemp(prefix="kilnlab_")
subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", xcresult, "--output-path", tmp],
               check=True, capture_output=True)
manifest = json.load(open(os.path.join(tmp, "manifest.json")))

shots, texts, notes = {}, {}, {}
for test in manifest:
    for a in test.get("attachments", []):
        name = re.sub(r"_\d+_[0-9A-F-]{36}\.\w+$", "", a["suggestedHumanReadableName"])
        path = os.path.join(tmp, a["exportedFileName"])
        parts = name.split("|")
        if len(parts) == 3 and parts[2] == "notes":
            notes[(parts[0], parts[1])] = open(path).read().strip()
        elif len(parts) == 4 and parts[3] == "texts":
            texts[(parts[0], parts[1], parts[2])] = [l.strip() for l in open(path).read().splitlines() if l.strip()]
        elif len(parts) == 3:
            shots[(parts[0], parts[1], parts[2])] = path

EMOJI = re.compile(r"^[\U0001F300-\U0001FAFF☀-➿️‍]+$")
TIME = re.compile(r"^(\d{2}):(\d{2})$")

def normalize(example, labels):
    out = set()
    for l in labels:
        l = re.sub(r"\s+", " ", l)
        if example == "MemoryMatch" and EMOJI.match(l):
            l = "<face-up card>"
        if example == "MemoryMatch" and re.match(r"^Card \d+$", l):
            l = "<face-down card>"
        out.add(l)
    return out

def times_close(a, b):
    ma, mb = TIME.match(a), TIME.match(b)
    if not (ma and mb): return False
    sa = int(ma[1]) * 60 + int(ma[2]); sb = int(mb[1]) * 60 + int(mb[2])
    return abs(sa - sb) <= 1

def compare(example, native, kiln):
    n, k = normalize(example, native), normalize(example, kiln)
    missing, extra = sorted(n - k), sorted(k - n)
    # A countdown read a second apart is the same screen.
    for m in list(missing):
        twin = next((e for e in extra if times_close(m, e)), None)
        if twin: missing.remove(m); extra.remove(twin)
    union = len(n | k) or 1
    score = 1 - (len(missing) + len(extra)) / union
    return max(score, 0), missing, extra

def block_diff(a, b):
    """Share of 32x32-point blocks (status bar excluded) that look the same, and
    the blocks that differ, so a black icon where native has a white one counts."""
    ia, ib = Image.open(a).convert("L"), Image.open(b).convert("L")
    w, h = ia.size
    ib = ib.resize((w, h))
    top = int(h * 0.06)
    qa = ia.crop((0, top, w, h)).resize((w // 4, (h - top) // 4))
    qb = ib.crop((0, top, w, h)).resize((w // 4, (h - top) // 4))
    diff = ImageChops.difference(qa, qb)
    cols, rows = diff.size[0] // 8, diff.size[1] // 8
    means = diff.resize((cols, rows), Image.BOX).load()
    boxes = []
    for y in range(rows):
        for x in range(cols):
            if means[x, y] > 10:
                boxes.append((x * 32, top + y * 32, (x + 1) * 32, top + (y + 1) * 32))
    return 1 - len(boxes) / (cols * rows), boxes

def font(size):
    for f in ["/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/HelveticaNeue.ttc"]:
        try: return ImageFont.truetype(f, size)
        except Exception: pass
    return ImageFont.load_default()

def side_by_side(left, right, title, path, boxes=None):
    """Native, Kiln, and Kiln with the blocks that differ from native in red."""
    imgs = [Image.open(p).convert("RGB") if p else None for p in (left, right)]
    w, h = next(i.size for i in imgs if i)
    scale = 0.5
    W, H = int(w * scale), int(h * scale)
    panels = [(imgs[0], "Native SwiftUI"), (imgs[1], "Kiln")]
    if boxes is not None and imgs[1] is not None:
        marked = imgs[1].resize((w, h)).copy()
        overlay = Image.new("RGBA", marked.size, (0, 0, 0, 0))
        od = ImageDraw.Draw(overlay)
        for bx in boxes:
            od.rectangle(bx, fill=(255, 40, 40, 90))
        marked = Image.alpha_composite(Image.blend(marked, Image.new("RGB", marked.size, "white"), 0.45).convert("RGBA"), overlay).convert("RGB")
        panels.append((marked, "Differs from native" if boxes else "Same as native"))
    canvas = Image.new("RGB", (W * len(panels) + 20 * (len(panels) + 1), H + 110), "white")
    d = ImageDraw.Draw(canvas)
    d.text((20, 18), title, fill=(20, 20, 24), font=font(30))
    for i, (img, cap) in enumerate(panels):
        x = 20 + i * (W + 20)
        d.text((x, 62), cap, fill=(90, 90, 96), font=font(24))
        if img:
            canvas.paste(img.resize((W, H)), (x, 96))
        else:
            d.rectangle([x, 96, x + W, 96 + H], outline=(200, 200, 200), width=2)
            d.text((x + 20, 120), "no screen", fill=(150, 150, 150), font=font(24))
    canvas.save(path)

examples = sorted({k[0] for k in shots if not k[0].endswith(".md")})
replies = sorted({k[0] for k in shots if k[0].endswith(".md")})
bench = {r["file"]: r for r in json.load(open(bench_path))} if os.path.exists(bench_path) else {}

summary = {"label": label, "date": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"), "examples": {}, "replies": {}}
md = [f"# {label}", "", f"_{summary['date']}_", ""]
if changed: md += ["## What changed", "", changed, ""]
md += ["## Example apps: native SwiftUI vs Kiln", "", "| App | Steps matching | Label match | Look alike | Engine check |", "|---|---|---|---|---|"]
details = []
for ex in examples:
    steps = sorted({k[2] for k in shots if k[0] == ex})
    scores, looks, matched = [], [], 0
    det = [f"### {ex}", ""]
    for st in steps:
        n_img, k_img = shots.get((ex, "native", st)), shots.get((ex, "kiln", st))
        score, missing, extra = compare(ex, texts.get((ex, "native", st), []), texts.get((ex, "kiln", st), []))
        look, boxes = block_diff(n_img, k_img) if n_img and k_img else (0, None)
        scores.append(score); looks.append(look)
        if score >= 0.999: matched += 1
        fname = f"{ex} - {st}.png"
        side_by_side(n_img, k_img, f"{ex} · {st}", os.path.join(out_dir, fname), boxes)
        det.append(f"**{st}**: labels {score:.0%}, look {look:.0%}  ")
        if missing: det.append(f"only in native: {', '.join(missing[:12])}  ")
        if extra: det.append(f"only in Kiln: {', '.join(extra[:12])}  ")
        det.append(f"![{st}]({fname.replace(' ', '%20')})")
        det.append("")
    nb = notes.get((ex, "kiln"))
    if nb: det += ["Kiln run notes: " + nb.replace("\n", "; "), ""]
    b = bench.get(ex + ".swift", {})
    check = "pass" if b.get("valid") else ("hang" if b.get("hung") else ("fail" if b else "n/a"))
    avg = sum(scores) / len(scores) if scores else 0
    look = sum(looks) / len(looks) if looks else 0
    summary["examples"][ex] = {"steps": len(steps), "matched": matched, "labels": round(avg, 3), "look": round(look, 3), "engine": check,
                               "errors": b.get("errors", [])[:3]}
    md.append(f"| {ex} | {matched}/{len(steps)} | {avg:.0%} | {look:.0%} | {check} |")
    if b.get("errors"): det += ["Engine errors: " + " / ".join(e.splitlines()[0] for e in b["errors"][:3]), ""]
    details += det
md += ["", "## Apple Intelligence replies in Kiln", "", "| Reply | Engine check | First error |", "|---|---|---|"]
for rp in replies:
    img = shots.get((rp, "kiln", "1 start"))
    fname = f"reply - {rp.replace('.md', '')}.png"
    if img: Image.open(img).convert("RGB").resize((660, 1434)).save(os.path.join(out_dir, fname))
    b = bench.get(rp, {})
    check = "pass" if b.get("valid") else ("hang" if b.get("hung") else ("fail" if b else "n/a"))
    err = (b.get("errors") or [""])[0].splitlines()[0][:120] if b.get("errors") else ""
    summary["replies"][rp] = {"engine": check, "error": err}
    md.append(f"| {rp} | {check} | {err} |")
    details += [f"### {rp}", "", f"![{rp}]({fname.replace(' ', '%20')})", ""]
md += ["", "## Details", ""] + details
open(os.path.join(out_dir, "report.md"), "w").write("\n".join(md) + "\n")
json.dump(summary, open(os.path.join(out_dir, "summary.json"), "w"), indent=1)

# Index of all iterations.
root = os.path.dirname(out_dir.rstrip("/"))
rows = []
for d in sorted(os.listdir(root)):
    p = os.path.join(root, d, "summary.json")
    if not os.path.exists(p): continue
    s = json.load(open(p))
    ex = s["examples"]
    apps = sum(1 for v in ex.values() if v["steps"] and v["matched"] == v["steps"])
    lab = sum(v["labels"] for v in ex.values()) / (len(ex) or 1)
    rep = sum(1 for v in s["replies"].values() if v["engine"] == "pass")
    rows.append(f"| [{d}]({d.replace(' ', '%20')}/report.md) | {s['date']} | {apps}/{len(ex)} | {lab:.0%} | {rep}/{len(s['replies'])} |")
index = ["# Kiln iterations", "", "Each folder is one pass of the loop: the five example apps run natively and in Kiln,",
         "side by side, plus Apple Intelligence's own replies run in Kiln.", "",
         "| Iteration | When | Apps fully matching | Label match | AI replies passing |", "|---|---|---|---|---|"] + rows
open(os.path.join(root, "README.md"), "w").write("\n".join(index) + "\n")
print(open(os.path.join(out_dir, "report.md")).read()[:3000])
