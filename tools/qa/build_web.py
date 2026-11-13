"""Собрать веб-версию и (по желанию) поднять локальный сервер.

  python tools/qa/build_web.py              # сборка в build/web
  python tools/qa/build_web.py --serve      # сборка + сервер http://127.0.0.1:8060 (до Ctrl+C / остановки задачи)
  python tools/qa/build_web.py --serve-only
"""
import argparse
import functools
import http.server
import os

from common import ROOT, godot, utf8_stdout


def build():
    os.makedirs(os.path.join(ROOT, "build", "web"), exist_ok=True)
    code, out = godot(["--export-release", "Web", "build/web/index.html"], timeout=900)
    pck = os.path.join(ROOT, "build", "web", "index.pck")
    wasm = os.path.join(ROOT, "build", "web", "index.wasm")
    ok = os.path.exists(pck) and os.path.getsize(pck) > 0
    print("Сборка:", "OK" if ok else "ОШИБКА (код %s)" % code)
    if ok:
        print("  index.pck  %.1f МБ" % (os.path.getsize(pck) / 1e6))
        print("  index.wasm %.1f МБ" % (os.path.getsize(wasm) / 1e6))
    else:
        print(out[-3000:])
    return ok


def serve(port):
    h = functools.partial(http.server.SimpleHTTPRequestHandler, directory=os.path.join(ROOT, "build", "web"))
    print("Сервер: http://127.0.0.1:%d/" % port)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), h).serve_forever()


if __name__ == "__main__":
    utf8_stdout()
    ap = argparse.ArgumentParser()
    ap.add_argument("--serve", action="store_true")
    ap.add_argument("--serve-only", action="store_true")
    ap.add_argument("--port", type=int, default=8060)
    a = ap.parse_args()
    if not a.serve_only and not build():
        raise SystemExit(1)
    if a.serve or a.serve_only:
        serve(a.port)
