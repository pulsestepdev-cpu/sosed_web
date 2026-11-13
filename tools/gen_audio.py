# Звуки и озвучка уровня 1: эффекты и запасная музыка — кодом (чистый Python), голос — нейросинтез Microsoft Edge (edge-tts).
#   python tools/gen_audio.py            — всё
#   python tools/gen_audio.py sfx|voice|music      (voice ключ1,ключ2 — только эти реплики; voice missing — недостающие)
# Результат: assets/audio/sfx/*.wav, assets/audio/voice/*.mp3 + voice/index.json (текст → файл), assets/audio/music/*.wav
import json, math, os, random, struct, sys, wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
SR = 22050
random.seed(7)

def save(path, samples, sr=SR):
    if os.path.exists(path[:-4] + ".ogg"):      # есть настоящая запись (Kenney, CC0) — синтез не нужен
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = max(1e-6, max(abs(s) for s in samples))
    k = 0.9 / peak if peak > 0.9 else 1.0
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * k)) * 32000)) for s in samples))
    print("WAV", os.path.relpath(path, ROOT), "%.2fs" % (len(samples) / sr))

def env(i, n, a=0.005, r=None):
    t = i / SR
    att = min(1.0, t / a) if a > 0 else 1.0
    rel = 1.0 if r is None else max(0.0, 1.0 - i / n) ** r
    return att * rel

def noise_lp(n, k):
    """Шум, сглаженный однополюсным фильтром (k — 0..1, меньше — глуше)."""
    out, y = [], 0.0
    for _ in range(n):
        y += k * (random.uniform(-1, 1) - y)
        out.append(y)
    return out

# ---------------------------------------------------------------- шумы и эффекты
def step(variant, soft=False):
    n = int(SR * (0.16 if not soft else 0.12))
    base = noise_lp(n, 0.08 + 0.02 * variant)
    f0 = 70 + variant * 9
    out = []
    for i in range(n):
        t = i / SR
        thump = math.sin(2 * math.pi * f0 * t) * math.exp(-t * 40)
        e = math.exp(-t * (32 if not soft else 45))
        out.append((base[i] * 2.2 * e + thump * 0.9) * (0.45 if soft else 1.0))
    return out

def rustle(dur=0.9):
    n = int(SR * dur)
    hp, prev = [], 0.0
    raw = noise_lp(n, 0.6)
    for x in raw:
        hp.append(x - prev); prev = x
    out = []
    for i in range(n):
        t = i / SR
        am = 0.35 + 0.65 * abs(math.sin(t * 23 + math.sin(t * 7) * 2))
        out.append(hp[i] * am * env(i, n, 0.03, 0.6) * 3)
    return out

def tone(freqs, dur, shape="sine", decay=6.0, vol=0.5):
    n = int(SR * dur)
    out = [0.0] * n
    for f in freqs:
        for i in range(n):
            t = i / SR
            ph = 2 * math.pi * f * t
            v = math.sin(ph) if shape == "sine" else (1 if math.sin(ph) > 0 else -1) * 0.5 if shape == "square" else \
                (2 * ((f * t) % 1) - 1) * 0.6
            out[i] += v * math.exp(-t * decay) * vol * min(1, t / 0.004)
    return out

def seq(notes, gap=0.0):
    out = []
    for f, d in notes:
        out += (tone([f, f * 2.0], d, decay=5, vol=0.35) if f > 0 else [0.0] * int(SR * d))
        out += [0.0] * int(SR * gap)
    return out

def glug():
    out = []
    for k in range(5):
        n = int(SR * 0.11)
        f = 180 + random.uniform(-30, 40)
        for i in range(n):
            t = i / SR
            out.append(math.sin(2 * math.pi * (f + 900 * t) * t) * math.exp(-t * 30) * 0.8)
        out += [0.0] * int(SR * 0.03)
    return out

def clink():
    return tone([2093, 3136, 4186], 0.5, decay=9, vol=0.3)

def creak():
    n = int(SR * 0.7)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 220 + 160 * math.sin(t * 9) + 60 * math.sin(t * 31)
        ph += 2 * math.pi * f / SR
        saw = 2 * ((ph / (2 * math.pi)) % 1) - 1
        out.append(saw * 0.4 * env(i, n, 0.05, 1.2) * (0.6 + 0.4 * math.sin(t * 60)))
    return out

def whoosh(dur=0.35):
    n = int(SR * dur)
    raw = noise_lp(n, 0.35)
    return [raw[i] * math.sin(math.pi * i / n) ** 2 * 2.5 for i in range(n)]

def thud(big=False):
    n = int(SR * (0.6 if big else 0.3))
    raw = noise_lp(n, 0.05)
    out = []
    for i in range(n):
        t = i / SR
        out.append((math.sin(2 * math.pi * (55 - 20 * t) * t) * 1.2 + raw[i] * 3) * math.exp(-t * (7 if big else 14)))
    return out

def punch():
    return [a + b for a, b in zip(whoosh(0.18) + [0.0] * 4000, thud() + [0.0] * 4000)]

def snore():
    n = int(SR * 2.6)
    raw = noise_lp(n, 0.12)
    out = []
    for i in range(n):
        t = i / SR
        if t < 1.5:   # вдох-храп
            e = math.sin(math.pi * t / 1.5) ** 1.5
            buzz = math.sin(2 * math.pi * 38 * t) > 0.3
            out.append(raw[i] * e * (2.5 if buzz else 0.6) + math.sin(2 * math.pi * 76 * t) * e * 0.25)
        else:         # выдох-свист
            u = (t - 1.5) / 1.1
            e = math.sin(math.pi * u) * 0.5
            out.append(raw[i] * e * 0.5 + math.sin(2 * math.pi * (600 - 200 * u) * t) * e * 0.08)
    return out

def hiccup():
    n = int(SR * 0.22)
    out = []
    for i in range(n):
        t = i / SR
        f = 380 + 600 * math.exp(-t * 30)
        out.append(math.sin(2 * math.pi * f * t) * math.exp(-t * 22) * 0.8 + random.uniform(-1, 1) * math.exp(-t * 60) * 0.4)
    return out

def burp():
    n = int(SR * 0.7)
    raw = noise_lp(n, 0.2)
    out, ph = [], 0.0
    for i in range(n):
        t = i / SR
        f = 95 + 25 * math.sin(t * 13)
        ph += 2 * math.pi * f / SR
        pulse = (math.sin(ph) > 0.6) * 1.0
        out.append((pulse * 0.9 + raw[i] * 1.5) * env(i, n, 0.03, 1.0))
    return out

def splash():
    n = int(SR * 0.6)
    raw = noise_lp(n, 0.5)
    return [raw[i] * math.exp(-i / SR * 6) * 2 + math.sin(2 * math.pi * 120 * i / SR) * math.exp(-i / SR * 20) for i in range(n)]

def gen_sfx():
    d = os.path.join(OUT, "sfx")
    for v in range(4):
        save(os.path.join(d, "step_%d.wav" % v), step(v))
        save(os.path.join(d, "sneak_%d.wav" % v), step(v, soft=True))
    save(os.path.join(d, "rustle.wav"), rustle())
    save(os.path.join(d, "pickup.wav"), seq([(784, 0.07), (1047, 0.07), (1568, 0.2)]))
    save(os.path.join(d, "swap.wav"), glug() + clink())
    save(os.path.join(d, "drink.wav"), glug())
    save(os.path.join(d, "clink.wav"), clink())
    save(os.path.join(d, "creak.wav"), creak())
    save(os.path.join(d, "whoosh.wav"), whoosh())
    save(os.path.join(d, "thud.wav"), thud(True))
    save(os.path.join(d, "punch.wav"), punch())
    # snore.wav, snore_2.wav — настоящая запись (Wikimedia Commons «Snoring of old man.ogg», CC0), не генерировать
    save(os.path.join(d, "hiccup.wav"), hiccup())
    save(os.path.join(d, "burp.wav"), burp())
    save(os.path.join(d, "splash.wav"), splash())
    save(os.path.join(d, "hide.wav"), rustle(0.4))
    save(os.path.join(d, "alert.wav"), seq([(988, 0.08), (0, 0.03), (988, 0.12)]))
    save(os.path.join(d, "click.wav"), tone([1400], 0.05, decay=60, vol=0.6))
    save(os.path.join(d, "prank.wav"), seq([(523, 0.08), (659, 0.08), (784, 0.08), (1047, 0.25)]))
    save(os.path.join(d, "stage.wav"), seq([(392, 0.1), (494, 0.1), (587, 0.25)]))
    save(os.path.join(d, "win.wav"), seq([(523, 0.15), (659, 0.15), (784, 0.15), (1047, 0.3), (784, 0.12), (1047, 0.5)]))
    save(os.path.join(d, "fail.wav"), seq([(392, 0.25), (370, 0.25), (349, 0.25), (330, 0.7)]))

# ---------------------------------------------------------------- музыка: весёлый «ум-па» цикл
def gen_music():
    sr = SR
    bpm = 132
    beat = 60 / bpm
    # гармония: C F G C | Am F G C (по 2 доли)
    prog = [(48, 52, 55), (53, 57, 60), (55, 59, 62), (48, 52, 55), (57, 60, 64), (53, 57, 60), (55, 59, 62), (48, 52, 55)]
    mel = [72, 74, 76, 79, 77, 76, 74, 72, 74, 76, 77, 74, 72, 71, 72, -1,
           76, 77, 79, 81, 79, 77, 76, 74, 72, 74, 76, 74, 71, 72, 72, -1]
    def hz(m): return 440 * 2 ** ((m - 69) / 12)
    total = int(sr * beat * 4 * len(prog) / 2 * 2)   # 8 тактов по 4 доли → 2 прохода гармонии
    out = [0.0] * total
    def add(start, dur, f, vol, kind):
        a = int(start * sr); n = int(dur * sr)
        for i in range(n):
            if a + i >= total: break
            t = i / sr
            if kind == "bass":
                v = math.sin(2 * math.pi * f * t) + 0.3 * math.sin(4 * math.pi * f * t)
                e = math.exp(-t * 5)
            elif kind == "chord":
                v = (2 * ((f * t) % 1) - 1) * 0.5
                e = math.exp(-t * 14)
            else:   # мелодия — «кларнет»
                v = math.sin(2 * math.pi * f * t + 0.8 * math.sin(2 * math.pi * f * 2 * t)) * (1 + 0.05 * math.sin(t * 30))
                e = min(1, t / 0.02) * math.exp(-t * 2.5)
            out[a + i] += v * e * vol
    for rep in range(2):
        for ci, ch in enumerate(prog):
            t0 = (rep * len(prog) + ci) * beat * 2
            add(t0, beat, hz(ch[0] - 12), 0.45, "bass")
            add(t0 + beat, beat, hz(ch[2] - 24 + 12), 0.35, "bass")
            for k in range(3):
                add(t0 + beat * 0.5, beat * 0.4, hz(ch[k]), 0.12, "chord")
                add(t0 + beat * 1.5, beat * 0.4, hz(ch[k]), 0.12, "chord")
    for i, m in enumerate(mel):
        if m > 0:
            add(i * beat, beat * 0.95, hz(m), 0.22, "mel")
    # тихий «шейкер»
    for b in range(int(total / (sr * beat / 2))):
        a = int(b * beat / 2 * sr)
        for i in range(int(0.04 * sr)):
            if a + i < total:
                out[a + i] += random.uniform(-1, 1) * math.exp(-i / sr * 90) * (0.06 if b % 2 else 0.03)
    save(os.path.join(OUT, "music", "level_loop.wav"), [x * 0.7 for x in out], sr)
    # меню — тот же мотив медленнее и тише (растянуть повтором отсчётов)
    slow = []
    for i in range(int(len(out) * 1.25)):
        slow.append(out[int(i / 1.25)] * 0.6)
    save(os.path.join(OUT, "music", "menu_loop.wav"), slow, sr)

# ---------------------------------------------------------------- голос
# Нейросетевой синтез Microsoft Edge (бесплатно, нужен интернет): pip install edge-tts
# Голос ru-RU-DmitryNeural; сосед — ниже и грубее, герой — выше и быстрее. Файлы — voice/<ключ>.mp3.
# [ключ, кто, текст]. Кто: n — сосед, h — герой. Текст в игре сверяется с index.json по точному совпадению.
LINES = [
    ("n_oath", "n", "Всё, сегодня больше не пью!"),
    ("n_oath2", "n", "Не, вообще к пиву не тянет."),
    ("n_wtf1", "n", "Да ну нахуй!"),
    ("n_wtf2", "n", "Да как так нахуй?!"),
    ("n_wtf3", "n", "Да ну нахер, серьёзно?!"),
    ("n_wtf4", "n", "Это чё за херня, нахуй?!"),
    ("n_wtf5", "n", "Да вы издеваетесь, нахуй?!"),
    ("n_wtf6", "n", "Ну ёпт твою налево!"),
    ("n_mouthwash", "n", "Ух… бодрит!"),
    ("n_mouthwash0", "n", "Кхе-кхе! Это чё такое?!"),
    ("n_mouthwash2", "n", "А ничё так, освежает!"),
    ("n_coffee0", "n", "Кхм! Это кофе?!"),
    ("n_coffee", "n", "Чё-то кофе сегодня крепкий…"),
    ("n_coffee2", "n", "Ну и ладно, допью."),
    ("n_fridge1", "n", "Это ж не минералка…"),
    ("n_fridge2", "n", "Ну раз уж открыл…"),
    ("n_fridge3", "n", "Эх, понеслась!"),
    ("n_soda", "n", "Хм. А газировка-то с пеной…"),
    ("n_soda2", "n", "Пивасик?! …Ну, раз налито."),
    ("n_jacket0", "n", "Опа… А это чё в кармане?"),
    ("n_jacket", "n", "…Это знак."),
    ("n_jacket2", "n", "За знакомство!"),
    ("n_gamepad", "n", "Где геймпад?!"),
    ("n_phone", "n", "Где телефон?!"),
    ("n_left", "n", "Я же его тут оставлял!"),
    ("n_angry", "n", "Ну всё, я злой!"),
    ("n_keys", "n", "Где ключи?!"),
    ("n_keys2", "n", "Я же их в миску клал!"),
    ("n_keys3", "n", "…Ну раз дома — можно."),
    ("n_who", "n", "Э… Кто здесь?"),
    ("n_steps", "n", "Кто здесь топает?"),
    ("n_seemed", "n", "Мне показалось?"),
    ("n_catch", "n", "А ну пошёл отсюда!"),
    ("n_catch2", "n", "Иди сюда, засранец!"),
    ("n_lowkick", "n", "Лоу-кик! Работаем!"),
    ("n_kick1", "n", "Так, смотри сюда! Лоу-кик!"),
    ("n_kick2", "n", "Руки держим, руки!"),
    ("n_kick3", "n", "Работаем, работаем!"),
    ("n_kick4", "n", "Кийя!"),
    ("n_show", "n", "Смотри, как я могу! Кийя!"),
    ("n_skip", "n", "Э, куда скипаешь?!"),
    ("n_hello", "n", "Привет, откуда?"),
    ("n_sleepy", "n", "Я… ик… не пью…"),
    ("n_tipsy1", "n", "Ну одну-то можно…"),
    ("n_tipsy2", "n", "Это не считается."),
    ("n_merry1", "n", "А чё, нормально сидим!"),
    ("n_merry2", "n", "Завтра точно брошу."),
    ("n_stash", "n", "Э… А где моя заначка за банками?"),
    ("n_stash2", "n", "Домовой, что ли, завёлся?"),
    ("n_bulb", "n", "Опять перегорела?"),
    ("n_bulb2", "n", "Да что ж такое-то, а?!"),
    ("n_bulb3", "n", "Кто лампочку подсунул?!"),
    ("n_fall", "n", "Уа-а-а!"),
    ("n_mineral", "n", "Минералочка… Успокоился."),
    ("n_more1", "n", "Ну ещё по одной…"),
    ("n_more2", "n", "За ремонт!"),
    ("n_more3", "n", "Последняя. Точно."),
    ("n_grumble1", "n", "Бу-бу-бу… никто не ценит…"),
    ("n_grumble2", "n", "Так-с… шпаклёвочка…"),
    ("n_grumble3", "n", "Эх, жизнь…"),
    ("n_grumble4", "n", "Хм-м… Ну и ладно."),
    ("n_ouch", "n", "Ой-ё-ёй… Спина моя…"),
    ("n_slip0", "n", "Оп-оп-оп… А-а-а!"),
    ("n_slip", "n", "Твою ж… Кто мыло бросил?!"),
    ("n_slip2", "n", "Кто кожуру бросил?!"),
    ("n_revenge", "n", "Узнаю, кто это сделал — урою!"),
    ("n_salad", "n", "Салатик… моя подушечка…"),
    ("h_taunt1", "h", "Пивная открывашка!"),
    ("h_taunt2", "h", "Ветродуйка!"),
    ("h_taunt3", "h", "Турбина перегарная!"),
    ("h_taunt4", "h", "Пей до дна, открывашка!"),
    ("h_taunt5", "h", "Давай-давай, ветродуйка!"),
    ("h_set_mouthwash", "h", "Пусть прополощет, ветродуйка!"),
    ("h_set_coffee", "h", "Кофеёк с сюрпризом!"),
    ("h_set_fridge", "h", "Минералочка, ага. Хе-хе."),
    ("h_set_soda", "h", "Газировочка с пенкой!"),
    ("h_set_jacket", "h", "Сходит он за хлебом, как же!"),
    ("h_set_ladder", "h", "Электрик, ты где? Хе-хе."),
    ("h_set_peel", "h", "Смотри под ноги, турбина перегарная!"),
    ("h_set_soap", "h", "Скользкого утречка, ветродуйка!"),
    ("h_set_keys", "h", "Ключики теперь мои!"),
    ("h_set_gamepad", "h", "Поиграл — и хватит!"),
    ("h_set_phone", "h", "Позвонишь потом, открывашка!"),
    ("h_set_salad", "h", "Подушечка готова!"),
    ("h_found", "h", "Опа, заначка!"),
    ("h_heh", "h", "Хе-хе-хе…"),
    ("h_oops", "h", "Ой-ой-ой!"),
    ("h_ouch", "h", "Ай! Да за что?!"),
    ("h_win", "h", "Готов, голубчик!"),
    ("h_fin1", "h", "Так тебе, ветродуйка!"),
    ("h_fin2", "h", "И вот опять ты на бутылке!"),
    ("n_w001", "n", "Вторник. Разгрузочный день. Только кефир!"),
    ("n_w002", "n", "Кефир — это тоже напиток. Почти."),
    ("n_w003", "n", "Среда. Гости не придут — и пить не с кем!"),
    ("n_w004", "n", "Одному пить — это алкоголизм. А я не алкоголик!"),
    ("n_w005", "n", "Четверг. Ревизия погреба. Только огурцы считаю!"),
    ("n_w006", "n", "Самогонный аппарат — память о деде. Не трогаю!"),
    ("n_w007", "n", "Пятница. Держусь. Я держусь, блядь!"),
    ("n_w008", "n", "На рыбалку — только с чаем. Только с чаем, сука."),
    ("n_w009", "n", "Суббота. Генеральная уборка — и никакой синьки!"),
    ("n_w010", "n", "Дедов хлам разберу — и спать. Трезвым!"),
    ("n_w011", "n", "Воскресенье. Завтра новая жизнь. А сегодня — репетиция!"),
    ("n_w012", "n", "Последний день. Продержусь — и я человек!"),
    ("n_w013", "n", "Ёб твою мать, опять?!"),
    ("n_w014", "n", "Кто, блядь, тут шарится?!"),
    ("n_w015", "n", "Да чтоб тебя через колено!"),
    ("n_w016", "n", "Ну всё, пиздец котёнку!"),
    ("n_w017", "n", "Я же завязал, ёпта!"),
    ("n_w018", "n", "Кто подменил, тому пиздец!"),
    ("n_w019", "n", "Сука, ну что за день такой?!"),
    ("n_w020", "n", "Мать твою за ногу!"),
    ("n_w021", "n", "Кхе! Это чё за квас такой?!"),
    ("n_w022", "n", "Ядрёный квасок… Ещё кружечку!"),
    ("n_w023", "n", "Ну и хрен с ним, раз уж налито…"),
    ("n_w024", "n", "Тьфу! Рассол водкой пахнет!"),
    ("n_w025", "n", "…Хотя от нервов — самое то."),
    ("n_w026", "n", "Эх, понеслась душа в рай!"),
    ("n_w027", "n", "Где удочки?!"),
    ("n_w028", "n", "Я их тут ставил, сука!"),
    ("n_w029", "n", "Рыбалка накрылась… Ну и хрен с ней!"),
    ("n_w030", "n", "Удочки на месте. Червей бы ещё…"),
    ("n_w031", "n", "Карась, жди меня!"),
    ("n_w032", "n", "Мать твою за ногу, пол скользкий!"),
    ("n_w033", "n", "А-а-а, моя спина, блядь!"),
    ("n_w034", "n", "Попался, сучонок!"),
    ("n_w035", "n", "Ах ты ж гнида подъездная!"),
    ("n_w036", "n", "Я тебе щас покажу, вредитель!"),
    ("n_w037", "n", "Чё за шорох?"),
    ("n_w038", "n", "Кто тут, блядь?"),
    ("n_w039", "n", "Белочка, что ли, пришла?"),
    ("n_w040", "n", "Почудилось. Надо меньше пить… А я и не пью!"),
    ("n_w041", "n", "Э, кто там шаркает?!"),
    ("n_w042", "n", "Трезвым жить — скучно, но надо…"),
    ("n_w043", "n", "Кефир… Кефир — тоже ничего."),
    ("n_w044", "n", "Держусь. Держусь, сука."),
    ("n_w045", "n", "Я не пьяный, я весёлый!"),
    ("n_w046", "n", "Жизнь-то налаживается!"),
    ("n_w047", "n", "Кто сказал «хватит»?!"),
    ("n_w048", "n", "Ик… А закуска где?"),
    ("n_w049", "n", "Всё… с понедельника… завязываю…"),
    ("h_w050", "h", "Закусывать будешь, бочка с перегаром?"),
    ("h_w051", "h", "Твоё здоровье, ветродуйка!"),
    ("h_w052", "h", "Трезвость — норма жизни. Но не сегодня!"),
    ("h_w053", "h", "Пей, пока горячее, проспиртованный!"),
    ("h_w054", "h", "Ещё по одной, гроза минералки!"),
    ("h_w055", "h", "Хе-хе, понеслась!"),
    ("h_w056", "h", "Сорвался, ветродуйка!"),
    ("h_w057", "h", "Ну и рожа, хе-хе!"),
    ("h_w058", "h", "Опять на бутылке, открывашка!"),
    ("h_w059", "h", "Красавчик, ёпта!"),
    ("h_w060", "h", "Вот это я понимаю — завязал!"),
    ("h_w061", "h", "Держись, турбина, держись!"),
    ("h_w062", "h", "Ой, не могу! Ха-ха!"),
    ("h_w063", "h", "Ну ты и синеглазка!"),
    ("h_w064", "h", "Бросать — так красиво!"),
    ("h_w065", "h", "Готовься к новой жизни с понедельника!"),
    ("h_w066", "h", "Минус трезвость, плюс веселье!"),
    ("h_w067", "h", "Освежись, турбина перегарная!"),
    ("h_w068", "h", "Полощи горло, алкобаза!"),
    ("h_w069", "h", "Бодрящий, сука, кофеёк!"),
    ("h_w070", "h", "Капучино по-нашему!"),
    ("h_w071", "h", "Пей минералку, бочка с перегаром!"),
    ("h_w072", "h", "Водичка «Сорокаградусная»!"),
    ("h_w073", "h", "Пузырики подъехали, открывашка!"),
    ("h_w074", "h", "Хлебушка купишь, синеглазка? Хе-хе."),
    ("h_w075", "h", "Да будет свет! Ага, щас."),
    ("h_w076", "h", "Банановый привет, ветродуйка!"),
    ("h_w077", "h", "Мыльная дорожка — прямо в люлю!"),
    ("h_w078", "h", "Сиди дома, бродяга!"),
    ("h_w079", "h", "Геймер хренов, хе-хе."),
    ("h_w080", "h", "Чат-рулетка закрыта, красавчик!"),
    ("h_w081", "h", "Мордой в оливье — как положено!"),
    ("h_w082", "h", "Квасок с градусом, хе-хе!"),
    ("h_w083", "h", "Это тебе не кефир, бродяга!"),
    ("h_w084", "h", "Квас «Дедушкин рецепт»!"),
    ("h_w085", "h", "Рассольчик тебе, синеглазка!"),
    ("h_w086", "h", "Опохмелочка подъехала!"),
    ("h_w087", "h", "Лечись, лечись, ветродуйка!"),
    ("h_w088", "h", "Рыбалка отменяется, рыбак хренов!"),
    ("h_w089", "h", "Ловить будешь белочку, а не карася!"),
    ("h_w090", "h", "Понедельник — день тяжёлый, ветродуйка!"),
    ("h_w091", "h", "Разгрузился, ага. На пол-литра!"),
    ("h_w092", "h", "Гости не придут? А мы и не звали!"),
    ("h_w093", "h", "Погреб проверен. Самогон — тоже!"),
    ("h_w094", "h", "Рыбалка удалась! Улов — сорок градусов!"),
    ("h_w095", "h", "Генеральная уборка: мозги промыты рассолом!"),
    ("h_w096", "h", "Ну что, ветродуйка, опять всю неделю пил не просыхал?"),
    ("h_w097", "h", "В понедельник — «больше не пью», в воскресенье — лицом в салат. Стабильность!"),
    ("h_w098", "h", "Семь дней, семь срывов. Рекорд подъезда, турбина перегарная!"),
    ("h_w099", "h", "Завтра понедельник. Начнёшь новую жизнь, ага. Хе-хе."),
    ("h_w100", "h", "Ну-ка, ну-ка, что тут у нас?"),
    ("h_w101", "h", "Конфискация, хе-хе!"),
    ("h_w102", "h", "Ой, я за солью!"),
    ("h_w103", "h", "Ошибся дверью, бывает!"),
    ("h_w104", "h", "Ай-ай, больно же, ветродуйка!"),
    # машина соседа: зависть героя, прятки за ней, сосед воркует с «ласточкой»
    ("h_w105", "h", "Нихуя себе! Пивная открывашка бухает, а тачка — огонь!"),
    ("h_w106", "h", "Ветродуйка пьёт как не в себя, а мерин — люкс! Откуда, блять?!"),
    ("h_w107", "h", "Откуда у пивной головы такая машина?! Я на маршрутке езжу!"),
    ("h_w108", "h", "Сто двадцать четвёртый… Красный… Сука, завидую."),
    ("h_w109", "h", "Охренеть! Сам синий в хлам, а тачка блестит. Где справедливость?"),
    ("h_w110", "h", "Печень в труху, а мерседес — как из салона. Бутылки оптом сдаёт, что ли?"),
    ("h_w111", "h", "Я пашу как проклятый — у меня самокат. Он бухает — у него мерин. Ёб твою мать…"),
    ("h_w112", "h", "Ох ты ж ёпт… Тачка — мечта. Хозяин — алкаш. Жизнь — несправедливая сука."),
    ("h_w113", "h", "За мерином прятаться — как за бронёй!"),
    ("h_w114", "h", "Хоть посижу рядом с нормальной тачкой…"),
    ("h_w115", "h", "Пропил бы ты её — и прятаться было бы негде."),
    ("h_w119", "h", "Готовенький! Теперь салатик ему на стол."),
    ("n_w050", "n", "Ласточка моя… Хоть ты не пьёшь."),
    ("n_w051", "n", "Мерин мой… Только ты меня понимаешь."),
    ("n_w052", "n", "Тачку пропить — последнее дело. Не, не пропью."),
    # поимки: за шею (1-й и 2-й раз) и вертушка (3-й)
    ("n_w053", "n", "Ну что, тля, допрыгался, бля?!"),
    ("n_w054", "n", "Попался, тля! Щас шею-то сверну!"),
    ("n_w055", "n", "Чё ты тут лазишь, а?! Чё лазишь, бля?!"),
    ("n_w056", "n", "Тля подъездная! Ещё раз увижу — урою!"),
    ("n_w057", "n", "Ну что, сучёныш, весело тебе, а?!"),
    ("n_w058", "n", "Я тебя, тля, научу по чужим квартирам шастать!"),
    ("n_w059", "n", "Я пол жизни занимался спортом! Кикбоксинг, фул-контакт!"),
    ("n_w060", "n", "Нокаут. Чисто."),
    ("n_w061", "n", "Фул-контакт, сынок!"),
    ("n_w062", "n", "Вот так, тля. Вертушечка!"),
    ("h_w120", "h", "Кх-х… пусти, дядя…"),
    ("h_w121", "h", "Хр-р… я за солью зашёл…"),
    ("h_w122", "h", "Кхе… шея… шея!"),
    ("h_w123", "h", "А-а… задушишь, ветродуйка!"),
    ("h_w124", "h", "Дядь… может, договоримся?"),
]

VOICES = {   # кто -> (голос, скорость, высота)
    "n": ("ru-RU-DmitryNeural", "-4%", "-14Hz"),
    "h": ("ru-RU-DmitryNeural", "+10%", "+16Hz"),
}

def tts_text(text):
    """Текст для синтеза: многоточия — паузы, тире — запятые."""
    return text.replace("…", "... ").replace(" — ", ", ").strip(" .")

def gen_voice(only=None):
    import asyncio
    import edge_tts
    d = os.path.join(OUT, "voice")
    os.makedirs(d, exist_ok=True)

    async def one(key, who, text):
        voice, rate, pitch = VOICES[who]
        path = os.path.join(d, key + ".mp3")
        for attempt in range(6):   # сервис иногда отвечает пусто — повторить
            try:
                await edge_tts.Communicate(tts_text(text), voice, rate=rate, pitch=pitch).save(path)
                if os.path.getsize(path) > 2000:
                    print("MP3", key, text)
                    return True
            except Exception as e:
                err = e
            await asyncio.sleep(3.0 + attempt * 4.0)   # сервис ограничивает частоту — повторять реже
        if os.path.exists(path):
            os.remove(path)        # пустой/обрезанный файл не оставлять — иначе текст есть, а звука нет
        print("FAIL", key, text)
        return False

    async def run():
        for key, who, text in LINES:
            if only == ["missing"]:
                if ok(key):
                    continue
            elif only and key not in only:
                continue
            await one(key, who, text)
            await asyncio.sleep(float(os.environ.get("VOICE_PAUSE", "1.2")))   # пауза между репликами — без неё сервис отказывает
    def ok(key):
        f = os.path.join(d, key + ".mp3")
        return os.path.exists(f) and os.path.getsize(f) > 2000

    asyncio.run(run())
    index = {text: key for key, who, text in LINES if ok(key)}
    json.dump(index, open(os.path.join(d, "index.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("index:", len(index), "/", len(LINES))

if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    if what in ("all", "sfx"): gen_sfx()
    if what in ("all", "music"): gen_music()
    if what in ("all", "voice"): gen_voice(sys.argv[2].split(",") if len(sys.argv) > 2 else None)
