# Звуки и озвучка уровня 1 — генерируются кодом (чистый Python, без библиотек) + голос Windows (SAPI, ru-RU).
#   python tools/gen_audio.py            — всё
#   python tools/gen_audio.py sfx|voice|music
# Результат: assets/audio/sfx/*.wav, assets/audio/voice/*.wav + voice/index.json (текст → файл), assets/audio/music/*.wav
# Голос: русский синтезатор, затем понижение тона (сосед — грубее и ниже, герой — чуть ниже).
import json, math, os, random, struct, subprocess, sys, tempfile, wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
SR = 22050
random.seed(7)

def save(path, samples, sr=SR):
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
    save(os.path.join(d, "snore.wav"), snore())
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
    ("n_coffee", "n", "Чё-то кофе сегодня крепкий…"),
    ("n_fridge2", "n", "Ну раз уж открыл…"),
    ("n_soda", "n", "Хм. А газировка-то с пеной…"),
    ("n_jacket", "n", "…Это знак."),
    ("n_gamepad", "n", "Где геймпад?!"),
    ("n_phone", "n", "Где телефон?!"),
    ("n_keys", "n", "Где ключи?! …Ну раз дома — можно."),
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
    ("n_bulb", "n", "Опять перегорела?"),
    ("n_mineral", "n", "Минералочка… Успокоился."),
    ("n_more1", "n", "Ну ещё по одной…"),
    ("n_more2", "n", "За ремонт!"),
    ("n_more3", "n", "Последняя. Точно."),
    ("n_grumble1", "n", "Бу-бу-бу… никто не ценит…"),
    ("n_grumble2", "n", "Так-с… шпаклёвочка…"),
    ("n_grumble3", "n", "Эх, жизнь…"),
    ("n_grumble4", "n", "Хм-м… Ну и ладно."),
    ("n_ouch", "n", "Ой-ё-ёй… Спина моя…"),
    ("n_slip", "n", "Твою ж… Кто мыло бросил?!"),
    ("n_salad", "n", "Салатик… моя подушечка…"),
    ("h_taunt1", "h", "Пивная открывашка!"),
    ("h_taunt2", "h", "Ветродуйка!"),
    ("h_taunt3", "h", "Турбина перегарная!"),
    ("h_taunt4", "h", "Пей до дна, открывашка!"),
    ("h_taunt5", "h", "Давай-давай, ветродуйка!"),
    ("h_taunt6", "h", "Спи, турбина перегарная."),
    ("h_found", "h", "Опа, заначка!"),
    ("h_heh", "h", "Хе-хе-хе…"),
    ("h_oops", "h", "Ой-ой-ой!"),
    ("h_shh", "h", "Тс-с-с…"),
    ("h_ouch", "h", "Ай! Да за что?!"),
    ("h_win", "h", "Готов, голубчик!"),
]

PS = r'''
Add-Type -AssemblyName System.Speech
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$s.SelectVoice("Microsoft Irina Desktop")
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
foreach ($line in Get-Content -Encoding UTF8 $args[0]) {
  $p = $line.Split("`t")
  $s.SetOutputToWaveFile($p[0], $fmt)
  $s.Rate = [int]$p[2]
  $s.Speak($p[1])
}
$s.SetOutputToNull()
'''

def read_wav(path):
    with wave.open(path, "rb") as w:
        n = w.getnframes(); raw = w.readframes(n)
    return [v / 32768 for v in struct.unpack("<%dh" % n, raw)]

def pitch_down(x, k):
    """Тон ниже в 1/k раз (k<1): растянуть отсчёты (замедление), а речь заранее синтезирована быстрее."""
    out, i = [], 0.0
    while i < len(x) - 1:
        a = int(i); f = i - a
        out.append(x[a] * (1 - f) + x[a + 1] * f)
        i += k
    return out

def gruff(x, amount):
    """Хрипотца: лёгкий перегруз + немного шума по огибающей."""
    out, e = [], 0.0
    for v in x:
        e = max(abs(v), e * 0.995)
        y = math.tanh(v * (1 + amount * 4)) / math.tanh(1 + amount * 4)
        out.append(y + random.uniform(-1, 1) * e * amount * 0.15)
    return out

def trim(x, thr=0.01):
    a = next((i for i, v in enumerate(x) if abs(v) > thr), 0)
    b = len(x) - next((i for i, v in enumerate(reversed(x)) if abs(v) > thr), 0)
    return x[max(0, a - 300):min(len(x), b + 1500)]

def gen_voice():
    d = os.path.join(OUT, "voice")
    os.makedirs(d, exist_ok=True)
    tmp = tempfile.mkdtemp()
    tsv = os.path.join(tmp, "lines.tsv")
    with open(tsv, "w", encoding="utf-8") as f:
        for key, who, text in LINES:
            rate = 4 if who == "n" else 3
            f.write("%s\t%s\t%d\n" % (os.path.join(tmp, key + ".wav"), text.replace("…", ", "), rate))
    ps1 = os.path.join(tmp, "say.ps1")
    open(ps1, "w", encoding="utf-8-sig").write(PS)
    subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps1, tsv], check=True)
    index = {}
    for key, who, text in LINES:
        x = trim(read_wav(os.path.join(tmp, key + ".wav")))
        if who == "n":
            x = gruff(pitch_down(x, 0.66), 0.35)
        else:
            x = gruff(pitch_down(x, 0.78), 0.12)
        save(os.path.join(d, key + ".wav"), x)
        index[text] = key
    json.dump(index, open(os.path.join(d, "index.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)

if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    if what in ("all", "sfx"): gen_sfx()
    if what in ("all", "music"): gen_music()
    if what in ("all", "voice"): gen_voice()
