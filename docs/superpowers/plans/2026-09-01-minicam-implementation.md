# MiniCam — план реализации

Дата: 2026-09-01  
Спецификация: `docs/superpowers/specs/2026-09-01-minicam-design.md`

## Принципы выполнения

- Сначала проверяются два главных риска: Universal-сборка VLCKit и чтение реального архива Hikvision.
- Интерфейс не полируется, пока live и переход в архив не работают на камере.
- Автоматических тестов мало: только критическая логика без надёжной визуальной проверки.
- Каждый этап заканчивается небольшой проверкой и отдельным коммитом.
- Пароль камеры никогда не записывается в файлы проекта или командную строку.

## Этап 0. Подготовить инструменты

Текущее состояние: установлен Swift 6.2.1 и Command Line Tools, но полного Xcode нет; активный developer directory — `/Library/Developer/CommandLineTools`. CocoaPods 1.11.3 доступен, но сообщает о старом расширении `ffi`. `xcodegen` отсутствует.

Необходимо:

1. Установить полный Xcode, совместимый с текущей macOS.
2. Один раз запустить Xcode и принять лицензию/установку компонентов.
3. Выбрать Xcode как активный developer directory.
4. Проверить `xcodebuild -version` и доступность macOS SDK.
5. Установить или предоставить XcodeGen для воспроизводимого создания `.xcodeproj` из `project.yml`.
6. Исправить CocoaPods `ffi`, только если `pod install` действительно завершится ошибкой.

Критерий: `xcodebuild` работает, `xcodegen` доступен, CocoaPods способен разрешить зависимости.

## Этап 1. Создать минимальный Universal-проект

Файлы:

- `project.yml`
- `Podfile`
- `.gitignore`
- `MiniCam/App/MiniCamApp.swift`
- `MiniCam/App/AppContainer.swift`
- `MiniCam/Resources/Info.plist`

Действия:

1. Создать macOS application target и unit-test target через XcodeGen.
2. Установить deployment target `12.0` и стандартные архитектуры `arm64 x86_64`.
3. Использовать Swift language mode, совместимый с Monterey и VLCKit 3.x.
4. Зафиксировать `VLCKit` версии `3.7.2` в CocoaPods; не использовать VLC 4 alpha.
5. Сгенерировать workspace и собрать пустое приложение.
6. Проверить, что бинарник Release содержит обе архитектуры.

Команды проверки после установки Xcode:

```sh
xcodegen generate
pod install
xcodebuild -workspace MiniCam.xcworkspace -scheme MiniCam -configuration Release -derivedDataPath build ONLY_ACTIVE_ARCH=NO build
lipo -archs build/Build/Products/Release/MiniCam.app/Contents/MacOS/MiniCam
```

Критерий: пустое приложение запускается на текущем Mac, а Release-бинарник содержит `arm64` и `x86_64`.

## Этап 2. Описать доменную модель

Файлы:

- `MiniCam/Domain/CameraProfile.swift`
- `MiniCam/Domain/RecordingSegment.swift`
- `MiniCam/Domain/PlaybackState.swift`
- `MiniCam/Domain/CameraError.swift`

Модели:

- `CameraProfile`: host, HTTP port, RTSP port, channel; без пароля.
- `RecordingSegment`: начало, конец и закрытый служебный URI архива.
- `PlaybackState`: live, loading, archive, failed.
- `CameraError`: понятные категории ошибок для UI.

Проверка: профиль сериализуется без учётных данных; интервалы запрещают конец раньше начала.

## Этап 3. Реализовать безопасные настройки

Файлы:

- `MiniCam/Infrastructure/Settings/ProfileStore.swift`
- `MiniCam/Infrastructure/Security/CredentialStore.swift`
- `MiniCam/Infrastructure/Security/KeychainCredentialStore.swift`

Действия:

1. Несекретный профиль хранить в `UserDefaults`.
2. Имя пользователя и пароль хранить отдельной записью Keychain.
3. Не встраивать credentials в сохраняемый RTSP URL.
4. Подготовить in-memory реализацию CredentialStore для preview и ручной проверки.

Критерий: после перезапуска профиль восстанавливается, пароль читается из Keychain и отсутствует в plist/UserDefaults.

## Этап 4. Проверить Hikvision ISAPI на реальной камере

Файлы:

- `MiniCam/Infrastructure/Hikvision/HikvisionClient.swift`
- `MiniCam/Infrastructure/Hikvision/DigestSessionDelegate.swift`
- `MiniCam/Infrastructure/Hikvision/ISAPIModels.swift`
- `MiniCam/Infrastructure/Hikvision/ISAPIXMLParser.swift`
- `MiniCamTests/Fixtures/content-search-response.xml`
- `MiniCamTests/ISAPIXMLParserTests.swift`

Действия:

1. Выполнить Digest-аутентификацию через challenge URLSession.
2. Проверить сведения об устройстве через ISAPI.
3. Проверить состояние microSD.
4. Отправить поиск записей за небольшой интервал через Content Management search на целевой камере `192.168.1.122`.
5. Сохранить обезличенный пример XML-ответа как fixture.
6. Из результата определить точный playback URI, который отдаёт эта прошивка.
7. Проверить полученный источник непосредственно VLC/VLCKit.

Единственный тест этапа: parser корректно извлекает начало, конец и URI из реального обезличенного XML.

Критерий: приложение получает хотя бы один интервал и VLCKit открывает соответствующую запись. Если камера не отдаёт пригодный playback URI, реализация останавливается и архитектура пересматривается до разработки UI.

## Этап 5. Построить непрерывную шкалу архива

Файлы:

- `MiniCam/Domain/ArchiveTimeline.swift`
- `MiniCam/Application/ArchiveService.swift`
- `MiniCamTests/ArchiveTimelineTests.swift`

Действия:

1. Нормализовать даты камеры в UTC, отображать их в локальном часовом поясе Mac.
2. Сортировать и дедуплицировать сегменты.
3. Объединять только небольшие технические разрывы для визуального отображения, сохраняя исходные сегменты для открытия.
4. Выбирать сегмент, содержащий целевое время; для разрыва выбирать ближайший последующий.
5. Кэшировать результаты по суткам в памяти.

Минимальные тесты одним файлом:

- сортировка/объединение;
- выбор внутри сегмента;
- выбор в разрыве;
- переход через полночь.

Критерий: для любого времени сервис возвращает правильный исходный сегмент или сообщает об отсутствии записи.

## Этап 6. Подключить VLCKit и быстрый live

Файлы:

- `MiniCam/Infrastructure/Streaming/LiveStreamService.swift`
- `MiniCam/Infrastructure/Player/VLCPlayerAdapter.swift`
- `MiniCam/UI/Player/VLCPlayerView.swift`

Действия:

1. Формировать main stream `/Streaming/Channels/101` из номера канала.
2. Передавать credentials плееру только в памяти.
3. Создать AppKit video surface через `NSViewRepresentable`.
4. Настроить RTSP over TCP, небольшой network cache и аппаратное декодирование.
5. Передавать в SwiftUI состояния opening, playing, paused, buffering, ended и error.
6. Сравнить задержку MiniCam и VLC на одном потоке.

Критерий: live стабильно работает на реальной камере, задержка визуально сопоставима с VLC, пароль не появляется в журнале.

## Этап 7. Реализовать единое воспроизведение live/archive

Файлы:

- `MiniCam/Application/PlaybackCoordinator.swift`
- `MiniCam/Application/PlaybackClock.swift`
- `MiniCamTests/PlaybackCoordinatorTests.swift`

Действия:

1. Запускать приложение в live.
2. По завершённому seek выбирать архивный сегмент и менять источник плеера.
3. Пересчитывать позицию внутри выбранного сегмента.
4. По окончании сегмента открывать следующий.
5. При необходимости загружать следующие сутки.
6. При достижении live edge переключаться на прямой RTSP.
7. Кнопкой «В прямой эфир» прерывать любую архивную операцию.
8. Ограниченно повторять подключение после сетевого сбоя.

Единственный набор тестов: переходы `live → archive → следующий сегмент → live` на fake player и fake archive service.

Критерий: координатор непрерывно ведёт пользовательское время через источники, не заставляя UI знать о файлах камеры.

## Этап 8. Собрать интерфейс первой версии

Файлы:

- `MiniCam/UI/Root/RootView.swift`
- `MiniCam/UI/Setup/CameraSetupView.swift`
- `MiniCam/UI/Player/CameraPlayerView.swift`
- `MiniCam/UI/Timeline/TimelineView.swift`
- `MiniCam/UI/Timeline/TimelineViewModel.swift`
- `MiniCam/UI/Components/PlaybackControls.swift`
- `MiniCam/UI/Components/StatusOverlay.swift`

Действия:

1. Создать настройку камеры с проверкой подключения.
2. Разместить видео и постоянные элементы управления в одном окне.
3. Отобразить live edge, интервалы записи, разрывы и выбранное время.
4. Во время drag менять только preview времени; seek выполнять после mouse-up.
5. Добавить календарь без отдельной страницы архива.
6. Добавить паузу, звук, fullscreen и «В прямой эфир».
7. Показать понятные состояния загрузки и ошибки поверх видео.

Проверка только ручная: размеры окна, читаемость, управление мышью, переход live/archive и отсутствие зависаний при перетаскивании.

## Этап 9. Интеграционная проверка

Сценарии на DS-2CD2043G2-IU:

1. Первый запуск и сохранение credentials.
2. Live не менее 15 минут.
3. Переход на 5 минут, 1 час и предыдущие сутки назад.
4. Перемотка вперёд и назад внутри записи.
5. Автоматический переход между двумя реальными сегментами.
6. Возврат в live кнопкой и достижением правого края.
7. Отключение сети на короткое время и восстановление.
8. День без записи и неверный пароль.

Критерий: нет сбоев процесса, UI не блокируется, ошибки понятны, секреты не появляются в Console.

## Этап 10. Собрать устанавливаемое приложение

Действия:

1. Выполнить Release Archive без App Store distribution.
2. Проверить deployment target `12.0` во всех собственных и встроенных бинарниках.
3. Проверить `arm64` и `x86_64` через `lipo`.
4. Подписать для личного запуска доступной Development/adhoc-подписью.
5. Перенести `.app` на Intel Mac с Monterey и выполнить smoke test.
6. Дополнить README инструкцией сборки и установки, используя фактически проверенные команды.

Критерий: один Universal `MiniCam.app` запускается на текущем Mac и на Intel Mac с Monterey.

## Порядок коммитов

1. `build: create universal macOS project`
2. `feat: add camera profile and secure credentials`
3. `feat: query Hikvision recording archive`
4. `feat: build continuous archive timeline`
5. `feat: add low latency VLC live player`
6. `feat: coordinate live and archive playback`
7. `feat: add unified camera timeline UI`
8. `docs: add verified build and installation steps`

## Точка остановки по риску

После этапа 4 нельзя переходить к полноценному UI, пока реальная камера не вернула открываемый архивный источник. Это основной технический риск проекта. Если ISAPI текущей прошивки предоставляет только поиск без пригодного воспроизведения, нужно выбрать другой транспорт архива или пересмотреть требование чтения непосредственно с microSD.
