# Сосед на бутылке — правила работы

## Общение
- Отвечать пользователю **только по-русски**.

## Git
- **Коммитить и пушить самостоятельно**, без вопросов и подтверждений, после каждого заметного шага.
- Пушить в `origin main` → https://github.com/pulsestepdev-cpu/sosed_web
- Не ждать пользователя, если пуш долгий: запустить в фоне и продолжать работу.
- В репозиторий не попадают: `.mcp.json`, `.claude/` (кроме `.claude/agents/`, `.claude/commands/`, `.claude/settings.json`),
  `screenshots/`, `build/`, `assets/raw/ref/` (фото реальных людей).

## Godot
- Движок: `C:\Users\belya\Desktop\projects\Godot\Godot.exe` (4.7.2). Godot MCP подключён через `.mcp.json`.
- Скриншоты для проверки: `Godot.exe --path . -- --shot=screenshots/x.png --shot-delay=1.5 [--shot-scene=res://...]`, потом открыть PNG. F12 в игре — `screenshots/last.png`.
- Стартовая сцена: `scenes/main_menu.tscn` (обложка `assets/ui/menu_bg.jpg`, `scripts/ui/`). Игра: `scenes/game.tscn` →
  `scripts/game3d/game.gd` (3D-квартира `scenes/level1_3d.tscn`, правила `rules3d.gd`, сосед `neighbor3d.gd`, герой `hero3d.gd`).
  Отладочные аргументы — в шапке `game.gd` (`--autostart --start=11.2 --log --use=... --click=x:y:сек --finale --hide=sofa`).
  Автопрогон без окна: `Godot.exe --headless --path . res://scenes/game.tscn -- --autostart --log --speed=6 --use=...`
- Старый 2D-прототип: `scenes/level1.tscn` (`scripts/game/`), больше не основной.
- Звук и озвучка: `python tools/gen_audio.py [sfx|voice|music]` → `assets/audio/`. Голос — нейросинтез Microsoft Edge
  (`pip install edge-tts`, нужен интернет; ru-RU-DmitryNeural, сосед ниже, герой выше) → `voice/*.mp3`; `voice ключ1,ключ2` —
  перезаписать только эти. Реплика озвучивается, если её текст есть в `assets/audio/voice/index.json`; новую реплику добавить
  в `LINES` в gen_audio.py. После новых файлов — `Godot.exe --headless --path . --import`. Громкость — автозагрузка `Settings`.
- Музыка: `assets/audio/music/main_musik.mp3` — песня автора, в меню и в игре (`Settings.TRACKS`: старт с 15.8 с, −7 дБ).
- Вырезка картинок с однотонным фоном (зелёный #00FF00 или пурпурный #FF00FF):
  `Godot.exe --headless --path . --script res://tools/chroma_key.gd -- <вход.png> <папка> <префикс> [имена,через,запятую]`

## Веб-версия
- Пресет экспорта «Web» (`export_presets.cfg`): без потоков и PWA, в сборку — сцены меню/игры + `scripts/*`, `assets/textures/*`,
  звук, модели, иконки (всё, что грузится по имени в коде, добавлять в `include_filter`). `assets/raw` не попадает.
- Локально: `Godot.exe --headless --path . --export-release "Web" build/web/index.html`, затем
  `python -m http.server 8060` в `build/web` → http://127.0.0.1:8060. Шаблоны: `python tools/fetch_web_templates.py
  "%APPDATA%/Godot/export_templates/4.7.2.stable"`.
- Две веб-сборки: «Web» (многопоточная, корень) и «Web-compat» (`compat/`, для Safari/iPhone/iPad); выбор — в `web/shell.html`
  (там же страница загрузки: прогресс, проверка WebGL 2, ошибки по-русски). Многопоточной нужны заголовки COOP/COEP (`deploy/nginx.conf`).
- Текстуры — WebP с потерями (качество 0.8): новые картинки импортировать так же (`compress/mode=1` в `.import`).
- Графика: `Settings.quality` auto/high/low (`apply_quality()` в game.gd; авто — по FPS первых секунд игры).
- Телефон/планшет (`Settings.is_touch()`; на ПК — отладочный `--touch`): интерфейс крупнее (`content_scale_factor`), экранные кнопки
  (`Hud3D._build_touch_bar`), тап — на отпускании, перетаскивание — обзор, щипок — приближение (`_input`/`_touch_input` в game.gd),
  раскладка HUD считается от размера экрана (`Hud3D._layout`). Вертикально — экран «поверни телефон» в `web/shell.html`.
- В вебе нет системных шрифтов: в текстах только кириллица/латиница и « » — … · • (стрелки, эмодзи — квадратики).
- Выкладка: push в `main` → GitHub Actions (`.github/workflows/web.yml`) собирает и деплоит в CapRover (`deploy/`: Dockerfile
  с nginx, gzip, no-cache). Секреты репозитория: `CAPROVER_SERVER` и `CAPROVER_APP_TOKEN` или `CAPROVER_PASSWORD` (пароль панели); переменная `CAPROVER_APP` (по умолч. sosed).

## Автотесты и агенты
- Бот-игрок `scripts/debug/qa_bot.gd` (`--bot=careful|normal|reckless`), отчёт `scripts/debug/qa_recorder.gd`
  (`--report=файл.json --quit-on-end --max-real=сек`, `--perf` — FPS в лог). В браузере те же параметры — в адресе: `?qa=1&bot=normal&perf=1`.
- Обёртки (`tools/qa/`, результаты в `screenshots/qa/`):
  `run_level.py` — прогоны ботом и сводка; `record.py --preset trap|finale|…` — запись кадров + листы раскадровки;
  `web_check.py` — браузеры/устройства, загрузка, ошибки, звук, FPS; `build_web.py [--serve]` — веб-сборка и сервер.
- Агенты `.claude/agents/`: level-runner (прохождение), balance (сложность), anim-review (анимация), perf-audio (FPS и звук),
  web-qa (веб), release (выкладка). Команда `/qa [all|quick|level|balance|anim|perf|web]` — проверка и сводный отчёт.
- Разрешения инструментов — `.claude/settings.json` (запрещены force-push, reset --hard, git clean).

## Blender
- `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe` (5.2.3 LTS). Управлять скриптами в фоне:
  `blender.exe -b [файл.blend] -P tools/blender/<скрипт>.py -- <аргументы>`
- Скрипты Blender лежат в `tools/blender/`. Пути в аргументах — Windows-формата (`pwd -W`).
- В Godot модели идут как `.glb` (`export_scene.gltf`, формат GLB) в `assets/models/`.
- Проверка, что Godot открывает модель и видит анимации:
  `Godot.exe --headless --path . --script res://tools/check_glb.gd -- res://assets/models/x.glb`
- Сам Blender можно отрендерить в PNG (EEVEE) и посмотреть картинку — так проверять модели до Godot.

## 3D-ассеты
- **Mixamo** и **Tripo 3D** для новых уровней НЕ используем: все модели и анимации — скриптами Blender, референсы — из интернета.

## Документы
- План: `docs/PLAN.md`, неделя (7 уровней): `docs/WEEK_PLAN.md`, дизайн уровня 1: `docs/LEVEL1_DESIGN.md`, промпты графики: `docs/PROMPTS.md`, персонаж: `docs/CHARACTER.md`.
- Стиль: механики жанра «пакости соседу» — да; копировать персонажей, графику и интерфейс конкретной существующей игры — нет.
