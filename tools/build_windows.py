"""Версия для Windows: полная сборка (zip для друзей) и маленькие патчи к ней.

  python tools/build_windows.py --full           # новая полная версия: releases/vN/sosed_vN.zip (N = прошлая + 1)
  python tools/build_windows.py --patch          # патч к последней версии: releases/vN/patch_K.pck
  python tools/build_windows.py --list           # что уже собрано

Как это устроено:
  * полная версия = sosed.exe (движок Godot, меняется только с версией Godot) + sosed.pck (вся игра);
    sosed.pck копируется в releases/vN/ — от него считаются патчи. Папку releases/ НЕ удалять (в git её нет).
  * патч = только файлы, изменённые с полной версии vN (Godot --export-patch). Каждый патч содержит ВСЕ изменения
    с vN, поэтому другу достаточно последнего: положить patch_K.pck рядом с sosed.exe (старый можно удалить).
    Игра при запуске берёт патч с самым большим K (scripts/autoload/patches.gd), номер виден в углу меню.
  * патчем НЕ обновляются project.godot (автозагрузки, настройки окна и т.п.) и scripts/autoload/patches.gd —
    после их изменения нужна новая полная версия (--full). Скрипт предупреждает об этом сам.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "qa"))
from common import ROOT, godot, utf8_stdout  # noqa: E402

PRESET = "Windows"
OUT = os.path.join(ROOT, "build", "windows")
REL = os.path.join(ROOT, "releases")
VERSION_CFG = os.path.join(ROOT, "version.cfg")
# файлы, изменения которых патч не донесёт
NOT_PATCHABLE = ["project.godot", "scripts/autoload/patches.gd", "export_presets.cfg"]

README = """Сосед на бутылке — версия для Windows

Запуск: распакуйте архив в любую папку и откройте sosed.exe.
Интернет не нужен. Сохранения хранятся отдельно и не пропадают при обновлениях.

Если Windows пишет «Система Windows защитила ваш компьютер» — нажмите «Подробнее» → «Выполнить в любом случае»
(игра не подписана платным сертификатом, это нормально для самодельных игр).

Обновления: вам пришлют небольшой файл patch_N.pck — положите его в эту же папку рядом с sosed.exe
(старые patch_*.pck можно удалить). Номер версии и патча видно в правом нижнем углу главного меню.
"""


def versions():
    if not os.path.isdir(REL):
        return []
    return sorted(int(m.group(1)) for d in os.listdir(REL) if (m := re.fullmatch(r"v(\d+)", d)))


def patches(v):
    d = os.path.join(REL, "v%d" % v)
    return sorted(int(m.group(1)) for f in os.listdir(d) if (m := re.fullmatch(r"patch_(\d+)\.pck", f)))


def file_hash(path):
    return hashlib.md5(open(path, "rb").read()).hexdigest()


def write_version(v):
    with open(VERSION_CFG, "w", encoding="utf-8") as f:
        f.write('[build]\n\nversion="%d"\n' % v)


def prepare():
    for d in (OUT, REL):
        os.makedirs(d, exist_ok=True)
    for d in (os.path.join(ROOT, "build"), REL):             # Godot не импортирует содержимое этих папок
        open(os.path.join(d, ".gdignore"), "w").close()


def full():
    prepare()
    v = (versions() or [0])[-1] + 1
    write_version(v)
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT)
    code, out = godot(["--export-release", PRESET, "build/windows/sosed.exe"], timeout=1200)
    exe, pck = os.path.join(OUT, "sosed.exe"), os.path.join(OUT, "sosed.pck")
    if not (os.path.exists(exe) and os.path.exists(pck)):
        print(out[-3000:])
        sys.exit("Сборка не удалась (код %s)" % code)
    d = os.path.join(REL, "v%d" % v)
    os.makedirs(d)
    shutil.copy2(pck, os.path.join(d, "sosed.pck"))
    # отпечатки «непатчируемых» файлов — чтобы --patch предупредил, если они изменились
    json.dump({p: file_hash(os.path.join(ROOT, p)) for p in NOT_PATCHABLE},
              open(os.path.join(d, "base.json"), "w", encoding="utf-8"), indent=1)
    z = os.path.join(d, "sosed_v%d.zip" % v)
    folder = "Sosed na butilke"
    with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for f in sorted(os.listdir(OUT)):
            zf.write(os.path.join(OUT, f), folder + "/" + f)
        zf.writestr(folder + "/README.txt", "﻿" + README.replace("\n", "\r\n"))
    print("Полная версия v%d:" % v)
    for f in sorted(os.listdir(OUT)):
        print("  %-28s %6.1f МБ" % (f, os.path.getsize(os.path.join(OUT, f)) / 1e6))
    print("  архив для друзей: %s (%.1f МБ)" % (z, os.path.getsize(z) / 1e6))


def patch():
    vs = versions()
    if not vs:
        sys.exit("Нет полной версии — сначала: python tools/build_windows.py --full")
    v = vs[-1]
    d = os.path.join(REL, "v%d" % v)
    base = os.path.join(d, "sosed.pck")
    try:
        old = json.load(open(os.path.join(d, "base.json"), encoding="utf-8"))
    except OSError:
        old = {}
    changed = [p for p in NOT_PATCHABLE if p in old and old[p] != file_hash(os.path.join(ROOT, p))]
    if changed:
        print("ВНИМАНИЕ: изменены %s — патч их не донесёт. Нужна новая полная версия (--full)." % ", ".join(changed))
        if "--force" not in sys.argv:
            sys.exit("Остановлено. Чтобы всё равно собрать патч: --patch --force")
    prepare()
    write_version(v)                                           # версия та же — номер патча берётся из имени файла
    k = (patches(v) or [0])[-1] + 1
    rel = "releases/v%d/patch_%d.pck" % (v, k)
    code, out = godot(["--export-patch", PRESET, rel, "--patches", "releases/v%d/sosed.pck" % v], timeout=1200)
    p = os.path.join(ROOT, rel)
    if not os.path.exists(p):
        print(out[-3000:])
        sys.exit("Патч не собрался (код %s)" % code)
    print("Патч %d к версии v%d: %s (%.2f МБ)" % (k, v, p, os.path.getsize(p) / 1e6))
    print("Друзьям: положить patch_%d.pck в папку с sosed.exe (старые patch_*.pck можно удалить)." % k)


def show():
    for v in versions():
        d = os.path.join(REL, "v%d" % v)
        print("v%d:" % v, ", ".join("%s %.2f МБ" % (f, os.path.getsize(os.path.join(d, f)) / 1e6)
                                   for f in sorted(os.listdir(d)) if f.endswith((".zip", ".pck"))))


if __name__ == "__main__":
    utf8_stdout()
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--full", action="store_true")
    g.add_argument("--patch", action="store_true")
    g.add_argument("--list", action="store_true")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    full() if a.full else patch() if a.patch else show()
