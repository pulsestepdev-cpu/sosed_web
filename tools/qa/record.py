"""Запись сцены кадрами (Movie Maker Godot) и листы-раскадровки — для проверки анимации (агент anim-review).

  python tools/qa/record.py --preset trap              # готовый сценарий
  python tools/qa/record.py --list                     # список сценариев
  python tools/qa/record.py --args "--start=9.75 --focus --ghost" --seconds 12 --name gaming2

Окно Godot откроется на время записи (Movie Maker рендерит по-настоящему). Время в игре идёт ровно по --fps,
независимо от скорости ПК. Результат: screenshots/qa/record/<время>/frames/*.png и sheet_*.png
(сетка 4×4 кадров с подписью секунд) — их удобно смотреть целиком.
"""
import argparse
import glob
import os
import shlex

from PIL import Image, ImageDraw

from common import godot, out_dir, utf8_stdout

# сценарий: (аргументы игры, секунд записи, что смотреть)
PRESETS = {
    "wake":    ("--day=3 --start=7.9 --ghost --focus", 18, "сосед встаёт с кровати, клятва, идёт в ванную"),
    "trap":    ("--day=3 --start=9.55 --give=banana --use=sel:banana,peeltrap,sofa --ghost --focus", 28,
                "сосед поскальзывается на кожуре: падение, лежит, встаёт, злится"),
    "fridge":  ("--day=3 --start=9.9 --give=vodka --use=sel:vodka,fridge,sofa --ghost --focus", 34,
                "водка вместо минералки: глоток, шок, «ну раз уж открыл», танец"),
    "gaming":  ("--day=3 --start=9.75 --ghost --focus", 12, "сосед играет: геймпад двумя руками, телевизор включён"),
    "bulb":    ("--day=3 --start=10.9 --give=bulb --use=ladder,wardrobe --ghost --focus", 40, "стремянка в прихожей, лампочка"),
    "catch":   ("--day=3 --start=9.3 --catch", 9, "поимка: сосед бежит, удар, герой исчезает"),
    "hide":    ("--day=3 --start=8.6 --hero-at=8.0,1 --use=bed --ghost", 8, "герой ныряет под кровать, глаза из укрытия"),
    "finale":  ("--day=3 --start=10 --salad --finale --ghost --hero-at=12.0,0", 34,
                "финал: сосед идёт к салату, падает лицом, камера на героя, танец, реплики"),
    "overview": ("--day=3 --start=8.0 --ghost", 20, "общий план: мысли соседа, метка цели, точки предметов"),
    "cellar":  ("--day=4 --start=8.2 --ghost --hero-at=5.0,0 --goto=5.0,-1", 16,
                "дверь под лестницей: герой входит, дверь закрывается, выходит из двери в подвале"),
    "attic":   ("--day=6 --start=8.2 --ghost --hero-at=12.6,1 --goto=8.0,2", 16,
                "дверь с площадки правой лестницы: герой поднимается на чердак"),
    "week":    ("--day=7 --start=10 --salad --finale --ghost --hero-at=8.0,0", 46,
                "финал недели: сосед лицом в салат, герой: «опять всю неделю пил не просыхал?», сосед во сне"),
}


def sheets(frames, d, per=16, cols=4, fps=10):
    paths = []
    step = max(1, len(frames) // (per * 3)) if len(frames) > per * 3 else max(1, len(frames) // per)
    picked = frames[::step]
    for si in range(0, len(picked), per):
        chunk = picked[si:si + per]
        first = Image.open(chunk[0])
        w, h = first.size
        tw, th = 480, int(480 * h / w)
        rows = (len(chunk) + cols - 1) // cols
        sheet = Image.new("RGB", (tw * cols, th * rows), (20, 12, 8))
        dr = ImageDraw.Draw(sheet)
        for i, f in enumerate(chunk):
            im = Image.open(f).convert("RGB").resize((tw, th))
            x, y = (i % cols) * tw, (i // cols) * th
            sheet.paste(im, (x, y))
            idx = frames.index(f)
            dr.rectangle([x, y, x + 86, y + 22], fill=(0, 0, 0))
            dr.text((x + 4, y + 4), "%.1f c" % (idx / fps), fill=(255, 230, 160))
        p = os.path.join(d, "sheet_%02d.png" % (si // per + 1))
        sheet.save(p)
        paths.append(p)
    return paths


def main():
    utf8_stdout()
    ap = argparse.ArgumentParser()
    ap.add_argument("--preset", help=", ".join(PRESETS))
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--args", default="", help="свои аргументы игры (вместо --preset)")
    ap.add_argument("--seconds", type=float, default=0, help="длительность записи")
    ap.add_argument("--fps", type=int, default=10)
    ap.add_argument("--size", default="1280x720", help="разрешение окна")
    ap.add_argument("--name", default="")
    a = ap.parse_args()
    if a.list:
        for k, (args, sec, what) in PRESETS.items():
            print("%-9s %3d с  %s\n          %s" % (k, sec, what, args))
        return
    if a.preset:
        args, sec, what = PRESETS[a.preset]
    else:
        args, sec, what = a.args, 10, "свой сценарий"
    if a.seconds:
        sec = a.seconds
    d = out_dir("record")
    if a.name or a.preset:
        nd = d + "_" + (a.name or a.preset)
        os.rename(d, nd)
        d = nd
    fd = os.path.join(d, "frames")
    os.makedirs(fd, exist_ok=True)
    n = int(sec * a.fps)
    game_args = ["--resolution", a.size, "--write-movie", os.path.join(fd, "f.png"), "--fixed-fps", str(a.fps),
                 "--quit-after", str(n), "res://scenes/game.tscn", "--", "--autostart"] + shlex.split(args)
    code, out = godot(game_args, timeout=int(sec * 20) + 120, headless=False)
    open(os.path.join(d, "godot.log"), "w", encoding="utf-8").write(out)
    frames = sorted(glob.glob(os.path.join(fd, "*.png")))
    if not frames:
        print("Кадров нет. Лог:", os.path.join(d, "godot.log"))
        return
    ps = sheets(frames, d, fps=a.fps)
    print("Сценарий:", what)
    print("Кадров:", len(frames), "  папка:", fd)
    print("Листы раскадровки (смотреть их):")
    for p in ps:
        print("  ", p)
    errs = [l for l in out.splitlines() if "SCRIPT ERROR" in l or "ERROR: res://" in l]
    for e in errs[:10]:
        print("ОШИБКА:", e)


if __name__ == "__main__":
    main()
