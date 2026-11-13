"""Общее для инструментов автотестов: пути, запуск Godot, папка отчётов."""
import datetime
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GODOT = os.environ.get("GODOT_EXE", r"C:\Users\belya\Desktop\projects\Godot\Godot.exe")
QA_DIR = os.path.join(ROOT, "screenshots", "qa")      # screenshots/ не попадает в git


def out_dir(kind: str) -> str:
    """Новая папка для результатов: screenshots/qa/<kind>/<дата-время>."""
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    d = os.path.join(QA_DIR, kind, stamp)
    os.makedirs(d, exist_ok=True)
    return d


def godot(args, timeout=600, headless=True, capture=True):
    """Запустить Godot в папке проекта. Возвращает (код, вывод)."""
    cmd = [GODOT] + (["--headless"] if headless else []) + ["--path", ROOT] + list(args)
    try:
        p = subprocess.run(cmd, cwd=ROOT, timeout=timeout, capture_output=capture, text=True,
                           encoding="utf-8", errors="replace")
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired as e:
        out = e.stdout.decode("utf-8", "replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        return -1, out + "\n[TIMEOUT]"


def utf8_stdout():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
