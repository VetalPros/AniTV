# Политика конфиденциальности AniTV / AniTV Privacy Policy

**Последнее обновление / Last updated:** 2026-11-27
**Действует для сборок TestFlight и для приложения AniTV для Apple TV.**

---

## Русский

### Коротко

Приложение **не собирает** персональные данные и **не передаёт** их разработчикам. У разработчиков нет
своих серверов, аналитики, рекламы и сторонних SDK. Всё, что приложение отправляет в сеть, уходит напрямую
сервису **AniLiberty** (`aniliberty.top`), потому что приложение — его неофициальный клиент.

### Кто за что отвечает

- **Разработчики AniTV** не получают никаких данных: приложение не обращается к нашим серверам, их нет.
- **Оператор сервиса AniLiberty** — самостоятельный контроллер данных вашего аккаунта: избранного, истории,
  профиля. Условия обработки определяет он, а не приложение.

### Что приложение хранит на устройстве

| Данные | Где хранятся | Зачем |
| --- | --- | --- |
| Токен сессии (появляется после привязки телевизора по коду) | Связка ключей tvOS (Keychain) | Чтобы не привязывать телевизор заново при каждом запуске |
| Технический идентификатор устройства (случайный UUID) | Локальные настройки приложения | Сервис требует один и тот же идентификатор при запросе кода привязки и при его проверке |
| Две настройки плеера (пропускать опенинги/эндинги) | Локальные настройки приложения | Запоминать ваш выбор |
| Позиция просмотра и прогресс по релизам | Локально на устройстве | Продолжать просмотр с того же места |
| Кэш изображений и ответов каталога | Локально на устройстве | Не тратить трафик и не нагружать сервис повторными запросами |

Все эти данные удаляются вместе с приложением. Токен можно удалить, выйдя из аккаунта в приложении.

### Что уходит в сеть и куда

Приложение обращается **только** к `https://aniliberty.top` (API и изображения постеров). В запросах
передаются:

- технический идентификатор устройства — при привязке телевизора;
- токен сессии — в заголовке авторизации, после успешной привязки;
- обычные параметры запросов: идентификаторы релизов, поисковые строки, фильтры, страницы каталога;
- при добавлении/удалении избранного и чтении профиля — соответствующие запросы к вашему аккаунту.

Приложение не отправляет: имя, e-mail, местоположение, контакты, идентификаторы рекламы (IDFA), данные
использования, диагностику и краш-логи.

### Чего приложение не делает

- нет аналитики, трекеров, рекламы и сторонних библиотек;
- нет доступа к микрофону, камере, контактам, календарю, геолокации и фотографиям;
- нет фоновой передачи данных, кроме обычных сетевых запросов, пока приложение открыто;
- нет продажи или передачи данных третьим лицам — передавать нечего.

### Дети

Приложение не предназначено для детей: каталог сервиса содержит материалы с возрастными ограничениями
до 18+. Приложение не собирает данные о возрасте.

### Ваши права

Данными аккаунта распоряжается сервис AniLiberty: запросы на удаление аккаунта, избранного и истории
направляются ему. Локальные данные удаляются удалением приложения или выходом из аккаунта.

### Изменения

Актуальная версия этой политики всегда лежит в репозитории проекта. Дата последнего обновления указана
в начале документа.

### Контакты

Вопросы по приложению: <https://github.com/VetalPros/AniTV/issues>

---

## English

### In short

The app **does not collect** personal data and **does not send** any to its developers. There are no
developer-run servers, no analytics, no advertising and no third-party SDKs. Everything the app sends over
the network goes directly to **AniLiberty** (`aniliberty.top`), because the app is an unofficial client of
that service.

### Who is responsible for what

- **The AniTV developers** receive nothing: the app never contacts a server of ours, because none exists.
- **The AniLiberty service operator** is the independent controller of your account data (favourites,
  history, profile). Its terms, not this app, govern that processing.

### What the app stores on the device

| Data | Where | Why |
| --- | --- | --- |
| Session token (created after pairing the TV with a code) | tvOS Keychain | Avoid pairing the TV again on every launch |
| Technical device identifier (random UUID) | App's local preferences | The service requires the same identifier when a pairing code is requested and when it is polled |
| Two playback switches (skip openings/endings) | App's local preferences | Remember your choice |
| Playback position and per-release progress | Locally on the device | Resume where you stopped |
| Image and catalogue response caches | Locally on the device | Save bandwidth and avoid repeated requests |

All of it is removed when the app is deleted; the token can be removed by signing out in the app.

### What leaves the device, and where it goes

The app talks to **`https://aniliberty.top` only** (API and poster images). Requests carry:

- the technical device identifier, during TV pairing;
- the session token, in the authorization header, after successful pairing;
- ordinary request parameters: release identifiers, search strings, filters, catalogue pages;
- profile and favourites requests when you open your account or change favourites.

The app does **not** send: name, e-mail, location, contacts, advertising identifiers (IDFA), usage data,
diagnostics or crash logs.

### What the app does not do

- no analytics, trackers, advertising or third-party libraries;
- no access to microphone, camera, contacts, calendar, location or photos;
- no background data transfer beyond ordinary requests while the app is open;
- no sale or sharing of data with third parties — there is nothing to share.

### Children

The app is not aimed at children: the service's catalogue includes titles rated up to 18+. The app does not
collect age information.

### Your rights

Account data is governed by the AniLiberty service; deletion requests for the account, favourites and
history go to that service. Local data is removed by deleting the app or signing out.

### Changes

The current version of this policy always lives in the project repository; the date at the top of this
document is the last update.

### Contact

App-related questions: <https://github.com/VetalPros/AniTV/issues>
