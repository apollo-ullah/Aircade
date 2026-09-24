#!/usr/bin/env python3
"""Assemble the 14.8s AIRCADE teaser with ffmpeg.

Each shot is rendered to an intermediate clip (scaled, cropped, captioned), the
clips are concatenated, a light grain + vignette is laid over the whole cut, and
the Wii Sports music bed is muxed in. Missing generated assets fall back to a
labelled slate so the timeline can be checked before generating.
"""
from __future__ import annotations
import os, subprocess, sys, json
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC, GEN, BUILD, OUT = ROOT / "source", ROOT / "generated", ROOT / "build", ROOT / "out"
for d in (BUILD / "seg", OUT):
    d.mkdir(parents=True, exist_ok=True)

W, H, FPS = 1920, 1080, 24
FONT = "Avenir Next"
MUSIC = BUILD / "music-bed.wav"

@dataclass
class Shot:
    name: str
    src: Path
    dur: float
    start: float = 0.0
    caption: str | None = None
    crop: str | None = None          # ffmpeg crop=w:h:x:y applied before scaling
    still: bool = False              # src is an image
    extra_vf: list[str] = field(default_factory=list)
    label: str = ""                  # slate text if src missing

SHOTS = [
    Shot("01-intro", GEN / "intro.mp4", 2.0, start=0.4, caption="Remember this?", label="GEN intro"),
    Shot("02-remote-to-earbuds", GEN / "remote-to-earbuds.mp4", 1.4, start=1.0, label="GEN remote to earbuds"),
    Shot("03-swing", SRC / "swing.mp4", 1.8, start=0.6, caption="Your earbuds are the controller."),
    Shot("04-tennis", SRC / "tennis.mp4", 0.8, start=0.0, caption="Swing."),
    Shot("05-slice", SRC / "slice.mp4", 0.8, start=0.3, caption="Slice."),
    Shot("06-ai", SRC / "ai.mp4", 2.6, start=1.5, caption="Meet your AI opponent.", crop="1230:692:130:90"),
    Shot("07-channel-wipe", GEN / "channel-wipe.mp4", 0.6, start=2.4, label="GEN channel wipe"),
    Shot("08-play", SRC / "play.mp4", 2.0, start=1.0, caption="Pick up. Play."),
    Shot("09-reaction", SRC / "reaction.mp4", 1.4, start=0.5),
    Shot("10-endcard", GEN / "endcard.png", 1.4, still=True, label="GEN end card"),
]

FONT_FILE = "/System/Library/Fonts/Avenir Next.ttc"
FONT_DEMI, FONT_MED = 2, 5   # face indexes inside the .ttc

def text_png(name: str, text: str, *, size=62, color=(255, 255, 255, 255), pos="lower-left", face=FONT_DEMI) -> Path:
    """Render a transparent 1920x1080 PNG with the text and a soft drop shadow."""
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
    out = BUILD / "text" / f"{name}.png"
    out.parent.mkdir(exist_ok=True)
    font = ImageFont.truetype(FONT_FILE, size, index=face)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = d.textbbox((0, 0), text, font=font)
    tw, th = x1 - x0, y1 - y0
    if pos == "lower-left":
        x, y = 96 - x0, H - 96 - th - y0
    else:
        x, y = (W - tw) // 2 - x0, (H - th) // 2 - y0
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((x + 2, y + 4), text, font=font, fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(4))
    img = Image.alpha_composite(shadow, img)
    ImageDraw.Draw(img).text((x, y), text, font=font, fill=color)
    img.save(out)
    return out

def render_endcard_frames(shot: Shot) -> Path:
    from PIL import Image, ImageDraw, ImageFont, ImageEnhance
    frames = BUILD / "frames" / shot.name
    frames.mkdir(parents=True, exist_ok=True)
    for f in frames.glob("*.png"):
        f.unlink()
    if shot.src.exists():
        card = Image.open(shot.src).convert("RGB")
        # cover-fit to 16:9
        r = max(W / card.width, H / card.height)
        card = card.resize((round(card.width * r), round(card.height * r)), Image.LANCZOS)
        cx, cy = (card.width - W) // 2, (card.height - H) // 2
        card = card.crop((cx, cy, cx + W, cy + H))
    else:
        card = Image.new("RGB", (W, H), (28, 28, 30))
        d = ImageDraw.Draw(card)
        font = ImageFont.truetype(FONT_FILE, 72, index=FONT_MED)
        x0, y0, x1, y1 = d.textbbox((0, 0), shot.label, font=font)
        d.text(((W - (x1 - x0)) // 2 - x0, (H - (y1 - y0)) // 2 - y0), shot.label, font=font, fill=(154, 154, 158))
    n = round(shot.dur * FPS)
    collapse_at = shot.dur - 0.40          # start of the CRT power-off
    for i in range(n):
        t = i / FPS
        zoom = 1.06 - 0.05 * min(1.0, t / max(collapse_at, 0.01))
        zw, zh = round(W / zoom), round(H / zoom)
        frame = card.crop(((W - zw) // 2, (H - zh) // 2, (W - zw) // 2 + zw, (H - zh) // 2 + zh)).resize((W, H), Image.LANCZOS)
        if t >= collapse_at:
            u = (t - collapse_at) / 0.40      # 0..1 over the collapse
            hf = max(0.004, 1 - u / 0.45)     # height squashes fast to a line
            wf = max(0.01, 1 - max(0.0, u - 0.45) / 0.45)  # then the line shrinks to a dot
            w2, h2 = max(2, round(W * wf)), max(2, round(H * hf))
            small = ImageEnhance.Brightness(frame.resize((w2, h2), Image.LANCZOS)).enhance(1 + 1.5 * u)
            frame = Image.new("RGB", (W, H), (0, 0, 0))
            frame.paste(small, ((W - w2) // 2, (H - h2) // 2))
            if u > 0.92:
                frame = Image.new("RGB", (W, H), (0, 0, 0))
                ImageDraw.Draw(frame).ellipse((W // 2 - 4, H // 2 - 4, W // 2 + 4, H // 2 + 4), fill=(255, 255, 255))
        frame.save(frames / f"{i:04d}.png")
    return frames

def render_shot(shot: Shot) -> Path:
    out = BUILD / "seg" / f"{shot.name}.mp4"
    vf: list[str] = []
    overlays: list[tuple[Path, float]] = []   # (png, fade-in seconds)
    if not shot.src.exists() and not shot.still:
        print(f"   {shot.name}: MISSING {shot.src.relative_to(ROOT)} -> slate")
        cmd = ["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"color=c=0x1c1c1e:s={W}x{H}:r={FPS}:d={shot.dur}"]
        overlays.append((text_png(f"slate-{shot.name}", shot.label or shot.name, size=72,
                                  color=(154, 154, 158, 255), pos="center", face=FONT_MED), 0.0))
    elif shot.still:
        if not shot.src.exists():
            print(f"   {shot.name}: MISSING {shot.src.relative_to(ROOT)} -> slate")
        frames = render_endcard_frames(shot)
        cmd = ["ffmpeg", "-v", "error", "-y", "-framerate", str(FPS), "-i", str(frames / "%04d.png")]
    else:
        cmd = ["ffmpeg", "-v", "error", "-y", "-ss", f"{shot.start}", "-t", f"{shot.dur}", "-i", str(shot.src)]
        if shot.crop:
            vf.append(f"crop={shot.crop}")
        vf.append(f"scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H}")
    vf += shot.extra_vf
    vf.append(f"fps={FPS},setsar=1,format=yuv420p")
    if shot.caption:
        overlays.append((text_png(shot.name, shot.caption), 0.22))
    graph = f"[0:v]{','.join(vf)}[v0]"
    last = "v0"
    for i, (png, fade) in enumerate(overlays, start=1):
        cmd += ["-loop", "1", "-framerate", str(FPS), "-t", f"{shot.dur}", "-i", str(png)]
        fade_f = f",fade=t=in:st=0:d={fade}:alpha=1" if fade else ""
        graph += f";[{i}:v]format=rgba{fade_f}[t{i}];[{last}][t{i}]overlay=0:0:format=auto[v{i}]"
        last = f"v{i}"
    cmd += ["-filter_complex", graph, "-map", f"[{last}]", "-t", f"{shot.dur}", "-an",
            "-c:v", "libx264", "-preset", "fast", "-crf", "16", "-pix_fmt", "yuv420p", str(out)]
    subprocess.run(cmd, check=True)
    return out

def main() -> None:
    print("Rendering shots")
    segs = [render_shot(s) for s in SHOTS]
    total = sum(s.dur for s in SHOTS)
    lst = BUILD / "concat.txt"
    lst.write_text("".join(f"file '{p}'\n" for p in segs))

    final = OUT / "aircade-teaser-15s.mp4"
    grade = (
        "vignette=angle=PI/5:mode=forward,"
        "noise=alls=6:allf=t+u,"
        "eq=saturation=1.06:contrast=1.02"
    )
    cmd = [
        "ffmpeg", "-v", "error", "-y",
        "-f", "concat", "-safe", "0", "-i", str(lst),
        "-i", str(MUSIC),
        "-filter_complex", f"[0:v]{grade},format=yuv420p[v];[1:a]atrim=0:{total},afade=t=out:st={total-0.3}:d=0.3[a]",
        "-map", "[v]", "-map", "[a]",
        "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-profile:v", "high", "-level", "4.1",
        "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-t", f"{total}",
        str(final),
    ]
    subprocess.run(cmd, check=True)
    print(f"Wrote {final.relative_to(ROOT)}  ({total:.2f}s)")

    # contact sheet for review
    sheet = BUILD / "final-contact.jpg"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(final),
                    "-vf", f"fps=2,scale=384:-1,tile=6x5", "-frames:v", "1", str(sheet)], check=True)
    print(f"Contact sheet {sheet.relative_to(ROOT)}")

if __name__ == "__main__":
    main()
