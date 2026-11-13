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
    """Две сборки: build/web — многопоточная (Chrome/Edge/Firefox), build/web/compat — без потоков (Safari, iPhone)."""
    ok_all = True
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    open(os.path.join(ROOT, "build", ".gdignore"), "w").close()     # Godot не импортирует содержимое build/
    for preset, sub in (("Web", ""), ("Web-compat", "compat")):
        d = os.path.join(ROOT, "build", "web", sub)
        os.makedirs(d, exist_ok=True)
        code, out = godot(["--export-release", preset, os.path.join("build", "web", sub, "index.html").replace("\\", "/")], timeout=900)
        pck, wasm = os.path.join(d, "index.pck"), os.path.join(d, "index.wasm")
        ok = os.path.exists(pck) and os.path.getsize(pck) > 0
        ok_all = ok_all and ok
        print("Сборка %-10s:" % preset, "OK" if ok else "ОШИБКА (код %s)" % code)
        if ok:
            print("  index.pck  %.1f МБ, index.wasm %.1f МБ" % (os.path.getsize(pck) / 1e6, os.path.getsize(wasm) / 1e6))
        else:
            print(out[-3000:])
    return ok_all


class Handler(http.server.SimpleHTTPRequestHandler):
    """Как nginx на сервере: заголовки изоляции (нужны многопоточной сборке) и без кэша."""
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, *a):
        pass


def serve(port):
    h = functools.partial(Handler, directory=os.path.join(ROOT, "build", "web"))
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
