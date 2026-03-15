# FreeMusic Player for iOS

🎵 **Свободный музыкальный плеер без регистрации и подписок**

![Platform](https://img.shields.io/badge/platform-iOS%2016.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## 📱 Скриншоты

<div align="center">
  <img src="screenshots/home.png" width="200" alt="Главная"/>
  <img src="screenshots/library.png" width="200" alt="Медиатека"/>
  <img src="screenshots/player.png" width="200" alt="Плеер"/>
  <img src="screenshots/settings.png" width="200" alt="Настройки"/>
</div>

## ✨ Особенности

- 🔓 **Без регистрации** - начните использовать сразу
- 💾 **Локальное хранение** - все данные на устройстве
- 🎨 **Современный дизайн** - тёмная тема, красные акценты
- 🎵 **Поддержка форматов** - MP3, FLAC, WAV, M4A, OGG
-  **Файловый менеджер** - импорт через Files.app
- 🎧 **Фоновое воспроизведение** - слушайте в других приложениях
- ⚡ **Быстрый и лёгкий** - никаких задержек

## 🚀 Функции

### Главная
- Моя волна (случайное воспроизведение)
- Плейлисты карточками
- Популярное
- Недавние треки

### Медиатека
- Все треки списком
- Фильтры (Все, Любимые, Офлайн, Плейлисты)
- Поиск по библиотеке
- Избранное

### Плеер
- Прогресс-бар с перемоткой
- Shuffle / Repeat
- Скорость воспроизведения
- Мини-плеер

### Настройки
- Хранилище
- Интеграции (Last.fm, Прокси)
- Сервисы (YouTube, SoundCloud, Spotify)
- Очистка кеша

## 📦 Установка

### Через GitHub Actions (рекомендуется)

1. **Скачайте IPA** из [Releases](../../releases) или из артефактов сборки

2. **Установите через Sideloadly** или AltStore:
   ```bash
   # Sideloadly (GUI)
   # 1. Откройте Sideloadly
   # 2. Перетащите IPA файл
   # 3. Введите Apple ID
   # 4. Нажмите Start
   ```

3. **Доверяйте сертификату** в Настройки → Основные → VPN и управление устройством

### Компиляция из исходников

```bash
# Клонируйте репозиторий
git clone https://github.com/collotype/FreeMusicPlayer-iOS.git
cd FreeMusicPlayer-iOS

# Откройте в Xcode
open FreeMusicPlayer.xcodeproj

# Соберите (Cmd+B) и запустите (Cmd+R)
```

## 🔧 Компиляция IPA через GitHub Actions

1. **Fork** этого репозитория

2. **Включите GitHub Actions** в настройках репозитория

3. **Запустите workflow**:
   - Перейдите в Actions → Build Unsigned IPA → Run workflow

4. **Скачайте артефакт**:
   - После завершения скачайте `FreeMusicPlayer-ipa.zip`

## 📁 Структура проекта

```
FreeMusicPlayer-iOS/
├── .github/workflows/
│   └── build.yml              # GitHub Actions для сборки IPA
├── FreeMusicPlayer.xcodeproj/
│   └── project.pbxproj        # Xcode проект
├── FreeMusicPlayer/
│   ├── FreeMusicPlayerApp.swift   # Точка входа
│   ├── ContentView.swift          # Главный экран
│   ├── HomeView.swift             # Главная страница
│   ├── LibraryView.swift          # Медиатека
│   ├── PlayerView.swift           # Полный плеер
│   ├── MiniPlayer.swift           # Мини-плеер
│   ├── SearchView.swift           # Поиск
│   ├── SettingsView.swift         # Настройки
│   ├── AudioPlayer.swift          # Аудио движок
│   ├── Track.swift                # Модель трека
│   ├── DataManager.swift          # Управление данными
│   └── Info.plist                 # Конфигурация
├── Assets.xcassets/               # Ресурсы
├── ExportOptions.plist            # Настройки экспорта
└── README.md
```

## 🎯 Отличия от React версии

| Функция | React (Web) | iOS (Swift) |
|---------|-------------|-------------|
| Платформа | Веб-браузер | Нативное iOS |
| Язык | JavaScript/React | Swift/SwiftUI |
| Хранение | LocalStorage | UserDefaults + Files |
| Аудио | HTML5 Audio | AVFoundation |
| UI | CSS | SwiftUI |
| Компиляция | npm/Vite | Xcode/GitHub Actions |
| Установка | Открыть URL | IPA через Sideloadly |

## 🔮 Планы

- [ ] Интеграция с YouTube Music API
- [ ] Интеграция со SoundCloud
- [ ] Тексты песен
- [ ] Эквалайзер
- [ ] Темы оформления (светлая/тёмная)
- [ ] Виджеты на главный экран
- [ ] CarPlay поддержка
- [ ] AirPlay 2

## 🛠 Технологии

- **Swift 5.9+**
- **SwiftUI** - UI фреймворк
- **AVFoundation** - воспроизведение аудио
- **UserDefaults** - хранение настроек
- **FileManager** - работа с файлами
- **UniformTypeIdentifiers** - импорт файлов

## 📄 Лицензия

MIT - Используйте как угодно

## 👨‍💻 Автор

**collotype**

Создано на основе анализа Dotify v1.1.0

---

**⚠️ Важно:** Это приложение для воспроизведения локальных файлов. Для стриминга требуется настройка внешних API.
