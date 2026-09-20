# CCS: загрузка в TestFlight с Mac

Codemagic для этого процесса не нужен. Flutter собирает приложение на Mac,
Xcode подписывает архив и отправляет его в App Store Connect.

## Текущее состояние настройки

20 сентября 2026: архив и IPA `1.0.9 (2)` из `alex-ui`, коммит `cc5878aa`,
собраны. Первая прямая загрузка отклонена Apple с `Invalid Signature`.
Облачная подпись Apple Distribution не проходит локальную проверку своего
designated requirement: в имени сертификата и в требовании различается
Unicode-представление `Š`. Успешная загрузка пока не подтверждена.

На Mac установлен Apple Development. Сертификат Apple Distribution от июня
виден в Xcode как `Not in Keychain`: его закрытого ключа на этом Mac нет.
Следующий шаг настройки — локальный Apple Distribution и проверка нового
экспорта. Само создание сертификата ещё не доказывает исправление ошибки.

## Однократная настройка

1. В Xcode открой **Settings → Apple Accounts**, свой аккаунт и команду
   **ALEKSEJS PAŠEGOROVS** (`N7BDW56D69`).
2. **Manage Certificates → + → Apple Distribution** создаёт локальный
   сертификат и ключ публикации. Не отзывай существующие сертификаты.
3. Если Xcode сообщает об ошибке создания, сохрани точный текст ошибки.
4. Проект открывается через `ios/Runner.xcworkspace`. Bundle ID:
   `lv.ilexall.ccs`. Команда подписи уже указана в проекте.

## Следующие сборки после исправления подписи

1. В GitHub Desktop выбери `alex-ui` и получи нужные изменения.
   Локально можно собрать и ещё не отправленный на GitHub код.
2. В `pubspec.yaml` увеличь номер после `+`. Например, после `1.0.9+2`
   используй `1.0.9+3`, если этот номер ещё не загружен в App Store Connect.
3. В Терминале выполни:

   ```sh
   cd /Users/ilexall/Documents/GitHub/ccs
   flutter build ipa --release --dart-define=CCS_CARTO_BASEMAP_KEY=cb1_2n69_1_8c3e5525543822b4ade84b5d
   open build/ios/archive/Runner.xcarchive
   ```

   Значение параметра карты взято из текущей конфигурации проекта.
   Оно нужно и при локальной сборке. Сборка создаёт архив в
   `build/ios/archive/` и экспортирует IPA в `build/ios/ipa/`.
4. В Xcode Organizer проверь версию выбранного архива.
   Выбери **Distribute App → App Store Connect → Distribute**.
   Для группы внешних тестировщиков используй App Store Connect;
   вариант **TestFlight Internal Only** ограничивает сборку внутренним тестированием.
5. Дождись сообщения об успешной загрузке. Наличие IPA само по себе
   не означает, что Apple принял сборку.
6. В App Store Connect открой **Community Car Spots → TestFlight**.
   Дождись обработки Apple, заполни вопросы по экспортному соответствию,
   если они появятся, и добавь сборку в нужную группу, например **CCS BETA**.
   Для внешнего тестирования Apple может потребовать Beta App Review.

При `Invalid Signature` повторная загрузка того же пакета не исправляет
подпись. Нужно проверить сертификат и заново экспортировать архив.

## Справка

- [Flutter: сборка iOS](https://docs.flutter.dev/deployment/ios)
- [Apple: загрузка сборок](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [Apple: распространение через Xcode](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
