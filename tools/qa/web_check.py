"""Проверка веб-версии в браузерах (Playwright): загрузка, ошибки, звук, FPS, игра ботом. Агенты web-qa и perf-audio.

  python tools/qa/web_check.py                                   # живой сайт, Chrome, компьютер
  python tools/qa/web_check.py --url http://127.0.0.1:8060/ --browsers chrome,firefox,webkit --devices desktop,iphone,android
  python tools/qa/web_check.py --headed --play 90 --bot normal   # с окном (настоящая видеокарта) и ботом 90 с

Что меряет: время до меню и до игры, объём загрузки, ошибки консоли и сети, уровень звука на выходе (провалы),
FPS из игры (параметр perf), отчёт бота ([QA-REPORT]), скриншоты. Без --headed браузер рисует 3D программно —
FPS тогда не показателен (функциональную проверку это не портит).
Результат: screenshots/qa/web/<время>/report.json и *.png.
"""
import argparse
import json
import os
import re
import time

from playwright.sync_api import sync_playwright

from common import out_dir, utf8_stdout

LIVE = "https://sosed.2.28.66.82.nip.io/"
AUDIO_HOOK = """
(() => {
  window.__levels = [];
  if (typeof AudioNode === 'undefined' || typeof AudioDestinationNode === 'undefined') return;
  const orig = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function(dest, ...rest) {
    const r = orig.call(this, dest, ...rest);
    try {
      if (dest instanceof AudioDestinationNode) {
        const ctx = dest.context;
        if (!ctx.__an) { ctx.__an = ctx.createAnalyser(); ctx.__an.fftSize = 2048; window.__ctx = ctx; }
        orig.call(this, ctx.__an);
      }
    } catch (e) {}
    return r;
  };
  setInterval(() => {
    const c = window.__ctx; if (!c || !c.__an) return;
    const a = new Float32Array(2048); c.__an.getFloatTimeDomainData(a);
    let m = 0; for (const v of a) m = Math.max(m, Math.abs(v));
    window.__levels.push(+m.toFixed(4));
  }, 250);
})();
"""
DEVICES = {"desktop": None, "iphone": "iPhone 13", "android": "Pixel 7", "ipad": "iPad (gen 7) landscape"}


def check(p, browser, device, url, a, d):
    tag = "%s_%s" % (browser, device)
    res = {"browser": browser, "device": device, "errors": [], "page_errors": [], "failed_requests": [],
           "perf": [], "bytes": 0}
    launch = {"headless": not a.headed}
    if browser == "chrome":
        bt = p.chromium
        launch["channel"] = "chrome"
        if not a.headed:
            launch["args"] = ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"]
    elif browser == "edge":
        bt = p.chromium
        launch["channel"] = "msedge"
    elif browser == "firefox":
        bt = p.firefox
    else:
        bt = p.webkit
    try:
        b = bt.launch(**launch)
    except Exception as e:
        res["fatal"] = "браузер не запустился: %s" % e
        return res
    ctx_args = dict(p.devices[DEVICES[device]]) if DEVICES.get(device) else {"viewport": {"width": 1600, "height": 900}}
    if browser == "firefox":
        ctx_args.pop("is_mobile", None)
    ctx = b.new_context(**ctx_args)
    page = ctx.new_page()
    page.add_init_script(AUDIO_HOOK)
    t0 = time.time()
    marks = {}

    def on_console(m):
        text = m.text
        now = round(time.time() - t0, 2)
        if "Godot Engine v" in text and "engine" not in marks:
            marks["engine"] = now
        if "[QA] menu ready" in text:
            marks.setdefault("menu", now)
        if "[QA] game ready" in text:
            marks.setdefault("game", now)
        if text.startswith("[QA-REPORT] "):
            try:
                res["bot_report"] = json.loads(text[12:])
            except Exception:
                pass
        if "PERF fps=" in text:
            res["perf"].append(text.strip())
        if m.type == "error" and "[QA-REPORT]" not in text:
            res["errors"].append(text[:300])

    page.on("console", on_console)
    page.on("pageerror", lambda e: res["page_errors"].append(str(e)[:300]))
    page.on("requestfailed", lambda r: res["failed_requests"].append("%s %s" % (r.url, r.failure)))

    def on_response(r):
        try:
            if r.status >= 400:
                res["failed_requests"].append("%s HTTP %d" % (r.url, r.status))
            cl = r.headers.get("content-length")
            if cl:
                res["bytes"] += int(cl)
        except Exception:
            pass

    page.on("response", on_response)
    q = "qa=1&perf=1&speed=%s" % a.speed
    if a.bot:
        q += "&bot=%s&report=web&max-real=%d" % (a.bot, max(10, a.play - 3))
    full = url + ("&" if "?" in url else "?") + q
    try:
        page.goto(full, timeout=60000)
    except Exception as e:
        res["fatal"] = "страница не открылась: %s" % e
    deadline = time.time() + a.load_timeout
    while "game" not in marks and time.time() < deadline and "fatal" not in res:
        page.wait_for_timeout(500)
    page.screenshot(path=os.path.join(d, tag + "_start.png"))
    if "game" in marks:
        page.mouse.click(ctx_args.get("viewport", {"width": 1600})["width"] // 2, 300)   # жест пользователя — для звука
        page.wait_for_timeout(int(a.play * 1000))
        page.screenshot(path=os.path.join(d, tag + "_play.png"))
    else:
        txt = ""
        try:
            txt = page.inner_text("body")[:500]
        except Exception:
            pass
        res["no_game"] = "игра не запустилась за %d с. Текст страницы: %s" % (a.load_timeout, txt)
    try:
        lv = page.evaluate("window.__levels || []")
    except Exception:
        lv = []
    res["timings_sec"] = marks
    res["download_mb"] = round(res["bytes"] / 1e6, 1)
    if lv:
        tail = lv[-int(a.play * 4):] if a.play else lv
        silent = sum(1 for v in tail if v < 0.001)
        res["audio"] = {"max": max(lv), "samples": len(tail), "silent_share": round(silent / max(1, len(tail)), 2)}
    fps = [int(m.group(1)) for m in (re.search(r"fps=(\d+)", x) for x in res["perf"]) if m]
    if fps:
        res["fps"] = {"min": min(fps), "avg": round(sum(fps) / len(fps), 1), "samples": len(fps)}
    b.close()
    return res


def main():
    utf8_stdout()
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default=LIVE)
    ap.add_argument("--browsers", default="chrome", help="chrome,edge,firefox,webkit")
    ap.add_argument("--devices", default="desktop", help="desktop,iphone,android,ipad")
    ap.add_argument("--headed", action="store_true", help="с окном: настоящая видеокарта, честный FPS")
    ap.add_argument("--play", type=int, default=25, help="секунд игры после загрузки")
    ap.add_argument("--speed", default="1")
    ap.add_argument("--bot", default="", help="бот играет в браузере: careful|normal|reckless")
    ap.add_argument("--load-timeout", type=int, default=150)
    a = ap.parse_args()
    d = out_dir("web")
    results = []
    with sync_playwright() as p:
        for br in a.browsers.split(","):
            for dev in a.devices.split(","):
                r = check(p, br.strip(), dev.strip(), a.url, a, d)
                results.append(r)
                t = r.get("timings_sec", {})
                print("\n== %s / %s" % (r["browser"], r["device"]))
                if r.get("fatal"):
                    print("   ФАТАЛЬНО:", r["fatal"])
                print("   до движка %s с, до меню %s с, до игры %s с, загружено %.1f МБ"
                      % (t.get("engine"), t.get("menu"), t.get("game"), r.get("download_mb", 0)))
                if r.get("no_game"):
                    print("   ", r["no_game"])
                if "audio" in r:
                    print("   звук: макс %.3f, доля тишины %.0f%%" % (r["audio"]["max"], r["audio"]["silent_share"] * 100))
                if "fps" in r:
                    print("   FPS: мин %d, средн %.1f" % (r["fps"]["min"], r["fps"]["avg"]))
                for e in (r["errors"] + r["page_errors"] + r["failed_requests"])[:8]:
                    print("   ОШИБКА:", e)
                if r.get("bot_report"):
                    br_ = r["bot_report"]
                    print("   бот: %s, задания %s/%s, поимок %s" % (br_["result"], br_.get("tasks_done"), br_.get("tasks_total"), br_.get("catches")))
    json.dump(results, open(os.path.join(d, "report.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("\nПапка:", d)


if __name__ == "__main__":
    main()
