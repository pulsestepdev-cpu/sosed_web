# Сосед на бутылке — правила работы

## Общение
- Отвечать пользователю **только по-русски**.

## Git
- **Коммитить и пушить самостоятельно**, без вопросов и подтверждений, после каждого заметного шага.
- Пушить в `origin main` → https://github.com/pulsestepdev-cpu/sosed_web
- Не ждать пользователя, если пуш долгий: запустить в фоне и продолжать работу.
- В репозиторий не попадают: `.mcp.json`, `.claude/`, `screenshots/`, `assets/raw/ref/` (фото реальных людей).

## Godot
- Движок: `C:\Users\belya\Desktop\projects\Godot\Godot.exe` (4.7.2). Godot MCP подключён через `.mcp.json`.
- Скриншоты для проверки: `Godot.exe --path . -- --shot=screenshots/x.png --shot-delay=1.5 [--shot-scene=res://...]`, потом открыть PNG. F12 в игре — `screenshots/last.png`.
- Главная сцена: `scenes/level1.tscn` (`scripts/game/level.gd`). Отладочные аргументы описаны в шапке `level.gd`.
- Вырезка картинок с однотонным фоном (зелёный #00FF00 или пурпурный #FF00FF):
  `Godot.exe --headless --path . --script res://tools/chroma_key.gd -- <вход.png> <папка> <префикс> [имена,через,запятую]`

## Документы
- План: `docs/PLAN.md`, дизайн уровня 1: `docs/LEVEL1_DESIGN.md`, промпты графики: `docs/PROMPTS.md`, персонаж: `docs/CHARACTER.md`.
- Стиль: механики жанра «пакости соседу» — да; копировать персонажей, графику и интерфейс конкретной существующей игры — нет.
