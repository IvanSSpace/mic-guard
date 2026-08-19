# MicGuard

Menu bar утилита для macOS: держит default audio input на нужном микрофоне, не даёт Bluetooth-наушникам самовольно стать входом (из-за этого проседает качество звука — переключение на HFP-профиль).

## Как работает

- Слушает CoreAudio-события смены устройств/входа, сверяет с сохранённым приоритетом (по persistent device UID, переживает переподключение).
- Всегда держит топ-1 **физический** микрофон (builtIn/USB/Bluetooth) как default input — переключился вручную на что-то ниже рангом, тул вернёт обратно.
- Виртуальные устройства (Loopback, Screaming Bee, Zoom и т.п.) в выборе не участвуют вообще — если такое выбрано руками (ради роутинга), тул не трогает.
- Тумблер «Блокировать Bluetooth» исключает Bluetooth из кандидатов независимо от ранга.
- Чекбокс у устройства — временно исключить его без физического отключения.
- Разрешений на микрофон не требует — только переключает default input.

## Сборка и запуск

```bash
git clone git@github.com:IvanSSpace/mic-guard.git
cd mic-guard
./build.sh
open /Applications/MicGuard.app
```

Требует Xcode Command Line Tools (`xcode-select --install`). `build.sh` собирает `.app`, подписывает ad-hoc и ставит в `/Applications`. Дальше — через Spotlight (`Cmd+Space` → MicGuard).

## Использование

Клик по иконке в menu bar → панель: текущий вход, тумблер блокировки Bluetooth, список устройств с чекбоксом (вкл/выкл) и стрелками ↑/↓ (приоритет). Отключённые физически устройства остаются в списке серым — вернутся сами при подключении.

## Автозапуск при логине

```bash
cp com.user.micguard.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.micguard.plist
```

Отключить: `launchctl bootout gui/$(id -u)/com.user.micguard`
