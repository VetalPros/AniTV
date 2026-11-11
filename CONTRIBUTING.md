# Как участвовать в разработке AniTV

Спасибо, что заглянули. Этот документ описывает рабочий процесс для людей и для AI-агентов:
он один и тот же для всех. Перед первым действием прочитайте [AGENTS.md](AGENTS.md) — там
жёсткие ограничения проекта и соглашения по коду, они важнее любых личных предпочтений.

## С чего начать

1. Прочитайте [AGENTS.md](AGENTS.md) целиком. Это точка входа, а не формальность: в §2 собраны
   ограничения, которые нельзя нарушать (секреты, сторонние зависимости, бесплатный аккаунт
   Apple Developer, вежливость к API).
2. Прочитайте [docs/PROJECT_MEMORY.md](docs/PROJECT_MEMORY.md) — там текущее состояние проекта,
   окружение и следующие шаги.
3. Пролистайте хвост [docs/DECISIONS.md](docs/DECISIONS.md). Решения из журнала не
   пересматриваются молча: если нужно иначе — добавьте новую запись ADR, объясняющую почему.
4. Если задача связана с сетью, посмотрите [docs/api-notes.md](docs/api-notes.md).

## Протокол памяти (обязателен)

Контекст не сохраняется между сессиями, поэтому состояние проекта ведётся явно и в git:

| Файл | Назначение | Когда обновлять |
| --- | --- | --- |
| `docs/PROJECT_MEMORY.md` | Живое состояние: что есть, окружение, следующие шаги, открытые вопросы | В каждой сессии, которая меняет состояние |
| `docs/DECISIONS.md` | Журнал архитектурных решений (ADR-lite), только дописывание | При каждом архитектурном выборе |
| `docs/api-notes.md` | Проверенные факты об HTTP API и воспроизведении HLS | Когда проверен новый эндпоинт или поведение |

Правила простые: изменение кода и обновление памяти едут одним коммитом; в память не попадают
секреты, токены, персональные данные и непроверенные догадки (непроверенное помечается
`unverified`).

## Как генерируется Xcode-проект

`AniTV.xcodeproj` — **артефакт**, а не источник истины. Источник истины — `project.yml`
(см. [ADR 0004](docs/DECISIONS.md)). Поэтому:

```bash
xcodegen generate
```

- **`.xcodeproj` не коммитится никогда.** Любое изменение настроек таргетов, схемы или
  deployment target делается в `project.yml`; правки в сгенерированном проекте потеряются при
  следующей генерации.
- **`App/Info.plist` не коммитится.** XcodeGen создаёт его из `info.path` и свойств в
  `project.yml`, то есть это тоже артефакт. Значения вроде `CFBundleShortVersionString`
  подставляются из build settings.
- `AniTV.xcodeproj` и `/App/Info.plist` перечислены в [.gitignore](.gitignore). Если вы видите их
  в `git status` — что-то не так с окружением, а не с проекта.

После изменения `project.yml` всегда проверяйте, что генерация и сборка проходят с нуля:

```bash
xcodegen generate
xcodebuild -project AniTV.xcodeproj -scheme AniTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (4th generation)' \
  -derivedDataPath .build/DerivedData build
```

## Перед Pull Request

Определение готовности одинаково для людей и агентов — все пять пунктов должны быть зелёными
(пятый, UI-тесты, требует сети и загрузки симулятора, поэтому в CI он пока advisory — см. ниже):

```bash
# 1. Юнит-тесты пакета (без сети и без симулятора)
swift test --package-path AniLibertyKit

# 2. Сборка приложения под симулятор tvOS
#    Для CI и для «просто убедиться, что собирается» имя устройства не нужно —
#    generic-назначение работает без конкретного симулятора (его и использует CI):
xcodebuild -project AniTV.xcodeproj -scheme AniTV \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

#    Если нужен запуск в конкретном симуляторе:
xcodebuild -project AniTV.xcodeproj -scheme AniTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (4th generation)' \
  -derivedDataPath .build/DerivedData build | xcbeautify

# 3. Форматирование (сначала применить, потом проверить)
swiftformat .
swiftformat --lint .

# 4. Линт в строгом режиме: любое предупреждение — ошибка
swiftlint --strict

# 5. UI-тесты: два XCUITest-сценария (лента → карточка → Menu и карточка → плеер → Menu)
#    ведут приложение по настоящему API AniLiberty через focus engine, поэтому нужны сеть
#    и поднятый симулятор tvOS. Подставьте UDID из `xcrun simctl list devices`:
xcodebuild test -project AniTV.xcodeproj -scheme AniTV \
  -only-testing:AniTVUITests \
  -destination 'platform=tvOS Simulator,id=1CEE9693-F8EB-45A4-8223-1679EE0EFC5A' \
  -derivedDataPath .build/DerivedData | xcbeautify
```

Дополнительно:

- CI выполняет пункты 1–4 в job `build-test-lint`, а пункт 5 — в отдельном job `ui-tests`.
  UI-тесты там **advisory**: падение не блокирует PR и не делает весь прогон красным, зато
  `.xcresult` уезжает артефактом, а в summary появляется предупреждение. Причина — живой API
  из апстрима и медленная загрузка симулятора tvOS на GitHub-раннере; в required его переведут,
  когда наберётся серия зелёных прогонов на раннере (подробности — в комментарии к job).
- Все CLI-инструменты в CI распинуты (XcodeGen 2.46.0, xcbeautify 3.2.1, SwiftFormat 0.64.6,
  SwiftLint 0.65.1) и ставятся из GitHub releases, а не из Homebrew: `brew install` уже даёт
  более новые версии, а конфиги репозитория проверены именно на этих.
- В проекте не должно появляться новых предупреждений компилятора.
- Новые файлы Swift автоматически попадают под линт — отдельная настройка не нужна.
- Конфигурации `.swiftlint.yml` и `.swiftformat` согласованы между собой (например, правило
  `trailing_comma` в SwiftLint требует запятую в многострочных коллекциях, а SwiftFormat
  `--trailing-commas collections-only` её ставит). Меняя одно, проверьте другое в обе стороны:
  `swiftformat --lint .` и `swiftlint --strict`.
- Порядок модификаторов — зона SwiftFormat, правило `modifier_order` в SwiftLint отключено
  осознанно: в версиях 0.64.6 / 0.65.1 инструменты требуют противоположного порядка
  (`private nonisolated` против `nonisolated private`), а настроить порядок в SwiftLint нельзя —
  токена `nonisolated` в `preferred_modifier_order` нет. Пишите `private nonisolated` (как
  делает `swiftformat .`); CI всё равно проверяет порядок через `swiftformat --lint .`.

## Коммиты

[Conventional Commits](https://www.conventionalcommits.org/), тема на английском, в
повелительном наклонении:

```
feat: add release detail screen
fix: keep resume position when the player is reopened
chore: pin swiftlint to 0.65.1 in CI
docs: record ADR for image cache eviction
test: cover tolerant date decoding
refactor: extract stream resolver from view model
```

Правила:

- Одно логическое изменение на коммит; код, память проекта и `CHANGELOG.md` — в одном коммите.
- Никогда не коммитьте `*.xcodeproj`, `DerivedData/`, `.build/`, пользовательские схемы и секреты.
- Никаких `git commit --amend`/`push --force` в общие ветки.

## Код и стиль

Полные правила — в [AGENTS.md](AGENTS.md) §7; короткая выжимка:

- Swift 6, строгая конкурентность, `@Observable` вместо `ObservableObject`/`@Published`.
- tvOS 26.0 — минимальная версия, никаких `if #available` для старых систем.
- 4 пробела, максимум 120 символов в строке, никаких force unwrap / `try!` / `as!` в
  production-коде. В тестах `XCTUnwrap` предпочтительнее.
- Бизнес-логика живёт в `AniLibertyKit`, а не во вью. Приложение общается только через публичный
  API пакета: `HTTPTransport`, `URLSession`, JSON-детали и `ServiceURL` — внутренние символы,
  трогать их из `App/` нельзя.
- UI-тексты — через String Catalogs; в коде нет захардкоженных пользовательских строк.
- Логирование — через `Logger`, не `print`.
- Сторонние зависимости не добавляются: `Package.swift` остаётся без зависимостей, пока не
  появится ADR с обоснованием.

## Работа в команде агентов

Разработка ведётся через DSH Agent Teams (см. [AGENTS.md](AGENTS.md) §3): Lead и тимейты с
непересекающимися зонами записи, доска задач в общем доступе.

- Задачу сначала клеймят на доске, потом делают. Без клейма задачу не начинают.
- Один агент — один набор файлов. Общие файлы (`project.yml`, `Package.swift`, `AGENTS.md`,
  `docs/`) принадлежат Lead и не редактируются тимейтами.
- Тимейты **не** делают `git commit` и `git push`. Коммитит только Lead, после зелёной сборки.
- «Готово» от тимейта — это заявка, а не доказательство: Lead перечитывает diff и сам запускает
  сборку и тесты.

## Секреты и приватность

В репозитории нет и не будет ключей, токенов, сертификатов и профилей. Токен сессии пользователя
хранится только в Keychain на устройстве. Если вы случайно закоммитили секрет — не «убирайте»
его следующим коммитом: сообщите приватно по инструкции из [SECURITY.md](SECURITY.md), секрет
нужно считать скомпрометированным.

## Лицензия вклада

Отправляя Pull Request, вы соглашаетесь, что ваш вклад распространяется под лицензией
[MIT](LICENSE), как и остальной проект.
