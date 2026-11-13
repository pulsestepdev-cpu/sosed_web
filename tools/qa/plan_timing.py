"""Оценка распорядка соседа по дням: когда он приходит к каждому делу и сколько раз за день бывает у мест заданий.

  python tools/qa/plan_timing.py            # все дни
  python tools/qa/plan_timing.py 6 -v       # день 6 подробно (время каждого дела)

Модель грубая: ходьба по дорожке со скоростью соседа, лестницы и двери-переходы — по их длине, на месте — секунды
из распорядка + 1.2 с на «пользуется» + REACT с на реакцию (если место — задание дня). Читает scripts/levels/days.gd.
Цель: каждое место задания — минимум 2 визита за день, первый — не раньше ~2 минут игры (игроку надо успеть).
"""
import re
import sys

from common import utf8_stdout

SPEED = 1.0          # м/с (1.05 трезвый, пьяный медленнее)
DAY_SEC = 12.5 * 50  # 07:30–20:00
WAKE_SEC = 0.5 * 50  # просыпается в 8:00
REACT = 7.0
FH = 3.05
CONN = [  # (этаж a, x a, этаж b, x b, длина)
    (0, 3.2, 1, 3.7, 9.1), (0, 13.8, 1, 13.3, 9.1),    # лестницы
    (0, 3.25, -1, 1.75, 6.1 + 1.0), (1, 13.3, 2, 15.5, 6.4 + 1.0),   # подвал, чердак (+ время в двери)
]
USES = {"mouthwash": "mouthwash", "coffee": "coffee", "fridge": "fridge", "soda": "soda", "jacket": "jacket",
        "kvass": "kvass", "brine": "brine", "gamepad": "gamepad", "phone": "phone", "keys": "keys", "rods": "rods",
        "ladder": "ladder", "peeltrap": "fridge", "soaptrap": "mouthwash", "salad": None}


def parse():
    src = open("scripts/levels/days.gd", encoding="utf-8").read()
    consts = {}
    for m in re.finditer(r'const (\w+) := \[([^\[\]]*)\]', src):
        parts = [p.strip().strip('"') for p in m.group(2).split(",")]
        if len(parts) >= 7:
            consts[m.group(1)] = parts
    days = []
    body = src[src.index("const _DAYS"):]
    for blk in re.findall(r'\{\s*#.*?\n(.*?)\n\t\},', body, re.S):
        rooms = re.search(r'"rooms": \[(.*?)\]', blk).group(1)
        tasks = re.search(r'"tasks": \[(.*?)\]', blk, re.S).group(1)
        plan = re.search(r'"plan": \[(.*?)\],', blk, re.S).group(1)
        loop = int(re.search(r'"loop": (\d+)', blk).group(1))
        days.append({
            "rooms": re.findall(r'"(\w+)"', rooms), "tasks": re.findall(r'"(\w+)"', tasks),
            "plan": [consts[n] for n in re.findall(r'\b(\w+)\b', plan)], "loop": loop,
        })
    return days


def route(f0, x0, f1, x1, conns):
    # Дейкстра по точкам связей (как game.gd: _route_floors)
    nodes = [(f0, x0), (f1, x1)]
    for c in conns:
        nodes += [(c[0], c[1]), (c[2], c[3])]
    dist = [1e9] * len(nodes)
    dist[0] = 0
    done = [False] * len(nodes)
    while True:
        u = min((i for i in range(len(nodes)) if not done[i] and dist[i] < 1e9), key=lambda i: dist[i], default=None)
        if u is None or u == 1:
            break
        done[u] = True
        for v in range(len(nodes)):
            if done[v] or v == u:
                continue
            w = 1e9
            if nodes[u][0] == nodes[v][0]:
                w = abs(nodes[u][1] - nodes[v][1])
            if u >= 2 and v >= 2 and (u - 2) // 2 == (v - 2) // 2:
                w = conns[(u - 2) // 2][4]
            dist[v] = min(dist[v], dist[u] + w)
    return dist[1]


def simulate(d, verbose=False):
    rooms = d["rooms"]
    conns = CONN[:1]
    if "living" in rooms and "balcony" in rooms:
        conns.append(CONN[1])
    if "basement" in rooms:
        conns.append(CONN[2])
    if "attic" in rooms:
        conns.append(CONN[3])
    task_uses = {USES[t] for t in d["tasks"] if USES.get(t)}
    plan = d["plan"]
    t = WAKE_SEC
    i = 1
    pos = (1, 9.35)
    visits = {}
    log = []
    while t < DAY_SEC:
        e = plan[i]
        x, f, what, use, stay = float(e[0]), int(e[1]), e[2], e[4], float(e[6])
        walk = route(pos[0], pos[1], f, x, conns)
        if len(e) > 7:
            walk += 2 * abs(float(e[7]) + 1.0)
        t += walk / SPEED
        if t >= DAY_SEC:
            break
        hour = 7.5 + t / 50
        log.append("%5.2f  %-22s %s" % (hour, what, ("[%s]" % use) if use in task_uses else ""))
        if use in task_uses:
            visits.setdefault(use, []).append(round(hour, 2))
        t += stay + (1.2 if use else 0) + (REACT if use in task_uses else 0)
        pos = (f, x)
        i = i + 1 if i + 1 < len(plan) else d["loop"]
    return visits, log


def main():
    utf8_stdout()
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    only = [int(a) for a in args] or list(range(1, 8))
    days = parse()
    for n in only:
        d = days[n - 1]
        visits, log = simulate(d, "-v" in sys.argv)
        need = sorted({USES[t] for t in d["tasks"] if USES.get(t)})
        bad = [u for u in need if len(visits.get(u, [])) < 2]
        print("День %d: дел за день %d, визиты к местам заданий:" % (n, len(log)))
        for u in need:
            print("   %-10s %s%s" % (u, visits.get(u, []), "   <-- мало" if u in bad else ""))
        if "-v" in sys.argv:
            print("\n".join("      " + l for l in log))


if __name__ == "__main__":
    main()
