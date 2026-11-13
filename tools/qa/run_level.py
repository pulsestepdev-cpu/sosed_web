"""Прогоны уровня ботом без окна + сводка. Для агентов level-runner и balance.

  python tools/qa/run_level.py                         # 1 прогон, стратегия normal, день 3 (среда)
  python tools/qa/run_level.py --day all --runs 2      # вся неделя (Пн–Вс), сводка по каждому дню
  python tools/qa/run_level.py --day 1,4,7 --bot careful,normal,reckless
  python tools/qa/run_level.py --bot careful,normal,reckless --runs 3 --parallel 3
  python tools/qa/run_level.py --bot normal --extra "--start=11 --drunk=30"
  python tools/qa/run_level.py --windowed --perf        # в окне: честный FPS (окно на экране!)

Результат: screenshots/qa/runs/<время>/<стратегия>_<n>.json (+ .log) и summary.json, сводка печатается.
"""
import argparse
import concurrent.futures as cf
import json
import os
import shlex
import statistics

from common import godot, out_dir, utf8_stdout

KEY_LINES = ("BOT", "TOAST", "FINISHED", "SCRIPT ERROR", "ERROR: res", "Invalid", "[QA]", "PERF")


def one_run(day, strategy, n, d, speed, extra, windowed, perf, max_real):
    rep = os.path.join(d, "d%s_%s_%d.json" % (day, strategy, n))
    args = ["res://scenes/game.tscn", "--", "--day=%s" % day, "--autostart", "--log", "--speed=%s" % speed,
            "--bot=%s" % strategy, "--report=%s" % rep, "--quit-on-end", "--max-real=%d" % max_real]
    if perf:
        args.append("--perf")
    args += shlex.split(extra)
    code, out = godot(args, timeout=max_real + 60, headless=not windowed)
    with open(rep[:-5] + ".log", "w", encoding="utf-8") as f:
        f.write(out)
    errors = [l for l in out.splitlines() if "SCRIPT ERROR" in l or "ERROR: res://" in l or "Invalid" in l]
    try:
        r = json.load(open(rep, encoding="utf-8"))
    except Exception:
        r = {"result": {"win": False, "reason": "нет отчёта (код %s)" % code}, "tasks": {}, "events": []}
    r["strategy"] = strategy
    r["day"] = day
    r["script_errors"] = errors[:20]
    return r


def summarize(runs):
    by = {}
    for r in runs:
        by.setdefault("день %s · %s" % (r["day"], r["strategy"]), []).append(r)
    out = {}
    for s, rs in by.items():
        wins = [r for r in rs if r["result"].get("win")]
        task_rate = {}
        for r in rs:
            for t, ok in r.get("tasks", {}).items():
                task_rate.setdefault(t, []).append(1 if ok else 0)
        out[s] = {
            "runs": len(rs),
            "win_rate": round(len(wins) / len(rs), 2),
            "avg_end_hour_win": round(statistics.mean([r["hour_end"] for r in wins]), 2) if wins else None,
            "avg_score": round(statistics.mean([r.get("score", 0) for r in rs]), 1),
            "avg_catches": round(statistics.mean([r.get("catches", 0) for r in rs]), 2),
            "avg_tasks": round(statistics.mean([r.get("tasks_done", 0) for r in rs]), 2),
            "voice_overlaps": sum(r.get("voice_overlaps", 0) for r in rs),
            "reasons": [r["result"].get("reason") for r in rs],
            "task_completion": {t: round(sum(v) / len(v), 2) for t, v in task_rate.items()},
            "script_errors": sorted({e for r in rs for e in r.get("script_errors", [])})[:20],
        }
    return out


def main():
    utf8_stdout()
    ap = argparse.ArgumentParser()
    ap.add_argument("--bot", default="normal", help="стратегии через запятую: careful,normal,reckless")
    ap.add_argument("--day", default="3", help="день 1..7, список через запятую или all (вся неделя)")
    ap.add_argument("--runs", type=int, default=1, help="прогонов на стратегию")
    ap.add_argument("--parallel", type=int, default=2, help="одновременных процессов Godot")
    ap.add_argument("--speed", default="8", help="Engine.time_scale (8 — уровень ~1,5 мин)")
    ap.add_argument("--extra", default="", help="доп. аргументы игры, напр. \"--start=11 --drunk=30\"")
    ap.add_argument("--windowed", action="store_true", help="с окном (для FPS); --parallel лучше 1")
    ap.add_argument("--perf", action="store_true", help="печатать FPS в лог")
    ap.add_argument("--max-real", type=int, default=300, help="страховка, секунд реального времени")
    a = ap.parse_args()
    d = out_dir("runs")
    days = list(range(1, 8)) if a.day == "all" else [int(x) for x in a.day.split(",")]
    jobs = [(dy, s.strip(), n) for dy in days for s in a.bot.split(",") for n in range(1, a.runs + 1)]
    with cf.ThreadPoolExecutor(max_workers=max(1, a.parallel)) as ex:
        runs = list(ex.map(lambda j: one_run(j[0], j[1], j[2], d, a.speed, a.extra, a.windowed, a.perf, a.max_real), jobs))
    summ = summarize(runs)
    json.dump({"summary": summ, "args": vars(a)}, open(os.path.join(d, "summary.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    print("Папка:", d)
    for s, v in summ.items():
        print("\n== %s: побед %d%% из %d, финал в среднем в %s, очки %.0f, поимок %.2f, заданий %.1f/%d, наложений голосов %d"
              % (s, v["win_rate"] * 100, v["runs"], v["avg_end_hour_win"], v["avg_score"], v["avg_catches"],
                 v["avg_tasks"], len(v["task_completion"]), v["voice_overlaps"]))
        print("   итоги:", "; ".join(str(x) for x in v["reasons"]))
        never = [t for t, rate in v["task_completion"].items() if rate == 0]
        if never:
            print("   ни разу не сработало:", ", ".join(never))
        for e in v["script_errors"]:
            print("   ОШИБКА:", e)


if __name__ == "__main__":
    main()
