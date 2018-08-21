---
title: Adding source code with `git` directive
sidebar: reference
permalink: git.html
folder: directive
---

Для добавления кода в собираемый образ, предусмотрена директива `git`, с помощью которой можно добавить код из локального или удаленного репозитория (включая сабмодули) как в образ приложения так и в образ артефакта.

With `git` directive dapp can add source code from a Git repository to an image.
It supports both local and remote repositories, including submodules,
and can build both application and artifact images.

При первой сборке образа с указанием директивы `git`, в него добавляется содержимое git репозитория (стадия `g_a_archive`) согласно соответствующих инструкций. При последующих сборках образа, изменения в git репозитории добавляются отдельным docker-слоем, который содержит git-патч (git patch apply). Содержимое таких docker-слоев с патчами также кешируется, что еще более повышает скорость сборки. В случае отмены сделанных изменений в исходном коде приложения (например, через git revert), при сборке будет накладываться патч с отменой изменений, будет использоваться слой из кеша.

When dapp first builds an image from a dappfile with `git` directive, it adds source code from a Git repository to the image.
This happens on the `g_a_archive` stage.
On next builds dapp does not create new images with a full copies of source code.
Instead, it generates git patches (with `git patch apply`) and applies them as image layers.
Dapp caches these image layers to boost build speed.
If changes in source code are undone, for example with `git revert`, dapp detects that and reuses a cached layer.

## Building artifacts

Сборка образов артефактов отличается отсутствием стадии `latest_patch`, т.о. при первой сборке образа артефакта используются текущие состояния git-репозиториев и при последующих сборках образы артефактов не пересобираются (при условии, что отсутствуют зависимости пользовательских стадий от файлов, описанных с помощью директивы `stageDependencies`, о чем см. ниже).

Building artifacts is different from building applications: there is no `latest_patch` stage.
When dapp first builds an artifact image, it uses the current
On next builds the artifact images are not rebuilt.

An exception is when user stages are dependent on files, listed in `stageDependencies` directive.
This will be explained further in TODO.

Система кеширования dapp принимает решение о необходимости повторной сборки стадии или использовании кеша, на основании вычисления [сигнатуры стадии](stages_diagram.html), которая не зависит напрямую от состояния git репозитория. Т.о., если не указать это явно (см далее про директиву `stageDependencies`), то изменения только кода в git репозитории не приведут к повторной сборке пользовательской стадии (`before_install`, `install`, `before_setup`, `setup`, `build_artifact`). Чтобы явно определить зависимость от файлов и папок, при изменении которых сборщику необходимо выполнить принудительную сборку определенных пользовательских стадий, в директиве `git` предусмотрена директива `stageDependencies` (`stage_dependencies` для Ruby синтаксиса).

Правильная установка зависимостей - важное условие построения эффективного процесса сборки!

Количество указаний директивы `git` в описании образа не ограничено, но нужно стремиться к их уменьшению, путем правильного использования `includePaths` и `excludePaths`.

## Общие особенности использования

## General Features 

* пути добавления не должны пересекаться между артефактами;
* описание сборки образа (`dimg` или `artifact`) может содержать любое количество git-директив;
* изменение кода в git репозитории который используется при сборке **образа приложения**, накладывается патчем и не ведет к пересборке какой-либо пользовательской стадии (если нет явного указания зависимости через `stageDependencies`);
* изменение кода в git репозитории который используется при сборке **образа артефакта**, не ведет к пересборке образа артефакта и не накладывается патчем (если нет явного указания зависимости через `stageDependencies`);
* для пересборки пользовательской стадии в зависимости от изменений в git репозитории нужно описывать зависимости с использованием `stageDependencies`;
* поддерживается два типа git-директив, local и remote, для использования локального и удаленного репозитория соответственно;
* при использовании git submodule-й, логика не меняется - инструкции описываются так же, как в случае с директориями;
* для исключения избыточного копирования кода в образ, в директиве `git` предусмотрены параметры `includePaths` и `excludePaths`;
* важно помнить, что код добавленный с помощью директивы `git`, еще не доступен на пользовательской стадии `before install` (см. [подробней](/stages_arhitecture.html) про стадии сборки).

## YAML синтаксис (dappfile.yml)

В dappfile.yml директива `git` применяется следующим образом:
```
git:
- GIT_SPEC
...
- GIT_SPEC
```
, где `GIT_SPEC` - один или несколько массивов описаний директив добавления кода следующего вида:
- для работы с локальным репозиторием

```
as: <custom_name>
add: <add_absolute_path>
to: <to_absolute_path>
owner: <owner>
group: <group>
includePaths:
- <relative_path_or_mask>
excludePaths:
- <relative_path_or_mask>
stageDependencies:
  install:
  - <relative_path_or_mask>
  beforeSetup:
  - <relative_path_or_mask>
  setup:
  - <relative_path_or_mask>
```
- для работы с удаленным репозиторием

```
url: <git_repo_url>
branch: <branch_name>
commit: <commit>
as: <custom_name>
add: <add_absolute_path>
to: <to_absolute_path>
owner: <owner>
group: <group>
includePaths:
- <relative_path_or_mask>
excludePaths:
- <relative_path_or_mask>
stageDependencies:
  install:
  - <relative_path_or_mask>
  beforeSetup:
  - <relative_path_or_mask>
  setup:
  - <relative_path_or_mask>
  build_artifact:
  - <relative_path_or_mask>
```

Описание директив:
* `url: <git_repo_url>` - определяет внешний git репозиторий, где `<git_repo_url>` - ssh или https адрес репозитория (в случае использования ssh адреса, ключ `--ssh-key` dapp позволяет указать ssh-ключ для доступа к репозиторию).
* `branch: <branch_name>` - определяет используемую ветку внешнего git репозитория, необязательный параметр (по умолчанию - master).
* `commit: <commit>` - определяет используемый коммит внешнего git репозитория, необязательный параметр.
* `as: <custom_name>` - назначает данному описанию git артефакта имя. Используется, например, в helm шаблонах для получения и передачи через переменные окружения в образ id коммита (обратиться можно через `.Values.global.dapp.dimg.DIMG_NAME.git.CUSTOM_NAME.commit_id` для именованного образа и `.Values.global.dapp.dimg.git.CUSTOM_NAME.commit_id` для безымянного образа).
* `add: <add_absolute_path>` - определяет путь - источник репозитория, где `<add_absolute_path>` - путь относительно репозитория, из которого будут копироваться ресурсы.
* `to: <to_absolute_path>` -  определяет путь назначения, при копировании файлов из репозитория, где `<to_absolute_path>` - абсолютный путь, в который будут копироваться ресурсы.
* `owner: <owner>` - определяет пользователя владельца, который будет установлен ресурсам после их копирования.
* `group: <group` - определяет группу владельца, которая будет установлена ресурсам после их копирования.
* `include_paths: <relative_path_or_mask>` - определяет относительные пути или маски ресурсов которые и только которые будут скопированы.
* `exclude_paths: <relative_path_or_mask>` - определяет относительные пути или маски ресурсов которые необходимо игнорировать при копировании.
* `stageDependencies: ` - определяет зависимость пользовательской стадии (`install`, `beforeSetup`, `setup` - для любого типа образов, `buildArtifact` - только для сборки образа артефактов) от файлов и папок, при изменении которых необходимо выполнить принудительную сборку пользовательской стадии. Файлы и папки определяются относительным путем или маской. Учитывается как содержимое так и имена файлов/папок.

Правила указания масок:
* поддерживаются glob-паттерны
* пути в <glob> указываются относительные
* директории игнорируются
* маски чувствительны к регистру.


### Примеры
#### Добавление кода удаленного репозитория

```
git:
- url: https://github.com/kr/beanstalkd.git
  add: /
  to: /build
```


#### Пример добавления одного файла из локального репозитория

Пример добавления файла `/folder/file` из локального репозитория в папку `/destfolder` собираемого образа, с определением зависимости пересборки пользовательской стадии setup при изменении файла `/folder/file` в репозитории:

```
git:
- add: /folder/file
  to: /destfolder
  includePaths:
  - file
  stageDependencies:
    setup:
    - file
```

#### Пример добавления нескольких папок и установки прав

Как в предыдущем примере, только добавляется вся папка `/folder`, и зависимость определяется на изменение любого файла в исходной папке.

```
git:
- add: /folder/
  to: /destfolder
  stageDependencies:
    setup:
    - "*"
```

#### Пример сборки приложения

Пример сборки приложения на nodeJS. Код приложения находится в корне локального репозитория.

```
dimg: testimage
from: node:9.11-alpine
git:
  - add: /
    to: /app
    stageDependencies:
      install:
        - package.json
        - bower.json
      beforeSetup:
        - app
        - gulpfile.js
shell:
  beforeInstall:
  - apk update
  - apk add git
  - npm install --global bower
  - npm install --global gulp
  install:
  - cd /app
  - npm install
  - bower install --allow-root
  beforeSetup:
  - cd /app
  - gulp build
docker:
  WORKDIR: "/app"
  CMD: ["gulp", "connect"]
```

## Ruby синтаксис (Dappfile)

Директива `git [<url>]` позволяет определить один или несколько git-директив.

* Поддерживается два типа git-директив, local и remote.
* Необязательный параметр \<url\> соответствует адресу удалённого git-репозитория (remote).
* Для добавления git-директивы необходимо использовать поддирективу add.
  * Принимает параметр \<cwd\> (по умолчанию используется '\\').
  * Параметры \<include_paths\>, \<exclude_paths\>, \<owner\>, \<group\>, \<to\> определяются в контексте.
  * Параметры \<branch\>, \<commit\> могут быть определены в контексте remote git-директивы.
* В контексте директивы можно указать базовые параметры git-директив, которые могут быть переопределены в контексте каждого из них.
  * \<owner\>.
  * \<group\>.
  * \<branch\>.
  * \<commit\>.


### Параметры артефакта

#### Общие
* to: абсолютный путь, в который будут копироваться ресурсы.
* cwd: абсолютный путь, определяет рабочую директорию.
* include_paths: добавить только указанные относительные пути.
* exclude_paths: игнорировать указанные относительные пути.
* owner: определить пользователя.
* group: определить группу.

#### Дополнительные для remote git-директив
* branch: определить branch.
* commit: определить commit.

#### Управление запуском сборки при изменении файлов

Директива `git.add.stage_dependencies` позволяет определить для пользовательской стадии `install`, `before_setup`, `setup` и `build_artifact` зависимости от файлов git-директивы.

* При изменении содержимого указанных файлов, произойдет пересборка зависимой стадии.
* Учитывается содержимое и имена файлов.
* Поддерживаются glob-паттерны.
* Пути в \<glob\> указываются относительно cwd git-директивы.
* Директории игнорируются.
* \<glob\> чувствителен к регистру.

### Примеры

#### Как собрать образ с несколькими git-директивами
```ruby
dimg do
  docker.from 'image:tag'

  git do
    add '/' do
      exclude_paths 'assets'
      to '/app'
    end

    add '/assets' do
      to '/web/site.narod.ru/assets_with_strange_name'
    end
  end

  git 'https://site.com/com/project.git' do
    owner 'user4'
    group 'stuff'

    add '/' do
      to '/project'
    end
  end
end
```

### Как определить зависимости для нескольких git-директив
```ruby
dimg do
  docker.from 'image:tag'

  git do
    add '/' do
      to '/app'

      stage_dependencies do
        install 'flag'
      end
    end

    add '/assets' do
      to '/web/site.narod.ru/assets_with_strange_name'
      stage_dependencies.setup '*.less'
    end
  end
end
```
