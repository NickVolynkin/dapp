---
title: Первое приложение на dapp (shell)
sidebar: how_to
permalink: get_started.html
---

@todo: переписать эту главу


## Шаги сборки для приложения

Для начала разберём, что нужно выполнить для сборки образа php приложения, например demo приложения symfony, по списку шагов из предыдущей главы.

- установить системное ПО и системные зависимости

Нужно установить php, например, 7-ой версии. Понадобятся расширения php7.0-sqlite3 (для приложения) php7.0-xml php7.0-zip (для composer).

- настроить системное ПО

Для работы веб-сервера нужен пользователь. Это будет пользователь phpapp.

- установить прикладные зависимости

Для установки зависимостей проекта нужен composer. Его можно установить скачиванием phar файла, поэтому в системное ПО добавится curl.

- добавить код

Код будет располагаться в финальном образе в директории /demo. Всем файлам проекта нужно установить владельцем пользователя phpapp.

- настроить приложение

Никаких особых настроек производить не нужно. Единственной настройкой будет ip адрес, на котором  слушает веб-сервер, но эта настройка будет в скрипте /opt/start.sh, который будет запускаться при старте контейнера.

В качестве иллюстрации для стадии setup добавится создание файла version.txt с текущей датой.

## Сборка и запуск

Для запуска этого Dappfile нужно склонировать репозиторий с приложением и создать в корне репозитория Dаppfile.

```
git clone https://github.com/symfony/symfony-demo.git
cd symfony-demo
vi Dappfile
```

Далее нужно собрать образ приложения можно командой

```
dapp dimg build
```

А запустить командой

```
dapp dimg run -d -p 8000:8000 -- /opt/start.sh
```

После чего проверить браузером или в консоли

```
curl host_ip:8000
```


## Что не так?

* Набор команд echo для создания файла start.sh вполне заменим на ещё одну директиву git и хранение файла в репозитории.
* Если директивой git можно копировать файлы, то почему бы в этой директиве не указать права на эти файлы?
* composer install требуется не каждый раз, а только при изменении файла package.json, поэтому было бы отлично, если эта команда запускалась только при изменении этого файла.

Эти проблемы будут разобраны в следующей главе [Поддержка git](git_for_build.html)