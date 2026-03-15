# 📤 Инструкция по загрузке на GitHub и компиляции

## Шаг 1: Создание репозитория на GitHub

1. Открой https://github.com/new
2. Введи имя репозитория: `FreeMusicPlayer-iOS`
3. Выбери **Public** или **Private**
4. **НЕ** ставь галочки на "Initialize with README"
5. Нажми **Create repository**

## Шаг 2: Инициализация Git и загрузка

Открой PowerShell в папке проекта (`C:\Users\Collotype\Desktop\FreeMusicPlayer-iOS`) и выполни:

```powershell
# Инициализация Git
git init

# Добавление всех файлов
git add .

# Первый коммит
git commit -m "Initial commit: FreeMusic Player iOS"

# Добавление удалённого репозитория (замени USERNAME на свой логин)
git remote add origin https://github.com/collotype/FreeMusicPlayer-iOS.git

# Переименование ветки в main
git branch -M main

# Отправка на GitHub
git push -u origin main
```

## Шаг 3: Включение GitHub Actions

1. Перейди в свой репозиторий на GitHub
2. Нажми **Actions** вверху
3. Если видишь предупреждение, нажми **I understand my workflows, go ahead and enable them**

## Шаг 4: Запуск сборки

### Автоматически (при пуше)
Сборка запустится автоматически при каждом `git push`

### Вручную
1. Перейди в **Actions** → **Build Unsigned IPA**
2. Нажми **Run workflow** (справа)
3. Выбери ветку `main`
4. Нажми **Run workflow**

## Шаг 5: Скачивание IPA

После завершения сборки (5-10 минут):

1. Перейди в **Actions** → нажми на последний запуск (с зелёной галочкой)
2. Прокрути вниз до раздела **Artifacts**
3. Нажми **FreeMusicPlayer-ipa**
4. Скачается ZIP архив с IPA файлом

## Шаг 6: Установка на iPhone

### Вариант A: Sideloadly (Windows)

1. Скачай Sideloadly: https://sideloadly.io/
2. Распакуй `FreeMusicPlayer-ipa.zip`
3. Открой Sideloadly
4. Перетащи `.ipa` файл в окно
5. Введи свой Apple ID
6. Нажми **Start**
7. На iPhone: Настройки → Основные → VPN и управление устройством → Доверяй своему Apple ID

### Вариант B: AltStore

1. Установи AltStore на компьютер и iPhone
2. Открой AltStore на компьютере
3. Нажми **+** в левом верхнем углу
4. Выбери `.ipa` файл
5. Приложение установится на iPhone

### Вариант C: Signulous / AppDB (платно, но без компьютера)

1. Купи подписку (~$5-10/год)
2. Загрузи IPA через их приложение
3. Установи с их сертификатом

## 🔧 Решение проблем

### Ошибка: "Code signing failed"
Это нормально! Мы собираем **без подписи**. IPA будет работать через Sideloadly/AltStore.

### Ошибка: "No provisioning profile"
Используем `CODE_SIGNING_REQUIRED=NO` в GitHub Actions - это правильно.

### Сборка упала с ошибкой
1. Проверь логи в GitHub Actions
2. Убедись что все Swift файлы на месте
3. Проверь синтаксис в Xcode (если есть Mac)

### IPA не устанавливается
1. Убедись что доверяешь сертификату на iPhone
2. Попробуй другой метод установки (Sideloadly → AltStore)
3. Пересобери с новым Apple ID

## 📱 Обновление приложения

Для обновления после изменений:

```powershell
# После изменений в коде
git add .
git commit -m "Описание изменений"
git push
```

GitHub Actions автоматически соберёт новую версию IPA!

## 🎨 Добавление иконок

1. Создай иконку 1024x1024 PNG
2. Положи в `Assets.xcassets/AppIcon.appiconset/`
3. Переименуй в `app-icon-1024.png`
4. Обнови `Contents.json`
5. Закоммить и запушь

## 🚀 Публикация в Releases

Для создания релиза:

```powershell
# Создай тег версии
git tag v1.0.0
git push origin v1.0.0
```

Затем на GitHub:
1. **Releases** → **Create a new release**
2. Выбери тег `v1.0.0`
3. Прикрепи IPA файл из артефактов
4. Нажми **Publish release**

---

**Готово!** 🎉 Твоё приложение доступно для установки!
