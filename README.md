# MicGuard

Menu bar утилита для macOS: держит default audio input на нужном микрофоне и не даёт Bluetooth-наушникам самовольно стать входом.

## Проблема

Когда Bluetooth-наушники (AirPods, Sony WH и т.п.) становятся default input, macOS переключает их с профиля A2DP (полный битрейт, стерео) на HFP/HSP (моно, низкий битрейт) — и звук в самих наушниках становится хуже, даже если микрофон вообще не нужен. macOS сама может выбрать Bluetooth-устройство как вход при подключении, и штатного способа навсегда это заблокировать в системных настройках нет.

## Как работает

- Фоновый процесс слушает CoreAudio-события (`kAudioHardwarePropertyDefaultInputDevice`, `kAudioHardwarePropertyDevices`) — реагирует на любую смену устройств или дефолтного входа.
- При каждом событии строится список всех доступных input-устройств и сверяется с сохранённым порядком приоритета.
- **Приоритет хранится по persistent device UID**, а не по CoreAudio `AudioDeviceID` — тот выдаётся заново при каждом переподключении, UID переживает переподключение и перезагрузку.
- Новые (ранее не виденные) устройства уходят в конец списка приоритета автоматически.
- Правило простое: **всегда держать топ-1 устройство из приоритетного списка как default input**. Переключился вручную в системных настройках на что-то с более низким рангом — тул тут же вернёт обратно.
- Тумблер «Блокировать Bluetooth-микрофон» (включён по умолчанию) убирает все Bluetooth-устройства из кандидатов, независимо от их ранга в списке. Выключил тумблер — Bluetooth снова участвует по своему рангу.
- Никаких прав на запись/чтение микрофона (TCC-разрешение) утилите не нужно — она только переключает default input, не пишет звук.

## Требования

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`) — для `swiftc`

## Сборка и запуск

```bash
git clone git@github.com:IvanSSpace/mic-guard.git
cd mic-guard
./build.sh
```

`build.sh` компилирует бинарник, собирает `.app`-бандл, ad-hoc подписывает (`codesign --sign -`, чтобы Gatekeeper не ругался при каждом запуске) и копирует готовое приложение в `/Applications/MicGuard.app`.

Запустить:

```bash
open /Applications/MicGuard.app
```

Или через Spotlight (`Cmd+Space` → `MicGuard`) / Launchpad.

Иконка появится в menu bar (без иконки в Dock — это background-утилита, `LSUIElement`).

## Использование

Клик по иконке в menu bar открывает панель:

- **Текущий вход** — какое устройство активно сейчас
- **Блокировать Bluetooth-микрофон** — тумблер, вкл/выкл по необходимости
- **Приоритет входов** — список всех обнаруженных микрофонов, кнопки ↑/↓ у каждой строки меняют ранг. Заблокированные Bluetooth-устройства показаны зачёркнутыми с иконкой замка, но сохраняют позицию в списке — разблокируешь тумблер, и если Bluetooth-устройство топ-1 по рангу, оно тут же станет входом само.
- **Выйти** — останавливает процесс

## Автозапуск при логине

```bash
mkdir -p ~/Library/Logs
cp com.user.micguard.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.micguard.plist
```

Отключить автозапуск:

```bash
launchctl bootout gui/$(id -u)/com.user.micguard
rm ~/Library/LaunchAgents/com.user.micguard.plist
```

## Структура

```
Sources/MicGuard/
  main.swift          — menu bar UI (SwiftUI, MenuBarExtra)
  AudioMonitor.swift   — CoreAudio listener + policy engine
  PriorityStore.swift  — хранение порядка приоритета (по device UID)
  LockState.swift      — состояние тумблера блокировки Bluetooth
Info.plist              — бандл-метаданные (LSUIElement)
build.sh                — сборка + установка в /Applications
com.user.micguard.plist — LaunchAgent для автозапуска
```
