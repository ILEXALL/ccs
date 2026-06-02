import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as material show Text;
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

// Paste the OAuth 2.0 Web Client ID from Firebase/Google Cloud here.
// It usually looks like: 325709324670-xxxxx.apps.googleusercontent.com
const googleServerClientId =
    '325709324670-cep9b3r2j2mmapmmuougmqai7umvlod6.apps.googleusercontent.com';

// Real Telegram login needs a small backend server.
// Deploy ccs_app/telegram_auth_server, then paste its HTTPS URL here.
const telegramAuthBaseUrl = 'https://ccs-wine.vercel.app';
const pushNotificationUrl = '$telegramAuthBaseUrl/api/push-notification';
const r2PresignUploadUrl =
    'https://ccs-telegram-auth-server.vercel.app/api/r2-presign-upload';
const int maxSpotGalleryPhotos = 4;
const Duration maxTemporarySpotDuration = Duration(hours: 12);
const double temporarySpotHidePermanentRadiusMeters = 500;
const double minimumPermanentSpotDistanceMeters = 500;
const int maxGaragePhotos = 4;
const int r2SpotPhotoMaxLongSide = 1280;
const int r2AvatarPhotoMaxLongSide = 768;
const int r2GaragePhotoMaxLongSide = 1280;
const int r2JpegQuality = 76;
const double garagePhotoAspectRatio = 1.45;

String? googleSignInSetupError;
bool firebaseReady = false;
bool rememberMeEnabled = false;
const rememberMeKey = 'remember_me';
const liveLocationDisclaimerDismissedKey = 'live_location_disclaimer_dismissed';
const liveLocationDurationChoices = <Duration>[
  Duration(hours: 1),
  Duration(hours: 2),
  Duration(hours: 4),
];
const liveLocationRenewGracePeriod = Duration(minutes: 10);
StreamSubscription<String>? pushTokenRefreshSubscription;
StreamSubscription<RemoteMessage>? foregroundPushSubscription;
StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
notificationCenterUnreadSubscription;
final notificationCenterUnreadCount = ValueNotifier<int>(0);

enum AppLanguage { en, ru, lv }

class AppUiPreferences extends ChangeNotifier {
  static const languageKey = 'app_language';
  static const lightThemeKey = 'app_light_theme';

  AppLanguage language = AppLanguage.en;
  bool lightTheme = false;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      language = AppLanguage.values.firstWhere(
        (value) => value.name == prefs.getString(languageKey),
        orElse: () => AppLanguage.en,
      );
      // Light theme is disabled: CCS uses the dark map/glass design only.
      lightTheme = false;
      await prefs.setBool(lightThemeKey, false);
    } catch (_) {}
  }

  Future<void> setLanguage(AppLanguage value) async {
    if (language == value) {
      return;
    }

    language = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(languageKey, value.name);
    } catch (_) {}
  }

  Future<void> setLightTheme(bool value) async {
    // Light theme is removed from the app. Keep this method only so old calls do not break.
    if (!lightTheme) {
      return;
    }

    lightTheme = false;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(lightThemeKey, false);
    } catch (_) {}
  }
}

final appUiPreferences = AppUiPreferences();

class MaintenanceModeConfig {
  final bool maintenanceEnabled;
  final String maintenanceTitle;
  final String maintenanceMessage;
  final bool allowAdminBypass;

  const MaintenanceModeConfig({
    required this.maintenanceEnabled,
    required this.maintenanceTitle,
    required this.maintenanceMessage,
    required this.allowAdminBypass,
  });

  static const disabled = MaintenanceModeConfig(
    maintenanceEnabled: false,
    maintenanceTitle: 'Maintenance',
    maintenanceMessage: 'CCS will be back shortly.',
    allowAdminBypass: false,
  );

  factory MaintenanceModeConfig.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!snapshot.exists) {
      return disabled;
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    return MaintenanceModeConfig(
      maintenanceEnabled: data['maintenanceEnabled'] == true,
      maintenanceTitle: stringFromFirebase(
        data['maintenanceTitle'],
        'Maintenance',
      ),
      maintenanceMessage: stringFromFirebase(
        data['maintenanceMessage'],
        'CCS will be back shortly.',
      ),
      allowAdminBypass: data['allowAdminBypass'] == true,
    );
  }
}

final maintenanceModeConfig = ValueNotifier<MaintenanceModeConfig>(
  MaintenanceModeConfig.disabled,
);
final maintenanceAccessRevision = ValueNotifier<int>(0);
StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
maintenanceModeSubscription;

DocumentReference<Map<String, dynamic>> maintenanceModeDocument() {
  return FirebaseFirestore.instance.collection('app_config').doc('main');
}

void refreshMaintenanceAccess() {
  maintenanceAccessRevision.value += 1;
}

Future<void> refreshMaintenanceMode() async {
  if (!firebaseReady) {
    return;
  }

  try {
    final snapshot = await maintenanceModeDocument().get();
    maintenanceModeConfig.value = MaintenanceModeConfig.fromSnapshot(snapshot);
  } catch (error) {
    debugPrint('Maintenance config refresh failed: $error');
  }
}

Future<void> initializeMaintenanceMode() async {
  await maintenanceModeSubscription?.cancel();
  await refreshMaintenanceMode();

  maintenanceModeSubscription = maintenanceModeDocument().snapshots().listen(
    (snapshot) {
      maintenanceModeConfig.value = MaintenanceModeConfig.fromSnapshot(
        snapshot,
      );
    },
    onError: (Object error) {
      debugPrint('Maintenance config watcher failed: $error');
    },
  );
}

const _ruText = <String, String>{
  'Spots': 'Споты',
  'Map': 'Карта',
  'Add Spot': 'Добавить спот',
  'Chat': 'Чат',
  'Profile': 'Профиль',
  'Settings': 'Настройки',
  'Notifications': 'Уведомления',
  'Privacy': 'Приватность',
  'Appearance': 'Оформление',
  'Light theme': 'Светлая тема',
  'Use a brighter interface throughout the app':
      'Использовать светлое оформление во всём приложении',
  'Language': 'Язык',
  'Recent notifications': 'Последние уведомления',
  'Project news': 'Новости проекта',
  'No notifications yet': 'Уведомлений пока нет',
  'Your latest CCS updates will appear here.':
      'Здесь будут появляться последние обновления CCS.',
  'CCS notification center is ready.': 'Центр уведомлений CCS готов к работе.',
  'Refresh': 'Обновить',
  'Retry': 'Повторить',
  'Approved car spots': 'Одобренные автомобильные споты',
  'Filters': 'Фильтры',
  'Explore filters': 'Фильтры спотов',
  'All categories enabled': 'Включены все категории',
  'Select all': 'Выбрать все',
  'Clear': 'Очистить',
  'Apply filters': 'Применить фильтры',
  'Popular': 'Популярные',
  'Newest': 'Новые',
  'Oldest': 'Старые',
  'Meet spots': 'Встречи',
  'Saved': 'Сохранённые',
  'Show less': 'Свернуть',
  'Saved Spots': 'Сохранённые споты',
  'No saved spots yet': 'Сохранённых спотов пока нет',
  'No spots here yet': 'Здесь пока нет спотов',
  'No spots match your filters': 'Нет спотов по выбранным фильтрам',
  'Tap the bookmark on a spot to keep it here.':
      'Нажмите закладку на споте, чтобы сохранить его здесь.',
  'Approved spots will appear here after moderation.':
      'Одобренные споты появятся здесь после модерации.',
  'Open filters and enable more categories to see more spots.':
      'Откройте фильтры и включите дополнительные категории.',
  'Spot review updates': 'Результаты проверки спотов',
  'Approved or rejected spot submissions': 'Одобрение или отклонение спотов',
  'Likes on my spots': 'Лайки моих спотов',
  'When people like your approved spots':
      'Когда пользователи лайкают ваши споты',
  'Comments': 'Комментарии',
  'Future comments and community replies': 'Новые комментарии и ответы',
  'New spots': 'Новые споты',
  'Fresh approved locations nearby': 'Новые одобренные места поблизости',
  'Messages': 'Сообщения',
  'New direct and group messages': 'Новые личные и групповые сообщения',
  'Public profile': 'Публичный профиль',
  'Let other drivers see your profile':
      'Разрешить другим водителям видеть профиль',
  'Show garage': 'Показывать гараж',
  'Display your car builds on your profile': 'Показывать автомобили в профиле',
  'Save Settings': 'Сохранить настройки',
  'Settings saved to your account.': 'Настройки аккаунта сохранены.',
  'Add Car': 'Добавить автомобиль',
  'Edit Garage': 'Редактировать гараж',
  'Car photos': 'Фотографии автомобиля',
  'Car info': 'Информация об автомобиле',
  'Car name': 'Название автомобиля',
  'Description': 'Описание',
  'Add up to 4 car photos. The first photo becomes the garage cover.':
      'Добавьте до 4 фотографий. Первая станет обложкой гаража.',
  'Upload photos': 'Загрузить фотографии',
  'Cover': 'Обложка',
  'Save Garage': 'Сохранить гараж',
  'Photo': 'Фото',
  'Meet': 'Встречи',
  'Drive': 'Поездки',
  'Service': 'Сервис',
  'Detailing': 'Детейлинг',
  'Wash': 'Мойка',
  'Store': 'Магазин',
  'Drag': 'Драг',
  'Off-road': 'Бездорожье',
  'Food': 'Еда',
  'Today': 'Сегодня',
  'Tomorrow': 'Завтра',
  'This week': 'На этой неделе',
  'Next week': 'На следующей неделе',
  'This month': 'В этом месяце',
  'Next month': 'В следующем месяце',
  'Write a comment': 'Напишите комментарий',
  'Post Comment': 'Опубликовать',
  'Posting...': 'Публикация...',
  'Message': 'Сообщение',
  'Save Spot': 'Сохранить спот',
  'Saved Spot': 'Спот сохранён',
  'View Spot': 'Открыть спот',
  'View Profile': 'Открыть профиль',
  'Edit Profile': 'Редактировать профиль',
  'Adjust Photo': 'Настроить фото',
  'Use Photo': 'Использовать фото',
  'Saving...': 'Сохранение...',
  'Monday': 'Понедельник',
  'Tuesday': 'Вторник',
  'Wednesday': 'Среда',
  'Thursday': 'Четверг',
  'Friday': 'Пятница',
  'Saturday': 'Суббота',
  'Sunday': 'Воскресенье',
  'Just now': 'Только что',
  'Stop sharing': 'Остановить показ',
  'Not there': 'Уже нет',
  'Still there': 'Всё ещё там',
  'Live now': 'Сейчас онлайн',
  'Spot': 'Спот',
  'Show on map': 'Показать на карте',
  'Edit Service Info': 'Редактировать данные сервиса',
  'Hours not added': 'Часы работы не добавлены',
  'The owner has not added opening hours yet.':
      'Владелец пока не добавил часы работы.',
  'Closed today': 'Сегодня закрыто',
  'Hours need update': 'Нужно обновить часы работы',
  'Opening hours are not formatted correctly.': 'Часы работы указаны неверно.',
  'Open now': 'Сейчас открыто',
  'Closed now': 'Сейчас закрыто',
  'Phone': 'Телефон',
  'Instagram': 'Instagram',
  'Email': 'Эл. почта',
  'Cancel': 'Отмена',
  'Save': 'Сохранить',
  'Delete': 'Удалить',
  'Find exact address': 'Найти точный адрес',
  'Street, city, country': 'Улица, город, страна',
  'Find': 'Найти',
  'Basic info': 'Основная информация',
  'Spot name': 'Название спота',
  'Pin on the map': 'Поставить метку на карте',
  'Use current location': 'Использовать текущее местоположение',
  'Visibility': 'Видимость',
  'Verified only': 'Только проверенные пользователи',
  'Temporary schedule': 'Временное расписание',
  'Categories': 'Категории',
  'Contacts': 'Контакты',
  'Opening hours': 'Часы работы',
  'Media': 'Медиа',
  'Instagram / TikTok video link': 'Ссылка на видео Instagram / TikTok',
  'Added by': 'Добавил',
  'Starts at': 'Начинается',
  'Ends at': 'Заканчивается',
  'Choose Location': 'Выбрать место',
  'Service Info': 'Данные сервиса',
  'My Submissions': 'Мои заявки',
  'No submissions yet': 'Заявок пока нет',
  'Log in required': 'Требуется вход',
  'Chats': 'Чаты',
  'Groups': 'Группы',
  'No chats yet': 'Чатов пока нет',
  'Edit Chat View': 'Настроить отображение чата',
  'New Chat': 'Новый чат',
  'Direct': 'Личный',
  'Group': 'Группа',
  'Find friend': 'Найти друга',
  'Group name': 'Название группы',
  'No friends found': 'Друзья не найдены',
  'owner': 'владелец',
  'moderator': 'модератор',
  'Group Info': 'Информация о группе',
  'Group description': 'Описание группы',
  'Save Group': 'Сохранить группу',
  'No messages yet': 'Сообщений пока нет',
  'Friends': 'Друзья',
  'Send requests, accept invites, and manage friends':
      'Отправляйте заявки, принимайте приглашения и управляйте друзьями',
  'Add another car': 'Добавить автомобиль',
  'Add another car to your garage': 'Добавить ещё один автомобиль в гараж',
  'Account, privacy, notifications': 'Аккаунт, приватность, уведомления',
  'Log out of this Google account': 'Выйти из аккаунта Google',
  'Cars': 'Автомобили',
  'Base': 'Город',
  'Verified': 'Проверен',
  'No garage shared': 'Гараж не опубликован',
  'Profile not found': 'Профиль не найден',
  'Profile deleted': 'Профиль удалён',
  'Private profile': 'Закрытый профиль',
  'No friends yet': 'Друзей пока нет',
  'Remove': 'Удалить',
  'No incoming requests': 'Нет входящих заявок',
  'Accept': 'Принять',
  'Decline': 'Отклонить',
  'No sent requests': 'Нет отправленных заявок',
  'nickname or name': 'никнейм или имя',
  'No users found': 'Пользователи не найдены',
  'Profile info': 'Информация профиля',
  'Nickname': 'Никнейм',
  'About you': 'О себе',
  'Social links': 'Социальные сети',
  'Save Profile': 'Сохранить профиль',
  'Verified Users': 'Проверенные пользователи',
  'No users yet': 'Пользователей пока нет',
  'Delete user?': 'Удалить пользователя?',
  'Open profile': 'Открыть профиль',
  'Ban 1 day': 'Заблокировать на 1 день',
  'Ban 7 days': 'Заблокировать на 7 дней',
  'Ban 30 days': 'Заблокировать на 30 дней',
  'Ban forever': 'Заблокировать навсегда',
  'Unban': 'Снять блокировку',
  'Make moderator': 'Назначить модератором',
  'Remove moderator': 'Убрать модератора',
  'Users': 'Пользователи',
  'Open profiles, ban, unban, or delete users':
      'Открывайте профили, блокируйте и удаляйте пользователей',
  'Grant or remove verified status':
      'Назначайте или снимайте проверенный статус',
  'Edit Spot': 'Редактировать спот',
  'City / country': 'Город / страна',
  'Latitude': 'Широта',
  'Longitude': 'Долгота',
  'Category': 'Категория',
  'Photos': 'Фотографии',
  'Manage Spot': 'Управление спотом',
  'Reject': 'Отклонить',
  'Approve': 'Одобрить',
  'Delete Spot': 'Удалить спот',
  'Write a comment about this spot': 'Напишите комментарий об этом споте',
  'Edit your comment': 'Измените комментарий',
  'Search users': 'Поиск пользователей',
  'Spot owner': 'Владелец спота',
  'Search nickname, name, or email': 'Поиск по никнейму, имени или эл. почте',
  'Search to change owner': 'Найдите нового владельца',
  'Add friends first, then start a chat here.':
      'Сначала добавьте друзей, затем начните чат здесь.',
  'Add map alert': 'Добавить отметку на карте',
  'Add members': 'Добавить участников',
  'Address not found. Try adding city and country.':
      'Адрес не найден. Добавьте город и страну.',
  'Admin accounts cannot be managed here.':
      'Аккаунтами администраторов нельзя управлять здесь.',
  'Admins publish instantly. User spots wait for review.':
      'Споты администраторов публикуются сразу. Остальные ждут проверки.',
  'Approved spots': 'Одобренные споты',
  'Are you sure you want to delete this comment?':
      'Вы уверены, что хотите удалить комментарий?',
  'By continuing, you agree to our Terms & Privacy Policy':
      'Продолжая, вы принимаете условия и политику конфиденциальности',
  'Car added to your account.': 'Автомобиль добавлен в аккаунт.',
  'Choose both start and end time for a temporary spot.':
      'Выберите время начала и окончания временного спота.',
  'Closed': 'Закрыто',
  'Comment deleted.': 'Комментарий удалён.',
  'Comment posted.': 'Комментарий опубликован.',
  'Comment updated.': 'Комментарий обновлён.',
  'Continue sharing': 'Продолжить показ',
  'Continue sharing?': 'Продолжить показ?',
  'Could not open this contact.': 'Не удалось открыть контакт.',
  'Could not open this link.': 'Не удалось открыть ссылку.',
  'Created spots will appear here.': 'Созданные споты появятся здесь.',
  'Current location selected for this spot.':
      'Для спота выбрано текущее местоположение.',
  'Delete comment': 'Удалить комментарий',
  'Delete message': 'Удалить сообщение',
  'Delete message?': 'Удалить сообщение?',
  'Delete spot': 'Удалить спот',
  'Delete spot?': 'Удалить спот?',
  'Delete user': 'Удалить пользователя',
  'Description is required.': 'Добавьте описание.',
  'Edit comment': 'Редактировать комментарий',
  'Edit message': 'Редактировать сообщение',
  'Edit spot': 'Редактировать спот',
  'End time must be after start time.':
      'Время окончания должно быть позже времени начала.',
  'End time must be in the future.': 'Время окончания должно быть в будущем.',
  'Enter valid latitude and longitude.': 'Введите корректные координаты.',
  'Friend invites sent to you will appear here.':
      'Здесь появятся входящие заявки в друзья.',
  'Garage saved to your account.': 'Гараж сохранён в аккаунте.',
  'Garage tags': 'Теги гаража',
  'Get closer to this police mark before confirming it.':
      'Подъедьте ближе к отметке полиции, чтобы подтвердить её.',
  'Grant verified status': 'Назначить проверенный статус',
  'Group info': 'Информация о группе',
  'Incoming requests': 'Входящие заявки',
  'Live location sharing is on for 1 hour.':
      'Показ геопозиции включён на 1 час.',
  'Loading users...': 'Загрузка пользователей...',
  'Location is required. Pin it on the map, find exact address, or use current location first.':
      'Укажите место на карте, найдите адрес или используйте текущую геопозицию.',
  'Location permission is needed for distance.':
      'Для определения расстояния нужен доступ к геопозиции.',
  'Location permission is needed to share your location.':
      'Для отправки геопозиции нужен доступ к ней.',
  'Location permission is needed to show you on the map.':
      'Для отображения на карте нужен доступ к геопозиции.',
  'Location permission is needed to use your current position.':
      'Для использования текущего места нужен доступ к геопозиции.',
  'Log in before adding a police mark.':
      'Войдите в аккаунт перед добавлением отметки полиции.',
  'Log in before confirming a police mark.':
      'Войдите в аккаунт перед подтверждением отметки полиции.',
  'Log in before finding friends.': 'Войдите в аккаунт для поиска друзей.',
  'Log in before liking comments.':
      'Войдите в аккаунт, чтобы лайкать комментарии.',
  'Log in before liking spots.': 'Войдите в аккаунт, чтобы лайкать споты.',
  'Log in before sharing your live location.':
      'Войдите в аккаунт для показа геопозиции.',
  'Log in before sharing your location.':
      'Войдите в аккаунт для отправки геопозиции.',
  'Log in before using chat.': 'Войдите в аккаунт для использования чата.',
  'Log in before using friend requests.':
      'Войдите в аккаунт для использования заявок в друзья.',
  'Log in before using friends.': 'Войдите в аккаунт для просмотра друзей.',
  'Map filters': 'Фильтры карты',
  'Mark police at your current location for 2 hours.':
      'Отметить полицию в текущем месте на 2 часа.',
  'Maximum 4 photos per spot.': 'Максимум 4 фотографии на один спот.',
  'Maximum 4 spot photos.': 'Максимум 4 фотографии спота.',
  'Members': 'Участники',
  'Messages with friends and groups': 'Сообщения с друзьями и группами',
  'Moderators cannot manage other moderators.':
      'Модераторы не могут управлять другими модераторами.',
  'Move down': 'Переместить вниз',
  'Move up': 'Переместить вверх',
  'My submissions': 'Мои заявки',
  'NOW': 'СЕЙЧАС',
  'No answer. Live location will stop automatically in 10 minutes.':
      'Ответа нет. Показ геопозиции остановится через 10 минут.',
  'No comments yet. Be the first to comment on this spot.':
      'Комментариев пока нет. Оставьте первый комментарий.',
  'No link added for this spot.': 'Для этого спота ссылка не добавлена.',
  'No submitted spots yet.': 'Отправленных спотов пока нет.',
  'No tags yet': 'Тегов пока нет',
  'No users available to add.': 'Нет доступных пользователей для добавления.',
  'No users found.': 'Пользователи не найдены.',
  'Nothing here yet.': 'Здесь пока ничего нет.',
  'Only the assigned owner or an admin can edit this spot.':
      'Редактировать спот может только владелец или администратор.',
  'Only verified users and admins can see this spot after approval':
      'После одобрения спот увидят только проверенные пользователи и администраторы',
  'Photo picker is not connected in Android native code.':
      'Выбор фото не подключён в Android.',
  'Pick at least one friend for a group.':
      'Выберите хотя бы одного друга для группы.',
  'Pin up to 3 direct chats and 3 groups. Use arrows to change pinned order.':
      'Закрепите до 3 личных чатов и 3 групп. Порядок меняется стрелками.',
  'Police': 'Полиция',
  'Police mark removed from the map.': 'Отметка полиции удалена с карты.',
  'Police marked on the map for 2 hours.':
      'Полиция отмечена на карте на 2 часа.',
  'Police nearby': 'Полиция поблизости',
  'SOS': 'SOS',
  'Help request': 'Запрос помощи',
  'Need help': 'Нужна помощь',
  'Ask nearby drivers for help.': 'Попросить водителей рядом о помощи.',
  'Describe what happened and what help you need.':
      'Опишите, что случилось и какая помощь нужна.',
  'What happened?': 'Что случилось?',
  'Create SOS': 'Создать SOS',
  'SOS added on the map.': 'SOS добавлен на карту.',
  'SOS removed from the map.': 'SOS удалён с карты.',
  'Still need help?': 'Всё ещё нужна помощь?',
  'You moved away from your SOS point. Do you still need help there?':
      'Вы отъехали от точки SOS. Помощь там ещё нужна?',
  'SOS reason battery': 'Сел аккумулятор',
  'SOS reason tire': 'Прокол колеса',
  'SOS reason fuel': 'Закончилось топливо',
  'SOS reason towing': 'Нужна буксировка',
  'SOS reason breakdown': 'Поломка',
  'SOS reason other': 'Другое',
  'Choose SOS reason': 'Выберите причину SOS',
  'Only one active SOS is allowed.': 'Можно создать только один активный SOS.',
  'Close your current SOS before creating a new one.':
      'Закройте текущий SOS перед созданием нового.',
  'Close the current SOS or wait one minute before creating another one.':
      'Закройте текущий SOS или подождите одну минуту перед созданием нового.',
  'Description looks like spam. Please write clearly what happened.':
      'Описание похоже на спам. Напишите понятно, что случилось.',
  'Police already marked nearby.': 'Полиция уже отмечена рядом.',
  'In this area police is already marked.':
      'В этом районе полиция уже отмечена.',
  'No, remove': 'Нет, удалить',
  'Yes, still need': 'Да, нужна',
  'Open Waze': 'Открыть Waze',
  'Write message': 'Написать',
  'Profile saved to your account.': 'Профиль сохранён в аккаунте.',
  'Rating saved.': 'Оценка сохранена.',
  'Remember me': 'Запомнить меня',
  'Remove owner': 'Убрать владельца',
  'Requests': 'Заявки',
  'Requests you send will appear here until accepted.':
      'Отправленные заявки будут здесь до принятия.',
  'Selected owner': 'Выбранный владелец',
  'Send the first message.': 'Отправьте первое сообщение.',
  'Sent requests': 'Отправленные заявки',
  'Service info updated.': 'Данные сервиса обновлены.',
  'Share live location': 'Поделиться геопозицией в реальном времени',
  'Share live location?': 'Поделиться геопозицией?',
  'You are about to share your live location. People who have access to this share will be able to see you on the map until sharing expires or you stop it.':
      'Вы собираетесь поделиться своей геопозицией. Пользователи, у которых есть доступ к этой отправке, смогут видеть вас на карте до окончания времени или пока вы не остановите показ.',
  "Don't show again": 'Больше не показывать',
  'Choose sharing duration': 'Выберите длительность показа',
  '1 hour': '1 час',
  '2 hours': '2 часа',
  '4 hours': '4 часа',
  'Share location': 'Поделиться геопозицией',
  'Short description': 'Краткое описание',
  'Sign in with Google before submitting a spot.':
      'Войдите через Google перед отправкой спота.',
  'Spot approved. It is now public.': 'Спот одобрен и теперь опубликован.',
  'Spot deleted.': 'Спот удалён.',
  'Spot name and description are required.':
      'Добавьте название и описание спота.',
  'Spot name can use only English or Latvian letters, numbers, spaces, and simple punctuation.':
      'Название может содержать латинские или латышские буквы, цифры, пробелы и простую пунктуацию.',
  'Spot name is required.': 'Добавьте название спота.',
  'Spot rejected.': 'Спот отклонён.',
  'Start a chat with a friend or create a group.':
      'Начните чат с другом или создайте группу.',
  'Submissions': 'Заявки',
  'Tap the map where this car spot should be placed.':
      'Нажмите на карту в месте расположения спота.',
  'Tap to change avatar': 'Нажмите, чтобы изменить аватар',
  'Tell people about your car, build, setup, and plans':
      'Расскажите об автомобиле, доработках и планах',
  'Temporary spot': 'Временный спот',
  'Temporary spot can be active for 12 hours maximum.':
      'Временный спот может быть активен не более 12 часов.',
  'Temporary spot end time must be after start time.':
      'Временный спот должен закончиться после начала.',
  'Temporary spots and events': 'Временные споты и события',
  'Temporary spots can be active for maximum 12 hours.':
      'Временные споты могут быть активны не более 12 часов.',
  'This chat has no one to share location with.':
      'В этом чате не с кем поделиться геопозицией.',
  'This driver has not shared car builds yet.':
      'Этот водитель пока не опубликовал автомобили.',
  'This driver keeps their profile private.':
      'У этого водителя закрытый профиль.',
  'This link is not valid yet.': 'Ссылка пока недействительна.',
  'This message will be deleted from the chat.':
      'Сообщение будет удалено из чата.',
  'This user profile is not available anymore.': 'Профиль больше недоступен.',
  'Try searching by nickname or name.':
      'Попробуйте поиск по никнейму или имени.',
  'Turn on phone location first.': 'Сначала включите геопозицию на телефоне.',
  'Turn on phone location to show distance.':
      'Включите геопозицию, чтобы увидеть расстояние.',
  'Turn on phone location to use your current position.':
      'Включите геопозицию, чтобы использовать текущее место.',
  'Upcoming': 'Предстоящие',
  'Upload at least 1 photo before creating the spot.':
      'Загрузите хотя бы одну фотографию перед созданием спота.',
  'Use Find Users to send your first friend request.':
      'Используйте поиск, чтобы отправить первую заявку в друзья.',
  'Use photo': 'Использовать фото',
  'Use this Location': 'Использовать это место',
  'Use this for meets and events. Maximum active time is 12 hours.':
      'Используйте для встреч и событий. Максимальное время: 12 часов.',
  'User deleted.': 'Пользователь удалён.',
  'User unbanned.': 'Блокировка пользователя снята.',
  'Users will appear here after they sign in.':
      'Пользователи появятся здесь после входа.',
  'Verified users can create and see verified-only spots.':
      'Проверенные пользователи могут создавать и видеть закрытые споты.',
  'Video link': 'Ссылка на видео',
  'What is this group about?': 'О чём эта группа?',
  'What makes this spot good for car photos?':
      'Чем хорош этот спот для автомобильных фотографий?',
  'Write a comment first.': 'Сначала напишите комментарий.',
  'You cannot manage your own account here.':
      'Здесь нельзя управлять собственным аккаунтом.',
  'You created this mark. You can confirm it later if you drive by this spot again.':
      'Вы создали эту отметку. Подтвердить её можно позже, проехав рядом снова.',
  'Your created spots are saved here. Pending spots wait for review; live spots are already public.':
      'Созданные споты хранятся здесь. Заявки ждут проверки, опубликованные уже видны всем.',
  'Your live location has been shared for 1 hour. Keep sharing it for another hour?':
      'Геопозиция показывается уже час. Продолжить ещё на час?',
  'Your profile nickname': 'Ваш никнейм',
  'Your rating': 'Ваша оценка',
  'edited': 'изменено',
  'New': 'Новые',
  'Old': 'Старые',
  'Like': 'Лайк',
  'Liked': 'Лайкнуто',
  'Create Spot': 'Создать спот',
  'Creating spot...': 'Создаём спот...',
  'Submit for Review': 'Отправить на проверку',
  'Submitting for review...': 'Отправляем на проверку...',
  'Choose the spot on map': 'Выберите спот на карте',
  'Spot location selected on map': 'Место спота выбрано на карте',
  'Type an address and place the pin automatically':
      'Введите адрес, и метка поставится автоматически',
  'Use your phone GPS position': 'Использовать GPS телефона',
  'Replace pin with your current GPS position':
      'Заменить метку текущей геопозицией',
  'Getting your GPS position...': 'Получаем вашу GPS-позицию...',
  'Detecting city/country...': 'Определяем город/страну...',
  'Checking distance...': 'Проверяем расстояние...',
  'Distance unavailable': 'Расстояние недоступно',
  'Open route': 'Открыть маршрут',
  'Add up to 4 spot photos. The first photo becomes the Explore thumbnail.':
      'Добавьте до 4 фото спота. Первое фото станет обложкой в ленте.',
  'Maximum 4 photos selected. First photo is the spot thumbnail.':
      'Выбрано максимум 4 фото. Первое фото — обложка спота.',
  'Saved spots will appear here.': 'Сохранённые споты появятся здесь.',
  'Review spots and manage users':
      'Проверка спотов и управление пользователями',
  'Save Changes': 'Сохранить изменения',
  'Drift': 'Дрифт',
  'No video link added': 'Ссылка на видео не добавлена',
  'Sunday is marked as closed.': 'Воскресенье отмечено как выходной.',
  'Sign out': 'Выйти',
  'Signing out...': 'Выход...',
  'Add': 'Добавить',
  'Friend': 'Друг',
  'Driver': 'Водитель',
  'Group share': 'Группа',
  'Chat share': 'Чат',
  'Friends share': 'Друзья',
  'online': 'в сети',
  'offline': 'не в сети',
  'Shared live location with this group.':
      'Геопозиция отправлена в эту группу.',
  'Shared live location with you.': 'Геопозиция отправлена вам.',
  'Location shared with this group for 1 hour.':
      'Геопозиция опубликована в группе на 1 час.',
  'Location shared with this chat for 1 hour.':
      'Геопозиция опубликована в чате на 1 час.',
  'Updated': 'Обновлено',
  'Live location': 'Геопозиция онлайн',
  'Admin Panel': 'Админ-панель',
  'Moderator Panel': 'Панель модератора',
  'Review spots and moderate users':
      'Проверка спотов и модерация пользователей',
  'Pending': 'На проверке',
  'Edited': 'Изменённые',
  'Approved': 'Одобренные',
  'Rejected': 'Отклонённые',
  'All': 'Все',
  'pending': 'на проверке',
  'approved': 'одобрен',
  'rejected': 'отклонён',
  'live': 'активно',
  'No pending spots': 'Нет спотов на проверке',
  'No edited spots': 'Нет изменённых спотов',
  'No approved spots': 'Нет одобренных спотов',
  'No rejected spots': 'Нет отклонённых спотов',
  'No community spots yet': 'Спотов сообщества пока нет',
  'New user submitted spots will appear here first.':
      'Новые споты от пользователей сначала появятся здесь.',
  'User spot edits will appear here for approval.':
      'Изменения спотов от пользователей появятся здесь для одобрения.',
  'Rejected spots will appear here after moderation.':
      'Отклонённые споты появятся здесь после модерации.',
  'When users submit spots, they will appear in this admin panel.':
      'Когда пользователи отправят споты, они появятся в этой админ-панели.',
  'Direct chats': 'Личные чаты',
  'No direct chats yet.': 'Личных чатов пока нет.',
  'No groups yet.': 'Групп пока нет.',
  'Sent': 'Отправлено',
  'Friend request': 'Заявка в друзья',
  'This is your current nickname.': 'Это ваш текущий никнейм.',
  'Checking nickname availability...': 'Проверяем доступность никнейма...',
  'Nickname is available.': 'Никнейм свободен.',
  'This nickname is already taken.': 'Этот никнейм уже занят.',
  'Nickname must be at least 3 characters.':
      'Никнейм должен быть минимум 3 символа.',
  'Could not check nickname availability.': 'Не удалось проверить никнейм.',
  'Untitled car': 'Автомобиль без названия',
  'Car profile.': 'Описание автомобиля.',
  'Spot saved.': 'Спот сохранён.',
  'Spot removed from saved.': 'Спот удалён из сохранённых.',
  'Comment': 'Комментарии',
  'Add or remove spot photos. The first photo becomes the Explore thumbnail.':
      'Добавьте или удалите фото спота. Первое фото станет обложкой в ленте.',
  'Description placeholder': 'Описание',
  'Notification center could not load.': 'Не удалось загрузить уведомления.',
  'Push notifications are connected through Firebase Cloud Messaging.':
      'Уведомления подключены через Firebase Cloud Messaging.',
  'you': 'вы',
  'Yesterday': 'Вчера',
  'Temporary event': 'Временный ивент',
  'Temporary events': 'Временные ивенты',
};

const _lvText = <String, String>{
  'Spots': 'Vietas',
  'Map': 'Karte',
  'Add Spot': 'Pievienot vietu',
  'Chat': 'Čats',
  'Profile': 'Profils',
  'Settings': 'Iestatījumi',
  'Notifications': 'Paziņojumi',
  'Privacy': 'Privātums',
  'Appearance': 'Izskats',
  'Light theme': 'Gaišais režīms',
  'Use a brighter interface throughout the app':
      'Izmantot gaišāku saskarni visā lietotnē',
  'Language': 'Valoda',
  'Recent notifications': 'Jaunākie paziņojumi',
  'Project news': 'Projekta jaunumi',
  'No notifications yet': 'Paziņojumu vēl nav',
  'Your latest CCS updates will appear here.':
      'Šeit parādīsies jaunākie CCS atjauninājumi.',
  'CCS notification center is ready.': 'CCS paziņojumu centrs ir gatavs.',
  'Refresh': 'Atjaunot',
  'Retry': 'Mēģināt vēlreiz',
  'Approved car spots': 'Apstiprinātas auto vietas',
  'Filters': 'Filtri',
  'Explore filters': 'Vietu filtri',
  'All categories enabled': 'Ieslēgtas visas kategorijas',
  'Select all': 'Izvēlēties visu',
  'Clear': 'Notīrīt',
  'Apply filters': 'Lietot filtrus',
  'Popular': 'Populāri',
  'Newest': 'Jaunākie',
  'Oldest': 'Vecākie',
  'Meet spots': 'Tikšanās',
  'Saved': 'Saglabātie',
  'Show less': 'Rādīt mazāk',
  'Saved Spots': 'Saglabātās vietas',
  'No saved spots yet': 'Saglabātu vietu vēl nav',
  'No spots here yet': 'Šeit vietu vēl nav',
  'No spots match your filters': 'Filtriem neatbilst neviena vieta',
  'Tap the bookmark on a spot to keep it here.':
      'Nospiediet grāmatzīmi, lai saglabātu vietu.',
  'Approved spots will appear here after moderation.':
      'Apstiprinātās vietas šeit parādīsies pēc moderācijas.',
  'Open filters and enable more categories to see more spots.':
      'Atveriet filtrus un ieslēdziet papildu kategorijas.',
  'Spot review updates': 'Vietu pārbaudes rezultāti',
  'Approved or rejected spot submissions':
      'Apstiprinātas vai noraidītas vietas',
  'Likes on my spots': 'Patīk manām vietām',
  'When people like your approved spots': 'Kad lietotāji novērtē jūsu vietas',
  'Comments': 'Komentāri',
  'Future comments and community replies': 'Jauni komentāri un atbildes',
  'New spots': 'Jaunas vietas',
  'Fresh approved locations nearby': 'Jaunas apstiprinātas vietas tuvumā',
  'Messages': 'Ziņas',
  'New direct and group messages': 'Jaunas privātās un grupu ziņas',
  'Public profile': 'Publisks profils',
  'Let other drivers see your profile':
      'Ļaut citiem autovadītājiem redzēt profilu',
  'Show garage': 'Rādīt garāžu',
  'Display your car builds on your profile': 'Rādīt automašīnas profilā',
  'Save Settings': 'Saglabāt iestatījumus',
  'Settings saved to your account.': 'Konta iestatījumi saglabāti.',
  'Add Car': 'Pievienot auto',
  'Edit Garage': 'Mainīt garāžu',
  'Car photos': 'Auto fotogrāfijas',
  'Car info': 'Informācija par auto',
  'Car name': 'Auto nosaukums',
  'Description': 'Apraksts',
  'Add up to 4 car photos. The first photo becomes the garage cover.':
      'Pievienojiet līdz 4 fotogrāfijām. Pirmā būs garāžas vāks.',
  'Upload photos': 'Augšupielādēt fotogrāfijas',
  'Cover': 'Vāks',
  'Save Garage': 'Saglabāt garāžu',
  'Photo': 'Foto',
  'Meet': 'Tikšanās',
  'Drive': 'Braucieni',
  'Service': 'Serviss',
  'Detailing': 'Detalizēšana',
  'Wash': 'Mazgātava',
  'Store': 'Veikals',
  'Drag': 'Drags',
  'Off-road': 'Bezceļi',
  'Food': 'Ēdiens',
  'Today': 'Šodien',
  'Tomorrow': 'Rīt',
  'This week': 'Šonedēļ',
  'Next week': 'Nākamnedēļ',
  'This month': 'Šomēnes',
  'Next month': 'Nākamajā mēnesī',
  'Write a comment': 'Rakstiet komentāru',
  'Post Comment': 'Publicēt',
  'Posting...': 'Publicē...',
  'Message': 'Ziņa',
  'Save Spot': 'Saglabāt vietu',
  'Saved Spot': 'Vieta saglabāta',
  'View Spot': 'Atvērt vietu',
  'View Profile': 'Atvērt profilu',
  'Edit Profile': 'Mainīt profilu',
  'Adjust Photo': 'Pielāgot foto',
  'Use Photo': 'Izmantot foto',
  'Saving...': 'Saglabā...',
  'Monday': 'Pirmdiena',
  'Tuesday': 'Otrdiena',
  'Wednesday': 'Trešdiena',
  'Thursday': 'Ceturtdiena',
  'Friday': 'Piektdiena',
  'Saturday': 'Sestdiena',
  'Sunday': 'Svētdiena',
  'Just now': 'Tikko',
  'Stop sharing': 'Pārtraukt kopīgošanu',
  'Not there': 'Vairs nav',
  'Still there': 'Joprojām tur',
  'Live now': 'Tiešsaistē',
  'Spot': 'Vieta',
  'Show on map': 'Rādīt kartē',
  'Edit Service Info': 'Rediģēt servisa informāciju',
  'Hours not added': 'Darba laiks nav pievienots',
  'The owner has not added opening hours yet.':
      'Īpašnieks vēl nav pievienojis darba laiku.',
  'Closed today': 'Šodien slēgts',
  'Hours need update': 'Jāatjaunina darba laiks',
  'Opening hours are not formatted correctly.':
      'Darba laiks nav norādīts pareizi.',
  'Open now': 'Tagad atvērts',
  'Closed now': 'Tagad slēgts',
  'Phone': 'Tālrunis',
  'Instagram': 'Instagram',
  'Email': 'E-pasts',
  'Cancel': 'Atcelt',
  'Save': 'Saglabāt',
  'Delete': 'Dzēst',
  'Find exact address': 'Atrast precīzu adresi',
  'Street, city, country': 'Iela, pilsēta, valsts',
  'Find': 'Atrast',
  'Basic info': 'Pamatinformācija',
  'Spot name': 'Vietas nosaukums',
  'Pin on the map': 'Atzīmēt kartē',
  'Use current location': 'Izmantot pašreizējo atrašanās vietu',
  'Visibility': 'Redzamība',
  'Verified only': 'Tikai verificētiem lietotājiem',
  'Temporary schedule': 'Pagaidu grafiks',
  'Categories': 'Kategorijas',
  'Contacts': 'Kontakti',
  'Opening hours': 'Darba laiks',
  'Media': 'Multivide',
  'Instagram / TikTok video link': 'Instagram / TikTok video saite',
  'Added by': 'Pievienoja',
  'Starts at': 'Sākas',
  'Ends at': 'Beidzas',
  'Choose Location': 'Izvēlēties vietu',
  'Service Info': 'Servisa informācija',
  'My Submissions': 'Mani pieteikumi',
  'No submissions yet': 'Pieteikumu vēl nav',
  'Log in required': 'Nepieciešama pieslēgšanās',
  'Chats': 'Čati',
  'Groups': 'Grupas',
  'No chats yet': 'Čatu vēl nav',
  'Edit Chat View': 'Rediģēt čata skatu',
  'New Chat': 'Jauns čats',
  'Direct': 'Privāts',
  'Group': 'Grupa',
  'Find friend': 'Atrast draugu',
  'Group name': 'Grupas nosaukums',
  'No friends found': 'Draugi nav atrasti',
  'owner': 'īpašnieks',
  'moderator': 'moderators',
  'Group Info': 'Grupas informācija',
  'Group description': 'Grupas apraksts',
  'Save Group': 'Saglabāt grupu',
  'No messages yet': 'Ziņu vēl nav',
  'Friends': 'Draugi',
  'Send requests, accept invites, and manage friends':
      'Sūtiet pieprasījumus, pieņemiet ielūgumus un pārvaldiet draugus',
  'Add another car': 'Pievienot auto',
  'Add another car to your garage': 'Pievienot vēl vienu auto garāžai',
  'Account, privacy, notifications': 'Konts, privātums, paziņojumi',
  'Log out of this Google account': 'Izrakstīties no Google konta',
  'Cars': 'Auto',
  'Base': 'Pilsēta',
  'Verified': 'Verificēts',
  'No garage shared': 'Garāža nav publicēta',
  'Profile not found': 'Profils nav atrasts',
  'Profile deleted': 'Profils ir dzēsts',
  'Private profile': 'Privāts profils',
  'No friends yet': 'Draugu vēl nav',
  'Remove': 'Noņemt',
  'No incoming requests': 'Nav ienākošo pieprasījumu',
  'Accept': 'Pieņemt',
  'Decline': 'Noraidīt',
  'No sent requests': 'Nav nosūtītu pieprasījumu',
  'nickname or name': 'segvārds vai vārds',
  'No users found': 'Lietotāji nav atrasti',
  'Profile info': 'Profila informācija',
  'Nickname': 'Segvārds',
  'About you': 'Par jums',
  'Social links': 'Sociālie tīkli',
  'Save Profile': 'Saglabāt profilu',
  'Verified Users': 'Verificētie lietotāji',
  'No users yet': 'Lietotāju vēl nav',
  'Delete user?': 'Dzēst lietotāju?',
  'Open profile': 'Atvērt profilu',
  'Ban 1 day': 'Bloķēt uz 1 dienu',
  'Ban 7 days': 'Bloķēt uz 7 dienām',
  'Ban 30 days': 'Bloķēt uz 30 dienām',
  'Ban forever': 'Bloķēt uz visiem laikiem',
  'Unban': 'Atbloķēt',
  'Make moderator': 'Iecelt par moderatoru',
  'Remove moderator': 'Noņemt moderatoru',
  'Users': 'Lietotāji',
  'Open profiles, ban, unban, or delete users':
      'Atveriet profilus, bloķējiet vai dzēsiet lietotājus',
  'Grant or remove verified status': 'Piešķiriet vai noņemiet verifikāciju',
  'Edit Spot': 'Rediģēt vietu',
  'City / country': 'Pilsēta / valsts',
  'Latitude': 'Platums',
  'Longitude': 'Garums',
  'Category': 'Kategorija',
  'Photos': 'Fotogrāfijas',
  'Manage Spot': 'Pārvaldīt vietu',
  'Reject': 'Noraidīt',
  'Approve': 'Apstiprināt',
  'Delete Spot': 'Dzēst vietu',
  'Write a comment about this spot': 'Rakstiet komentāru par šo vietu',
  'Edit your comment': 'Rediģējiet komentāru',
  'Search users': 'Meklēt lietotājus',
  'Spot owner': 'Vietas īpašnieks',
  'Search nickname, name, or email': 'Meklēt pēc segvārda, vārda vai e-pasta',
  'Search to change owner': 'Meklēt jaunu īpašnieku',
  'Add friends first, then start a chat here.':
      'Vispirms pievienojiet draugus, pēc tam sāciet čatu.',
  'Add map alert': 'Pievienot brīdinājumu kartē',
  'Add members': 'Pievienot dalībniekus',
  'Address not found. Try adding city and country.':
      'Adrese nav atrasta. Pievienojiet pilsētu un valsti.',
  'Admin accounts cannot be managed here.':
      'Administratoru kontus šeit nevar pārvaldīt.',
  'Admins publish instantly. User spots wait for review.':
      'Administratoru vietas publicē uzreiz. Citas vietas gaida pārbaudi.',
  'Approved spots': 'Apstiprinātās vietas',
  'Are you sure you want to delete this comment?':
      'Vai tiešām vēlaties dzēst komentāru?',
  'By continuing, you agree to our Terms & Privacy Policy':
      'Turpinot jūs piekrītat noteikumiem un privātuma politikai',
  'Car added to your account.': 'Auto pievienots kontam.',
  'Choose both start and end time for a temporary spot.':
      'Izvēlieties pagaidu vietas sākuma un beigu laiku.',
  'Closed': 'Slēgts',
  'Comment deleted.': 'Komentārs dzēsts.',
  'Comment posted.': 'Komentārs publicēts.',
  'Comment updated.': 'Komentārs atjaunināts.',
  'Continue sharing': 'Turpināt kopīgošanu',
  'Continue sharing?': 'Turpināt kopīgošanu?',
  'Could not open this contact.': 'Neizdevās atvērt kontaktu.',
  'Could not open this link.': 'Neizdevās atvērt saiti.',
  'Created spots will appear here.': 'Izveidotās vietas parādīsies šeit.',
  'Current location selected for this spot.':
      'Vietai izvēlēta pašreizējā atrašanās vieta.',
  'Delete comment': 'Dzēst komentāru',
  'Delete message': 'Dzēst ziņu',
  'Delete message?': 'Dzēst ziņu?',
  'Delete spot': 'Dzēst vietu',
  'Delete spot?': 'Dzēst vietu?',
  'Delete user': 'Dzēst lietotāju',
  'Description is required.': 'Pievienojiet aprakstu.',
  'Edit comment': 'Rediģēt komentāru',
  'Edit message': 'Rediģēt ziņu',
  'Edit spot': 'Rediģēt vietu',
  'End time must be after start time.': 'Beigu laikam jābūt pēc sākuma laika.',
  'End time must be in the future.': 'Beigu laikam jābūt nākotnē.',
  'Enter valid latitude and longitude.': 'Ievadiet derīgas koordinātas.',
  'Friend invites sent to you will appear here.':
      'Šeit parādīsies saņemtie draudzības uzaicinājumi.',
  'Garage saved to your account.': 'Garāža saglabāta kontā.',
  'Garage tags': 'Garāžas birkas',
  'Get closer to this police mark before confirming it.':
      'Piebrauciet tuvāk policijas atzīmei, lai to apstiprinātu.',
  'Grant verified status': 'Piešķirt verificētu statusu',
  'Group info': 'Grupas informācija',
  'Incoming requests': 'Saņemtie pieprasījumi',
  'Live location sharing is on for 1 hour.':
      'Atrašanās vietas kopīgošana ieslēgta uz 1 stundu.',
  'Loading users...': 'Ielādē lietotājus...',
  'Location is required. Pin it on the map, find exact address, or use current location first.':
      'Atzīmējiet vietu kartē, atrodiet adresi vai izmantojiet pašreizējo atrašanās vietu.',
  'Location permission is needed for distance.':
      'Attāluma noteikšanai vajadzīga piekļuve atrašanās vietai.',
  'Location permission is needed to share your location.':
      'Atrašanās vietas nosūtīšanai vajadzīga piekļuve tai.',
  'Location permission is needed to show you on the map.':
      'Attēlošanai kartē vajadzīga piekļuve atrašanās vietai.',
  'Location permission is needed to use your current position.':
      'Pašreizējās pozīcijas izmantošanai vajadzīga piekļuve atrašanās vietai.',
  'Log in before adding a police mark.':
      'Pieslēdzieties pirms policijas atzīmes pievienošanas.',
  'Log in before confirming a police mark.':
      'Pieslēdzieties pirms policijas atzīmes apstiprināšanas.',
  'Log in before finding friends.': 'Pieslēdzieties, lai meklētu draugus.',
  'Log in before liking comments.': 'Pieslēdzieties, lai novērtētu komentārus.',
  'Log in before liking spots.': 'Pieslēdzieties, lai novērtētu vietas.',
  'Log in before sharing your live location.':
      'Pieslēdzieties, lai kopīgotu atrašanās vietu.',
  'Log in before sharing your location.':
      'Pieslēdzieties, lai nosūtītu atrašanās vietu.',
  'Log in before using chat.': 'Pieslēdzieties, lai izmantotu čatu.',
  'Log in before using friend requests.':
      'Pieslēdzieties, lai izmantotu draudzības pieprasījumus.',
  'Log in before using friends.': 'Pieslēdzieties, lai skatītu draugus.',
  'Map filters': 'Kartes filtri',
  'Mark police at your current location for 2 hours.':
      'Atzīmēt policiju pašreizējā vietā uz 2 stundām.',
  'Maximum 4 photos per spot.': 'Maksimums 4 fotogrāfijas vienai vietai.',
  'Maximum 4 spot photos.': 'Maksimums 4 vietas fotogrāfijas.',
  'Members': 'Dalībnieki',
  'Messages with friends and groups': 'Ziņas ar draugiem un grupām',
  'Moderators cannot manage other moderators.':
      'Moderatori nevar pārvaldīt citus moderatorus.',
  'Move down': 'Pārvietot lejup',
  'Move up': 'Pārvietot augšup',
  'My submissions': 'Mani pieteikumi',
  'NOW': 'TAGAD',
  'No answer. Live location will stop automatically in 10 minutes.':
      'Atbildes nav. Atrašanās vietas kopīgošana beigsies pēc 10 minūtēm.',
  'No comments yet. Be the first to comment on this spot.':
      'Komentāru vēl nav. Pievienojiet pirmo komentāru.',
  'No link added for this spot.': 'Šai vietai nav pievienota saite.',
  'No submitted spots yet.': 'Iesniegtu vietu vēl nav.',
  'No tags yet': 'Birku vēl nav',
  'No users available to add.': 'Nav pieejamu lietotāju pievienošanai.',
  'No users found.': 'Lietotāji nav atrasti.',
  'Nothing here yet.': 'Šeit vēl nekā nav.',
  'Only the assigned owner or an admin can edit this spot.':
      'Vietu var rediģēt tikai īpašnieks vai administrators.',
  'Only verified users and admins can see this spot after approval':
      'Pēc apstiprināšanas vietu redzēs tikai verificēti lietotāji un administratori',
  'Photo picker is not connected in Android native code.':
      'Foto izvēle nav pieslēgta Android lietotnei.',
  'Pick at least one friend for a group.':
      'Izvēlieties vismaz vienu draugu grupai.',
  'Pin up to 3 direct chats and 3 groups. Use arrows to change pinned order.':
      'Piespraudiet līdz 3 privātiem čatiem un 3 grupām. Secību mainiet ar bultiņām.',
  'Police': 'Policija',
  'Police mark removed from the map.': 'Policijas atzīme noņemta no kartes.',
  'Police marked on the map for 2 hours.':
      'Policija atzīmēta kartē uz 2 stundām.',
  'Police nearby': 'Policija tuvumā',
  'SOS': 'SOS',
  'Help request': 'Palīdzības pieprasījums',
  'Need help': 'Vajadzīga palīdzība',
  'Ask nearby drivers for help.':
      'Palūgt palīdzību tuvumā esošajiem autovadītājiem.',
  'Describe what happened and what help you need.':
      'Aprakstiet, kas notika un kāda palīdzība vajadzīga.',
  'What happened?': 'Kas notika?',
  'Create SOS': 'Izveidot SOS',
  'SOS added on the map.': 'SOS pievienots kartē.',
  'SOS removed from the map.': 'SOS noņemts no kartes.',
  'Still need help?': 'Palīdzība vēl vajadzīga?',
  'You moved away from your SOS point. Do you still need help there?':
      'Jūs aizbraucāt no SOS vietas. Vai palīdzība tur vēl ir vajadzīga?',
  'SOS reason battery': 'Izlādējies akumulators',
  'SOS reason tire': 'Pārdurta riepa',
  'SOS reason fuel': 'Beigusies degviela',
  'SOS reason towing': 'Nepieciešama vilkšana',
  'SOS reason breakdown': 'Bojājums',
  'SOS reason other': 'Cits',
  'Choose SOS reason': 'Izvēlieties SOS iemeslu',
  'Only one active SOS is allowed.': 'Atļauts tikai viens aktīvs SOS.',
  'Close your current SOS before creating a new one.':
      'Aizveriet pašreizējo SOS pirms jauna izveides.',
  'Close the current SOS or wait one minute before creating another one.':
      'Aizveriet pašreizējo SOS vai uzgaidiet vienu minūti pirms jauna izveides.',
  'Description looks like spam. Please write clearly what happened.':
      'Apraksts izskatās pēc spama. Uzrakstiet skaidri, kas notika.',
  'Police already marked nearby.': 'Policija jau ir atzīmēta tuvumā.',
  'In this area police is already marked.':
      'Šajā rajonā policija jau ir atzīmēta.',
  'No, remove': 'Nē, noņemt',
  'Yes, still need': 'Jā, vajag',
  'Open Waze': 'Atvērt Waze',
  'Write message': 'Rakstīt',
  'Profile saved to your account.': 'Profils saglabāts kontā.',
  'Rating saved.': 'Vērtējums saglabāts.',
  'Remember me': 'Atcerēties mani',
  'Remove owner': 'Noņemt īpašnieku',
  'Requests': 'Pieprasījumi',
  'Requests you send will appear here until accepted.':
      'Nosūtītie pieprasījumi būs šeit līdz apstiprināšanai.',
  'Selected owner': 'Izvēlētais īpašnieks',
  'Send the first message.': 'Nosūtiet pirmo ziņu.',
  'Sent requests': 'Nosūtītie pieprasījumi',
  'Service info updated.': 'Servisa informācija atjaunināta.',
  'Share live location': 'Kopīgot atrašanās vietu tiešsaistē',
  'Share live location?': 'Kopīgot atrašanās vietu tiešsaistē?',
  'You are about to share your live location. People who have access to this share will be able to see you on the map until sharing expires or you stop it.':
      'Jūs gatavojaties kopīgot savu atrašanās vietu tiešsaistē. Lietotāji, kuriem ir piekļuve šai kopīgošanai, varēs redzēt jūs kartē līdz kopīgošanas beigām vai līdz brīdim, kad to apturēsiet.',
  "Don't show again": 'Vairs nerādīt',
  'Choose sharing duration': 'Izvēlieties kopīgošanas ilgumu',
  '1 hour': '1 stunda',
  '2 hours': '2 stundas',
  '4 hours': '4 stundas',
  'Share location': 'Kopīgot atrašanās vietu',
  'Short description': 'Īss apraksts',
  'Sign in with Google before submitting a spot.':
      'Pieslēdzieties ar Google pirms vietas iesniegšanas.',
  'Spot approved. It is now public.':
      'Vieta apstiprināta un tagad ir publiska.',
  'Spot deleted.': 'Vieta dzēsta.',
  'Spot name and description are required.':
      'Pievienojiet vietas nosaukumu un aprakstu.',
  'Spot name can use only English or Latvian letters, numbers, spaces, and simple punctuation.':
      'Nosaukumā drīkst izmantot angļu vai latviešu burtus, ciparus, atstarpes un vienkāršas pieturzīmes.',
  'Spot name is required.': 'Pievienojiet vietas nosaukumu.',
  'Spot rejected.': 'Vieta noraidīta.',
  'Start a chat with a friend or create a group.':
      'Sāciet čatu ar draugu vai izveidojiet grupu.',
  'Submissions': 'Pieteikumi',
  'Tap the map where this car spot should be placed.':
      'Nospiediet kartē vietā, kur jāatrodas auto vietai.',
  'Tap to change avatar': 'Nospiediet, lai mainītu avatāru',
  'Tell people about your car, build, setup, and plans':
      'Pastāstiet par auto, uzlabojumiem un plāniem',
  'Temporary spot': 'Pagaidu vieta',
  'Temporary spot can be active for 12 hours maximum.':
      'Pagaidu vieta var būt aktīva ne ilgāk par 12 stundām.',
  'Temporary spot end time must be after start time.':
      'Pagaidu vietas beigu laikam jābūt pēc sākuma laika.',
  'Temporary spots and events': 'Pagaidu vietas un pasākumi',
  'Temporary spots can be active for maximum 12 hours.':
      'Pagaidu vietas var būt aktīvas ne ilgāk par 12 stundām.',
  'This chat has no one to share location with.':
      'Šajā čatā nav neviena, ar ko kopīgot atrašanās vietu.',
  'This driver has not shared car builds yet.':
      'Šis autovadītājs vēl nav publicējis auto.',
  'This driver keeps their profile private.':
      'Šim autovadītājam ir privāts profils.',
  'This link is not valid yet.': 'Saite vēl nav derīga.',
  'This message will be deleted from the chat.': 'Ziņa tiks dzēsta no čata.',
  'This user profile is not available anymore.': 'Profils vairs nav pieejams.',
  'Try searching by nickname or name.': 'Meklējiet pēc segvārda vai vārda.',
  'Turn on phone location first.':
      'Vispirms ieslēdziet atrašanās vietu tālrunī.',
  'Turn on phone location to show distance.':
      'Ieslēdziet atrašanās vietu, lai redzētu attālumu.',
  'Turn on phone location to use your current position.':
      'Ieslēdziet atrašanās vietu, lai izmantotu pašreizējo pozīciju.',
  'Upcoming': 'Gaidāmie',
  'Upload at least 1 photo before creating the spot.':
      'Pirms vietas izveides augšupielādējiet vismaz vienu foto.',
  'Use Find Users to send your first friend request.':
      'Izmantojiet meklēšanu, lai nosūtītu pirmo draudzības pieprasījumu.',
  'Use photo': 'Izmantot foto',
  'Use this Location': 'Izmantot šo vietu',
  'Use this for meets and events. Maximum active time is 12 hours.':
      'Izmantojiet tikšanās reizēm un pasākumiem. Maksimālais laiks: 12 stundas.',
  'User deleted.': 'Lietotājs dzēsts.',
  'User unbanned.': 'Lietotājs atbloķēts.',
  'Users will appear here after they sign in.':
      'Lietotāji parādīsies šeit pēc pieslēgšanās.',
  'Verified users can create and see verified-only spots.':
      'Verificētie lietotāji var veidot un redzēt slēgtās vietas.',
  'Video link': 'Video saite',
  'What is this group about?': 'Par ko ir šī grupa?',
  'What makes this spot good for car photos?':
      'Kāpēc šī vieta ir piemērota auto fotogrāfijām?',
  'Write a comment first.': 'Vispirms uzrakstiet komentāru.',
  'You cannot manage your own account here.':
      'Šeit nevar pārvaldīt savu kontu.',
  'You created this mark. You can confirm it later if you drive by this spot again.':
      'Jūs izveidojāt šo atzīmi. To varēs apstiprināt vēlāk, vēlreiz braucot garām.',
  'Your created spots are saved here. Pending spots wait for review; live spots are already public.':
      'Izveidotās vietas glabājas šeit. Pieteikumi gaida pārbaudi, publicētās vietas jau ir redzamas.',
  'Your live location has been shared for 1 hour. Keep sharing it for another hour?':
      'Atrašanās vieta kopīgota jau stundu. Turpināt vēl vienu stundu?',
  'Your profile nickname': 'Jūsu segvārds',
  'Your rating': 'Jūsu vērtējums',
  'edited': 'rediģēts',
  'New': 'Jauni',
  'Old': 'Veci',
  'Like': 'Patīk',
  'Liked': 'Patīk',
  'Create Spot': 'Izveidot vietu',
  'Creating spot...': 'Izveido vietu...',
  'Submit for Review': 'Iesniegt pārbaudei',
  'Submitting for review...': 'Iesniedz pārbaudei...',
  'Choose the spot on map': 'Izvēlieties vietu kartē',
  'Spot location selected on map': 'Vieta izvēlēta kartē',
  'Type an address and place the pin automatically':
      'Ievadiet adresi, un atzīme tiks novietota automātiski',
  'Use your phone GPS position': 'Izmantot tālruņa GPS pozīciju',
  'Replace pin with your current GPS position':
      'Aizstāt atzīmi ar pašreizējo GPS pozīciju',
  'Getting your GPS position...': 'Iegūstam GPS pozīciju...',
  'Detecting city/country...': 'Nosakām pilsētu/valsti...',
  'Checking distance...': 'Pārbaudām attālumu...',
  'Distance unavailable': 'Attālums nav pieejams',
  'Open route': 'Atvērt maršrutu',
  'Add up to 4 spot photos. The first photo becomes the Explore thumbnail.':
      'Pievienojiet līdz 4 vietas foto. Pirmais būs vāks sarakstā.',
  'Maximum 4 photos selected. First photo is the spot thumbnail.':
      'Izvēlēti maksimums 4 foto. Pirmais foto ir vietas vāks.',
  'Saved spots will appear here.': 'Saglabātās vietas parādīsies šeit.',
  'Review spots and manage users': 'Pārbaudīt vietas un pārvaldīt lietotājus',
  'Save Changes': 'Saglabāt izmaiņas',
  'Drift': 'Drifts',
  'No video link added': 'Video saite nav pievienota',
  'Sunday is marked as closed.': 'Svētdiena ir atzīmēta kā slēgta.',
  'Sign out': 'Izrakstīties',
  'Signing out...': 'Izrakstās...',
  'Add': 'Pievienot',
  'Friend': 'Draugs',
  'Driver': 'Vadītājs',
  'Group share': 'Grupa',
  'Chat share': 'Čats',
  'Friends share': 'Draugi',
  'online': 'tiešsaistē',
  'offline': 'bezsaistē',
  'Shared live location with this group.':
      'Atrašanās vieta nosūtīta šai grupai.',
  'Shared live location with you.': 'Atrašanās vieta nosūtīta jums.',
  'Location shared with this group for 1 hour.':
      'Atrašanās vieta kopīgota grupā uz 1 stundu.',
  'Location shared with this chat for 1 hour.':
      'Atrašanās vieta kopīgota čatā uz 1 stundu.',
  'Updated': 'Atjaunināts',
  'Live location': 'Tiešraides atrašanās vieta',
  'Admin Panel': 'Admina panelis',
  'Moderator Panel': 'Moderatora panelis',
  'Review spots and moderate users': 'Pārbaudīt vietas un moderēt lietotājus',
  'Pending': 'Gaida',
  'Edited': 'Labotās',
  'Approved': 'Apstiprinātās',
  'Rejected': 'Noraidītās',
  'All': 'Visas',
  'pending': 'gaida',
  'approved': 'apstiprināts',
  'rejected': 'noraidīts',
  'live': 'aktīvs',
  'No pending spots': 'Nav vietu pārbaudei',
  'No edited spots': 'Nav labotu vietu',
  'No approved spots': 'Nav apstiprinātu vietu',
  'No rejected spots': 'Nav noraidītu vietu',
  'No community spots yet': 'Kopienas vietu vēl nav',
  'New user submitted spots will appear here first.':
      'Jaunas lietotāju vietas vispirms parādīsies šeit.',
  'User spot edits will appear here for approval.':
      'Lietotāju labojumi parādīsies šeit apstiprināšanai.',
  'Rejected spots will appear here after moderation.':
      'Noraidītās vietas parādīsies šeit pēc moderācijas.',
  'When users submit spots, they will appear in this admin panel.':
      'Kad lietotāji iesniegs vietas, tās parādīsies šajā admina panelī.',
  'Direct chats': 'Privātie čati',
  'No direct chats yet.': 'Privāto čatu vēl nav.',
  'No groups yet.': 'Grupu vēl nav.',
  'Sent': 'Nosūtīts',
  'Friend request': 'Draudzības pieprasījums',
  'This is your current nickname.': 'Šis ir jūsu pašreizējais segvārds.',
  'Checking nickname availability...': 'Pārbaudām segvārda pieejamību...',
  'Nickname is available.': 'Segvārds ir pieejams.',
  'This nickname is already taken.': 'Šis segvārds jau ir aizņemts.',
  'Nickname must be at least 3 characters.':
      'Segvārdam jābūt vismaz 3 rakstzīmēm.',
  'Could not check nickname availability.': 'Neizdevās pārbaudīt segvārdu.',
  'Untitled car': 'Auto bez nosaukuma',
  'Car profile.': 'Auto apraksts.',
  'Spot saved.': 'Vieta saglabāta.',
  'Spot removed from saved.': 'Vieta noņemta no saglabātajām.',
  'Comment': 'Komentāri',
  'Add or remove spot photos. The first photo becomes the Explore thumbnail.':
      'Pievienojiet vai noņemiet vietas foto. Pirmais foto būs vāks sarakstā.',
  'Description placeholder': 'Apraksts',
  'Notification center could not load.': 'Neizdevās ielādēt paziņojumus.',
  'Push notifications are connected through Firebase Cloud Messaging.':
      'Paziņojumi ir pieslēgti caur Firebase Cloud Messaging.',
  'you': 'jūs',
  'Yesterday': 'Vakar',
  'Temporary event': 'Pagaidu pasākums',
  'Temporary events': 'Pagaidu pasākumi',
};

String trText(String value, {AppLanguage? language}) {
  final selectedLanguage = language ?? appUiPreferences.language;
  final translations = switch (selectedLanguage) {
    AppLanguage.en => const <String, String>{},
    AppLanguage.ru => _ruText,
    AppLanguage.lv => _lvText,
  };
  if (value == 'Add Spot Nav') {
    return switch (selectedLanguage) {
      AppLanguage.en => 'Add\nSpot',
      AppLanguage.ru => 'Добавить\nспот',
      AppLanguage.lv => 'Pievienot\nvietu',
    };
  }

  final exact = translations[value];

  if (exact != null) {
    return exact;
  }

  final showMoreMatch = RegExp(r'^Show (\d+) more$').firstMatch(value);
  if (showMoreMatch != null) {
    final count = showMoreMatch.group(1)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => 'Показать ещё: $count',
      AppLanguage.lv => 'Rādīt vēl: $count',
    };
  }

  final spotsMatch = RegExp(r'^(\d+) spots$').firstMatch(value);
  if (spotsMatch != null) {
    final count = spotsMatch.group(1)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => 'Споты: $count',
      AppLanguage.lv => 'Vietas: $count',
    };
  }

  final ratingMatch = RegExp(
    r'^([0-9]+(?:\.[0-9]+)?) spot rating$',
  ).firstMatch(value);
  if (ratingMatch != null) {
    final rating = ratingMatch.group(1)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => '$rating рейтинг спота',
      AppLanguage.lv => '$rating vietas vērtējums',
    };
  }

  final commentsMatch = RegExp(r'^(\d+) comments?$').firstMatch(value);
  if (commentsMatch != null) {
    final count = commentsMatch.group(1)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => '$count комментариев',
      AppLanguage.lv => '$count komentāri',
    };
  }

  final photosSelectedMatch = RegExp(
    r'^(\d+)/(\d+) photos selected$',
  ).firstMatch(value);
  if (photosSelectedMatch != null) {
    final current = photosSelectedMatch.group(1)!;
    final max = photosSelectedMatch.group(2)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => '$current/$max фото выбрано',
      AppLanguage.lv => '$current/$max foto izvēlēti',
    };
  }

  final addedByMatch = RegExp(r'^Added by:? (.+)$').firstMatch(value);
  if (addedByMatch != null) {
    final name = addedByMatch.group(1)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => 'Добавлено $name',
      AppLanguage.lv => 'Pievienoja $name',
    };
  }

  final addedDateMatch = RegExp(r'^Added (.+)$').firstMatch(value);
  if (addedDateMatch != null) {
    final date = addedDateMatch.group(1)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => 'Добавлена дата $date',
      AppLanguage.lv => 'Pievienošanas datums $date',
    };
  }

  final commentTitleMatch = RegExp(r'^Comment (.+)$').firstMatch(value);
  if (commentTitleMatch != null) {
    final spotName = commentTitleMatch.group(1)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => 'Комментарии $spotName',
      AppLanguage.lv => 'Komentāri $spotName',
    };
  }

  final awayKmMatch = RegExp(
    r'^ • ([0-9]+(?:\.[0-9]+)?) km away$',
  ).firstMatch(value);
  if (awayKmMatch != null) {
    final km = awayKmMatch.group(1)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => ' • $km км',
      AppLanguage.lv => ' • $km km',
    };
  }

  final awayMMatch = RegExp(r'^ • (\d+) m away$').firstMatch(value);
  if (awayMMatch != null) {
    final meters = awayMMatch.group(1)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => ' • $meters м',
      AppLanguage.lv => ' • $meters m',
    };
  }

  final friendAtSpotMatch = RegExp(r'^@(.+) is at (.+)$').firstMatch(value);
  if (friendAtSpotMatch != null) {
    final friend = friendAtSpotMatch.group(1)!;
    final spotName = friendAtSpotMatch.group(2)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => '@$friend находится у $spotName',
      AppLanguage.lv => '@$friend ir pie $spotName',
    };
  }

  final friendNearbyMatch = RegExp(r'^@(.+) is nearby(.*)$').firstMatch(value);
  if (friendNearbyMatch != null) {
    final friend = friendNearbyMatch.group(1)!;
    final distance = friendNearbyMatch.group(2)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => '@$friend рядом$distance',
      AppLanguage.lv => '@$friend ir tuvumā$distance',
    };
  }

  final updatedMatch = RegExp(r'^Updated (.+)$').firstMatch(value);
  if (updatedMatch != null) {
    final date = updatedMatch.group(1)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => 'Обновлено $date',
      AppLanguage.lv => 'Atjaunināts $date',
    };
  }

  final noAdminSpotsMatch = RegExp(
    r'^No (pending|edited|approved|rejected|all) spots right now\.$',
  ).firstMatch(value);
  if (noAdminSpotsMatch != null) {
    final kind = noAdminSpotsMatch.group(1)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru =>
        'Сейчас нет спотов: ${trText(kind, language: selectedLanguage)}.',
      AppLanguage.lv =>
        'Pašlaik nav vietu: ${trText(kind, language: selectedLanguage)}.',
    };
  }

  final adminFirebaseCountMatch = RegExp(
    r'^(\d+) (pending|edited|approved|rejected|all) spots? in Firebase\.$',
  ).firstMatch(value);
  if (adminFirebaseCountMatch != null) {
    final count = adminFirebaseCountMatch.group(1)!;
    final kind = adminFirebaseCountMatch.group(2)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru =>
        '$count спотов в Firebase: ${trText(kind, language: selectedLanguage)}.',
      AppLanguage.lv =>
        '$count vietas Firebase: ${trText(kind, language: selectedLanguage)}.',
    };
  }

  final adminCountMatch = RegExp(
    r'^(Pending|Edited|Approved|Rejected|All) (\d+)$',
  ).firstMatch(value);
  if (adminCountMatch != null) {
    final status = adminCountMatch.group(1)!;
    final count = adminCountMatch.group(2)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => switch (status) {
        'Pending' => 'На проверке $count',
        'Edited' => 'Изменённые $count',
        'Approved' => 'Одобренные $count',
        'Rejected' => 'Отклонённые $count',
        _ => 'Все $count',
      },
      AppLanguage.lv => switch (status) {
        'Pending' => 'Gaida $count',
        'Edited' => 'Labotie $count',
        'Approved' => 'Apstiprinātie $count',
        'Rejected' => 'Noraidītie $count',
        _ => 'Visi $count',
      },
    };
  }

  final awayMatch = RegExp(r'^(.+) away$').firstMatch(value);
  if (awayMatch != null) {
    final distance = awayMatch.group(1)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => '$distance от вас',
      AppLanguage.lv => '$distance attālumā',
    };
  }

  final minuteMatch = RegExp(r'^~(\d+) min$').firstMatch(value);
  if (minuteMatch != null) {
    final minutes = minuteMatch.group(1)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => '~$minutes мин',
      AppLanguage.lv => '~$minutes min',
    };
  }

  return value;
}

Color? _lightTextColor(Color? color) {
  if (!appUiPreferences.lightTheme || color == null) {
    return color;
  }

  if (color.red >= 220 && color.green >= 220 && color.blue >= 220) {
    return Color.fromARGB(color.alpha, 24, 28, 34);
  }

  return color;
}

TextStyle? _appTextStyle(TextStyle? style) {
  if (style == null || !appUiPreferences.lightTheme) {
    return style;
  }

  return style.copyWith(color: _lightTextColor(style.color));
}

class Text extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  const Text(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appUiPreferences,
      builder: (context, _) {
        return material.Text(
          trText(data),
          style: _appTextStyle(style),
          strutStyle: strutStyle,
          textAlign: textAlign,
          textDirection: textDirection,
          locale: locale,
          softWrap: softWrap,
          overflow: overflow,
          textScaler: textScaler,
          maxLines: maxLines,
          semanticsLabel: semanticsLabel,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior,
          selectionColor: selectionColor,
        );
      },
    );
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await warmUpAppMapBackground();
  await appUiPreferences.load();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
    await initializeMaintenanceMode();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Google Sign-In needs one setup call before we use the login button.
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: googleServerClientId,
      );
    } catch (error) {
      googleSignInSetupError = error.toString();
    }

    rememberMeEnabled = await loadRememberMePreference();
    await loadSpotCategoryFiltersPreference();
    await loadSavedSpotsFromPrefs();

    final appUser = await loadCurrentFirebaseUser();
    if (appUser != null) {
      startFirebaseSpotSync();
      unawaited(initializePushNotificationsForCurrentUser());
    }
  } catch (error) {
    // Do not let a Firebase/Google services problem crash the app on startup.
    firebaseReady = false;
    googleSignInSetupError = error.toString();
    rememberMeEnabled = false;
  }

  runApp(const CCSApp());
}

class CCSApp extends StatelessWidget {
  const CCSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appUiPreferences,
      builder: (context, _) {
        const lightTheme = false;
        final baseTheme = ThemeData.dark();

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'CCS',
          locale: Locale(appUiPreferences.language.name),
          theme: baseTheme.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
            textTheme: baseTheme.textTheme.apply(
              bodyColor: lightTheme ? const Color(0xFF181C22) : Colors.white,
              displayColor: lightTheme ? const Color(0xFF181C22) : Colors.white,
            ),
            iconTheme: IconThemeData(
              color: lightTheme ? const Color(0xFF242A33) : Colors.white70,
            ),
            inputDecorationTheme: InputDecorationTheme(
              labelStyle: TextStyle(
                color: lightTheme ? Colors.black54 : Colors.white60,
              ),
              hintStyle: TextStyle(
                color: lightTheme ? Colors.black38 : Colors.white24,
              ),
            ),
          ),
          builder: (context, child) {
            return MaintenanceModeGate(
              child: Stack(
                fit: StackFit.expand,
                children: [const AppMapBackground(), if (child != null) child],
              ),
            );
          },
          home:
              firebaseReady &&
                  rememberMeEnabled &&
                  FirebaseAuth.instance.currentUser != null
              ? const MainScreen()
              : const SplashScreen(),
        );
      },
    );
  }
}

class MaintenanceModeGate extends StatelessWidget {
  final Widget child;

  const MaintenanceModeGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        maintenanceModeConfig,
        maintenanceAccessRevision,
      ]),
      builder: (context, _) {
        final config = maintenanceModeConfig.value;
        final isSignedIn = FirebaseAuth.instance.currentUser != null;
        final canAdminBypass =
            isSignedIn &&
            config.allowAdminBypass &&
            currentUser.role == UserRole.admin;

        // Keep login reachable so an administrator can authenticate during maintenance.
        if (!config.maintenanceEnabled || !isSignedIn || canAdminBypass) {
          return child;
        }

        return MaintenanceModeScreen(config: config);
      },
    );
  }
}

class MaintenanceModeScreen extends StatelessWidget {
  final MaintenanceModeConfig config;

  const MaintenanceModeScreen({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg.png', fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.82)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _CcsWordmark(width: 196),
                  const SizedBox(height: 38),
                  const Icon(
                    Icons.build_circle_outlined,
                    size: 54,
                    color: blue,
                  ),
                  const SizedBox(height: 22),
                  material.Text(
                    config.maintenanceTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: material.Text(
                      config.maintenanceMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    onPressed: () => unawaited(refreshMaintenanceMode()),
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text(
                      'Retry',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 15,
                      ),
                      elevation: 10,
                      shadowColor: blue.withValues(alpha: 0.36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const blue = Color(0xFF1565FF);
const sosAlertColor = Color(0xFFFF2D55);

Color policeAlertColor(double pulse) {
  return Color.lerp(blue, sosAlertColor, pulse)!;
}

Color get night => const Color(0xFF050507);
Color get panel => const Color(0xFF101014);
Color get panelGlass => const Color(0xCC101014);
Color get panelGlassSoft => const Color(0xB0101014);
Color get appPrimaryText => Colors.white;
Color get appSecondaryText => Colors.white54;
Color get appSubtleText => Colors.white38;
Color get appOutline => Colors.white12;
Color get appSurfaceOverlay => Colors.white.withValues(alpha: 0.06);
const appMapBackgroundAsset = 'assets/bg_map.png';
ui.Image? appMapBackgroundImage;

Future<void> warmUpAppMapBackground() async {
  try {
    final bytes = await rootBundle.load(appMapBackgroundAsset);
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    appMapBackgroundImage = frame.image;
  } catch (_) {
    appMapBackgroundImage = null;
  }
}

class AppMapBackground extends StatelessWidget {
  const AppMapBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: night),
        CustomPaint(
          painter: AppMapBackgroundPainter(appMapBackgroundImage),
          child: const SizedBox.expand(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.36),
                Colors.black.withValues(alpha: 0.18),
                Colors.black.withValues(alpha: 0.42),
              ],
            ),
          ),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.02)),
      ],
    );
  }
}

class AppMapBackgroundPainter extends CustomPainter {
  final ui.Image? image;

  const AppMapBackgroundPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    if (image == null || size.isEmpty) {
      return;
    }

    final inputSize = Size(image.width.toDouble(), image.height.toDouble());
    final outputRect = Offset.zero & size;
    final fitted = applyBoxFit(BoxFit.cover, inputSize, size);
    final sourceRect = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & inputSize,
    );
    final destinationRect = Alignment.center.inscribe(
      fitted.destination,
      outputRect,
    );
    final paint = Paint()..filterQuality = FilterQuality.high;

    canvas.drawImageRect(image, sourceRect, destinationRect, paint);
  }

  @override
  bool shouldRepaint(AppMapBackgroundPainter oldDelegate) {
    return oldDelegate.image != image;
  }
}

class AppRouteBackground extends StatelessWidget {
  final Widget child;

  const AppRouteBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [const AppMapBackground(), child],
    );
  }
}

PageRoute<T> appPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    opaque: true,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) {
      return AppRouteBackground(child: builder(context));
    },
  );
}

const photoPickerChannel = MethodChannel('ccs/photo_picker');
const liveLocationBackgroundChannel = MethodChannel(
  'ccs/live_location_background',
);
const systemNotificationsChannel = MethodChannel('ccs/system_notifications');
const spotCategoryFiltersKey = 'spot_category_filters';

Future<void> registerPushTokenForCurrentUser(String token) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final cleanToken = token.trim();

  if (firebaseUser == null || cleanToken.isEmpty) {
    debugPrint(
      'Push token registration skipped. firebaseUser=${firebaseUser?.uid}, tokenEmpty=${cleanToken.isEmpty}',
    );
    return;
  }

  try {
    await usersCollection().doc(firebaseUser.uid).set({
      'fcmTokens': FieldValue.arrayUnion([cleanToken]),
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      'lastFcmTokenPlatform': Platform.operatingSystem,
    }, SetOptions(merge: true));
    debugPrint(
      'Push token registered for ${firebaseUser.uid}: ${cleanToken.substring(0, math.min(12, cleanToken.length))}...',
    );
  } catch (error, stack) {
    debugPrint('Push token registration failed: $error');
    debugPrint('$stack');
  }
}

Future<void> unregisterPushTokenForCurrentUser() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return;
  }

  try {
    final token = await FirebaseMessaging.instance.getToken();

    if (token == null || token.trim().isEmpty) {
      return;
    }

    await usersCollection().doc(firebaseUser.uid).set({
      'fcmTokens': FieldValue.arrayRemove([token]),
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (error, stack) {
    debugPrint('Push token cleanup failed: $error');
    debugPrint('$stack');
  }
}

Future<void> showForegroundSystemNotification(RemoteMessage message) async {
  if (!Platform.isAndroid) {
    return;
  }

  final notification = message.notification;
  final title = notification?.title ?? message.data['title'] ?? 'CCS';
  final body = notification?.body ?? message.data['body'] ?? '';

  if (body.trim().isEmpty) {
    return;
  }

  try {
    await systemNotificationsChannel.invokeMethod<void>('showNotification', {
      'id': (message.messageId ?? '$title|$body').hashCode & 0x7fffffff,
      'title': title,
      'body': body,
    });
  } catch (error, stack) {
    debugPrint('Foreground push display failed: $error');
    debugPrint('$stack');
  }
}

Future<void> initializePushNotificationsForCurrentUser() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (!firebaseReady || firebaseUser == null) {
    debugPrint(
      'Push initialization skipped. firebaseReady=$firebaseReady, firebaseUser=${firebaseUser?.uid}',
    );
    return;
  }

  try {
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('Push permission status: ${settings.authorizationStatus}');

    final token = await messaging.getToken();
    if (token == null || token.trim().isEmpty) {
      debugPrint('FirebaseMessaging.getToken() returned no token.');
    } else {
      await registerPushTokenForCurrentUser(token);
    }
    unawaited(refreshNotificationCenterUnreadCount());
    startNotificationCenterUnreadWatcher();

    pushTokenRefreshSubscription ??= messaging.onTokenRefresh.listen(
      (token) {
        debugPrint('FCM token refreshed.');
        unawaited(registerPushTokenForCurrentUser(token));
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('FCM token refresh listener failed: $error');
        debugPrint('$stack');
      },
    );

    foregroundPushSubscription ??= FirebaseMessaging.onMessage.listen(
      (message) {
        debugPrint(
          'Foreground push received. messageId=${message.messageId}, data=${message.data}',
        );
        unawaited(showForegroundSystemNotification(message));
        unawaited(refreshNotificationCenterUnreadCount());
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('Foreground push listener failed: $error');
        debugPrint('$stack');
      },
    );
  } catch (error, stack) {
    debugPrint('Push initialization failed: $error');
    debugPrint('$stack');
  }
}

const spotCategoryOptions = [
  'Drift',
  'Photo',
  'Meet',
  'Drive',
  'Service',
  'Detailing',
  'Wash',
  'Store',
  'Drag',
  'Off-road',
  'Food',
];

const contactEnabledSpotCategories = {
  'Service',
  'Detailing',
  'Wash',
  'Store',
  'Food',
};

bool spotCategorySupportsContacts(String category) {
  return contactEnabledSpotCategories.contains(category.trim());
}

const weekdayLabels = {
  1: 'Monday',
  2: 'Tuesday',
  3: 'Wednesday',
  4: 'Thursday',
  5: 'Friday',
  6: 'Saturday',
  7: 'Sunday',
};

class OpeningHoursData {
  final bool isOpen;
  final String opensAt;
  final String closesAt;

  const OpeningHoursData({
    required this.isOpen,
    required this.opensAt,
    required this.closesAt,
  });

  OpeningHoursData copyWith({bool? isOpen, String? opensAt, String? closesAt}) {
    return OpeningHoursData(
      isOpen: isOpen ?? this.isOpen,
      opensAt: opensAt ?? this.opensAt,
      closesAt: closesAt ?? this.closesAt,
    );
  }

  factory OpeningHoursData.fromFirebase(Object? value) {
    final data = mapFromFirebase(value);

    return OpeningHoursData(
      isOpen: data['isOpen'] == true,
      opensAt: stringFromFirebase(data['opensAt'], '08:00'),
      closesAt: stringFromFirebase(data['closesAt'], '20:00'),
    );
  }

  Map<String, Object?> toFirebase() {
    return {'isOpen': isOpen, 'opensAt': opensAt, 'closesAt': closesAt};
  }
}

Map<int, OpeningHoursData> defaultServiceOpeningHours() {
  return {
    for (var weekday = 1; weekday <= 7; weekday++)
      weekday: OpeningHoursData(
        isOpen: weekday <= DateTime.friday,
        opensAt: '08:00',
        closesAt: '20:00',
      ),
  };
}

Map<int, OpeningHoursData> openingHoursFromFirebase(Object? value) {
  final data = mapFromFirebase(value);
  final openingHours = <int, OpeningHoursData>{};

  for (final entry in data.entries) {
    final weekday = int.tryParse(entry.key);
    if (weekday == null ||
        weekday < DateTime.monday ||
        weekday > DateTime.sunday) {
      continue;
    }

    openingHours[weekday] = OpeningHoursData.fromFirebase(entry.value);
  }

  return openingHours;
}

Map<String, Object?> openingHoursToFirebase(
  Map<int, OpeningHoursData> openingHours,
) {
  return {
    for (final entry in openingHours.entries)
      '${entry.key}': entry.value.toFirebase(),
  };
}

int? minutesFromClockText(String value) {
  final parts = value.trim().split(':');
  if (parts.length != 2) {
    return null;
  }

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }

  return hour * 60 + minute;
}

String clockTextFromTimeOfDay(TimeOfDay value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

const spotCategoryIconAssets = {
  'Drift': 'assets/spot_icons/drift.png',
  'Photo': 'assets/spot_icons/photo.png',
  'Meet': 'assets/spot_icons/meet.png',
  'Drive': 'assets/spot_icons/drive.png',
  'Service': 'assets/spot_icons/service.png',
  'Detailing': 'assets/spot_icons/detailing.png',
  'Wash': 'assets/spot_icons/wash.png',
  'Store': 'assets/spot_icons/store.png',
  'Drag': 'assets/spot_icons/drag.png',
  'Off-road': 'assets/spot_icons/offroad.png',
  'Food': 'assets/spot_icons/food.png',
};

const spotCategoryColors = {
  'Drift': Color(0xFFFF7A00),
  'Photo': Color(0xFF9B35FF),
  'Meet': Color(0xFF8AE600),
  'Drive': Color(0xFF00B8FF),
  'Service': Color(0xFFFFD400),
  'Detailing': Color(0xFF00E0C7),
  'Wash': Color(0xFF008CFF),
  'Store': Color(0xFFA83DFF),
  'Drag': Color(0xFFFF1635),
  'Off-road': Color(0xFF8B5A2B),
  'Food': Color(0xFFFF1B8D),
};

const regularUserCarIconAsset = 'assets/user_cars/car_blue.png';
const verifiedUserCarIconAsset = 'assets/user_cars/car_green.png';
const friendUserCarIconAsset = 'assets/user_cars/car_purple.png';

String spotIconAssetPathForCategory(String category) {
  return spotCategoryIconAssets[category] ?? spotCategoryIconAssets['Photo']!;
}

String primarySpotCategory(CarSpot spot) {
  for (final category in spot.categories) {
    if (spotCategoryIconAssets.containsKey(category)) {
      return category;
    }
  }

  return 'Photo';
}

String spotIconAssetPathForSpot(CarSpot spot) {
  return spotIconAssetPathForCategory(primarySpotCategory(spot));
}

Color spotColorForCategory(String category) {
  return spotCategoryColors[category] ?? blue;
}

Color spotColorForSpot(CarSpot spot) {
  return spotColorForCategory(primarySpotCategory(spot));
}

final submittedSpots = ValueNotifier<List<CarSpot>>([]);
final savedSpots = ValueNotifier<List<CarSpot>>([]);
final reviewSpots = ValueNotifier<List<CarSpot>>([]);
final userSettings = ValueNotifier<UserSettingsData>(defaultUserSettings());
final garageCars = ValueNotifier<List<GarageCar>>(defaultGarageCars());
final mapFocusRequest = ValueNotifier<MapFocusRequest?>(null);
final spotCategoryFilters = ValueNotifier<Set<String>>({
  ...spotCategoryOptions,
});
const savedSpotsKey = 'saved_spot_ids_v1';
Set<String> savedSpotIds = {};

Set<String> sanitizedSpotCategoryFilters(Iterable<String> categories) {
  final validCategories = spotCategoryOptions.toSet();
  final cleanCategories = categories
      .map((category) => category.trim())
      .where(validCategories.contains)
      .toSet();

  return cleanCategories;
}

Future<void> loadSpotCategoryFiltersPreference() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedCategories = prefs.getStringList(spotCategoryFiltersKey);

    if (savedCategories == null) {
      return;
    }

    spotCategoryFilters.value = sanitizedSpotCategoryFilters(savedCategories);
  } catch (_) {}
}

Future<void> saveSpotCategoryFiltersPreference(Set<String> categories) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      spotCategoryFiltersKey,
      categories.toList()..sort(),
    );
  } catch (_) {}
}

Future<void> loadSavedSpotsFromPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    savedSpotIds = (prefs.getStringList(savedSpotsKey) ?? const <String>[])
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    restoreSavedSpotsFromFirebaseCache();
  } catch (_) {}
}

Future<void> saveSavedSpotIds() async {
  try {
    savedSpotIds = savedSpots.value
        .map((spot) => spot.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(savedSpotsKey, savedSpotIds.toList());
  } catch (_) {}
}

void restoreSavedSpotsFromFirebaseCache() {
  if (savedSpotIds.isEmpty) {
    if (savedSpots.value.isNotEmpty) {
      savedSpots.value = [];
    }
    return;
  }

  final availableById = <String, CarSpot>{
    for (final spot in reviewSpots.value)
      if (spot.id.trim().isNotEmpty) spot.id.trim(): spot,
  };
  final restored = savedSpotIds
      .map((id) => availableById[id])
      .whereType<CarSpot>()
      .toList();
  final unchanged =
      restored.length == savedSpots.value.length &&
      restored.every(
        (spot) => savedSpots.value.any((saved) => isSameSpot(saved, spot)),
      );

  if (!unchanged) {
    savedSpots.value = restored;
  }
}

void updateSpotCategoryFilters(Set<String> categories) {
  final cleanCategories = sanitizedSpotCategoryFilters(categories);
  spotCategoryFilters.value = cleanCategories;
  unawaited(saveSpotCategoryFiltersPreference(cleanCategories));
}

class MapFocusRequest {
  final String spotId;
  final LatLng coordinates;
  final int token;

  MapFocusRequest({required this.spotId, required this.coordinates})
    : token = DateTime.now().microsecondsSinceEpoch;
}

enum PhotoCropShape { rectangle, circle }

Future<String?> pickPhotoFromPhone(
  BuildContext context, {
  double cropAspectRatio = 1,
  PhotoCropShape cropShape = PhotoCropShape.rectangle,
}) async {
  try {
    final path = await photoPickerChannel.invokeMethod<String>('pickPhoto');

    if (!context.mounted || path == null || path.trim().isEmpty) {
      return path;
    }

    return Navigator.push<String>(
      context,
      appPageRoute(
        builder: (_) => PhotoCropScreen(
          sourcePath: path,
          cropAspectRatio: cropAspectRatio,
          cropShape: cropShape,
        ),
      ),
    );
  } on PlatformException catch (error) {
    if (!context.mounted) {
      return null;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          error.message ?? 'Could not open photo picker.',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    return null;
  } on MissingPluginException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Photo picker is not connected in Android native code.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return null;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not open photo picker. $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return null;
  }
}

class PhotoCropScreen extends StatefulWidget {
  final String sourcePath;
  final double cropAspectRatio;
  final PhotoCropShape cropShape;

  const PhotoCropScreen({
    super.key,
    required this.sourcePath,
    required this.cropAspectRatio,
    this.cropShape = PhotoCropShape.rectangle,
  });

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  double zoom = 1;
  Offset offset = Offset.zero;
  double editorWidth = 0;
  double editorHeight = 0;
  double cropWidth = 0;
  double cropHeight = 0;
  double gestureStartZoom = 1;
  int? imageWidth;
  int? imageHeight;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    loadImageSize();
  }

  Future<void> loadImageSize() async {
    try {
      final bytes = await File(widget.sourcePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      final normalized = decoded == null ? null : img.bakeOrientation(decoded);

      if (!mounted || normalized == null) {
        return;
      }

      setState(() {
        imageWidth = normalized.width;
        imageHeight = normalized.height;
      });
    } catch (_) {}
  }

  double minZoomForLayout() {
    final width = imageWidth;
    final height = imageHeight;

    if (width == null ||
        height == null ||
        editorWidth <= 0 ||
        editorHeight <= 0 ||
        cropWidth <= 0 ||
        cropHeight <= 0) {
      return 1;
    }

    final baseScale = math.min(editorWidth / width, editorHeight / height);
    return math.max(
      1.0,
      math.max(
        cropWidth / (width * baseScale),
        cropHeight / (height * baseScale),
      ),
    );
  }

  Offset clampedOffset(Offset value, {double? zoomValue}) {
    final width = imageWidth;
    final height = imageHeight;
    final currentZoom = zoomValue ?? zoom;

    if (width == null ||
        height == null ||
        editorWidth <= 0 ||
        editorHeight <= 0 ||
        cropWidth <= 0 ||
        cropHeight <= 0) {
      return value;
    }

    final baseScale = math.min(editorWidth / width, editorHeight / height);
    final displayWidth = width * baseScale * currentZoom;
    final displayHeight = height * baseScale * currentZoom;
    final cropLeft = (editorWidth - cropWidth) / 2;
    final cropTop = (editorHeight - cropHeight) / 2;
    final cropRight = cropLeft + cropWidth;
    final cropBottom = cropTop + cropHeight;
    final minX = cropRight - (editorWidth + displayWidth) / 2;
    final maxX = cropLeft - (editorWidth - displayWidth) / 2;
    final minY = cropBottom - (editorHeight + displayHeight) / 2;
    final maxY = cropTop - (editorHeight - displayHeight) / 2;

    return Offset(
      value.dx.clamp(minX, maxX).toDouble(),
      value.dy.clamp(minY, maxY).toDouble(),
    );
  }

  Future<void> saveCroppedPhoto() async {
    if (isSaving) {
      return;
    }

    setState(() => isSaving = true);

    try {
      final file = File(widget.sourcePath);
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        throw Exception('Could not read selected image.');
      }

      final normalized = img.bakeOrientation(decoded);
      final width = normalized.width;
      final height = normalized.height;
      final hasLayout =
          editorWidth > 0 &&
          editorHeight > 0 &&
          cropWidth > 0 &&
          cropHeight > 0;
      final fallbackWidth = math.min(width, height);
      final fallbackHeight = math.min(width, height);
      final baseScale = hasLayout
          ? math.min(editorWidth / width, editorHeight / height)
          : 1.0;
      final effectiveZoom = math.max(zoom, minZoomForLayout());
      final totalScale = hasLayout ? baseScale * effectiveZoom : 1.0;
      final cropPixelWidth =
          (hasLayout ? cropWidth / totalScale : fallbackWidth)
              .round()
              .clamp(1, width)
              .toInt();
      final cropPixelHeight =
          (hasLayout ? cropHeight / totalScale : fallbackHeight)
              .round()
              .clamp(1, height)
              .toInt();
      final cropLeft = hasLayout ? (editorWidth - cropWidth) / 2 : 0.0;
      final cropTop = hasLayout ? (editorHeight - cropHeight) / 2 : 0.0;
      final imageLeft = hasLayout
          ? (editorWidth - width * totalScale) / 2 + offset.dx
          : (width - cropPixelWidth) / 2;
      final imageTop = hasLayout
          ? (editorHeight - height * totalScale) / 2 + offset.dy
          : (height - cropPixelHeight) / 2;
      final cropX = hasLayout
          ? ((cropLeft - imageLeft) / totalScale)
                .round()
                .clamp(0, width - cropPixelWidth)
                .toInt()
          : ((width - cropPixelWidth) / 2).round();
      final cropY = hasLayout
          ? ((cropTop - imageTop) / totalScale)
                .round()
                .clamp(0, height - cropPixelHeight)
                .toInt()
          : ((height - cropPixelHeight) / 2).round();
      final cropped = img.copyCrop(
        normalized,
        x: cropX,
        y: cropY,
        width: cropPixelWidth,
        height: cropPixelHeight,
      );
      final directory = await Directory.systemTemp.createTemp('ccs_photo_');
      final croppedPath =
          '${directory.path}${Platform.pathSeparator}photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final croppedFile = File(croppedPath);

      await croppedFile.writeAsBytes(img.encodeJpg(cropped, quality: 92));

      if (mounted) {
        Navigator.pop(context, croppedFile.path);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not prepare photo: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Adjust Photo'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
        actions: [
          IconButton(
            tooltip: 'Use photo',
            onPressed: isSaving ? null : saveCroppedPhoto,
            icon: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          editorWidth = (constraints.maxWidth - 40).clamp(260, 520).toDouble();
          editorHeight = math
              .min(constraints.maxHeight * 0.58, 560)
              .clamp(330, 560)
              .toDouble();
          final frameMaxWidth = editorWidth - 34;
          final frameMaxHeight = editorHeight - 70;
          final isCircleCrop = widget.cropShape == PhotoCropShape.circle;
          cropWidth = frameMaxWidth;
          final cropRatio = isCircleCrop
              ? 1.0
              : widget.cropAspectRatio <= 0
              ? 1.0
              : widget.cropAspectRatio;
          cropHeight = cropWidth / cropRatio;
          if (cropHeight > frameMaxHeight) {
            cropHeight = frameMaxHeight;
            cropWidth = cropHeight * cropRatio;
          }
          final minZoom = minZoomForLayout();
          final maxZoom = math.max(3.0, minZoom * 3);
          final effectiveZoom = zoom.clamp(minZoom, maxZoom).toDouble();
          if ((zoom - effectiveZoom).abs() > 0.001) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  zoom = effectiveZoom;
                  offset = clampedOffset(offset, zoomValue: effectiveZoom);
                });
              }
            });
          }
          offset = clampedOffset(offset, zoomValue: effectiveZoom);
          final cropLeft = (editorWidth - cropWidth) / 2;
          final cropTop = (editorHeight - cropHeight) / 2;
          final cropRightWidth = editorWidth - cropLeft - cropWidth;
          final cropBottomHeight = editorHeight - cropTop - cropHeight;

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              children: [
                Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: (_) {
                      gestureStartZoom = effectiveZoom;
                    },
                    onScaleUpdate: (details) {
                      final nextZoom = (gestureStartZoom * details.scale)
                          .clamp(minZoom, maxZoom)
                          .toDouble();
                      setState(() {
                        zoom = nextZoom;
                        offset = clampedOffset(
                          offset + details.focalPointDelta,
                          zoomValue: nextZoom,
                        );
                      });
                    },
                    child: Container(
                      width: editorWidth,
                      height: editorHeight,
                      decoration: BoxDecoration(
                        color: panelGlass,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Transform.translate(
                            offset: offset,
                            child: Transform.scale(
                              scale: effectiveZoom,
                              child: Image.file(
                                File(widget.sourcePath),
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: Colors.white38,
                                    size: 44,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            right: 0,
                            height: cropTop,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: cropTop,
                            width: cropLeft,
                            height: cropHeight,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: cropTop,
                            width: cropRightWidth,
                            height: cropHeight,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: cropBottomHeight,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                          Positioned(
                            left: cropLeft,
                            top: cropTop,
                            child: IgnorePointer(
                              child: Container(
                                width: cropWidth,
                                height: cropHeight,
                                decoration: BoxDecoration(
                                  shape: isCircleCrop
                                      ? BoxShape.circle
                                      : BoxShape.rectangle,
                                  borderRadius: isCircleCrop
                                      ? null
                                      : BorderRadius.circular(12),
                                  border: Border.all(color: blue, width: 2),
                                ),
                                child: isCircleCrop
                                    ? const SizedBox.shrink()
                                    : Stack(
                                        children: [
                                          Center(
                                            child: Container(
                                              width: cropWidth,
                                              height: 1,
                                              color: Colors.white.withValues(
                                                alpha: 0.22,
                                              ),
                                            ),
                                          ),
                                          Center(
                                            child: Container(
                                              width: 1,
                                              height: cropHeight,
                                              color: Colors.white.withValues(
                                                alpha: 0.22,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                          if (isCircleCrop)
                            Positioned(
                              left: cropLeft,
                              top: cropTop,
                              child: IgnorePointer(
                                child: Container(
                                  width: cropWidth,
                                  height: cropHeight,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.36,
                                        ),
                                        blurRadius: 18,
                                        spreadRadius: -6,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: panelGlass,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.zoom_out, color: Colors.white54),
                      Expanded(
                        child: Slider(
                          value: effectiveZoom,
                          min: minZoom,
                          max: maxZoom,
                          activeColor: blue,
                          inactiveColor: Colors.white24,
                          onChanged: (value) {
                            setState(() {
                              zoom = value;
                              offset = clampedOffset(offset, zoomValue: value);
                            });
                          },
                        ),
                      ),
                      const Icon(Icons.zoom_in, color: Colors.white54),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: isSaving ? null : saveCroppedPhoto,
                    icon: const Icon(Icons.check),
                    label: Text(isSaving ? 'Saving...' : 'Use Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

enum UserRole { admin, moderator, user }

enum SpotStatus { pending, approved, rejected, edited }

class AppUser {
  final String uid;
  final String name;
  final String username;
  final String email;
  final String? photoUrl;
  final String bio;
  final String? avatarPath;
  final UserRole role;
  final bool verified;
  final String city;
  final String country;

  const AppUser({
    required this.uid,
    required this.name,
    required this.username,
    required this.email,
    this.photoUrl,
    this.bio = 'Find. Drive. Shoot.',
    this.avatarPath,
    required this.role,
    this.verified = false,
    required this.city,
    required this.country,
  });
}

// Keep the fallback unprivileged until Firebase login finishes.
AppUser currentUser = const AppUser(
  uid: '',
  name: '',
  username: '',
  email: '',
  role: UserRole.user,
  verified: false,
  city: '',
  country: '',
);

void setCurrentUser(AppUser value) {
  currentUser = value;
  refreshMaintenanceAccess();
}

String roleName(UserRole role) {
  switch (role) {
    case UserRole.admin:
      return 'admin';
    case UserRole.moderator:
      return 'moderator';
    case UserRole.user:
      return 'user';
  }
}

UserRole roleFromFirebase(Object? value) {
  switch (value) {
    case 'admin':
      return UserRole.admin;
    case 'moderator':
      return UserRole.moderator;
    default:
      return UserRole.user;
  }
}

bool userRoleIsAdmin(UserRole role) {
  return role == UserRole.admin;
}

bool userRoleIsModerator(UserRole role) {
  return role == UserRole.moderator;
}

bool userRoleIsStaff(UserRole role) {
  return role == UserRole.admin || role == UserRole.moderator;
}

Future<bool> loadRememberMePreference() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(rememberMeKey) ?? true;
}

Future<void> saveRememberMePreference(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(rememberMeKey, value);
  rememberMeEnabled = value;
}

Future<void> signOutCurrentAccount() async {
  await saveRememberMePreference(false);
  await unregisterPushTokenForCurrentUser();

  // Stop live Firebase listeners before auth becomes null.
  for (final subscription in spotSyncSubscriptions) {
    await subscription.cancel();
  }
  spotSyncSubscriptions.clear();
  _firebaseSpotCacheBySource.clear();
  await notificationCenterUnreadSubscription?.cancel();
  notificationCenterUnreadSubscription = null;
  notificationCenterUnreadCount.value = 0;

  // Best effort: mark the user offline before signing out.
  await updateCurrentUserOnlinePresence(isOnline: false);

  // Google Sign-In can throw on some platforms/states. Sign out must not crash.
  try {
    await GoogleSignIn.instance.signOut();
  } catch (_) {}

  try {
    await FirebaseAuth.instance.signOut();
  } catch (_) {}

  setCurrentUser(
    const AppUser(
      uid: '',
      name: '',
      username: '',
    email: '',
    role: UserRole.user,
    verified: false,
      city: '',
      country: '',
    ),
  );

  reviewSpots.value = [];
  submittedSpots.value = [];
  savedSpots.value = [];
  unawaited(saveSavedSpotIds());
  userSettings.value = defaultUserSettings();
  garageCars.value = defaultGarageCars();
}

String spotStatusName(SpotStatus status) {
  switch (status) {
    case SpotStatus.pending:
      return 'pending';
    case SpotStatus.approved:
      return 'approved';
    case SpotStatus.rejected:
      return 'rejected';
    case SpotStatus.edited:
      return 'edited';
  }
}

SpotStatus spotStatusFromFirebase(Object? value) {
  switch (value) {
    case 'approved':
      return SpotStatus.approved;
    case 'rejected':
      return SpotStatus.rejected;
    case 'edited':
      return SpotStatus.edited;
    default:
      return SpotStatus.pending;
  }
}

const minProfileUsernameLength = 3;
const maxProfileUsernameLength = 30;

String cleanProfileUsername(String value) {
  return value
      .trim()
      .replaceAll('@', '')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^a-zA-Z0-9_]+'), '')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

String boundedProfileUsername(String value) {
  final cleanValue = cleanProfileUsername(value);
  return cleanValue.length <= maxProfileUsernameLength
      ? cleanValue
      : cleanValue.substring(0, maxProfileUsernameLength);
}

String usernameWithSuffix(String value, String suffix) {
  final cleanValue = boundedProfileUsername(value);
  final cleanSuffix = cleanProfileUsername(suffix);
  final maxBaseLength = maxProfileUsernameLength - cleanSuffix.length - 1;
  final compactValue = cleanValue.length <= maxBaseLength
      ? cleanValue
      : cleanValue.substring(0, maxBaseLength);
  return '${compactValue}_$cleanSuffix';
}

String usernameKey(String value) {
  return cleanProfileUsername(value).toLowerCase();
}

String displayUsername(String value) {
  final cleanValue = cleanProfileUsername(value);
  if (cleanValue.isNotEmpty) {
    return cleanValue;
  }

  return value.trim().replaceAll('@', '');
}

String makeUsernameFromFirebaseUser(User user) {
  final displayName = user.displayName?.trim();
  final emailName = user.email?.split('@').first.trim();
  final rawName = (displayName != null && displayName.isNotEmpty)
      ? displayName
      : (emailName != null && emailName.isNotEmpty)
      ? emailName
      : 'ccs_driver';
  final cleanName = boundedProfileUsername(rawName);

  return cleanName.isEmpty ? 'ccs_driver' : cleanName;
}

String providerNameForFirebaseUser(User user) {
  if (user.isAnonymous) {
    return 'telegram';
  }

  final providerIds = user.providerData.map((provider) => provider.providerId);
  if (providerIds.contains('google.com')) {
    return 'google';
  }

  return providerIds.isEmpty ? 'firebase' : providerIds.first;
}

CollectionReference<Map<String, dynamic>> usernamesCollection() {
  return FirebaseFirestore.instance.collection('usernames');
}

enum UsernameAvailability {
  unchanged,
  checking,
  available,
  taken,
  invalid,
  error,
}

Future<UsernameAvailability> checkUsernameAvailabilityForCurrentUser(
  String username, {
  required String currentUsername,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final cleanUsername = cleanProfileUsername(username);

  if (cleanUsername.length < minProfileUsernameLength ||
      cleanUsername.length > maxProfileUsernameLength) {
    return UsernameAvailability.invalid;
  }

  if (usernameKey(cleanUsername) == usernameKey(currentUsername)) {
    return UsernameAvailability.unchanged;
  }

  if (firebaseUser == null) {
    return UsernameAvailability.error;
  }

  try {
    final snapshot = await usernamesCollection()
        .doc(usernameKey(cleanUsername))
        .get();

    if (!snapshot.exists) {
      return UsernameAvailability.available;
    }

    final ownerUid = snapshot.data()?['uid'] as String?;
    return ownerUid == firebaseUser.uid
        ? UsernameAvailability.unchanged
        : UsernameAvailability.taken;
  } catch (_) {
    return UsernameAvailability.error;
  }
}

String usernameAvailabilityText(UsernameAvailability availability) {
  switch (availability) {
    case UsernameAvailability.unchanged:
      return 'This is your current nickname.';
    case UsernameAvailability.checking:
      return 'Checking nickname availability...';
    case UsernameAvailability.available:
      return 'Nickname is available.';
    case UsernameAvailability.taken:
      return 'This nickname is already taken.';
    case UsernameAvailability.invalid:
      return 'Nickname must be 3 to 30 characters.';
    case UsernameAvailability.error:
      return 'Could not check nickname availability.';
  }
}

Color usernameAvailabilityColor(UsernameAvailability availability) {
  switch (availability) {
    case UsernameAvailability.available:
    case UsernameAvailability.unchanged:
      return Colors.greenAccent;
    case UsernameAvailability.checking:
      return Colors.white54;
    case UsernameAvailability.taken:
    case UsernameAvailability.invalid:
    case UsernameAvailability.error:
      return Colors.redAccent;
  }
}

IconData usernameAvailabilityIcon(UsernameAvailability availability) {
  switch (availability) {
    case UsernameAvailability.available:
    case UsernameAvailability.unchanged:
      return Icons.check_circle_outline;
    case UsernameAvailability.checking:
      return Icons.hourglass_empty;
    case UsernameAvailability.taken:
    case UsernameAvailability.invalid:
    case UsernameAvailability.error:
      return Icons.error_outline;
  }
}

String fallbackUsernameSuffix(String uid) {
  return uid.length <= 6 ? uid : uid.substring(0, 6);
}

Future<String> reserveUsernameForCurrentUser({
  required String preferredUsername,
  String? previousUsername,
  bool allowFallback = false,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before changing your nickname.',
    );
  }

  final cleanPreferred = cleanProfileUsername(preferredUsername);

  if (cleanPreferred.length < minProfileUsernameLength ||
      cleanPreferred.length > maxProfileUsernameLength) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'username-invalid-length',
      message: 'Nickname must be 3 to 30 characters.',
    );
  }

  final suffix = fallbackUsernameSuffix(firebaseUser.uid);

  for (var attempt = 0; attempt < 20; attempt++) {
    final candidate = attempt == 0
        ? cleanPreferred
        : attempt == 1
        ? usernameWithSuffix(cleanPreferred, suffix)
        : usernameWithSuffix(cleanPreferred, '${suffix}_$attempt');
    final key = usernameKey(candidate);
    final usernameRef = usernamesCollection().doc(key);
    final previousKey = previousUsername == null
        ? ''
        : usernameKey(previousUsername);
    final previousRef = previousKey.isEmpty || previousKey == key
        ? null
        : usernamesCollection().doc(previousKey);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(usernameRef);
        final previousSnapshot = previousRef == null
            ? null
            : await transaction.get(previousRef);
        final existingUid = snapshot.data()?['uid'] as String?;
        final previousUid = previousSnapshot?.data()?['uid'] as String?;

        if (snapshot.exists && existingUid != firebaseUser.uid) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'username-taken',
            message: 'This nickname is already taken.',
          );
        }

        transaction.set(usernameRef, {
          'uid': firebaseUser.uid,
          'username': candidate,
          'usernameKey': key,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (previousSnapshot != null &&
            previousSnapshot.exists &&
            previousUid == firebaseUser.uid) {
          transaction.delete(previousRef!);
        }
      });

      return candidate;
    } on FirebaseException catch (error) {
      if (!allowFallback || error.code != 'username-taken') {
        rethrow;
      }
    }
  }

  throw FirebaseException(
    plugin: 'cloud_firestore',
    code: 'username-taken',
    message: 'This nickname is already taken.',
  );
}

Future<UserRole> defaultRoleForNewFirebaseUser() async {
  // New users must always be regular users.
  // Admin rights are assigned manually in Firebase Console.
  return UserRole.user;
}

Future<AppUser?> loadCurrentFirebaseUser() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return null;
  }

  try {
    setCurrentUser(
      await saveFirebaseUser(
        firebaseUser,
        provider: providerNameForFirebaseUser(firebaseUser),
      ),
    );
    return currentUser;
  } catch (_) {
    return null;
  }
}

Future<AppUser> saveFirebaseUser(
  User firebaseUser, {
  required String provider,
  String? displayNameOverride,
  String? usernameOverride,
  String? emailOverride,
  String? photoUrlOverride,
  String? telegramUsername,
}) async {
  final userRef = FirebaseFirestore.instance
      .collection('users')
      .doc(firebaseUser.uid);
  final snapshot = await userRef.get();
  final data = snapshot.data();
  final isNewUser = !snapshot.exists;

  if (!isNewUser && userBanIsActive(data)) {
    throw FirebaseException(
      plugin: 'firebase_auth',
      code: 'user-banned',
      message: 'This account is banned.',
    );
  }

  if (!isNewUser && data?['deleted'] == true) {
    throw FirebaseException(
      plugin: 'firebase_auth',
      code: 'user-deleted',
      message: 'This account was removed.',
    );
  }

  final role = isNewUser
      ? await defaultRoleForNewFirebaseUser()
      : roleFromFirebase(data?['role']);
  final name = (data?['name'] as String?)?.trim().isNotEmpty == true
      ? data!['name'] as String
      : displayNameOverride?.trim().isNotEmpty == true
      ? displayNameOverride!.trim()
      : firebaseUser.displayName ?? 'CCS Driver';
  final rawUsername = (data?['username'] as String?)?.trim().isNotEmpty == true
      ? data!['username'] as String
      : usernameOverride?.trim().isNotEmpty == true
      ? usernameOverride!.trim()
      : makeUsernameFromFirebaseUser(firebaseUser);
  final username = await reserveUsernameForCurrentUser(
    preferredUsername: boundedProfileUsername(rawUsername),
    previousUsername: data?['username'] as String?,
    allowFallback: true,
  );
  final city = (data?['city'] as String?)?.trim().isNotEmpty == true
      ? data!['city'] as String
      : 'Riga';
  final country = (data?['country'] as String?)?.trim().isNotEmpty == true
      ? data!['country'] as String
      : 'Latvia';
  final photoUrl = (data?['photoUrl'] as String?)?.trim().isNotEmpty == true
      ? data!['photoUrl'] as String
      : photoUrlOverride ?? firebaseUser.photoURL;
  final bio = (data?['bio'] as String?)?.trim().isNotEmpty == true
      ? data!['bio'] as String
      : 'Night drive setup, Riga spots, clean reels, and low car routes.';
  final avatarPath = (data?['avatarPath'] as String?)?.trim().isNotEmpty == true
      ? data!['avatarPath'] as String
      : null;
  final verified = data?['verified'] == true;
  final settings = UserSettingsData.fromFirebase(data?['settings']);
  final garage = garageCarsFromFirebase(data?['garage']);

  userSettings.value = settings;
  garageCars.value = garage;

  final firebaseData = <String, Object?>{
    'uid': firebaseUser.uid,
    'name': name,
    'username': username,
    'usernameKey': usernameKey(username),
    'email': emailOverride ?? firebaseUser.email ?? '',
    'photoUrl': photoUrl,
    'bio': bio,
    'avatarPath': avatarPath,
    'city': city,
    'country': country,
    'settings': settings.toFirebase(),
    'instagram': settings.instagram.trim(),
    'tiktok': settings.tiktok.trim(),
    'telegram': settings.telegram.trim(),
    'reviewNotifications': settings.reviewNotifications,
    'likeNotifications': settings.likeNotifications,
    'commentNotifications': settings.commentNotifications,
    'newSpotNotifications': settings.newSpotNotifications,
    'newMessageNotifications': settings.newMessageNotifications,
    'publicProfile': settings.publicProfile,
    'showGarage': settings.showGarage,
    'garage': garage.map((car) => car.toFirebase()).toList(),
    'provider': provider,
    'telegramUsername': telegramUsername,
    'isOnline': true,
    'lastSeenAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  if (isNewUser) {
    firebaseData['role'] = roleName(role);
    firebaseData['verified'] = verified;
    firebaseData['banned'] = false;
    firebaseData['deleted'] = false;
    firebaseData['createdAt'] = FieldValue.serverTimestamp();
  }

  await userRef.set(firebaseData, SetOptions(merge: true));

  return AppUser(
    uid: firebaseUser.uid,
    name: name,
    username: username,
    email: emailOverride ?? firebaseUser.email ?? '',
    photoUrl: photoUrl,
    bio: bio,
    avatarPath: avatarPath,
    role: role,
    verified: verified,
    city: city,
    country: country,
  );
}

Future<AppUser> signInWithTelegramAndSaveUser() async {
  if (!firebaseReady) {
    throw Exception(
      googleSignInSetupError ??
          'Firebase did not initialize on this device. Check setup first.',
    );
  }

  final baseUrl = telegramAuthBaseUrl.trim();
  if (baseUrl.contains('YOUR_CCS_TELEGRAM_AUTH_BACKEND')) {
    throw Exception(
      'Telegram backend URL is not set. Deploy telegram_auth_server first.',
    );
  }

  final startData = await getJsonFromUrl('$baseUrl/api/telegram-start');
  final sessionId = stringFromFirebase(startData['sessionId'], '');
  final loginUrl = stringFromFirebase(startData['loginUrl'], '');

  if (sessionId.isEmpty || loginUrl.isEmpty) {
    throw Exception('Telegram backend returned an invalid login session.');
  }

  final opened = await launchUrl(
    Uri.parse(loginUrl),
    mode: LaunchMode.externalApplication,
  );

  if (!opened) {
    throw Exception('Could not open Telegram login page.');
  }

  Map<String, dynamic>? completeData;

  for (var attempt = 0; attempt < 90; attempt++) {
    await Future.delayed(const Duration(seconds: 2));

    final statusData = await getJsonFromUrl(
      '$baseUrl/api/telegram-status?sessionId=${Uri.encodeComponent(sessionId)}',
    );
    final status = stringFromFirebase(statusData['status'], 'pending');

    if (status == 'complete') {
      completeData = statusData;
      break;
    }

    if (status == 'error') {
      throw Exception(
        stringFromFirebase(statusData['message'], 'Telegram login failed.'),
      );
    }
  }

  if (completeData == null) {
    throw Exception('Telegram login timed out. Try again.');
  }

  final firebaseToken = stringFromFirebase(completeData['firebaseToken'], '');
  final telegramData = mapFromFirebase(completeData['telegram']);

  if (firebaseToken.isEmpty) {
    throw Exception('Telegram backend did not return a Firebase token.');
  }

  final userCredential = await FirebaseAuth.instance.signInWithCustomToken(
    firebaseToken,
  );
  final firebaseUser = userCredential.user;

  if (firebaseUser == null) {
    throw Exception('Firebase login finished without a user.');
  }

  final telegramUsername = stringFromFirebase(telegramData['username'], '');
  final firstName = stringFromFirebase(telegramData['first_name'], '');
  final lastName = stringFromFirebase(telegramData['last_name'], '');
  final fullName = ('$firstName $lastName').trim();
  final telegramId = stringFromFirebase(telegramData['id'], firebaseUser.uid);
  final photoUrl = stringFromFirebase(telegramData['photo_url'], '');
  final fallbackUsername = telegramUsername.isNotEmpty
      ? telegramUsername
      : 'telegram_$telegramId';

  setCurrentUser(
    await saveFirebaseUser(
      firebaseUser,
      provider: 'telegram',
      displayNameOverride: fullName.isEmpty ? '$fallbackUsername' : fullName,
      usernameOverride: fallbackUsername,
      emailOverride: '',
      photoUrlOverride: photoUrl.isEmpty ? null : photoUrl,
      telegramUsername: fallbackUsername,
    ),
  );
  startFirebaseSpotSync();
  unawaited(initializePushNotificationsForCurrentUser());
  return currentUser;
}

Future<Map<String, dynamic>> getJsonFromUrl(
  String url, {
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();

  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }

    final response = await request.close();
    final body = await utf8.decodeStream(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed ${response.statusCode}: $body');
    }

    final decoded = jsonDecode(body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw Exception('Backend returned invalid JSON.');
  } finally {
    client.close(force: true);
  }
}

bool isNetworkUrl(String? value) {
  final cleanValue = value?.trim() ?? '';
  return cleanValue.startsWith('http://') || cleanValue.startsWith('https://');
}

String imageContentTypeForPath(String path) {
  // R2 uploads are normalized to compressed JPEGs to keep storage and bandwidth low.
  return 'image/jpeg';
}

String imageExtensionForPath(String path) {
  // Keep all uploaded images as JPG, even if the original phone image was PNG/WEBP.
  return 'jpg';
}

String safeR2Path(String value) {
  final clean = value
      .trim()
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'^/+'), '')
      .replaceAll(RegExp(r'/+'), '/');

  return clean.replaceAll(RegExp(r'[^a-zA-Z0-9_./-]'), '_');
}

Future<List<int>> compressedJpegBytesFromFile(
  String localPhotoPath, {
  int maxLongSide = r2SpotPhotoMaxLongSide,
  int quality = r2JpegQuality,
}) async {
  final file = File(localPhotoPath);

  if (!await file.exists()) {
    throw Exception('Selected image file was not found on this phone.');
  }

  final originalBytes = await file.readAsBytes();
  final decoded = img.decodeImage(originalBytes);

  if (decoded == null) {
    throw Exception('Could not read selected image. Try another photo.');
  }

  var normalized = img.bakeOrientation(decoded);
  final longestSide = math.max(normalized.width, normalized.height);

  if (longestSide > maxLongSide) {
    final scale = maxLongSide / longestSide;
    normalized = img.copyResize(
      normalized,
      width: math.max(1, (normalized.width * scale).round()),
      height: math.max(1, (normalized.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  }

  return img.encodeJpg(normalized, quality: quality);
}

Future<Map<String, dynamic>> postJsonToUrl(
  String url,
  Map<String, Object?> body, {
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();

  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    request.add(utf8.encode(jsonEncode(body)));

    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);
    debugPrint('POST $url -> ${response.statusCode}: $responseBody');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed ${response.statusCode}: $responseBody');
    }

    final decoded = jsonDecode(responseBody);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw Exception('Backend returned invalid JSON.');
  } finally {
    client.close(force: true);
  }
}

Future<void> sendPushNotificationEvent(Map<String, Object?> event) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    debugPrint(
      'Push event skipped because there is no signed-in Firebase user. event=$event',
    );
    return;
  }

  try {
    final idToken = await firebaseUser.getIdToken(true);

    if (idToken == null || idToken.trim().isEmpty) {
      debugPrint(
        'Push event skipped because Firebase ID token is empty. event=$event',
      );
      return;
    }

    debugPrint('Sending push event: $event');
    await postJsonToUrl(
      pushNotificationUrl,
      {...event, 'senderUserId': firebaseUser.uid},
      headers: {HttpHeaders.authorizationHeader: 'Bearer $idToken'},
    );
    debugPrint('Push event accepted by backend: $event');
  } catch (error, stack) {
    debugPrint('Push event failed: $error');
    debugPrint('$stack');
  }
}

Future<void> putBytesToPresignedUrl({
  required String uploadUrl,
  required List<int> bytes,
  required String contentType,
}) async {
  final client = HttpClient();

  try {
    final request = await client.putUrl(Uri.parse(uploadUrl));
    request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    request.contentLength = bytes.length;
    request.add(bytes);

    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('R2 upload failed ${response.statusCode}: $responseBody');
    }
  } finally {
    client.close(force: true);
  }
}

Future<String> uploadImageBytesToR2({
  required String r2Path,
  required List<int> bytes,
  String contentType = 'image/jpeg',
}) async {
  final presignData = await postJsonToUrl(r2PresignUploadUrl, {
    'path': safeR2Path(r2Path),
    'contentType': contentType,
  });

  final uploadUrl = stringFromFirebase(presignData['uploadUrl'], '');
  final publicUrl = stringFromFirebase(presignData['publicUrl'], '');

  if (uploadUrl.isEmpty || publicUrl.isEmpty) {
    throw Exception('R2 backend did not return upload URL.');
  }

  await putBytesToPresignedUrl(
    uploadUrl: uploadUrl,
    bytes: bytes,
    contentType: contentType,
  );

  return publicUrl;
}

Future<String> uploadImageToR2({
  required String r2Path,
  required String localPhotoPath,
  int maxLongSide = r2SpotPhotoMaxLongSide,
  int quality = r2JpegQuality,
}) async {
  final bytes = await compressedJpegBytesFromFile(
    localPhotoPath,
    maxLongSide: maxLongSide,
    quality: quality,
  );

  return uploadImageBytesToR2(
    r2Path: r2Path,
    bytes: bytes,
    contentType: 'image/jpeg',
  );
}

Future<AppUser> signInWithGoogleAndSaveUser() async {
  if (!firebaseReady) {
    throw Exception(
      googleSignInSetupError ??
          'Firebase did not initialize on this device. Check google-services.json and Android setup.',
    );
  }

  if (googleSignInSetupError != null) {
    throw Exception(googleSignInSetupError);
  }

  if (!GoogleSignIn.instance.supportsAuthenticate()) {
    throw Exception('Google Sign-In is not supported on this platform.');
  }

  final googleUser = await GoogleSignIn.instance.authenticate();
  final googleAuth = googleUser.authentication;
  final idToken = googleAuth.idToken;

  if (idToken == null) {
    throw Exception('Google did not return an ID token.');
  }

  final credential = GoogleAuthProvider.credential(idToken: idToken);
  final userCredential = await FirebaseAuth.instance.signInWithCredential(
    credential,
  );
  final firebaseUser = userCredential.user;

  if (firebaseUser == null) {
    throw Exception('Firebase login finished without a user.');
  }

  setCurrentUser(await saveFirebaseUser(firebaseUser, provider: 'google'));
  startFirebaseSpotSync();
  unawaited(initializePushNotificationsForCurrentUser());
  return currentUser;
}

class UserSettingsData {
  final String instagram;
  final String tiktok;
  final String telegram;
  final bool reviewNotifications;
  final bool likeNotifications;
  final bool commentNotifications;
  final bool newSpotNotifications;
  final bool newMessageNotifications;
  final bool publicProfile;
  final bool showGarage;

  const UserSettingsData({
    required this.instagram,
    required this.tiktok,
    required this.telegram,
    required this.reviewNotifications,
    required this.likeNotifications,
    required this.commentNotifications,
    required this.newSpotNotifications,
    this.newMessageNotifications = true,
    required this.publicProfile,
    required this.showGarage,
  });

  factory UserSettingsData.fromFirebase(Object? value) {
    final data = mapFromFirebase(value);
    final defaults = defaultUserSettings();

    return UserSettingsData(
      instagram: stringFromFirebase(data['instagram'], defaults.instagram),
      tiktok: stringFromFirebase(data['tiktok'], defaults.tiktok),
      telegram: stringFromFirebase(data['telegram'], defaults.telegram),
      reviewNotifications: boolFromFirebase(
        data['reviewNotifications'],
        defaults.reviewNotifications,
      ),
      likeNotifications: boolFromFirebase(
        data['likeNotifications'],
        defaults.likeNotifications,
      ),
      commentNotifications: boolFromFirebase(
        data['commentNotifications'],
        defaults.commentNotifications,
      ),
      newSpotNotifications: boolFromFirebase(
        data['newSpotNotifications'],
        defaults.newSpotNotifications,
      ),
      newMessageNotifications: boolFromFirebase(
        data['newMessageNotifications'],
        defaults.newMessageNotifications,
      ),
      publicProfile: boolFromFirebase(
        data['publicProfile'],
        defaults.publicProfile,
      ),
      showGarage: boolFromFirebase(data['showGarage'], defaults.showGarage),
    );
  }

  Map<String, Object?> toFirebase() {
    return {
      'instagram': instagram,
      'tiktok': tiktok,
      'telegram': telegram,
      'reviewNotifications': reviewNotifications,
      'likeNotifications': likeNotifications,
      'commentNotifications': commentNotifications,
      'newSpotNotifications': newSpotNotifications,
      'newMessageNotifications': newMessageNotifications,
      'publicProfile': publicProfile,
      'showGarage': showGarage,
    };
  }

  UserSettingsData copyWith({
    String? instagram,
    String? tiktok,
    String? telegram,
    bool? reviewNotifications,
    bool? likeNotifications,
    bool? commentNotifications,
    bool? newSpotNotifications,
    bool? newMessageNotifications,
    bool? publicProfile,
    bool? showGarage,
  }) {
    return UserSettingsData(
      instagram: instagram ?? this.instagram,
      tiktok: tiktok ?? this.tiktok,
      telegram: telegram ?? this.telegram,
      reviewNotifications: reviewNotifications ?? this.reviewNotifications,
      likeNotifications: likeNotifications ?? this.likeNotifications,
      commentNotifications: commentNotifications ?? this.commentNotifications,
      newSpotNotifications: newSpotNotifications ?? this.newSpotNotifications,
      newMessageNotifications:
          newMessageNotifications ?? this.newMessageNotifications,
      publicProfile: publicProfile ?? this.publicProfile,
      showGarage: showGarage ?? this.showGarage,
    );
  }
}

Future<void> saveCurrentUserSettings(UserSettingsData settings) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    userSettings.value = settings;
    return;
  }

  userSettings.value = settings;

  await usersCollection().doc(firebaseUser.uid).set({
    'settings': settings.toFirebase(),
    'instagram': settings.instagram.trim(),
    'tiktok': settings.tiktok.trim(),
    'telegram': settings.telegram.trim(),
    'reviewNotifications': settings.reviewNotifications,
    'likeNotifications': settings.likeNotifications,
    'commentNotifications': settings.commentNotifications,
    'newSpotNotifications': settings.newSpotNotifications,
    'newMessageNotifications': settings.newMessageNotifications,
    'publicProfile': settings.publicProfile,
    'showGarage': settings.showGarage,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

UserSettingsData defaultUserSettings() {
  return const UserSettingsData(
    instagram: '',
    tiktok: '',
    telegram: '',
    reviewNotifications: true,
    likeNotifications: true,
    commentNotifications: true,
    newSpotNotifications: true,
    newMessageNotifications: true,
    publicProfile: true,
    showGarage: true,
  );
}

class CarSpot {
  final String id;
  final String name;
  final String cityCountry;
  final LatLng coordinates;
  final String description;
  final List<String> categories;
  final double rating;
  final String photoUrl;
  final List<String> photoUrls;
  final String? localPhotoPath;
  final String reelLink;
  final String contactPhone;
  final String contactInstagram;
  final String contactEmail;
  final Map<int, OpeningHoursData> openingHours;
  final String ownerUid;
  final String ownerUsername;
  final String bestTime;
  final String parking;
  final String roadQuality;
  final bool lowCarFriendly;
  final String policeRisk;
  final String traffic;
  final String lighting;
  final String crowd;
  final String addedBy;
  final String addedByUid;
  final SpotStatus status;
  final int createdAtMillis;
  final bool isTemporary;
  final int? startsAtMillis;
  final int? expiresAtMillis;
  final int? showOnMapAtMillis;
  final bool verifiedOnly;
  final String rejectionReason;

  const CarSpot({
    this.id = '',
    required this.name,
    required this.cityCountry,
    required this.coordinates,
    required this.description,
    required this.categories,
    required this.rating,
    required this.photoUrl,
    this.photoUrls = const [],
    this.localPhotoPath,
    required this.reelLink,
    this.contactPhone = '',
    this.contactInstagram = '',
    this.contactEmail = '',
    this.openingHours = const {},
    this.ownerUid = '',
    this.ownerUsername = '',
    required this.bestTime,
    required this.parking,
    required this.roadQuality,
    required this.lowCarFriendly,
    required this.policeRisk,
    required this.traffic,
    required this.lighting,
    required this.crowd,
    required this.addedBy,
    this.addedByUid = '',
    required this.status,
    this.createdAtMillis = 0,
    this.isTemporary = false,
    this.startsAtMillis,
    this.expiresAtMillis,
    this.showOnMapAtMillis,
    this.verifiedOnly = false,
    this.rejectionReason = '',
  });

  CarSpot copyWith({
    String? id,
    String? name,
    String? cityCountry,
    LatLng? coordinates,
    String? description,
    List<String>? categories,
    double? rating,
    String? photoUrl,
    List<String>? photoUrls,
    String? localPhotoPath,
    String? reelLink,
    String? contactPhone,
    String? contactInstagram,
    String? contactEmail,
    Map<int, OpeningHoursData>? openingHours,
    String? ownerUid,
    String? ownerUsername,
    String? bestTime,
    String? parking,
    String? roadQuality,
    bool? lowCarFriendly,
    String? policeRisk,
    String? traffic,
    String? lighting,
    String? crowd,
    String? addedBy,
    String? addedByUid,
    SpotStatus? status,
    int? createdAtMillis,
    bool? isTemporary,
    int? startsAtMillis,
    int? expiresAtMillis,
    int? showOnMapAtMillis,
    bool? verifiedOnly,
    String? rejectionReason,
    bool clearTemporarySchedule = false,
    bool clearTemporaryMapReveal = false,
  }) {
    return CarSpot(
      id: id ?? this.id,
      name: name ?? this.name,
      cityCountry: cityCountry ?? this.cityCountry,
      coordinates: coordinates ?? this.coordinates,
      description: description ?? this.description,
      categories: categories ?? this.categories,
      rating: rating ?? this.rating,
      photoUrl: photoUrl ?? this.photoUrl,
      photoUrls: photoUrls ?? this.photoUrls,
      localPhotoPath: localPhotoPath ?? this.localPhotoPath,
      reelLink: reelLink ?? this.reelLink,
      contactPhone: contactPhone ?? this.contactPhone,
      contactInstagram: contactInstagram ?? this.contactInstagram,
      contactEmail: contactEmail ?? this.contactEmail,
      openingHours: openingHours ?? this.openingHours,
      ownerUid: ownerUid ?? this.ownerUid,
      ownerUsername: ownerUsername ?? this.ownerUsername,
      bestTime: bestTime ?? this.bestTime,
      parking: parking ?? this.parking,
      roadQuality: roadQuality ?? this.roadQuality,
      lowCarFriendly: lowCarFriendly ?? this.lowCarFriendly,
      policeRisk: policeRisk ?? this.policeRisk,
      traffic: traffic ?? this.traffic,
      lighting: lighting ?? this.lighting,
      crowd: crowd ?? this.crowd,
      addedBy: addedBy ?? this.addedBy,
      addedByUid: addedByUid ?? this.addedByUid,
      status: status ?? this.status,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
      isTemporary: isTemporary ?? this.isTemporary,
      startsAtMillis: clearTemporarySchedule
          ? null
          : startsAtMillis ?? this.startsAtMillis,
      expiresAtMillis: clearTemporarySchedule
          ? null
          : expiresAtMillis ?? this.expiresAtMillis,
      showOnMapAtMillis: clearTemporarySchedule || clearTemporaryMapReveal
          ? null
          : showOnMapAtMillis ?? this.showOnMapAtMillis,
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }

  bool get hasTemporaryWindow =>
      isTemporary && startsAtMillis != null && expiresAtMillis != null;

  bool get supportsContacts => categories.any(spotCategorySupportsContacts);

  bool get hasOwner => ownerUid.trim().isNotEmpty;

  bool get hasOpeningHours => openingHours.isNotEmpty;

  bool get hasContactInfo =>
      supportsContacts &&
      (contactPhone.trim().isNotEmpty ||
          contactInstagram.trim().isNotEmpty ||
          contactEmail.trim().isNotEmpty ||
          openingHours.isNotEmpty);

  bool get isExpired {
    final expiresAt = expiresAtMillis;
    return isTemporary &&
        expiresAt != null &&
        DateTime.now().millisecondsSinceEpoch >= expiresAt;
  }

  int? get effectiveShowOnMapAtMillis {
    if (!hasTemporaryWindow) {
      return null;
    }

    final customReveal = showOnMapAtMillis;
    if (customReveal != null) {
      return customReveal;
    }

    final startsAt = DateTime.fromMillisecondsSinceEpoch(startsAtMillis!);
    return DateTime(
      startsAt.year,
      startsAt.month,
      startsAt.day,
    ).millisecondsSinceEpoch;
  }

  bool get isTemporaryActiveNow {
    if (!hasTemporaryWindow) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    return now >= startsAtMillis! && now < expiresAtMillis!;
  }

  bool get isTemporaryUpcomingOnMap {
    if (!hasTemporaryWindow) {
      return false;
    }

    final revealAt = effectiveShowOnMapAtMillis;
    if (revealAt == null) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    return now >= revealAt && now < startsAtMillis! && now < expiresAtMillis!;
  }

  bool get isTemporaryLocationAvailableNow {
    if (!hasTemporaryWindow) {
      return !isTemporary;
    }

    final revealAt = effectiveShowOnMapAtMillis;
    if (revealAt == null) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    return now >= revealAt && now < expiresAtMillis!;
  }

  bool get isTemporaryMapVisibleNow => isTemporaryLocationAvailableNow;

  bool get isVisibleOnMapNow {
    if (!isTemporary) {
      return true;
    }

    return isTemporaryMapVisibleNow;
  }

  bool get isVisibleNow {
    if (!isTemporary) {
      return true;
    }

    return hasTemporaryWindow && !isExpired;
  }

  String get temporaryStartsAtLabel {
    final startsAt = startsAtMillis;
    if (startsAt == null) {
      return '';
    }

    return 'starts at ${formatClockTime(DateTime.fromMillisecondsSinceEpoch(startsAt))}';
  }

  String get temporaryStartingAtLabel {
    final startsAt = startsAtMillis;
    if (startsAt == null) {
      return '';
    }

    return 'starting at ${formatClockTime(DateTime.fromMillisecondsSinceEpoch(startsAt))}';
  }

  String get temporaryLocationAvailableAtLabel {
    final revealAt = effectiveShowOnMapAtMillis;
    if (revealAt == null) {
      return '';
    }

    final revealDate = DateTime.fromMillisecondsSinceEpoch(revealAt);
    final now = DateTime.now();
    final revealText = isSameLocalDate(now, revealDate)
        ? formatClockTime(revealDate)
        : formatShortDateTime(revealDate);
    return 'location will be available at $revealText';
  }

  String get temporaryEndsAtLabel {
    final expiresAt = expiresAtMillis;
    if (expiresAt == null) {
      return '';
    }

    return 'ends at ${formatClockTime(DateTime.fromMillisecondsSinceEpoch(expiresAt))}';
  }

  String get temporaryTodayLabel {
    return isTemporaryActiveNow ? temporaryEndsAtLabel : temporaryStartsAtLabel;
  }

  String get temporaryTimeLabel {
    if (!hasTemporaryWindow) {
      return '';
    }

    final startsAt = DateTime.fromMillisecondsSinceEpoch(startsAtMillis!);
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMillis!);
    return '${formatShortDateTime(startsAt)} - ${formatShortDateTime(expiresAt)}';
  }

  factory CarSpot.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final coordinates = safeLatLngFromFirestoreCoordinates(
      data['coordinates'],
      data['lat'],
      data['lng'],
    );

    return CarSpot(
      id: doc.id,
      name: stringFromFirebase(data['name'], 'Untitled spot'),
      cityCountry: stringFromFirebase(data['cityCountry'], 'Riga, Latvia'),
      coordinates: coordinates,
      description: stringFromFirebase(
        data['description'],
        'Submitted community car spot.',
      ),
      categories: stringListFromFirebase(data['categories'], const ['Photo']),
      rating: doubleFromFirebase(data['rating'], 0),
      photoUrl: stringFromFirebase(data['photoUrl'], ''),
      photoUrls: stringListFromFirebase(data['photoUrls'], const []),
      reelLink: stringFromFirebase(data['reelLink'], ''),
      contactPhone: stringFromFirebase(data['contactPhone'], ''),
      contactInstagram: stringFromFirebase(data['contactInstagram'], ''),
      contactEmail: stringFromFirebase(data['contactEmail'], ''),
      openingHours: openingHoursFromFirebase(data['openingHours']),
      ownerUid: stringFromFirebase(data['ownerUid'], ''),
      ownerUsername: stringFromFirebase(data['ownerUsername'], ''),
      bestTime: stringFromFirebase(data['bestTime'], 'Not reviewed'),
      parking: stringFromFirebase(data['parking'], 'Not reviewed'),
      roadQuality: stringFromFirebase(data['roadQuality'], 'Not reviewed'),
      lowCarFriendly: data['lowCarFriendly'] == true,
      policeRisk: stringFromFirebase(data['policeRisk'], 'Not reviewed'),
      traffic: stringFromFirebase(data['traffic'], 'Not reviewed'),
      lighting: stringFromFirebase(data['lighting'], 'Not reviewed'),
      crowd: stringFromFirebase(data['crowd'], 'Not reviewed'),
      addedBy: stringFromFirebase(data['addedBy'], 'ccs_driver'),
      addedByUid: stringFromFirebase(data['addedByUid'], ''),
      status: spotStatusFromFirebase(data['status']),
      createdAtMillis: timestampMillisFromFirebase(data['createdAt']),
      isTemporary: data['isTemporary'] == true,
      startsAtMillis: nullableTimestampMillisFromFirebase(data['startsAt']),
      expiresAtMillis: nullableTimestampMillisFromFirebase(data['expiresAt']),
      showOnMapAtMillis: nullableTimestampMillisFromFirebase(
        data['showOnMapAt'],
      ),
      verifiedOnly: data['verifiedOnly'] == true,
      rejectionReason: stringFromFirebase(data['rejectionReason'], ''),
    );
  }
}

String stringFromFirebase(Object? value, String fallback) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }

  return fallback;
}

double doubleFromFirebase(Object? value, double fallback) {
  double? parsed;

  if (value is num) {
    parsed = value.toDouble();
  } else if (value is String) {
    parsed = double.tryParse(value.trim().replaceAll(',', '.'));
  }

  if (parsed != null && parsed.isFinite) {
    return parsed;
  }

  return fallback;
}

int timestampMillisFromFirebase(Object? value) {
  if (value is Timestamp) {
    return value.millisecondsSinceEpoch;
  }

  if (value is num) {
    return value.toInt();
  }

  return 0;
}

int? nullableTimestampMillisFromFirebase(Object? value) {
  if (value is Timestamp) {
    return value.millisecondsSinceEpoch;
  }

  if (value is num) {
    return value.toInt();
  }

  return null;
}

String twoDigits(int value) => value.toString().padLeft(2, '0');

String formatShortDateTime(DateTime value) {
  return '${twoDigits(value.day)}.${twoDigits(value.month)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

String formatClockTime(DateTime value) {
  return '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

bool isSameLocalDate(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

String formatShortDate(DateTime value) {
  return '${twoDigits(value.day)}.${twoDigits(value.month)}.${value.year}';
}

List<String> stringListFromFirebase(Object? value, List<String> fallback) {
  if (value is List) {
    final list = value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();

    if (list.isNotEmpty) {
      return list;
    }
  }

  return fallback;
}

List<String> uniqueNonEmptyStrings(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];

  for (final value in values) {
    final cleanValue = value.trim();
    if (cleanValue.isEmpty || seen.contains(cleanValue)) {
      continue;
    }

    seen.add(cleanValue);
    result.add(cleanValue);
  }

  return result;
}

bool boolFromFirebase(Object? value, bool fallback) {
  return value is bool ? value : fallback;
}

Map<String, dynamic> mapFromFirebase(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  return <String, dynamic>{};
}

const LatLng fallbackRigaLatLng = LatLng(56.9496, 24.1052);

bool isValidLatLngValues(double? latitude, double? longitude) {
  return latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

bool isValidLatLng(LatLng? value) {
  return value != null &&
      isValidLatLngValues(value.latitude, value.longitude);
}

LatLng safeLatLng(
  double? latitude,
  double? longitude, {
  LatLng fallback = fallbackRigaLatLng,
}) {
  if (isValidLatLngValues(latitude, longitude)) {
    return LatLng(latitude!, longitude!);
  }

  return fallback;
}

LatLng safeLatLngFromFirestoreCoordinates(
  Object? coordinates,
  Object? lat,
  Object? lng, {
  LatLng fallback = fallbackRigaLatLng,
}) {
  if (coordinates is GeoPoint) {
    return safeLatLng(coordinates.latitude, coordinates.longitude, fallback: fallback);
  }

  return safeLatLng(
    doubleFromFirebase(lat, fallback.latitude),
    doubleFromFirebase(lng, fallback.longitude),
    fallback: fallback,
  );
}

LatLng? safeLatLngFromPosition(Position position) {
  if (!isValidLatLngValues(position.latitude, position.longitude)) {
    return null;
  }

  return LatLng(position.latitude, position.longitude);
}

bool userBanIsActive(Map<String, dynamic>? data) {
  if (data?['banned'] != true) {
    return false;
  }

  final untilMillis = nullableTimestampMillisFromFirebase(data?['bannedUntil']);
  return untilMillis == null ||
      untilMillis > DateTime.now().millisecondsSinceEpoch;
}

String userBanLabel({required bool banned, required int? bannedUntilMillis}) {
  if (!banned) {
    return 'Active';
  }

  if (bannedUntilMillis == null) {
    return 'Banned';
  }

  if (bannedUntilMillis <= DateTime.now().millisecondsSinceEpoch) {
    return 'Ban expired';
  }

  return 'Banned until ${formatShortDateTime(DateTime.fromMillisecondsSinceEpoch(bannedUntilMillis))}';
}

bool localFileExists(String? path) {
  if (path == null || path.trim().isEmpty) {
    return false;
  }

  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}

CollectionReference<Map<String, dynamic>> usersCollection() {
  return FirebaseFirestore.instance.collection('users');
}

class SpotOwnerAssignment {
  final String uid;
  final String username;

  const SpotOwnerAssignment({required this.uid, required this.username});
}

Future<SpotOwnerAssignment?> findSpotOwnerAssignment(
  String rawInput, {
  SpotOwnerAssignment? currentOwner,
}) async {
  final input = rawInput.trim();

  if (input.isEmpty) {
    return null;
  }

  final cleanInput = input.startsWith('@') ? input.substring(1) : input;

  if (currentOwner != null &&
      currentOwner.uid.isNotEmpty &&
      (cleanInput == currentOwner.uid ||
          usernameKey(cleanInput) == usernameKey(currentOwner.username))) {
    return currentOwner;
  }

  final byUid = await usersCollection().doc(cleanInput).get();
  if (byUid.exists) {
    final data = byUid.data() ?? {};
    return SpotOwnerAssignment(
      uid: byUid.id,
      username: stringFromFirebase(data['username'], byUid.id),
    );
  }

  final byUsername = await usersCollection()
      .where('usernameKey', isEqualTo: usernameKey(cleanInput))
      .limit(1)
      .get();
  if (byUsername.docs.isNotEmpty) {
    final doc = byUsername.docs.first;
    final data = doc.data();
    return SpotOwnerAssignment(
      uid: doc.id,
      username: stringFromFirebase(data['username'], doc.id),
    );
  }

  final byEmail = await usersCollection()
      .where('email', isEqualTo: input)
      .limit(1)
      .get();
  if (byEmail.docs.isNotEmpty) {
    final doc = byEmail.docs.first;
    final data = doc.data();
    return SpotOwnerAssignment(
      uid: doc.id,
      username: stringFromFirebase(data['username'], doc.id),
    );
  }

  return null;
}

CollectionReference<Map<String, dynamic>> liveLocationsCollection() {
  return FirebaseFirestore.instance.collection('live_locations');
}

class LiveLocationData {
  final String uid;
  final String username;
  final String name;
  final String? photoUrl;
  final UserRole role;
  final bool verified;
  final double headingDegrees;
  final LatLng coordinates;
  final List<String> visibleToUserIds;
  final String visibleToChatId;
  final String shareScope;
  final int shareDurationMinutes;
  final int promptAtMillis;
  final int expiresAtMillis;
  final int updatedAtMillis;

  const LiveLocationData({
    required this.uid,
    required this.username,
    required this.name,
    this.photoUrl,
    required this.role,
    required this.verified,
    this.headingDegrees = 0,
    required this.coordinates,
    this.visibleToUserIds = const [],
    this.visibleToChatId = '',
    this.shareScope = '',
    this.shareDurationMinutes = 60,
    required this.promptAtMillis,
    required this.expiresAtMillis,
    required this.updatedAtMillis,
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch >= expiresAtMillis;

  factory LiveLocationData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final coordinates = safeLatLngFromFirestoreCoordinates(
      data['coordinates'],
      data['lat'],
      data['lng'],
    );

    final role = roleFromFirebase(data['role']);

    return LiveLocationData(
      uid: stringFromFirebase(data['uid'], doc.id),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      name: stringFromFirebase(data['name'], 'CCS Driver'),
      photoUrl: data['photoUrl'] is String ? data['photoUrl'] as String : null,
      role: role,
      verified: userRoleIsStaff(role) || data['verified'] == true,
      headingDegrees: normalizedHeadingDegrees(
        doubleFromFirebase(data['heading'], 0),
      ),
      coordinates: coordinates,
      visibleToUserIds: stringListFromFirebase(
        data['visibleToUserIds'],
        const [],
      ),
      visibleToChatId: stringFromFirebase(data['visibleToChatId'], ''),
      shareScope: stringFromFirebase(data['shareScope'], ''),
      shareDurationMinutes: data['shareDurationMinutes'] is num
          ? (data['shareDurationMinutes'] as num).toInt()
          : 60,
      promptAtMillis: timestampMillisFromFirebase(data['promptAt']),
      expiresAtMillis: timestampMillisFromFirebase(data['expiresAt']),
      updatedAtMillis: timestampMillisFromFirebase(data['updatedAt']),
    );
  }
}

CollectionReference<Map<String, dynamic>> policeReportsCollection() {
  return FirebaseFirestore.instance.collection('police_reports');
}

CollectionReference<Map<String, dynamic>> sosReportsCollection() {
  return FirebaseFirestore.instance.collection('sos_reports');
}

CollectionReference<Map<String, dynamic>> meetNotificationsCollection() {
  return FirebaseFirestore.instance.collection('meet_notifications');
}

CollectionReference<Map<String, dynamic>> adminNotificationsCollection() {
  return FirebaseFirestore.instance.collection('admin_notifications');
}

Future<Map<String, dynamic>> patchJsonToUrl(
  String url,
  Map<String, Object?> body, {
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();

  try {
    final request = await client.patchUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    request.add(utf8.encode(jsonEncode(body)));

    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed ${response.statusCode}: $responseBody');
    }

    final decoded = jsonDecode(responseBody);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw Exception('Backend returned invalid JSON.');
  } finally {
    client.close(force: true);
  }
}

CollectionReference<Map<String, dynamic>> userNotificationsCollection() {
  return FirebaseFirestore.instance.collection('user_notifications');
}

String spotNotificationOwnerUid(CarSpot spot) {
  final ownerUid = spot.ownerUid.trim();
  if (ownerUid.isNotEmpty) {
    return ownerUid;
  }

  return spot.addedByUid.trim();
}

Future<bool> userNotificationPreferenceEnabled(
  String userId,
  String settingName,
) async {
  if (userId.trim().isEmpty) {
    return false;
  }

  try {
    final snapshot = await usersCollection().doc(userId).get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    final nestedSettings = mapFromFirebase(data['settings']);

    if (data[settingName] is bool) {
      return data[settingName] == true;
    }

    if (nestedSettings[settingName] is bool) {
      return nestedSettings[settingName] == true;
    }
  } catch (error, stack) {
    debugPrint(
      'Could not read notification setting $settingName for $userId: $error',
    );
    debugPrint('$stack');
  }

  // Missing settings are treated as enabled. This matches the app default.
  return true;
}

Future<void> createUserNotification({
  required String userId,
  required String type,
  required String title,
  required String body,
  required String settingName,
  String? notificationId,
  Map<String, Object?> extra = const {},
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final cleanUserId = userId.trim();

  if (firebaseUser == null ||
      cleanUserId.isEmpty ||
      cleanUserId == firebaseUser.uid) {
    return;
  }

  final allowed = await userNotificationPreferenceEnabled(
    cleanUserId,
    settingName,
  );
  if (!allowed) {
    debugPrint(
      'Notification skipped. userId=$cleanUserId disabled $settingName',
    );
    return;
  }

  try {
    final reference = notificationId == null || notificationId.trim().isEmpty
        ? userNotificationsCollection().doc()
        : userNotificationsCollection().doc(notificationId.trim());

    await reference.set({
      'userId': cleanUserId,
      'type': type,
      'title': title,
      'body': body,
      'actorUserId': firebaseUser.uid,
      'actorUsername': currentUser.username,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      ...extra,
    }, SetOptions(merge: true));

    unawaited(refreshNotificationCenterUnreadCount());
  } catch (error, stack) {
    debugPrint('Could not create notification center item: $error');
    debugPrint('$stack');
  }
}

Future<void> createSpotLikeNotification(CarSpot spot, String likeId) async {
  final ownerUid = spotNotificationOwnerUid(spot);
  await createUserNotification(
    userId: ownerUid,
    type: 'spot_like',
    title: 'Likes on my spots',
    body: '@${currentUser.username} liked ${spot.name}.',
    settingName: 'likeNotifications',
    notificationId: likeId.trim().isEmpty ? null : 'spot_like_$likeId',
    extra: {
      'spotId': spotReviewKey(spot),
      'spotName': spot.name,
      'cityCountry': spot.cityCountry,
    },
  );
}

Future<void> createSpotCommentNotification(
  CarSpot spot,
  String reviewId,
  String comment,
) async {
  final ownerUid = spotNotificationOwnerUid(spot);
  await createUserNotification(
    userId: ownerUid,
    type: 'spot_comment',
    title: 'Comments',
    body: '@${currentUser.username} commented on ${spot.name}.',
    settingName: 'commentNotifications',
    notificationId: reviewId.trim().isEmpty ? null : 'spot_comment_$reviewId',
    extra: {
      'reviewId': reviewId,
      'spotId': spotReviewKey(spot),
      'spotName': spot.name,
      'comment': comment.trim(),
      'cityCountry': spot.cityCountry,
    },
  );
}

Future<void> createSpotReviewUpdateNotification(
  CarSpot spot,
  SpotStatus status, {
  String rejectionReason = '',
}) async {
  if (status != SpotStatus.approved && status != SpotStatus.rejected) {
    return;
  }

  final ownerUid = spotNotificationOwnerUid(spot);
  final statusName = spotStatusName(status);
  final approved = status == SpotStatus.approved;
  final cleanReason = rejectionReason.trim();

  await createUserNotification(
    userId: ownerUid,
    type: 'spot_review_update',
    title: 'Spot review updates',
    body: approved
        ? '${spot.name} was approved.'
        : cleanReason.isEmpty
        ? '${spot.name} was rejected.'
        : '${spot.name} was rejected. Reason: $cleanReason',
    settingName: 'reviewNotifications',
    notificationId: spot.id.trim().isEmpty
        ? null
        : 'spot_review_${spot.id}_${statusName}_$ownerUid',
    extra: {
      'spotId': spot.id.trim().isEmpty ? spotReviewKey(spot) : spot.id.trim(),
      'spotName': spot.name,
      'cityCountry': spot.cityCountry,
      'status': statusName,
      'reviewedBy': currentUser.username,
      'reviewedByUid': currentUser.uid,
      if (cleanReason.isNotEmpty) 'rejectionReason': cleanReason,
    },
  );
}

Future<void> createNewSpotNotificationForUsers(CarSpot spot) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null || spot.status != SpotStatus.approved) {
    return;
  }

  final type = spot.isTemporary ? 'temporary_event' : 'new_spot';
  final title = spot.isTemporary ? 'Temporary events' : 'New spots';
  final body = spot.isTemporary
      ? '${spot.name} event was added in ${spot.cityCountry}.'
      : '${spot.name} was added in ${spot.cityCountry}.';

  try {
    final usersSnapshot = await usersCollection().limit(500).get();
    final batch = FirebaseFirestore.instance.batch();
    var writes = 0;

    for (final doc in usersSnapshot.docs) {
      final userId = doc.id;
      final data = doc.data();
      if (userId == firebaseUser.uid || data['deleted'] == true) {
        continue;
      }

      final nestedSettings = mapFromFirebase(data['settings']);
      final enabled = data['newSpotNotifications'] is bool
          ? data['newSpotNotifications'] == true
          : boolFromFirebase(nestedSettings['newSpotNotifications'], true);
      if (!enabled) {
        continue;
      }

      final notificationId = '${type}_${spot.id}_$userId';
      batch.set(userNotificationsCollection().doc(notificationId), {
        'userId': userId,
        'type': type,
        'title': title,
        'body': body,
        'actorUserId': firebaseUser.uid,
        'actorUsername': currentUser.username,
        'spotId': spot.id,
        'spotName': spot.name,
        'cityCountry': spot.cityCountry,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      writes++;

      if (writes >= 450) {
        break;
      }
    }

    if (writes > 0) {
      await batch.commit();
    }
  } catch (error, stack) {
    debugPrint('Could not create new spot notifications: $error');
    debugPrint('$stack');
  }
}

Future<void> createChatMessageNotification({
  required ChatThreadData chat,
  required String messageText,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null) {
    return;
  }

  final recipients = chat.memberIds
      .where((uid) => uid.trim().isNotEmpty && uid != firebaseUser.uid)
      .toSet();
  for (final userId in recipients) {
    await createUserNotification(
      userId: userId,
      type: 'chat_message',
      title: 'Messages',
      body: chat.isGroup
          ? '@${currentUser.username} in ${chat.titleForCurrentUser(userId)}: $messageText'
          : '@${currentUser.username}: $messageText',
      settingName: 'newMessageNotifications',
      notificationId:
          'chat_${chat.id}_${DateTime.now().microsecondsSinceEpoch}_$userId',
      extra: {'chatId': chat.id, 'isGroup': chat.isGroup},
    );
  }
}

void startNotificationCenterUnreadWatcher() {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    notificationCenterUnreadCount.value = 0;
    return;
  }

  notificationCenterUnreadSubscription?.cancel();
  notificationCenterUnreadSubscription = userNotificationsCollection()
      .where('userId', isEqualTo: firebaseUser.uid)
      .where('read', isEqualTo: false)
      .snapshots()
      .listen(
        (snapshot) {
          notificationCenterUnreadCount.value = snapshot.docs.length;
        },
        onError: (Object error, StackTrace stack) {
          debugPrint('Notification unread watcher failed: $error');
          debugPrint('$stack');
        },
      );
}

CollectionReference<Map<String, dynamic>> projectNewsCollection() {
  return FirebaseFirestore.instance.collection('project_news');
}

CollectionReference<Map<String, dynamic>> friendRequestsCollection() {
  return FirebaseFirestore.instance.collection('friend_requests');
}

CollectionReference<Map<String, dynamic>> friendshipsCollection() {
  return FirebaseFirestore.instance.collection('friendships');
}

CollectionReference<Map<String, dynamic>>
friendLocationNotificationsCollection() {
  return FirebaseFirestore.instance.collection('friend_location_notifications');
}

CollectionReference<Map<String, dynamic>> chatsCollection() {
  return FirebaseFirestore.instance.collection('chats');
}

CollectionReference<Map<String, dynamic>> chatMessagesCollection(
  String chatId,
) {
  return chatsCollection().doc(chatId).collection('messages');
}

String friendshipIdFor(String firstUid, String secondUid) {
  final ids = [firstUid, secondUid]..sort();
  return '${ids[0]}_${ids[1]}';
}

String friendRequestIdFor(String fromUid, String toUid) {
  return '${fromUid}_$toUid';
}

class FriendUserData {
  final String uid;
  final String username;
  final String name;
  final String email;
  final String? photoUrl;
  final String? avatarPath;
  final bool verified;
  final UserRole role;
  final bool banned;
  final int? bannedUntilMillis;
  final bool deleted;
  final bool isOnline;
  final int lastSeenAtMillis;
  final bool isSharingLiveLocation;
  final int? liveLocationExpiresAtMillis;
  final List<String> liveLocationVisibleToUserIds;

  const FriendUserData({
    required this.uid,
    required this.username,
    required this.name,
    required this.email,
    this.photoUrl,
    this.avatarPath,
    required this.verified,
    required this.role,
    required this.banned,
    this.bannedUntilMillis,
    required this.deleted,
    this.isOnline = false,
    this.lastSeenAtMillis = 0,
    this.isSharingLiveLocation = false,
    this.liveLocationExpiresAtMillis,
    this.liveLocationVisibleToUserIds = const [],
  });

  bool get canSeeLiveLocationPresence {
    final currentUid =
        FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;

    return currentUid.trim().isNotEmpty &&
        (uid == currentUid ||
            liveLocationVisibleToUserIds.contains(currentUid));
  }

  bool get appearsOnline => userAppearsOnlineFromPresence(
    isOnline: isOnline,
    lastSeenAtMillis: lastSeenAtMillis,
    isSharingLiveLocation: isSharingLiveLocation && canSeeLiveLocationPresence,
    liveLocationExpiresAtMillis: liveLocationExpiresAtMillis,
  );

  bool get banActive {
    return banned &&
        (bannedUntilMillis == null ||
            bannedUntilMillis! > DateTime.now().millisecondsSinceEpoch);
  }

  bool get canAppearInUserLists => !deleted && !banActive;

  factory FriendUserData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final role = roleFromFirebase(data['role']);
    final bannedUntilMillis = nullableTimestampMillisFromFirebase(
      data['bannedUntil'],
    );

    return FriendUserData(
      uid: stringFromFirebase(data['uid'], doc.id),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      name: stringFromFirebase(data['name'], 'CCS Driver'),
      email: stringFromFirebase(data['email'], ''),
      photoUrl: data['photoUrl'] is String ? data['photoUrl'] as String : null,
      avatarPath: data['avatarPath'] is String
          ? data['avatarPath'] as String
          : null,
      role: role,
      verified: userRoleIsStaff(role) || data['verified'] == true,
      banned: data['banned'] == true,
      bannedUntilMillis: bannedUntilMillis,
      deleted: data['deleted'] == true,
      isOnline: data['isOnline'] == true,
      lastSeenAtMillis: timestampMillisFromFirebase(data['lastSeenAt']),
      isSharingLiveLocation: data['isSharingLiveLocation'] == true,
      liveLocationExpiresAtMillis: nullableTimestampMillisFromFirebase(
        data['liveLocationExpiresAt'],
      ),
      liveLocationVisibleToUserIds: stringListFromFirebase(
        data['liveLocationVisibleToUserIds'],
        const [],
      ),
    );
  }
}

class FriendRequestData {
  final String id;
  final String fromUid;
  final String fromUsername;
  final String fromName;
  final String toUid;
  final String toUsername;
  final String toName;
  final String status;
  final int createdAtMillis;

  const FriendRequestData({
    required this.id,
    required this.fromUid,
    required this.fromUsername,
    required this.fromName,
    required this.toUid,
    required this.toUsername,
    required this.toName,
    required this.status,
    required this.createdAtMillis,
  });

  factory FriendRequestData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return FriendRequestData(
      id: doc.id,
      fromUid: stringFromFirebase(data['fromUid'], ''),
      fromUsername: stringFromFirebase(data['fromUsername'], 'ccs_driver'),
      fromName: stringFromFirebase(data['fromName'], 'CCS Driver'),
      toUid: stringFromFirebase(data['toUid'], ''),
      toUsername: stringFromFirebase(data['toUsername'], 'ccs_driver'),
      toName: stringFromFirebase(data['toName'], 'CCS Driver'),
      status: stringFromFirebase(data['status'], 'pending'),
      createdAtMillis: timestampMillisFromFirebase(data['createdAt']),
    );
  }
}

Future<bool> areUsersFriends(String firstUid, String secondUid) async {
  if (firstUid.trim().isEmpty || secondUid.trim().isEmpty) {
    return false;
  }

  final snapshot = await friendshipsCollection()
      .doc(friendshipIdFor(firstUid, secondUid))
      .get();
  return snapshot.exists;
}

Future<String?> pendingRequestStatusBetweenUsers(
  String firstUid,
  String secondUid,
) async {
  final outgoing = await friendRequestsCollection()
      .doc(friendRequestIdFor(firstUid, secondUid))
      .get();

  if (outgoing.exists && outgoing.data()?['status'] == 'pending') {
    return 'outgoing';
  }

  final incoming = await friendRequestsCollection()
      .doc(friendRequestIdFor(secondUid, firstUid))
      .get();

  if (incoming.exists && incoming.data()?['status'] == 'pending') {
    return 'incoming';
  }

  return null;
}

Future<void> sendFriendRequestToUser(FriendUserData user) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before adding friends.',
    );
  }

  if (user.uid == firebaseUser.uid) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'cannot-add-yourself',
      message: 'You cannot add yourself as a friend.',
    );
  }

  if (await areUsersFriends(firebaseUser.uid, user.uid)) {
    return;
  }

  final incomingRef = friendRequestsCollection().doc(
    friendRequestIdFor(user.uid, firebaseUser.uid),
  );
  final incoming = await incomingRef.get();

  if (incoming.exists && incoming.data()?['status'] == 'pending') {
    await acceptFriendRequest(FriendRequestData.fromFirestore(incoming));
    return;
  }

  await friendRequestsCollection()
      .doc(friendRequestIdFor(firebaseUser.uid, user.uid))
      .set({
        'fromUid': firebaseUser.uid,
        'fromUsername': currentUser.username,
        'fromName': currentUser.name,
        'toUid': user.uid,
        'toUsername': user.username,
        'toName': user.name,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}

Future<void> acceptFriendRequest(FriendRequestData request) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null || request.toUid != firebaseUser.uid) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Only the invited user can accept this request.',
    );
  }

  final friendshipRef = friendshipsCollection().doc(
    friendshipIdFor(request.fromUid, request.toUid),
  );
  final requestRef = friendRequestsCollection().doc(request.id);

  await FirebaseFirestore.instance.runTransaction((transaction) async {
    transaction.set(friendshipRef, {
      'userIds': [request.fromUid, request.toUid]..sort(),
      'users': {
        request.fromUid: {
          'uid': request.fromUid,
          'username': request.fromUsername,
          'name': request.fromName,
        },
        request.toUid: {
          'uid': request.toUid,
          'username': request.toUsername,
          'name': request.toName,
        },
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    transaction.set(requestRef, {
      'status': 'accepted',
      'respondedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  });
}

Future<void> declineFriendRequest(FriendRequestData request) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null || request.toUid != firebaseUser.uid) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Only the invited user can decline this request.',
    );
  }

  await friendRequestsCollection().doc(request.id).set({
    'status': 'declined',
    'respondedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> cancelFriendRequest(FriendRequestData request) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null || request.fromUid != firebaseUser.uid) {
    return;
  }

  await friendRequestsCollection().doc(request.id).delete();
}

String friendUidFromFriendshipData(
  Map<String, dynamic> data,
  String currentUid,
) {
  final userIds = stringListFromFirebase(data['userIds'], const []);

  for (final uid in userIds) {
    if (uid != currentUid) {
      return uid;
    }
  }

  return '';
}

Future<void> removeFriendship(String friendUid) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return;
  }

  await friendshipsCollection()
      .doc(friendshipIdFor(firebaseUser.uid, friendUid))
      .delete();
}

const double friendNearbyRadiusMeters = 5000;
const double friendAtSpotRadiusMeters = 200;
const Duration friendLocationNotificationCooldown = Duration(minutes: 30);

String friendNearbyNotificationId(String userId, String friendUid) {
  return 'nearby_${userId}_$friendUid';
}

String friendSpotNotificationId(
  String userId,
  String friendUid,
  String spotId,
) {
  return 'spot_${userId}_${friendUid}_$spotId';
}

Future<List<String>> loadCurrentFriendUids() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return const [];
  }

  final snapshot = await friendshipsCollection()
      .where('userIds', arrayContains: firebaseUser.uid)
      .get();

  return snapshot.docs
      .map((doc) => friendUidFromFriendshipData(doc.data(), firebaseUser.uid))
      .where((uid) => uid.trim().isNotEmpty)
      .toList();
}

Future<List<FriendUserData>> loadCurrentFriendUsers() async {
  final friendUids = await loadCurrentFriendUids();
  final friends = <FriendUserData>[];

  for (final uid in friendUids) {
    final snapshot = await usersCollection().doc(uid).get();
    if (snapshot.exists) {
      final user = FriendUserData.fromFirestore(snapshot);
      if (user.canAppearInUserLists) {
        friends.add(user);
      }
    }
  }

  friends.sort((a, b) {
    final onlineCompare = b.appearsOnline.toString().compareTo(
      a.appearsOnline.toString(),
    );
    if (onlineCompare != 0) {
      return onlineCompare;
    }

    return a.username.toLowerCase().compareTo(b.username.toLowerCase());
  });
  return friends;
}

Future<List<FriendUserData>> loadAllVisibleUsersForGroupInvite() async {
  final snapshot = await usersCollection().limit(200).get();
  final users = snapshot.docs
      .map(FriendUserData.fromFirestore)
      .where((user) => user.uid != currentUser.uid && user.canAppearInUserLists)
      .toList();

  users.sort((a, b) {
    final onlineCompare = b.appearsOnline.toString().compareTo(
      a.appearsOnline.toString(),
    );
    if (onlineCompare != 0) {
      return onlineCompare;
    }

    return a.username.toLowerCase().compareTo(b.username.toLowerCase());
  });

  return users;
}

String directChatIdFor(String firstUid, String secondUid) {
  final ids = [firstUid, secondUid]..sort();
  return 'direct_${ids[0]}_${ids[1]}';
}

Future<void> openMessageToUserFromContext(
  BuildContext context,
  FriendUserData user,
) async {
  try {
    final chatId = await createOrOpenDirectChat(user);
    final chat = ChatThreadData(
      id: chatId,
      isGroup: false,
      name: '',
      memberIds: [currentUser.uid, user.uid],
      memberUsernames: [currentUser.username, user.username],
      memberPhotoUrls: [currentUser.photoUrl ?? '', user.photoUrl ?? ''],
      lastMessage: '',
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    if (!context.mounted) {
      return;
    }

    Navigator.push(
      context,
      appPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'Could not open chat: $error',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class ChatThreadData {
  final String id;
  final bool isGroup;
  final String name;
  final String photoUrl;
  final String description;
  final List<String> memberIds;
  final List<String> memberUsernames;
  final List<String> memberPhotoUrls;
  final String lastMessage;
  final String lastSenderUid;
  final String lastSenderUsername;
  final String avatarUrl;
  final String ownerUid;
  final List<String> moderatorIds;
  final int updatedAtMillis;

  const ChatThreadData({
    required this.id,
    required this.isGroup,
    required this.name,
    this.photoUrl = '',
    this.description = '',
    required this.memberIds,
    required this.memberUsernames,
    this.memberPhotoUrls = const [],
    required this.lastMessage,
    this.lastSenderUid = '',
    this.lastSenderUsername = '',
    this.avatarUrl = '',
    this.ownerUid = '',
    this.moderatorIds = const [],
    required this.updatedAtMillis,
  });

  factory ChatThreadData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return ChatThreadData(
      id: doc.id,
      isGroup: data['isGroup'] == true,
      name: stringFromFirebase(data['name'], ''),
      photoUrl: stringFromFirebase(data['photoUrl'], ''),
      description: stringFromFirebase(data['description'], ''),
      memberIds: stringListFromFirebase(data['memberIds'], const []),
      memberUsernames: stringListFromFirebase(
        data['memberUsernames'],
        const [],
      ),
      memberPhotoUrls: stringListFromFirebase(
        data['memberPhotoUrls'],
        const [],
      ),
      lastMessage: stringFromFirebase(data['lastMessage'], ''),
      lastSenderUid: stringFromFirebase(data['lastSenderUid'], ''),
      lastSenderUsername: stringFromFirebase(data['lastSenderUsername'], ''),
      avatarUrl: stringFromFirebase(data['avatarUrl'], ''),
      ownerUid: stringFromFirebase(data['ownerUid'], ''),
      moderatorIds: stringListFromFirebase(data['moderatorIds'], const []),
      updatedAtMillis: timestampMillisFromFirebase(data['updatedAt']),
    );
  }

  String titleForCurrentUser(String currentUid) {
    if (isGroup) {
      return name.trim().isEmpty ? 'Group chat' : name.trim();
    }

    for (var index = 0; index < memberIds.length; index++) {
      if (memberIds[index] == currentUid) {
        continue;
      }

      if (index < memberUsernames.length &&
          memberUsernames[index].trim().isNotEmpty) {
        return displayUsername(memberUsernames[index]);
      }

      return 'Direct chat';
    }

    return 'Direct chat';
  }

  String subtitleForCurrentUser(String currentUid) {
    if (lastMessage.trim().isNotEmpty) {
      if (isGroup) {
        if (lastSenderUid.trim().isEmpty && lastSenderUsername.trim().isEmpty) {
          return lastMessage.trim();
        }

        final sender = lastSenderUid == currentUid
            ? 'You'
            : displayUsername(
                lastSenderUsername.trim().isEmpty
                    ? 'ccs_driver'
                    : lastSenderUsername,
              );
        return '$sender: ${lastMessage.trim()}';
      }

      return lastMessage.trim();
    }

    if (isGroup) {
      return description.trim().isNotEmpty
          ? description.trim()
          : '${memberIds.length} members';
    }

    return 'No messages yet';
  }

  String directPhotoUrlForCurrentUser(String currentUid) {
    if (isGroup) {
      return avatarUrl;
    }

    for (var index = 0; index < memberIds.length; index++) {
      if (memberIds[index] == currentUid) {
        continue;
      }

      if (index < memberPhotoUrls.length) {
        return memberPhotoUrls[index];
      }
    }

    return '';
  }
}

class ChatMessageData {
  final String id;
  final String senderUid;
  final String senderUsername;
  final String text;
  final int createdAtMillis;
  final bool edited;
  final int updatedAtMillis;

  const ChatMessageData({
    required this.id,
    required this.senderUid,
    required this.senderUsername,
    required this.text,
    required this.createdAtMillis,
    this.edited = false,
    this.updatedAtMillis = 0,
  });

  factory ChatMessageData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return ChatMessageData(
      id: doc.id,
      senderUid: stringFromFirebase(data['senderUid'], ''),
      senderUsername: stringFromFirebase(data['senderUsername'], 'ccs_driver'),
      text: stringFromFirebase(data['text'], ''),
      createdAtMillis: timestampMillisFromFirebase(data['createdAt']),
      edited: data['edited'] == true,
      updatedAtMillis: timestampMillisFromFirebase(data['updatedAt']),
    );
  }
}

Future<String> createOrOpenDirectChat(FriendUserData user) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before opening chat.',
    );
  }

  final chatId = directChatIdFor(firebaseUser.uid, user.uid);
  final memberIds = [firebaseUser.uid, user.uid];
  final memberUsernames = [currentUser.username, user.username];

  final chatRef = chatsCollection().doc(chatId);
  final existing = await chatRef.get();

  if (!existing.exists) {
    await chatRef.set({
      'isGroup': false,
      'name': '',
      'memberIds': memberIds,
      'memberUsernames': memberUsernames,
      'memberPhotoUrls': [currentUser.photoUrl ?? '', user.photoUrl ?? ''],
      'photoUrl': '',
      'lastMessage': '',
      'lastSenderUid': '',
      'lastSenderUsername': '',
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  } else {
    await chatRef.set({
      'memberIds': memberIds,
      'memberUsernames': memberUsernames,
      'memberPhotoUrls': [currentUser.photoUrl ?? '', user.photoUrl ?? ''],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  return chatId;
}

Future<String> createGroupChat({
  required String name,
  required List<FriendUserData> users,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before creating chat.',
    );
  }

  final uniqueUsers = <String, FriendUserData>{
    for (final user in users) user.uid: user,
  }.values.toList();
  final memberIds = [firebaseUser.uid, ...uniqueUsers.map((user) => user.uid)];
  final memberUsernames = [
    currentUser.username,
    ...uniqueUsers.map((user) => user.username),
  ];
  final fallbackName = uniqueUsers
      .map((user) => user.username)
      .where((username) => username.trim().isNotEmpty)
      .take(3)
      .join(', ');
  final doc = chatsCollection().doc();

  await doc.set({
    'isGroup': true,
    'name': name.trim().isEmpty ? fallbackName : name.trim(),
    'memberIds': memberIds,
    'memberUsernames': memberUsernames,
    'memberPhotoUrls': [
      currentUser.photoUrl ?? '',
      ...uniqueUsers.map((user) => user.photoUrl ?? ''),
    ],
    'ownerUid': firebaseUser.uid,
    'moderatorIds': [],
    'photoUrl': '',
    'description': '',
    'lastMessage': '',
    'updatedAt': FieldValue.serverTimestamp(),
    'createdAt': FieldValue.serverTimestamp(),
  });

  return doc.id;
}

Future<void> sendChatMessage({
  required String chatId,
  required String text,
  ChatThreadData? chat,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before sending messages.',
    );
  }

  final cleanText = text.trim();

  if (cleanText.isEmpty) {
    return;
  }

  final messageRef = await chatMessagesCollection(chatId).add({
    'senderUid': firebaseUser.uid,
    'senderUsername': currentUser.username,
    'text': cleanText,
    'createdAt': FieldValue.serverTimestamp(),
  });

  await chatsCollection().doc(chatId).set({
    'lastMessage': cleanText,
    'lastSenderUid': firebaseUser.uid,
    'lastSenderUsername': currentUser.username,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  if (chat != null) {
    await createChatMessageNotification(chat: chat, messageText: cleanText);
  }

  await sendPushNotificationEvent({
    'type': 'chat_message',
    'chatId': chatId,
    'messageId': messageRef.id,
  });
}

Future<Position?> getChatSharePosition(BuildContext context) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();

  if (!serviceEnabled) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Turn on phone location first.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return null;
  }

  var permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Location permission is needed to share your location.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return null;
  }

  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
}

String liveLocationDurationLabel(Duration duration) {
  final hours = duration.inHours;
  if (hours == 1) {
    return trText('1 hour');
  }

  return trText('$hours hours');
}

Future<bool> showLiveLocationSharingDisclaimer(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final dismissed = prefs.getBool(liveLocationDisclaimerDismissedKey) == true;
  if (dismissed) {
    return true;
  }

  if (!context.mounted) {
    return false;
  }

  var doNotShowAgain = false;
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: panelGlass,
            title: Text(
              trText('Share live location?'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trText(
                    'You are about to share your live location. People who have access to this share will be able to see you on the map until sharing expires or you stop it.',
                  ),
                  style: const TextStyle(color: Colors.white70, height: 1.35),
                ),
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () =>
                      setDialogState(() => doNotShowAgain = !doNotShowAgain),
                  child: Row(
                    children: [
                      Checkbox(
                        value: doNotShowAgain,
                        activeColor: blue,
                        onChanged: (value) => setDialogState(
                          () => doNotShowAgain = value == true,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          trText("Don't show again"),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(trText('Cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: ElevatedButton.styleFrom(backgroundColor: blue),
                child: const Text('OK', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );
    },
  );

  if (accepted == true && doNotShowAgain) {
    await prefs.setBool(liveLocationDisclaimerDismissedKey, true);
  }

  return accepted == true;
}

Future<Duration?> showLiveLocationDurationDialog(BuildContext context) async {
  if (!context.mounted) {
    return null;
  }

  return showDialog<Duration>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: panelGlass,
        title: Text(
          trText('Choose sharing duration'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: liveLocationDurationChoices.map((duration) {
            final label = liveLocationDurationLabel(duration);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, duration),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: panelGlass,
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white12),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(trText('Cancel')),
          ),
        ],
      );
    },
  );
}

Future<void> shareChatLiveLocation(
  BuildContext context,
  ChatThreadData chat,
) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Log in before sharing your location.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return;
  }

  final otherDirectUserId = chat.memberIds.firstWhere(
    (uid) => uid.trim().isNotEmpty && uid != firebaseUser.uid,
    orElse: () => '',
  );
  final visibleToUserIds = uniqueNonEmptyStrings(
    chat.isGroup
        ? [firebaseUser.uid, ...chat.memberIds]
        : [firebaseUser.uid, otherDirectUserId],
  );

  if (visibleToUserIds.length <= 1) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'This chat has no one to share location with.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return;
  }

  final acceptedDisclaimer = await showLiveLocationSharingDisclaimer(context);
  if (!acceptedDisclaimer || !context.mounted) {
    return;
  }

  final shareDuration = await showLiveLocationDurationDialog(context);
  if (shareDuration == null || !context.mounted) {
    return;
  }

  final position = await getChatSharePosition(context);

  if (position == null) {
    return;
  }

  final now = DateTime.now();
  final promptAt = now.add(shareDuration);
  final expiresAt = promptAt.add(liveLocationRenewGracePeriod);
  final chatTitle = chat.titleForCurrentUser(firebaseUser.uid);

  await liveLocationsCollection().doc(firebaseUser.uid).set({
    'uid': firebaseUser.uid,
    'username': currentUser.username,
    'name': currentUser.name,
    'photoUrl': currentUser.photoUrl,
    'role': roleName(currentUser.role),
    'verified': currentUser.verified,
    'heading': normalizedHeadingDegrees(position.heading),
    'lat': position.latitude,
    'lng': position.longitude,
    'coordinates': GeoPoint(position.latitude, position.longitude),
    'visibleToUserIds': visibleToUserIds,
    'visibleToChatId': chat.id,
    'visibleToChatName': chatTitle,
    'shareScope': chat.isGroup ? 'group' : 'direct',
    'shareDurationMinutes': shareDuration.inMinutes,
    'promptAt': Timestamp.fromDate(promptAt),
    'expiresAt': Timestamp.fromDate(expiresAt),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  await usersCollection().doc(firebaseUser.uid).set({
    'isSharingLiveLocation': true,
    'liveLocationExpiresAt': Timestamp.fromDate(expiresAt),
    'liveLocationShareDurationMinutes': shareDuration.inMinutes,
    'liveLocationVisibleToUserIds': visibleToUserIds,
    'lastSeenAt': FieldValue.serverTimestamp(),
    'isOnline': true,
  }, SetOptions(merge: true));

  await sendChatMessage(
    chatId: chat.id,
    text: chat.isGroup
        ? 'Shared live location with this group.'
        : 'Shared live location with you.',
  );

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: panelGlass,
        content: Text(
          chat.isGroup
              ? 'Location shared with this group for ${liveLocationDurationLabel(shareDuration)}.'
              : 'Location shared with this chat for ${liveLocationDurationLabel(shareDuration)}.',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

Future<bool> currentUserCanModerateChat(String chatId) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null) return false;
  if (userRoleIsStaff(currentUser.role)) return true;

  final snapshot = await chatsCollection().doc(chatId).get();
  final data = snapshot.data();
  if (data == null || data['isGroup'] != true) return false;

  final memberIds = stringListFromFirebase(data['memberIds'], const []);
  if (!memberIds.contains(firebaseUser.uid)) return false;

  final ownerUid = stringFromFirebase(
    data['ownerUid'],
    memberIds.isEmpty ? '' : memberIds.first,
  );
  final moderatorIds = stringListFromFirebase(data['moderatorIds'], const []);

  return ownerUid == firebaseUser.uid ||
      moderatorIds.contains(firebaseUser.uid);
}

Future<void> editChatMessage({
  required String chatId,
  required ChatMessageData message,
  required String text,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final canModerate = await currentUserCanModerateChat(chatId);

  if (firebaseUser == null ||
      (firebaseUser.uid != message.senderUid && !canModerate)) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'You can edit only your own messages.',
    );
  }

  final cleanText = text.trim();

  if (cleanText.isEmpty) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'empty-message',
      message: 'Message cannot be empty.',
    );
  }

  await chatMessagesCollection(chatId).doc(message.id).set({
    'text': cleanText,
    'edited': true,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  await chatsCollection().doc(chatId).set({
    'lastMessage': cleanText,
    'lastSenderUid': firebaseUser.uid,
    'lastSenderUsername': currentUser.username,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> deleteChatMessage({
  required String chatId,
  required ChatMessageData message,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final canModerate = await currentUserCanModerateChat(chatId);

  if (firebaseUser == null ||
      (firebaseUser.uid != message.senderUid && !canModerate)) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'You can delete only your own messages.',
    );
  }

  await chatMessagesCollection(chatId).doc(message.id).delete();

  final latestSnapshot = await chatMessagesCollection(
    chatId,
  ).orderBy('createdAt', descending: true).limit(1).get();
  final latestText = latestSnapshot.docs.isEmpty
      ? ''
      : stringFromFirebase(latestSnapshot.docs.first.data()['text'], '');
  final latestSenderUid = latestSnapshot.docs.isEmpty
      ? ''
      : stringFromFirebase(latestSnapshot.docs.first.data()['senderUid'], '');
  final latestSenderUsername = latestSnapshot.docs.isEmpty
      ? ''
      : stringFromFirebase(
          latestSnapshot.docs.first.data()['senderUsername'],
          '',
        );

  await chatsCollection().doc(chatId).set({
    'lastMessage': latestText,
    'lastSenderUid': latestSenderUid,
    'lastSenderUsername': latestSenderUsername,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<LiveLocationData?> loadCurrentLiveLocationForUser(String uid) async {
  final snapshot = await liveLocationsCollection().doc(uid).get();

  if (!snapshot.exists) {
    return null;
  }

  final location = LiveLocationData.fromFirestore(snapshot);
  return location.isExpired ? null : location;
}

Future<bool> shouldCreateFriendLocationNotification(
  String notificationId,
) async {
  final snapshot = await friendLocationNotificationsCollection()
      .doc(notificationId)
      .get();

  if (!snapshot.exists) {
    return true;
  }

  final data = snapshot.data() ?? {};
  final lastNotifiedAtMillis = timestampMillisFromFirebase(
    data['lastNotifiedAtMillis'],
  );

  if (lastNotifiedAtMillis <= 0) {
    return true;
  }

  final elapsedMillis =
      DateTime.now().millisecondsSinceEpoch - lastNotifiedAtMillis;
  return elapsedMillis >= friendLocationNotificationCooldown.inMilliseconds;
}

Future<void> createFriendLocationNotification({
  required String notificationId,
  required String userId,
  required LiveLocationData friendLocation,
  required String type,
  required double distanceMeters,
  CarSpot? spot,
}) async {
  if (!await shouldCreateFriendLocationNotification(notificationId)) {
    return;
  }

  final nowMillis = DateTime.now().millisecondsSinceEpoch;

  await friendLocationNotificationsCollection().doc(notificationId).set({
    'userId': userId,
    'friendUid': friendLocation.uid,
    'friendUsername': friendLocation.username,
    'friendName': friendLocation.name,
    'friendLat': friendLocation.coordinates.latitude,
    'friendLng': friendLocation.coordinates.longitude,
    'friendCoordinates': GeoPoint(
      friendLocation.coordinates.latitude,
      friendLocation.coordinates.longitude,
    ),
    'type': type,
    'distanceMeters': distanceMeters.round(),
    'spotId': spot?.id ?? '',
    'spotName': spot?.name ?? '',
    'spotCategory': spot?.categories.isEmpty == true
        ? ''
        : spot?.categories.first ?? '',
    'read': false,
    'lastNotifiedAtMillis': nowMillis,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> checkFriendLocationNotifications() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return;
  }

  final friendUids = await loadCurrentFriendUids();

  if (friendUids.isEmpty) {
    return;
  }

  final activeLocations = await liveLocationsCollection()
      .where('visibleToUserIds', arrayContains: firebaseUser.uid)
      .get();

  final friendUidSet = friendUids.toSet();
  final friendLocations = activeLocations.docs
      .map((doc) => LiveLocationData.fromFirestore(doc))
      .where(
        (location) =>
            friendUidSet.contains(location.uid) &&
            location.uid != firebaseUser.uid &&
            location.visibleToUserIds.contains(firebaseUser.uid) &&
            !location.isExpired,
      )
      .toList();

  if (friendLocations.isEmpty) {
    return;
  }

  final currentLocation = await loadCurrentLiveLocationForUser(
    firebaseUser.uid,
  );
  final visibleApprovedSpots = approvedPublicSpots();

  for (final friendLocation in friendLocations) {
    if (currentLocation != null) {
      final distanceMeters = distanceBetweenLatLngMeters(
        currentLocation.coordinates,
        friendLocation.coordinates,
      );

      if (distanceMeters <= friendNearbyRadiusMeters) {
        await createFriendLocationNotification(
          notificationId: friendNearbyNotificationId(
            firebaseUser.uid,
            friendLocation.uid,
          ),
          userId: firebaseUser.uid,
          friendLocation: friendLocation,
          type: 'friend_nearby',
          distanceMeters: distanceMeters,
        );
      }
    }

    for (final spot in visibleApprovedSpots) {
      if (spot.id.trim().isEmpty) {
        continue;
      }

      final distanceToSpotMeters = distanceBetweenLatLngMeters(
        friendLocation.coordinates,
        spot.coordinates,
      );

      if (distanceToSpotMeters <= friendAtSpotRadiusMeters) {
        await createFriendLocationNotification(
          notificationId: friendSpotNotificationId(
            firebaseUser.uid,
            friendLocation.uid,
            spot.id,
          ),
          userId: firebaseUser.uid,
          friendLocation: friendLocation,
          type: 'friend_at_spot',
          distanceMeters: distanceToSpotMeters,
          spot: spot,
        );
      }
    }
  }
}

bool get currentUserCanUseVerifiedOnlySpots {
  return userRoleIsStaff(currentUser.role) || currentUser.verified;
}

bool currentUserCanManageSpotBusiness(CarSpot spot) {
  return spot.supportsContacts &&
      (userRoleIsStaff(currentUser.role) ||
          (spot.ownerUid.isNotEmpty && spot.ownerUid == currentUser.uid));
}

Future<String> detectCityCountryForCoordinates(LatLng coordinates) async {
  try {
    final placemarks = await placemarkFromCoordinates(
      coordinates.latitude,
      coordinates.longitude,
    );

    if (placemarks.isEmpty) {
      return 'Unknown location';
    }

    final place = placemarks.first;
    final city =
        [place.locality, place.subAdministrativeArea, place.administrativeArea]
            .whereType<String>()
            .map((value) => value.trim())
            .firstWhere(
              (value) => value.isNotEmpty,
              orElse: () => 'Unknown city',
            );
    final country = (place.country ?? '').trim();

    return country.isEmpty ? city : '$city, $country';
  } catch (_) {
    return 'Unknown location';
  }
}

double distanceBetweenLatLngMeters(LatLng first, LatLng second) {
  if (!isValidLatLng(first) || !isValidLatLng(second)) {
    return double.infinity;
  }

  return const Distance().as(LengthUnit.Meter, first, second);
}

bool spotBlocksPermanentSpotCreation(CarSpot spot) {
  if (spot.status == SpotStatus.rejected) {
    return false;
  }

  if (spot.isTemporary && spot.isExpired) {
    return false;
  }

  return true;
}

Future<CarSpot?> findNearbySpotBlockingPermanentSpotCreation(
  LatLng location, {
  String? ignoreSpotId,
}) async {
  List<CarSpot> existingSpots;

  try {
    final snapshot = await spotsCollection().get(
      const GetOptions(source: Source.server),
    );
    existingSpots = snapshot.docs
        .map((doc) => CarSpot.fromFirestore(doc))
        .toList();
  } catch (_) {
    existingSpots = reviewSpots.value;
  }

  CarSpot? nearestSpot;
  var nearestDistance = double.infinity;

  for (final spot in existingSpots) {
    if (ignoreSpotId != null &&
        ignoreSpotId.isNotEmpty &&
        spot.id == ignoreSpotId) {
      continue;
    }

    if (!spotBlocksPermanentSpotCreation(spot)) {
      continue;
    }

    final distance = distanceBetweenLatLngMeters(location, spot.coordinates);
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestSpot = spot;
    }
  }

  if (nearestSpot == null ||
      nearestDistance >= minimumPermanentSpotDistanceMeters) {
    return null;
  }

  return nearestSpot;
}

double normalizedHeadingDegrees(double value, {double fallback = 0}) {
  final safeFallback = fallback.isFinite && fallback >= 0
      ? fallback % 360
      : 0.0;

  if (!value.isFinite || value < 0) {
    return safeFallback;
  }

  final normalized = value % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}

double headingRadiansForMap(double headingDegrees, double mapRotationDegrees) {
  return (headingDegrees - mapRotationDegrees) * math.pi / 180;
}

double headingRadiansForMapPinnedMarker(double headingDegrees) {
  return normalizedHeadingDegrees(headingDegrees) * math.pi / 180;
}

double bearingBetweenLatLngDegrees(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final deltaLng = (to.longitude - from.longitude) * math.pi / 180;

  final y = math.sin(deltaLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
  final bearing = math.atan2(y, x) * 180 / math.pi;

  return normalizedHeadingDegrees(bearing + 360);
}

LatLng projectLatLngMeters(
  LatLng origin,
  double bearingDegrees,
  double distanceMeters,
) {
  if (!isValidLatLng(origin) || distanceMeters <= 0 || !distanceMeters.isFinite) {
    return isValidLatLng(origin) ? origin : fallbackRigaLatLng;
  }

  const earthRadiusMeters = 6371000.0;
  final bearing = normalizedHeadingDegrees(bearingDegrees) * math.pi / 180;
  final angularDistance = distanceMeters / earthRadiusMeters;
  final lat1 = origin.latitude * math.pi / 180;
  final lng1 = origin.longitude * math.pi / 180;

  final lat2 = math.asin(
    math.sin(lat1) * math.cos(angularDistance) +
        math.cos(lat1) * math.sin(angularDistance) * math.cos(bearing),
  );
  final lng2 =
      lng1 +
      math.atan2(
        math.sin(bearing) * math.sin(angularDistance) * math.cos(lat1),
        math.cos(angularDistance) - math.sin(lat1) * math.sin(lat2),
      );

  return safeLatLng(lat2 * 180 / math.pi, lng2 * 180 / math.pi, fallback: origin);
}

LatLng lerpLatLng(LatLng from, LatLng to, double amount) {
  if (!isValidLatLng(from)) {
    return isValidLatLng(to) ? to : fallbackRigaLatLng;
  }

  if (!isValidLatLng(to)) {
    return from;
  }

  final t = amount.clamp(0.0, 1.0).toDouble();
  return safeLatLng(
    from.latitude + (to.latitude - from.latitude) * t,
    from.longitude + (to.longitude - from.longitude) * t,
    fallback: from,
  );
}

Future<void> createMeetSpotNotificationsForNearbyUsers(CarSpot spot) async {
  if (spot.id.trim().isEmpty || !spot.categories.contains('Meet')) {
    return;
  }

  final activeLocations = await liveLocationsCollection()
      .where('expiresAt', isGreaterThan: Timestamp.now())
      .get();
  final batch = FirebaseFirestore.instance.batch();
  var writes = 0;

  for (final doc in activeLocations.docs) {
    final liveLocation = LiveLocationData.fromFirestore(doc);

    if (liveLocation.uid == spot.addedByUid || liveLocation.isExpired) {
      continue;
    }

    final distanceMeters = distanceBetweenLatLngMeters(
      spot.coordinates,
      liveLocation.coordinates,
    );

    if (distanceMeters > 50000) {
      continue;
    }

    final notificationId = '${spot.id}_${liveLocation.uid}';
    final notificationRef = meetNotificationsCollection().doc(notificationId);
    batch.set(notificationRef, {
      'userId': liveLocation.uid,
      'spotId': spot.id,
      'spotName': spot.name,
      'cityCountry': spot.cityCountry,
      'lat': spot.coordinates.latitude,
      'lng': spot.coordinates.longitude,
      'coordinates': GeoPoint(
        spot.coordinates.latitude,
        spot.coordinates.longitude,
      ),
      'distanceMeters': distanceMeters.round(),
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    writes++;
  }

  if (writes > 0) {
    await batch.commit();
  }
}

Future<List<String>> adminUserIdsExcept({String? excludedUid}) async {
  final snapshot = await usersCollection()
      .where('role', isEqualTo: 'admin')
      .get();

  return snapshot.docs
      .map((doc) => stringFromFirebase(doc.data()['uid'], doc.id))
      .where((uid) => uid.isNotEmpty && uid != excludedUid)
      .toList();
}

Future<void> createAdminSpotReviewNotification(CarSpot spot) async {
  if (spot.id.trim().isEmpty || spot.status != SpotStatus.pending) {
    return;
  }

  final adminUids = await adminUserIdsExcept(excludedUid: spot.addedByUid);

  if (adminUids.isEmpty) {
    return;
  }

  final batch = FirebaseFirestore.instance.batch();

  for (final adminUid in adminUids) {
    final notificationRef = adminNotificationsCollection().doc(
      '${spot.id}_review_$adminUid',
    );
    batch.set(notificationRef, {
      'userId': adminUid,
      'type': 'spot_pending_review',
      'spotId': spot.id,
      'spotName': spot.name,
      'cityCountry': spot.cityCountry,
      'addedBy': spot.addedBy,
      'addedByUid': spot.addedByUid,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  await batch.commit();
}

Future<void> createAdminSpotDecisionNotification(
  CarSpot spot,
  SpotStatus status, {
  String rejectionReason = '',
}) async {
  if (spot.id.trim().isEmpty ||
      (status != SpotStatus.approved && status != SpotStatus.rejected)) {
    return;
  }

  final adminUids = await adminUserIdsExcept(excludedUid: currentUser.uid);

  if (adminUids.isEmpty) {
    return;
  }

  final batch = FirebaseFirestore.instance.batch();
  final statusName = spotStatusName(status);
  final cleanReason = rejectionReason.trim();

  for (final adminUid in adminUids) {
    final notificationRef = adminNotificationsCollection().doc(
      '${spot.id}_${statusName}_$adminUid',
    );
    batch.set(notificationRef, {
      'userId': adminUid,
      'type': status == SpotStatus.approved
          ? 'spot_approved_by_admin'
          : 'spot_rejected_by_admin',
      'spotId': spot.id,
      'spotName': spot.name,
      'cityCountry': spot.cityCountry,
      'status': statusName,
      'reviewedBy': currentUser.username,
      'reviewedByUid': currentUser.uid,
      if (cleanReason.isNotEmpty) 'rejectionReason': cleanReason,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  await batch.commit();
}

class PoliceReportData {
  final String id;
  final String uid;
  final String username;
  final LatLng coordinates;
  final int createdAtMillis;
  final int expiresAtMillis;
  final int updatedAtMillis;
  final String status;
  final List<String> stillThereBy;
  final List<String> notThereBy;

  const PoliceReportData({
    required this.id,
    required this.uid,
    required this.username,
    required this.coordinates,
    required this.createdAtMillis,
    required this.expiresAtMillis,
    required this.updatedAtMillis,
    this.status = 'active',
    this.stillThereBy = const [],
    this.notThereBy = const [],
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch >= expiresAtMillis;
  bool get isActive => status != 'removed' && !isExpired;
  int get stillThereCount => stillThereBy.length;
  int get notThereCount => notThereBy.length;

  bool userPressedStillThere(String? uid) {
    return uid != null && stillThereBy.contains(uid);
  }

  bool userPressedNotThere(String? uid) {
    return uid != null && notThereBy.contains(uid);
  }

  factory PoliceReportData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final coordinates = safeLatLngFromFirestoreCoordinates(
      data['coordinates'],
      data['lat'],
      data['lng'],
    );

    return PoliceReportData(
      id: doc.id,
      uid: stringFromFirebase(data['uid'], ''),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      coordinates: coordinates,
      createdAtMillis: timestampMillisFromFirebase(data['createdAt']),
      expiresAtMillis: timestampMillisFromFirebase(data['expiresAt']),
      updatedAtMillis: timestampMillisFromFirebase(data['updatedAt']),
      status: stringFromFirebase(data['status'], 'active'),
      stillThereBy: stringListFromFirebase(data['stillThereBy'], const []),
      notThereBy: stringListFromFirebase(data['notThereBy'], const []),
    );
  }
}

class SosRequestDraft {
  final String reason;
  final String description;

  const SosRequestDraft({required this.reason, required this.description});
}

const sosReasonLabels = <String, String>{
  'battery': 'SOS reason battery',
  'tire': 'SOS reason tire',
  'fuel': 'SOS reason fuel',
  'towing': 'SOS reason towing',
  'breakdown': 'SOS reason breakdown',
  'other': 'SOS reason other',
};

const sosBlockedTextParts = <String>[
  'хуй',
  'пизд',
  'еб',
  'бля',
  'fuck',
  'shit',
  'spam',
];

bool sosDescriptionLooksLikeSpam(String value) {
  final clean = value.trim().toLowerCase();
  if (clean.length < 12) {
    return true;
  }

  final lettersAndDigits = clean.replaceAll(
    RegExp(r'[^a-zа-яё0-9]', unicode: true),
    '',
  );
  if (lettersAndDigits.length < 8) {
    return true;
  }

  final repeatedChars = RegExp(r'(.)\1{7,}', unicode: true);
  if (repeatedChars.hasMatch(clean)) {
    return true;
  }

  for (final part in sosBlockedTextParts) {
    if (clean.contains(part)) {
      return true;
    }
  }

  return false;
}

String sosReasonLabel(String reason) {
  return sosReasonLabels[reason.trim()] ?? sosReasonLabels['other']!;
}

class SosReportData {
  final String id;
  final String uid;
  final String username;
  final String description;
  final String reason;
  final LatLng coordinates;
  final int createdAtMillis;
  final int expiresAtMillis;
  final int updatedAtMillis;
  final int confirmationRequestedAtMillis;
  final String status;

  const SosReportData({
    required this.id,
    required this.uid,
    required this.username,
    required this.description,
    this.reason = 'other',
    required this.coordinates,
    required this.createdAtMillis,
    required this.expiresAtMillis,
    required this.updatedAtMillis,
    this.confirmationRequestedAtMillis = 0,
    this.status = 'active',
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch >= expiresAtMillis;
  bool get isActive => status != 'removed' && !isExpired;

  factory SosReportData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final coordinates = safeLatLngFromFirestoreCoordinates(
      data['coordinates'],
      data['lat'],
      data['lng'],
    );

    return SosReportData(
      id: doc.id,
      uid: stringFromFirebase(data['uid'], ''),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      description: stringFromFirebase(data['description'], ''),
      reason: stringFromFirebase(data['reason'], 'other'),
      coordinates: coordinates,
      createdAtMillis: timestampMillisFromFirebase(data['createdAt']),
      expiresAtMillis: timestampMillisFromFirebase(data['expiresAt']),
      updatedAtMillis: timestampMillisFromFirebase(data['updatedAt']),
      confirmationRequestedAtMillis: timestampMillisFromFirebase(
        data['confirmationRequestedAt'],
      ),
      status: stringFromFirebase(data['status'], 'active'),
    );
  }
}

Future<void> saveCurrentUserFields(Map<String, Object?> data) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return;
  }

  await usersCollection().doc(firebaseUser.uid).set({
    ...data,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

const int onlinePresenceFreshMillis = 2 * 60 * 1000;

bool isOnlinePresenceFresh(int lastSeenAtMillis) {
  if (lastSeenAtMillis <= 0) {
    return false;
  }

  return DateTime.now().millisecondsSinceEpoch - lastSeenAtMillis <=
      onlinePresenceFreshMillis;
}

bool liveLocationShareIsFresh(int? expiresAtMillis) {
  return expiresAtMillis != null &&
      expiresAtMillis > DateTime.now().millisecondsSinceEpoch;
}

bool userAppearsOnlineFromPresence({
  required bool isOnline,
  required int lastSeenAtMillis,
  required bool isSharingLiveLocation,
  required int? liveLocationExpiresAtMillis,
}) {
  return (isOnline && isOnlinePresenceFresh(lastSeenAtMillis)) ||
      (isSharingLiveLocation &&
          liveLocationShareIsFresh(liveLocationExpiresAtMillis));
}

Future<void> updateCurrentUserOnlinePresence({required bool isOnline}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return;
  }

  try {
    await usersCollection().doc(firebaseUser.uid).set({
      'isOnline': isOnline,
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (_) {
    // Presence should never block the app if Firebase temporarily fails.
  }
}

CollectionReference<Map<String, dynamic>> spotsCollection() {
  return FirebaseFirestore.instance.collection('spots');
}

Query<Map<String, dynamic>> approvedSpotsForCurrentUserQuery() {
  var query = spotsCollection().where(
    'status',
    isEqualTo: spotStatusName(SpotStatus.approved),
  );

  if (!currentUserCanUseVerifiedOnlySpots) {
    query = query.where('verifiedOnly', isEqualTo: false);
  }

  return query;
}

Future<String> uploadSpotPhoto({
  required String spotId,
  required String localPhotoPath,
  required String userId,
  required int photoIndex,
}) async {
  if (photoIndex < 0 || photoIndex >= maxSpotGalleryPhotos) {
    throw Exception('Spot photo index is outside the allowed gallery range.');
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final r2Path = photoIndex == 0
      ? 'spots/$spotId/main.jpg'
      : 'spots/$spotId/gallery/photo_${photoIndex + 1}_$timestamp.jpg';

  return uploadImageToR2(
    r2Path: r2Path,
    localPhotoPath: localPhotoPath,
    maxLongSide: r2SpotPhotoMaxLongSide,
    quality: r2JpegQuality,
  );
}

Future<String> uploadUserAvatarPhoto({
  required String userId,
  required String localPhotoPath,
}) async {
  final r2Path = 'users/$userId/avatar.jpg';

  return uploadImageToR2(
    r2Path: r2Path,
    localPhotoPath: localPhotoPath,
    maxLongSide: r2AvatarPhotoMaxLongSide,
    quality: r2JpegQuality,
  );
}

Future<String> uploadGarageCarPhoto({
  required String userId,
  required int carIndex,
  required int photoIndex,
  required String localPhotoPath,
}) async {
  if (photoIndex < 0 || photoIndex >= maxGaragePhotos) {
    throw Exception('Garage photo index is outside the allowed range.');
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final r2Path = photoIndex == 0
      ? 'garage/$userId/car_${carIndex}_cover.jpg'
      : 'garage/$userId/car_$carIndex/photo_${photoIndex + 1}_$timestamp.jpg';

  return uploadImageToR2(
    r2Path: r2Path,
    localPhotoPath: localPhotoPath,
    maxLongSide: r2GaragePhotoMaxLongSide,
    quality: r2JpegQuality,
  );
}

Map<String, Object?> spotToFirestoreData(
  CarSpot spot, {
  bool includeCreatedAt = false,
}) {
  final data = <String, Object?>{
    'name': spot.name,
    'cityCountry': spot.cityCountry,
    'lat': spot.coordinates.latitude,
    'lng': spot.coordinates.longitude,
    'coordinates': GeoPoint(
      spot.coordinates.latitude,
      spot.coordinates.longitude,
    ),
    'description': spot.description,
    'categories': spot.categories,
    'rating': spot.rating,
    'photoUrl': spot.photoUrl,
    'photoUrls': spot.photoUrls,
    'reelLink': spot.reelLink,
    'contactPhone': spot.contactPhone,
    'contactInstagram': spot.contactInstagram,
    'contactEmail': spot.contactEmail,
    'openingHours': openingHoursToFirebase(spot.openingHours),
    'ownerUid': spot.ownerUid,
    'ownerUsername': spot.ownerUsername,
    'bestTime': spot.bestTime,
    'parking': spot.parking,
    'roadQuality': spot.roadQuality,
    'lowCarFriendly': spot.lowCarFriendly,
    'policeRisk': spot.policeRisk,
    'traffic': spot.traffic,
    'lighting': spot.lighting,
    'crowd': spot.crowd,
    'addedBy': spot.addedBy,
    'addedByUid': spot.addedByUid,
    'status': spotStatusName(spot.status),
    'verifiedOnly': spot.verifiedOnly,
    'rejectionReason': spot.rejectionReason,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  if (spot.isTemporary) {
    data['isTemporary'] = true;
    data['startsAt'] = spot.startsAtMillis == null
        ? null
        : Timestamp.fromMillisecondsSinceEpoch(spot.startsAtMillis!);
    data['expiresAt'] = spot.expiresAtMillis == null
        ? null
        : Timestamp.fromMillisecondsSinceEpoch(spot.expiresAtMillis!);
    data['showOnMapAt'] = spot.showOnMapAtMillis == null
        ? null
        : Timestamp.fromMillisecondsSinceEpoch(spot.showOnMapAtMillis!);
  } else {
    data['isTemporary'] = false;
    data['startsAt'] = null;
    data['expiresAt'] = null;
    data['showOnMapAt'] = null;
  }

  if (includeCreatedAt) {
    data['createdAt'] = FieldValue.serverTimestamp();
  }

  return data;
}

const int firebaseApprovedSpotsListenLimit = 250;
const int firebaseMySpotsListenLimit = 100;
const int firebaseAdminReviewSpotsListenLimit = 250;
const int firebaseChatsListenLimit = 60;
const int firebaseChatMessagesListenLimit = 50;

final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
spotSyncSubscriptions = [];
final Map<String, Map<String, CarSpot>> _firebaseSpotCacheBySource = {};

String _spotCacheKey(CarSpot spot) {
  if (spot.id.trim().isNotEmpty) {
    return spot.id.trim();
  }

  return '${spot.name}_${spot.addedByUid}_${spot.createdAtMillis}';
}

void _publishFirebaseSpotCaches() {
  final merged = <String, CarSpot>{};

  for (final sourceSpots in _firebaseSpotCacheBySource.values) {
    for (final entry in sourceSpots.entries) {
      merged[entry.key] = entry.value;
    }
  }

  final firebaseSpots = merged.values.toList()
    ..sort(
      (first, second) =>
          second.createdAtMillis.compareTo(first.createdAtMillis),
    );

  final currentUid = FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;
  reviewSpots.value = firebaseSpots;
  submittedSpots.value = firebaseSpots
      .where((spot) => spot.addedByUid == currentUid)
      .toList();
  restoreSavedSpotsFromFirebaseCache();
}

void _listenToSpotQuery({
  required String source,
  required Query<Map<String, dynamic>> query,
}) {
  final subscription = query.snapshots().listen(
    (snapshot) {
      _firebaseSpotCacheBySource[source] = {
        for (final doc in snapshot.docs)
          _spotCacheKey(CarSpot.fromFirestore(doc)): CarSpot.fromFirestore(doc),
      };
      _publishFirebaseSpotCaches();
    },
    onError: (Object error, StackTrace stack) {
      debugPrint('Spot listener failed for $source: $error');
      debugPrint('$stack');
    },
  );

  spotSyncSubscriptions.add(subscription);
}

void startFirebaseSpotSync() {
  for (final subscription in spotSyncSubscriptions) {
    subscription.cancel();
  }
  spotSyncSubscriptions.clear();
  _firebaseSpotCacheBySource.clear();

  // Important cost optimization: never listen to the entire spots collection.
  // Normal users only need a small approved feed plus their own submissions.
  // Staff get a separate limited review queue.
  _listenToSpotQuery(
    source: 'approved',
    query: approvedSpotsForCurrentUserQuery().limit(
      firebaseApprovedSpotsListenLimit,
    ),
  );

  final currentUid = FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;
  if (currentUid.trim().isNotEmpty && currentUid != 'mock_user') {
    _listenToSpotQuery(
      source: 'mine',
      query: spotsCollection()
          .where('addedByUid', isEqualTo: currentUid)
          .limit(firebaseMySpotsListenLimit),
    );
  }

  if (userRoleIsStaff(currentUser.role)) {
    for (final status in const [
      SpotStatus.pending,
      SpotStatus.edited,
      SpotStatus.rejected,
    ]) {
      _listenToSpotQuery(
        source: 'admin_${spotStatusName(status)}',
        query: spotsCollection()
            .where('status', isEqualTo: spotStatusName(status))
            .limit(firebaseAdminReviewSpotsListenLimit),
      );
    }
  }
}

Future<void> refreshFirebaseSpotsFromServer() async {
  final currentUid = FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;
  final refreshCaches = <String, Map<String, CarSpot>>{};

  Future<void> loadQuery(
    String source,
    Query<Map<String, dynamic>> query,
  ) async {
    final snapshot = await query.get(const GetOptions(source: Source.server));
    refreshCaches[source] = {
      for (final doc in snapshot.docs)
        _spotCacheKey(CarSpot.fromFirestore(doc)): CarSpot.fromFirestore(doc),
    };
  }

  await loadQuery(
    'approved',
    approvedSpotsForCurrentUserQuery().limit(firebaseApprovedSpotsListenLimit),
  );

  if (currentUid.trim().isNotEmpty && currentUid != 'mock_user') {
    await loadQuery(
      'mine',
      spotsCollection()
          .where('addedByUid', isEqualTo: currentUid)
          .limit(firebaseMySpotsListenLimit),
    );
  }

  if (userRoleIsStaff(currentUser.role)) {
    for (final status in const [
      SpotStatus.pending,
      SpotStatus.edited,
      SpotStatus.rejected,
    ]) {
      await loadQuery(
        'admin_${spotStatusName(status)}',
        spotsCollection()
            .where('status', isEqualTo: spotStatusName(status))
            .limit(firebaseAdminReviewSpotsListenLimit),
      );
    }
  }

  _firebaseSpotCacheBySource
    ..clear()
    ..addAll(refreshCaches);
  _publishFirebaseSpotCaches();
}

Query<Map<String, dynamic>> currentUserChatsQuery(String uid) {
  return chatsCollection()
      .where('memberIds', arrayContains: uid)
      .limit(firebaseChatsListenLimit);
}

Query<Map<String, dynamic>> latestChatMessagesQuery(String chatId) {
  return chatMessagesCollection(chatId)
      .orderBy('createdAt', descending: true)
      .limit(firebaseChatMessagesListenLimit);
}

class SpotReviewData {
  final String id;
  final String spotId;
  final String userId;
  final String username;
  final int rating;
  final String comment;
  final DateTime createdAt;

  const SpotReviewData({
    required this.id,
    required this.spotId,
    required this.userId,
    required this.username,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory SpotReviewData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final timestamp = data['createdAt'];

    return SpotReviewData(
      id: doc.id,
      spotId: stringFromFirebase(data['spotId'], ''),
      userId: stringFromFirebase(data['userId'], ''),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      rating: doubleFromFirebase(data['rating'], 5).round().clamp(1, 5).toInt(),
      comment: stringFromFirebase(data['comment'], ''),
      createdAt: timestamp is Timestamp
          ? timestamp.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

CollectionReference<Map<String, dynamic>> spotReviewsCollection() {
  return FirebaseFirestore.instance.collection('spot_reviews');
}

CollectionReference<Map<String, dynamic>> spotLikesCollection() {
  return FirebaseFirestore.instance.collection('spot_likes');
}

const int maxCommentsPerUserPerSpot = 50;

String spotReviewKey(CarSpot spot) {
  if (spot.id.trim().isNotEmpty) {
    return spot.id.trim();
  }

  final safeName = spot.name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  return safeName.isEmpty ? 'demo_spot' : 'demo_$safeName';
}

Stream<List<SpotReviewData>> watchSpotReviews(CarSpot spot) {
  return spotReviewsCollection()
      .where('spotId', isEqualTo: spotReviewKey(spot))
      .snapshots()
      .map((snapshot) {
        final reviews = snapshot.docs
            .map((doc) => SpotReviewData.fromFirestore(doc))
            .where((review) => review.comment.isNotEmpty)
            .toList();

        reviews.sort(
          (first, second) => second.createdAt.compareTo(first.createdAt),
        );
        return reviews;
      });
}

Stream<int> watchSpotCommentCount(CarSpot spot) {
  return watchSpotReviews(spot).map((reviews) => reviews.length);
}

Stream<int> watchSpotLikeCount(CarSpot spot) {
  return spotLikesCollection()
      .where('spotId', isEqualTo: spotReviewKey(spot))
      .snapshots()
      .map((snapshot) => snapshot.docs.length);
}

Stream<bool> watchCurrentUserLikedSpot(CarSpot spot) {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return Stream.value(false);
  }

  return spotLikesCollection()
      .doc('${spotReviewKey(spot)}_${firebaseUser.uid}')
      .snapshots()
      .map((snapshot) => snapshot.exists);
}

Future<void> toggleSpotLike(
  BuildContext context,
  CarSpot spot,
  bool currentlyLiked,
) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'Log in before liking spots.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return;
  }

  final likeRef = spotLikesCollection().doc(
    '${spotReviewKey(spot)}_${firebaseUser.uid}',
  );

  if (currentlyLiked) {
    await likeRef.delete();
  } else {
    final notificationId = 'spot_like_${likeRef.id}';
    final alreadyNotified = await userNotificationsCollection()
        .doc(notificationId)
        .get()
        .then((snapshot) => snapshot.exists)
        .catchError((_) => false);

    await likeRef.set({
      'spotId': spotReviewKey(spot),
      'spotName': spot.name,
      'spotOwnerUid': spotNotificationOwnerUid(spot),
      'userId': firebaseUser.uid,
      'username': currentUser.username,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (!alreadyNotified) {
      await createSpotLikeNotification(spot, likeRef.id);
      await sendPushNotificationEvent({
        'type': 'spot_like',
        'likeId': likeRef.id,
      });
    }
  }
}

String commentLikeDocumentId(SpotReviewData review, String userId) {
  return 'comment_${review.id}_$userId';
}

Stream<int> watchCommentLikeCount(SpotReviewData review) {
  return spotLikesCollection()
      .where('commentId', isEqualTo: review.id)
      .snapshots()
      .map((snapshot) => snapshot.docs.length);
}

Stream<bool> watchCurrentUserLikedComment(SpotReviewData review) {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return Stream.value(false);
  }

  return spotLikesCollection()
      .doc(commentLikeDocumentId(review, firebaseUser.uid))
      .snapshots()
      .map((snapshot) => snapshot.exists);
}

Future<void> toggleCommentLike(
  BuildContext context,
  SpotReviewData review,
  bool currentlyLiked,
) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'Log in before liking comments.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return;
  }

  final likeRef = spotLikesCollection().doc(
    commentLikeDocumentId(review, firebaseUser.uid),
  );

  if (currentlyLiked) {
    await likeRef.delete();
  } else {
    await likeRef.set({
      'targetType': 'comment',
      'commentId': review.id,
      'commentSpotId': review.spotId,
      'userId': firebaseUser.uid,
      'username': currentUser.username,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

Future<void> saveSpotReview({
  required CarSpot spot,
  required String comment,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before leaving a review.',
    );
  }

  final spotId = spotReviewKey(spot);
  final cleanComment = comment.trim();

  final existingReviews = await spotReviewsCollection()
      .where('spotId', isEqualTo: spotId)
      .get();

  final userCommentCount = existingReviews.docs.where((doc) {
    final data = doc.data();
    return stringFromFirebase(data['userId'], '') == firebaseUser.uid &&
        stringFromFirebase(data['comment'], '').trim().isNotEmpty;
  }).length;

  if (userCommentCount >= maxCommentsPerUserPerSpot) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'comment-limit-reached',
      message: 'You reached the 50 comment limit for this spot.',
    );
  }

  final reviewRef = await spotReviewsCollection().add({
    'spotId': spotId,
    'spotName': spot.name,
    'type': 'comment',
    'userId': firebaseUser.uid,
    'username': currentUser.username,
    'comment': cleanComment,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  await createSpotCommentNotification(spot, reviewRef.id, cleanComment);

  await sendPushNotificationEvent({
    'type': 'spot_comment',
    'reviewId': reviewRef.id,
  });
}

Future<void> editSpotReview({
  required CarSpot spot,
  required SpotReviewData review,
  required String comment,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before editing a review.',
    );
  }

  if (firebaseUser.uid != review.userId) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'You can edit only your own comments.',
    );
  }

  final cleanComment = comment.trim();
  if (cleanComment.isEmpty) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'empty-comment',
      message: 'Comment cannot be empty.',
    );
  }

  await spotReviewsCollection().doc(review.id).update({
    'comment': cleanComment,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

Future<void> deleteSpotReview({
  required CarSpot spot,
  required SpotReviewData review,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before deleting a review.',
    );
  }

  if (firebaseUser.uid != review.userId) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'You can delete only your own comments.',
    );
  }

  await spotReviewsCollection().doc(review.id).delete();
}

String spotRatingDocumentId(CarSpot spot, String userId) {
  return '${spotReviewKey(spot)}_${userId}_rating';
}

Stream<int> watchCurrentUserSpotRating(CarSpot spot) {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return Stream.value(0);
  }

  return spotReviewsCollection()
      .doc(spotRatingDocumentId(spot, firebaseUser.uid))
      .snapshots()
      .map((snapshot) {
        final data = snapshot.data();

        if (!snapshot.exists || data == null) {
          return 0;
        }

        return doubleFromFirebase(
          data['rating'],
          0,
        ).round().clamp(0, 5).toInt();
      });
}

Future<double?> saveSpotRating({
  required CarSpot spot,
  required int rating,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before rating a spot.',
    );
  }

  final safeRating = rating.clamp(1, 5);
  final ratingRef = spotReviewsCollection().doc(
    spotRatingDocumentId(spot, firebaseUser.uid),
  );
  final ratingSnapshot = await ratingRef.get();

  final data = <String, Object?>{
    'spotId': spotReviewKey(spot),
    'spotName': spot.name,
    'type': 'rating',
    'userId': firebaseUser.uid,
    'username': currentUser.username,
    'rating': safeRating,
    'comment': '',
    'updatedAt': FieldValue.serverTimestamp(),
  };

  if (!ratingSnapshot.exists) {
    data['createdAt'] = FieldValue.serverTimestamp();
  }

  await ratingRef.set(data, SetOptions(merge: true));

  return updateSpotRatingFromReviews(spot);
}

Future<double?> updateSpotRatingFromReviews(CarSpot spot) async {
  if (spot.id.trim().isEmpty) {
    return null;
  }

  final snapshot = await spotReviewsCollection()
      .where('spotId', isEqualTo: spotReviewKey(spot))
      .get();

  final ratings = snapshot.docs
      .map((doc) => doc.data())
      .where((data) => stringFromFirebase(data['type'], '') == 'rating')
      .map((data) => doubleFromFirebase(data['rating'], 0))
      .where((rating) => rating >= 1 && rating <= 5)
      .toList();

  if (ratings.isEmpty) {
    return null;
  }

  final averageRating =
      ratings.fold<double>(0, (total, rating) => total + rating) /
      ratings.length;
  final roundedRating = double.parse(averageRating.toStringAsFixed(1));

  await spotsCollection().doc(spot.id).update({
    'rating': roundedRating,
    'ratingCount': ratings.length,
    'reviewUpdatedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  final updatedSpot = spot.copyWith(rating: roundedRating);

  reviewSpots.value = reviewSpots.value
      .map((item) => isSameSpot(item, spot) ? updatedSpot : item)
      .toList();
  submittedSpots.value = submittedSpots.value
      .map((item) => isSameSpot(item, spot) ? updatedSpot : item)
      .toList();
  savedSpots.value = savedSpots.value
      .map((item) => isSameSpot(item, spot) ? updatedSpot : item)
      .toList();

  return roundedRating;
}

const demoSpots = [
  CarSpot(
    name: 'Andrejsala Harbor',
    cityCountry: 'Riga, Latvia',
    coordinates: LatLng(56.9612, 24.0944),
    description:
        'Industrial harbor mood, wide roads, dark water reflections, and a strong night shoot atmosphere.',
    categories: ['Photo', 'Reels', 'Meet'],
    rating: 4.8,
    photoUrl:
        'https://images.unsplash.com/photo-1492144534655-ae79c964c9d7?q=80&w=1200&auto=format&fit=crop',
    reelLink: 'https://instagram.com/reel/demo-andrejsala',
    bestTime: 'Night',
    parking: 'Easy',
    roadQuality: 'Good',
    lowCarFriendly: true,
    policeRisk: 'Medium',
    traffic: 'Low',
    lighting: 'Street lights',
    crowd: 'Medium',
    addedBy: 'riga_driver',
    status: SpotStatus.approved,
  ),
  CarSpot(
    name: 'Spikeri Brick Yard',
    cityCountry: 'Riga, Latvia',
    coordinates: LatLng(56.9427, 24.1168),
    description:
        'Brick walls, city texture, and clean angles for rollers, portraits, and parked car shots.',
    categories: ['Photo', 'Reels'],
    rating: 4.6,
    photoUrl:
        'https://images.unsplash.com/photo-1542362567-b07e54358753?q=80&w=1200&auto=format&fit=crop',
    reelLink: 'https://tiktok.com/@ccs/video/demo-spikeri',
    bestTime: 'Golden hour',
    parking: 'Street',
    roadQuality: 'Mixed',
    lowCarFriendly: false,
    policeRisk: 'Low',
    traffic: 'Medium',
    lighting: 'Warm city lights',
    crowd: 'Low',
    addedBy: 'stance_lv',
    status: SpotStatus.approved,
  ),
  CarSpot(
    name: 'Bikernieki Forest Road',
    cityCountry: 'Riga, Latvia',
    coordinates: LatLng(56.9662, 24.2294),
    description:
        'Forest road energy near the track area. Best for clean rolling content and small meets.',
    categories: ['Drive', 'Meet', 'Reels'],
    rating: 4.7,
    photoUrl:
        'https://images.unsplash.com/photo-1503736334956-4c8f8e92946d?q=80&w=1200&auto=format&fit=crop',
    reelLink: 'https://instagram.com/reel/demo-bikernieki',
    bestTime: 'Evening',
    parking: 'Good',
    roadQuality: 'Good',
    lowCarFriendly: true,
    policeRisk: 'Low',
    traffic: 'Low',
    lighting: 'Natural',
    crowd: 'Low',
    addedBy: 'jdm_riga',
    status: SpotStatus.approved,
  ),
  CarSpot(
    name: 'Riga Rooftop Parking',
    cityCountry: 'Riga, Latvia',
    coordinates: LatLng(56.9497, 24.1052),
    description:
        'Skyline view and clean concrete lines. This spot is waiting for moderator approval.',
    categories: ['Photo', 'Low car'],
    rating: 4.4,
    photoUrl:
        'https://images.unsplash.com/photo-1511919884226-fd3cad34687c?q=80&w=1200&auto=format&fit=crop',
    reelLink: 'https://instagram.com/reel/demo-pending',
    bestTime: 'Sunset',
    parking: 'Private',
    roadQuality: 'Good',
    lowCarFriendly: true,
    policeRisk: 'High',
    traffic: 'Medium',
    lighting: 'Rooftop lights',
    crowd: 'Unknown',
    addedBy: 'new_spotter',
    status: SpotStatus.pending,
  ),
];

List<CarSpot> approvedPublicSpots() {
  // Public Explore/Map must show only real Firebase spots.
  // Demo spots stay in code as backup data, but they should not reappear
  // after an admin deletes an approved Firebase spot.
  return reviewSpots.value
      .where(
        (spot) =>
            spot.status == SpotStatus.approved &&
            spot.isVisibleNow &&
            (!spot.verifiedOnly || currentUserCanUseVerifiedOnlySpots),
      )
      .toList();
}

List<CarSpot> pendingReviewSpots() {
  return reviewSpots.value
      .where((spot) => spot.status == SpotStatus.pending)
      .toList();
}

bool isSameSpot(CarSpot first, CarSpot second) {
  if (first.id.isNotEmpty && second.id.isNotEmpty) {
    return first.id == second.id;
  }

  return first.name == second.name && first.addedBy == second.addedBy;
}

Future<void> updateSpotStatus(
  CarSpot spot,
  SpotStatus status, {
  String rejectionReason = '',
}) async {
  final statusChanged = spot.status != status;
  final cleanRejectionReason = status == SpotStatus.rejected
      ? rejectionReason.trim()
      : '';
  final shouldNotifyNearbyMeetUsers =
      status == SpotStatus.approved &&
      spot.status != SpotStatus.approved &&
      spot.categories.contains('Meet');
  final shouldNotifyOtherAdmins =
      statusChanged &&
      (status == SpotStatus.approved || status == SpotStatus.rejected);

  final updatedSpot = spot.copyWith(
    status: status,
    rating: status == SpotStatus.approved && spot.rating == 0
        ? 4.5
        : spot.rating,
    rejectionReason: cleanRejectionReason,
  );

  if (spot.id.isNotEmpty) {
    await spotsCollection().doc(spot.id).update({
      'status': spotStatusName(status),
      'rating': updatedSpot.rating,
      'reviewedBy': currentUser.username,
      'reviewedByUid': currentUser.uid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'rejectionReason': cleanRejectionReason,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Keep the local UI responsive while Firestore sends the fresh snapshot.
  reviewSpots.value = reviewSpots.value
      .map((item) => isSameSpot(item, spot) ? updatedSpot : item)
      .toList();
  submittedSpots.value = submittedSpots.value
      .map((item) => isSameSpot(item, spot) ? updatedSpot : item)
      .toList();
  savedSpots.value = savedSpots.value
      .map((item) => isSameSpot(item, spot) ? updatedSpot : item)
      .toList();

  if (shouldNotifyNearbyMeetUsers) {
    await createMeetSpotNotificationsForNearbyUsers(updatedSpot);
  }

  if (shouldNotifyOtherAdmins) {
    await createAdminSpotDecisionNotification(
      updatedSpot,
      status,
      rejectionReason: cleanRejectionReason,
    );
  }

  if (statusChanged &&
      (status == SpotStatus.approved || status == SpotStatus.rejected)) {
    await createSpotReviewUpdateNotification(
      updatedSpot,
      status,
      rejectionReason: cleanRejectionReason,
    );
  }

  if (statusChanged &&
      spot.id.isNotEmpty &&
      (status == SpotStatus.approved || status == SpotStatus.rejected)) {
    await sendPushNotificationEvent({
      'type': 'spot_decision',
      'spotId': spot.id,
      'status': spotStatusName(status),
      if (cleanRejectionReason.isNotEmpty)
        'rejectionReason': cleanRejectionReason,
    });
  }
}

Future<void> deleteSpotFromFirebase(CarSpot spot) async {
  if (spot.id.isNotEmpty) {
    await spotsCollection().doc(spot.id).delete();
  }

  reviewSpots.value = reviewSpots.value
      .where((item) => !isSameSpot(item, spot))
      .toList();
  submittedSpots.value = submittedSpots.value
      .where((item) => !isSameSpot(item, spot))
      .toList();
  savedSpots.value = savedSpots.value
      .where((item) => !isSameSpot(item, spot))
      .toList();
  unawaited(saveSavedSpotIds());
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController introController;
  late final Animation<double> ccsSlide;
  late final Animation<double> subtitleSlide;
  late final Animation<double> taglineSlide;
  late final Animation<double> buttonSlide;
  late final Animation<double> ccsFade;
  late final Animation<double> subtitleFade;
  late final Animation<double> taglineFade;
  late final Animation<double> buttonFade;

  @override
  void initState() {
    super.initState();

    introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );

    ccsSlide = _slideAnimation(0.00, 0.58);
    subtitleSlide = _slideAnimation(0.14, 0.68);
    taglineSlide = _slideAnimation(0.28, 0.78);
    buttonSlide = _slideAnimation(0.44, 1.00);
    ccsFade = _fadeAnimation(0.00, 0.42);
    subtitleFade = _fadeAnimation(0.14, 0.52);
    taglineFade = _fadeAnimation(0.28, 0.66);
    buttonFade = _fadeAnimation(0.44, 0.88);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        introController.forward();
      }
    });
  }

  Animation<double> _slideAnimation(double begin, double end) {
    return CurvedAnimation(
      parent: introController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  Animation<double> _fadeAnimation(double begin, double end) {
    return CurvedAnimation(
      parent: introController,
      curve: Interval(begin, end, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    introController.dispose();
    super.dispose();
  }

  void openLogin() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 650),
        reverseTransitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (context, animation, secondaryAnimation) {
          return const LoginScreen(showBackground: false);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/bg.png', fit: BoxFit.cover),
              Container(color: Colors.black.withValues(alpha: 0.42)),
              SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(curvedAnimation),
                child: FadeTransition(opacity: curvedAnimation, child: child),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg.png', fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.42)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Stack(
                children: [
                  Align(
                    alignment: const Alignment(0, -0.62),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SplashIntroItem(
                          animation: ccsSlide,
                          fadeAnimation: ccsFade,
                          travel: 118,
                          child: const _CcsWordmark(),
                        ),
                        const SizedBox(height: 16),
                        _SplashIntroItem(
                          animation: subtitleSlide,
                          fadeAnimation: subtitleFade,
                          travel: 104,
                          child: const Text(
                            'COMMUNITY CAR SPOTS',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              letterSpacing: 4.2,
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        _SplashIntroItem(
                          animation: taglineSlide,
                          fadeAnimation: taglineFade,
                          travel: 90,
                          child: const Text(
                            'FIND - DRIVE - SHOOT',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              letterSpacing: 4.4,
                              color: Colors.white54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.76),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SplashIntroItem(
                        animation: buttonSlide,
                        fadeAnimation: buttonFade,
                        travel: 78,
                        child: ElevatedButton(
                          onPressed: openLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: blue,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 42,
                              vertical: 16,
                            ),
                            elevation: 12,
                            shadowColor: blue.withValues(alpha: 0.35),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text(
                            'ENTER CCS',
                            style: TextStyle(
                              fontSize: 16,
                              letterSpacing: 2,
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CcsWordmark extends StatelessWidget {
  final double width;

  const _CcsWordmark({this.width = 213});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Image.asset(
        'assets/ccs_logo.png',
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class CcsAppBarLogo extends StatelessWidget {
  const CcsAppBarLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Image.asset(
        'assets/ccs_logo.png',
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class NotificationCenterItem {
  final String id;
  final String title;
  final String body;
  final String type;
  final int createdAtMillis;
  final bool read;
  final DocumentReference<Map<String, dynamic>>? reference;
  final bool projectNews;
  final String spotId;
  final String spotName;
  final String chatId;
  final String userId;
  final String addedByUid;
  final String status;
  final String rejectionReason;

  const NotificationCenterItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAtMillis,
    required this.read,
    this.reference,
    this.projectNews = false,
    this.spotId = '',
    this.spotName = '',
    this.chatId = '',
    this.userId = '',
    this.addedByUid = '',
    this.status = '',
    this.rejectionReason = '',
  });

  NotificationCenterItem copyWith({
    String? id,
    String? title,
    String? body,
    String? type,
    int? createdAtMillis,
    bool? read,
    DocumentReference<Map<String, dynamic>>? reference,
    bool clearReference = false,
    bool? projectNews,
    String? spotId,
    String? spotName,
    String? chatId,
    String? userId,
    String? addedByUid,
    String? status,
    String? rejectionReason,
  }) {
    return NotificationCenterItem(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
      read: read ?? this.read,
      reference: clearReference ? null : (reference ?? this.reference),
      projectNews: projectNews ?? this.projectNews,
      spotId: spotId ?? this.spotId,
      spotName: spotName ?? this.spotName,
      chatId: chatId ?? this.chatId,
      userId: userId ?? this.userId,
      addedByUid: addedByUid ?? this.addedByUid,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }

  bool get canOpen =>
      !projectNews &&
      (spotId.trim().isNotEmpty ||
          chatId.trim().isNotEmpty ||
          addedByUid.trim().isNotEmpty ||
          userId.trim().isNotEmpty ||
          type == 'spot_pending_review');
}

bool notificationCenterItemIsRejected(NotificationCenterItem item) {
  final status = item.status.trim().toLowerCase();
  final title = item.title.trim().toLowerCase();
  final body = item.body.trim().toLowerCase();
  final type = item.type.trim().toLowerCase();

  return status == 'rejected' ||
      status.contains('reject') ||
      type == 'spot_rejected_by_admin' ||
      type.contains('reject') ||
      title.contains('rejected') ||
      body.contains('rejected') ||
      body.contains('was rejected') ||
      item.rejectionReason.trim().isNotEmpty;
}

String bodyWithRejectionReason(String body, String reason) {
  final cleanReason = reason.trim();
  if (cleanReason.isEmpty || body.toLowerCase().contains('reason:')) {
    return body;
  }

  final cleanBody = body.trim();
  if (cleanBody.isEmpty) {
    return 'Your spot was rejected. Reason: $cleanReason';
  }

  return '$cleanBody Reason: $cleanReason';
}

IconData notificationCenterIcon(NotificationCenterItem item) {
  if (item.projectNews) {
    return Icons.campaign;
  }

  // Rejection must always win over any generic review/update type. Some
  // notification payloads arrive as spot_review_update, so deciding only from
  // the type can incorrectly show the green approval check.
  if (notificationCenterItemIsRejected(item)) {
    return Icons.cancel;
  }

  return switch (item.type) {
    'spot_like' => Icons.favorite,
    'spot_comment' => Icons.chat_bubble,
    'chat_message' => Icons.mark_chat_unread,
    'spot_review_update' =>
      notificationCenterItemIsRejected(item)
          ? Icons.cancel
          : Icons.check_circle,
    'spot_pending_review' => Icons.fact_check,
    'spot_approved_by_admin' => Icons.check_circle,
    'spot_rejected_by_admin' => Icons.cancel,
    'new_spot' => Icons.add_location_alt,
    'temporary_event' => Icons.event_available,
    'friend_nearby' || 'friend_at_spot' => Icons.location_on,
    _ => Icons.notifications,
  };
}

Color notificationCenterColor(NotificationCenterItem item) {
  if (item.projectNews) {
    return const Color(0xFFFFB300);
  }

  // Same rule as the icon: any rejected review notification is red.
  if (notificationCenterItemIsRejected(item)) {
    return Colors.redAccent;
  }

  return switch (item.type) {
    'spot_like' => Colors.redAccent,
    'spot_comment' || 'chat_message' => blue,
    'spot_review_update' =>
      notificationCenterItemIsRejected(item) ? Colors.redAccent : Colors.green,
    'spot_rejected_by_admin' => Colors.redAccent,
    'spot_approved_by_admin' => Colors.green,
    'spot_pending_review' => blue,
    'new_spot' => const Color(0xFF9B35FF),
    'temporary_event' => const Color(0xFFFF7A00),
    'friend_nearby' || 'friend_at_spot' => Colors.greenAccent.shade700,
    _ => blue,
  };
}

String notificationCenterTime(int createdAtMillis) {
  if (createdAtMillis <= 0) {
    return '';
  }

  final time = DateTime.fromMillisecondsSinceEpoch(createdAtMillis);
  final now = DateTime.now();
  final difference = now.difference(time);

  if (difference.inMinutes < 1) {
    return trText('Just now');
  }

  if (difference.inHours < 1) {
    return '${difference.inMinutes} min';
  }

  if (difference.inDays < 1) {
    return '${difference.inHours} h';
  }

  final day = time.day.toString().padLeft(2, '0');
  final month = time.month.toString().padLeft(2, '0');
  return '$day.$month.${time.year}';
}

NotificationCenterItem notificationCenterItemFromJson(Object? value) {
  final data = mapFromFirebase(value);
  final payload = mapFromFirebase(data['data']);

  String pickString(String key, String fallback) {
    final topLevel = stringFromFirebase(data[key], '');
    if (topLevel.trim().isNotEmpty) {
      return topLevel;
    }
    return stringFromFirebase(payload[key], fallback);
  }

  int pickMillis(String key) {
    final topLevel = data[key];
    if (topLevel is num) {
      return topLevel.toInt();
    }
    final nested = payload[key];
    if (nested is num) {
      return nested.toInt();
    }
    return 0;
  }

  final type = pickString('type', 'notification');
  final status = pickString('status', '');
  final spotName = pickString('spotName', '');
  final rejectionReason = pickString('rejectionReason', '');
  var body = pickString('body', '');

  if (type == 'spot_review_update' &&
      status == 'rejected' &&
      rejectionReason.trim().isNotEmpty &&
      !body.toLowerCase().contains('reason:')) {
    if (body.trim().isEmpty) {
      body = spotName.trim().isEmpty
          ? 'Your spot was rejected. Reason: ${rejectionReason.trim()}'
          : '$spotName was rejected. Reason: ${rejectionReason.trim()}';
    } else if (body.toLowerCase().contains('rejected')) {
      body = bodyWithRejectionReason(body, rejectionReason);
    }
  }

  return NotificationCenterItem(
    id: pickString('id', ''),
    title: pickString('title', 'CCS'),
    body: body,
    type: type,
    createdAtMillis: pickMillis('createdAtMillis'),
    read: data['read'] == true || payload['read'] == true,
    projectNews: data['projectNews'] == true || payload['projectNews'] == true,
    spotId: pickString('spotId', ''),
    spotName: spotName,
    chatId: pickString('chatId', ''),
    userId: pickString('userId', ''),
    addedByUid: pickString('addedByUid', ''),
    status: status,
    rejectionReason: rejectionReason,
  );
}

NotificationCenterItem notificationCenterItemFromDocument(
  DocumentSnapshot<Map<String, dynamic>> doc, {
  bool projectNews = false,
}) {
  final data = doc.data() ?? {};
  final type = stringFromFirebase(
    data['type'],
    projectNews ? 'project_news' : 'notification',
  );
  final spotName = stringFromFirebase(data['spotName'], '');
  final status = stringFromFirebase(data['status'], '');
  final reviewedBy = stringFromFirebase(data['reviewedBy'], '');
  final rejectionReason = stringFromFirebase(data['rejectionReason'], '');
  final actorUsername = stringFromFirebase(data['actorUsername'], '');
  final comment = stringFromFirebase(data['comment'], '');
  final friendUsername = stringFromFirebase(data['friendUsername'], '');
  final title = stringFromFirebase(data['title'], switch (type) {
    'spot_like' => 'Likes on my spots',
    'spot_comment' => 'Comments',
    'spot_review_update' => 'Spot review updates',
    'chat_message' => 'Messages',
    'new_spot' => 'New spots',
    'temporary_event' => 'Temporary events',
    'spot_pending_review' => 'Spot review updates',
    'spot_approved_by_admin' ||
    'spot_rejected_by_admin' => 'Spot review updates',
    'friend_nearby' || 'friend_at_spot' => 'Live location',
    'project_news' => 'Project news',
    _ => 'CCS',
  });
  var body = stringFromFirebase(data['body'], '');

  if (body.trim().isEmpty) {
    body = switch (type) {
      'spot_like' =>
        spotName.trim().isEmpty
            ? '${actorUsername.trim().isEmpty ? 'Someone' : '@$actorUsername'} liked your spot.'
            : '${actorUsername.trim().isEmpty ? 'Someone' : '@$actorUsername'} liked $spotName.',
      'spot_comment' =>
        spotName.trim().isEmpty
            ? '${actorUsername.trim().isEmpty ? 'Someone' : '@$actorUsername'} commented on your spot${comment.trim().isEmpty ? '.' : ': $comment'}'
            : '${actorUsername.trim().isEmpty ? 'Someone' : '@$actorUsername'} commented on $spotName${comment.trim().isEmpty ? '.' : ': $comment'}',
      'chat_message' => body.trim().isEmpty ? 'New message.' : body,
      'new_spot' =>
        spotName.trim().isEmpty
            ? 'New spot was added.'
            : '$spotName was added.',
      'temporary_event' =>
        spotName.trim().isEmpty
            ? 'New temporary event was added.'
            : '$spotName temporary event was added.',
      'spot_review_update' =>
        status == 'approved'
            ? (spotName.trim().isEmpty
                  ? 'Your spot was approved.'
                  : '$spotName was approved.')
            : (spotName.trim().isEmpty
                  ? 'Your spot was rejected${rejectionReason.trim().isEmpty ? '.' : '. Reason: $rejectionReason'}'
                  : '$spotName was rejected${rejectionReason.trim().isEmpty ? '.' : '. Reason: $rejectionReason'}'),
      'spot_pending_review' =>
        spotName.trim().isEmpty
            ? 'New spot is waiting for review.'
            : '$spotName is waiting for review.',
      'spot_approved_by_admin' =>
        spotName.trim().isEmpty
            ? 'Spot approved.'
            : '$spotName approved${reviewedBy.trim().isEmpty ? '' : ' by $reviewedBy'}.',
      'spot_rejected_by_admin' =>
        spotName.trim().isEmpty
            ? 'Spot rejected${rejectionReason.trim().isEmpty ? '.' : '. Reason: $rejectionReason'}'
            : '$spotName rejected${reviewedBy.trim().isEmpty ? '' : ' by $reviewedBy'}${rejectionReason.trim().isEmpty ? '.' : '. Reason: $rejectionReason'}',
      'friend_nearby' =>
        friendUsername.trim().isEmpty
            ? 'A friend is nearby.'
            : '@$friendUsername is nearby.',
      'friend_at_spot' =>
        friendUsername.trim().isEmpty
            ? 'A friend is at a spot.'
            : '@$friendUsername is at ${spotName.trim().isEmpty ? 'a spot' : spotName}.',
      _ => stringFromFirebase(data['message'], ''),
    };
  }

  final cleanReason = rejectionReason.trim();
  final rejectedWithoutReason =
      cleanReason.isNotEmpty &&
      ((type == 'spot_review_update' && status == 'rejected') ||
          type == 'spot_rejected_by_admin') &&
      !body.toLowerCase().contains('reason:') &&
      body.toLowerCase().contains('rejected');
  if (rejectedWithoutReason) {
    body = bodyWithRejectionReason(body, cleanReason);
  }

  return NotificationCenterItem(
    id: doc.id,
    title: title,
    body: body,
    type: type,
    createdAtMillis: timestampMillisFromFirebase(data['createdAt']),
    read: data['read'] == true,
    reference: projectNews ? null : doc.reference,
    projectNews: projectNews,
    spotId: stringFromFirebase(data['spotId'], ''),
    spotName: spotName,
    chatId: stringFromFirebase(data['chatId'], ''),
    userId: stringFromFirebase(data['userId'], ''),
    addedByUid: stringFromFirebase(data['addedByUid'], ''),
    status: status,
    rejectionReason: rejectionReason,
  );
}

String notificationCenterHiddenIdsKey(String uid) =>
    'notification_center_hidden_ids_$uid';

Future<Set<String>> loadHiddenNotificationCenterIds(String uid) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(notificationCenterHiddenIdsKey(uid))?.toSet() ??
        <String>{};
  } catch (_) {
    return <String>{};
  }
}

Future<void> saveHiddenNotificationCenterIds(
  String uid,
  Set<String> ids,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      notificationCenterHiddenIdsKey(uid),
      ids.toList(),
    );
  } catch (_) {}
}

Future<String> rejectionReasonForNotificationItem(
  NotificationCenterItem item,
) async {
  final existingReason = item.rejectionReason.trim();
  if (existingReason.isNotEmpty) {
    return existingReason;
  }

  final cleanSpotId = item.spotId.trim();
  if (cleanSpotId.isEmpty) {
    return '';
  }

  for (final spot in [
    ...reviewSpots.value,
    ...submittedSpots.value,
    ...approvedPublicSpots(),
  ]) {
    if (spot.id == cleanSpotId || spotReviewKey(spot) == cleanSpotId) {
      return spot.rejectionReason.trim();
    }
  }

  try {
    final doc = await spotsCollection().doc(cleanSpotId).get();
    if (!doc.exists) {
      return '';
    }
    final data = doc.data() ?? {};
    return stringFromFirebase(data['rejectionReason'], '').trim();
  } catch (error, stack) {
    debugPrint('Could not load rejection reason for notification: $error');
    debugPrint('$stack');
    return '';
  }
}

Future<List<NotificationCenterItem>> enrichRejectedNotificationCenterItems(
  List<NotificationCenterItem> items,
) async {
  final enriched = <NotificationCenterItem>[];

  for (final item in items) {
    if (!notificationCenterItemIsRejected(item)) {
      enriched.add(item);
      continue;
    }

    final reason = await rejectionReasonForNotificationItem(item);
    if (reason.trim().isEmpty) {
      enriched.add(item);
      continue;
    }

    enriched.add(
      item.copyWith(
        status: item.status.trim().isEmpty ? 'rejected' : item.status,
        rejectionReason: reason.trim(),
        body: bodyWithRejectionReason(item.body, reason),
      ),
    );
  }

  return enriched;
}

Future<Map<String, String>?> firebaseNotificationHeaders() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return null;
  }

  final token = await firebaseUser.getIdToken();
  if (token == null || token.trim().isEmpty) {
    return null;
  }

  return {HttpHeaders.authorizationHeader: 'Bearer $token'};
}

Future<List<NotificationCenterItem>> loadNotificationCenterItems() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final items = <NotificationCenterItem>[];

  if (firebaseUser == null) {
    notificationCenterUnreadCount.value = 0;
    return const [];
  }

  Future<void> addItems(
    Future<QuerySnapshot<Map<String, dynamic>>> snapshotFuture, {
    bool projectNews = false,
  }) async {
    try {
      final snapshot = await snapshotFuture;
      for (final doc in snapshot.docs) {
        items.add(
          notificationCenterItemFromDocument(doc, projectNews: projectNews),
        );
      }
    } catch (error, stack) {
      debugPrint('Notification center source could not load: $error');
      debugPrint('$stack');
    }
  }

  var serverItemsLoaded = false;
  try {
    final headers = await firebaseNotificationHeaders();
    if (headers != null) {
      final response = await getJsonFromUrl(
        pushNotificationUrl,
        headers: headers,
      );
      final notifications = response['notifications'];
      if (notifications is List) {
        items.addAll(notifications.map(notificationCenterItemFromJson));
        serverItemsLoaded = true;
      }
    }
  } catch (error, stack) {
    debugPrint('Server notification history could not load: $error');
    debugPrint('$stack');
  }

  final sourceLoads = <Future<void>>[
    addItems(
      adminNotificationsCollection()
          .where('userId', isEqualTo: firebaseUser.uid)
          .limit(50)
          .get(),
    ),
    addItems(
      friendLocationNotificationsCollection()
          .where('userId', isEqualTo: firebaseUser.uid)
          .limit(50)
          .get(),
    ),
    // Always load Firestore user notifications too. The push server history can
    // lag behind or omit custom fields such as rejectionReason, so Firestore is
    // the source of truth for review decision details.
    addItems(
      userNotificationsCollection()
          .where('userId', isEqualTo: firebaseUser.uid)
          .limit(50)
          .get(),
    ),
    addItems(projectNewsCollection().limit(20).get(), projectNews: true),
  ];

  await Future.wait(sourceLoads);

  if (!items.any((item) => item.projectNews)) {
    items.addAll(const [
      NotificationCenterItem(
        id: 'project_news_ready',
        title: 'Project news',
        body: 'CCS notification center is ready.',
        type: 'project_news',
        createdAtMillis: 0,
        read: true,
        projectNews: true,
      ),
    ]);
  }

  final mergedById = <String, NotificationCenterItem>{};
  final mergedItems = <NotificationCenterItem>[];

  bool isRicherNotification(
    NotificationCenterItem candidate,
    NotificationCenterItem current,
  ) {
    final candidateHasReason =
        candidate.rejectionReason.trim().isNotEmpty ||
        candidate.body.toLowerCase().contains('reason:');
    final currentHasReason =
        current.rejectionReason.trim().isNotEmpty ||
        current.body.toLowerCase().contains('reason:');

    if (candidateHasReason && !currentHasReason) {
      return true;
    }

    if (candidate.reference != null && current.reference == null) {
      return true;
    }

    return candidate.body.length > current.body.length;
  }

  for (final item in items) {
    final id = item.id.trim();
    if (id.isEmpty) {
      mergedItems.add(item);
      continue;
    }

    final current = mergedById[id];
    if (current == null || isRicherNotification(item, current)) {
      mergedById[id] = item;
    }
  }

  items
    ..clear()
    ..addAll(mergedItems)
    ..addAll(mergedById.values);

  final hiddenIds = await loadHiddenNotificationCenterIds(firebaseUser.uid);
  if (hiddenIds.isNotEmpty) {
    items.removeWhere((item) {
      final id = item.id.trim();
      return id.isNotEmpty && hiddenIds.contains(id);
    });
  }

  final enrichedItems = await enrichRejectedNotificationCenterItems(items);
  items
    ..clear()
    ..addAll(enrichedItems);

  items.sort((first, second) {
    if (first.createdAtMillis == second.createdAtMillis) {
      return first.projectNews ? 1 : -1;
    }

    return second.createdAtMillis.compareTo(first.createdAtMillis);
  });

  notificationCenterUnreadCount.value = items
      .where((item) => !item.read)
      .length;
  return items.take(80).toList();
}

Future<void> markNotificationCenterItemsRead(
  Iterable<NotificationCenterItem> items,
) async {
  final unreadItems = items.where((item) => !item.read).toList();
  final firestoreItems = unreadItems
      .where((item) => !item.read && item.reference != null)
      .toList();
  final serverNotificationIds = unreadItems
      .where((item) => item.reference == null && !item.projectNews)
      .map((item) => item.id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();

  if (firestoreItems.isEmpty && serverNotificationIds.isEmpty) {
    return;
  }

  try {
    if (serverNotificationIds.isNotEmpty) {
      final headers = await firebaseNotificationHeaders();
      if (headers != null) {
        await patchJsonToUrl(pushNotificationUrl, {
          'notificationIds': serverNotificationIds,
        }, headers: headers);
      }
    }

    if (firestoreItems.isNotEmpty) {
      final batch = FirebaseFirestore.instance.batch();
      for (final item in firestoreItems) {
        final reference = item.reference;
        if (reference == null) {
          continue;
        }
        batch.set(reference, {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }

    notificationCenterUnreadCount.value = 0;
  } catch (error, stack) {
    debugPrint('Notification history could not be marked read: $error');
    debugPrint('$stack');
  }
}

Future<void> clearNotificationCenterItems(
  Iterable<NotificationCenterItem> items,
) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null) {
    notificationCenterUnreadCount.value = 0;
    return;
  }

  final cleanItems = items.toList();
  if (cleanItems.isEmpty) {
    notificationCenterUnreadCount.value = 0;
    return;
  }

  final hiddenIds = await loadHiddenNotificationCenterIds(firebaseUser.uid);
  for (final item in cleanItems) {
    final id = item.id.trim();
    if (id.isNotEmpty) {
      hiddenIds.add(id);
    }
  }
  await saveHiddenNotificationCenterIds(firebaseUser.uid, hiddenIds);

  final references = cleanItems
      .map((item) => item.reference)
      .whereType<DocumentReference<Map<String, dynamic>>>()
      .toList();

  if (references.isNotEmpty) {
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final reference in references) {
        batch.delete(reference);
      }
      await batch.commit();
    } catch (error, stack) {
      debugPrint('Notification center could not clear Firestore items: $error');
      debugPrint('$stack');
    }
  }

  final serverNotificationIds = cleanItems
      .where((item) => item.reference == null && !item.projectNews)
      .map((item) => item.id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();

  if (serverNotificationIds.isNotEmpty) {
    try {
      final headers = await firebaseNotificationHeaders();
      if (headers != null) {
        // The backend currently supports marking notifications read. The local
        // hidden-id list above keeps cleared server-history items out of the
        // bell even if the backend does not physically delete them yet.
        await patchJsonToUrl(pushNotificationUrl, {
          'notificationIds': serverNotificationIds,
        }, headers: headers);
      }
    } catch (error, stack) {
      debugPrint(
        'Server notifications could not be marked read while clearing: $error',
      );
      debugPrint('$stack');
    }
  }

  notificationCenterUnreadCount.value = 0;
}

Future<void> refreshNotificationCenterUnreadCount() async {
  await loadNotificationCenterItems();
}

class CcsLanguageSelector extends StatelessWidget {
  const CcsLanguageSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appUiPreferences,
      builder: (context, _) {
        return PopupMenuButton<AppLanguage>(
          tooltip: trText('Language'),
          onSelected: (language) {
            unawaited(appUiPreferences.setLanguage(language));
          },
          itemBuilder: (context) => [
            for (final language in AppLanguage.values)
              PopupMenuItem<AppLanguage>(
                value: language,
                child: Row(
                  children: [
                    Icon(
                      appUiPreferences.language == language
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: blue,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(language.name.toUpperCase()),
                  ],
                ),
              ),
          ],
          child: Container(
            width: 42,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: blue.withValues(alpha: 0.52)),
            ),
            child: Text(
              appUiPreferences.language.name.toUpperCase(),
              style: const TextStyle(
                color: blue,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      },
    );
  }
}

class CcsNotificationBell extends StatelessWidget {
  const CcsNotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: trText('Notifications'),
      onPressed: () {
        Navigator.push(
          context,
          appPageRoute(builder: (_) => const NotificationCenterScreen()),
        );
      },
      icon: ValueListenableBuilder<int>(
        valueListenable: notificationCenterUnreadCount,
        builder: (context, unreadCount, _) {
          return Badge(
            isLabelVisible: unreadCount > 0,
            label: Text(unreadCount > 9 ? '9+' : '$unreadCount'),
            child: const Icon(Icons.notifications_none),
          );
        },
      ),
    );
  }
}

List<Widget> ccsAppBarActions() {
  return const [
    CcsLanguageSelector(),
    SizedBox(width: 6),
    CcsNotificationBell(),
    SizedBox(width: 4),
  ];
}

Future<CarSpot?> spotForNotificationItem(NotificationCenterItem item) async {
  final cleanSpotId = item.spotId.trim();
  if (cleanSpotId.isEmpty) {
    return null;
  }

  for (final spot in reviewSpots.value) {
    if (spot.id == cleanSpotId || spotReviewKey(spot) == cleanSpotId) {
      return spot;
    }
  }
  for (final spot in approvedPublicSpots()) {
    if (spot.id == cleanSpotId || spotReviewKey(spot) == cleanSpotId) {
      return spot;
    }
  }
  for (final spot in submittedSpots.value) {
    if (spot.id == cleanSpotId || spotReviewKey(spot) == cleanSpotId) {
      return spot;
    }
  }

  try {
    final doc = await spotsCollection().doc(cleanSpotId).get();
    if (doc.exists) {
      return CarSpot.fromFirestore(doc);
    }
  } catch (_) {}

  return null;
}

Future<void> openNotificationCenterItem(
  BuildContext context,
  NotificationCenterItem item,
) async {
  if (item.reference != null) {
    unawaited(item.reference!.set({'read': true}, SetOptions(merge: true)));
  }

  final cleanChatId = item.chatId.trim();
  if (cleanChatId.isNotEmpty) {
    try {
      final doc = await chatsCollection().doc(cleanChatId).get();
      if (!context.mounted) return;
      if (doc.exists) {
        Navigator.push(
          context,
          appPageRoute(
            builder: (_) =>
                ChatConversationScreen(chat: ChatThreadData.fromFirestore(doc)),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Chat is not available anymore.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not open chat: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return;
  }

  final cleanProfileUid = item.addedByUid.trim().isNotEmpty
      ? item.addedByUid.trim()
      : item.userId.trim();
  if ((item.type == 'friend_nearby' || item.type == 'friend_at_spot') &&
      cleanProfileUid.isNotEmpty) {
    openUserProfile(context, uid: cleanProfileUid);
    return;
  }

  final spot = await spotForNotificationItem(item);
  if (!context.mounted) return;

  if (spot == null) {
    if (item.type == 'spot_pending_review' &&
        userRoleIsStaff(currentUser.role)) {
      Navigator.push(
        context,
        appPageRoute(builder: (_) => const AdminReviewScreen()),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'Spot is not available anymore.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return;
  }

  if (userRoleIsStaff(currentUser.role) &&
      (item.type == 'spot_pending_review' ||
          item.type == 'spot_approved_by_admin' ||
          item.type == 'spot_rejected_by_admin')) {
    Navigator.push(
      context,
      appPageRoute(builder: (_) => AdminSpotReviewScreen(spot: spot)),
    );
    return;
  }

  Navigator.push(
    context,
    appPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
  );
}

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  late Future<List<NotificationCenterItem>> itemsFuture;
  bool markedRead = false;
  bool clearingNotifications = false;

  @override
  void initState() {
    super.initState();
    itemsFuture = loadNotificationCenterItems();
  }

  void refresh() {
    setState(() {
      markedRead = false;
      itemsFuture = loadNotificationCenterItems();
    });
  }

  Future<void> clearAllNotifications() async {
    if (clearingNotifications) {
      return;
    }

    setState(() => clearingNotifications = true);

    try {
      final items = await itemsFuture;
      await clearNotificationCenterItems(items);
      if (!mounted) {
        return;
      }
      setState(() {
        markedRead = true;
        itemsFuture = Future.value(const <NotificationCenterItem>[]);
      });
    } catch (error, stack) {
      debugPrint('Notification center could not clear items: $error');
      debugPrint('$stack');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not clear notifications: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => clearingNotifications = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: [
          TextButton.icon(
            onPressed: clearingNotifications ? null : clearAllNotifications,
            icon: clearingNotifications
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.clear_all, size: 18),
            label: const Text('Clear all'),
            style: TextButton.styleFrom(foregroundColor: blue),
          ),
          IconButton(
            tooltip: trText('Refresh'),
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<NotificationCenterItem>>(
        future: itemsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data ?? const <NotificationCenterItem>[];
          if (!markedRead) {
            markedRead = true;
            unawaited(markNotificationCenterItemsRead(items));
          }

          if (items.isEmpty) {
            return const EmptyStateCard(
              icon: Icons.notifications_none,
              title: 'No notifications yet',
              text: 'Your latest CCS updates will appear here.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              final color = notificationCenterColor(item);

              return InkWell(
                onTap: item.canOpen
                    ? () => openNotificationCenterItem(context, item)
                    : null,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: panelGlass,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: item.read
                          ? Colors.white12
                          : color.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(notificationCenterIcon(item), color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (item.body.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                item.body,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            if (notificationCenterTime(
                              item.createdAtMillis,
                            ).isNotEmpty) ...[
                              const SizedBox(height: 7),
                              Text(
                                notificationCenterTime(item.createdAtMillis),
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (item.canOpen) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.chevron_right,
                          color: Colors.white38,
                          size: 22,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SplashIntroItem extends StatelessWidget {
  final Animation<double> animation;
  final Animation<double> fadeAnimation;
  final Widget child;
  final double travel;

  const _SplashIntroItem({
    required this.animation,
    required this.fadeAnimation,
    required this.child,
    this.travel = 96,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final easedValue = animation.value;
        final opacity = fadeAnimation.value.clamp(0.0, 1.0);

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, (1 - easedValue) * travel),
            child: child,
          ),
        );
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  final bool showBackground;

  const LoginScreen({super.key, this.showBackground = true});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool isSigningIn = false;
  bool rememberMe = rememberMeEnabled;

  late final AnimationController loginIntroController;
  late final Animation<double> loginLogoSlide;
  late final Animation<double> loginSubtitleSlide;
  late final Animation<double> loginGoogleSlide;
  late final Animation<double> loginTelegramSlide;
  late final Animation<double> loginRememberSlide;
  late final Animation<double> loginTermsSlide;
  late final Animation<double> loginLogoFade;
  late final Animation<double> loginSubtitleFade;
  late final Animation<double> loginGoogleFade;
  late final Animation<double> loginTelegramFade;
  late final Animation<double> loginRememberFade;
  late final Animation<double> loginTermsFade;

  @override
  void initState() {
    super.initState();

    loginIntroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );

    loginLogoSlide = _loginSlideAnimation(0.00, 0.50);
    loginSubtitleSlide = _loginSlideAnimation(0.12, 0.58);
    loginGoogleSlide = _loginSlideAnimation(0.28, 0.72);
    loginTelegramSlide = _loginSlideAnimation(0.40, 0.84);
    loginRememberSlide = _loginSlideAnimation(0.52, 0.92);
    loginTermsSlide = _loginSlideAnimation(0.62, 1.00);
    loginLogoFade = _loginFadeAnimation(0.00, 0.36);
    loginSubtitleFade = _loginFadeAnimation(0.12, 0.44);
    loginGoogleFade = _loginFadeAnimation(0.28, 0.62);
    loginTelegramFade = _loginFadeAnimation(0.40, 0.74);
    loginRememberFade = _loginFadeAnimation(0.52, 0.86);
    loginTermsFade = _loginFadeAnimation(0.62, 1.00);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        loginIntroController.forward();
      }
    });
  }

  Animation<double> _loginSlideAnimation(double begin, double end) {
    return CurvedAnimation(
      parent: loginIntroController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  Animation<double> _loginFadeAnimation(double begin, double end) {
    return CurvedAnimation(
      parent: loginIntroController,
      curve: Interval(begin, end, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    loginIntroController.dispose();
    super.dispose();
  }

  Widget loginButton(
    String text,
    IconData icon,
    Color color,
    VoidCallback? onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color),
        label: Text(text),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Future<void> loginWithGoogle() async {
    setState(() => isSigningIn = true);

    try {
      await signInWithGoogleAndSaveUser();
      await saveRememberMePreference(rememberMe);

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        appPageRoute(builder: (_) => const MainScreen()),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Google login failed. Check Firebase Google sign-in setup. $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSigningIn = false);
      }
    }
  }

  Future<void> loginWithTelegram() async {
    setState(() => isSigningIn = true);

    try {
      await signInWithTelegramAndSaveUser();
      await saveRememberMePreference(rememberMe);

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        appPageRoute(builder: (_) => const MainScreen()),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Telegram login failed. $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSigningIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.showBackground
          ? Colors.black
          : Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.showBackground) ...[
            Image.asset('assets/bg.png', fit: BoxFit.cover),
            Container(color: Colors.black.withValues(alpha: 0.42)),
          ],
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SplashIntroItem(
                  animation: loginLogoSlide,
                  fadeAnimation: loginLogoFade,
                  travel: 112,
                  child: const _CcsWordmark(width: 213),
                ),
                const SizedBox(height: 14),
                _SplashIntroItem(
                  animation: loginSubtitleSlide,
                  fadeAnimation: loginSubtitleFade,
                  travel: 100,
                  child: const Text(
                    'COMMUNITY CAR SPOTS',
                    style: TextStyle(letterSpacing: 3, color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 60),
                _SplashIntroItem(
                  animation: loginGoogleSlide,
                  fadeAnimation: loginGoogleFade,
                  travel: 88,
                  child: loginButton(
                    isSigningIn ? 'Signing in...' : 'Continue with Google',
                    Icons.g_mobiledata,
                    Colors.red,
                    isSigningIn ? null : loginWithGoogle,
                  ),
                ),
                _SplashIntroItem(
                  animation: loginTelegramSlide,
                  fadeAnimation: loginTelegramFade,
                  travel: 76,
                  child: loginButton(
                    'Continue with Telegram',
                    Icons.send,
                    blue,
                    isSigningIn ? null : loginWithTelegram,
                  ),
                ),
                const SizedBox(height: 4),
                _SplashIntroItem(
                  animation: loginRememberSlide,
                  fadeAnimation: loginRememberFade,
                  travel: 64,
                  child: _RememberMeRow(
                    value: rememberMe,
                    enabled: !isSigningIn,
                    onChanged: (value) => setState(() => rememberMe = value),
                  ),
                ),
                const SizedBox(height: 28),
                _SplashIntroItem(
                  animation: loginTermsSlide,
                  fadeAnimation: loginTermsFade,
                  travel: 52,
                  child: const Text(
                    'By continuing, you agree to our Terms & Privacy Policy',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RememberMeRow extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _RememberMeRow({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: enabled
                  ? (checked) => onChanged(checked ?? false)
                  : null,
              activeColor: blue,
              checkColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
            ),
            const SizedBox(width: 4),
            const Text(
              'Remember me',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            const Icon(Icons.lock_outline, color: Colors.white38, size: 16),
          ],
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int index = 0;
  bool hasOpenedMap = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  meetNotificationSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  adminNotificationSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  friendLocationNotificationSubscription;
  Timer? friendLocationCheckTimer;
  Timer? onlinePresenceRefreshTimer;
  bool isCheckingFriendLocationNotifications = false;

  List<Widget> get screens => [
    const ExploreScreen(),
    hasOpenedMap
        ? MapScreen(isVisible: index == 1)
        : const SizedBox.shrink(),
    const AddSpotScreen(),
    const ChatScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    mapFocusRequest.addListener(handleMapFocusRequest);
    unawaited(initializePushNotificationsForCurrentUser());
    updateCurrentUserOnlinePresence(isOnline: true);
    onlinePresenceRefreshTimer = Timer.periodic(const Duration(seconds: 20), (
      _,
    ) {
      updateCurrentUserOnlinePresence(isOnline: true);
    });
    startMeetNotificationListener();
    startAdminNotificationListener();
    startFriendLocationNotificationListener();
    startFriendLocationNotificationChecks();
  }

  void handleMapFocusRequest() {
    if (mapFocusRequest.value == null || !mounted) {
      return;
    }

    if (index != 1 || !hasOpenedMap) {
      setState(() {
        hasOpenedMap = true;
        index = 1;
      });
    }
  }

  void openMapTab() {
    if (index == 1 && hasOpenedMap) {
      return;
    }

    setState(() {
      hasOpenedMap = true;
      index = 1;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      updateCurrentUserOnlinePresence(isOnline: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      updateCurrentUserOnlinePresence(isOnline: false);
    }
  }

  void startMeetNotificationListener() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return;
    }

    meetNotificationSubscription = meetNotificationsCollection()
        .where('userId', isEqualTo: firebaseUser.uid)
        .snapshots()
        .listen((snapshot) async {
          for (final change in snapshot.docChanges) {
            if (change.type != DocumentChangeType.added) {
              continue;
            }

            final data = change.doc.data() ?? {};

            if (data['read'] == true) {
              continue;
            }

            final spotName = stringFromFirebase(
              data['spotName'],
              'New meet spot',
            );
            final distanceMeters = doubleFromFirebase(
              data['distanceMeters'],
              0,
            );
            final distanceKm = distanceMeters <= 0
                ? ''
                : ' • ${(distanceMeters / 1000).toStringAsFixed(1)} km away';

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: blue,
                  content: Text(
                    'New meet nearby: $spotName$distanceKm',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }

            await change.doc.reference.set({
              'read': true,
              'readAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        });
  }

  void startAdminNotificationListener() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null || currentUser.role != UserRole.admin) {
      return;
    }

    adminNotificationSubscription = adminNotificationsCollection()
        .where('userId', isEqualTo: firebaseUser.uid)
        .snapshots()
        .listen((snapshot) async {
          for (final change in snapshot.docChanges) {
            if (change.type != DocumentChangeType.added) {
              continue;
            }

            final data = change.doc.data() ?? {};

            if (data['read'] == true) {
              continue;
            }

            final type = stringFromFirebase(data['type'], '');
            final spotName = stringFromFirebase(data['spotName'], 'New spot');
            final addedBy = stringFromFirebase(data['addedBy'], 'user');
            final reviewedBy = stringFromFirebase(data['reviewedBy'], 'admin');
            final rejectionReason = stringFromFirebase(
              data['rejectionReason'],
              '',
            );
            final rejectionSuffix = rejectionReason.trim().isEmpty
                ? ''
                : ' — $rejectionReason';

            final message = switch (type) {
              'spot_pending_review' =>
                'New spot waiting for review: $spotName by $addedBy',
              'spot_approved_by_admin' =>
                '$reviewedBy approved spot: $spotName',
              'spot_rejected_by_admin' =>
                '$reviewedBy rejected spot: $spotName$rejectionSuffix',
              _ => 'Admin update: $spotName',
            };

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: panelGlass,
                  content: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }

            await change.doc.reference.set({
              'read': true,
              'readAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        });
  }

  void startFriendLocationNotificationListener() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return;
    }

    friendLocationNotificationSubscription =
        friendLocationNotificationsCollection()
            .where('userId', isEqualTo: firebaseUser.uid)
            .snapshots()
            .listen((snapshot) async {
              for (final change in snapshot.docChanges) {
                if (change.type != DocumentChangeType.added &&
                    change.type != DocumentChangeType.modified) {
                  continue;
                }

                final data = change.doc.data() ?? {};

                if (data['read'] == true) {
                  continue;
                }

                final type = stringFromFirebase(data['type'], 'friend_nearby');
                final friendUsername = stringFromFirebase(
                  data['friendUsername'],
                  'friend',
                );
                final spotName = stringFromFirebase(data['spotName'], 'a spot');
                final distanceMeters = doubleFromFirebase(
                  data['distanceMeters'],
                  0,
                );
                final distanceLabel = distanceMeters <= 0
                    ? ''
                    : distanceMeters >= 1000
                    ? ' • ${(distanceMeters / 1000).toStringAsFixed(1)} km away'
                    : ' • ${distanceMeters.round()} m away';

                final message = type == 'friend_at_spot'
                    ? '@$friendUsername is at $spotName$distanceLabel'
                    : '@$friendUsername is nearby$distanceLabel';

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.greenAccent.shade700,
                      content: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }

                await change.doc.reference.set({
                  'read': true,
                  'readAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
              }
            });
  }

  void startFriendLocationNotificationChecks() {
    runFriendLocationNotificationCheck();
    friendLocationCheckTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => runFriendLocationNotificationCheck(),
    );
  }

  Future<void> runFriendLocationNotificationCheck() async {
    if (isCheckingFriendLocationNotifications) {
      return;
    }

    isCheckingFriendLocationNotifications = true;

    try {
      await checkFriendLocationNotifications();
    } catch (_) {
      // Friend location notifications are best-effort in-app alerts.
    } finally {
      isCheckingFriendLocationNotifications = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    mapFocusRequest.removeListener(handleMapFocusRequest);
    onlinePresenceRefreshTimer?.cancel();
    updateCurrentUserOnlinePresence(isOnline: false);
    meetNotificationSubscription?.cancel();
    adminNotificationSubscription?.cancel();
    friendLocationNotificationSubscription?.cancel();
    friendLocationCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appUiPreferences,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: false,
          body: IndexedStack(index: index, children: screens),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              height: 62,
              decoration: BoxDecoration(
                color: panelGlass,
                border: const Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _CcsBottomNavItem(
                      icon: Icons.location_on,
                      label: trText('Spots'),
                      selected: index == 0,
                      onTap: () => setState(() => index = 0),
                    ),
                  ),
                  Expanded(
                    child: _CcsBottomNavItem(
                      icon: Icons.map,
                      label: trText('Map'),
                      selected: index == 1,
                      onTap: openMapTab,
                    ),
                  ),
                  Expanded(
                    child: _CcsBottomNavItem(
                      icon: Icons.add_circle_outline,
                      label: trText('Add Spot Nav'),
                      selected: index == 2,
                      onTap: () => setState(() => index = 2),
                      twoLineCentered:
                          appUiPreferences.language != AppLanguage.en,
                    ),
                  ),
                  Expanded(
                    child: _CcsBottomNavItem(
                      icon: Icons.chat_bubble_outline,
                      label: trText('Chat'),
                      selected: index == 3,
                      onTap: () => setState(() => index = 3),
                    ),
                  ),
                  Expanded(
                    child: _CcsBottomNavItem(
                      icon: Icons.person_outline,
                      label: trText('Profile'),
                      selected: index == 4,
                      onTap: () => setState(() => index = 4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CcsBottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool twoLineCentered;

  const _CcsBottomNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.twoLineCentered = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? blue : Colors.white54;
    final parts = label.split('\n');
    final firstLine = parts.isEmpty ? label : parts.first;
    final secondLine = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    // Keep every bottom-tab icon on the same Y level.
    // RU/LV Add Spot uses two centered lines: first line aligned with other labels,
    // second line sits below it. EN stays as the original single-line label.
    return InkWell(
      onTap: onTap,
      child: SizedBox.expand(
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(top: 7, child: Icon(icon, color: color, size: 22)),
            Positioned(
              top: 33,
              left: 0,
              right: 0,
              child: Text(
                twoLineCentered ? firstLine : label.replaceAll('\n', ' '),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  height: 1.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (twoLineCentered && secondLine.trim().isNotEmpty)
              Positioned(
                top: 43,
                left: 0,
                right: 0,
                child: Text(
                  secondLine,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    height: 1.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum ExploreSortMode { popular, newest, old, meet }

String exploreSortLabel(ExploreSortMode mode) {
  switch (mode) {
    case ExploreSortMode.popular:
      return 'Popular';
    case ExploreSortMode.newest:
      return 'New';
    case ExploreSortMode.old:
      return 'Old';
    case ExploreSortMode.meet:
      return 'Meet';
  }
}

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  ExploreSortMode selectedMode = ExploreSortMode.popular;
  bool showSavedOnly = false;
  final Set<String> expandedCategories = {};

  @override
  void initState() {
    super.initState();
    savedSpots.addListener(refreshSavedFilter);
    spotCategoryFilters.addListener(refreshSpotCategoryFilters);
  }

  @override
  void dispose() {
    savedSpots.removeListener(refreshSavedFilter);
    spotCategoryFilters.removeListener(refreshSpotCategoryFilters);
    super.dispose();
  }

  void refreshSavedFilter() {
    if (mounted && showSavedOnly) {
      setState(() {});
    }
  }

  void refreshSpotCategoryFilters() {
    if (mounted) {
      setState(() {});
    }
  }

  void toggleCategoryExpansion(String category) {
    setState(() {
      if (!expandedCategories.add(category)) {
        expandedCategories.remove(category);
      }
    });
  }

  List<CarSpot> sortedSpots(List<CarSpot> spots) {
    final list = [...spots];

    if (selectedMode == ExploreSortMode.meet) {
      list.removeWhere((spot) => !spot.categories.contains('Meet'));
    }

    switch (selectedMode) {
      case ExploreSortMode.popular:
        list.sort((a, b) {
          final ratingCompare = b.rating.compareTo(a.rating);
          if (ratingCompare != 0) {
            return ratingCompare;
          }
          return b.createdAtMillis.compareTo(a.createdAtMillis);
        });
        break;
      case ExploreSortMode.newest:
        list.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
        break;
      case ExploreSortMode.old:
        list.sort((a, b) => a.createdAtMillis.compareTo(b.createdAtMillis));
        break;
      case ExploreSortMode.meet:
        list.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
        break;
    }

    return list;
  }

  List<CarSpot> filteredSpots() {
    final enabledCategoryFilters = spotCategoryFilters.value;

    if (enabledCategoryFilters.isEmpty) {
      return const [];
    }

    return approvedPublicSpots().where((spot) {
      if (!spot.categories.any(enabledCategoryFilters.contains)) {
        return false;
      }

      if (!showSavedOnly) {
        return true;
      }

      return savedSpots.value.any((saved) => isSameSpot(saved, spot));
    }).toList();
  }

  Map<String, List<CarSpot>> upcomingTemporarySpotGroups() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final dayAfterTomorrowStart = todayStart.add(const Duration(days: 2));
    final thisWeekEnd = todayStart.add(
      Duration(days: DateTime.sunday - now.weekday + 1),
    );
    final nextWeekStart = thisWeekEnd;
    final nextWeekEnd = nextWeekStart.add(const Duration(days: 7));
    final thisMonthEnd = DateTime(now.year, now.month + 1, 1);
    final nextMonthEnd = DateTime(now.year, now.month + 2, 1);

    final groups = <String, List<CarSpot>>{
      'Today': [],
      'Tomorrow': [],
      'This week': [],
      'Next week': [],
      'This month': [],
      'Next month': [],
    };

    for (final spot in approvedPublicSpots()) {
      if (!spot.hasTemporaryWindow || spot.isExpired) {
        continue;
      }

      final startsAt = DateTime.fromMillisecondsSinceEpoch(
        spot.startsAtMillis!,
      );
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        spot.expiresAtMillis!,
      );
      final startsToday = isSameLocalDate(now, startsAt);
      final startsTomorrow =
          !startsAt.isBefore(tomorrowStart) &&
          startsAt.isBefore(dayAfterTomorrowStart);

      if (spot.isTemporaryActiveNow || startsToday) {
        groups['Today']!.add(spot);
      } else if (startsTomorrow) {
        groups['Tomorrow']!.add(spot);
      } else if (!startsAt.isBefore(dayAfterTomorrowStart) &&
          startsAt.isBefore(thisWeekEnd)) {
        groups['This week']!.add(spot);
      } else if (!startsAt.isBefore(nextWeekStart) &&
          startsAt.isBefore(nextWeekEnd)) {
        groups['Next week']!.add(spot);
      } else if (!startsAt.isBefore(nextWeekEnd) &&
          startsAt.isBefore(thisMonthEnd)) {
        groups['This month']!.add(spot);
      } else if (!startsAt.isBefore(thisMonthEnd) &&
          startsAt.isBefore(nextMonthEnd)) {
        groups['Next month']!.add(spot);
      } else if (expiresAt.isAfter(now) && startsAt.isBefore(tomorrowStart)) {
        groups['Today']!.add(spot);
      }
    }

    for (final spots in groups.values) {
      spots.sort((a, b) {
        final aActive = a.isTemporaryActiveNow;
        final bActive = b.isTemporaryActiveNow;

        if (aActive != bActive) {
          return aActive ? -1 : 1;
        }

        final aStartsAt = a.startsAtMillis ?? 0;
        final bStartsAt = b.startsAtMillis ?? 0;
        return aStartsAt.compareTo(bStartsAt);
      });
    }

    groups.removeWhere((_, spots) => spots.isEmpty);
    return groups;
  }

  Map<String, List<CarSpot>> groupedSpotsByCategory(List<CarSpot> spots) {
    final grouped = <String, List<CarSpot>>{};

    for (final category in spotCategoryOptions) {
      final categorySpots = spots
          .where((spot) => primarySpotCategory(spot) == category)
          .toList();
      final sortedCategorySpots = sortedSpots(categorySpots);

      if (sortedCategorySpots.isNotEmpty) {
        grouped[category] = sortedCategorySpots;
      }
    }

    return grouped;
  }

  Future<void> showExploreCategoryFilterSheet() async {
    final nextEnabledCategories = Set<String>.from(spotCategoryFilters.value);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: panelGlass,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final selectedCount = nextEnabledCategories.length;

            void selectAll() {
              setSheetState(() {
                nextEnabledCategories
                  ..clear()
                  ..addAll(spotCategoryOptions);
              });
            }

            void clearAll() {
              setSheetState(nextEnabledCategories.clear);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Explore filters',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectedCount == spotCategoryOptions.length
                          ? 'All categories enabled'
                          : '$selectedCount of ${spotCategoryOptions.length} categories enabled',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: selectAll,
                          icon: const Icon(Icons.done_all),
                          label: const Text('Select all'),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: clearAll,
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final category in spotCategoryOptions)
                              CheckboxListTile(
                                value: nextEnabledCategories.contains(category),
                                onChanged: (enabled) {
                                  setSheetState(() {
                                    if (enabled == true) {
                                      nextEnabledCategories.add(category);
                                    } else {
                                      nextEnabledCategories.remove(category);
                                    }
                                  });
                                },
                                dense: true,
                                activeColor: spotColorForCategory(category),
                                checkColor: Colors.black,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: spotColorForCategory(category),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      category,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          updateSpotCategoryFilters(nextEnabledCategories);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: const Icon(Icons.tune),
                        label: const Text(
                          'Apply filters',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget sortChip(ExploreSortMode mode) {
    final selected = selectedMode == mode;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(exploreSortLabel(mode)),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => selectedMode = mode),
        selectedColor: blue,
        backgroundColor: Colors.white.withValues(alpha: 0.07),
        side: BorderSide(color: selected ? blue : Colors.white12),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }

  Widget savedFilterChip() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: const Text('Saved'),
        avatar: Icon(
          showSavedOnly ? Icons.bookmark : Icons.bookmark_border,
          color: showSavedOnly ? Colors.white : Colors.white70,
          size: 18,
        ),
        selected: showSavedOnly,
        showCheckmark: false,
        onSelected: (value) => setState(() => showSavedOnly = value),
        selectedColor: blue,
        backgroundColor: Colors.white.withValues(alpha: 0.07),
        side: BorderSide(color: showSavedOnly ? blue : Colors.white12),
        labelStyle: TextStyle(
          color: showSavedOnly ? Colors.white : Colors.white70,
          fontWeight: showSavedOnly ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CarSpot>>(
      valueListenable: reviewSpots,
      builder: (context, _, _) {
        final approvedSpots = filteredSpots();
        final upcomingTemporaryGroups = upcomingTemporarySpotGroups();
        final upcomingTemporaryCount = upcomingTemporaryGroups.values.fold<int>(
          0,
          (count, spots) => count + spots.length,
        );
        final groupedSpots = groupedSpotsByCategory(
          approvedSpots
              .where((spot) => !spot.hasTemporaryWindow || spot.isExpired)
              .toList(),
        );
        final selectedCount = spotCategoryFilters.value.length;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const CcsAppBarLogo(),
            backgroundColor: Colors.transparent,
            foregroundColor: blue,
            actions: ccsAppBarActions(),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Spots',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Approved car spots',
                          style: TextStyle(color: Colors.white54, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: showExploreCategoryFilterSheet,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(
                      selectedCount == spotCategoryOptions.length
                          ? 'Filters'
                          : '$selectedCount/${spotCategoryOptions.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    sortChip(ExploreSortMode.popular),
                    sortChip(ExploreSortMode.newest),
                    sortChip(ExploreSortMode.old),
                    sortChip(ExploreSortMode.meet),
                    savedFilterChip(),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (upcomingTemporaryGroups.isNotEmpty) ...[
                UpcomingTemporarySpotsSection(groups: upcomingTemporaryGroups),
                const SizedBox(height: 18),
              ],
              if (groupedSpots.isEmpty && upcomingTemporaryCount == 0)
                EmptyStateCard(
                  icon: Icons.explore,
                  title: showSavedOnly
                      ? 'No saved spots yet'
                      : approvedPublicSpots().isEmpty
                      ? 'No spots here yet'
                      : 'No spots match your filters',
                  text: showSavedOnly
                      ? 'Tap the bookmark on a spot to keep it here.'
                      : approvedPublicSpots().isEmpty
                      ? 'Approved spots will appear here after moderation.'
                      : 'Open filters and enable more categories to see more spots.',
                ),
              for (final entry in groupedSpots.entries) ...[
                ExploreCategoryHeader(
                  category: entry.key,
                  count: entry.value.length,
                ),
                const SizedBox(height: 10),
                for (final spot
                    in (expandedCategories.contains(entry.key)
                        ? entry.value
                        : entry.value.take(2))) ...[
                  ExploreSpotCard(spot: spot),
                  const SizedBox(height: 14),
                ],
                if (entry.value.length > 2)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => toggleCategoryExpansion(entry.key),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: spotColorForCategory(entry.key),
                        side: BorderSide(
                          color: spotColorForCategory(
                            entry.key,
                          ).withValues(alpha: 0.55),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: Icon(
                        expandedCategories.contains(entry.key)
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                      label: Text(
                        expandedCategories.contains(entry.key)
                            ? 'Show less'
                            : 'Show ${entry.value.length - 2} more',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        );
      },
    );
  }
}

class UpcomingTemporarySpotsSection extends StatelessWidget {
  final Map<String, List<CarSpot>> groups;

  const UpcomingTemporarySpotsSection({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    final totalCount = groups.values.fold<int>(
      0,
      (count, spots) => count + spots.length,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.36)),
        boxShadow: [
          BoxShadow(
            color: Colors.orangeAccent.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.campaign, color: Colors.orangeAccent),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upcoming',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Temporary spots and events',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                '$totalCount',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final groupEntry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Row(
                children: [
                  Text(
                    groupEntry.key,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${groupEntry.value.length}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            for (
              var index = 0;
              index < groupEntry.value.take(6).length;
              index++
            ) ...[
              UpcomingTemporarySpotNewsCard(spot: groupEntry.value[index]),
              if (index != groupEntry.value.take(6).length - 1)
                const SizedBox(height: 10),
            ],
            if (groupEntry != groups.entries.last) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class UpcomingTemporarySpotNewsCard extends StatelessWidget {
  final CarSpot spot;

  const UpcomingTemporarySpotNewsCard({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          appPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.orangeAccent.withValues(alpha: 0.65),
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orangeAccent.withValues(alpha: 0.16),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                ),
                SpotPhoto(
                  spot: spot,
                  width: 52,
                  height: 52,
                  borderRadius: BorderRadius.circular(14),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.temporaryTodayLabel,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    spot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    spot.cityCountry,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (!spot.isTemporaryLocationAvailableNow) ...[
                    const SizedBox(height: 2),
                    Text(
                      spot.temporaryLocationAvailableAtLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class ExploreCategoryHeader extends StatelessWidget {
  final String category;
  final int count;

  const ExploreCategoryHeader({
    super.key,
    required this.category,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final color = spotColorForCategory(category);

    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 12),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            category,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          '$count',
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class ExploreSpotCard extends StatelessWidget {
  final CarSpot spot;

  const ExploreSpotCard({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    final visibleCategories = <String>{
      for (final category in spot.categories)
        if (category.trim().isNotEmpty) category.trim(),
    }.take(3).toList();

    final tagWidgets = <Widget>[
      if (spot.verifiedOnly)
        _SmallTag(label: 'Verified only', icon: Icons.verified),
      if (spot.isTemporary)
        _SmallTag(
          label: spot.isTemporaryMapVisibleNow
              ? spot.temporaryTodayLabel
              : spot.temporaryTimeLabel,
          icon: Icons.event,
        ),
      for (final category in visibleCategories)
        _SmallTag(label: category, icon: Icons.local_offer),
    ];
    final addedDateText = spot.createdAtMillis > 0
        ? 'Added ${formatShortDate(DateTime.fromMillisecondsSinceEpoch(spot.createdAtMillis))}'
        : 'Added date unknown';
    final categoryColor = spot.isTemporary
        ? Colors.orangeAccent
        : spotColorForSpot(spot);
    final addedByText = spot.addedBy.trim().isEmpty
        ? 'Added by: unknown'
        : 'Added by: ${spot.addedBy}';

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          appPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: categoryColor.withValues(alpha: 0.85),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: categoryColor.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SpotPhoto(
                  spot: spot,
                  width: 118,
                  height: 104,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(12),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              spot.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.star, color: blue, size: 15),
                          const SizedBox(width: 3),
                          Text(
                            spot.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        spot.cityCountry,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule,
                            color: Colors.white38,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              addedDateText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            color: Colors.white38,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              spot.addedByUid.trim().isEmpty
                                  ? addedByText
                                  : 'Added by ${displayUsername(spot.addedBy)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        spot.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ExploreSpotStatsRow(spot: spot),
                const SizedBox(width: 6),
                SaveSpotButton(spot: spot, compact: true),
                const SizedBox(width: 6),
                if (tagWidgets.isNotEmpty)
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: tagWidgets.first,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ExploreSpotStatsRow extends StatelessWidget {
  final CarSpot spot;
  final bool overlay;

  const ExploreSpotStatsRow({
    super.key,
    required this.spot,
    this.overlay = false,
  });

  Widget simpleStat({
    required IconData icon,
    required int count,
    required Color color,
    VoidCallback? onTap,
  }) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: overlay ? 16 : 18),
        const SizedBox(width: 5),
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: overlay ? 12 : 13,
            fontWeight: FontWeight.w900,
            shadows: overlay
                ? const [Shadow(color: Colors.black, blurRadius: 5)]
                : null,
          ),
        ),
      ],
    );

    if (overlay) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: content,
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.42)),
        ),
        child: content,
      ),
    );
  }

  Widget statsDivider() {
    if (overlay) {
      return const SizedBox(width: 5);
    }

    return const SizedBox(width: 7);
  }

  Stream<bool> currentUserCommentedStream() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return Stream.value(false);
    }

    return watchSpotReviews(spot).map(
      (reviews) => reviews.any(
        (review) =>
            review.userId == firebaseUser.uid && review.comment.isNotEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inactiveColor = overlay
        ? Colors.white.withValues(alpha: 0.88)
        : Colors.white70;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder<bool>(
          stream: watchCurrentUserLikedSpot(spot),
          builder: (context, likedSnapshot) {
            final liked = likedSnapshot.data ?? false;

            return StreamBuilder<int>(
              stream: watchSpotLikeCount(spot),
              builder: (context, countSnapshot) {
                final likeCount = countSnapshot.data ?? 0;

                return simpleStat(
                  icon: liked ? Icons.favorite : Icons.favorite_border,
                  count: likeCount,
                  color: liked ? Colors.redAccent : inactiveColor,
                  onTap: () => toggleSpotLike(context, spot, liked),
                );
              },
            );
          },
        ),
        statsDivider(),
        StreamBuilder<bool>(
          stream: currentUserCommentedStream(),
          builder: (context, commentedSnapshot) {
            final commented = commentedSnapshot.data ?? false;

            return StreamBuilder<int>(
              stream: watchSpotCommentCount(spot),
              builder: (context, countSnapshot) {
                final commentCount = countSnapshot.data ?? 0;

                return simpleStat(
                  icon: commented
                      ? Icons.chat_bubble
                      : Icons.chat_bubble_outline,
                  count: commentCount,
                  color: commented ? blue : inactiveColor,
                  onTap: () => showSpotCommentComposer(context, spot),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

Future<void> showSpotCommentComposer(BuildContext context, CarSpot spot) async {
  final messenger = ScaffoldMessenger.maybeOf(context);

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: panelGlass,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) {
      return _SpotCommentComposerSheet(spot: spot, messenger: messenger);
    },
  );
}

class _SpotCommentComposerSheet extends StatefulWidget {
  final CarSpot spot;
  final ScaffoldMessengerState? messenger;

  const _SpotCommentComposerSheet({
    required this.spot,
    required this.messenger,
  });

  @override
  State<_SpotCommentComposerSheet> createState() =>
      _SpotCommentComposerSheetState();
}

class _SpotCommentComposerSheetState extends State<_SpotCommentComposerSheet> {
  late final TextEditingController controller;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void showMessage(SnackBar snackBar) {
    final messenger = widget.messenger;
    if (messenger == null) {
      return;
    }

    messenger.clearSnackBars();
    messenger.showSnackBar(snackBar);
  }

  Future<void> submitComment() async {
    final comment = controller.text.trim();

    if (comment.isEmpty) {
      showMessage(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Write a comment first.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (isSaving) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    if (mounted) {
      setState(() => isSaving = true);
    }

    try {
      await saveSpotReview(spot: widget.spot, comment: comment);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        showMessage(
          const SnackBar(
            backgroundColor: blue,
            content: Text(
              'Comment posted.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      final code = error is FirebaseException ? error.code : error.toString();

      showMessage(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not save comment: $code',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );

      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(18, 14, 18, 18 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Comment ${widget.spot.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: isSaving
                      ? null
                      : () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.of(context).pop();
                        },
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: false,
              minLines: 3,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: trText('Write a comment'),
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: blue),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: isSaving ? null : submitComment,
                icon: Icon(isSaving ? Icons.hourglass_top : Icons.send),
                label: Text(isSaving ? 'Posting...' : 'Post Comment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CurrentUserTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final triangle = ui.Path()
      ..moveTo(centerX, size.height * 0.10)
      ..lineTo(size.width * 0.22, size.height * 0.86)
      ..quadraticBezierTo(
        centerX,
        size.height * 0.72,
        size.width * 0.78,
        size.height * 0.86,
      )
      ..close();

    final shadowPaint = Paint()
      ..color = const Color(0xFF4DDCFF).withValues(alpha: 0.32)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(triangle.shift(const Offset(0, 2)), shadowPaint);

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF9BEFFF), Color(0xFF1AAFFF)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(triangle, fillPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.92);
    canvas.drawPath(triangle, borderPaint);

    final centerPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(Offset(centerX, size.height * 0.51), 3.6, centerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MapScreen extends StatefulWidget {
  final bool isVisible;

  const MapScreen({super.key, required this.isVisible});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  // Default map view: open Riga area first, do not auto-jump to the user.
  static const rigaCenter = LatLng(56.9496, 24.1052);
  static const rigaZoom = 11.25;
  static const fullSpotIconMinZoom = 11.25;
  static const navigationZoom = 16.35;
  static const Duration liveLocationUploadInterval = Duration(seconds: 30);
  static const double liveLocationMinimumUploadDistanceMeters = 0;

  final mapController = MapController();
  late final AnimationController mapAlertPulseController;
  Timer? temporarySpotRefreshTimer;
  Timer? liveLocationUploadTimer;
  Timer? liveLocationPromptTimer;
  Timer? liveLocationAutoStopTimer;
  Timer? navigationPredictionTimer;
  StreamSubscription<Position>? navigationPositionSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  liveLocationSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  policeReportSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  sosReportSubscription;
  Timer? sosDistanceCheckTimer;
  CarSpot? selectedSpot;
  PoliceReportData? selectedPoliceReport;
  SosReportData? selectedSosReport;
  LiveLocationData? selectedLiveLocation;
  LatLng? currentUserLocation;
  LatLng? displayedUserLocation;
  LatLng? lastGpsUserLocation;
  LatLng? lastUploadedLiveLocation;
  DateTime? lastGpsUserLocationAt;
  double currentUserSpeedMetersPerSecond = 0;
  bool isLocatingUser = false;
  bool isAddingPoliceReport = false;
  bool isAddingSosReport = false;
  bool sosConfirmationDialogOpen = false;
  bool isVotingPoliceReport = false;
  bool isSharingLiveLocation = false;
  static const double policeReportVoteRadiusMeters = 300;
  static const double policeReportDuplicateRadiusMeters = 500;
  static const double sosAutoCheckRadiusMeters = 500;
  static const Duration sosNoAnswerAutoRemoveDelay = Duration(minutes: 5);
  static const Duration policeReportCreatorVoteCooldown = Duration(minutes: 15);
  bool isTogglingLiveLocation = false;
  bool liveLocationPromptOpen = false;
  DateTime? liveLocationPromptAt;
  DateTime? liveLocationExpiresAt;
  Duration liveLocationShareDuration = const Duration(hours: 1);
  List<LiveLocationData> liveLocations = [];
  Set<String> friendLiveLocationUids = {};
  List<PoliceReportData> policeReports = [];
  List<SosReportData> sosReports = [];
  LatLng currentMapCenter = rigaCenter;
  double currentMapZoom = rigaZoom;
  double currentMapRotationDegrees = 0;
  double currentUserHeadingDegrees = 0;
  LatLng? previousAcceptedHeadingLocation;
  double smoothedUserHeadingDegrees = 0;
  DateTime? lastNavigationPositionAt;
  bool mapCenteredOnCurrentUser = false;
  bool mapCameraReady = false;
  int? lastHandledMapFocusRequestToken;

  double scaledMapIconValue({
    required double zoom,
    required double minZoom,
    required double maxZoom,
    required double minValue,
    required double maxValue,
  }) {
    if (maxZoom <= minZoom) {
      return maxValue;
    }

    final progress = ((zoom - minZoom) / (maxZoom - minZoom))
        .clamp(0.0, 1.0)
        .toDouble();
    final easedProgress = Curves.easeOutCubic.transform(progress);
    return minValue + (maxValue - minValue) * easedProgress;
  }

  @override
  void initState() {
    super.initState();
    mapAlertPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    reviewSpots.addListener(refreshMap);
    spotCategoryFilters.addListener(refreshMap);
    mapFocusRequest.addListener(handleMapFocusRequest);

    // Temporary spots can become visible or expire just because time passes.
    // Firestore will not send a new snapshot at the start/end time, so the map
    // needs a small live refresh while this screen is open.
    temporarySpotRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => refreshMap(),
    );
    startLiveLocationSync();
    loadFriendLiveLocationUids();
    startPoliceReportSync();
    startSosReportSync();
    sosDistanceCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => checkOwnSosDistance(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isVisible) {
        return;
      }

      mapCameraReady = true;
      restoreMapCamera();
      handleMapFocusRequest();
    });
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isVisible == widget.isVisible) {
      return;
    }

    if (!widget.isVisible) {
      mapCameraReady = false;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isVisible) {
        return;
      }

      mapCameraReady = true;
      restoreMapCamera();
      handleMapFocusRequest();
    });
  }

  void refreshMap() {
    if (!mounted) {
      return;
    }

    setState(() {
      final spot = selectedSpot;
      final policeReport = selectedPoliceReport;
      final sosReport = selectedSosReport;
      final liveLocation = selectedLiveLocation;

      if (spot != null &&
          (!spot.isVisibleOnMapNow ||
              !spot.categories.any(spotCategoryFilters.value.contains))) {
        selectedSpot = null;
      }

      if (policeReport != null && !policeReport.isActive) {
        selectedPoliceReport = null;
      }

      if (sosReport != null && !sosReport.isActive) {
        selectedSosReport = null;
      }

      if (liveLocation != null && liveLocation.isExpired) {
        selectedLiveLocation = null;
      }
    });
  }

  double get currentMapLoadRadiusMeters {
    if (currentMapZoom >= 14) return 24000;
    if (currentMapZoom >= 12) return 42000;
    if (currentMapZoom >= 10) return 72000;
    return 120000;
  }

  int get currentMapMarkerLimit {
    if (currentMapZoom >= 14) return 420;
    if (currentMapZoom >= 12) return 260;
    if (currentMapZoom >= 10) return 160;
    return 90;
  }

  List<CarSpot> get visibleSpots {
    final enabledCategoryFilters = spotCategoryFilters.value;

    if (enabledCategoryFilters.isEmpty) {
      return const [];
    }

    final candidates = <MapEntry<CarSpot, double>>[];
    for (final spot in approvedPublicSpots()) {
      if (spot.status != SpotStatus.approved ||
          !spot.categories.any(enabledCategoryFilters.contains) ||
          !spot.isVisibleOnMapNow) {
        continue;
      }

      final distance = distanceBetweenLatLngMeters(
        currentMapCenter,
        spot.coordinates,
      );
      if (distance <= currentMapLoadRadiusMeters) {
        candidates.add(MapEntry(spot, distance));
      }
    }

    final visibleTemporarySpots = candidates
        .map((entry) => entry.key)
        .where((spot) => spot.isTemporary && spot.isTemporaryMapVisibleNow)
        .toList();

    final withPermanentSpotsSuppressed = candidates.where((entry) {
      final spot = entry.key;
      if (spot.isTemporary) {
        return true;
      }

      return !visibleTemporarySpots.any(
        (temporarySpot) =>
            distanceBetweenLatLngMeters(
              spot.coordinates,
              temporarySpot.coordinates,
            ) <=
            temporarySpotHidePermanentRadiusMeters,
      );
    }).toList();

    withPermanentSpotsSuppressed.sort((a, b) {
      final aTemporary = a.key.isTemporary && a.key.isTemporaryMapVisibleNow;
      final bTemporary = b.key.isTemporary && b.key.isTemporaryMapVisibleNow;

      if (aTemporary != bTemporary) {
        return aTemporary ? -1 : 1;
      }

      return a.value.compareTo(b.value);
    });

    return withPermanentSpotsSuppressed
        .take(currentMapMarkerLimit)
        .map((entry) => entry.key)
        .toList();
  }

  Future<void> showMapCategoryFilterSheet() async {
    final nextEnabledCategories = Set<String>.from(spotCategoryFilters.value);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: panelGlass,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final selectedCount = nextEnabledCategories.length;

            void selectAll() {
              setSheetState(() {
                nextEnabledCategories
                  ..clear()
                  ..addAll(spotCategoryOptions);
              });
            }

            void clearAll() {
              setSheetState(nextEnabledCategories.clear);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Map filters',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectedCount == spotCategoryOptions.length
                          ? 'All categories enabled'
                          : '$selectedCount of ${spotCategoryOptions.length} categories enabled',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: selectAll,
                          icon: const Icon(Icons.done_all),
                          label: const Text('Select all'),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: clearAll,
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final category in spotCategoryOptions)
                              CheckboxListTile(
                                value: nextEnabledCategories.contains(category),
                                onChanged: (enabled) {
                                  setSheetState(() {
                                    if (enabled == true) {
                                      nextEnabledCategories.add(category);
                                    } else {
                                      nextEnabledCategories.remove(category);
                                    }
                                  });
                                },
                                dense: true,
                                activeColor: spotColorForCategory(category),
                                checkColor: Colors.black,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: spotColorForCategory(category),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      category,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          updateSpotCategoryFilters(nextEnabledCategories);
                          setState(() {
                            selectedSpot = null;
                            selectedLiveLocation = null;
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: const Icon(Icons.tune),
                        label: const Text(
                          'Apply filters',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Marker> get markers {
    final showFullIcons = currentMapZoom >= fullSpotIconMinZoom;
    final compactZoomProgress =
        ((currentMapZoom - 3) / (fullSpotIconMinZoom - 3))
            .clamp(0.0, 1.0)
            .toDouble();
    final compactMarkerSize =
        4.0 + (13.0 - 4.0) * math.pow(compactZoomProgress, 2.7);
    final fullMarkerSize = scaledMapIconValue(
      zoom: currentMapZoom,
      minZoom: fullSpotIconMinZoom.toDouble(),
      maxZoom: 16,
      minValue: 46,
      maxValue: 70,
    );
    final fullMarkerWidth = scaledMapIconValue(
      zoom: currentMapZoom,
      minZoom: fullSpotIconMinZoom.toDouble(),
      maxZoom: 16,
      minValue: 96,
      maxValue: 122,
    );
    final fullMarkerHeight = scaledMapIconValue(
      zoom: currentMapZoom,
      minZoom: fullSpotIconMinZoom.toDouble(),
      maxZoom: 16,
      minValue: 84,
      maxValue: 112,
    );
    final labelFontSize = scaledMapIconValue(
      zoom: currentMapZoom,
      minZoom: fullSpotIconMinZoom.toDouble(),
      maxZoom: 16,
      minValue: 8.2,
      maxValue: 10,
    );
    final spotNameLabelOpacity = scaledMapIconValue(
      zoom: currentMapZoom,
      minZoom: fullSpotIconMinZoom.toDouble() + 1.1,
      maxZoom: fullSpotIconMinZoom.toDouble() + 3.0,
      minValue: 0,
      maxValue: 1,
    ).clamp(0.0, 1.0).toDouble();

    return visibleSpots.map((spot) {
      final closedNow = spotIsClosedNow(spot);
      final isTemporaryActive = spot.isTemporaryActiveNow;
      final isTemporaryUpcoming = spot.isTemporaryUpcomingOnMap;
      final markerColor = closedNow && !isTemporaryActive
          ? Colors.grey.shade500
          : isTemporaryActive || isTemporaryUpcoming
          ? Colors.orangeAccent
          : spotColorForSpot(spot);
      final baseMarkerSize = showFullIcons ? fullMarkerSize : compactMarkerSize;
      final markerVisualSize = isTemporaryActive || isTemporaryUpcoming
          ? baseMarkerSize * (showFullIcons ? 1.16 : 1.04)
          : baseMarkerSize;
      final compactMarkerPadding = showFullIcons
          ? 0.0
          : spot.isTemporary
          ? math.max(2.4, markerVisualSize * (isTemporaryActive ? 0.54 : 0.38))
          : math.max(1.4, markerVisualSize * 0.26);
      final markerWidth = showFullIcons
          ? fullMarkerWidth + (spot.isTemporary ? 30 : 0)
          : math.max(
              44.0,
              markerVisualSize + (spot.isTemporary ? compactMarkerPadding : 8),
            );
      final markerHeight = showFullIcons
          ? fullMarkerHeight +
                (isTemporaryUpcoming
                    ? 34
                    : isTemporaryActive
                    ? 24
                    : 0)
          : math.max(
              44.0,
              markerVisualSize + (spot.isTemporary ? compactMarkerPadding : 8),
            );
      final markerOpacity = isTemporaryUpcoming || closedNow ? 0.58 : 1.0;
      final iconTopPadding = math.max(
        0.0,
        (markerHeight - markerVisualSize) / 2,
      );
      final mapNameLabelTop = math.max(0.0, iconTopPadding - labelFontSize - 3);
      final mapStartLabelBottom = math.max(0.0, iconTopPadding - 14);

      Widget iconWidget() {
        final asset = spotIconAssetPathForSpot(spot);
        final image = Image.asset(
          asset,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return CompactSpotMapPoint(
              color: markerColor,
              faded: isTemporaryUpcoming || closedNow,
              event: isTemporaryActive || isTemporaryUpcoming,
            );
          },
        );

        final icon = SizedBox(
          width: markerVisualSize,
          height: markerVisualSize,
          child: closedNow || isTemporaryUpcoming
              ? Opacity(
                  opacity: markerOpacity,
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      markerColor,
                      BlendMode.srcATop,
                    ),
                    child: image,
                  ),
                )
              : image,
        );

        Widget withVerifiedBadge(Widget child) {
          if (!spot.verifiedOnly) {
            return child;
          }

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              child,
              Positioned(
                right: -2,
                top: -2,
                child: _VerifiedSpotBadge(
                  size: markerVisualSize.clamp(13.0, 18.0).toDouble(),
                ),
              ),
            ],
          );
        }

        if (!isTemporaryActive) {
          return withVerifiedBadge(icon);
        }

        return withVerifiedBadge(
          PulsingTemporarySpotIconGlow(size: markerVisualSize, child: icon),
        );
      }

      Widget fullMarker() {
        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: mapNameLabelTop,
              left: 2,
              right: 2,
              child: IgnorePointer(
                child: Opacity(
                  opacity: spotNameLabelOpacity,
                  child: Text(
                    spot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: closedNow || isTemporaryUpcoming
                          ? Colors.white.withValues(alpha: 0.46)
                          : Colors.white.withValues(alpha: 0.74),
                      fontSize: labelFontSize,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 5),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            iconWidget(),
            if (isTemporaryActive)
              Positioned(
                right: 2,
                top: iconTopPadding + markerVisualSize * 0.28,
                child: const _TemporaryMapBadge(),
              ),
            if (isTemporaryUpcoming)
              Positioned(
                left: 2,
                right: 2,
                bottom: mapStartLabelBottom,
                child: IgnorePointer(
                  child: Text(
                    spot.temporaryStartingAtLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                    ),
                  ),
                ),
              ),
          ],
        );
      }

      Widget compactMarker() {
        final point = CompactSpotMapPoint(
          color: markerColor,
          size: markerVisualSize,
          faded: isTemporaryUpcoming || closedNow,
          event: isTemporaryActive || isTemporaryUpcoming,
        );

        Widget marker = point;

        if (isTemporaryActive) {
          marker = PulsingTemporarySpotIconGlow(
            size: markerVisualSize,
            compact: true,
            child: point,
          );
        }

        return marker;
      }

      return Marker(
        point: spot.coordinates,
        width: markerWidth,
        height: markerHeight,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            setState(() {
              selectedSpot = spot;
              selectedPoliceReport = null;
              selectedSosReport = null;
              selectedLiveLocation = null;
            });
          },
          child: showFullIcons ? fullMarker() : compactMarker(),
        ),
      );
    }).toList();
  }

  List<Marker> get allMapMarkers {
    final allMarkers = [
      ...markers,
      ...policeReportMarkers,
      ...sosReportMarkers,
      ...liveLocationMarkers,
    ];
    final userMarker = currentUserMarker;

    if (userMarker != null) {
      allMarkers.add(userMarker);
    }

    return allMarkers.where((marker) => isValidLatLng(marker.point)).toList();
  }

  List<PoliceReportData> get visiblePoliceReports {
    return policeReports.where((report) => report.isActive).toList();
  }

  List<Marker> get policeReportMarkers {
    final showPoliceRadius = currentMapZoom >= 14.2;
    final markerOuterSize = showPoliceRadius
        ? scaledMapIconValue(
            zoom: currentMapZoom,
            minZoom: 14.2,
            maxZoom: 17,
            minValue: 42,
            maxValue: 74,
          )
        : scaledMapIconValue(
            zoom: currentMapZoom,
            minZoom: 4,
            maxZoom: 14.2,
            minValue: 13,
            maxValue: 22,
          );
    final markerInnerSize = showPoliceRadius
        ? 34.0
        : math.max(9.0, markerOuterSize - 8);
    return visiblePoliceReports.map((report) {
      return Marker(
        point: report.coordinates,
        width: markerOuterSize,
        height: markerOuterSize,
        child: GestureDetector(
          onTap: () {
            setState(() {
              selectedPoliceReport = report;
              selectedSpot = null;
              selectedSosReport = null;
              selectedLiveLocation = null;
            });
          },
          child: Tooltip(
            message: 'Police marked by ${displayUsername(report.username)}',
            child: AnimatedBuilder(
              animation: mapAlertPulseController,
              builder: (context, child) {
                final progress = Curves.easeInOut.transform(
                  mapAlertPulseController.value,
                );
                final color = policeAlertColor(progress);
                return Container(
                  decoration: BoxDecoration(
                    color: color.withValues(
                      alpha: showPoliceRadius ? 0.14 : 0.90,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(
                        alpha: showPoliceRadius ? 0.72 : 1,
                      ),
                      width: showPoliceRadius ? 2 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.32),
                        blurRadius: showPoliceRadius ? 18 : 9,
                        spreadRadius: showPoliceRadius ? 3 : 1,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: markerInnerSize,
                      height: markerInnerSize,
                      decoration: BoxDecoration(
                        color: showPoliceRadius ? panelGlass : color,
                        shape: BoxShape.circle,
                        border: showPoliceRadius
                            ? Border.all(color: color, width: 2)
                            : null,
                      ),
                      child: showPoliceRadius
                          ? Icon(Icons.local_police, color: color, size: 21)
                          : const SizedBox.shrink(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }).toList();
  }

  List<SosReportData> get visibleSosReports {
    return sosReports.where((report) => report.isActive).toList();
  }

  List<Marker> get sosReportMarkers {
    final showSosRadius = currentMapZoom >= 14.2;
    final markerOuterSize = showSosRadius
        ? scaledMapIconValue(
            zoom: currentMapZoom,
            minZoom: 14.2,
            maxZoom: 17,
            minValue: 46,
            maxValue: 82,
          )
        : scaledMapIconValue(
            zoom: currentMapZoom,
            minZoom: 4,
            maxZoom: 14.2,
            minValue: 15,
            maxValue: 26,
          );
    final markerInnerSize = showSosRadius
        ? 38.0
        : math.max(10.0, markerOuterSize - 8);
    return visibleSosReports.map((report) {
      return Marker(
        point: report.coordinates,
        width: markerOuterSize,
        height: markerOuterSize,
        child: GestureDetector(
          onTap: () {
            setState(() {
              selectedSosReport = report;
              selectedSpot = null;
              selectedPoliceReport = null;
              selectedLiveLocation = null;
            });
          },
          child: Tooltip(
            message: 'SOS by ${displayUsername(report.username)}',
            child: AnimatedBuilder(
              animation: mapAlertPulseController,
              builder: (context, child) {
                final pulse = Curves.easeInOut.transform(
                  mapAlertPulseController.value,
                );
                final alpha = showSosRadius
                    ? 0.18 + pulse * 0.12
                    : 0.82 + pulse * 0.14;
                return Container(
                  decoration: BoxDecoration(
                    color: sosAlertColor.withValues(alpha: alpha),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: sosAlertColor.withValues(
                        alpha: 0.82 + pulse * 0.18,
                      ),
                      width: showSosRadius ? 2.2 : 1.6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: sosAlertColor.withValues(
                          alpha: 0.34 + pulse * 0.22,
                        ),
                        blurRadius: showSosRadius
                            ? 16 + pulse * 10
                            : 9 + pulse * 5,
                        spreadRadius: showSosRadius
                            ? 2 + pulse * 4
                            : 1 + pulse * 1.5,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: markerInnerSize,
                      height: markerInnerSize,
                      decoration: BoxDecoration(
                        color: showSosRadius ? panelGlass : sosAlertColor,
                        shape: BoxShape.circle,
                        border: showSosRadius
                            ? Border.all(color: sosAlertColor, width: 2)
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          showSosRadius ? 'SOS' : '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }).toList();
  }

  Future<void> loadFriendLiveLocationUids() async {
    try {
      final friendUids = await loadCurrentFriendUids();

      if (!mounted) {
        return;
      }

      setState(() => friendLiveLocationUids = friendUids.toSet());
    } catch (_) {
      // Friend icon highlighting is best-effort.
    }
  }

  bool liveLocationIsFriend(LiveLocationData location) {
    return friendLiveLocationUids.contains(location.uid);
  }

  String liveLocationCarIconAsset(LiveLocationData location) {
    if (liveLocationIsFriend(location)) {
      return friendUserCarIconAsset;
    }

    if (location.verified) {
      return verifiedUserCarIconAsset;
    }

    return regularUserCarIconAsset;
  }

  String liveLocationTooltipMessage(LiveLocationData location) {
    if (liveLocationIsFriend(location)) {
      return '${displayUsername(location.username)} is your friend and is sharing live location';
    }

    if (location.verified) {
      return '${displayUsername(location.username)} is verified and is sharing live location';
    }

    return '${displayUsername(location.username)} is sharing live location';
  }

  List<Marker> get liveLocationMarkers {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    return liveLocations
        .where((location) => !location.isExpired)
        .where((location) => location.uid != firebaseUser?.uid)
        .map((location) {
          final carIconSize = scaledMapIconValue(
            zoom: currentMapZoom,
            minZoom: 4,
            maxZoom: 17,
            minValue: 9,
            maxValue: 34,
          );
          final labelWidth = scaledMapIconValue(
            zoom: currentMapZoom,
            minZoom: 4,
            maxZoom: 17,
            minValue: 58,
            maxValue: 82,
          );
          final labelFontSize = scaledMapIconValue(
            zoom: currentMapZoom,
            minZoom: 4,
            maxZoom: 17,
            minValue: 7.8,
            maxValue: 10.5,
          );
          final userNameLabelOpacity = scaledMapIconValue(
            zoom: currentMapZoom,
            minZoom: 10.8,
            maxZoom: 14.2,
            minValue: 0,
            maxValue: 1,
          ).clamp(0.0, 1.0).toDouble();
          final markerHeight = carIconSize + 36;
          final iconAsset = liveLocationCarIconAsset(location);
          final fallbackColor = liveLocationIsFriend(location)
              ? Colors.purpleAccent
              : location.verified
              ? Colors.greenAccent
              : blue;

          return Marker(
            point: location.coordinates,
            width: labelWidth,
            height: markerHeight,
            rotate: false,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  selectedLiveLocation = location;
                  selectedSpot = null;
                  selectedPoliceReport = null;
                  selectedSosReport = null;
                });
              },
              child: Tooltip(
                message: liveLocationTooltipMessage(location),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 0,
                      left: 2,
                      right: 2,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: userNameLabelOpacity,
                          child: Text(
                            displayUsername(location.username),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.74),
                              fontSize: labelFontSize,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              shadows: const [
                                Shadow(color: Colors.black, blurRadius: 5),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: SizedBox(
                        width: carIconSize,
                        height: carIconSize,
                        child: Transform.rotate(
                          angle: headingRadiansForMap(
                            location.headingDegrees,
                            currentMapRotationDegrees,
                          ),
                          child: Image.asset(
                            iconAsset,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.directions_car,
                                color: fallbackColor,
                                size: carIconSize * 0.82,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        })
        .toList();
  }

  Marker? get currentUserMarker {
    final location = displayedUserLocation ?? currentUserLocation;

    if (location == null) {
      return null;
    }

    return Marker(
      point: location,
      width: 42,
      height: 42,
      rotate: false,
      child: Tooltip(
        message: 'Your location',
        child: Transform.rotate(
          angle: headingRadiansForMap(
            currentUserHeadingDegrees,
            currentMapRotationDegrees,
          ),
          child: CustomPaint(
            painter: CurrentUserTrianglePainter(),
            child: const SizedBox(width: 42, height: 42),
          ),
        ),
      ),
    );
  }

  void moveMapCamera(
    LatLng location,
    double zoom, {
    double? rotationDegrees,
  }) {
    if (!isValidLatLng(location) || !zoom.isFinite) {
      return;
    }

    final safeZoom = zoom.clamp(4.0, 18.0).toDouble();
    final safeRotation = normalizedHeadingDegrees(
      rotationDegrees ?? currentMapRotationDegrees,
    );

    currentMapCenter = location;
    currentMapZoom = safeZoom;
    currentMapRotationDegrees = safeRotation;

    if (!widget.isVisible || !mapCameraReady) {
      return;
    }

    mapController.moveAndRotate(location, safeZoom, safeRotation);
  }

  void restoreMapCamera() {
    moveMapCamera(
      isValidLatLng(currentMapCenter) ? currentMapCenter : rigaCenter,
      currentMapZoom.isFinite ? currentMapZoom : rigaZoom,
      rotationDegrees: currentMapRotationDegrees,
    );
  }

  void handleMapFocusRequest() {
    final request = mapFocusRequest.value;

    if (request == null || request.token == lastHandledMapFocusRequestToken) {
      return;
    }

    lastHandledMapFocusRequestToken = request.token;
    CarSpot? matchingSpot;
    for (final spot in approvedPublicSpots()) {
      if (spot.id == request.spotId) {
        matchingSpot = spot;
        break;
      }
    }

    if (mounted) {
      setState(() {
        selectedSpot = matchingSpot;
        selectedPoliceReport = null;
        selectedSosReport = null;
        selectedLiveLocation = null;
        mapCenteredOnCurrentUser = false;
        currentMapZoom = 16.4;
      });
    }

    moveMapCamera(
      request.coordinates,
      16.4,
      rotationDegrees: currentMapRotationDegrees,
    );
  }

  void startPoliceReportSync() {
    policeReportSubscription?.cancel();
    policeReportSubscription = policeReportsCollection()
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) {
              return;
            }

            final reports = snapshot.docs
                .map((doc) => PoliceReportData.fromFirestore(doc))
                .where((report) => report.isActive)
                .toList();

            setState(() {
              policeReports = reports;

              final selected = selectedPoliceReport;
              if (selected != null) {
                final stillVisible = reports.any(
                  (report) => report.id == selected.id,
                );
                if (!stillVisible) {
                  selectedPoliceReport = null;
                }
              }
            });
          },
          onError: (_) {
            // Firestore rules may still be closed while this feature is being set up.
          },
        );
  }

  void startSosReportSync() {
    sosReportSubscription?.cancel();
    sosReportSubscription = sosReportsCollection()
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) {
              return;
            }

            final reports = snapshot.docs
                .map((doc) => SosReportData.fromFirestore(doc))
                .where((report) => report.isActive)
                .toList();

            setState(() {
              sosReports = reports;

              final selected = selectedSosReport;
              if (selected != null) {
                final stillVisible = reports.any(
                  (report) => report.id == selected.id,
                );
                if (!stillVisible) {
                  selectedSosReport = null;
                }
              }
            });
          },
          onError: (_) {
            // Firestore rules may still be closed while this feature is being set up.
          },
        );
  }

  Future<SosRequestDraft?> showSosDescriptionDialog() async {
    String selectedReason = 'battery';
    String description = '';
    String? validationError;

    return showDialog<SosRequestDraft>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: panelGlass,
              title: Text(
                trText('Need help'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trText('Choose SOS reason'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Column(
                      children: sosReasonLabels.entries.map((entry) {
                        final selected = selectedReason == entry.key;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              setDialogState(() {
                                selectedReason = entry.key;
                                validationError = null;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: double.infinity,
                              constraints: const BoxConstraints(minHeight: 42),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? sosAlertColor
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? sosAlertColor
                                      : Colors.white12,
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 18,
                                    child: selected
                                        ? const Icon(
                                            Icons.check,
                                            size: 16,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      trText(entry.value),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : Colors.white70,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      autofocus: false,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 220,
                      style: const TextStyle(color: Colors.white),
                      onChanged: (value) {
                        description = value;
                        if (validationError != null) {
                          setDialogState(() => validationError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: trText('What happened?'),
                        hintText: trText(
                          'Describe what happened and what help you need.',
                        ),
                        errorText: validationError == null
                            ? null
                            : trText(validationError!),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(trText('Cancel')),
                ),
                ElevatedButton(
                  onPressed: () {
                    final cleanDescription = description.trim();
                    if (sosDescriptionLooksLikeSpam(cleanDescription)) {
                      setDialogState(() {
                        validationError =
                            'Description looks like spam. Please write clearly what happened.';
                      });
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      SosRequestDraft(
                        reason: selectedReason,
                        description: cleanDescription,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: sosAlertColor,
                  ),
                  child: Text(
                    trText('Create SOS'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<String>> loadSosVisibleUserIds(String fallbackUid) async {
    try {
      final snapshot = await usersCollection().limit(500).get();
      final ids = snapshot.docs
          .map((doc) => stringFromFirebase(doc.data()['uid'], doc.id))
          .where((uid) => uid.trim().isNotEmpty)
          .toList();
      return uniqueNonEmptyStrings([fallbackUid, ...ids]);
    } catch (_) {
      return uniqueNonEmptyStrings([fallbackUid]);
    }
  }

  Future<void> startSosLiveLocationSharing(Position position) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return;
    }

    final now = DateTime.now();
    const shareDuration = Duration(hours: 12);
    final promptAt = now.add(shareDuration);
    final expiresAt = promptAt.add(liveLocationRenewGracePeriod);
    final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }
    final speed = position.speed.isFinite ? math.max(0.0, position.speed) : 0.0;
    final heading = headingForNewUserLocation(
      location,
      position.heading,
      speedMetersPerSecond: speed,
    );
    final visibleToUserIds = await loadSosVisibleUserIds(firebaseUser.uid);

    liveLocationShareDuration = shareDuration;
    liveLocationPromptAt = promptAt;
    liveLocationExpiresAt = expiresAt;

    await liveLocationsCollection().doc(firebaseUser.uid).set({
      'uid': firebaseUser.uid,
      'username': currentUser.username,
      'name': currentUser.name,
      'photoUrl': currentUser.photoUrl,
      'role': roleName(currentUser.role),
      'verified': currentUser.verified,
      'heading': normalizedHeadingDegrees(
        heading,
        fallback: currentUserHeadingDegrees,
      ),
      'lat': position.latitude,
      'lng': position.longitude,
      'coordinates': GeoPoint(position.latitude, position.longitude),
      'visibleToUserIds': visibleToUserIds,
      'visibleToChatId': '',
      'visibleToChatName': '',
      'shareScope': 'sos',
      'shareDurationMinutes': shareDuration.inMinutes,
      'promptAt': Timestamp.fromDate(promptAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    try {
      await usersCollection().doc(firebaseUser.uid).set({
        'isSharingLiveLocation': true,
        'liveLocationExpiresAt': Timestamp.fromDate(expiresAt),
        'liveLocationVisibleToUserIds': visibleToUserIds,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'isOnline': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error, stack) {
      debugPrint('SOS user live-location flag update failed: $error');
      debugPrint('$stack');
    }

    if (!mounted) {
      return;
    }

    setState(() {
      currentUserLocation = location;
      displayedUserLocation = location;
      lastGpsUserLocation = location;
      lastUploadedLiveLocation = location;
      lastGpsUserLocationAt = DateTime.now();
      currentUserHeadingDegrees = heading;
      currentUserSpeedMetersPerSecond = speed;
      isSharingLiveLocation = true;
    });

    scheduleLiveLocationTimers();
    startNavigationTracking();
    updateFollowCamera(location, heading);

    final prompt = liveLocationPromptAt;
    final expiry = liveLocationExpiresAt;
    if (prompt != null && expiry != null) {
      unawaited(
        startNativeLiveLocationBackgroundService(
          uid: firebaseUser.uid,
          visibleToUserIds: visibleToUserIds,
          shareScope: 'sos',
          promptAt: prompt,
          expiresAt: expiry,
        ),
      );
    }

    liveLocationUploadTimer?.cancel();
    liveLocationUploadTimer = null;
    ensureLiveLocationUploadLoop();
  }

  Future<void> addSosReportAtCurrentLocation() async {
    if (isAddingSosReport) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Log in before sharing your location.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final activeOwnSos = sosReports.any(
      (report) => report.uid == firebaseUser.uid && report.isActive,
    );
    if (activeOwnSos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: panelGlass,
          content: Text(
            trText('Only one active SOS is allowed.'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      return;
    }

    try {
      final existingOwnSos = await sosReportsCollection()
          .where('uid', isEqualTo: firebaseUser.uid)
          .where('status', isEqualTo: 'active')
          .where('expiresAt', isGreaterThan: Timestamp.now())
          .limit(1)
          .get();
      if (existingOwnSos.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: panelGlass,
              content: Text(
                trText('Close your current SOS before creating a new one.'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
        return;
      }
    } catch (_) {
      // Local check above still protects beta builds while rules/indexes are being updated.
    }

    final draft = await showSosDescriptionDialog();
    if (draft == null || draft.description.isEmpty) {
      return;
    }

    setState(() => isAddingSosReport = true);

    final position = await getMapUserPosition(showErrors: true);

    if (!mounted) {
      return;
    }

    if (position == null) {
      setState(() => isAddingSosReport = false);
      return;
    }

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 12));
    final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }
    final docRef = sosReportsCollection().doc(firebaseUser.uid);

    try {
      await docRef.set({
        'uid': firebaseUser.uid,
        'username': currentUser.username,
        'description': draft.description,
        'reason': draft.reason,
        'lat': position.latitude,
        'lng': position.longitude,
        'coordinates': GeoPoint(position.latitude, position.longitude),
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'updatedAt': FieldValue.serverTimestamp(),
        'confirmationRequestedAt': null,
        'status': 'active',
      });
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() => isAddingSosReport = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              error.code == 'permission-denied'
                  ? trText(
                      'Close the current SOS or wait one minute before creating another one.',
                    )
                  : 'Could not create SOS: ${error.message ?? error.code}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      return;
    }

    try {
      await startSosLiveLocationSharing(position);
    } catch (error, stack) {
      debugPrint('SOS live location start failed: $error');
      debugPrint('$stack');
    }

    if (!mounted) {
      return;
    }

    final newReport = SosReportData(
      id: docRef.id,
      uid: firebaseUser.uid,
      username: currentUser.username,
      description: draft.description,
      reason: draft.reason,
      coordinates: location,
      createdAtMillis: now.millisecondsSinceEpoch,
      expiresAtMillis: expiresAt.millisecondsSinceEpoch,
      updatedAtMillis: now.millisecondsSinceEpoch,
    );

    setState(() {
      currentUserLocation = location;
      selectedSpot = null;
      selectedPoliceReport = null;
      selectedSosReport = newReport;
      selectedLiveLocation = null;
      isAddingSosReport = false;
    });

    moveMapCamera(location, 15.5);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: panelGlass,
        content: Text(
          trText('SOS added on the map.'),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> removeSosReport(SosReportData report) async {
    await sosReportsCollection().doc(report.id).set({
      'status': 'removed',
      'removedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) {
      return;
    }

    setState(() {
      selectedSosReport = null;
      sosReports = sosReports.where((item) => item.id != report.id).toList();
    });
  }

  Future<void> checkOwnSosDistance() async {
    if (!mounted || sosConfirmationDialogOpen) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      return;
    }

    SosReportData? ownSos;
    for (final report in sosReports) {
      if (report.uid == firebaseUser.uid && report.isActive) {
        ownSos = report;
        break;
      }
    }

    if (ownSos == null) {
      return;
    }

    final position = await getMapUserPosition(showErrors: false);
    if (!mounted || position == null) {
      return;
    }

    final freshLocation = safeLatLngFromPosition(position);
    if (freshLocation == null) {
      return;
    }
    final distance = distanceBetweenLatLngMeters(
      freshLocation,
      ownSos.coordinates,
    );

    setState(() => currentUserLocation = freshLocation);

    if (distance <= sosAutoCheckRadiusMeters) {
      return;
    }

    final requestedAt = ownSos.confirmationRequestedAtMillis;
    final now = DateTime.now();
    if (requestedAt > 0) {
      final requestedAtDate = DateTime.fromMillisecondsSinceEpoch(requestedAt);
      if (now.difference(requestedAtDate) >= sosNoAnswerAutoRemoveDelay) {
        await removeSosReport(ownSos);
      }
      return;
    }

    await sosReportsCollection().doc(ownSos.id).set({
      'confirmationRequestedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    sosConfirmationDialogOpen = true;
    final keep = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: const Text(
            'Still need help?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'You moved away from your SOS point. Do you still need help there?',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(trText('No, remove')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(backgroundColor: sosAlertColor),
              child: const Text(
                'Yes, still need',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    ).timeout(sosNoAnswerAutoRemoveDelay, onTimeout: () => false);

    sosConfirmationDialogOpen = false;

    if (!mounted) {
      return;
    }

    if (keep == true) {
      await sosReportsCollection().doc(ownSos.id).set({
        'confirmationRequestedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await removeSosReport(ownSos);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: panelGlass,
          content: Text(
            trText('SOS removed from the map.'),
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
  }

  Future<void> showAddMapReportSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: panelGlass,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add map alert',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: AnimatedBuilder(
                    animation: mapAlertPulseController,
                    builder: (context, child) {
                      final pulse = Curves.easeInOut.transform(
                        mapAlertPulseController.value,
                      );
                      final color = policeAlertColor(pulse);
                      return Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: color.withValues(alpha: 0.72),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.32),
                              blurRadius: 9,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Icon(Icons.local_police, color: color),
                      );
                    },
                  ),
                  title: const Text(
                    'Police',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: const Text(
                    'Mark police at your current location for 2 hours.',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(context, 'police'),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: AnimatedBuilder(
                    animation: mapAlertPulseController,
                    builder: (context, child) {
                      final pulse = Curves.easeInOut.transform(
                        mapAlertPulseController.value,
                      );
                      return Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: sosAlertColor.withValues(
                            alpha: 0.18 + pulse * 0.12,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: sosAlertColor.withValues(
                              alpha: 0.82 + pulse * 0.18,
                            ),
                            width: 1.6,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: sosAlertColor.withValues(
                                alpha: 0.34 + pulse * 0.22,
                              ),
                              blurRadius: 9 + pulse * 5,
                              spreadRadius: 1 + pulse * 1.5,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'SOS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  title: const Text(
                    'SOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: const Text(
                    'Ask nearby drivers for help.',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(context, 'sos'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == 'police') {
      await addPoliceReportAtCurrentLocation();
    } else if (selected == 'sos') {
      await addSosReportAtCurrentLocation();
    }
  }

  double? policeReportDistanceMeters(PoliceReportData report) {
    final location = currentUserLocation;

    if (location == null) {
      return null;
    }

    return const Distance().as(LengthUnit.Meter, location, report.coordinates);
  }

  bool isPoliceReportCreatorCooldownOver(PoliceReportData report) {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      report.createdAtMillis,
    );

    return DateTime.now().difference(createdAt) >=
        policeReportCreatorVoteCooldown;
  }

  bool canVotePoliceReportFromCurrentMapLocation(PoliceReportData report) {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return false;
    }

    final distance = policeReportDistanceMeters(report);

    if (distance == null || distance > policeReportVoteRadiusMeters) {
      return false;
    }

    if (report.uid == firebaseUser.uid &&
        !isPoliceReportCreatorCooldownOver(report)) {
      return false;
    }

    return true;
  }

  String policeReportVoteHint(PoliceReportData report) {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return 'Log in to confirm this police mark.';
    }

    final distance = policeReportDistanceMeters(report);

    if (distance == null) {
      return 'Move to your current location before confirming this mark.';
    }

    if (distance > policeReportVoteRadiusMeters) {
      return 'Get closer to confirm this police mark.';
    }

    if (report.uid == firebaseUser.uid &&
        !isPoliceReportCreatorCooldownOver(report)) {
      return 'You created this mark. You can confirm it later if you drive by this spot again.';
    }

    return '';
  }

  Future<void> addPoliceReportAtCurrentLocation() async {
    if (isAddingPoliceReport) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Log in before adding a police mark.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    setState(() => isAddingPoliceReport = true);

    final position = await getMapUserPosition(showErrors: true);

    if (!mounted) {
      return;
    }

    if (position == null) {
      setState(() => isAddingPoliceReport = false);
      return;
    }

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 2));
    final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }

    for (final report in visiblePoliceReports) {
      final distance = distanceBetweenLatLngMeters(
        location,
        report.coordinates,
      );
      if (distance <= policeReportDuplicateRadiusMeters) {
        setState(() => isAddingPoliceReport = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: panelGlass,
            content: Text(
              trText('In this area police is already marked.'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        setState(() {
          selectedSpot = null;
          selectedPoliceReport = report;
          selectedSosReport = null;
          selectedLiveLocation = null;
        });
        moveMapCamera(report.coordinates, 15.5);
        return;
      }
    }

    try {
      final activePoliceSnapshot = await policeReportsCollection()
          .where('expiresAt', isGreaterThan: Timestamp.now())
          .where('status', isEqualTo: 'active')
          .get();
      for (final doc in activePoliceSnapshot.docs) {
        final report = PoliceReportData.fromFirestore(doc);
        final distance = distanceBetweenLatLngMeters(
          location,
          report.coordinates,
        );
        if (distance <= policeReportDuplicateRadiusMeters) {
          if (mounted) {
            setState(() => isAddingPoliceReport = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: panelGlass,
                content: Text(
                  trText('In this area police is already marked.'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
            setState(() {
              selectedSpot = null;
              selectedPoliceReport = report;
              selectedSosReport = null;
              selectedLiveLocation = null;
            });
            moveMapCamera(report.coordinates, 15.5);
          }
          return;
        }
      }
    } catch (_) {
      // Local visible reports are already checked. Server check is best-effort for beta.
    }

    final docRef = policeReportsCollection().doc();

    await docRef.set({
      'uid': firebaseUser.uid,
      'username': currentUser.username,
      'lat': position.latitude,
      'lng': position.longitude,
      'coordinates': GeoPoint(position.latitude, position.longitude),
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'updatedAt': FieldValue.serverTimestamp(),
      'status': 'active',
      'stillThereBy': <String>[],
      'notThereBy': <String>[],
    });

    if (!mounted) {
      return;
    }

    final newReport = PoliceReportData(
      id: docRef.id,
      uid: firebaseUser.uid,
      username: currentUser.username,
      coordinates: location,
      createdAtMillis: now.millisecondsSinceEpoch,
      expiresAtMillis: expiresAt.millisecondsSinceEpoch,
      updatedAtMillis: now.millisecondsSinceEpoch,
    );

    setState(() {
      currentUserLocation = location;
      selectedSpot = null;
      selectedPoliceReport = newReport;
      selectedSosReport = null;
      selectedLiveLocation = null;
      isAddingPoliceReport = false;
    });

    moveMapCamera(location, 15.5);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: panelGlass,
        content: Text(
          'Police marked on the map for 2 hours.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> removePoliceReport(PoliceReportData report) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null ||
        (report.uid != firebaseUser.uid &&
            !userRoleIsStaff(currentUser.role))) {
      return;
    }

    await policeReportsCollection().doc(report.id).set({
      'status': 'removed',
      'removedByUid': firebaseUser.uid,
      'removedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) {
      return;
    }

    setState(() {
      selectedPoliceReport = null;
      policeReports = policeReports
          .where((item) => item.id != report.id)
          .toList();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: panelGlass,
        content: const Text(
          'Police mark removed from the map.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> votePoliceReport(
    PoliceReportData report, {
    required bool stillThere,
  }) async {
    if (isVotingPoliceReport) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Log in before confirming a police mark.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final position = await getMapUserPosition(showErrors: true);

    if (!mounted) {
      return;
    }

    if (position == null) {
      return;
    }

    final freshLocation = safeLatLngFromPosition(position);
    if (freshLocation == null) {
      return;
    }
    final distance = const Distance().as(
      LengthUnit.Meter,
      freshLocation,
      report.coordinates,
    );

    setState(() => currentUserLocation = freshLocation);

    if (distance > policeReportVoteRadiusMeters) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: panelGlass,
          content: Text(
            'Get closer to this police mark before confirming it.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (report.uid == firebaseUser.uid &&
        !isPoliceReportCreatorCooldownOver(report)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: panelGlass,
          content: Text(
            'You created this mark. You can confirm it later if you drive by this spot again.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    setState(() => isVotingPoliceReport = true);

    final reportRef = policeReportsCollection().doc(report.id);
    var removed = false;

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(reportRef);

        if (!snapshot.exists) {
          removed = true;
          return;
        }

        final data = snapshot.data() ?? <String, dynamic>{};
        final stillThereBy = List<String>.of(
          stringListFromFirebase(data['stillThereBy'], const []),
        );
        final notThereBy = List<String>.of(
          stringListFromFirebase(data['notThereBy'], const []),
        );

        stillThereBy.remove(firebaseUser.uid);
        notThereBy.remove(firebaseUser.uid);

        if (stillThere) {
          stillThereBy.add(firebaseUser.uid);
        } else {
          notThereBy.add(firebaseUser.uid);
        }

        final shouldRemove =
            !stillThere &&
            (notThereBy.length >= 3 || data['uid'] == firebaseUser.uid);

        if (shouldRemove) {
          removed = true;
          transaction.update(reportRef, {
            'status': 'removed',
            'removedByUid': firebaseUser.uid,
            'removedAt': FieldValue.serverTimestamp(),
            'stillThereBy': stillThereBy,
            'notThereBy': notThereBy,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.update(reportRef, {
            'stillThereBy': stillThereBy,
            'notThereBy': notThereBy,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } finally {
      if (mounted) {
        setState(() => isVotingPoliceReport = false);
      }
    }

    if (!mounted) {
      return;
    }

    if (removed) {
      setState(() {
        selectedPoliceReport = null;
        policeReports = policeReports
            .where((item) => item.id != report.id)
            .toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: panelGlass,
          content: Text(
            'Police mark removed from the map.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: panelGlass,
          content: Text(
            stillThere
                ? 'Thanks. Police mark confirmed.'
                : 'Thanks. Not there report saved.',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  void startLiveLocationSync() {
    liveLocationSubscription?.cancel();
    final currentFirebaseUser = FirebaseAuth.instance.currentUser;

    if (currentFirebaseUser == null) {
      setState(() {
        liveLocations = const [];
        selectedLiveLocation = null;
        isSharingLiveLocation = false;
        liveLocationPromptAt = null;
        liveLocationExpiresAt = null;
      });
      cancelLiveLocationTimers(keepUploadTimer: false);
      return;
    }

    liveLocationSubscription = liveLocationsCollection()
        .where('visibleToUserIds', arrayContains: currentFirebaseUser.uid)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) {
              return;
            }

            final firebaseUser = FirebaseAuth.instance.currentUser;
            final locations = snapshot.docs
                .map((doc) => LiveLocationData.fromFirestore(doc))
                .where((location) => !location.isExpired)
                .toList();
            final visibleLocations = locations.where((location) {
              if (firebaseUser == null) {
                return false;
              }

              if (location.uid == firebaseUser.uid) {
                return true;
              }

              return location.visibleToUserIds.contains(firebaseUser.uid);
            }).toList();

            LiveLocationData? ownLocation;
            if (firebaseUser != null) {
              for (final location in visibleLocations) {
                if (location.uid == firebaseUser.uid) {
                  ownLocation = location;
                  break;
                }
              }
            }

            setState(() {
              liveLocations = visibleLocations;
              final selectedUid = selectedLiveLocation?.uid;
              selectedLiveLocation = selectedUid == null
                  ? null
                  : (() {
                      for (final location in visibleLocations) {
                        if (location.uid == selectedUid &&
                            location.uid != firebaseUser?.uid) {
                          return location;
                        }
                      }
                      return null;
                    })();
              if (ownLocation != null) {
                isSharingLiveLocation = true;
                liveLocationPromptAt = DateTime.fromMillisecondsSinceEpoch(
                  ownLocation.promptAtMillis,
                );
                liveLocationExpiresAt = DateTime.fromMillisecondsSinceEpoch(
                  ownLocation.expiresAtMillis,
                );
                liveLocationShareDuration = Duration(
                  minutes: ownLocation.shareDurationMinutes,
                );
                scheduleLiveLocationTimers();
              } else if (!isTogglingLiveLocation) {
                isSharingLiveLocation = false;
                liveLocationPromptAt = null;
                liveLocationExpiresAt = null;
                cancelLiveLocationTimers(keepUploadTimer: false);
              }
            });

            if (ownLocation != null && firebaseUser != null) {
              ensureLiveLocationUploadLoop();
              final promptAt = DateTime.fromMillisecondsSinceEpoch(
                ownLocation.promptAtMillis,
              );
              final expiresAt = DateTime.fromMillisecondsSinceEpoch(
                ownLocation.expiresAtMillis,
              );
              unawaited(
                startNativeLiveLocationBackgroundService(
                  uid: firebaseUser.uid,
                  visibleToUserIds: ownLocation.visibleToUserIds.isEmpty
                      ? [firebaseUser.uid]
                      : ownLocation.visibleToUserIds,
                  shareScope: ownLocation.shareScope.trim().isEmpty
                      ? 'friends'
                      : ownLocation.shareScope,
                  promptAt: promptAt,
                  expiresAt: expiresAt,
                ),
              );
            }
          },
          onError: (_) {
            // Firestore rules may still be closed while this feature is being set up.
          },
        );
  }

  void ensureLiveLocationUploadLoop() {
    if (liveLocationUploadTimer != null) {
      return;
    }

    liveLocationUploadTimer = Timer.periodic(
      liveLocationUploadInterval,
      (_) => uploadLatestLiveLocation(),
    );
  }

  void cancelLiveLocationTimers({bool keepUploadTimer = false}) {
    liveLocationPromptTimer?.cancel();
    liveLocationPromptTimer = null;
    liveLocationAutoStopTimer?.cancel();
    liveLocationAutoStopTimer = null;

    if (!keepUploadTimer) {
      liveLocationUploadTimer?.cancel();
      liveLocationUploadTimer = null;
    }
  }

  void scheduleLiveLocationTimers() {
    final promptAt = liveLocationPromptAt;
    final expiresAt = liveLocationExpiresAt;

    liveLocationPromptTimer?.cancel();
    liveLocationAutoStopTimer?.cancel();

    if (!isSharingLiveLocation || promptAt == null || expiresAt == null) {
      return;
    }

    final now = DateTime.now();
    final promptDelay = promptAt.difference(now);
    final autoStopDelay = expiresAt.difference(now);

    liveLocationPromptTimer = Timer(
      promptDelay.isNegative ? Duration.zero : promptDelay,
      showLiveLocationRenewPrompt,
    );
    liveLocationAutoStopTimer = Timer(
      autoStopDelay.isNegative ? Duration.zero : autoStopDelay,
      stopLiveLocationSharing,
    );
  }

  Future<void> toggleLiveLocationSharing(bool enabled) async {
    if (enabled) {
      await startLiveLocationSharing();
    } else {
      await stopLiveLocationSharing();
    }
  }

  Future<void> startNativeLiveLocationBackgroundService({
    required String uid,
    required List<String> visibleToUserIds,
    required String shareScope,
    required DateTime promptAt,
    required DateTime expiresAt,
  }) async {
    try {
      await liveLocationBackgroundChannel.invokeMethod('start', {
        'uid': uid,
        'visibleToUserIds': visibleToUserIds,
        'shareScope': shareScope,
        'promptAtMillis': promptAt.millisecondsSinceEpoch,
        'expiresAtMillis': expiresAt.millisecondsSinceEpoch,
        'uploadIntervalSeconds': liveLocationUploadInterval.inSeconds,
        'minimumUploadDistanceMeters': liveLocationMinimumUploadDistanceMeters,
      });
    } on MissingPluginException {
      // Native background tracking is not wired yet. Foreground sharing still works.
    } catch (_) {}
  }

  Future<void> stopNativeLiveLocationBackgroundService() async {
    try {
      await liveLocationBackgroundChannel.invokeMethod('stop');
    } on MissingPluginException {
      // Native background tracking is not wired yet.
    } catch (_) {}
  }

  Future<void> startLiveLocationSharing() async {
    if (isTogglingLiveLocation) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Log in before sharing your live location.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    setState(() => isTogglingLiveLocation = true);

    final acceptedDisclaimer = await showLiveLocationSharingDisclaimer(context);
    if (!mounted) {
      return;
    }
    if (!acceptedDisclaimer) {
      setState(() => isTogglingLiveLocation = false);
      return;
    }

    final shareDuration = await showLiveLocationDurationDialog(context);
    if (!mounted) {
      return;
    }
    if (shareDuration == null) {
      setState(() => isTogglingLiveLocation = false);
      return;
    }

    liveLocationShareDuration = shareDuration;

    final position = await getMapUserPosition(showErrors: true);

    if (!mounted) {
      return;
    }

    if (position == null) {
      setState(() => isTogglingLiveLocation = false);
      return;
    }

    var friendUids = const <String>[];
    try {
      friendUids = await loadCurrentFriendUids();
    } catch (_) {
      friendUids = const <String>[];
    }

    if (!mounted) {
      return;
    }

    final visibleToUserIds = uniqueNonEmptyStrings([
      firebaseUser.uid,
      ...friendUids,
    ]);
    final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }
    final speed = position.speed.isFinite ? math.max(0.0, position.speed) : 0.0;
    final heading = headingForNewUserLocation(
      location,
      position.heading,
      speedMetersPerSecond: speed,
    );

    await writeLiveLocation(
      position,
      renewWindow: true,
      headingDegrees: heading,
      shareDuration: shareDuration,
      visibleToUserIds: visibleToUserIds,
      shareScope: 'friends',
    );

    final promptAt = liveLocationPromptAt;
    final expiresAt = liveLocationExpiresAt;
    if (promptAt != null && expiresAt != null) {
      unawaited(
        startNativeLiveLocationBackgroundService(
          uid: firebaseUser.uid,
          visibleToUserIds: visibleToUserIds,
          shareScope: 'friends',
          promptAt: promptAt,
          expiresAt: expiresAt,
        ),
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      currentUserLocation = location;
      displayedUserLocation = location;
      lastGpsUserLocation = location;
      lastUploadedLiveLocation = location;
      lastGpsUserLocationAt = DateTime.now();
      currentUserHeadingDegrees = heading;
      currentUserSpeedMetersPerSecond = speed;
      isSharingLiveLocation = true;
      isTogglingLiveLocation = false;
    });

    startNavigationTracking();
    updateFollowCamera(location, heading);

    liveLocationUploadTimer?.cancel();
    liveLocationUploadTimer = Timer.periodic(
      liveLocationUploadInterval,
      (_) => uploadLatestLiveLocation(),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: panelGlass,
        content: Text(
          'Live location sharing is on for ${liveLocationDurationLabel(shareDuration)}.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> uploadLatestLiveLocation() async {
    if (!isSharingLiveLocation) {
      return;
    }

    final position = await getMapUserPosition(showErrors: false);

    if (position == null || !mounted) {
      return;
    }

    final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }
    final speed = position.speed.isFinite ? math.max(0.0, position.speed) : 0.0;
    final heading = headingForNewUserLocation(
      location,
      position.heading,
      speedMetersPerSecond: speed,
    );
    final lastUploadedLocation = lastUploadedLiveLocation;
    final movedSinceLastUpload = lastUploadedLocation == null
        ? liveLocationMinimumUploadDistanceMeters
        : const Distance().as(LengthUnit.Meter, lastUploadedLocation, location);

    // Upload live location every 30 seconds while sharing is active.
    // Local marker still updates smoothly between Firebase writes.
    if (liveLocationMinimumUploadDistanceMeters > 0 &&
        movedSinceLastUpload < liveLocationMinimumUploadDistanceMeters) {
      setState(() {
        currentUserLocation = location;
        displayedUserLocation ??= location;
        lastGpsUserLocation = location;
        lastGpsUserLocationAt = DateTime.now();
        currentUserHeadingDegrees = heading;
        currentUserSpeedMetersPerSecond = speed;
      });

      if (mapCenteredOnCurrentUser) {
        updateFollowCamera(displayedUserLocation ?? location, heading);
      }
      return;
    }

    await writeLiveLocation(
      position,
      renewWindow: false,
      headingDegrees: heading,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      currentUserLocation = location;
      displayedUserLocation ??= location;
      lastGpsUserLocation = location;
      lastUploadedLiveLocation = location;
      lastGpsUserLocationAt = DateTime.now();
      currentUserHeadingDegrees = heading;
      currentUserSpeedMetersPerSecond = speed;
    });

    if (mapCenteredOnCurrentUser) {
      updateFollowCamera(displayedUserLocation ?? location, heading);
    }
  }

  Future<void> writeLiveLocation(
    Position position, {
    required bool renewWindow,
    double? headingDegrees,
    Duration? shareDuration,
    List<String>? visibleToUserIds,
    String? visibleToChatId,
    String? visibleToChatName,
    String? shareScope,
  }) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return;
    }

    final now = DateTime.now();
    final duration = shareDuration ?? liveLocationShareDuration;
    final promptAt = renewWindow
        ? now.add(duration)
        : liveLocationPromptAt ?? now.add(duration);
    final expiresAt = renewWindow
        ? promptAt.add(liveLocationRenewGracePeriod)
        : liveLocationExpiresAt ?? promptAt.add(liveLocationRenewGracePeriod);

    liveLocationShareDuration = duration;
    liveLocationPromptAt = promptAt;
    liveLocationExpiresAt = expiresAt;

    final docRef = liveLocationsCollection().doc(firebaseUser.uid);
    Map<String, dynamic>? existingData;

    if (visibleToUserIds == null ||
        visibleToChatId == null ||
        visibleToChatName == null ||
        shareScope == null) {
      final existingSnapshot = await docRef.get();
      existingData = existingSnapshot.data();
    }

    final nextVisibleToUserIds = uniqueNonEmptyStrings(
      visibleToUserIds ??
          stringListFromFirebase(existingData?['visibleToUserIds'], [
            firebaseUser.uid,
          ]),
    );
    final nextVisibleToChatId =
        visibleToChatId ??
        stringFromFirebase(existingData?['visibleToChatId'], '');
    final nextVisibleToChatName =
        visibleToChatName ??
        stringFromFirebase(existingData?['visibleToChatName'], '');
    final nextShareScope =
        shareScope ?? stringFromFirebase(existingData?['shareScope'], '');

    await docRef.set({
      'uid': firebaseUser.uid,
      'username': currentUser.username,
      'name': currentUser.name,
      'photoUrl': currentUser.photoUrl,
      'role': roleName(currentUser.role),
      'verified': currentUser.verified,
      'heading': normalizedHeadingDegrees(
        headingDegrees ?? position.heading,
        fallback: currentUserHeadingDegrees,
      ),
      'lat': position.latitude,
      'lng': position.longitude,
      'coordinates': GeoPoint(position.latitude, position.longitude),
      'visibleToUserIds': nextVisibleToUserIds.isEmpty
          ? [firebaseUser.uid]
          : nextVisibleToUserIds,
      'visibleToChatId': nextVisibleToChatId,
      'visibleToChatName': nextVisibleToChatName,
      'shareScope': nextShareScope,
      'shareDurationMinutes': duration.inMinutes,
      'promptAt': Timestamp.fromDate(promptAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await usersCollection().doc(firebaseUser.uid).set({
      'isSharingLiveLocation': true,
      'liveLocationExpiresAt': Timestamp.fromDate(expiresAt),
      'liveLocationShareDurationMinutes': duration.inMinutes,
      'liveLocationVisibleToUserIds': nextVisibleToUserIds.isEmpty
          ? [firebaseUser.uid]
          : nextVisibleToUserIds,
      'lastSeenAt': FieldValue.serverTimestamp(),
      'isOnline': true,
    }, SetOptions(merge: true));

    if (mounted) {
      scheduleLiveLocationTimers();
    }
  }

  Future<void> stopLiveLocationSharing() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    liveLocationUploadTimer?.cancel();
    liveLocationUploadTimer = null;
    cancelLiveLocationTimers(keepUploadTimer: true);
    unawaited(stopNativeLiveLocationBackgroundService());

    if (firebaseUser != null) {
      await liveLocationsCollection().doc(firebaseUser.uid).delete();
      await usersCollection().doc(firebaseUser.uid).set({
        'isSharingLiveLocation': false,
        'liveLocationExpiresAt': null,
        'liveLocationShareDurationMinutes': null,
        'liveLocationVisibleToUserIds': [],
      }, SetOptions(merge: true));
    }

    if (!mounted) {
      return;
    }

    setState(() {
      isSharingLiveLocation = false;
      isTogglingLiveLocation = false;
      liveLocationPromptAt = null;
      liveLocationExpiresAt = null;
      liveLocationShareDuration = const Duration(hours: 1);
      liveLocationPromptOpen = false;
      lastUploadedLiveLocation = null;
      liveLocations = liveLocations
          .where((location) => location.uid != firebaseUser?.uid)
          .toList();
    });
  }

  Future<void> continueLiveLocationSharing() async {
    final position = await getMapUserPosition(showErrors: true);

    if (!mounted) {
      return;
    }

    if (position == null) {
      await stopLiveLocationSharing();
      return;
    }

    final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }
    final speed = position.speed.isFinite ? math.max(0.0, position.speed) : 0.0;
    final heading = headingForNewUserLocation(
      location,
      position.heading,
      speedMetersPerSecond: speed,
    );

    await writeLiveLocation(
      position,
      renewWindow: true,
      headingDegrees: heading,
      shareDuration: liveLocationShareDuration,
    );

    final firebaseUser = FirebaseAuth.instance.currentUser;
    final promptAt = liveLocationPromptAt;
    final expiresAt = liveLocationExpiresAt;
    if (firebaseUser != null && promptAt != null && expiresAt != null) {
      var friendUids = const <String>[];
      try {
        friendUids = await loadCurrentFriendUids();
      } catch (_) {
        friendUids = const <String>[];
      }

      unawaited(
        startNativeLiveLocationBackgroundService(
          uid: firebaseUser.uid,
          visibleToUserIds: uniqueNonEmptyStrings([
            firebaseUser.uid,
            ...friendUids,
          ]),
          shareScope: 'friends',
          promptAt: promptAt,
          expiresAt: expiresAt,
        ),
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      isSharingLiveLocation = true;
      currentUserLocation = location;
      lastUploadedLiveLocation = location;
      currentUserHeadingDegrees = heading;
    });

    if (mapCenteredOnCurrentUser) {
      updateFollowCamera(location, heading);
    }
  }

  Future<void> showLiveLocationRenewPrompt() async {
    if (!mounted || !isSharingLiveLocation || liveLocationPromptOpen) {
      return;
    }

    liveLocationPromptOpen = true;

    final keepSharing = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: const Text(
            'Continue sharing?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: Text(
            'Your live location has been shared for ${liveLocationDurationLabel(liveLocationShareDuration)}. Keep sharing it for another ${liveLocationDurationLabel(liveLocationShareDuration)}?',
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stop sharing'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: blue),
              child: const Text(
                'Continue sharing',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    liveLocationPromptOpen = false;

    if (!mounted || !isSharingLiveLocation) {
      return;
    }

    if (keepSharing == true) {
      await continueLiveLocationSharing();
    } else if (keepSharing == false) {
      await stopLiveLocationSharing();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: panelGlass,
          content: Text(
            'No answer. Live location will stop automatically in 10 minutes.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    temporarySpotRefreshTimer?.cancel();
    liveLocationUploadTimer?.cancel();
    liveLocationPromptTimer?.cancel();
    liveLocationAutoStopTimer?.cancel();
    liveLocationSubscription?.cancel();
    policeReportSubscription?.cancel();
    sosReportSubscription?.cancel();
    sosDistanceCheckTimer?.cancel();
    navigationPositionSubscription?.cancel();
    navigationPredictionTimer?.cancel();
    reviewSpots.removeListener(refreshMap);
    spotCategoryFilters.removeListener(refreshMap);
    mapFocusRequest.removeListener(handleMapFocusRequest);
    mapAlertPulseController.dispose();
    mapController.dispose();
    super.dispose();
  }

  Future<void> openSosMessage(SosReportData report) async {
    try {
      final snapshot = await usersCollection().doc(report.uid).get();
      if (!snapshot.exists) {
        throw Exception('User profile is not available anymore.');
      }

      final user = FriendUserData.fromFirestore(snapshot);
      if (!mounted) {
        return;
      }

      await openMessageToUserFromContext(context, user);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not open chat: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  Future<void> openWazeRouteToLatLng(LatLng location) async {
    final wazeAppUrl = Uri.parse(
      'waze://?ll=${location.latitude},${location.longitude}&navigate=yes',
    );
    final wazeWebUrl = Uri.parse(
      'https://waze.com/ul?ll=${location.latitude},${location.longitude}&navigate=yes',
    );

    if (await canLaunchUrl(wazeAppUrl)) {
      await launchUrl(wazeAppUrl, mode: LaunchMode.externalApplication);
      return;
    }

    await launchUrl(wazeWebUrl, mode: LaunchMode.externalApplication);
  }

  void openSpotDetails(CarSpot spot) {
    Navigator.push(
      context,
      appPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
    );
  }

  void loadInitialUserLocation() {
    // Intentionally do nothing on map open.
    // The map should open on Riga spots first. User location is requested only
    // after pressing the blue "find me" button or enabling live location.
  }

  void startNavigationTracking() {
    navigationPositionSubscription ??=
        Geolocator.getPositionStream(
          locationSettings: Platform.isAndroid
              ? AndroidSettings(
                  accuracy: LocationAccuracy.bestForNavigation,
                  distanceFilter: 0,
                  intervalDuration: const Duration(milliseconds: 500),
                  forceLocationManager: false,
                )
              : AppleSettings(
                  accuracy: LocationAccuracy.bestForNavigation,
                  distanceFilter: 0,
                  activityType: ActivityType.automotiveNavigation,
                  pauseLocationUpdatesAutomatically: false,
                ),
        ).listen(
          handleNavigationPosition,
          onError: (_) {
            // Keep the map usable even if the high-frequency stream is unavailable.
          },
        );

    navigationPredictionTimer ??= Timer.periodic(
      const Duration(milliseconds: 80),
      (_) => updatePredictedUserMarker(),
    );
  }

  void handleNavigationPosition(Position position) {
    if (!mounted) {
      return;
    }

    final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }
    final speed = position.speed.isFinite ? math.max(0.0, position.speed) : 0.0;
    final heading = headingForNewUserLocation(
      location,
      position.heading,
      speedMetersPerSecond: speed,
    );

    final currentDisplay = displayedUserLocation ?? location;
    final distanceToNewGps = distanceBetweenLatLngMeters(
      currentDisplay,
      location,
    );

    final nextDisplay = distanceToNewGps > 80
        ? location
        : lerpLatLng(currentDisplay, location, speed >= 2.0 ? 0.35 : 0.18);

    setState(() {
      currentUserLocation = location;
      displayedUserLocation = nextDisplay;
      lastGpsUserLocation = location;
      lastGpsUserLocationAt = DateTime.now();
      lastNavigationPositionAt = DateTime.now();
      currentUserHeadingDegrees = heading;
      currentUserSpeedMetersPerSecond = speed;
    });

    if (mapCenteredOnCurrentUser) {
      updateFollowCamera(nextDisplay, heading);
    }
  }

  void updatePredictedUserMarker() {
    if (!mounted) {
      return;
    }

    final gpsLocation = lastGpsUserLocation ?? currentUserLocation;
    final gpsTime = lastGpsUserLocationAt;

    if (gpsLocation == null || gpsTime == null) {
      return;
    }

    final speed = currentUserSpeedMetersPerSecond.clamp(0.0, 38.0).toDouble();
    final currentDisplay = displayedUserLocation ?? gpsLocation;

    // If almost stopped, do not keep projecting forward. Gently settle back
    // onto the latest GPS point instead of overshooting and snapping back.
    if (speed < 0.8) {
      final nextDisplay = lerpLatLng(currentDisplay, gpsLocation, 0.12);

      setState(() => displayedUserLocation = nextDisplay);

      if (mapCenteredOnCurrentUser) {
        updateFollowCamera(nextDisplay, currentUserHeadingDegrees);
      }

      return;
    }

    final secondsSinceGps =
        DateTime.now().difference(gpsTime).inMilliseconds / 1000.0;
    final predictedSeconds = secondsSinceGps.clamp(0.0, 0.75).toDouble();
    final predicted = projectLatLngMeters(
      gpsLocation,
      currentUserHeadingDegrees,
      speed * predictedSeconds,
    );
    final distanceToGps = distanceBetweenLatLngMeters(
      currentDisplay,
      gpsLocation,
    );
    final nextDisplay = distanceToGps > 80
        ? gpsLocation
        : lerpLatLng(currentDisplay, predicted, 0.16);

    setState(() => displayedUserLocation = nextDisplay);

    if (mapCenteredOnCurrentUser) {
      updateFollowCamera(nextDisplay, currentUserHeadingDegrees);
    }
  }

  Future<Position?> getMapUserPosition({required bool showErrors}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Turn on phone location first.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }

      return null;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Location permission is needed to show you on the map.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }

      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
      ),
    );
  }

  double headingForNewUserLocation(
    LatLng nextLocation,
    double rawHeading, {
    double speedMetersPerSecond = 0,
  }) {
    final fallback = currentUserHeadingDegrees;
    final normalizedRawHeading = normalizedHeadingDegrees(
      rawHeading,
      fallback: fallback,
    );

    final previousLocation =
        previousAcceptedHeadingLocation ?? currentUserLocation;

    if (previousLocation == null) {
      previousAcceptedHeadingLocation = nextLocation;
      smoothedUserHeadingDegrees = normalizedRawHeading;
      return smoothedUserHeadingDegrees;
    }

    final movedMeters = distanceBetweenLatLngMeters(
      previousLocation,
      nextLocation,
    );

    var targetHeading = smoothedUserHeadingDegrees;

    // Tiny GPS movements can produce random bearings, which makes the triangle
    // look like it is driving sideways. Use coordinate bearing only after real
    // movement; otherwise trust the device heading only while actually moving.
    if (movedMeters >= 5) {
      targetHeading = bearingBetweenLatLngDegrees(
        previousLocation,
        nextLocation,
      );
      previousAcceptedHeadingLocation = nextLocation;
    } else if (speedMetersPerSecond >= 2.0 &&
        rawHeading.isFinite &&
        rawHeading >= 0) {
      targetHeading = normalizedRawHeading;
    }

    smoothedUserHeadingDegrees = smoothHeadingDegrees(
      smoothedUserHeadingDegrees,
      targetHeading,
      speedMetersPerSecond >= 2.0 ? 0.22 : 0.10,
    );

    return smoothedUserHeadingDegrees;
  }

  double smoothHeadingDegrees(double from, double to, double amount) {
    final a = normalizedHeadingDegrees(from);
    final b = normalizedHeadingDegrees(to);
    final delta = ((b - a + 540) % 360) - 180;

    return normalizedHeadingDegrees(a + delta * amount);
  }

  void updateFollowCamera(LatLng location, double headingDegrees) {
    if (!isValidLatLng(location)) {
      return;
    }

    final safeHeading = normalizedHeadingDegrees(
      headingDegrees,
      fallback: currentMapRotationDegrees,
    );

    moveMapCamera(
      location,
      navigationZoom,
      rotationDegrees: safeHeading,
    );
  }

  Future<void> moveToCurrentLocation({bool showErrors = true}) async {
    if (isLocatingUser) {
      return;
    }

    setState(() => isLocatingUser = true);

    final position = await getMapUserPosition(showErrors: showErrors);

    if (!mounted) {
      return;
    }

    if (position == null) {
      setState(() => isLocatingUser = false);
      return;
    }

    final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }
    final speed = position.speed.isFinite ? math.max(0.0, position.speed) : 0.0;
    final heading = headingForNewUserLocation(
      location,
      position.heading,
      speedMetersPerSecond: speed,
    );

    setState(() {
      currentUserLocation = location;
      displayedUserLocation = location;
      lastGpsUserLocation = location;
      lastGpsUserLocationAt = DateTime.now();
      currentUserHeadingDegrees = heading;
      currentUserSpeedMetersPerSecond = speed;
      currentMapZoom = navigationZoom;
      currentMapRotationDegrees = heading;
      mapCenteredOnCurrentUser = true;
      selectedSpot = null;
      selectedPoliceReport = null;
      selectedSosReport = null;
      selectedLiveLocation = null;
      isLocatingUser = false;
    });

    startNavigationTracking();
    updateFollowCamera(location, heading);
  }

  @override
  Widget build(BuildContext context) {
    final spot = selectedSpot;
    final policeReport = selectedPoliceReport;
    final sosReport = selectedSosReport;
    final liveLocation = selectedLiveLocation;
    final hasBottomCard =
        spot != null ||
        policeReport != null ||
        sosReport != null ||
        liveLocation != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: rigaCenter,
              initialZoom: rigaZoom,
              initialRotation: currentMapRotationDegrees,
              minZoom: 4,
              maxZoom: 18,
              backgroundColor: night,
              onPositionChanged: (camera, hasGesture) {
                if (!isValidLatLng(camera.center) || !camera.zoom.isFinite) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      restoreMapCamera();
                    }
                  });
                  return;
                }

                final nextZoom = camera.zoom.clamp(4.0, 18.0).toDouble();
                final nextRotation = normalizedHeadingDegrees(
                  camera.rotation,
                  fallback: currentMapRotationDegrees,
                );
                final zoomChanged = (nextZoom - currentMapZoom).abs() >= 0.05;
                final rotationChanged =
                    (nextRotation - currentMapRotationDegrees).abs() >= 0.5;

                if (zoomChanged || rotationChanged || hasGesture) {
                  setState(() {
                    currentMapCenter = camera.center;
                    currentMapZoom = nextZoom;
                    currentMapRotationDegrees = nextRotation;
                    if (hasGesture) {
                      mapCenteredOnCurrentUser = false;
                    }
                  });
                }
              },
              onTap: (_, _) => setState(() {
                selectedSpot = null;
                selectedPoliceReport = null;
                selectedSosReport = null;
                selectedLiveLocation = null;
              }),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.ccs_app',
                maxNativeZoom: 19,
              ),
              MarkerLayer(markers: allMapMarkers),
            ],
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: _MapHeader(
                    isSharingLiveLocation: isSharingLiveLocation,
                    isBusy: isTogglingLiveLocation,
                    onShareChanged: toggleLiveLocationSharing,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: MapFilterButton(
                      enabledCount: spotCategoryFilters.value.length,
                      totalCount: spotCategoryOptions.length,
                      onTap: showMapCategoryFilterSheet,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: hasBottomCard ? 196 : 18,
            child: FloatingActionButton.small(
              heroTag: 'add_map_report',
              onPressed: (isAddingPoliceReport || isAddingSosReport)
                  ? null
                  : showAddMapReportSheet,
              backgroundColor: panelGlass,
              foregroundColor: Colors.white,
              child: (isAddingPoliceReport || isAddingSosReport)
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add),
            ),
          ),
          Positioned(
            right: 16,
            bottom: hasBottomCard ? 196 : 18,
            child: FloatingActionButton.small(
              heroTag: 'current_location',
              onPressed: isLocatingUser ? null : () => moveToCurrentLocation(),
              backgroundColor: blue,
              foregroundColor: Colors.white,
              child: isLocatingUser
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
          if (policeReport != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: PoliceReportMapCard(
                report: policeReport,
                isBusy: isVotingPoliceReport,
                canVote: canVotePoliceReportFromCurrentMapLocation(
                  policeReport,
                ),
                voteHint: policeReportVoteHint(policeReport),
                onStillThere: () =>
                    votePoliceReport(policeReport, stillThere: true),
                onNotThere: () =>
                    votePoliceReport(policeReport, stillThere: false),
                onDelete:
                    policeReport.uid == FirebaseAuth.instance.currentUser?.uid
                    ? () => removePoliceReport(policeReport)
                    : null,
              ),
            ),
          if (sosReport != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SosReportMapCard(
                report: sosReport,
                isOwnReport:
                    sosReport.uid == FirebaseAuth.instance.currentUser?.uid,
                onOpenProfile: () => openUserProfile(
                  context,
                  uid: sosReport.uid,
                  fallbackUsername: sosReport.username,
                ),
                onMessage: () => openSosMessage(sosReport),
                onRoute: () => openWazeRouteToLatLng(sosReport.coordinates),
                onDelete:
                    sosReport.uid == FirebaseAuth.instance.currentUser?.uid
                    ? () => removeSosReport(sosReport)
                    : null,
              ),
            ),
          if (spot != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SpotMapCard(
                spot: spot,
                onOpen: () => openSpotDetails(spot),
              ),
            ),
          if (liveLocation != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: LiveLocationMapCard(
                location: liveLocation,
                isFriend: liveLocationIsFriend(liveLocation),
                onOpen: () => openUserProfile(
                  context,
                  uid: liveLocation.uid,
                  fallbackUsername: liveLocation.username,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MapFilterButton extends StatelessWidget {
  final int enabledCount;
  final int totalCount;
  final VoidCallback onTap;

  const MapFilterButton({
    super.key,
    required this.enabledCount,
    required this.totalCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final allEnabled = enabledCount == totalCount;
    final label = allEnabled ? 'Filters' : 'Filters $enabledCount/$totalCount';

    return Material(
      color: panelGlass,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: allEnabled ? Colors.white12 : blue.withValues(alpha: 0.75),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune,
                color: allEnabled ? Colors.white70 : blue,
                size: 19,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CompactSpotMapPoint extends StatelessWidget {
  final Color color;
  final double size;
  final bool faded;
  final bool event;

  const CompactSpotMapPoint({
    super.key,
    required this.color,
    this.size = 14,
    this.faded = false,
    this.event = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Opacity(
        opacity: faded ? 0.58 : 1,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: event
                  ? Colors.orangeAccent
                  : Colors.white.withValues(alpha: 0.80),
              width: event
                  ? math.max(0.5, size * 0.09)
                  : math.max(0.45, size * 0.065),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: event ? 0.54 : 0.38),
                blurRadius: math.max(
                  event ? 3.2 : 2.4,
                  size * (event ? 0.50 : 0.38),
                ),
                spreadRadius: math.max(
                  event ? 0.28 : 0.18,
                  size * (event ? 0.055 : 0.04),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PulsingTemporarySpotIconGlow extends StatefulWidget {
  final double size;
  final Widget child;
  final bool compact;

  const PulsingTemporarySpotIconGlow({
    super.key,
    required this.size,
    required this.child,
    this.compact = false,
  });

  @override
  State<PulsingTemporarySpotIconGlow> createState() =>
      _PulsingTemporarySpotIconGlowState();
}

class _PulsingTemporarySpotIconGlowState
    extends State<PulsingTemporarySpotIconGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final value = Curves.easeInOut.transform(controller.value);
        final scale = widget.compact ? 1 + value * 0.12 : 1 + value * 0.065;
        final glowBlur = widget.compact
            ? math.max(2.2, widget.size * (0.50 + value * 0.44))
            : math.max(12.0, widget.size * (0.30 + value * 0.16));
        final glowSpread = widget.compact
            ? math.max(0.10, widget.size * (0.04 + value * 0.05))
            : math.max(1.8, widget.size * (0.045 + value * 0.025));

        return Transform.scale(
          scale: scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.orangeAccent.withValues(
                    alpha: widget.compact ? 0.55 : 0.62,
                  ),
                  blurRadius: glowBlur,
                  spreadRadius: glowSpread,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _VerifiedSpotBadge extends StatelessWidget {
  final double size;

  const _VerifiedSpotBadge({this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: blue,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.92),
          width: math.max(1.0, size * 0.09),
        ),
        boxShadow: [
          BoxShadow(
            color: blue.withValues(alpha: 0.55),
            blurRadius: math.max(5.0, size * 0.42),
            spreadRadius: math.max(0.4, size * 0.04),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: math.max(3.0, size * 0.24),
          ),
        ],
      ),
      child: Icon(Icons.check, color: Colors.white, size: size * 0.68),
    );
  }
}

class _TemporaryMapBadge extends StatelessWidget {
  const _TemporaryMapBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: Colors.orangeAccent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: Colors.orangeAccent.withValues(alpha: 0.48),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Text(
        'NOW',
        style: TextStyle(
          color: Colors.black,
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          height: 1,
        ),
      ),
    );
  }
}

class _MapHeader extends StatelessWidget {
  final bool isSharingLiveLocation;
  final bool isBusy;
  final ValueChanged<bool> onShareChanged;

  const _MapHeader({
    required this.isSharingLiveLocation,
    required this.isBusy,
    required this.onShareChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.map, color: blue),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Approved spots',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              color: isSharingLiveLocation
                  ? blue.withValues(alpha: 0.18)
                  : panelGlass,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isSharingLiveLocation ? blue : Colors.white12,
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Share live location',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 0.74,
                  child: Switch(
                    value: isSharingLiveLocation,
                    activeThumbColor: blue,
                    onChanged: isBusy ? null : onShareChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SosReportMapCard extends StatelessWidget {
  final SosReportData report;
  final bool isOwnReport;
  final VoidCallback onOpenProfile;
  final VoidCallback onMessage;
  final VoidCallback onRoute;
  final VoidCallback? onDelete;

  const SosReportMapCard({
    super.key,
    required this.report,
    this.isOwnReport = false,
    required this.onOpenProfile,
    required this.onMessage,
    required this.onRoute,
    this.onDelete,
  });

  String get timeLeftLabel {
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      report.expiresAtMillis,
    );
    final left = expiresAt.difference(DateTime.now());

    if (left.isNegative) {
      return 'expired';
    }

    final hours = left.inHours;
    final minutes = left.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m left';
    }

    return '${left.inMinutes.clamp(0, 720)}m left';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: sosAlertColor.withValues(alpha: 0.42)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: sosAlertColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text(
                    'SOS',
                    style: TextStyle(
                      color: sosAlertColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Help request',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: isOwnReport ? null : onOpenProfile,
                      child: Text(
                        isOwnReport
                            ? 'Your SOS - $timeLeftLabel'
                            : '@${displayUsername(report.username)} - $timeLeftLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isOwnReport ? Colors.white54 : blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: sosAlertColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: sosAlertColor.withValues(alpha: 0.26)),
            ),
            child: Text(
              trText(sosReasonLabel(report.reason)),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            report.description,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              height: 1.28,
            ),
          ),
          if (!isOwnReport) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpenProfile,
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: const Text('View Profile'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onMessage,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Write message'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRoute,
                icon: const Icon(Icons.route, size: 18),
                label: const Text('Open Waze'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: sosAlertColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ] else ...[
            if (onDelete != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(trText('Delete SOS')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              trText('Other drivers can see this SOS and contact you.'),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PoliceReportMapCard extends StatelessWidget {
  final PoliceReportData report;
  final bool isBusy;
  final bool canVote;
  final String voteHint;
  final VoidCallback onStillThere;
  final VoidCallback onNotThere;
  final VoidCallback? onDelete;

  const PoliceReportMapCard({
    super.key,
    required this.report,
    required this.isBusy,
    required this.canVote,
    required this.voteHint,
    required this.onStillThere,
    required this.onNotThere,
    this.onDelete,
  });

  String get timeLeftLabel {
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      report.expiresAtMillis,
    );
    final left = expiresAt.difference(DateTime.now());

    if (left.isNegative) {
      return 'expired';
    }

    final hours = left.inHours;
    final minutes = left.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m left';
    }

    return '${left.inMinutes.clamp(0, 120)}m left';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.local_police, color: Colors.redAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Police nearby',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      onTap: report.uid.trim().isEmpty
                          ? null
                          : () => openUserProfile(
                              context,
                              uid: report.uid,
                              fallbackUsername: report.username,
                            ),
                      borderRadius: BorderRadius.circular(999),
                      child: Text(
                        'Marked by ${displayUsername(report.username)} - $timeLeftLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _SmallTag(
                label: '${report.stillThereCount} still there',
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(width: 8),
              _SmallTag(
                label: '${report.notThereCount} not there',
                icon: Icons.cancel_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (onDelete != null) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isBusy ? null : onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(trText('Delete police mark')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (!canVote)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                voteHint.isEmpty
                    ? 'You can confirm this mark when you are close to it.'
                    : voteHint,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isBusy ? null : onNotThere,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Not there'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isBusy ? null : onStillThere,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Still there'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class SpotMapCard extends StatelessWidget {
  final CarSpot spot;
  final VoidCallback onOpen;

  const SpotMapCard({super.key, required this.spot, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SpotPhoto(
              spot: spot,
              width: 96,
              height: 124,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        spot.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (spot.verifiedOnly) ...[
                      const SizedBox(width: 8),
                      const _VerifiedSpotBadge(size: 18),
                    ],
                    const SizedBox(width: 8),
                    const Icon(Icons.star, color: blue, size: 16),
                    const SizedBox(width: 3),
                    Text(
                      spot.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  spot.cityCountry,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  spot.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, height: 1.3),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    if (spot.verifiedOnly)
                      _SmallTag(label: 'Verified only', icon: Icons.verified),
                    if (spot.isTemporary)
                      _SmallTag(
                        label: spot.temporaryTimeLabel,
                        icon: Icons.event,
                      ),
                    if (spot.isTemporary &&
                        !spot.isTemporaryLocationAvailableNow)
                      _SmallTag(
                        label: spot.temporaryLocationAvailableAtLabel,
                        icon: Icons.visibility_off_outlined,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: ElevatedButton(
                          onPressed: onOpen,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.open_in_full, size: 16),
                              SizedBox(width: 8),
                              Text('View Spot'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SaveSpotButton(spot: spot, compact: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LiveLocationMapCard extends StatelessWidget {
  final LiveLocationData location;
  final bool isFriend;
  final VoidCallback onOpen;

  const LiveLocationMapCard({
    super.key,
    required this.location,
    required this.isFriend,
    required this.onOpen,
  });

  FriendUserData get user {
    return FriendUserData(
      uid: location.uid,
      username: location.username,
      name: location.name,
      email: '',
      photoUrl: location.photoUrl,
      verified: location.verified,
      role: location.role,
      banned: false,
      deleted: false,
      isOnline: true,
      lastSeenAtMillis: location.updatedAtMillis,
      isSharingLiveLocation: true,
      liveLocationExpiresAtMillis: location.expiresAtMillis,
      liveLocationVisibleToUserIds: location.visibleToUserIds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileUser = user;
    final updatedLabel = location.updatedAtMillis > 0
        ? 'Updated ${formatShortDateTime(DateTime.fromMillisecondsSinceEpoch(location.updatedAtMillis))}'
        : 'Live location';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          UserAvatarCircle(user: profileUser, size: 84),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayUsername(location.username),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (location.verified) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.verified, color: blue, size: 17),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  updatedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _SmallTag(
                      label: isFriend ? 'Friend' : 'Driver',
                      icon: isFriend ? Icons.people : Icons.person,
                    ),
                    _SmallTag(
                      label: location.isExpired ? 'offline' : 'online',
                      icon: Icons.my_location,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: ElevatedButton(
                    onPressed: onOpen,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_circle_outlined, size: 16),
                        SizedBox(width: 8),
                        Text('View Profile'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SaveSpotButton extends StatelessWidget {
  final CarSpot spot;
  final bool compact;

  const SaveSpotButton({super.key, required this.spot, this.compact = false});

  bool isSaved(List<CarSpot> spots) {
    return spots.any((savedSpot) => isSameSpot(savedSpot, spot));
  }

  void toggleSaved(BuildContext context, bool saved) {
    if (saved) {
      savedSpots.value = savedSpots.value
          .where((savedSpot) => !isSameSpot(savedSpot, spot))
          .toList();
    } else {
      savedSpots.value = [spot, ...savedSpots.value];
    }
    unawaited(saveSavedSpotIds());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: saved ? panel : blue,
        content: Text(
          saved ? 'Spot removed from saved.' : 'Spot saved.',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CarSpot>>(
      valueListenable: savedSpots,
      builder: (context, spots, _) {
        final saved = isSaved(spots);

        if (compact) {
          return SizedBox(
            width: 44,
            height: 38,
            child: OutlinedButton(
              onPressed: () => toggleSaved(context, saved),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: saved
                    ? blue.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.06),
                foregroundColor: saved ? blue : Colors.white70,
                side: BorderSide(
                  color: saved ? blue : Colors.white24,
                  width: saved ? 1.4 : 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: Icon(
                saved ? Icons.bookmark : Icons.bookmark_border,
                size: 18,
              ),
            ),
          );
        }

        return SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () => toggleSaved(context, saved),
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            label: Text(saved ? 'Saved Spot' : 'Save Spot'),
            style: OutlinedButton.styleFrom(
              foregroundColor: saved ? blue : Colors.white,
              side: BorderSide(color: saved ? blue : Colors.white24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        );
      },
    );
  }
}

class SavedSpotTile extends StatelessWidget {
  final CarSpot spot;

  const SavedSpotTile({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          appPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            SpotPhoto(
              spot: spot,
              width: 84,
              height: 84,
              borderRadius: BorderRadius.circular(14),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    spot.cityCountry,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final category in spot.categories.take(2))
                        _SmallTag(label: category, icon: Icons.local_offer),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const EmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: blue),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, height: 1.35),
          ),
        ],
      ),
    );
  }
}

Future<void> launchExternalUrl(BuildContext context, String rawUrl) async {
  final trimmedUrl = rawUrl.trim();

  if (trimmedUrl.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'No link added for this spot.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return;
  }

  final uri = Uri.tryParse(trimmedUrl);

  if (uri == null || !uri.hasScheme) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'This link is not valid yet.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return;
  }

  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'Could not open this link.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

Future<void> openWazeRoute(BuildContext context, CarSpot spot) async {
  final lat = spot.coordinates.latitude;
  final lng = spot.coordinates.longitude;
  final wazeUri = Uri.parse('waze://?ll=$lat,$lng&navigate=yes');
  final webUri = Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes');

  try {
    final openedWaze = await launchUrl(
      wazeUri,
      mode: LaunchMode.externalApplication,
    );

    if (openedWaze) {
      return;
    }

    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  } catch (_) {
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }
}

Future<Position?> getCurrentPhoneLocation(BuildContext context) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();

  if (!serviceEnabled) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Turn on phone location to show distance.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return null;
  }

  var permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Location permission is needed for distance.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return null;
  }

  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
  );
}

double distanceToSpotInKm(Position position, CarSpot spot) {
  const distance = Distance();

  return distance.as(
    LengthUnit.Kilometer,
    safeLatLng(position.latitude, position.longitude),
    spot.coordinates,
  );
}

String formatDistanceKm(double value) {
  if (value < 1) {
    return '${(value * 1000).round()} m';
  }

  return '${value.toStringAsFixed(1)} km';
}

String estimateDriveTime(double distanceKm) {
  // This is only a rough straight-line estimate before Waze opens.
  // City trips use slower speed, long trips use a higher average speed.
  final averageSpeedKmh = distanceKm > 120 ? 70 : 35;
  final minutes = (distanceKm / averageSpeedKmh * 60).round().clamp(2, 999999);

  if (minutes < 60) {
    return '~$minutes min';
  }

  final hours = minutes ~/ 60;
  final restMinutes = minutes % 60;

  if (hours < 24) {
    return restMinutes == 0 ? '~$hours h' : '~$hours h $restMinutes min';
  }

  final days = hours ~/ 24;
  final restHours = hours % 24;

  return restHours == 0 ? '~$days d' : '~$days d $restHours h';
}

List<String> spotPhotoSources(CarSpot spot) {
  final sources = <String>[];

  void addSource(String value) {
    final trimmed = value.trim();

    if (trimmed.isNotEmpty && !sources.contains(trimmed)) {
      sources.add(trimmed);
    }
  }

  if (localFileExists(spot.localPhotoPath)) {
    addSource('local:${spot.localPhotoPath}');
  }

  for (final photoUrl in spot.photoUrls) {
    addSource(photoUrl);
  }

  addSource(spot.photoUrl);

  return sources;
}

bool isLocalSpotPhotoSource(String source) {
  return source.startsWith('local:');
}

String localPhotoPathFromSource(String source) {
  return source.substring('local:'.length);
}

Widget spotPhotoImage(
  String source, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  if (isLocalSpotPhotoSource(source)) {
    return Image.file(
      File(localPhotoPathFromSource(source)),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) =>
          _SpotPhotoPlaceholder(width: width, height: height),
    );
  }

  return Image.network(
    source,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: (_, _, _) =>
        _SpotPhotoPlaceholder(width: width, height: height),
  );
}

class SpotPhotoCarousel extends StatefulWidget {
  final CarSpot spot;
  final double height;

  const SpotPhotoCarousel({
    super.key,
    required this.spot,
    required this.height,
  });

  @override
  State<SpotPhotoCarousel> createState() => _SpotPhotoCarouselState();
}

class _SpotPhotoCarouselState extends State<SpotPhotoCarousel> {
  int currentIndex = 0;

  void openGallery(int index) {
    Navigator.push(
      context,
      appPageRoute(
        builder: (_) =>
            SpotPhotoGalleryScreen(spot: widget.spot, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = spotPhotoSources(widget.spot);

    if (sources.isEmpty) {
      return _SpotPhotoPlaceholder(height: widget.height);
    }

    if (currentIndex >= sources.length) {
      currentIndex = sources.length - 1;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTap: () => openGallery(currentIndex),
                child: spotPhotoImage(
                  sources[currentIndex],
                  width: double.infinity,
                  height: widget.height,
                  fit: BoxFit.cover,
                ),
              ),
              if (sources.length > 1)
                Positioned(
                  top: 14,
                  right: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      '${currentIndex + 1}/${sources.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (sources.length > 1)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            color: Colors.black,
            child: Row(
              children: [
                for (var index = 0; index < sources.length; index++) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => currentIndex = index),
                      onLongPress: () => openGallery(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: currentIndex == index
                              ? [
                                  BoxShadow(
                                    color: blue.withValues(alpha: 0.36),
                                    blurRadius: 14,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        foregroundDecoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: currentIndex == index
                                ? blue
                                : Colors.white24,
                            width: currentIndex == index ? 2.2 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            spotPhotoImage(sources[index], fit: BoxFit.cover),
                            if (currentIndex == index)
                              Container(
                                decoration: BoxDecoration(
                                  color: blue.withValues(alpha: 0.16),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (index != sources.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class SpotPhotoGalleryScreen extends StatefulWidget {
  final CarSpot spot;
  final int initialIndex;

  const SpotPhotoGalleryScreen({
    super.key,
    required this.spot,
    required this.initialIndex,
  });

  @override
  State<SpotPhotoGalleryScreen> createState() => _SpotPhotoGalleryScreenState();
}

class _SpotPhotoGalleryScreenState extends State<SpotPhotoGalleryScreen> {
  late final List<String> sources;
  late final PageController controller;
  late int currentIndex;

  @override
  void initState() {
    super.initState();
    sources = spotPhotoSources(widget.spot);
    currentIndex =
        widget.initialIndex >= 0 && widget.initialIndex < sources.length
        ? widget.initialIndex
        : 0;
    controller = PageController(initialPage: currentIndex);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          if (sources.isEmpty)
            const Center(
              child: Icon(Icons.directions_car, color: blue, size: 44),
            )
          else
            PageView.builder(
              controller: controller,
              itemCount: sources.length,
              onPageChanged: (index) => setState(() => currentIndex = index),
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: spotPhotoImage(
                      sources[index],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                  const Spacer(),
                  if (sources.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        '${currentIndex + 1}/${sources.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SpotDetailScreen extends StatefulWidget {
  final CarSpot spot;

  const SpotDetailScreen({super.key, required this.spot});

  @override
  State<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends State<SpotDetailScreen> {
  late CarSpot spot;

  @override
  void initState() {
    super.initState();
    spot = widget.spot;
  }

  void updateVisibleRating(double rating) {
    if ((spot.rating - rating).abs() < 0.01) {
      return;
    }

    setState(() => spot = spot.copyWith(rating: rating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Spot'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: [
          if (userRoleIsStaff(currentUser.role) ||
              spot.addedByUid == currentUser.uid)
            IconButton(
              tooltip: 'Edit spot',
              onPressed: () async {
                final saved = await Navigator.push<bool>(
                  context,
                  appPageRoute(builder: (_) => AdminEditSpotScreen(spot: spot)),
                );
                if (saved == true && mounted) {
                  final fresh = await spotsCollection().doc(spot.id).get();
                  if (fresh.exists && mounted) {
                    setState(() => spot = CarSpot.fromFirestore(fresh));
                  }
                }
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: ListView(
        children: [
          SpotPhotoCarousel(spot: spot, height: 300),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        spot.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (spot.hasOwner) ...[
                      const SizedBox(width: 10),
                      SpotOwnerBadge(spot: spot),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  spot.cityCountry,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 18),
                SpotDetailEngagementPanel(
                  spot: spot,
                  onRatingChanged: updateVisibleRating,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (spot.createdAtMillis > 0) ...[
                      Icon(
                        Icons.schedule,
                        color: Colors.white.withValues(alpha: 0.45),
                        size: 17,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Added ${formatShortDate(DateTime.fromMillisecondsSinceEpoch(spot.createdAtMillis))}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: spot.addedByUid.trim().isEmpty
                          ? Text(
                              'Added by ${spot.addedBy}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white54),
                            )
                          : InkWell(
                              onTap: () => openUserProfile(
                                context,
                                uid: spot.addedByUid,
                                fallbackUsername: spot.addedBy,
                              ),
                              borderRadius: BorderRadius.circular(999),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Text(
                                  'Added by ${displayUsername(spot.addedBy)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: blue,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  spot.description,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (spot.isTemporary)
                      _SmallTag(
                        label: spot.temporaryTimeLabel,
                        icon: Icons.event,
                      ),
                    if (spot.isTemporary &&
                        !spot.isTemporaryLocationAvailableNow)
                      _SmallTag(
                        label: spot.temporaryLocationAvailableAtLabel,
                        icon: Icons.visibility_off_outlined,
                      ),
                    for (final category in spot.categories)
                      _SmallTag(label: category, icon: Icons.local_offer),
                  ],
                ),
                const SizedBox(height: 22),
                SaveSpotButton(spot: spot),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (spot.isTemporary &&
                          !spot.isTemporaryLocationAvailableNow) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Colors.redAccent,
                            content: Text(
                              'Location not available yet',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                        return;
                      }

                      mapFocusRequest.value = MapFocusRequest(
                        spotId: spot.id,
                        coordinates: spot.coordinates,
                      );

                      // Do not pop back to the first route here. Some users reach
                      // MainScreen from Splash/Login, so route.isFirst can be the
                      // login screen. Only close the spot details page; MainScreen
                      // listens to mapFocusRequest and switches to the Map tab.
                      Navigator.of(context).maybePop();
                    },
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Show on map'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                      elevation: 10,
                      shadowColor: blue.withValues(alpha: 0.28),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SpotRouteActions(spot: spot),
                if (spot.supportsContacts) ...[
                  const SizedBox(height: 24),
                  SpotBusinessStatusCard(spot: spot),
                ],
                if (currentUserCanManageSpotBusiness(spot)) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final updatedSpot = await Navigator.push<CarSpot>(
                          context,
                          appPageRoute(
                            builder: (_) =>
                                ServiceSpotBusinessEditScreen(spot: spot),
                          ),
                        );

                        if (updatedSpot != null && mounted) {
                          setState(() => spot = updatedSpot);
                        }
                      },
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Edit Service Info'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: blue,
                        side: const BorderSide(color: blue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
                if (spot.hasContactInfo) ...[
                  const SizedBox(height: 24),
                  SpotContactSection(spot: spot),
                ],
                const SizedBox(height: 24),
                const Text(
                  'Video link',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => launchExternalUrl(context, spot.reelLink),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: panelGlass,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            spot.reelLink.isEmpty
                                ? 'No video link added'
                                : spot.reelLink,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.open_in_new, color: blue, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SpotReviewsSection(spot: spot),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SpotOwnerBadge extends StatelessWidget {
  final CarSpot spot;

  const SpotOwnerBadge({super.key, required this.spot});

  String get ownerLabel {
    final username = spot.ownerUsername.trim();

    if (username.isNotEmpty) {
      final handle = displayUsername(username);
      return 'Owner $handle';
    }

    return 'Owner';
  }

  @override
  Widget build(BuildContext context) {
    final badge = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 170),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: blue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: blue.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.manage_accounts, color: blue, size: 15),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                ownerLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (spot.ownerUid.trim().isEmpty) {
      return badge;
    }

    return InkWell(
      onTap: () => openUserProfile(
        context,
        uid: spot.ownerUid,
        fallbackUsername: spot.ownerUsername,
      ),
      borderRadius: BorderRadius.circular(999),
      child: badge,
    );
  }
}

Future<void> launchContactUri(BuildContext context, Uri uri) async {
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'Could not open this contact.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

Uri instagramContactUri(String value) {
  final trimmed = value.trim();
  final parsed = Uri.tryParse(trimmed);

  if (parsed != null && parsed.hasScheme) {
    return parsed;
  }

  var handle = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
  handle = handle.replaceFirst(RegExp(r'^(www\.)?instagram\.com/?'), '');
  handle = handle.replaceAll(RegExp(r'^/+'), '');

  return Uri.https('instagram.com', handle.isEmpty ? '/' : '/$handle');
}

class SpotBusinessStatus {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const SpotBusinessStatus({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

String nextOpeningLabel(Map<int, OpeningHoursData> openingHours, int weekday) {
  for (var offset = 1; offset <= 7; offset++) {
    final nextWeekday = ((weekday - 1 + offset) % 7) + 1;
    final nextDay = openingHours[nextWeekday];
    if (nextDay != null && nextDay.isOpen) {
      return '${weekdayLabels[nextWeekday] ?? 'Next day'} at ${nextDay.opensAt}';
    }
  }

  return 'No upcoming opening hours';
}

SpotBusinessStatus businessStatusForSpot(CarSpot spot) {
  if (spot.openingHours.isEmpty) {
    return const SpotBusinessStatus(
      title: 'Hours not added',
      subtitle: 'The owner has not added opening hours yet.',
      icon: Icons.schedule,
      color: Colors.white54,
    );
  }

  final now = DateTime.now();
  final today = spot.openingHours[now.weekday];
  final weekdayName = weekdayLabels[now.weekday] ?? 'Today';

  if (today == null || !today.isOpen) {
    return SpotBusinessStatus(
      title: 'Closed today',
      subtitle: '$weekdayName is marked as closed.',
      icon: Icons.close,
      color: Colors.redAccent,
    );
  }

  final opensAt = minutesFromClockText(today.opensAt);
  final closesAt = minutesFromClockText(today.closesAt);
  final nowMinutes = now.hour * 60 + now.minute;

  if (opensAt == null || closesAt == null) {
    return const SpotBusinessStatus(
      title: 'Hours need update',
      subtitle: 'Opening hours are not formatted correctly.',
      icon: Icons.error_outline,
      color: Colors.orangeAccent,
    );
  }

  final isOpenNow = closesAt > opensAt
      ? nowMinutes >= opensAt && nowMinutes < closesAt
      : nowMinutes >= opensAt || nowMinutes < closesAt;

  if (isOpenNow) {
    return SpotBusinessStatus(
      title: 'Open now',
      subtitle: 'Today ${today.opensAt} - ${today.closesAt}',
      icon: Icons.check,
      color: Colors.greenAccent,
    );
  }

  if (closesAt > opensAt && nowMinutes < opensAt) {
    return SpotBusinessStatus(
      title: 'Closed now',
      subtitle: 'Opens today at ${today.opensAt}',
      icon: Icons.close,
      color: Colors.redAccent,
    );
  }

  return SpotBusinessStatus(
    title: 'Closed now',
    subtitle: 'Opens ${nextOpeningLabel(spot.openingHours, now.weekday)}',
    icon: Icons.close,
    color: Colors.redAccent,
  );
}

bool spotIsClosedNow(CarSpot spot) {
  if (!spot.supportsContacts || !spot.hasOpeningHours) {
    return false;
  }

  final status = businessStatusForSpot(spot);
  return status.title == 'Closed now' || status.title == 'Closed today';
}

class SpotBusinessStatusCard extends StatelessWidget {
  final CarSpot spot;

  const SpotBusinessStatusCard({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    final status = businessStatusForSpot(spot);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: status.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: status.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(status.icon, color: status.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.title,
                  style: TextStyle(
                    color: status.color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  status.subtitle,
                  style: const TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SpotContactSection extends StatelessWidget {
  final CarSpot spot;

  const SpotContactSection({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contacts',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: panelGlass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              if (spot.contactPhone.trim().isNotEmpty)
                _SpotContactTile(
                  icon: Icons.phone,
                  label: 'Phone',
                  value: spot.contactPhone,
                  onTap: () => launchContactUri(
                    context,
                    Uri(scheme: 'tel', path: spot.contactPhone.trim()),
                  ),
                ),
              if (spot.contactInstagram.trim().isNotEmpty)
                _SpotContactTile(
                  icon: Icons.alternate_email,
                  label: 'Instagram',
                  value: spot.contactInstagram,
                  onTap: () => launchContactUri(
                    context,
                    instagramContactUri(spot.contactInstagram),
                  ),
                ),
              if (spot.contactEmail.trim().isNotEmpty)
                _SpotContactTile(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: spot.contactEmail,
                  onTap: () => launchContactUri(
                    context,
                    Uri(scheme: 'mailto', path: spot.contactEmail.trim()),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpotContactTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SpotContactTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: blue, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.open_in_new, color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }
}

class SpotDetailEngagementPanel extends StatefulWidget {
  final CarSpot spot;
  final ValueChanged<double>? onRatingChanged;

  const SpotDetailEngagementPanel({
    super.key,
    required this.spot,
    this.onRatingChanged,
  });

  @override
  State<SpotDetailEngagementPanel> createState() =>
      _SpotDetailEngagementPanelState();
}

class _SpotDetailEngagementPanelState extends State<SpotDetailEngagementPanel> {
  bool isSavingRating = false;

  Future<void> submitRating(int rating) async {
    setState(() => isSavingRating = true);

    try {
      final updatedRating = await saveSpotRating(
        spot: widget.spot,
        rating: rating,
      );

      if (!mounted) {
        return;
      }

      if (updatedRating != null) {
        widget.onRatingChanged?.call(updatedRating);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
            'Rating saved.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      final code = error is FirebaseException ? error.code : error.toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not save rating: $code',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSavingRating = false);
      }
    }
  }

  Widget starButton(int value, int currentRating) {
    final selected = value <= currentRating;

    return IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: isSavingRating ? null : () => submitRating(value),
      icon: Icon(
        selected ? Icons.star : Icons.star_border,
        color: selected ? blue : Colors.white38,
        size: 26,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star, color: blue, size: 19),
              const SizedBox(width: 7),
              Text(
                '${widget.spot.rating.toStringAsFixed(1)} spot rating',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              StreamBuilder<bool>(
                stream: watchCurrentUserLikedSpot(widget.spot),
                builder: (context, likedSnapshot) {
                  final liked = likedSnapshot.data ?? false;

                  return StreamBuilder<int>(
                    stream: watchSpotLikeCount(widget.spot),
                    builder: (context, countSnapshot) {
                      final likeCount = countSnapshot.data ?? 0;

                      return InkWell(
                        onTap: () =>
                            toggleSpotLike(context, widget.spot, liked),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: liked
                                ? Colors.redAccent.withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: liked ? Colors.redAccent : Colors.white12,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                liked ? Icons.favorite : Icons.favorite_border,
                                color: liked
                                    ? Colors.redAccent
                                    : Colors.white70,
                                size: 23,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                liked ? 'Liked' : 'Like',
                                style: TextStyle(
                                  color: liked
                                      ? Colors.redAccent
                                      : Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$likeCount',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Your rating',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
            ),
          ),
          StreamBuilder<int>(
            stream: watchCurrentUserSpotRating(widget.spot),
            builder: (context, ratingSnapshot) {
              final currentRating = ratingSnapshot.data ?? 0;

              return Row(
                children: [
                  for (var i = 1; i <= 5; i++) starButton(i, currentRating),
                  if (isSavingRating) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: blue,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class SpotRouteActions extends StatefulWidget {
  final CarSpot spot;

  const SpotRouteActions({super.key, required this.spot});

  @override
  State<SpotRouteActions> createState() => _SpotRouteActionsState();
}

class _SpotRouteActionsState extends State<SpotRouteActions> {
  bool isLoadingDistance = false;
  double? distanceKm;

  @override
  void initState() {
    super.initState();
    loadDistance();
  }

  Future<void> loadDistance() async {
    if (widget.spot.isTemporary &&
        !widget.spot.isTemporaryLocationAvailableNow) {
      return;
    }

    if (isLoadingDistance) {
      return;
    }

    setState(() => isLoadingDistance = true);

    final position = await getCurrentPhoneLocation(context);

    if (!mounted) {
      return;
    }

    setState(() {
      distanceKm = position == null
          ? null
          : distanceToSpotInKm(position, widget.spot);
      isLoadingDistance = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.spot.isTemporary &&
        !widget.spot.isTemporaryLocationAvailableNow) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.visibility_off_outlined,
                color: Colors.orangeAccent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Location not available yet',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.spot.temporaryLocationAvailableAtLabel,
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final distanceText = distanceKm == null
        ? (isLoadingDistance ? 'Checking distance...' : 'Distance unavailable')
        : '${formatDistanceKm(distanceKm!)} away';
    final timeText = distanceKm == null
        ? 'Open route'
        : estimateDriveTime(distanceKm!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.route, color: blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  distanceText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(timeText, style: const TextStyle(color: Colors.white54)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 42,
            child: ElevatedButton.icon(
              onPressed: () => openWazeRoute(context, widget.spot),
              icon: const Icon(Icons.navigation, size: 17),
              label: const Text('Waze'),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SpotReviewsSection extends StatefulWidget {
  final CarSpot spot;

  const SpotReviewsSection({super.key, required this.spot});

  @override
  State<SpotReviewsSection> createState() => _SpotReviewsSectionState();
}

class _SpotReviewsSectionState extends State<SpotReviewsSection> {
  final commentController = TextEditingController();
  bool isSaving = false;

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }

  Future<void> submitComment() async {
    final comment = commentController.text.trim();

    if (comment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Write a comment first.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (isSaving) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => isSaving = true);

    try {
      await saveSpotReview(spot: widget.spot, comment: comment);

      if (!mounted) {
        return;
      }

      commentController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
            'Comment posted.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      final code = error is FirebaseException ? error.code : error.toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not save comment: $code',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SpotReviewData>>(
      stream: watchSpotReviews(widget.spot),
      builder: (context, snapshot) {
        final reviews = snapshot.data ?? const <SpotReviewData>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Comments',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  reviews.isEmpty
                      ? '0 comments'
                      : '${reviews.length} ${reviews.length == 1 ? 'comment' : 'comments'}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: panelGlass,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: commentController,
                    minLines: 2,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: trText('Write a comment about this spot'),
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: blue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: isSaving ? null : submitComment,
                      icon: Icon(
                        isSaving ? Icons.hourglass_bottom : Icons.send,
                      ),
                      label: Text(isSaving ? 'Saving...' : 'Post Comment'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (reviews.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: panelGlass,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Text(
                  'No comments yet. Be the first to comment on this spot.',
                  style: TextStyle(color: Colors.white54),
                ),
              )
            else
              for (final review in reviews) ...[
                SpotReviewCard(spot: widget.spot, review: review),
                const SizedBox(height: 10),
              ],
          ],
        );
      },
    );
  }
}

class SpotReviewCard extends StatelessWidget {
  final CarSpot spot;
  final SpotReviewData review;

  const SpotReviewCard({super.key, required this.spot, required this.review});

  Future<void> _showEditDialog(BuildContext context) async {
    final commentController = TextEditingController(text: review.comment);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: const Text(
            'Edit comment',
            style: TextStyle(color: Colors.white),
          ),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: commentController,
                    minLines: 3,
                    maxLines: 5,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: trText('Edit your comment'),
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (commentController.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (saved != true) {
      return;
    }

    final newComment = commentController.text.trim();

    try {
      await editSpotReview(spot: spot, review: review, comment: newComment);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: blue,
            content: Text(
              'Comment updated.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        final code = error is FirebaseException ? error.code : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Could not update comment: $code',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: const Text(
            'Delete comment',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Are you sure you want to delete this comment?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await deleteSpotReview(spot: spot, review: review);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: blue,
            content: Text(
              'Comment deleted.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        final code = error is FirebaseException ? error.code : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Could not delete comment: $code',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = FirebaseAuth.instance.currentUser?.uid == review.userId;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: review.userId.trim().isEmpty
                      ? null
                      : () => openUserProfile(
                          context,
                          uid: review.userId,
                          fallbackUsername: review.username,
                        ),
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      displayUsername(review.username),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: blue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                formatShortDate(review.createdAt),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            review.comment,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              StreamBuilder<bool>(
                stream: watchCurrentUserLikedComment(review),
                builder: (context, likedSnapshot) {
                  final liked = likedSnapshot.data ?? false;

                  return StreamBuilder<int>(
                    stream: watchCommentLikeCount(review),
                    builder: (context, countSnapshot) {
                      final likeCount = countSnapshot.data ?? 0;

                      return InkWell(
                        onTap: () => toggleCommentLike(context, review, liked),
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                liked ? Icons.favorite : Icons.favorite_border,
                                color: liked
                                    ? Colors.redAccent
                                    : Colors.white54,
                                size: 17,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '$likeCount',
                                style: TextStyle(
                                  color: liked
                                      ? Colors.redAccent
                                      : Colors.white54,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              const Spacer(),
              if (canManage) ...[
                IconButton(
                  onPressed: () => _showEditDialog(context),
                  icon: const Icon(Icons.edit, color: Colors.white54, size: 18),
                  tooltip: 'Edit comment',
                ),
                IconButton(
                  onPressed: () => _showDeleteDialog(context),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.white54,
                    size: 18,
                  ),
                  tooltip: 'Delete comment',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class SpotPhoto extends StatelessWidget {
  final CarSpot spot;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const SpotPhoto({
    super.key,
    required this.spot,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final sources = spotPhotoSources(spot);
    final photo = sources.isEmpty
        ? _SpotPhotoPlaceholder(width: width, height: height)
        : spotPhotoImage(sources.first, width: width, height: height, fit: fit);

    if (borderRadius == null) {
      return photo;
    }

    return ClipRRect(borderRadius: borderRadius!, child: photo);
  }
}

class _SpotPhotoPlaceholder extends StatelessWidget {
  final double? width;
  final double? height;

  const _SpotPhotoPlaceholder({this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Colors.white10,
      child: const Icon(Icons.directions_car, color: blue),
    );
  }
}

class _SmallTag extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SmallTag({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: blue, size: 14),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 98),
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotCategoryDropdown extends StatelessWidget {
  final String value;
  final List<String> categories;
  final ValueChanged<String?> onChanged;

  const _SpotCategoryDropdown({
    required this.value,
    required this.categories,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: panel,
      iconEnabledColor: blue,
      decoration: InputDecoration(
        labelText: trText('Category'),
        labelStyle: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(10),
          child: Image.asset(
            spotIconAssetPathForCategory(value),
            width: 24,
            height: 24,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.local_offer, color: blue),
          ),
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: blue, width: 1.4),
        ),
      ),
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      items: categories.map((category) {
        return DropdownMenuItem<String>(
          value: category,
          child: Row(
            children: [
              Image.asset(
                spotIconAssetPathForCategory(category),
                width: 30,
                height: 30,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.local_offer, color: blue, size: 20),
              ),
              const SizedBox(width: 10),
              Text(category),
            ],
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}

class AddSpotScreen extends StatefulWidget {
  const AddSpotScreen({super.key});

  @override
  State<AddSpotScreen> createState() => _AddSpotScreenState();
}

class _AddSpotScreenState extends State<AddSpotScreen> {
  final nameController = TextEditingController();
  final cityController = TextEditingController();
  final addressController = TextEditingController();
  final descriptionController = TextEditingController();
  final reelController = TextEditingController();
  final phoneController = TextEditingController();
  final instagramController = TextEditingController();
  final emailController = TextEditingController();
  final addedByController = TextEditingController();

  final categoryOptions = spotCategoryOptions;

  String selectedCategory = 'Photo';
  LatLng? selectedLocation;
  String detectedCityCountry = 'Choose location to detect city/country';
  bool isDetectingCityCountry = false;
  bool isUsingCurrentLocation = false;
  final List<String> selectedPhotoPaths = [];
  bool verifiedOnlySpot = false;
  bool isTemporarySpot = false;
  DateTime? temporaryStartsAt;
  DateTime? temporaryExpiresAt;
  bool temporaryShowOnMapAtEnabled = false;
  DateTime? temporaryShowOnMapAt;
  Map<int, OpeningHoursData> openingHours = defaultServiceOpeningHours();
  SpotOwnerAssignment? selectedOwner;
  bool isSubmitting = false;

  @override
  void initState() {
    super.initState();
    addedByController.text = currentUser.username;
  }

  @override
  void dispose() {
    nameController.dispose();
    cityController.dispose();
    addressController.dispose();
    descriptionController.dispose();
    reelController.dispose();
    phoneController.dispose();
    instagramController.dispose();
    emailController.dispose();
    addedByController.dispose();
    super.dispose();
  }

  Future<void> applySelectedLocation(LatLng location) async {
    setState(() {
      selectedLocation = location;
      detectedCityCountry = 'Detecting city/country...';
      isDetectingCityCountry = true;
    });

    final cityCountry = await detectCityCountryForCoordinates(location);

    if (!mounted) {
      return;
    }

    setState(() {
      detectedCityCountry = cityCountry;
      isDetectingCityCountry = false;
    });
  }

  Future<void> chooseLocation() async {
    FocusScope.of(context).unfocus();

    final location = await Navigator.push<LatLng>(
      context,
      appPageRoute(
        builder: (_) => LocationPickerScreen(initialLocation: selectedLocation),
      ),
    );

    if (!mounted || location == null) {
      return;
    }

    await applySelectedLocation(location);
  }

  Future<void> findExactAddress() async {
    FocusScope.of(context).unfocus();

    final address = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: const Text('Find exact address'),
          content: TextField(
            controller: addressController,
            autofocus: true,
            keyboardType: TextInputType.streetAddress,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: trText('Street, city, country'),
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: blue),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: blue),
              ),
            ),
            onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, addressController.text.trim()),
              child: const Text('Find'),
            ),
          ],
        );
      },
    );

    if (!mounted || address == null || address.trim().isEmpty) {
      return;
    }

    try {
      setState(() {
        detectedCityCountry = 'Finding address...';
        isDetectingCityCountry = true;
      });

      final locations = await locationFromAddress(address.trim());

      if (!mounted) {
        return;
      }

      if (locations.isEmpty) {
        setState(() {
          detectedCityCountry = selectedLocation == null
              ? 'Choose location to detect city/country'
              : detectedCityCountry;
          isDetectingCityCountry = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Address not found. Try adding city and country.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      final first = locations.first;
      await applySelectedLocation(safeLatLng(first.latitude, first.longitude));
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        detectedCityCountry = selectedLocation == null
            ? 'Choose location to detect city/country'
            : detectedCityCountry;
        isDetectingCityCountry = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not find that address. $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  Future<void> useCurrentLocation() async {
    FocusScope.of(context).unfocus();

    if (isUsingCurrentLocation) {
      return;
    }

    final previousDetectedCityCountry = detectedCityCountry;

    setState(() {
      isUsingCurrentLocation = true;
      isDetectingCityCountry = true;
      detectedCityCountry = 'Getting current location...';
    });

    void restoreLocationState() {
      if (!mounted) {
        return;
      }

      setState(() {
        isUsingCurrentLocation = false;
        isDetectingCityCountry = false;
        detectedCityCountry = selectedLocation == null
            ? 'Choose location to detect city/country'
            : previousDetectedCityCountry;
      });
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!mounted) {
        return;
      }

      if (!serviceEnabled) {
        restoreLocationState();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Turn on phone location to use your current position.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (!mounted) {
        return;
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        restoreLocationState();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Location permission is needed to use your current position.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) {
        return;
      }

      final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }

      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (mounted && placemarks.isNotEmpty) {
          final place = placemarks.first;
          final addressParts =
              [place.street, place.subLocality, place.locality, place.country]
                  .whereType<String>()
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .toList();

          if (addressParts.isNotEmpty) {
            addressController.text = addressParts.join(', ');
          }
        }
      } catch (_) {
        // Address text is optional. The coordinates are enough to create a spot.
      }

      await applySelectedLocation(location);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
            'Current location selected for this spot.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isDetectingCityCountry = false;
        detectedCityCountry = selectedLocation == null
            ? 'Choose location to detect city/country'
            : previousDetectedCityCountry;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not use current location. $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isUsingCurrentLocation = false);
      }
    }
  }

  Future<void> choosePhoto() async {
    FocusScope.of(context).unfocus();

    if (selectedPhotoPaths.length >= maxSpotGalleryPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Maximum 4 photos per spot.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final path = await pickPhotoFromPhone(context);

    if (!mounted || path == null) {
      return;
    }

    if (selectedPhotoPaths.contains(path)) {
      return;
    }

    setState(() => selectedPhotoPaths.add(path));
  }

  void removePhotoAt(int index) {
    if (index < 0 || index >= selectedPhotoPaths.length) {
      return;
    }

    setState(() => selectedPhotoPaths.removeAt(index));
  }

  Future<DateTime?> pickTemporaryDateTime(DateTime? initialValue) async {
    final now = DateTime.now();
    final initial = initialValue ?? now.add(const Duration(hours: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(data: ThemeData.dark(), child: child!);
      },
    );

    if (date == null || !mounted) {
      return null;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) {
        return Theme(data: ThemeData.dark(), child: child!);
      },
    );

    if (time == null) {
      return null;
    }

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> chooseTemporaryStart() async {
    final value = await pickTemporaryDateTime(temporaryStartsAt);

    if (!mounted || value == null) {
      return;
    }

    setState(() {
      temporaryStartsAt = value;
      if (temporaryExpiresAt == null ||
          !temporaryExpiresAt!.isAfter(value) ||
          temporaryExpiresAt!.difference(value) > maxTemporarySpotDuration) {
        temporaryExpiresAt = value.add(const Duration(hours: 3));
      }
    });
  }

  Future<void> chooseTemporaryEnd() async {
    final fallback = temporaryStartsAt?.add(const Duration(hours: 3));
    final value = await pickTemporaryDateTime(temporaryExpiresAt ?? fallback);

    if (!mounted || value == null) {
      return;
    }

    setState(() => temporaryExpiresAt = value);
  }

  Future<void> chooseTemporaryShowOnMapAt() async {
    final fallback = temporaryStartsAt == null
        ? DateTime.now().add(const Duration(hours: 1))
        : DateTime(
            temporaryStartsAt!.year,
            temporaryStartsAt!.month,
            temporaryStartsAt!.day,
          );
    final value = await pickTemporaryDateTime(temporaryShowOnMapAt ?? fallback);

    if (!mounted || value == null) {
      return;
    }

    setState(() => temporaryShowOnMapAt = value);
  }

  void resetSpotFormAfterSubmit() {
    nameController.clear();
    cityController.clear();
    addressController.clear();
    descriptionController.clear();
    reelController.clear();
    phoneController.clear();
    instagramController.clear();
    emailController.clear();
    addedByController.text = currentUser.username;

    setState(() {
      selectedCategory = 'Photo';
      selectedLocation = null;
      detectedCityCountry = 'Choose location to detect city/country';
      isDetectingCityCountry = false;
      selectedPhotoPaths.clear();
      verifiedOnlySpot = false;
      isTemporarySpot = false;
      temporaryStartsAt = null;
      temporaryExpiresAt = null;
      temporaryShowOnMapAtEnabled = false;
      temporaryShowOnMapAt = null;
      openingHours = defaultServiceOpeningHours();
      selectedOwner = null;
    });
  }

  Future<void> submitSpot() async {
    FocusScope.of(context).unfocus();

    if (isSubmitting) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Sign in with Google before submitting a spot.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final cleanSpotName = nameController.text.trim();
    final cleanDescription = descriptionController.text.trim();
    final allowedSpotNamePattern = RegExp(
      r"^[A-Za-z0-9ĀāČčĒēĢģĪīĶķĻļŅņŠšŪūŽž .,'’&()\/-]+$",
    );

    if (cleanSpotName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Spot name is required.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (!allowedSpotNamePattern.hasMatch(cleanSpotName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Spot name can use only English or Latvian letters, numbers, spaces, and simple punctuation.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Location is required. Pin it on the map, find exact address, or use current location first.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (cleanDescription.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Description is required.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (selectedPhotoPaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Upload at least 1 photo before creating the spot.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (isTemporarySpot) {
      final startsAt = temporaryStartsAt;
      final expiresAt = temporaryExpiresAt;

      if (startsAt == null || expiresAt == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Choose both start and end time for a temporary spot.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      if (!expiresAt.isAfter(startsAt)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'End time must be after start time.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      if (expiresAt.difference(startsAt) > maxTemporarySpotDuration) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Temporary spots can be active for maximum 12 hours.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      if (!expiresAt.isAfter(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'End time must be in the future.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      if (temporaryShowOnMapAtEnabled) {
        final showOnMapAt = temporaryShowOnMapAt;
        if (showOnMapAt == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text(
                'Choose when the temporary spot location should appear on the map.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
          return;
        }

        if (!showOnMapAt.isBefore(expiresAt)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text(
                'Show on map time must be before the end time.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
          return;
        }
      }
    }

    final location = selectedLocation!;

    if (!isTemporarySpot) {
      final nearbySpot = await findNearbySpotBlockingPermanentSpotCreation(
        location,
      );

      if (nearbySpot != null) {
        final distance = distanceBetweenLatLngMeters(
          location,
          nearbySpot.coordinates,
        );
        final distanceLabel = distance >= 1000
            ? '${(distance / 1000).toStringAsFixed(1)} km'
            : '${distance.round()} m';

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Permanent spots must be at least ${minimumPermanentSpotDistanceMeters.round()} m apart. "${nearbySpot.name}" is $distanceLabel away. Temporary spots are allowed to overlap existing spots.',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }
    }

    final categories = [selectedCategory];
    final supportsContacts = spotCategorySupportsContacts(selectedCategory);
    final owner = supportsContacts && userRoleIsStaff(currentUser.role)
        ? selectedOwner
        : null;

    final isAdminCreatedSpot = userRoleIsStaff(currentUser.role);
    final initialStatus = isAdminCreatedSpot
        ? SpotStatus.approved
        : SpotStatus.pending;
    final spotRef = spotsCollection().doc();

    var newSpot = CarSpot(
      id: spotRef.id,
      name: cleanSpotName,
      cityCountry:
          detectedCityCountry.trim().isEmpty ||
              detectedCityCountry == 'Choose location to detect city/country' ||
              detectedCityCountry == 'Detecting city/country...'
          ? 'Unknown location'
          : detectedCityCountry.trim(),
      coordinates: location,
      description: cleanDescription,
      categories: categories,
      rating: isAdminCreatedSpot ? 4.5 : 0,
      photoUrl: '',
      localPhotoPath: selectedPhotoPaths.isEmpty
          ? null
          : selectedPhotoPaths.first,
      reelLink: reelController.text.trim(),
      contactPhone: supportsContacts ? phoneController.text.trim() : '',
      contactInstagram: supportsContacts ? instagramController.text.trim() : '',
      contactEmail: supportsContacts ? emailController.text.trim() : '',
      openingHours: supportsContacts ? openingHours : const {},
      ownerUid: supportsContacts ? (owner?.uid ?? '') : '',
      ownerUsername: supportsContacts ? (owner?.username ?? '') : '',
      bestTime: 'Not reviewed',
      parking: 'Not reviewed',
      roadQuality: 'Not reviewed',
      lowCarFriendly: false,
      policeRisk: 'Not reviewed',
      traffic: 'Not reviewed',
      lighting: 'Not reviewed',
      crowd: 'Not reviewed',
      addedBy: currentUser.username,
      addedByUid: firebaseUser.uid,
      status: initialStatus,
      isTemporary: isTemporarySpot,
      startsAtMillis: isTemporarySpot
          ? temporaryStartsAt!.millisecondsSinceEpoch
          : null,
      expiresAtMillis: isTemporarySpot
          ? temporaryExpiresAt!.millisecondsSinceEpoch
          : null,
      showOnMapAtMillis: isTemporarySpot && temporaryShowOnMapAtEnabled
          ? temporaryShowOnMapAt!.millisecondsSinceEpoch
          : null,
      verifiedOnly: verifiedOnlySpot,
    );

    setState(() => isSubmitting = true);

    try {
      final uploadedPhotoUrls = <String>[];

      for (var index = 0; index < selectedPhotoPaths.length; index++) {
        final uploadedUrl = await uploadSpotPhoto(
          spotId: spotRef.id,
          localPhotoPath: selectedPhotoPaths[index],
          userId: firebaseUser.uid,
          photoIndex: index,
        );
        uploadedPhotoUrls.add(uploadedUrl);
      }

      newSpot = newSpot.copyWith(
        photoUrl: uploadedPhotoUrls.isEmpty ? '' : uploadedPhotoUrls.first,
        photoUrls: uploadedPhotoUrls,
      );
      await spotRef.set(spotToFirestoreData(newSpot, includeCreatedAt: true));

      if (isAdminCreatedSpot) {
        await createNewSpotNotificationForUsers(newSpot);
        await sendPushNotificationEvent({
          'type': newSpot.isTemporary ? 'temporary_event' : 'new_spot',
          'spotId': spotRef.id,
        });
      }

      if (isAdminCreatedSpot && newSpot.categories.contains('Meet')) {
        await createMeetSpotNotificationsForNearbyUsers(newSpot);
      }

      if (!isAdminCreatedSpot) {
        await createAdminSpotReviewNotification(newSpot);
      }

      final savedSpot = await spotRef.get(
        const GetOptions(source: Source.server),
      );

      if (!savedSpot.exists) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'spot-not-found-after-save',
          message: 'Firebase did not return the saved spot.',
        );
      }

      await refreshFirebaseSpotsFromServer();

      if (!mounted) {
        return;
      }

      resetSpotFormAfterSubmit();

      final message = isAdminCreatedSpot
          ? 'Admin spot added. It is live now.'
          : 'Spot submitted for review. Admins have been notified.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: blue,
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Firebase did not save the spot/photo: ${error.code}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsAppBarLogo(),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: ccsAppBarActions(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: panelGlass,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: blue.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.add_location_alt, color: blue),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Spot',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Admins publish instantly. User spots wait for review.',
                        style: TextStyle(color: Colors.white54, height: 1.3),
                      ),
                    ],
                  ),
                ),
                _PendingBadge(
                  status: userRoleIsStaff(currentUser.role)
                      ? SpotStatus.approved
                      : SpotStatus.pending,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _AddSpotSection(
            title: 'Basic info',
            children: [
              _CcsTextField(
                controller: nameController,
                label: 'Spot name',
                hint: 'Andrejsala Harbor',
                icon: Icons.place,
              ),
              _LocationPickerField(
                title: 'Pin on the map',
                icon: Icons.map,
                hasLocation: selectedLocation != null,
                subtitle: isDetectingCityCountry
                    ? 'Detecting city/country...'
                    : selectedLocation == null
                    ? 'Choose the spot on map'
                    : detectedCityCountry,
                onTap: chooseLocation,
              ),
              const SizedBox(height: 10),
              _LocationPickerField(
                title: 'Find exact address',
                icon: Icons.search,
                hasLocation: selectedLocation != null,
                subtitle: selectedLocation == null
                    ? 'Type an address and place the pin automatically'
                    : 'Current pin: $detectedCityCountry',
                onTap: findExactAddress,
              ),
              const SizedBox(height: 10),
              _LocationPickerField(
                title: 'Use current location',
                icon: Icons.my_location,
                hasLocation: selectedLocation != null,
                subtitle: isUsingCurrentLocation
                    ? 'Getting your GPS position...'
                    : selectedLocation == null
                    ? 'Use your phone GPS position'
                    : 'Replace pin with your current GPS position',
                onTap: useCurrentLocation,
              ),
              _CcsTextField(
                controller: descriptionController,
                label: 'Description',
                hint: 'What makes this spot good for car photos?',
                icon: Icons.notes,
                maxLines: 4,
              ),
            ],
          ),
          if (currentUserCanUseVerifiedOnlySpots) ...[
            const SizedBox(height: 16),
            _AddSpotSection(
              title: 'Visibility',
              children: [
                _SettingsSwitchTile(
                  icon: Icons.verified_user,
                  title: 'Verified only',
                  subtitle:
                      'Only verified users and admins can see this spot after approval',
                  value: verifiedOnlySpot,
                  onChanged: (value) =>
                      setState(() => verifiedOnlySpot = value),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _AddSpotSection(
            title: 'Temporary schedule',
            children: [
              _TemporarySpotScheduleCard(
                enabled: isTemporarySpot,
                startsAt: temporaryStartsAt,
                expiresAt: temporaryExpiresAt,
                showOnMapAtEnabled: temporaryShowOnMapAtEnabled,
                showOnMapAt: temporaryShowOnMapAt,
                onEnabledChanged: (value) {
                  setState(() {
                    isTemporarySpot = value;
                    if (value && temporaryStartsAt == null) {
                      final start = DateTime.now().add(
                        const Duration(hours: 1),
                      );
                      temporaryStartsAt = start;
                      temporaryExpiresAt = start.add(const Duration(hours: 3));
                    }
                    if (!value) {
                      temporaryShowOnMapAtEnabled = false;
                      temporaryShowOnMapAt = null;
                    }
                  });
                },
                onShowOnMapAtEnabledChanged: (value) {
                  setState(() {
                    temporaryShowOnMapAtEnabled = value;
                    if (value &&
                        temporaryShowOnMapAt == null &&
                        temporaryStartsAt != null) {
                      temporaryShowOnMapAt = DateTime(
                        temporaryStartsAt!.year,
                        temporaryStartsAt!.month,
                        temporaryStartsAt!.day,
                      );
                    }
                    if (!value) {
                      temporaryShowOnMapAt = null;
                    }
                  });
                },
                onPickStart: chooseTemporaryStart,
                onPickEnd: chooseTemporaryEnd,
                onPickShowOnMapAt: chooseTemporaryShowOnMapAt,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AddSpotSection(
            title: 'Categories',
            children: [
              _SpotCategoryDropdown(
                value: selectedCategory,
                categories: categoryOptions,
                onChanged: (category) {
                  if (category == null) {
                    return;
                  }

                  setState(() => selectedCategory = category);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (spotCategorySupportsContacts(selectedCategory)) ...[
            _AddSpotSection(
              title: 'Contacts',
              children: [
                _CcsTextField(
                  controller: phoneController,
                  label: 'Phone',
                  hint: '+371 20 000 000',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
                _CcsTextField(
                  controller: instagramController,
                  label: 'Instagram',
                  hint: '@ccs.lv or https://instagram.com/ccs.lv',
                  icon: Icons.alternate_email,
                  keyboardType: TextInputType.url,
                ),
                _CcsTextField(
                  controller: emailController,
                  label: 'Email',
                  hint: 'hello@ccs.lv',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                if (userRoleIsStaff(currentUser.role))
                  SpotOwnerSelector(
                    selectedOwner: selectedOwner,
                    onChanged: (owner) => setState(() => selectedOwner = owner),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _AddSpotSection(
              title: 'Opening hours',
              children: [
                OpeningHoursEditor(
                  openingHours: openingHours,
                  onChanged: (value) => setState(() => openingHours = value),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          _AddSpotSection(
            title: 'Media',
            children: [
              _SpotPhotoPickerField(
                photoPaths: selectedPhotoPaths,
                onAddPhoto: choosePhoto,
                onRemovePhoto: removePhotoAt,
              ),
              _CcsTextField(
                controller: reelController,
                label: 'Instagram / TikTok video link',
                hint: 'https://instagram.com/reel/...',
                icon: Icons.play_circle,
                keyboardType: TextInputType.url,
              ),
              _CcsTextField(
                controller: addedByController,
                label: 'Added by',
                hint: 'Your profile nickname',
                icon: Icons.person,
                readOnly: true,
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: isSubmitting ? null : submitSpot,
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isSubmitting ? Icons.hourglass_top : Icons.send),
                  const SizedBox(width: 10),
                  Text(
                    isSubmitting
                        ? (userRoleIsStaff(currentUser.role)
                              ? 'Creating spot...'
                              : 'Submitting for review...')
                        : (userRoleIsStaff(currentUser.role)
                              ? 'Create Spot'
                              : 'Submit for Review'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _MySubmissionsSection(),
        ],
      ),
    );
  }
}

class _PendingBadge extends StatelessWidget {
  final SpotStatus status;

  const _PendingBadge({this.status = SpotStatus.pending});

  String get label {
    switch (status) {
      case SpotStatus.pending:
        return 'pending';
      case SpotStatus.approved:
        return 'live';
      case SpotStatus.rejected:
        return 'rejected';
      case SpotStatus.edited:
        return 'edited';
    }
  }

  Color get color {
    switch (status) {
      case SpotStatus.pending:
        return blue;
      case SpotStatus.approved:
        return Colors.greenAccent;
      case SpotStatus.rejected:
        return Colors.redAccent;
      case SpotStatus.edited:
        return Colors.orangeAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MySubmissionsSection extends StatelessWidget {
  const _MySubmissionsSection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CarSpot>>(
      valueListenable: submittedSpots,
      builder: (context, spots, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: panelGlass,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'My submissions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your created spots are saved here. Pending spots wait for review; live spots are already public.',
                style: TextStyle(color: Colors.white54, height: 1.3),
              ),
              const SizedBox(height: 14),
              if (spots.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Text(
                    'No submitted spots yet.',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              else
                ...spots.map(
                  (spot) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SubmittedSpotTile(spot: spot),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SubmittedSpotTile extends StatelessWidget {
  final CarSpot spot;

  const _SubmittedSpotTile({required this.spot});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          appPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            SpotPhoto(
              spot: spot,
              width: 72,
              height: 72,
              borderRadius: BorderRadius.circular(12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    spot.cityCountry,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _PendingBadge(status: spot.status),
                      for (final category in spot.categories.take(2))
                        _SmallTag(label: category, icon: Icons.local_offer),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class _TemporarySpotScheduleCard extends StatelessWidget {
  final bool enabled;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final bool showOnMapAtEnabled;
  final DateTime? showOnMapAt;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<bool> onShowOnMapAtEnabledChanged;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onPickShowOnMapAt;

  const _TemporarySpotScheduleCard({
    required this.enabled,
    required this.startsAt,
    required this.expiresAt,
    required this.showOnMapAtEnabled,
    required this.showOnMapAt,
    required this.onEnabledChanged,
    required this.onShowOnMapAtEnabledChanged,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onPickShowOnMapAt,
  });

  Widget timeButton({
    required String label,
    required DateTime? value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.06 : 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(icon, color: enabled ? blue : Colors.white30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value == null ? 'Choose time' : formatShortDateTime(value),
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled ? blue.withValues(alpha: 0.7) : Colors.white12,
        ),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: onEnabledChanged,
            activeThumbColor: blue,
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.timer, color: blue),
            title: const Text(
              'Temporary spot',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: const Text(
              'Use this for meets and events. Maximum active time is 12 hours.',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          if (enabled) ...[
            const SizedBox(height: 10),
            timeButton(
              label: 'Starts at',
              value: startsAt,
              icon: Icons.play_arrow,
              onTap: onPickStart,
            ),
            const SizedBox(height: 10),
            timeButton(
              label: 'Ends at',
              value: expiresAt,
              icon: Icons.stop,
              onTap: onPickEnd,
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              value: showOnMapAtEnabled,
              onChanged: enabled ? onShowOnMapAtEnabledChanged : null,
              activeThumbColor: blue,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.visibility_outlined, color: blue),
              title: const Text(
                'Show on map at',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: const Text(
                'Optional. If disabled, location appears at the beginning of the event day.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            if (showOnMapAtEnabled) ...[
              const SizedBox(height: 10),
              timeButton(
                label: 'Location visible from',
                value: showOnMapAt,
                icon: Icons.map_outlined,
                onTap: onPickShowOnMapAt,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;

  const LocationPickerScreen({super.key, this.initialLocation});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const defaultCenter = LatLng(56.9496, 24.1052);
  static const defaultZoom = 13.0;

  final mapController = MapController();
  LatLng? pickedLocation;

  @override
  void initState() {
    super.initState();
    pickedLocation = widget.initialLocation;
  }

  @override
  void dispose() {
    mapController.dispose();
    super.dispose();
  }

  List<Marker> get markers {
    final location = pickedLocation;

    if (location == null) {
      return [];
    }

    return [
      Marker(
        point: location,
        width: 64,
        height: 64,
        child: const Icon(Icons.location_on, color: blue, size: 56),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = pickedLocation != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Choose Location'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: pickedLocation ?? defaultCenter,
              initialZoom: defaultZoom,
              minZoom: 4,
              maxZoom: 18,
              backgroundColor: night,
              onTap: (_, point) => setState(() => pickedLocation = point),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.ccs_app',
                maxNativeZoom: 19,
              ),
              MarkerLayer(markers: markers),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.touch_app, color: blue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tap the map where this car spot should be placed.',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: panelGlass,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.36),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        hasLocation ? Icons.check_circle : Icons.place,
                        color: hasLocation ? blue : Colors.white54,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          hasLocation
                              ? 'Location selected'
                              : 'No location selected yet',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: hasLocation
                          ? () => Navigator.pop(context, pickedLocation)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue,
                        disabledBackgroundColor: Colors.white12,
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white38,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Use this Location',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationPickerField extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool hasLocation;
  final String? subtitle;
  final VoidCallback onTap;

  const _LocationPickerField({
    this.title = 'Location',
    this.icon = Icons.map,
    required this.hasLocation,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasLocation ? blue.withValues(alpha: 0.7) : Colors.white12,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(hasLocation ? Icons.check_circle : icon, color: blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle ??
                        (hasLocation
                            ? 'Spot location selected on map'
                            : 'Choose the spot on map'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

class _SpotPhotoPickerField extends StatelessWidget {
  final List<String> photoPaths;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;

  const _SpotPhotoPickerField({
    required this.photoPaths,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final canAddMore = photoPaths.length < maxSpotGalleryPhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: canAddMore ? onAddPhoto : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: photoPaths.isNotEmpty
                    ? blue.withValues(alpha: 0.7)
                    : Colors.white12,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    canAddMore ? Icons.add_photo_alternate : Icons.check,
                    color: blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        photoPaths.isEmpty
                            ? 'Upload photos'
                            : '${photoPaths.length}/$maxSpotGalleryPhotos photos selected',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        canAddMore
                            ? 'Add up to 4 spot photos. The first photo becomes the Explore thumbnail.'
                            : 'Maximum 4 photos selected. First photo is the spot thumbnail.',
                        style: const TextStyle(
                          color: Colors.white54,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  canAddMore ? Icons.chevron_right : Icons.lock,
                  color: Colors.white54,
                ),
              ],
            ),
          ),
        ),
        if (photoPaths.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var index = 0; index < photoPaths.length; index++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(
                        File(photoPaths[index]),
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) {
                          return Container(
                            width: 88,
                            height: 88,
                            color: Colors.white.withValues(alpha: 0.06),
                            child: const Icon(
                              Icons.broken_image,
                              color: Colors.white38,
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: index == 0
                              ? blue.withValues(alpha: 0.9)
                              : Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          index == 0 ? 'Cover' : '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: () => onRemovePhoto(index),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.78),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AddSpotSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _AddSpotSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          ...children.expand(
            (child) => [
              child,
              if (child != children.last) const SizedBox(height: 12),
            ],
          ),
        ],
      ),
    );
  }
}

class _CcsTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final TextInputType keyboardType;
  final bool readOnly;

  const _CcsTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: maxLines > 1 ? 3 : 1,
      maxLines: maxLines,
      keyboardType: maxLines > 1 ? TextInputType.multiline : keyboardType,
      textInputAction: maxLines > 1
          ? TextInputAction.newline
          : TextInputAction.done,
      readOnly: readOnly,
      style: TextStyle(color: appPrimaryText, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: trText(label),
        hintText: trText(hint),
        prefixIcon: Icon(icon, color: blue),
        labelStyle: TextStyle(color: appSecondaryText),
        hintStyle: TextStyle(color: appSubtleText),
        filled: true,
        fillColor: appSurfaceOverlay,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: appOutline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: blue, width: 1.4),
        ),
      ),
    );
  }
}

class SpotOwnerSelector extends StatefulWidget {
  final SpotOwnerAssignment? selectedOwner;
  final ValueChanged<SpotOwnerAssignment?> onChanged;

  const SpotOwnerSelector({
    super.key,
    required this.selectedOwner,
    required this.onChanged,
  });

  @override
  State<SpotOwnerSelector> createState() => _SpotOwnerSelectorState();
}

class _SpotOwnerSelectorState extends State<SpotOwnerSelector> {
  final searchController = TextEditingController();
  String searchText = '';
  late bool isPicking;

  @override
  void initState() {
    super.initState();
    isPicking = widget.selectedOwner == null;
  }

  @override
  void didUpdateWidget(covariant SpotOwnerSelector oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selectedOwner == null && oldWidget.selectedOwner != null) {
      isPicking = true;
    } else if (widget.selectedOwner != null &&
        oldWidget.selectedOwner?.uid != widget.selectedOwner?.uid) {
      isPicking = false;
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  String userInitial(String username) {
    final cleanUsername = username.trim();
    return cleanUsername.isEmpty ? '?' : cleanUsername[0].toUpperCase();
  }

  bool userMatchesSearch(FriendUserData user) {
    final query = searchText.trim().toLowerCase();

    if (query.isEmpty) {
      return true;
    }

    return user.username.toLowerCase().contains(query) ||
        user.name.toLowerCase().contains(query) ||
        user.email.toLowerCase().contains(query) ||
        user.uid.toLowerCase().contains(query);
  }

  void selectOwner(FriendUserData user) {
    widget.onChanged(
      SpotOwnerAssignment(uid: user.uid, username: user.username),
    );
    searchController.clear();
    setState(() {
      searchText = '';
      isPicking = false;
    });
    FocusScope.of(context).unfocus();
  }

  Widget avatarForUser(FriendUserData user) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: ClipOval(
        child: localFileExists(user.avatarPath)
            ? Image.file(File(user.avatarPath!), fit: BoxFit.cover)
            : (user.photoUrl != null && user.photoUrl!.trim().isNotEmpty)
            ? Image.network(
                user.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(
                  child: Text(
                    userInitial(user.username),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  userInitial(user.username),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
      ),
    );
  }

  Widget ownerSearchField() {
    return TextField(
      controller: searchController,
      textInputAction: TextInputAction.search,
      onTap: () => setState(() => isPicking = true),
      onChanged: (value) => setState(() {
        searchText = value;
        isPicking = true;
      }),
      style: TextStyle(color: appPrimaryText, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: trText('Spot owner'),
        hintText: widget.selectedOwner == null
            ? trText('Search nickname, name, or email')
            : trText('Search to change owner'),
        prefixIcon: const Icon(Icons.manage_accounts, color: blue),
        suffixIcon: searchText.trim().isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () {
                  searchController.clear();
                  setState(() => searchText = '');
                },
              )
            : null,
        labelStyle: TextStyle(color: appSecondaryText),
        hintStyle: TextStyle(color: appSubtleText),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: blue, width: 1.4),
        ),
      ),
    );
  }

  Widget selectedOwnerCard() {
    final owner = widget.selectedOwner;

    if (owner == null) {
      return const SizedBox.shrink();
    }

    final ownerLabel = owner.username.trim().isEmpty
        ? owner.uid
        : '@${owner.username}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.admin_panel_settings, color: blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Selected owner',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ownerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove owner',
            onPressed: () {
              widget.onChanged(null);
              setState(() => isPicking = true);
            },
            icon: const Icon(Icons.person_remove, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget ownerUserTile(FriendUserData user) {
    final isSelected = widget.selectedOwner?.uid == user.uid;

    return InkWell(
      onTap: () => selectOwner(user),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? blue.withValues(alpha: 0.13)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? blue.withValues(alpha: 0.65) : Colors.white10,
          ),
        ),
        child: Row(
          children: [
            avatarForUser(user),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (user.verified) ...[
                        const SizedBox(width: 5),
                        const Icon(Icons.verified, color: blue, size: 15),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user.email.trim().isEmpty ? user.name : user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              isSelected ? Icons.check_circle : Icons.add_circle_outline,
              color: isSelected ? blue : Colors.white38,
            ),
          ],
        ),
      ),
    );
  }

  Widget ownerResults() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: usersCollection().orderBy('usernameKey').snapshots(),
      builder: (context, snapshot) {
        final users =
            snapshot.data?.docs
                .map((doc) => FriendUserData.fromFirestore(doc))
                .where((user) => user.canAppearInUserLists)
                .where(userMatchesSearch)
                .toList() ??
            const <FriendUserData>[];

        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text(
                  'Loading users...',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          );
        }

        if (users.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: const Row(
              children: [
                Icon(Icons.person_search, color: Colors.white38),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No users found.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          );
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 290),
          child: ListView.separated(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: users.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => ownerUserTile(users[index]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final showResults = isPicking || searchText.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ownerSearchField(),
        if (widget.selectedOwner != null) ...[
          const SizedBox(height: 10),
          selectedOwnerCard(),
        ],
        if (showResults) ...[const SizedBox(height: 10), ownerResults()],
      ],
    );
  }
}

class OpeningHoursEditor extends StatelessWidget {
  final Map<int, OpeningHoursData> openingHours;
  final ValueChanged<Map<int, OpeningHoursData>> onChanged;

  const OpeningHoursEditor({
    super.key,
    required this.openingHours,
    required this.onChanged,
  });

  OpeningHoursData dayData(int weekday) {
    return openingHours[weekday] ??
        const OpeningHoursData(
          isOpen: false,
          opensAt: '08:00',
          closesAt: '20:00',
        );
  }

  void updateDay(int weekday, OpeningHoursData value) {
    onChanged({...openingHours, weekday: value});
  }

  Future<void> pickTime({
    required BuildContext context,
    required int weekday,
    required bool opensAt,
  }) async {
    final day = dayData(weekday);
    final currentValue = opensAt ? day.opensAt : day.closesAt;
    final currentMinutes = minutesFromClockText(currentValue) ?? 8 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: currentMinutes ~/ 60,
        minute: currentMinutes % 60,
      ),
      builder: (context, child) {
        return Theme(data: ThemeData.dark(), child: child!);
      },
    );

    if (picked == null) {
      return;
    }

    final nextTime = clockTextFromTimeOfDay(picked);
    updateDay(
      weekday,
      opensAt
          ? day.copyWith(opensAt: nextTime)
          : day.copyWith(closesAt: nextTime),
    );
  }

  Widget timeButton({
    required BuildContext context,
    required int weekday,
    required bool opensAt,
    required String value,
  }) {
    return OutlinedButton.icon(
      onPressed: () =>
          pickTime(context: context, weekday: weekday, opensAt: opensAt),
      icon: Icon(opensAt ? Icons.login : Icons.logout, size: 16),
      label: Text(value),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (
          var weekday = DateTime.monday;
          weekday <= DateTime.sunday;
          weekday++
        )
          Padding(
            padding: EdgeInsets.only(
              bottom: weekday == DateTime.sunday ? 0 : 10,
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          weekdayLabels[weekday] ?? 'Day',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Switch(
                        value: dayData(weekday).isOpen,
                        activeThumbColor: blue,
                        onChanged: (value) => updateDay(
                          weekday,
                          dayData(weekday).copyWith(isOpen: value),
                        ),
                      ),
                    ],
                  ),
                  if (dayData(weekday).isOpen) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: timeButton(
                            context: context,
                            weekday: weekday,
                            opensAt: true,
                            value: dayData(weekday).opensAt,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: timeButton(
                            context: context,
                            weekday: weekday,
                            opensAt: false,
                            value: dayData(weekday).closesAt,
                          ),
                        ),
                      ],
                    ),
                  ] else
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Closed',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class ServiceSpotBusinessEditScreen extends StatefulWidget {
  final CarSpot spot;

  const ServiceSpotBusinessEditScreen({super.key, required this.spot});

  @override
  State<ServiceSpotBusinessEditScreen> createState() =>
      _ServiceSpotBusinessEditScreenState();
}

class _ServiceSpotBusinessEditScreenState
    extends State<ServiceSpotBusinessEditScreen> {
  late final TextEditingController phoneController;
  late final TextEditingController instagramController;
  late final TextEditingController emailController;
  late Map<int, OpeningHoursData> openingHours;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    phoneController = TextEditingController(text: widget.spot.contactPhone);
    instagramController = TextEditingController(
      text: widget.spot.contactInstagram,
    );
    emailController = TextEditingController(text: widget.spot.contactEmail);
    openingHours = widget.spot.openingHours.isEmpty
        ? defaultServiceOpeningHours()
        : {...widget.spot.openingHours};
  }

  @override
  void dispose() {
    phoneController.dispose();
    instagramController.dispose();
    emailController.dispose();
    super.dispose();
  }

  Future<void> saveBusinessInfo() async {
    if (isSaving) {
      return;
    }

    if (!currentUserCanManageSpotBusiness(widget.spot)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Only the assigned owner or an admin can edit this spot.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final updatedSpot = widget.spot.copyWith(
        contactPhone: phoneController.text.trim(),
        contactInstagram: instagramController.text.trim(),
        contactEmail: emailController.text.trim(),
        openingHours: openingHours,
      );

      await spotsCollection().doc(widget.spot.id).update({
        'contactPhone': updatedSpot.contactPhone,
        'contactInstagram': updatedSpot.contactInstagram,
        'contactEmail': updatedSpot.contactEmail,
        'openingHours': openingHoursToFirebase(updatedSpot.openingHours),
        'businessEditedBy': currentUser.username,
        'businessEditedByUid': currentUser.uid,
        'businessEditedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final visibleUpdatedSpot = updatedSpot;

      reviewSpots.value = reviewSpots.value
          .map(
            (item) => isSameSpot(item, widget.spot) ? visibleUpdatedSpot : item,
          )
          .toList();
      submittedSpots.value = submittedSpots.value
          .map(
            (item) => isSameSpot(item, widget.spot) ? visibleUpdatedSpot : item,
          )
          .toList();
      savedSpots.value = savedSpots.value
          .map(
            (item) => isSameSpot(item, widget.spot) ? visibleUpdatedSpot : item,
          )
          .toList();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
            'Service info updated.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      Navigator.pop(context, updatedSpot);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not update service info: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Service Info'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          _AddSpotSection(
            title: 'Contacts',
            children: [
              _CcsTextField(
                controller: phoneController,
                label: 'Phone',
                hint: '+371 20 000 000',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
              ),
              _CcsTextField(
                controller: instagramController,
                label: 'Instagram',
                hint: '@ccs.lv or https://instagram.com/ccs.lv',
                icon: Icons.alternate_email,
                keyboardType: TextInputType.url,
              ),
              _CcsTextField(
                controller: emailController,
                label: 'Email',
                hint: 'hello@ccs.lv',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AddSpotSection(
            title: 'Opening hours',
            children: [
              OpeningHoursEditor(
                openingHours: openingHours,
                onChanged: (value) => setState(() => openingHours = value),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: isSaving ? null : saveBusinessInfo,
              icon: Icon(isSaving ? Icons.hourglass_top : Icons.save),
              label: Text(isSaving ? 'Saving...' : 'Save Service Info'),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UserSubmissionsScreen extends StatelessWidget {
  const UserSubmissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('My Submissions'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ValueListenableBuilder<List<CarSpot>>(
        valueListenable: submittedSpots,
        builder: (context, spots, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Text(
                spots.isEmpty
                    ? 'No spots created yet.'
                    : '${spots.length} created spots.',
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
              const SizedBox(height: 18),
              if (spots.isEmpty)
                const EmptyStateCard(
                  icon: Icons.add_location_alt,
                  title: 'No submissions yet',
                  text: 'Created spots will appear here.',
                )
              else
                for (final spot in spots) ...[
                  SavedSpotTile(spot: spot),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }
}

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsAppBarLogo(),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: ccsAppBarActions(),
      ),
      body: ValueListenableBuilder<List<CarSpot>>(
        valueListenable: savedSpots,
        builder: (context, spots, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              const Text(
                'Saved Spots',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                spots.isEmpty
                    ? 'Save approved spots from Explore, Map, or Spot pages.'
                    : '${spots.length} saved car spots.',
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
              const SizedBox(height: 18),
              if (spots.isEmpty)
                const EmptyStateCard(
                  icon: Icons.bookmark_border,
                  title: 'No saved spots yet',
                  text: 'Tap the bookmark on a spot to keep it here.',
                )
              else
                for (final spot in spots) ...[
                  SavedSpotTile(spot: spot),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }
}

const pinnedChatIdsPreferenceKey = 'pinned_chat_ids_v1';

Future<List<String>> loadPinnedChatIds() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(pinnedChatIdsPreferenceKey) ?? <String>[];
}

Future<void> savePinnedChatIds(List<String> ids) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(pinnedChatIdsPreferenceKey, ids.take(6).toList());
}

Widget chatAvatarWidget(ChatThreadData chat, String currentUid) {
  final photoUrl = chat.directPhotoUrlForCurrentUser(currentUid);

  if (!chat.isGroup && isNetworkUrl(photoUrl)) {
    return ClipOval(
      child: Image.network(
        photoUrl,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.person_outline, color: blue),
      ),
    );
  }

  if (chat.isGroup && isNetworkUrl(chat.avatarUrl)) {
    return ClipOval(
      child: Image.network(
        chat.avatarUrl,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.groups, color: blue),
      ),
    );
  }

  return Icon(chat.isGroup ? Icons.groups : Icons.person_outline, color: blue);
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<String> pinnedChatIds = const [];
  bool showGroupsTab = false;

  @override
  void initState() {
    super.initState();
    loadPins();
  }

  Future<void> loadPins() async {
    final ids = await loadPinnedChatIds();
    if (mounted) {
      setState(() => pinnedChatIds = ids);
    }
  }

  Future<void> openNewChat(BuildContext context) async {
    await Navigator.push(
      context,
      appPageRoute(builder: (_) => const NewChatScreen()),
    );
    loadPins();
  }

  Future<void> openChatManager(
    BuildContext context,
    List<ChatThreadData> chats,
  ) async {
    await Navigator.push(
      context,
      appPageRoute(
        builder: (_) =>
            ChatManageScreen(chats: chats, currentPinnedIds: pinnedChatIds),
      ),
    );
    loadPins();
  }

  List<ChatThreadData> sortedChats(List<ChatThreadData> chats) {
    final pinnedSet = pinnedChatIds.toSet();
    chats.sort((a, b) {
      final aPinned = pinnedSet.contains(a.id);
      final bPinned = pinnedSet.contains(b.id);

      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }

      if (aPinned && bPinned) {
        return pinnedChatIds
            .indexOf(a.id)
            .compareTo(pinnedChatIds.indexOf(b.id));
      }

      return b.updatedAtMillis.compareTo(a.updatedAtMillis);
    });
    return chats;
  }

  Widget sectionTitle(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: blue,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget chatSection({
    required String title,
    required String emptyText,
    required List<ChatThreadData> chats,
    required String currentUid,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panel.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionTitle(title, chats.length),
          if (chats.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                emptyText,
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
            )
          else
            for (final chat in chats) ...[
              ChatThreadTile(
                chat: chat,
                currentUid: currentUid,
                pinned: pinnedChatIds.contains(chat.id),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsAppBarLogo(),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: ccsAppBarActions(),
      ),
      floatingActionButton: firebaseUser == null
          ? null
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: currentUserChatsQuery(firebaseUser.uid).snapshots(),
              builder: (context, snapshot) {
                final chats =
                    snapshot.data?.docs
                        .map((doc) => ChatThreadData.fromFirestore(doc))
                        .toList() ??
                    <ChatThreadData>[];

                return FloatingActionButton(
                  onPressed: () => openChatManager(context, chats),
                  backgroundColor: blue,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.tune),
                );
              },
            ),
      body: firebaseUser == null
          ? const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: EmptyStateCard(
                icon: Icons.chat_bubble_outline,
                title: 'Log in required',
                text: 'Log in before using chat.',
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: currentUserChatsQuery(firebaseUser.uid).snapshots(),
              builder: (context, snapshot) {
                final chats =
                    snapshot.data?.docs
                        .map((doc) => ChatThreadData.fromFirestore(doc))
                        .toList() ??
                    <ChatThreadData>[];
                final directChats = sortedChats(
                  chats.where((chat) => !chat.isGroup).toList(),
                );
                final groupChats = sortedChats(
                  chats.where((chat) => chat.isGroup).toList(),
                );

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 92),
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Chat',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Messages with friends and groups',
                                style: TextStyle(
                                  color: Colors.white54,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filled(
                          onPressed: () => openNewChat(context),
                          style: IconButton.styleFrom(
                            backgroundColor: blue,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: false,
                            icon: Icon(Icons.person_outline),
                            label: Text('Chats'),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            icon: Icon(Icons.groups),
                            label: Text('Groups'),
                          ),
                        ],
                        selected: {showGroupsTab},
                        onSelectionChanged: (value) {
                          setState(() => showGroupsTab = value.first);
                        },
                        style: ButtonStyle(
                          foregroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? Colors.white
                                : Colors.white70,
                          ),
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? blue
                                : panel,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(color: blue),
                        ),
                      )
                    else if (chats.isEmpty)
                      const EmptyStateCard(
                        icon: Icons.chat_bubble_outline,
                        title: 'No chats yet',
                        text: 'Start a chat with a friend or create a group.',
                      )
                    else if (!showGroupsTab)
                      chatSection(
                        title: 'Chats',
                        emptyText: 'No direct chats yet.',
                        chats: directChats,
                        currentUid: firebaseUser.uid,
                      )
                    else
                      chatSection(
                        title: 'Groups',
                        emptyText: 'No groups yet.',
                        chats: groupChats,
                        currentUid: firebaseUser.uid,
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class ChatThreadTile extends StatelessWidget {
  final ChatThreadData chat;
  final String currentUid;
  final bool pinned;

  const ChatThreadTile({
    super.key,
    required this.chat,
    required this.currentUid,
    this.pinned = false,
  });

  String? otherUserId() {
    if (chat.isGroup) {
      return null;
    }

    for (final uid in chat.memberIds) {
      if (uid != currentUid && uid.trim().isNotEmpty) {
        return uid;
      }
    }

    return null;
  }

  Widget avatar(FriendUserData? directUser) {
    if (chat.isGroup) {
      final photoUrl = chat.photoUrl.trim();
      if (isNetworkUrl(photoUrl)) {
        return ClipOval(
          child: Image.network(
            photoUrl,
            width: 46,
            height: 46,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const UserAvatarFallback(size: 46, icon: Icons.groups),
          ),
        );
      }

      return const UserAvatarFallback(size: 46, icon: Icons.groups);
    }

    if (directUser != null) {
      return UserAvatarCircle(user: directUser, size: 46);
    }

    return const UserAvatarFallback(size: 46, icon: Icons.person_outline);
  }

  Widget subtitleLine(String subtitle, FriendUserData? directUser) {
    if (!chat.isGroup) {
      return Row(
        children: [
          OnlineStatusBadge(online: directUser?.appearsOnline ?? false),
          if (subtitle.trim().isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ],
      );
    }

    return Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white54),
    );
  }

  Widget tile(BuildContext context, FriendUserData? directUser) {
    final title = !chat.isGroup && directUser != null
        ? displayUsername(directUser.username)
        : chat.titleForCurrentUser(currentUid);
    final subtitle = chat.subtitleForCurrentUser(currentUid);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          appPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: pinned ? blue.withValues(alpha: 0.75) : Colors.white12,
            width: pinned ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            avatar(directUser),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (pinned) ...[
                        const Icon(Icons.push_pin, color: blue, size: 14),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  subtitleLine(subtitle, directUser),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = otherUserId();

    if (!chat.isGroup && uid != null) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: usersCollection().doc(uid).snapshots(),
        builder: (context, snapshot) {
          return tile(context, friendUserFromSnapshot(snapshot.data));
        },
      );
    }

    return tile(context, null);
  }
}

class UserAvatarFallback extends StatelessWidget {
  final double size;
  final IconData icon;

  const UserAvatarFallback({super.key, required this.size, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: Icon(icon, color: blue, size: size * 0.5),
    );
  }
}

class UserAvatarCircle extends StatelessWidget {
  final FriendUserData user;
  final double size;

  const UserAvatarCircle({super.key, required this.user, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: ClipOval(
        child: localFileExists(user.avatarPath)
            ? Image.file(File(user.avatarPath!), fit: BoxFit.cover)
            : isNetworkUrl(user.photoUrl)
            ? Image.network(
                user.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(
                  child: Text(
                    user.username.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  user.username.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
      ),
    );
  }
}

class OnlineStatusBadge extends StatelessWidget {
  final bool online;
  final double dotSize;
  final double fontSize;

  const OnlineStatusBadge({
    super.key,
    required this.online,
    this.dotSize = 7,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    final color = online ? Colors.greenAccent : Colors.white38;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          online ? 'online' : 'offline',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: online ? Colors.greenAccent : Colors.white54,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

FriendUserData? friendUserFromSnapshot(
  DocumentSnapshot<Map<String, dynamic>>? snapshot,
) {
  if (snapshot == null || !snapshot.exists) {
    return null;
  }

  return FriendUserData.fromFirestore(snapshot);
}

FriendUserData fallbackChatMember(ChatThreadData chat, String uid) {
  final index = chat.memberIds.indexOf(uid);
  final username = index >= 0 && index < chat.memberUsernames.length
      ? chat.memberUsernames[index]
      : 'ccs_driver';
  final photoUrl = index >= 0 && index < chat.memberPhotoUrls.length
      ? chat.memberPhotoUrls[index]
      : '';

  return FriendUserData(
    uid: uid,
    username: username.trim().isEmpty ? 'ccs_driver' : username,
    name: displayUsername(username.trim().isEmpty ? 'ccs_driver' : username),
    email: '',
    photoUrl: photoUrl.trim().isEmpty ? null : photoUrl,
    verified: false,
    role: UserRole.user,
    banned: false,
    deleted: false,
  );
}

List<FriendUserData> chatMembersFromSnapshot(
  QuerySnapshot<Map<String, dynamic>> snapshot,
  ChatThreadData chat,
) {
  final usersById = <String, FriendUserData>{
    for (final doc in snapshot.docs) doc.id: FriendUserData.fromFirestore(doc),
  };

  return [
    for (final uid in chat.memberIds)
      usersById[uid] ?? fallbackChatMember(chat, uid),
  ];
}

FriendUserData fallbackMessageSender(ChatMessageData message) {
  final username = message.senderUsername.trim().isEmpty
      ? 'ccs_driver'
      : message.senderUsername;

  return FriendUserData(
    uid: message.senderUid,
    username: username,
    name: displayUsername(username),
    email: '',
    verified: false,
    role: UserRole.user,
    banned: false,
    deleted: false,
  );
}

class ChatManageScreen extends StatefulWidget {
  final List<ChatThreadData> chats;
  final List<String> currentPinnedIds;

  const ChatManageScreen({
    super.key,
    required this.chats,
    required this.currentPinnedIds,
  });

  @override
  State<ChatManageScreen> createState() => _ChatManageScreenState();
}

class _ChatManageScreenState extends State<ChatManageScreen> {
  late List<String> pinnedIds;

  @override
  void initState() {
    super.initState();
    pinnedIds = [...widget.currentPinnedIds];
  }

  Future<void> togglePin(ChatThreadData chat) async {
    final sameTypePinned = pinnedIds
        .where(
          (id) => widget.chats.any(
            (item) => item.id == id && item.isGroup == chat.isGroup,
          ),
        )
        .toList();

    setState(() {
      if (pinnedIds.contains(chat.id)) {
        pinnedIds.remove(chat.id);
      } else {
        if (sameTypePinned.length >= 3) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text(
                chat.isGroup
                    ? 'You can pin up to 3 groups.'
                    : 'You can pin up to 3 direct chats.',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
          return;
        }
        pinnedIds.add(chat.id);
      }
    });

    await savePinnedChatIds(pinnedIds);
  }

  Future<void> movePinned(String chatId, int direction) async {
    final index = pinnedIds.indexOf(chatId);
    if (index < 0) {
      return;
    }

    final newIndex = (index + direction).clamp(0, pinnedIds.length - 1).toInt();
    if (newIndex == index) {
      return;
    }

    setState(() {
      final id = pinnedIds.removeAt(index);
      pinnedIds.insert(newIndex, id);
    });

    await savePinnedChatIds(pinnedIds);
  }

  Widget section(String title, List<ChatThreadData> chats) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (chats.isEmpty)
            const Text(
              'Nothing here yet.',
              style: TextStyle(color: Colors.white54),
            )
          else
            for (final chat in chats) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      chat.titleForCurrentUser(
                        FirebaseAuth.instance.currentUser?.uid ??
                            currentUser.uid,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Move up',
                    onPressed: pinnedIds.contains(chat.id)
                        ? () => movePinned(chat.id, -1)
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    onPressed: pinnedIds.contains(chat.id)
                        ? () => movePinned(chat.id, 1)
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                  IconButton(
                    tooltip: pinnedIds.contains(chat.id) ? 'Unpin' : 'Pin',
                    onPressed: () => togglePin(chat),
                    icon: Icon(
                      pinnedIds.contains(chat.id)
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      color: pinnedIds.contains(chat.id)
                          ? blue
                          : Colors.white54,
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white10),
            ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final directChats = widget.chats.where((chat) => !chat.isGroup).toList();
    final groupChats = widget.chats.where((chat) => chat.isGroup).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Edit Chat View'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          const Text(
            'Pin up to 3 direct chats and 3 groups. Use arrows to change pinned order.',
            style: TextStyle(color: Colors.white54, height: 1.35),
          ),
          const SizedBox(height: 18),
          section('Direct chats', directChats),
          const SizedBox(height: 16),
          section('Groups', groupChats),
        ],
      ),
    );
  }
}

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final searchController = TextEditingController();
  final groupNameController = TextEditingController();
  final Set<String> selectedUserIds = {};
  bool groupMode = false;
  String searchText = '';
  bool isCreating = false;

  @override
  void initState() {
    super.initState();
    searchController.addListener(() {
      setState(() => searchText = searchController.text);
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    groupNameController.dispose();
    super.dispose();
  }

  bool matchesSearch(FriendUserData user) {
    final query = searchText.trim().toLowerCase();

    if (query.isEmpty) {
      return true;
    }

    return user.username.toLowerCase().contains(query) ||
        user.name.toLowerCase().contains(query) ||
        user.email.toLowerCase().contains(query);
  }

  Future<void> openDirectChat(FriendUserData user) async {
    setState(() => isCreating = true);

    try {
      final chatId = await createOrOpenDirectChat(user);
      final chat = ChatThreadData(
        id: chatId,
        isGroup: false,
        name: '',
        memberIds: [currentUser.uid, user.uid],
        memberUsernames: [currentUser.username, user.username],
        lastMessage: '',
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        appPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not open chat: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isCreating = false);
      }
    }
  }

  Future<void> createGroup(List<FriendUserData> friends) async {
    final selected = friends
        .where((user) => selectedUserIds.contains(user.uid))
        .toList();

    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Pick at least one friend for a group.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    setState(() => isCreating = true);

    try {
      final chatId = await createGroupChat(
        name: groupNameController.text,
        users: selected,
      );
      final groupName = groupNameController.text.trim().isEmpty
          ? selected.map((user) => user.username).take(3).join(', ')
          : groupNameController.text.trim();
      final chat = ChatThreadData(
        id: chatId,
        isGroup: true,
        name: groupName,
        memberIds: [currentUser.uid, ...selected.map((user) => user.uid)],
        memberUsernames: [
          currentUser.username,
          ...selected.map((user) => user.username),
        ],
        lastMessage: '',
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        appPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not create group: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isCreating = false);
      }
    }
  }

  Widget userAvatar(FriendUserData user) {
    return UserAvatarCircle(user: user, size: 44);
  }

  Widget friendTile(FriendUserData user) {
    final selected = selectedUserIds.contains(user.uid);

    return InkWell(
      onTap: isCreating
          ? null
          : groupMode
          ? () {
              setState(() {
                if (selected) {
                  selectedUserIds.remove(user.uid);
                } else {
                  selectedUserIds.add(user.uid);
                }
              });
            }
          : () => openDirectChat(user),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? blue : Colors.white12,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            userAvatar(user),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayUsername(user.username),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: user.appearsOnline
                              ? Colors.greenAccent
                              : Colors.white38,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        user.appearsOnline ? 'online' : 'offline',
                        style: TextStyle(
                          color: user.appearsOnline
                              ? Colors.greenAccent
                              : Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (groupMode)
              Checkbox(
                value: selected,
                onChanged: (_) {
                  setState(() {
                    if (selected) {
                      selectedUserIds.remove(user.uid);
                    } else {
                      selectedUserIds.add(user.uid);
                    }
                  });
                },
                activeColor: blue,
                checkColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              )
            else
              const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('New Chat'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: FutureBuilder<List<FriendUserData>>(
        future: loadCurrentFriendUsers(),
        builder: (context, snapshot) {
          final friends =
              snapshot.data?.where(matchesSearch).toList() ??
              const <FriendUserData>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.person_outline),
                          label: Text('Direct'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.groups),
                          label: Text('Group'),
                        ),
                      ],
                      selected: {groupMode},
                      onSelectionChanged: (value) {
                        setState(() {
                          groupMode = value.first;
                          selectedUserIds.clear();
                        });
                      },
                      style: ButtonStyle(
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? Colors.white
                              : Colors.white70,
                        ),
                        backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? blue
                              : panel,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _CcsTextField(
                controller: searchController,
                label: 'Find friend',
                hint: '@username',
                icon: Icons.search,
              ),
              if (groupMode) ...[
                const SizedBox(height: 12),
                _CcsTextField(
                  controller: groupNameController,
                  label: 'Group name',
                  hint: 'Night drive crew',
                  icon: Icons.groups,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: isCreating ? null : () => createGroup(friends),
                    icon: Icon(isCreating ? Icons.hourglass_top : Icons.check),
                    label: Text(
                      selectedUserIds.isEmpty
                          ? 'Create Group'
                          : 'Create Group (${selectedUserIds.length + 1})',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: blue),
                  ),
                )
              else if (friends.isEmpty)
                const EmptyStateCard(
                  icon: Icons.group_outlined,
                  title: 'No friends found',
                  text: 'Add friends first, then start a chat here.',
                )
              else
                for (final friend in friends) friendTile(friend),
            ],
          );
        },
      ),
    );
  }
}

class GroupSettingsScreen extends StatefulWidget {
  final ChatThreadData chat;

  const GroupSettingsScreen({super.key, required this.chat});

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  late final TextEditingController nameController;
  late final TextEditingController descriptionController;
  bool isSaving = false;
  String photoUrl = '';

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.chat.name);
    descriptionController = TextEditingController(
      text: widget.chat.description,
    );
    photoUrl = widget.chat.photoUrl;
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> pickGroupAvatar() async {
    final path = await pickPhotoFromPhone(
      context,
      cropAspectRatio: 1,
      cropShape: PhotoCropShape.circle,
    );

    if (path == null || path.trim().isEmpty) {
      return;
    }

    setState(() => isSaving = true);

    try {
      final uploadedUrl = await uploadImageToR2(
        r2Path:
            'users/${currentUser.uid}/group_${safeR2Path(widget.chat.id)}_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
        localPhotoPath: path,
        maxLongSide: r2AvatarPhotoMaxLongSide,
      );

      await chatsCollection().doc(widget.chat.id).set({
        'photoUrl': uploadedUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() => photoUrl = uploadedUrl);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Could not update group photo: $error',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  bool get isCurrentUserGroupOwner {
    final ownerUid = widget.chat.ownerUid.trim().isEmpty
        ? (widget.chat.memberIds.isEmpty ? '' : widget.chat.memberIds.first)
        : widget.chat.ownerUid;
    return ownerUid == currentUser.uid;
  }

  bool get canManageGroupMembers {
    return isCurrentUserGroupOwner ||
        widget.chat.moderatorIds.contains(currentUser.uid) ||
        userRoleIsStaff(currentUser.role);
  }

  Future<void> addMembersToGroup() async {
    if (!canManageGroupMembers || isSaving) return;

    final friends = await loadAllVisibleUsersForGroupInvite();
    if (!mounted) return;

    final candidates = friends
        .where((user) => !widget.chat.memberIds.contains(user.uid))
        .toList();
    final selected = <FriendUserData>[];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: panelGlass,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add members',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (candidates.isEmpty)
                      const Text(
                        'No users available to add.',
                        style: TextStyle(color: Colors.white54),
                      )
                    else
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (final friend in candidates)
                                CheckboxListTile(
                                  value: selected.any(
                                    (u) => u.uid == friend.uid,
                                  ),
                                  onChanged: (value) {
                                    setSheetState(() {
                                      if (value == true) {
                                        selected.add(friend);
                                      } else {
                                        selected.removeWhere(
                                          (u) => u.uid == friend.uid,
                                        );
                                      }
                                    });
                                  },
                                  activeColor: blue,
                                  title: Text(
                                    displayUsername(friend.username),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  secondary: UserAvatarCircle(
                                    user: friend,
                                    size: 34,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.group_add),
                        label: Text('Add ${selected.length}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected.isEmpty) return;
    setState(() => isSaving = true);
    try {
      await chatsCollection().doc(widget.chat.id).set({
        'memberIds': FieldValue.arrayUnion(selected.map((u) => u.uid).toList()),
        'memberUsernames': FieldValue.arrayUnion(
          selected.map((u) => u.username).toList(),
        ),
        'memberPhotoUrls': FieldValue.arrayUnion(
          selected.map((u) => u.photoUrl ?? '').toList(),
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> toggleGroupModerator(FriendUserData user) async {
    if (!isCurrentUserGroupOwner || user.uid == currentUser.uid || isSaving)
      return;

    final isModerator = widget.chat.moderatorIds.contains(user.uid);
    setState(() => isSaving = true);
    try {
      await chatsCollection().doc(widget.chat.id).set({
        'moderatorIds': isModerator
            ? FieldValue.arrayRemove([user.uid])
            : FieldValue.arrayUnion([user.uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> saveGroup() async {
    final name = nameController.text.trim();
    final description = descriptionController.text.trim();

    setState(() => isSaving = true);

    try {
      await chatsCollection().doc(widget.chat.id).set({
        'name': name.isEmpty ? widget.chat.name : name,
        'description': description,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Could not update group: $error',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  Widget avatarPreview() {
    if (isNetworkUrl(photoUrl)) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const UserAvatarFallback(size: 96, icon: Icons.groups),
        ),
      );
    }

    return const UserAvatarFallback(size: 96, icon: Icons.groups);
  }

  Widget memberTile(FriendUserData user) {
    return InkWell(
      onTap: () => openUserProfile(
        context,
        uid: user.uid,
        fallbackUsername: user.username,
      ),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            UserAvatarCircle(user: user, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayUsername(user.username),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (user.uid == currentUser.uid) ...[
                        const SizedBox(width: 6),
                        const Text(
                          'you',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      OnlineStatusBadge(online: user.appearsOnline),
                      if (user.uid ==
                          (widget.chat.ownerUid.trim().isEmpty
                              ? (widget.chat.memberIds.isEmpty
                                    ? ''
                                    : widget.chat.memberIds.first)
                              : widget.chat.ownerUid))
                        const _SmallTag(label: 'owner', icon: Icons.shield),
                      if (widget.chat.moderatorIds.contains(user.uid))
                        const _SmallTag(
                          label: 'moderator',
                          icon: Icons.admin_panel_settings,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (isCurrentUserGroupOwner && user.uid != currentUser.uid)
              PopupMenuButton<String>(
                color: panel,
                icon: const Icon(Icons.more_horiz, color: Colors.white54),
                onSelected: (_) => toggleGroupModerator(user),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'toggle_moderator',
                    child: Text(
                      widget.chat.moderatorIds.contains(user.uid)
                          ? 'Remove group moderator'
                          : 'Make group moderator',
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget membersSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: usersCollection().snapshots(),
      builder: (context, snapshot) {
        final members = snapshot.hasData
            ? chatMembersFromSnapshot(snapshot.data!, widget.chat)
            : [
                for (final uid in widget.chat.memberIds)
                  fallbackChatMember(widget.chat, uid),
              ];

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: panelGlass,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Members',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (canManageGroupMembers)
                    IconButton(
                      tooltip: 'Add members',
                      onPressed: isSaving ? null : addMembersToGroup,
                      icon: const Icon(Icons.person_add_alt_1, color: blue),
                    ),
                  Text(
                    '${members.length}',
                    style: const TextStyle(
                      color: blue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final member in members) memberTile(member),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Group Info'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Center(
            child: InkWell(
              onTap: isSaving ? null : pickGroupAvatar,
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  avatarPreview(),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: blue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          _CcsTextField(
            controller: nameController,
            label: 'Group name',
            hint: 'Night drive crew',
            icon: Icons.groups,
          ),
          const SizedBox(height: 12),
          _CcsTextField(
            controller: descriptionController,
            label: 'Group description',
            hint: 'What is this group about?',
            icon: Icons.info_outline,
          ),
          const SizedBox(height: 18),
          membersSection(),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: isSaving ? null : saveGroup,
              icon: Icon(isSaving ? Icons.hourglass_top : Icons.check),
              label: const Text('Save Group'),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatTitleAvatar extends StatelessWidget {
  final String photoUrl;
  final String title;

  const ChatTitleAvatar({
    super.key,
    required this.photoUrl,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final firstLetter = title.trim().isEmpty
        ? '?'
        : title.trim().substring(0, 1).toUpperCase();

    if (isNetworkUrl(photoUrl)) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: 34,
          height: 34,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              UserAvatarFallback(size: 34, icon: Icons.person),
        ),
      );
    }

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: Center(
        child: Text(
          firstLetter,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

String formatChatMessageTime(int createdAtMillis) {
  if (createdAtMillis <= 0) {
    return '';
  }
  final value = DateTime.fromMillisecondsSinceEpoch(createdAtMillis);
  return '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

String chatDateDividerLabel(int createdAtMillis) {
  if (createdAtMillis <= 0) {
    return '';
  }
  final value = DateTime.fromMillisecondsSinceEpoch(createdAtMillis);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final messageDay = DateTime(value.year, value.month, value.day);
  final diffDays = today.difference(messageDay).inDays;

  if (diffDays == 0) {
    return trText('Today');
  }
  if (diffDays == 1) {
    return trText('Yesterday');
  }
  return formatShortDate(value);
}

Widget chatDateDivider(String label) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        const Expanded(child: Divider(color: Colors.white12)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: panelGlass,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Colors.white12)),
      ],
    ),
  );
}

class ChatConversationScreen extends StatefulWidget {
  final ChatThreadData chat;

  const ChatConversationScreen({super.key, required this.chat});

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final messageController = TextEditingController();
  final chatScrollController = ScrollController();
  bool isSending = false;
  bool isSharingChatLocation = false;
  bool hasScrolledToLatestMessage = false;
  bool scrollToLatestAfterNextMessage = false;
  int renderedMessageCount = 0;

  @override
  void dispose() {
    messageController.dispose();
    chatScrollController.dispose();
    super.dispose();
  }

  bool isNearLatestMessage() {
    if (!chatScrollController.hasClients) {
      return true;
    }

    final position = chatScrollController.position;
    return position.maxScrollExtent - position.pixels < 140;
  }

  void scheduleScrollToLatestMessage({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !chatScrollController.hasClients) {
        return;
      }

      final target = chatScrollController.position.maxScrollExtent;
      if (animated) {
        chatScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        chatScrollController.jumpTo(target);
      }
    });
  }

  void updateChatScrollForMessages(int messageCount) {
    final firstMessageLayout = !hasScrolledToLatestMessage;
    final receivedNewMessage = messageCount > renderedMessageCount;
    final shouldFollowLatest =
        firstMessageLayout ||
        (receivedNewMessage &&
            (scrollToLatestAfterNextMessage || isNearLatestMessage()));

    renderedMessageCount = messageCount;
    if (firstMessageLayout) {
      hasScrolledToLatestMessage = true;
    }
    if (receivedNewMessage) {
      scrollToLatestAfterNextMessage = false;
    }
    if (shouldFollowLatest) {
      scheduleScrollToLatestMessage(animated: !firstMessageLayout);
    }
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();

    if (text.isEmpty || isSending) {
      return;
    }

    setState(() => isSending = true);

    try {
      await sendChatMessage(chatId: widget.chat.id, text: text);
      messageController.clear();
      scrollToLatestAfterNextMessage = true;
      scheduleScrollToLatestMessage(animated: true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not send message: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSending = false);
      }
    }
  }

  Future<void> shareLiveLocation() async {
    if (isSharingChatLocation) {
      return;
    }

    setState(() => isSharingChatLocation = true);

    try {
      await shareChatLiveLocation(context, widget.chat);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not share location: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSharingChatLocation = false);
      }
    }
  }

  String? otherUserId(String currentUid) {
    if (widget.chat.isGroup) {
      return null;
    }

    for (final uid in widget.chat.memberIds) {
      if (uid != currentUid && uid.trim().isNotEmpty) {
        return uid;
      }
    }

    return null;
  }

  String otherUsername(String currentUid) {
    for (var index = 0; index < widget.chat.memberIds.length; index++) {
      final uid = widget.chat.memberIds[index];
      if (uid == currentUid) {
        continue;
      }

      if (index < widget.chat.memberUsernames.length) {
        return widget.chat.memberUsernames[index];
      }
    }

    return '';
  }

  void openChatUserProfile(String currentUid) {
    final uid = otherUserId(currentUid);

    if (uid == null) {
      return;
    }

    openUserProfile(
      context,
      uid: uid,
      fallbackUsername: otherUsername(currentUid),
    );
  }

  Future<void> showOwnMessageActions(ChatMessageData message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: panelGlass,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit, color: blue),
                  title: const Text(
                    'Edit message',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, 'edit'),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Delete message',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    if (action == 'edit') {
      await showEditMessageDialog(message);
    } else if (action == 'delete') {
      await confirmDeleteMessage(message);
    }
  }

  Future<void> showEditMessageDialog(ChatMessageData message) async {
    final controller = TextEditingController(text: message.text);

    final updatedText = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: const Text(
            'Edit message',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: trText('Message'),
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: blue),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              style: ElevatedButton.styleFrom(backgroundColor: blue),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (!mounted ||
        updatedText == null ||
        updatedText.trim() == message.text.trim()) {
      return;
    }

    try {
      await editChatMessage(
        chatId: widget.chat.id,
        message: message,
        text: updatedText,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not edit message: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  Future<void> confirmDeleteMessage(ChatMessageData message) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: const Text(
            'Delete message?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'This message will be deleted from the chat.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldDelete != true) {
      return;
    }

    try {
      await deleteChatMessage(chatId: widget.chat.id, message: message);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not delete message: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  Widget directChatTitle(
    String currentUid,
    String fallbackTitle,
    String fallbackPhotoUrl,
  ) {
    final uid = otherUserId(currentUid);

    Widget titleContent(FriendUserData? user) {
      final title = user == null
          ? fallbackTitle
          : displayUsername(user.username);

      return InkWell(
        onTap: () => openChatUserProfile(currentUid),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              user == null
                  ? ChatTitleAvatar(photoUrl: fallbackPhotoUrl, title: title)
                  : UserAvatarCircle(user: user, size: 34),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    OnlineStatusBadge(
                      online: user?.appearsOnline ?? false,
                      dotSize: 6,
                      fontSize: 10,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (uid == null) {
      return titleContent(null);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: usersCollection().doc(uid).snapshots(),
      builder: (context, snapshot) {
        return titleContent(friendUserFromSnapshot(snapshot.data));
      },
    );
  }

  Widget groupChatTitle(String title) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          appPageRoute(builder: (_) => GroupSettingsScreen(chat: widget.chat)),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups, size: 21),
            const SizedBox(width: 8),
            Flexible(child: Text(title)),
          ],
        ),
      ),
    );
  }

  Widget messageBubble(
    ChatMessageData message,
    String currentUid,
    Map<String, FriendUserData> usersById,
  ) {
    final mine = message.senderUid == currentUid;
    final canModerateMessage =
        widget.chat.isGroup &&
        (userRoleIsStaff(currentUser.role) ||
            widget.chat.ownerUid == currentUid ||
            widget.chat.moderatorIds.contains(currentUid));
    final showSender = !mine && widget.chat.isGroup;
    final sender =
        usersById[message.senderUid] ?? fallbackMessageSender(message);
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: showSender ? 248 : 280),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? blue : panel,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 5),
          bottomRight: Radius.circular(mine ? 5 : 16),
        ),
        border: mine ? null : Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (showSender) ...[
            Text(
              displayUsername(sender.username),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: blue,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            message.text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.edited) ...[
                Text(
                  'edited',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                formatChatMessageTime(message.createdAtMillis),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final content = showSender
        ? ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () => openUserProfile(
                      context,
                      uid: sender.uid,
                      fallbackUsername: sender.username,
                    ),
                    child: UserAvatarCircle(user: sender, size: 30),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: bubble),
              ],
            ),
          )
        : bubble;

    return GestureDetector(
      onLongPress: (mine || canModerateMessage)
          ? () => showOwnMessageActions(message)
          : null,
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final currentUid = firebaseUser?.uid ?? currentUser.uid;
    final title = widget.chat.titleForCurrentUser(currentUid);
    final chatPhotoUrl = widget.chat.directPhotoUrlForCurrentUser(currentUid);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: widget.chat.isGroup
            ? groupChatTitle(title)
            : directChatTitle(currentUid, title, chatPhotoUrl),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: widget.chat.isGroup
            ? [
                IconButton(
                  tooltip: 'Group info',
                  onPressed: () {
                    Navigator.push(
                      context,
                      appPageRoute(
                        builder: (_) => GroupSettingsScreen(chat: widget.chat),
                      ),
                    );
                  },
                  icon: const Icon(Icons.info_outline),
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Open profile',
                  onPressed: () => openChatUserProfile(currentUid),
                  icon: const Icon(Icons.account_circle_outlined),
                ),
              ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: latestChatMessagesQuery(widget.chat.id).snapshots(),
              builder: (context, snapshot) {
                final messages =
                    snapshot.data?.docs
                        .map((doc) => ChatMessageData.fromFirestore(doc))
                        .where((message) => message.text.trim().isNotEmpty)
                        .toList() ??
                    <ChatMessageData>[];
                messages.sort(
                  (first, second) =>
                      first.createdAtMillis.compareTo(second.createdAtMillis),
                );
                updateChatScrollForMessages(messages.length);

                if (messages.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: EmptyStateCard(
                      icon: Icons.chat_bubble_outline,
                      title: 'No messages yet',
                      text: 'Send the first message.',
                    ),
                  );
                }

                Widget listWithUsers(Map<String, FriendUserData> usersById) {
                  String previousDateLabel = '';
                  final children = <Widget>[];
                  for (final message in messages) {
                    final dateLabel = chatDateDividerLabel(
                      message.createdAtMillis,
                    );
                    if (dateLabel.isNotEmpty &&
                        dateLabel != previousDateLabel) {
                      children.add(chatDateDivider(dateLabel));
                      previousDateLabel = dateLabel;
                    }
                    children.add(messageBubble(message, currentUid, usersById));
                  }

                  return ListView(
                    controller: chatScrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    children: children,
                  );
                }

                if (!widget.chat.isGroup) {
                  return listWithUsers(const <String, FriendUserData>{});
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: usersCollection().snapshots(),
                  builder: (context, usersSnapshot) {
                    final members = usersSnapshot.hasData
                        ? chatMembersFromSnapshot(
                            usersSnapshot.data!,
                            widget.chat,
                          )
                        : [
                            for (final uid in widget.chat.memberIds)
                              fallbackChatMember(widget.chat, uid),
                          ];
                    final usersById = <String, FriendUserData>{
                      for (final member in members) member.uid: member,
                    };

                    return listWithUsers(usersById);
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: panelGlass,
                border: const Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Share location',
                    onPressed: isSharingChatLocation ? null : shareLiveLocation,
                    style: IconButton.styleFrom(foregroundColor: blue),
                    icon: Icon(
                      isSharingChatLocation
                          ? Icons.hourglass_top
                          : Icons.my_location,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      minLines: 1,
                      maxLines: 4,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: trText('Message'),
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: blue),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: isSending ? null : sendMessage,
                    style: IconButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(isSending ? Icons.hourglass_top : Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UserProfileData {
  final String username;
  final String cityCountry;
  final String bio;
  final String instagram;
  final String tiktok;
  final String telegram;
  final String? avatarPath;
  final String? photoUrl;

  const UserProfileData({
    required this.username,
    required this.cityCountry,
    required this.bio,
    required this.instagram,
    required this.tiktok,
    required this.telegram,
    this.avatarPath,
    this.photoUrl,
  });

  factory UserProfileData.fromCurrentUser() {
    final settings = userSettings.value;

    return UserProfileData(
      username: currentUser.username,
      cityCountry: '${currentUser.city}, ${currentUser.country}',
      bio: currentUser.bio,
      instagram: settings.instagram,
      tiktok: settings.tiktok,
      telegram: settings.telegram,
      avatarPath: currentUser.avatarPath,
      photoUrl: currentUser.photoUrl,
    );
  }
}

class GarageCar {
  final String name;
  final String description;
  final String buildType;
  final String useType;
  final List<String> tags;
  final String? photoPath;
  final List<String> photoPaths;

  const GarageCar({
    required this.name,
    required this.description,
    this.buildType = '',
    this.useType = '',
    this.tags = const [],
    this.photoPath,
    this.photoPaths = const [],
  });

  List<String> get galleryPhotos {
    final sources = <String>[];

    for (final source in photoPaths) {
      final cleanSource = source.trim();
      if (cleanSource.isNotEmpty && !sources.contains(cleanSource)) {
        sources.add(cleanSource);
      }
    }

    final cover = photoPath?.trim() ?? '';
    if (cover.isNotEmpty && !sources.contains(cover)) {
      sources.insert(0, cover);
    }

    return sources.take(maxGaragePhotos).toList();
  }

  String? get coverPhotoPath {
    final photos = galleryPhotos;
    return photos.isEmpty ? null : photos.first;
  }

  GarageCar copyWith({
    String? name,
    String? description,
    String? buildType,
    String? useType,
    List<String>? tags,
    String? photoPath,
    List<String>? photoPaths,
  }) {
    final nextPhotoPaths = photoPaths ?? this.photoPaths;
    final nextPhotoPath =
        photoPath ??
        (nextPhotoPaths.isNotEmpty ? nextPhotoPaths.first : this.photoPath);

    return GarageCar(
      name: name ?? this.name,
      description: description ?? this.description,
      buildType: buildType ?? this.buildType,
      useType: useType ?? this.useType,
      tags: tags ?? this.tags,
      photoPath: nextPhotoPath,
      photoPaths: nextPhotoPaths.take(maxGaragePhotos).toList(),
    );
  }

  factory GarageCar.fromFirebase(Object? value) {
    final data = mapFromFirebase(value);
    final photoPath = data['photoPath'];
    final legacyPhotoPath = photoPath is String && photoPath.trim().isNotEmpty
        ? photoPath.trim()
        : null;
    final photos = stringListFromFirebase(data['photoPaths'], const []);
    final gallery = photos.isNotEmpty
        ? photos.take(maxGaragePhotos).toList()
        : legacyPhotoPath == null
        ? const <String>[]
        : [legacyPhotoPath];

    return GarageCar(
      name: stringFromFirebase(data['name'], 'BMW E46 Coupe'),
      description: stringFromFirebase(
        data['description'],
        'Night drive setup for city shoots and clean street parking spots.',
      ),
      buildType: stringFromFirebase(data['buildType'], ''),
      useType: stringFromFirebase(data['useType'], ''),
      tags: stringListFromFirebase(data['tags'], const []),
      photoPath: gallery.isEmpty ? legacyPhotoPath : gallery.first,
      photoPaths: gallery,
    );
  }

  Map<String, Object?> toFirebase() {
    final gallery = galleryPhotos;

    return {
      'name': name,
      'description': description,
      'buildType': buildType,
      'useType': useType,
      'tags': tags,
      'photoPath': gallery.isEmpty ? photoPath : gallery.first,
      'photoPaths': gallery,
    };
  }
}

List<GarageCar> defaultGarageCars() {
  return const [
    GarageCar(
      name: 'BMW E46 Coupe',
      description:
          'Night drive setup for city shoots and clean street parking spots.',
    ),
  ];
}

List<GarageCar> garageCarsFromFirebase(Object? value) {
  if (value is List) {
    final cars = value.map(GarageCar.fromFirebase).toList();

    if (cars.isNotEmpty) {
      return cars;
    }
  }

  return defaultGarageCars();
}

class PublicUserProfileData {
  final String uid;
  final String username;
  final String name;
  final String email;
  final String? photoUrl;
  final String? avatarPath;
  final String bio;
  final String city;
  final String country;
  final UserRole role;
  final bool verified;
  final UserSettingsData settings;
  final List<GarageCar> garage;
  final bool deleted;
  final bool isOnline;
  final int lastSeenAtMillis;
  final bool isSharingLiveLocation;
  final int? liveLocationExpiresAtMillis;

  const PublicUserProfileData({
    required this.uid,
    required this.username,
    required this.name,
    required this.email,
    this.photoUrl,
    this.avatarPath,
    required this.bio,
    required this.city,
    required this.country,
    required this.role,
    required this.verified,
    required this.settings,
    required this.garage,
    required this.deleted,
    this.isOnline = false,
    this.lastSeenAtMillis = 0,
    this.isSharingLiveLocation = false,
    this.liveLocationExpiresAtMillis,
  });

  bool get canCurrentUserView {
    return userRoleIsStaff(currentUser.role) ||
        currentUser.uid == uid ||
        settings.publicProfile;
  }

  bool get appearsOnline => userAppearsOnlineFromPresence(
    isOnline: isOnline,
    lastSeenAtMillis: lastSeenAtMillis,
    isSharingLiveLocation: isSharingLiveLocation,
    liveLocationExpiresAtMillis: liveLocationExpiresAtMillis,
  );

  PublicUserProfileData copyWith({
    bool? isSharingLiveLocation,
    int? liveLocationExpiresAtMillis,
  }) {
    return PublicUserProfileData(
      uid: uid,
      username: username,
      name: name,
      email: email,
      photoUrl: photoUrl,
      avatarPath: avatarPath,
      bio: bio,
      city: city,
      country: country,
      role: role,
      verified: verified,
      settings: settings,
      garage: garage,
      deleted: deleted,
      isOnline: isOnline,
      lastSeenAtMillis: lastSeenAtMillis,
      isSharingLiveLocation:
          isSharingLiveLocation ?? this.isSharingLiveLocation,
      liveLocationExpiresAtMillis:
          liveLocationExpiresAtMillis ?? this.liveLocationExpiresAtMillis,
    );
  }

  String get cityCountry {
    final cleanCity = city.trim().isEmpty ? 'Riga' : city.trim();
    final cleanCountry = country.trim().isEmpty ? 'Latvia' : country.trim();
    return '$cleanCity, $cleanCountry';
  }

  factory PublicUserProfileData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final role = roleFromFirebase(data['role']);

    return PublicUserProfileData(
      uid: stringFromFirebase(data['uid'], doc.id),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      name: stringFromFirebase(data['name'], 'CCS Driver'),
      email: stringFromFirebase(data['email'], ''),
      photoUrl: data['photoUrl'] is String ? data['photoUrl'] as String : null,
      avatarPath: data['avatarPath'] is String
          ? data['avatarPath'] as String
          : null,
      bio: stringFromFirebase(data['bio'], 'Find. Drive. Shoot.'),
      city: stringFromFirebase(data['city'], 'Riga'),
      country: stringFromFirebase(data['country'], 'Latvia'),
      role: role,
      verified: userRoleIsStaff(role) || data['verified'] == true,
      settings: UserSettingsData.fromFirebase(data['settings']),
      garage: garageCarsFromFirebase(data['garage']),
      deleted: data['deleted'] == true,
      isOnline: data['isOnline'] == true,
      lastSeenAtMillis: timestampMillisFromFirebase(data['lastSeenAt']),
      isSharingLiveLocation: data['isSharingLiveLocation'] == true,
      liveLocationExpiresAtMillis: nullableTimestampMillisFromFirebase(
        data['liveLocationExpiresAt'],
      ),
    );
  }
}

void openUserProfile(
  BuildContext context, {
  required String uid,
  String fallbackUsername = '',
}) {
  final cleanUid = uid.trim();

  if (cleanUid.isEmpty) {
    return;
  }

  Navigator.push(
    context,
    appPageRoute(
      builder: (_) => PublicUserProfileScreen(
        userId: cleanUid,
        fallbackUsername: fallbackUsername,
      ),
    ),
  );
}

List<String> splitCityCountry(String value) {
  final parts = value.split(',');
  final city = parts.isNotEmpty && parts.first.trim().isNotEmpty
      ? parts.first.trim()
      : 'Riga';
  final countryText = parts.length > 1 ? parts.sublist(1).join(',').trim() : '';
  final country = countryText.isNotEmpty ? countryText : 'Latvia';

  return [city, country];
}

Future<void> saveProfileToFirebase(UserProfileData profile) async {
  final cityCountry = splitCityCountry(profile.cityCountry);
  final previousUsername = currentUser.username;
  final cleanUsername = await reserveUsernameForCurrentUser(
    preferredUsername: profile.username,
    previousUsername: previousUsername,
  );

  var nextPhotoUrl = currentUser.photoUrl;
  String? nextAvatarPath = profile.avatarPath;

  if (localFileExists(profile.avatarPath)) {
    nextPhotoUrl = await uploadUserAvatarPhoto(
      userId: currentUser.uid,
      localPhotoPath: profile.avatarPath!,
    );
    nextAvatarPath = null;
  } else if (isNetworkUrl(profile.avatarPath)) {
    nextPhotoUrl = profile.avatarPath;
    nextAvatarPath = null;
  }

  setCurrentUser(
    AppUser(
      uid: currentUser.uid,
      name: currentUser.name,
      username: cleanUsername,
      email: currentUser.email,
      photoUrl: nextPhotoUrl,
      bio: profile.bio,
      avatarPath: nextAvatarPath,
      role: currentUser.role,
      verified: currentUser.verified,
      city: cityCountry[0],
      country: cityCountry[1],
    ),
  );

  final nextSettings = userSettings.value.copyWith(
    instagram: profile.instagram.trim(),
    tiktok: profile.tiktok.trim(),
    telegram: profile.telegram.trim(),
  );
  userSettings.value = nextSettings;

  await saveCurrentUserFields({
    'username': cleanUsername,
    'usernameKey': usernameKey(cleanUsername),
    'bio': profile.bio,
    'photoUrl': nextPhotoUrl,
    'avatarPath': nextAvatarPath,
    'city': cityCountry[0],
    'country': cityCountry[1],
    'settings': nextSettings.toFirebase(),
    'instagram': nextSettings.instagram.trim(),
    'tiktok': nextSettings.tiktok.trim(),
    'telegram': nextSettings.telegram.trim(),
  });
}

Future<void> saveGarageToFirebase(List<GarageCar> cars) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final uploadedCars = <GarageCar>[];

  for (var carIndex = 0; carIndex < cars.length; carIndex++) {
    final car = cars[carIndex];
    final uploadedPhotoPaths = <String>[];
    final photoSources = car.galleryPhotos.take(maxGaragePhotos).toList();

    for (var photoIndex = 0; photoIndex < photoSources.length; photoIndex++) {
      final source = photoSources[photoIndex];

      if (firebaseUser != null && localFileExists(source)) {
        final uploadedPhotoUrl = await uploadGarageCarPhoto(
          userId: firebaseUser.uid,
          carIndex: carIndex,
          photoIndex: photoIndex,
          localPhotoPath: source,
        );
        uploadedPhotoPaths.add(uploadedPhotoUrl);
      } else if (source.trim().isNotEmpty) {
        uploadedPhotoPaths.add(source.trim());
      }
    }

    uploadedCars.add(
      GarageCar(
        name: car.name,
        description: car.description,
        buildType: car.buildType,
        useType: car.useType,
        tags: car.tags,
        photoPath: uploadedPhotoPaths.isEmpty ? null : uploadedPhotoPaths.first,
        photoPaths: uploadedPhotoPaths,
      ),
    );
  }

  garageCars.value = uploadedCars;

  await saveCurrentUserFields({
    'garage': uploadedCars.map((car) => car.toFirebase()).toList(),
  });
}

Future<void> saveSettingsToFirebase(UserSettingsData settings) async {
  userSettings.value = settings;

  await saveCurrentUserFields({
    'settings': settings.toFirebase(),
    'instagram': settings.instagram.trim(),
    'tiktok': settings.tiktok.trim(),
    'telegram': settings.telegram.trim(),
    // Keep flat copies too so older backend/functions or admin tools that read
    // notification settings directly from the user document do not miss changes.
    'reviewNotifications': settings.reviewNotifications,
    'likeNotifications': settings.likeNotifications,
    'commentNotifications': settings.commentNotifications,
    'newSpotNotifications': settings.newSpotNotifications,
    'newMessageNotifications': settings.newMessageNotifications,
    'publicProfile': settings.publicProfile,
    'showGarage': settings.showGarage,
  });
}

Widget profileMessageButton(BuildContext context, FriendUserData user) {
  if (user.uid == currentUser.uid) {
    return const SizedBox.shrink();
  }

  return Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
    child: SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () => openMessageToUserFromContext(context, user),
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text('Message'),
        style: ElevatedButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    ),
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool isSigningOut = false;

  UserProfileData profile = UserProfileData.fromCurrentUser();
  List<GarageCar> cars = garageCars.value;

  Future<void> editProfile() async {
    final updatedProfile = await Navigator.push<UserProfileData>(
      context,
      appPageRoute(builder: (_) => EditProfileScreen(profile: profile)),
    );

    if (!mounted || updatedProfile == null) {
      return;
    }

    try {
      await saveProfileToFirebase(updatedProfile);

      if (!mounted) {
        return;
      }

      setState(() => profile = UserProfileData.fromCurrentUser());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
            'Profile saved to your account.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not save profile: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  Future<void> editGarage(int index) async {
    final updatedCar = await Navigator.push<GarageCar>(
      context,
      appPageRoute(builder: (_) => EditGarageScreen(car: cars[index])),
    );

    if (!mounted || updatedCar == null) {
      return;
    }

    final nextCars = [...cars];
    nextCars[index] = updatedCar;
    setState(() => cars = nextCars);

    try {
      await saveGarageToFirebase(nextCars);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
            'Garage saved to your account.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not save garage: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  Future<void> addCar() async {
    final newCar = await Navigator.push<GarageCar>(
      context,
      appPageRoute(builder: (_) => const EditGarageScreen()),
    );

    if (!mounted || newCar == null) {
      return;
    }

    final nextCars = [...cars, newCar];
    setState(() => cars = nextCars);

    try {
      await saveGarageToFirebase(nextCars);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
            'Car added to your account.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not save car: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  void openSettings() {
    Navigator.push(
      context,
      appPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void openFriends() {
    Navigator.push(
      context,
      appPageRoute(builder: (_) => const FriendsScreen()),
    );
  }

  void openAdminPanel() {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null || !userRoleIsStaff(currentUser.role)) {
      return;
    }

    Navigator.push(
      context,
      appPageRoute(builder: (_) => const AdminReviewScreen()),
    );
  }

  Future<void> signOut() async {
    if (isSigningOut) {
      return;
    }

    setState(() => isSigningOut = true);

    try {
      await signOutCurrentAccount();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        appPageRoute(builder: (_) => const SplashScreen()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not sign out: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSigningOut = false);
      }
    }
  }

  String get garageValue {
    if (cars.length == 1) {
      return '1 car';
    }

    return '${cars.length} cars';
  }

  String get baseValue {
    final city = profile.cityCountry.split(',').first.trim();

    if (city.isEmpty) {
      return 'Riga';
    }

    return city;
  }

  List<String> get profileTags {
    final tags = <String>{};

    for (final car in cars) {
      tags.addAll(car.tags);
    }

    return tags.take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsAppBarLogo(),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: ccsAppBarActions(),
      ),
      body: ValueListenableBuilder<List<CarSpot>>(
        valueListenable: submittedSpots,
        builder: (context, spots, _) {
          final pendingCount = spots
              .where((spot) => spot.status == SpotStatus.pending)
              .length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              _ProfileHeader(
                profile: profile,
                garageValue: garageValue,
                spotsValue: '${spots.length} spots',
                onEdit: editProfile,
              ),
              const SizedBox(height: 16),
              const _ProfileSocialLinksSection(),
              const SizedBox(height: 16),
              for (var i = 0; i < cars.length; i++) ...[
                _GarageCard(car: cars[i], onEdit: () => editGarage(i)),
                const SizedBox(height: 16),
              ],
              ValueListenableBuilder<List<CarSpot>>(
                valueListenable: savedSpots,
                builder: (context, saved, _) {
                  return _ProfileSavedSpotsPreview(spots: saved);
                },
              ),
              const SizedBox(height: 16),
              _ProfileSubmissionsPreview(spots: spots),
              const SizedBox(height: 16),
              _ProfileActionTile(
                icon: Icons.group_add,
                title: 'Friends',
                subtitle: 'Send requests, accept invites, and manage friends',
                onTap: openFriends,
              ),
              const SizedBox(height: 10),
              if (userRoleIsStaff(currentUser.role)) ...[
                _ProfileActionTile(
                  icon: Icons.admin_panel_settings,
                  title: currentUser.role == UserRole.admin
                      ? 'Admin Panel'
                      : 'Moderator Panel',
                  subtitle: currentUser.role == UserRole.admin
                      ? 'Review spots and manage users'
                      : 'Review spots and moderate users',
                  onTap: openAdminPanel,
                ),
                const SizedBox(height: 10),
              ],
              _ProfileActionTile(
                icon: Icons.directions_car,
                title: 'Add another car',
                subtitle: 'Add another car to your garage',
                onTap: addCar,
              ),
              const SizedBox(height: 10),
              _ProfileActionTile(
                icon: Icons.settings,
                title: 'Settings',
                subtitle: 'Account, privacy, notifications',
                onTap: openSettings,
              ),
              const SizedBox(height: 10),
              _ProfileActionTile(
                icon: Icons.logout,
                title: isSigningOut ? 'Signing out...' : 'Sign out',
                subtitle: 'Log out of this Google account',
                color: Colors.redAccent,
                onTap: signOut,
              ),
            ],
          );
        },
      ),
    );
  }
}

class PublicUserProfileScreen extends StatelessWidget {
  final String userId;
  final String fallbackUsername;

  const PublicUserProfileScreen({
    super.key,
    required this.userId,
    this.fallbackUsername = '',
  });

  Widget avatar(PublicUserProfileData profile) {
    Widget fallback() {
      final initial = profile.username.trim().isEmpty
          ? 'C'
          : profile.username.trim()[0].toUpperCase();

      return Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: blue,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return Container(
      width: 86,
      height: 86,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.5)),
      ),
      child: ClipOval(
        child: localFileExists(profile.avatarPath)
            ? Image.file(File(profile.avatarPath!), fit: BoxFit.cover)
            : isNetworkUrl(profile.photoUrl)
            ? Image.network(
                profile.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback(),
              )
            : fallback(),
      ),
    );
  }

  Widget profileHeader(PublicUserProfileData profile) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          avatar(profile),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (profile.verified) ...[
                      const SizedBox(width: 7),
                      const Icon(Icons.verified, color: blue, size: 19),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: profile.appearsOnline
                            ? Colors.greenAccent
                            : Colors.white38,
                        shape: BoxShape.circle,
                        boxShadow: profile.appearsOnline
                            ? [
                                BoxShadow(
                                  color: Colors.greenAccent.withValues(
                                    alpha: 0.38,
                                  ),
                                  blurRadius: 9,
                                  spreadRadius: 1,
                                ),
                              ]
                            : const [],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      profile.appearsOnline ? 'online' : 'offline',
                      style: TextStyle(
                        color: profile.appearsOnline
                            ? Colors.greenAccent
                            : Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  profile.bio,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, height: 1.3),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: blue, size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        profile.cityCountry,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget messageButton(BuildContext context, PublicUserProfileData profile) {
    if (profile.uid == currentUser.uid) {
      return const SizedBox.shrink();
    }

    final user = FriendUserData(
      uid: profile.uid,
      username: profile.username,
      name: profile.name,
      email: profile.email,
      photoUrl: profile.photoUrl,
      avatarPath: profile.avatarPath,
      verified: profile.verified,
      role: profile.role,
      banned: false,
      deleted: false,
    );

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () async {
          try {
            final chatId = await createOrOpenDirectChat(user);
            final chat = ChatThreadData(
              id: chatId,
              isGroup: false,
              name: '',
              photoUrl: '',
              memberIds: [currentUser.uid, user.uid],
              memberUsernames: [currentUser.username, user.username],
              memberPhotoUrls: [
                currentUser.photoUrl ?? '',
                user.photoUrl ?? '',
              ],
              lastMessage: '',
              updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
            );

            if (!context.mounted) {
              return;
            }

            Navigator.push(
              context,
              appPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
            );
          } catch (error) {
            if (!context.mounted) {
              return;
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.redAccent,
                content: Text(
                  'Could not open chat: $error',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }
        },
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text('Message'),
        style: ElevatedButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }

  Widget socialLinks(PublicUserProfileData profile) {
    final settings = profile.settings;
    final links = <Widget>[
      if (settings.instagram.trim().isNotEmpty)
        _SocialLinkRow(
          icon: Icons.camera_alt,
          label: 'Instagram',
          value: settings.instagram,
        ),
      if (settings.tiktok.trim().isNotEmpty)
        _SocialLinkRow(
          icon: Icons.music_note,
          label: 'TikTok',
          value: settings.tiktok,
        ),
      if (settings.telegram.trim().isNotEmpty)
        _SocialLinkRow(
          icon: Icons.send,
          label: 'Telegram',
          value: settings.telegram,
        ),
    ];

    if (links.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Social links',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < links.length; index++) ...[
            if (index > 0) const SizedBox(height: 10),
            links[index],
          ],
        ],
      ),
    );
  }

  Widget profileBody(BuildContext context, PublicUserProfileData profile) {
    final visibleGarage = profile.settings.showGarage
        ? profile.garage
        : const <GarageCar>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        profileHeader(profile),
        const SizedBox(height: 12),
        messageButton(context, profile),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ProfileStatTile(
                icon: Icons.directions_car,
                value: '${visibleGarage.length}',
                label: 'Cars',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ProfileStatTile(
                icon: Icons.location_on,
                value: profile.city.trim().isEmpty ? 'Riga' : profile.city,
                label: 'Base',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ProfileStatTile(
                icon: profile.verified ? Icons.verified : Icons.person,
                value: profile.verified ? 'Yes' : 'No',
                label: 'Verified',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        socialLinks(profile),
        const SizedBox(height: 16),
        if (visibleGarage.isEmpty)
          const EmptyStateCard(
            icon: Icons.directions_car,
            title: 'No garage shared',
            text: 'This driver has not shared car builds yet.',
          )
        else
          for (final car in visibleGarage) ...[
            _GarageCard(car: car),
            const SizedBox(height: 16),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = fallbackUsername.trim().isEmpty
        ? 'Profile'
        : '@${fallbackUsername.replaceAll('@', '')}';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: usersCollection().doc(userId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final doc = snapshot.data;

          if (doc == null || !doc.exists) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyStateCard(
                icon: Icons.person_off,
                title: 'Profile not found',
                text: 'This user profile is not available anymore.',
              ),
            );
          }

          final profile = PublicUserProfileData.fromFirestore(doc);

          if (profile.deleted) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyStateCard(
                icon: Icons.person_off,
                title: 'Profile deleted',
                text: 'This user profile is not available anymore.',
              ),
            );
          }

          if (!profile.canCurrentUserView) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyStateCard(
                icon: Icons.lock,
                title: 'Private profile',
                text: 'This driver keeps their profile private.',
              ),
            );
          }

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: liveLocationsCollection().doc(userId).snapshots(),
            builder: (context, liveSnapshot) {
              var isSharingLiveLocation = false;
              final liveDoc = liveSnapshot.data;

              int? liveLocationExpiresAtMillis;
              if (liveDoc != null && liveDoc.exists) {
                final currentUid = FirebaseAuth.instance.currentUser?.uid;
                final liveLocation = LiveLocationData.fromFirestore(liveDoc);
                final currentUserCanView =
                    currentUid != null &&
                    (liveLocation.uid == currentUid ||
                        liveLocation.visibleToUserIds.contains(currentUid));
                isSharingLiveLocation =
                    currentUserCanView && !liveLocation.isExpired;
                liveLocationExpiresAtMillis = isSharingLiveLocation
                    ? liveLocation.expiresAtMillis
                    : null;
              }

              return profileBody(
                context,
                profile.copyWith(
                  isSharingLiveLocation: isSharingLiveLocation,
                  liveLocationExpiresAtMillis: liveLocationExpiresAtMillis,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final searchController = TextEditingController();
  String searchText = '';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<FriendUserData?> loadFriendUser(String uid) async {
    final snapshot = await usersCollection().doc(uid).get();

    if (!snapshot.exists) {
      return null;
    }

    return FriendUserData.fromFirestore(snapshot);
  }

  void showFriendActionMessage(String message, {Color color = blue}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> sendRequest(FriendUserData user) async {
    try {
      await sendFriendRequestToUser(user);
      showFriendActionMessage('Friend request sent to ${user.username}.');
      setState(() {});
    } catch (error) {
      showFriendActionMessage(
        'Could not send request: $error',
        color: Colors.redAccent,
      );
    }
  }

  Future<void> acceptRequest(FriendRequestData request) async {
    try {
      await acceptFriendRequest(request);
      showFriendActionMessage('${request.fromUsername} added to friends.');
      setState(() {});
    } catch (error) {
      showFriendActionMessage(
        'Could not accept request: $error',
        color: Colors.redAccent,
      );
    }
  }

  Future<void> declineRequest(FriendRequestData request) async {
    try {
      await declineFriendRequest(request);
      showFriendActionMessage('Friend request declined.');
      setState(() {});
    } catch (error) {
      showFriendActionMessage(
        'Could not decline request: $error',
        color: Colors.redAccent,
      );
    }
  }

  Future<void> cancelRequest(FriendRequestData request) async {
    try {
      await cancelFriendRequest(request);
      showFriendActionMessage('Friend request cancelled.');
      setState(() {});
    } catch (error) {
      showFriendActionMessage(
        'Could not cancel request: $error',
        color: Colors.redAccent,
      );
    }
  }

  Future<void> removeFriend(FriendUserData user) async {
    try {
      await removeFriendship(user.uid);
      showFriendActionMessage(
        '${user.username} removed from friends.',
        color: Colors.redAccent,
      );
      setState(() {});
    } catch (error) {
      showFriendActionMessage(
        'Could not remove friend: $error',
        color: Colors.redAccent,
      );
    }
  }

  Widget userAvatar({
    required String username,
    String? photoUrl,
    String? avatarPath,
    bool verified = false,
  }) {
    return Stack(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: blue.withValues(alpha: 0.16),
            shape: BoxShape.circle,
            border: Border.all(color: blue.withValues(alpha: 0.45)),
          ),
          child: ClipOval(
            child: localFileExists(avatarPath)
                ? Image.file(File(avatarPath!), fit: BoxFit.cover)
                : (photoUrl != null && photoUrl.trim().isNotEmpty)
                ? Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(
                      child: Text(
                        username.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      username.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
          ),
        ),
        if (verified)
          const Positioned(
            right: 0,
            bottom: 0,
            child: Icon(Icons.verified, color: blue, size: 17),
          ),
      ],
    );
  }

  Widget friendUserTile({
    required FriendUserData user,
    required String subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            userAvatar(
              username: user.username,
              photoUrl: user.photoUrl,
              avatarPath: user.avatarPath,
              verified: user.verified,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (user.role == UserRole.admin) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.admin_panel_settings,
                          color: blue,
                          size: 15,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: user.appearsOnline
                              ? Colors.greenAccent
                              : Colors.white38,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        user.appearsOnline ? 'online' : 'offline',
                        style: TextStyle(
                          color: user.appearsOnline
                              ? Colors.greenAccent
                              : Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget actionButton({
    required String label,
    required VoidCallback? onPressed,
    Color color = blue,
    bool outlined = false,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    );

    if (outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.65)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: shape,
        ),
        child: Text(label),
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: shape,
      ),
      child: Text(label),
    );
  }

  Widget friendsTab() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return const EmptyStateCard(
        icon: Icons.group,
        title: 'Log in required',
        text: 'Log in before using friends.',
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: usersCollection().snapshots(),
      builder: (context, _) {
        return FutureBuilder<List<FriendUserData>>(
          future: loadCurrentFriendUsers(),
          builder: (context, snapshot) {
            final friends = snapshot.data ?? const <FriendUserData>[];

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: blue),
                ),
              );
            }

            if (friends.isEmpty) {
              return const EmptyStateCard(
                icon: Icons.group_outlined,
                title: 'No friends yet',
                text: 'Use Find Users to send your first friend request.',
              );
            }

            return Column(
              children: [
                for (final user in friends)
                  friendUserTile(
                    user: user,
                    subtitle: user.name,
                    onTap: () => openUserProfile(
                      context,
                      uid: user.uid,
                      fallbackUsername: user.username,
                    ),
                    trailing: actionButton(
                      label: 'Remove',
                      color: Colors.redAccent,
                      outlined: true,
                      onPressed: () => removeFriend(user),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget requestsTab() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return const EmptyStateCard(
        icon: Icons.mark_email_unread_outlined,
        title: 'Log in required',
        text: 'Log in before using friend requests.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Incoming requests',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: friendRequestsCollection()
              .where('toUid', isEqualTo: firebaseUser.uid)
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, snapshot) {
            final requests =
                snapshot.data?.docs
                    .map((doc) => FriendRequestData.fromFirestore(doc))
                    .toList() ??
                const <FriendRequestData>[];

            if (requests.isEmpty) {
              return const EmptyStateCard(
                icon: Icons.inbox_outlined,
                title: 'No incoming requests',
                text: 'Friend invites sent to you will appear here.',
              );
            }

            return Column(
              children: [
                for (final request in requests)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: panelGlass,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        userAvatar(username: request.fromUsername),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.fromUsername,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                request.fromName,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        actionButton(
                          label: 'Accept',
                          onPressed: () => acceptRequest(request),
                        ),
                        const SizedBox(width: 6),
                        actionButton(
                          label: 'Decline',
                          color: Colors.redAccent,
                          outlined: true,
                          onPressed: () => declineRequest(request),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        const Text(
          'Sent requests',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: friendRequestsCollection()
              .where('fromUid', isEqualTo: firebaseUser.uid)
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, snapshot) {
            final requests =
                snapshot.data?.docs
                    .map((doc) => FriendRequestData.fromFirestore(doc))
                    .toList() ??
                const <FriendRequestData>[];

            if (requests.isEmpty) {
              return const EmptyStateCard(
                icon: Icons.outbox_outlined,
                title: 'No sent requests',
                text: 'Requests you send will appear here until accepted.',
              );
            }

            return Column(
              children: [
                for (final request in requests)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: panelGlass,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        userAvatar(username: request.toUsername),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.toUsername,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                request.toName,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        actionButton(
                          label: 'Cancel',
                          color: Colors.redAccent,
                          outlined: true,
                          onPressed: () => cancelRequest(request),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget findUsersTab() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return const EmptyStateCard(
        icon: Icons.person_search,
        title: 'Log in required',
        text: 'Log in before finding friends.',
      );
    }

    return Column(
      children: [
        TextField(
          controller: searchController,
          onChanged: (value) =>
              setState(() => searchText = value.trim().toLowerCase()),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            labelText: trText('Search users'),
            hintText: trText('nickname or name'),
            prefixIcon: const Icon(Icons.search, color: blue),
            labelStyle: const TextStyle(color: Colors.white60),
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: blue, width: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: usersCollection().orderBy('usernameKey').snapshots(),
          builder: (context, snapshot) {
            final users =
                snapshot.data?.docs
                    .map((doc) => FriendUserData.fromFirestore(doc))
                    .where((user) => user.canAppearInUserLists)
                    .where((user) => user.uid != firebaseUser.uid)
                    .where((user) {
                      if (searchText.isEmpty) {
                        return true;
                      }

                      return user.username.toLowerCase().contains(searchText) ||
                          user.name.toLowerCase().contains(searchText);
                    })
                    .toList() ??
                <FriendUserData>[];

            users.sort((a, b) {
              final onlineCompare = b.appearsOnline.toString().compareTo(
                a.appearsOnline.toString(),
              );
              if (onlineCompare != 0) {
                return onlineCompare;
              }

              return a.username.toLowerCase().compareTo(
                b.username.toLowerCase(),
              );
            });

            if (users.isEmpty) {
              return const EmptyStateCard(
                icon: Icons.person_search,
                title: 'No users found',
                text: 'Try searching by nickname or name.',
              );
            }

            return Column(
              children: [
                for (final user in users)
                  FutureBuilder<String>(
                    future: friendStatusLabelForUser(
                      firebaseUser.uid,
                      user.uid,
                    ),
                    builder: (context, statusSnapshot) {
                      final status = statusSnapshot.data ?? 'loading';
                      final isFriend = status == 'friends';
                      final incoming = status == 'incoming';
                      final outgoing = status == 'outgoing';

                      return friendUserTile(
                        user: user,
                        subtitle: user.name,
                        onTap: () => openUserProfile(
                          context,
                          uid: user.uid,
                          fallbackUsername: user.username,
                        ),
                        trailing: incoming
                            ? actionButton(
                                label: 'Accept',
                                onPressed: () async {
                                  final doc = await friendRequestsCollection()
                                      .doc(
                                        friendRequestIdFor(
                                          user.uid,
                                          firebaseUser.uid,
                                        ),
                                      )
                                      .get();
                                  if (doc.exists) {
                                    await acceptRequest(
                                      FriendRequestData.fromFirestore(doc),
                                    );
                                  }
                                },
                              )
                            : actionButton(
                                label: isFriend
                                    ? 'Friends'
                                    : outgoing
                                    ? 'Sent'
                                    : status == 'loading'
                                    ? '...'
                                    : 'Add',
                                outlined: isFriend || outgoing,
                                onPressed:
                                    (isFriend ||
                                        outgoing ||
                                        status == 'loading')
                                    ? null
                                    : () => sendRequest(user),
                              ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<String> friendStatusLabelForUser(
    String currentUid,
    String otherUid,
  ) async {
    if (await areUsersFriends(currentUid, otherUid)) {
      return 'friends';
    }

    return await pendingRequestStatusBetweenUsers(currentUid, otherUid) ??
        'none';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Friends'),
          backgroundColor: Colors.transparent,
          foregroundColor: blue,
          bottom: TabBar(
            indicatorColor: blue,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(icon: const Icon(Icons.group), text: trText('Friends')),
              Tab(
                icon: const Icon(Icons.mark_email_unread_outlined),
                text: trText('Requests'),
              ),
              Tab(icon: const Icon(Icons.person_search), text: trText('Find')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: friendsTab(),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: requestsTab(),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: findUsersTab(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final UserProfileData profile;
  final String garageValue;
  final String spotsValue;
  final VoidCallback onEdit;

  const _ProfileHeader({
    required this.profile,
    required this.garageValue,
    required this.spotsValue,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: blue.withValues(alpha: 0.5)),
                ),
                child: ClipOval(
                  child: localFileExists(profile.avatarPath)
                      ? Image.file(
                          File(profile.avatarPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) {
                            return const Center(
                              child: Text(
                                'CCS',
                                style: TextStyle(
                                  color: blue,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            );
                          },
                        )
                      : isNetworkUrl(profile.photoUrl)
                      ? Image.network(
                          profile.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) {
                            return const Center(
                              child: Text(
                                'CCS',
                                style: TextStyle(
                                  color: blue,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            );
                          },
                        )
                      : const Center(
                          child: Text(
                            'CCS',
                            style: TextStyle(
                              color: blue,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            profile.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (userRoleIsStaff(currentUser.role)) ...[
                          const SizedBox(width: 8),
                          _ProfileRoleBadge(role: currentUser.role),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.bio,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _MiniProfileInfoChip(
                              icon: Icons.location_on,
                              label: profile.cityCountry,
                            ),
                            const SizedBox(width: 6),
                            _MiniProfileInfoChip(
                              icon: Icons.directions_car,
                              label: garageValue,
                            ),
                            const SizedBox(width: 6),
                            _MiniProfileInfoChip(
                              icon: Icons.add_location_alt,
                              label: spotsValue,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('Edit Profile'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRoleBadge extends StatelessWidget {
  final UserRole role;

  const _ProfileRoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == UserRole.admin;
    final color = isAdmin ? Colors.redAccent : blue;
    final label = isAdmin ? 'Admin' : 'Mod';
    final icon = isAdmin ? Icons.shield : Icons.shield_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniProfileInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MiniProfileInfoChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: blue.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: blue, size: 12),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 74),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9.3,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _ProfileStatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: blue, size: 21),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _GarageGalleryHeader extends StatefulWidget {
  final GarageCar car;

  const _GarageGalleryHeader({required this.car});

  @override
  State<_GarageGalleryHeader> createState() => _GarageGalleryHeaderState();
}

class _GarageGalleryHeaderState extends State<_GarageGalleryHeader> {
  int currentIndex = 0;

  List<String> get photos => widget.car.galleryPhotos;

  void openGallery(int index) {
    if (photos.isEmpty) {
      return;
    }

    Navigator.push(
      context,
      appPageRoute(
        builder: (_) =>
            GaragePhotoGalleryScreen(car: widget.car, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentIndex >= photos.length) {
      currentIndex = photos.isEmpty ? 0 : photos.length - 1;
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: garagePhotoAspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTap: () => openGallery(currentIndex),
                  child: photos.isEmpty
                      ? const _GaragePhotoFallback()
                      : garagePhotoImage(
                          photos[currentIndex],
                          fit: BoxFit.cover,
                        ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.72),
                      ],
                    ),
                  ),
                ),
                if (photos.length > 1)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        '${currentIndex + 1}/${photos.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 270),
                      child: Text(
                        widget.car.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => openGallery(currentIndex),
                      splashColor: Colors.white10,
                      highlightColor: Colors.white.withValues(alpha: 0.04),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (photos.length > 1)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              color: Colors.black,
              child: Row(
                children: [
                  for (var index = 0; index < photos.length; index++) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => currentIndex = index),
                        onLongPress: () => openGallery(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: 70,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: currentIndex == index
                                ? [
                                    BoxShadow(
                                      color: blue.withValues(alpha: 0.36),
                                      blurRadius: 14,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          foregroundDecoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: currentIndex == index
                                  ? blue
                                  : Colors.white24,
                              width: currentIndex == index ? 2.2 : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              garagePhotoImage(
                                photos[index],
                                fit: BoxFit.cover,
                              ),
                              if (currentIndex == index)
                                Container(
                                  decoration: BoxDecoration(
                                    color: blue.withValues(alpha: 0.16),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (index != photos.length - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class GaragePhotoGalleryScreen extends StatefulWidget {
  final GarageCar car;
  final int initialIndex;

  const GaragePhotoGalleryScreen({
    super.key,
    required this.car,
    required this.initialIndex,
  });

  @override
  State<GaragePhotoGalleryScreen> createState() =>
      _GaragePhotoGalleryScreenState();
}

class _GaragePhotoGalleryScreenState extends State<GaragePhotoGalleryScreen> {
  late final PageController controller;
  late int currentIndex;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex.clamp(
      0,
      widget.car.galleryPhotos.length - 1,
    );
    controller = PageController(initialPage: currentIndex);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.car.galleryPhotos;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          photos.isEmpty
              ? widget.car.name
              : '${widget.car.name}  ${currentIndex + 1}/${photos.length}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: photos.isEmpty
          ? const Center(child: _GaragePhotoFallback())
          : PageView.builder(
              controller: controller,
              itemCount: photos.length,
              onPageChanged: (index) => setState(() => currentIndex = index),
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: garagePhotoImage(
                      photos[index],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _GarageCard extends StatelessWidget {
  final GarageCar car;
  final VoidCallback? onEdit;

  const _GarageCard({required this.car, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GarageGalleryHeader(car: car),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  car.description,
                  style: const TextStyle(color: Colors.white70, height: 1.35),
                ),
                if (onEdit != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit Garage'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSocialLinksSection extends StatelessWidget {
  const _ProfileSocialLinksSection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserSettingsData>(
      valueListenable: userSettings,
      builder: (context, settings, _) {
        final links = <Widget>[
          if (settings.instagram.trim().isNotEmpty)
            _SocialLinkRow(
              icon: Icons.camera_alt,
              label: 'Instagram',
              value: settings.instagram,
            ),
          if (settings.tiktok.trim().isNotEmpty)
            _SocialLinkRow(
              icon: Icons.music_note,
              label: 'TikTok',
              value: settings.tiktok,
            ),
          if (settings.telegram.trim().isNotEmpty)
            _SocialLinkRow(
              icon: Icons.send,
              label: 'Telegram',
              value: settings.telegram,
            ),
        ];

        if (links.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: panelGlass,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Social links',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              for (var index = 0; index < links.length; index++) ...[
                if (index > 0) const SizedBox(height: 10),
                links[index],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SocialLinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SocialLinkRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cleanValue = value.trim();

    if (cleanValue.isEmpty) {
      return const SizedBox.shrink();
    }

    return InkWell(
      onTap: () => launchExternalUrl(context, cleanValue),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, color: blue, size: 19),
            const SizedBox(width: 10),
            SizedBox(
              width: 82,
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Text(
                cleanValue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(color: blue),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.open_in_new, color: Colors.white38, size: 15),
          ],
        ),
      ),
    );
  }
}

class _BuildChip extends StatelessWidget {
  final String label;

  const _BuildChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class GarageCarPhoto extends StatefulWidget {
  final GarageCar car;

  const GarageCarPhoto({super.key, required this.car});

  @override
  State<GarageCarPhoto> createState() => _GarageCarPhotoState();
}

class _GarageCarPhotoState extends State<GarageCarPhoto> {
  final PageController controller = PageController();
  int currentIndex = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.car.galleryPhotos;

    if (photos.isEmpty) {
      return const _GaragePhotoFallback();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              appPageRoute(
                builder: (_) => GaragePhotoGalleryScreen(
                  car: widget.car,
                  initialIndex: currentIndex,
                ),
              ),
            );
          },
          child: PageView.builder(
            controller: controller,
            itemCount: photos.length,
            onPageChanged: (index) => setState(() => currentIndex = index),
            itemBuilder: (context, index) {
              return garagePhotoImage(photos[index], fit: BoxFit.cover);
            },
          ),
        ),
        if (photos.length > 1)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                '${currentIndex + 1}/${photos.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Widget garagePhotoImage(
  String source, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  if (localFileExists(source)) {
    return Image.file(
      File(source),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => const _GaragePhotoFallback(),
    );
  }

  if (isNetworkUrl(source)) {
    return Image.network(
      source,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => const _GaragePhotoFallback(),
    );
  }

  return const _GaragePhotoFallback();
}

class _GaragePhotoFallback extends StatelessWidget {
  const _GaragePhotoFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white10,
      child: const Icon(Icons.directions_car, color: blue, size: 54),
    );
  }
}

class _ProfileStyleSection extends StatelessWidget {
  final List<String> tags;

  const _ProfileStyleSection({required this.tags});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Garage tags',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (tags.isEmpty)
                const _SmallTag(label: 'No tags yet', icon: Icons.local_offer)
              else
                for (final tag in tags)
                  _SmallTag(label: tag, icon: Icons.local_offer),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileSubmissionsPreview extends StatelessWidget {
  final List<CarSpot> spots;

  const _ProfileSubmissionsPreview({required this.spots});

  @override
  Widget build(BuildContext context) {
    final latest = spots.isEmpty ? null : spots.first;
    final pendingCount = spots
        .where((spot) => spot.status == SpotStatus.pending)
        .length;
    final liveCount = spots
        .where((spot) => spot.status == SpotStatus.approved)
        .length;
    final rejectedCount = spots
        .where((spot) => spot.status == SpotStatus.rejected)
        .length;
    final summary = spots.isEmpty
        ? 'No spots created yet.'
        : [
            if (pendingCount > 0) '$pendingCount pending review',
            if (liveCount > 0) '$liveCount live',
            if (rejectedCount > 0) '$rejectedCount rejected',
          ].join(' • ');

    return InkWell(
      onTap: spots.isEmpty
          ? null
          : () {
              Navigator.push(
                context,
                appPageRoute(builder: (_) => const UserSubmissionsScreen()),
              );
            },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Submissions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(summary, style: const TextStyle(color: Colors.white54)),
            if (latest != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  SpotPhoto(
                    spot: latest,
                    width: 64,
                    height: 64,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          latest.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          latest.cityCountry,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54),
                        ),
                        const SizedBox(height: 8),
                        _PendingBadge(status: latest.status),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileSavedSpotsPreview extends StatelessWidget {
  final List<CarSpot> spots;

  const _ProfileSavedSpotsPreview({required this.spots});

  @override
  Widget build(BuildContext context) {
    final visibleSpots = spots.take(3).toList();
    final hiddenCount = spots.length - visibleSpots.length;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          appPageRoute(builder: (_) => const SavedScreen()),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Saved Spots',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${spots.length}',
                  style: const TextStyle(
                    color: blue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              spots.isEmpty
                  ? 'Saved spots will appear here.'
                  : hiddenCount > 0
                  ? 'Your bookmarked car spots. Tap to view all $hiddenCount more.'
                  : 'Your bookmarked car spots. Tap to view all.',
              style: const TextStyle(color: Colors.white54),
            ),
            if (visibleSpots.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (final spot in visibleSpots) ...[
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      appPageRoute(
                        builder: (_) => SpotDetailScreen(spot: spot),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SpotPhoto(
                          spot: spot,
                          width: 54,
                          height: 54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                spot.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                spot.cityCountry,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.white38),
                      ],
                    ),
                  ),
                ),
                if (spot != visibleSpots.last)
                  Divider(color: Colors.white.withValues(alpha: 0.08)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;

  const _ProfileActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color = blue,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  final UserProfileData profile;

  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController usernameController;
  late final TextEditingController cityController;
  late final TextEditingController bioController;
  late final TextEditingController instagramController;
  late final TextEditingController tiktokController;
  late final TextEditingController telegramController;
  String? avatarPath;
  Timer? usernameAvailabilityDebounce;
  UsernameAvailability usernameAvailability = UsernameAvailability.unchanged;

  bool get canSaveProfile {
    return usernameAvailability == UsernameAvailability.unchanged ||
        usernameAvailability == UsernameAvailability.available;
  }

  @override
  void initState() {
    super.initState();
    usernameController = TextEditingController(text: widget.profile.username);
    cityController = TextEditingController(text: widget.profile.cityCountry);
    bioController = TextEditingController(text: widget.profile.bio);
    instagramController = TextEditingController(text: widget.profile.instagram);
    tiktokController = TextEditingController(text: widget.profile.tiktok);
    telegramController = TextEditingController(text: widget.profile.telegram);
    avatarPath = widget.profile.avatarPath;
    usernameController.addListener(queueUsernameAvailabilityCheck);
  }

  @override
  void dispose() {
    usernameAvailabilityDebounce?.cancel();
    usernameController.removeListener(queueUsernameAvailabilityCheck);
    usernameController.dispose();
    cityController.dispose();
    bioController.dispose();
    instagramController.dispose();
    tiktokController.dispose();
    telegramController.dispose();
    super.dispose();
  }

  void queueUsernameAvailabilityCheck() {
    usernameAvailabilityDebounce?.cancel();

    final cleanUsername = cleanProfileUsername(usernameController.text);

    if (cleanUsername.length < minProfileUsernameLength ||
        cleanUsername.length > maxProfileUsernameLength) {
      setState(() => usernameAvailability = UsernameAvailability.invalid);
      return;
    }

    if (usernameKey(cleanUsername) == usernameKey(widget.profile.username)) {
      setState(() => usernameAvailability = UsernameAvailability.unchanged);
      return;
    }

    setState(() => usernameAvailability = UsernameAvailability.checking);

    usernameAvailabilityDebounce = Timer(const Duration(milliseconds: 450), () {
      checkUsernameAvailability(cleanUsername);
    });
  }

  Future<void> checkUsernameAvailability(String usernameToCheck) async {
    final checkedKey = usernameKey(usernameToCheck);
    final availability = await checkUsernameAvailabilityForCurrentUser(
      usernameToCheck,
      currentUsername: widget.profile.username,
    );

    if (!mounted || usernameKey(usernameController.text) != checkedKey) {
      return;
    }

    setState(() => usernameAvailability = availability);
  }

  Future<void> chooseAvatar() async {
    final path = await pickPhotoFromPhone(
      context,
      cropAspectRatio: 1,
      cropShape: PhotoCropShape.circle,
    );

    if (!mounted || path == null) {
      return;
    }

    setState(() => avatarPath = path);
  }

  void saveProfile() {
    if (!canSaveProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            usernameAvailabilityText(usernameAvailability),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      UserProfileData(
        username: usernameController.text.trim().isEmpty
            ? currentUser.username
            : cleanProfileUsername(usernameController.text),
        cityCountry: cityController.text.trim().isEmpty
            ? 'Riga, Latvia'
            : cityController.text.trim(),
        bio: bioController.text.trim().isEmpty
            ? 'Find. Drive. Shoot.'
            : bioController.text.trim(),
        instagram: instagramController.text.trim(),
        tiktok: tiktokController.text.trim(),
        telegram: telegramController.text.trim(),
        avatarPath: avatarPath,
        photoUrl: widget.profile.photoUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: panelGlass,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: chooseAvatar,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      color: blue.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(color: blue.withValues(alpha: 0.5)),
                    ),
                    child: ClipOval(
                      child: localFileExists(avatarPath)
                          ? Image.file(
                              File(avatarPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) {
                                return const Icon(
                                  Icons.add_a_photo,
                                  color: blue,
                                  size: 34,
                                );
                              },
                            )
                          : (isNetworkUrl(avatarPath) ||
                                (currentUser.photoUrl?.trim().isNotEmpty ??
                                    false))
                          ? Image.network(
                              isNetworkUrl(avatarPath)
                                  ? avatarPath!
                                  : currentUser.photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) {
                                return const Icon(
                                  Icons.add_a_photo,
                                  color: blue,
                                  size: 34,
                                );
                              },
                            )
                          : const Icon(
                              Icons.add_a_photo,
                              color: blue,
                              size: 34,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Tap to change avatar',
                  style: TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _AddSpotSection(
            title: 'Profile info',
            children: [
              _CcsTextField(
                controller: usernameController,
                label: 'Nickname',
                hint: 'riga_driver',
                icon: Icons.alternate_email,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    usernameAvailabilityIcon(usernameAvailability),
                    color: usernameAvailabilityColor(usernameAvailability),
                    size: 16,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      usernameAvailabilityText(usernameAvailability),
                      style: TextStyle(
                        color: usernameAvailabilityColor(usernameAvailability),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _CcsTextField(
                controller: cityController,
                label: 'Base',
                hint: 'Riga, Latvia',
                icon: Icons.location_city,
              ),
              const SizedBox(height: 14),
              _CcsTextField(
                controller: bioController,
                label: 'About you',
                hint: 'Short description',
                icon: Icons.notes,
                maxLines: 4,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AddSpotSection(
            title: 'Social links',
            children: [
              _CcsTextField(
                controller: instagramController,
                label: 'Instagram',
                hint: 'https://instagram.com/...',
                icon: Icons.camera_alt,
                keyboardType: TextInputType.url,
              ),
              _CcsTextField(
                controller: tiktokController,
                label: 'TikTok',
                hint: 'https://tiktok.com/@...',
                icon: Icons.music_note,
                keyboardType: TextInputType.url,
              ),
              _CcsTextField(
                controller: telegramController,
                label: 'Telegram',
                hint: 'https://t.me/...',
                icon: Icons.send,
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: canSaveProfile ? saveProfile : null,
              icon: const Icon(Icons.check),
              label: const Text('Save Profile'),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EditGarageScreen extends StatefulWidget {
  final GarageCar? car;

  const EditGarageScreen({super.key, this.car});

  @override
  State<EditGarageScreen> createState() => _EditGarageScreenState();
}

class _EditGarageScreenState extends State<EditGarageScreen> {
  late final TextEditingController nameController;
  late final TextEditingController descriptionController;
  late List<String> photoPaths;

  @override
  void initState() {
    super.initState();
    final car = widget.car;
    nameController = TextEditingController(text: car?.name ?? 'BMW E46 Coupe');
    descriptionController = TextEditingController(text: car?.description ?? '');
    photoPaths = [
      ...(car?.galleryPhotos ?? const <String>[]),
    ].take(maxGaragePhotos).toList();
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> chooseCarPhoto() async {
    if (photoPaths.length >= maxGaragePhotos) {
      return;
    }

    final path = await pickPhotoFromPhone(context);

    if (!mounted || path == null) {
      return;
    }

    setState(
      () => photoPaths = [...photoPaths, path].take(maxGaragePhotos).toList(),
    );
  }

  void removeCarPhoto(int index) {
    if (index < 0 || index >= photoPaths.length) {
      return;
    }

    setState(() => photoPaths = [...photoPaths]..removeAt(index));
  }

  void saveCar() {
    final cleanPhotos = photoPaths
        .map((source) => source.trim())
        .where((source) => source.isNotEmpty)
        .take(maxGaragePhotos)
        .toList();

    Navigator.pop(
      context,
      GarageCar(
        name: nameController.text.trim().isEmpty
            ? 'Untitled car'
            : nameController.text.trim(),
        description: descriptionController.text.trim().isEmpty
            ? 'Car profile.'
            : descriptionController.text.trim(),
        photoPath: cleanPhotos.isEmpty ? null : cleanPhotos.first,
        photoPaths: cleanPhotos,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.car != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Garage' : 'Add Car'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          _AddSpotSection(
            title: 'Car photos',
            children: [
              _GaragePhotoPickerField(
                photoPaths: photoPaths,
                onAddPhoto: chooseCarPhoto,
                onRemovePhoto: removeCarPhoto,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AddSpotSection(
            title: 'Car info',
            children: [
              _CcsTextField(
                controller: nameController,
                label: 'Car name',
                hint: 'BMW E46 Coupe',
                icon: Icons.directions_car,
              ),
              _CcsTextField(
                controller: descriptionController,
                label: 'Description',
                hint: 'Tell people about your car, build, setup, and plans',
                icon: Icons.notes,
                maxLines: 5,
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: saveCar,
              icon: const Icon(Icons.check),
              label: Text(isEditing ? 'Save Garage' : 'Add Car'),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GaragePhotoPickerField extends StatelessWidget {
  final List<String> photoPaths;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;

  const _GaragePhotoPickerField({
    required this.photoPaths,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final canAddMore = photoPaths.length < maxGaragePhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: canAddMore ? onAddPhoto : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: photoPaths.isNotEmpty
                    ? blue.withValues(alpha: 0.7)
                    : Colors.white12,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    canAddMore ? Icons.add_photo_alternate : Icons.check,
                    color: blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        photoPaths.isEmpty
                            ? 'Upload photos'
                            : '${photoPaths.length}/$maxGaragePhotos photos selected',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        canAddMore
                            ? 'Add up to 4 car photos. The first photo becomes the garage cover.'
                            : 'Maximum 4 photos selected. First photo is the garage cover.',
                        style: const TextStyle(
                          color: Colors.white54,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  canAddMore ? Icons.chevron_right : Icons.lock,
                  color: Colors.white54,
                ),
              ],
            ),
          ),
        ),
        if (photoPaths.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var index = 0; index < photoPaths.length; index++)
                Stack(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          appPageRoute(
                            builder: (_) => GaragePhotoGalleryScreen(
                              car: GarageCar(
                                name: 'Garage photos',
                                description: '',
                                photoPaths: photoPaths,
                              ),
                              initialIndex: index,
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: garagePhotoImage(
                          photoPaths[index],
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: index == 0
                              ? blue.withValues(alpha: 0.9)
                              : Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          index == 0 ? 'Cover' : '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: () => onRemovePhoto(index),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.78),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController instagramController;
  late final TextEditingController tiktokController;
  late final TextEditingController telegramController;

  late bool reviewNotifications;
  late bool likeNotifications;
  late bool commentNotifications;
  late bool newSpotNotifications;
  late bool newMessageNotifications;
  late bool publicProfile;
  late bool showGarage;
  bool isSavingSettings = false;

  @override
  void initState() {
    super.initState();
    final settings = userSettings.value;
    instagramController = TextEditingController(text: settings.instagram);
    tiktokController = TextEditingController(text: settings.tiktok);
    telegramController = TextEditingController(text: settings.telegram);
    reviewNotifications = settings.reviewNotifications;
    likeNotifications = settings.likeNotifications;
    commentNotifications = settings.commentNotifications;
    newSpotNotifications = settings.newSpotNotifications;
    newMessageNotifications = settings.newMessageNotifications;
    publicProfile = settings.publicProfile;
    showGarage = settings.showGarage;
  }

  @override
  void dispose() {
    instagramController.dispose();
    tiktokController.dispose();
    telegramController.dispose();
    super.dispose();
  }

  UserSettingsData settingsFromForm() {
    return UserSettingsData(
      instagram: instagramController.text.trim(),
      tiktok: tiktokController.text.trim(),
      telegram: telegramController.text.trim(),
      reviewNotifications: reviewNotifications,
      likeNotifications: likeNotifications,
      commentNotifications: commentNotifications,
      newSpotNotifications: newSpotNotifications,
      newMessageNotifications: newMessageNotifications,
      publicProfile: publicProfile,
      showGarage: showGarage,
    );
  }

  Future<void> persistSettings({bool showSuccessMessage = false}) async {
    if (isSavingSettings) {
      return;
    }

    setState(() => isSavingSettings = true);

    try {
      await saveSettingsToFirebase(settingsFromForm());

      if (!mounted) {
        return;
      }

      if (showSuccessMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: blue,
            content: Text(
              'Settings saved to your account.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not save settings: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSavingSettings = false);
      }
    }
  }

  Future<void> updateSettingsSwitch(VoidCallback update) async {
    setState(update);
    await persistSettings();
  }

  Future<void> saveSettings() async {
    await persistSettings(showSuccessMessage: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          _AddSpotSection(
            title: 'Notifications',
            children: [
              _SettingsSwitchTile(
                icon: Icons.verified,
                title: 'Spot review updates',
                subtitle: 'Approved or rejected spot submissions',
                value: reviewNotifications,
                onChanged: (value) =>
                    updateSettingsSwitch(() => reviewNotifications = value),
              ),
              _SettingsSwitchTile(
                icon: Icons.favorite,
                title: 'Likes on my spots',
                subtitle: 'When people like your approved spots',
                value: likeNotifications,
                onChanged: (value) =>
                    updateSettingsSwitch(() => likeNotifications = value),
              ),
              _SettingsSwitchTile(
                icon: Icons.chat_bubble,
                title: 'Comments',
                subtitle: 'Future comments and community replies',
                value: commentNotifications,
                onChanged: (value) =>
                    updateSettingsSwitch(() => commentNotifications = value),
              ),
              _SettingsSwitchTile(
                icon: Icons.map,
                title: 'New spots',
                subtitle: 'Fresh approved locations nearby',
                value: newSpotNotifications,
                onChanged: (value) =>
                    updateSettingsSwitch(() => newSpotNotifications = value),
              ),
              _SettingsSwitchTile(
                icon: Icons.mark_chat_unread,
                title: 'Messages',
                subtitle: 'New direct and group messages',
                value: newMessageNotifications,
                onChanged: (value) =>
                    updateSettingsSwitch(() => newMessageNotifications = value),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AddSpotSection(
            title: 'Privacy',
            children: [
              _SettingsSwitchTile(
                icon: Icons.public,
                title: 'Public profile',
                subtitle: 'Let other drivers see your profile',
                value: publicProfile,
                onChanged: (value) =>
                    updateSettingsSwitch(() => publicProfile = value),
              ),
              _SettingsSwitchTile(
                icon: Icons.directions_car,
                title: 'Show garage',
                subtitle: 'Display your car builds on your profile',
                value: showGarage,
                onChanged: (value) =>
                    updateSettingsSwitch(() => showGarage = value),
              ),
            ],
          ),

          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: isSavingSettings ? null : saveSettings,
              icon: Icon(isSavingSettings ? Icons.hourglass_top : Icons.check),
              label: const Text('Save Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: appSurfaceOverlay,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: appOutline),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: blue,
        secondary: Icon(icon, color: blue),
        title: Text(
          title,
          style: TextStyle(color: appPrimaryText, fontWeight: FontWeight.w800),
        ),
        subtitle: Text(subtitle, style: TextStyle(color: appSecondaryText)),
      ),
    );
  }
}

class AdminUserData {
  final String uid;
  final String username;
  final String name;
  final String email;
  final UserRole role;
  final bool verified;
  final bool banned;
  final int? bannedUntilMillis;
  final bool deleted;

  const AdminUserData({
    required this.uid,
    required this.username,
    required this.name,
    required this.email,
    required this.role,
    required this.verified,
    required this.banned,
    this.bannedUntilMillis,
    required this.deleted,
  });

  bool get banActive {
    return banned &&
        (bannedUntilMillis == null ||
            bannedUntilMillis! > DateTime.now().millisecondsSinceEpoch);
  }

  String get statusLabel {
    if (deleted) {
      return 'Deleted';
    }

    return userBanLabel(banned: banned, bannedUntilMillis: bannedUntilMillis);
  }

  factory AdminUserData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final bannedUntilMillis = nullableTimestampMillisFromFirebase(
      data['bannedUntil'],
    );

    return AdminUserData(
      uid: stringFromFirebase(data['uid'], doc.id),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      name: stringFromFirebase(data['name'], 'CCS Driver'),
      email: stringFromFirebase(data['email'], ''),
      role: roleFromFirebase(data['role']),
      verified:
          roleFromFirebase(data['role']) == UserRole.admin ||
          data['verified'] == true,
      banned: data['banned'] == true,
      bannedUntilMillis: bannedUntilMillis,
      deleted: data['deleted'] == true,
    );
  }
}

class AdminVerifiedUsersScreen extends StatelessWidget {
  const AdminVerifiedUsersScreen({super.key});

  Future<void> setVerifiedStatus(
    BuildContext context,
    AdminUserData user,
    bool verified,
  ) async {
    if (currentUser.role != UserRole.admin) {
      showAdminActionError(
        context,
        message: 'Only admins can change verified status',
        error: 'not-admin',
      );
      return;
    }

    try {
      await usersCollection().doc(user.uid).set({
        'verified': verified,
        'verifiedUpdatedByUid': currentUser.uid,
        'verifiedUpdatedBy': currentUser.username,
        'verifiedUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (user.uid == currentUser.uid) {
        setCurrentUser(
          AppUser(
            uid: currentUser.uid,
            name: currentUser.name,
            username: currentUser.username,
            email: currentUser.email,
            photoUrl: currentUser.photoUrl,
            bio: currentUser.bio,
            avatarPath: currentUser.avatarPath,
            role: currentUser.role,
            verified: verified || userRoleIsStaff(currentUser.role),
            city: currentUser.city,
            country: currentUser.country,
          ),
        );
      }
    } catch (error) {
      showAdminActionError(
        context,
        message: 'Could not update verified status',
        error: error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Verified Users'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: usersCollection().orderBy('usernameKey').snapshots(),
        builder: (context, snapshot) {
          final users =
              snapshot.data?.docs
                  .map((doc) => AdminUserData.fromFirestore(doc))
                  .where((user) => !user.deleted)
                  .toList() ??
              const <AdminUserData>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              const Text(
                'Grant verified status',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Verified users can create and see verified-only spots.',
                style: TextStyle(color: Colors.white54, height: 1.35),
              ),
              const SizedBox(height: 18),
              if (users.isEmpty)
                const EmptyStateCard(
                  icon: Icons.verified_user,
                  title: 'No users yet',
                  text: 'Users will appear here after they sign in.',
                )
              else
                for (final user in users) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: panelGlass,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: user.verified
                                ? blue.withValues(alpha: 0.16)
                                : Colors.white.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            user.verified
                                ? Icons.verified
                                : Icons.person_outline,
                            color: user.verified ? blue : Colors.white54,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      user.username,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (userRoleIsStaff(user.role)) ...[
                                    const SizedBox(width: 6),
                                    _ProfileRoleBadge(role: user.role),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                user.email.isEmpty ? user.name : user.email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: user.verified,
                          activeThumbColor: blue,
                          onChanged: user.role == UserRole.admin
                              ? null
                              : (value) =>
                                    setVerifiedStatus(context, user, value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          );
        },
      ),
    );
  }
}

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  Future<bool> canManageUser(BuildContext context, AdminUserData user) async {
    if (user.uid == currentUser.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'You cannot manage your own account here.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return false;
    }

    if (user.role == UserRole.admin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Admin accounts cannot be managed here.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return false;
    }

    if (currentUser.role == UserRole.moderator &&
        user.role == UserRole.moderator) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Moderators cannot manage other moderators.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return false;
    }

    return true;
  }

  Future<void> setModeratorStatus(
    BuildContext context,
    AdminUserData user,
    bool makeModerator,
  ) async {
    if (currentUser.role != UserRole.admin) {
      showAdminActionError(
        context,
        message: 'Only admins can change roles',
        error: 'not-admin',
      );
      return;
    }

    if (user.uid == currentUser.uid || user.role == UserRole.admin) {
      showAdminActionError(
        context,
        message: 'This role cannot be changed here',
        error: 'protected-user',
      );
      return;
    }

    try {
      await usersCollection().doc(user.uid).set({
        'role': makeModerator ? 'moderator' : 'user',
        'roleUpdatedByUid': currentUser.uid,
        'roleUpdatedBy': currentUser.username,
        'roleUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: blue,
            content: Text(
              makeModerator ? 'Moderator assigned.' : 'Moderator removed.',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      showAdminActionError(
        context,
        message: 'Could not update role',
        error: error,
      );
    }
  }

  Future<void> banUser(
    BuildContext context,
    AdminUserData user, {
    Duration? duration,
  }) async {
    if (!await canManageUser(context, user)) {
      return;
    }

    final bannedUntil = duration == null
        ? null
        : Timestamp.fromDate(DateTime.now().add(duration));

    try {
      await usersCollection().doc(user.uid).set({
        'banned': true,
        'bannedUntil': bannedUntil,
        'bannedByUid': currentUser.uid,
        'bannedBy': currentUser.username,
        'bannedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              duration == null ? 'User banned.' : 'User temporarily banned.',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      showAdminActionError(
        context,
        message: 'Could not ban user',
        error: error,
      );
    }
  }

  Future<void> unbanUser(BuildContext context, AdminUserData user) async {
    if (!await canManageUser(context, user)) {
      return;
    }

    try {
      await usersCollection().doc(user.uid).set({
        'banned': false,
        'bannedUntil': FieldValue.delete(),
        'unbannedByUid': currentUser.uid,
        'unbannedBy': currentUser.username,
        'unbannedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: blue,
            content: Text(
              'User unbanned.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      showAdminActionError(
        context,
        message: 'Could not unban user',
        error: error,
      );
    }
  }

  Future<void> deleteUser(BuildContext context, AdminUserData user) async {
    if (!await canManageUser(context, user)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: const Text('Delete user?'),
          content: Text(
            'This will remove ${displayUsername(user.username)} from the users list.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await usersCollection().doc(user.uid).set({
        'deleted': true,
        'banned': true,
        'bannedUntil': null,
        'publicProfile': false,
        'photoUrl': '',
        'avatarPath': null,
        'bio': 'Profile removed.',
        'garage': <Object>[],
        'settings': const UserSettingsData(
          instagram: '',
          tiktok: '',
          telegram: '',
          reviewNotifications: false,
          likeNotifications: false,
          commentNotifications: false,
          newSpotNotifications: false,
          newMessageNotifications: false,
          publicProfile: false,
          showGarage: false,
        ).toFirebase(),
        'deletedByUid': currentUser.uid,
        'deletedBy': currentUser.username,
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'User deleted.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      showAdminActionError(
        context,
        message: 'Could not delete user',
        error: error,
      );
    }
  }

  void handleUserAction(
    BuildContext context,
    AdminUserData user,
    String action,
  ) {
    switch (action) {
      case 'open':
        openUserProfile(
          context,
          uid: user.uid,
          fallbackUsername: user.username,
        );
        break;
      case 'ban_1d':
        banUser(context, user, duration: const Duration(days: 1));
        break;
      case 'ban_7d':
        banUser(context, user, duration: const Duration(days: 7));
        break;
      case 'ban_30d':
        banUser(context, user, duration: const Duration(days: 30));
        break;
      case 'ban_forever':
        banUser(context, user);
        break;
      case 'unban':
        unbanUser(context, user);
        break;
      case 'make_moderator':
        setModeratorStatus(context, user, true);
        break;
      case 'remove_moderator':
        setModeratorStatus(context, user, false);
        break;
      case 'delete':
        deleteUser(context, user);
        break;
    }
  }

  Widget userTile(BuildContext context, AdminUserData user) {
    final statusColor = user.banActive
        ? Colors.redAccent
        : user.verified
        ? blue
        : Colors.white54;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(
              user.banActive
                  ? Icons.block
                  : user.verified
                  ? Icons.verified
                  : Icons.person_outline,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => openUserProfile(
                context,
                uid: user.uid,
                fallbackUsername: user.username,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (userRoleIsStaff(user.role)) ...[
                          const SizedBox(width: 6),
                          _ProfileRoleBadge(role: user.role),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.email.isEmpty ? user.name : user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      user.statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            color: panelGlass,
            iconColor: Colors.white70,
            onSelected: (action) => handleUserAction(context, user, action),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'open', child: Text('Open profile')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'ban_1d', child: Text('Ban 1 day')),
              const PopupMenuItem(value: 'ban_7d', child: Text('Ban 7 days')),
              const PopupMenuItem(value: 'ban_30d', child: Text('Ban 30 days')),
              const PopupMenuItem(
                value: 'ban_forever',
                child: Text('Ban forever'),
              ),
              if (user.banned)
                const PopupMenuItem(value: 'unban', child: Text('Unban')),
              if (currentUser.role == UserRole.admin) ...[
                const PopupMenuDivider(),
                if (user.role == UserRole.user)
                  const PopupMenuItem(
                    value: 'make_moderator',
                    child: Text('Make moderator'),
                  ),
                if (user.role == UserRole.moderator)
                  const PopupMenuItem(
                    value: 'remove_moderator',
                    child: Text('Remove moderator'),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Delete user',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Users'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: usersCollection().orderBy('usernameKey').snapshots(),
        builder: (context, snapshot) {
          final users =
              snapshot.data?.docs
                  .map((doc) => AdminUserData.fromFirestore(doc))
                  .where((user) => !user.deleted)
                  .toList() ??
              const <AdminUserData>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              const Text(
                'Users',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                users.isEmpty
                    ? 'No users yet.'
                    : '${users.length} user${users.length == 1 ? '' : 's'} in Firebase.',
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
              const SizedBox(height: 18),
              if (users.isEmpty)
                const EmptyStateCard(
                  icon: Icons.people_outline,
                  title: 'No users yet',
                  text: 'Users will appear here after they sign in.',
                )
              else
                for (final user in users) ...[
                  userTile(context, user),
                  const SizedBox(height: 10),
                ],
            ],
          );
        },
      ),
    );
  }
}

enum AdminSpotFilter { pending, edited, approved, rejected, all }

String adminSpotFilterLabel(AdminSpotFilter filter) {
  switch (filter) {
    case AdminSpotFilter.pending:
      return 'Pending';
    case AdminSpotFilter.edited:
      return 'Edited';
    case AdminSpotFilter.approved:
      return 'Approved';
    case AdminSpotFilter.rejected:
      return 'Rejected';
    case AdminSpotFilter.all:
      return 'All';
  }
}

List<CarSpot> adminSpotsForFilter(AdminSpotFilter filter) {
  final spots = reviewSpots.value;

  switch (filter) {
    case AdminSpotFilter.pending:
      return spots.where((spot) => spot.status == SpotStatus.pending).toList();
    case AdminSpotFilter.edited:
      return spots.where((spot) => spot.status == SpotStatus.edited).toList();
    case AdminSpotFilter.approved:
      return spots.where((spot) => spot.status == SpotStatus.approved).toList();
    case AdminSpotFilter.rejected:
      return spots.where((spot) => spot.status == SpotStatus.rejected).toList();
    case AdminSpotFilter.all:
      return spots;
  }
}

int adminSpotCount(AdminSpotFilter filter) {
  return adminSpotsForFilter(filter).length;
}

String adminEmptyTitle(AdminSpotFilter filter) {
  switch (filter) {
    case AdminSpotFilter.pending:
      return 'No pending spots';
    case AdminSpotFilter.edited:
      return 'No edited spots';
    case AdminSpotFilter.approved:
      return 'No approved spots';
    case AdminSpotFilter.rejected:
      return 'No rejected spots';
    case AdminSpotFilter.all:
      return 'No community spots yet';
  }
}

String adminEmptyText(AdminSpotFilter filter) {
  switch (filter) {
    case AdminSpotFilter.pending:
      return 'New user submitted spots will appear here first.';
    case AdminSpotFilter.edited:
      return 'User spot edits will appear here for approval.';
    case AdminSpotFilter.approved:
      return 'Approved spots will appear here after moderation.';
    case AdminSpotFilter.rejected:
      return 'Rejected spots will appear here after moderation.';
    case AdminSpotFilter.all:
      return 'When users submit spots, they will appear in this admin panel.';
  }
}

Future<bool> confirmDeleteSpot(BuildContext context, CarSpot spot) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: panelGlass,
        title: const Text('Delete spot?'),
        content: Text(
          'This will remove "${spot.name}" from Firebase.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      );
    },
  );

  return confirmed == true;
}

void showAdminActionError(
  BuildContext context, {
  required String message,
  required Object error,
}) {
  if (!context.mounted) {
    return;
  }

  final code = error is FirebaseException ? error.code : error.toString();

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Colors.redAccent,
      content: Text(
        '$message: $code',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

Future<void> deleteAdminSpot(
  BuildContext context,
  CarSpot spot, {
  bool popAfterDelete = false,
}) async {
  final confirmed = await confirmDeleteSpot(context, spot);

  if (!confirmed) {
    return;
  }

  try {
    await deleteSpotFromFirebase(spot);

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'Spot deleted.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );

    if (popAfterDelete) {
      Navigator.pop(context);
    }
  } catch (error) {
    showAdminActionError(
      context,
      message: 'Could not delete spot',
      error: error,
    );
  }
}

class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({super.key});

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen> {
  AdminSpotFilter selectedFilter = AdminSpotFilter.pending;

  Widget filterChip(AdminSpotFilter filter) {
    final selected = selectedFilter == filter;
    final count = adminSpotCount(filter);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('${adminSpotFilterLabel(filter)} $count'),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => selectedFilter = filter),
        selectedColor: blue,
        backgroundColor: Colors.white.withValues(alpha: 0.07),
        side: BorderSide(color: selected ? blue : Colors.white12),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          currentUser.role == UserRole.admin
              ? 'Admin Panel'
              : 'Moderator Panel',
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ValueListenableBuilder<List<CarSpot>>(
        valueListenable: reviewSpots,
        builder: (context, _, _) {
          final filteredSpots = adminSpotsForFilter(selectedFilter);
          final label = adminSpotFilterLabel(selectedFilter).toLowerCase();

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Text(
                currentUser.role == UserRole.admin
                    ? 'Admin Review'
                    : 'Moderator Review',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                filteredSpots.isEmpty
                    ? 'No $label spots right now.'
                    : '${filteredSpots.length} $label spot${filteredSpots.length == 1 ? '' : 's'} in Firebase.',
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
              const SizedBox(height: 16),
              _ProfileActionTile(
                icon: Icons.people_alt,
                title: 'Users',
                subtitle: 'Open profiles, ban, unban, or delete users',
                onTap: () {
                  Navigator.push(
                    context,
                    appPageRoute(builder: (_) => const AdminUsersScreen()),
                  );
                },
              ),
              const SizedBox(height: 10),
              if (currentUser.role == UserRole.admin) ...[
                const SizedBox(height: 10),
                _ProfileActionTile(
                  icon: Icons.verified_user,
                  title: 'Verified Users',
                  subtitle: 'Grant or remove verified status',
                  onTap: () {
                    Navigator.push(
                      context,
                      appPageRoute(
                        builder: (_) => const AdminVerifiedUsersScreen(),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    filterChip(AdminSpotFilter.pending),
                    filterChip(AdminSpotFilter.edited),
                    filterChip(AdminSpotFilter.approved),
                    filterChip(AdminSpotFilter.rejected),
                    filterChip(AdminSpotFilter.all),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (filteredSpots.isEmpty)
                EmptyStateCard(
                  icon: Icons.admin_panel_settings,
                  title: adminEmptyTitle(selectedFilter),
                  text: adminEmptyText(selectedFilter),
                )
              else
                for (final spot in filteredSpots) ...[
                  AdminSpotTile(spot: spot),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }
}

class AdminSpotTile extends StatelessWidget {
  final CarSpot spot;

  const AdminSpotTile({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          appPageRoute(builder: (_) => AdminSpotReviewScreen(spot: spot)),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            SpotPhoto(
              spot: spot,
              width: 82,
              height: 82,
              borderRadius: BorderRadius.circular(14),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    spot.cityCountry,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _AdminStatusBadge(status: spot.status),
                      const SizedBox(width: 8),
                      Expanded(
                        child: spot.addedByUid.trim().isEmpty
                            ? Text(
                                'Added by ${spot.addedBy}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white38),
                              )
                            : InkWell(
                                onTap: () => openUserProfile(
                                  context,
                                  uid: spot.addedByUid,
                                  fallbackUsername: spot.addedBy,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                child: Text(
                                  'Added by ${displayUsername(spot.addedBy)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: blue,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit spot',
              onPressed: () => openAdminEditSpot(context, spot),
              icon: const Icon(Icons.edit_outlined, color: blue),
            ),
            IconButton(
              tooltip: 'Delete spot',
              onPressed: () => deleteAdminSpot(context, spot),
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class _AdminStatusBadge extends StatelessWidget {
  final SpotStatus status;

  const _AdminStatusBadge({required this.status});

  Color get color {
    switch (status) {
      case SpotStatus.pending:
        return blue;
      case SpotStatus.approved:
        return Colors.greenAccent;
      case SpotStatus.rejected:
        return Colors.redAccent;
      case SpotStatus.edited:
        return Colors.orangeAccent;
    }
  }

  IconData get icon {
    switch (status) {
      case SpotStatus.pending:
        return Icons.hourglass_bottom;
      case SpotStatus.approved:
        return Icons.check_circle;
      case SpotStatus.rejected:
        return Icons.cancel;
      case SpotStatus.edited:
        return Icons.edit_note;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            spotStatusName(status),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openAdminEditSpot(
  BuildContext context,
  CarSpot spot, {
  bool popAfterSave = false,
}) async {
  final saved = await Navigator.push<bool>(
    context,
    appPageRoute(builder: (_) => AdminEditSpotScreen(spot: spot)),
  );

  if (saved == true && popAfterSave && context.mounted) {
    Navigator.pop(context);
  }
}

class AdminEditSpotScreen extends StatefulWidget {
  final CarSpot spot;

  const AdminEditSpotScreen({super.key, required this.spot});

  @override
  State<AdminEditSpotScreen> createState() => _AdminEditSpotScreenState();
}

class _AdminEditSpotScreenState extends State<AdminEditSpotScreen> {
  late final TextEditingController nameController;
  late final TextEditingController cityController;
  late final TextEditingController latController;
  late final TextEditingController lngController;
  late final TextEditingController descriptionController;
  late final TextEditingController reelController;
  late final TextEditingController phoneController;
  late final TextEditingController instagramController;
  late final TextEditingController emailController;
  late String selectedCategory;
  late bool verifiedOnlySpot;
  late bool isTemporarySpot;
  DateTime? temporaryStartsAt;
  DateTime? temporaryExpiresAt;
  bool temporaryShowOnMapAtEnabled = false;
  DateTime? temporaryShowOnMapAt;
  late final List<String> existingPhotoUrls;
  final List<String> newPhotoPaths = [];
  late Map<int, OpeningHoursData> openingHours;
  SpotOwnerAssignment? selectedOwner;
  bool isSaving = false;

  int get totalPhotoCount => existingPhotoUrls.length + newPhotoPaths.length;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.spot.name);
    cityController = TextEditingController(text: widget.spot.cityCountry);
    latController = TextEditingController(
      text: widget.spot.coordinates.latitude.toStringAsFixed(6),
    );
    lngController = TextEditingController(
      text: widget.spot.coordinates.longitude.toStringAsFixed(6),
    );
    descriptionController = TextEditingController(
      text: widget.spot.description,
    );
    reelController = TextEditingController(text: widget.spot.reelLink);
    phoneController = TextEditingController(text: widget.spot.contactPhone);
    instagramController = TextEditingController(
      text: widget.spot.contactInstagram,
    );
    emailController = TextEditingController(text: widget.spot.contactEmail);
    if (widget.spot.ownerUid.isNotEmpty ||
        widget.spot.ownerUsername.isNotEmpty) {
      selectedOwner = SpotOwnerAssignment(
        uid: widget.spot.ownerUid,
        username: widget.spot.ownerUsername.isNotEmpty
            ? widget.spot.ownerUsername
            : widget.spot.ownerUid,
      );
    }
    selectedCategory = primarySpotCategory(widget.spot);
    verifiedOnlySpot = widget.spot.verifiedOnly;
    isTemporarySpot = widget.spot.isTemporary;
    temporaryStartsAt = widget.spot.startsAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(widget.spot.startsAtMillis!);
    temporaryExpiresAt = widget.spot.expiresAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(widget.spot.expiresAtMillis!);
    temporaryShowOnMapAtEnabled = widget.spot.showOnMapAtMillis != null;
    temporaryShowOnMapAt = widget.spot.showOnMapAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(widget.spot.showOnMapAtMillis!);
    openingHours = widget.spot.openingHours.isEmpty
        ? defaultServiceOpeningHours()
        : {...widget.spot.openingHours};
    existingPhotoUrls = <String>[];

    void addExistingUrl(String value) {
      final cleanValue = value.trim();
      if (cleanValue.isNotEmpty &&
          isNetworkUrl(cleanValue) &&
          !existingPhotoUrls.contains(cleanValue)) {
        existingPhotoUrls.add(cleanValue);
      }
    }

    for (final photoUrl in widget.spot.photoUrls) {
      addExistingUrl(photoUrl);
    }
    addExistingUrl(widget.spot.photoUrl);
  }

  @override
  void dispose() {
    nameController.dispose();
    cityController.dispose();
    latController.dispose();
    lngController.dispose();
    descriptionController.dispose();
    reelController.dispose();
    phoneController.dispose();
    instagramController.dispose();
    emailController.dispose();
    super.dispose();
  }

  Future<void> addPhoto() async {
    if (totalPhotoCount >= maxSpotGalleryPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Maximum 4 spot photos.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final path = await pickPhotoFromPhone(context);
    if (!mounted || path == null || path.trim().isEmpty) {
      return;
    }

    if (newPhotoPaths.contains(path)) {
      return;
    }

    setState(() => newPhotoPaths.add(path));
  }

  void removeExistingPhotoAt(int index) {
    if (index < 0 || index >= existingPhotoUrls.length) {
      return;
    }

    setState(() => existingPhotoUrls.removeAt(index));
  }

  void removeNewPhotoAt(int index) {
    if (index < 0 || index >= newPhotoPaths.length) {
      return;
    }

    setState(() => newPhotoPaths.removeAt(index));
  }

  Future<DateTime?> pickTemporaryDateTime(DateTime? initialValue) async {
    final now = DateTime.now();
    final initial = initialValue ?? now.add(const Duration(hours: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(data: ThemeData.dark(), child: child!);
      },
    );

    if (date == null || !mounted) {
      return null;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) {
        return Theme(data: ThemeData.dark(), child: child!);
      },
    );

    if (time == null) {
      return null;
    }

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> chooseTemporaryStart() async {
    final value = await pickTemporaryDateTime(temporaryStartsAt);

    if (!mounted || value == null) {
      return;
    }

    setState(() {
      temporaryStartsAt = value;
      if (temporaryExpiresAt == null ||
          !temporaryExpiresAt!.isAfter(value) ||
          temporaryExpiresAt!.difference(value) > maxTemporarySpotDuration) {
        temporaryExpiresAt = value.add(const Duration(hours: 3));
      }
    });
  }

  Future<void> chooseTemporaryEnd() async {
    final fallback = temporaryStartsAt?.add(const Duration(hours: 3));
    final value = await pickTemporaryDateTime(temporaryExpiresAt ?? fallback);

    if (!mounted || value == null) {
      return;
    }

    setState(() => temporaryExpiresAt = value);
  }

  Future<void> chooseTemporaryShowOnMapAt() async {
    final fallback = temporaryStartsAt == null
        ? DateTime.now().add(const Duration(hours: 1))
        : DateTime(
            temporaryStartsAt!.year,
            temporaryStartsAt!.month,
            temporaryStartsAt!.day,
          );
    final value = await pickTemporaryDateTime(temporaryShowOnMapAt ?? fallback);

    if (!mounted || value == null) {
      return;
    }

    setState(() => temporaryShowOnMapAt = value);
  }

  Future<void> saveSpot() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final isOwner = widget.spot.addedByUid == firebaseUser?.uid;
    final isStaff = userRoleIsStaff(currentUser.role);
    if (firebaseUser == null || (!isOwner && !isStaff)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Only the assigned owner or an admin can edit this spot.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final cleanName = nameController.text.trim();
    final cleanCity = cityController.text.trim();
    final cleanDescription = descriptionController.text.trim();
    final editedLatitude = double.tryParse(
      latController.text.trim().replaceAll(',', '.'),
    );
    final editedLongitude = double.tryParse(
      lngController.text.trim().replaceAll(',', '.'),
    );
    final cleanReel = reelController.text.trim();
    final cleanPhone = phoneController.text.trim();
    final cleanInstagram = instagramController.text.trim();
    final cleanEmail = emailController.text.trim();
    final supportsContacts = spotCategorySupportsContacts(selectedCategory);
    final owner = supportsContacts ? selectedOwner : null;

    if (widget.spot.id.trim().isEmpty) {
      showAdminActionError(
        context,
        message: 'Could not save spot',
        error: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'missing-spot-id',
        ),
      );
      return;
    }

    if (editedLatitude == null ||
        editedLongitude == null ||
        editedLatitude < -90 ||
        editedLatitude > 90 ||
        editedLongitude < -180 ||
        editedLongitude > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Enter valid latitude and longitude.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (cleanName.isEmpty || cleanDescription.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Spot name and description are required.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (isTemporarySpot) {
      final startsAt = temporaryStartsAt;
      final expiresAt = temporaryExpiresAt;

      if (startsAt == null || expiresAt == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Choose both start and end time for a temporary spot.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      if (!expiresAt.isAfter(startsAt)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Temporary spot end time must be after start time.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      if (expiresAt.difference(startsAt) > maxTemporarySpotDuration) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Temporary spot can be active for 12 hours maximum.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      if (temporaryShowOnMapAtEnabled) {
        final showOnMapAt = temporaryShowOnMapAt;
        if (showOnMapAt == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text(
                'Choose when the temporary spot location should appear on the map.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
          return;
        }

        if (!showOnMapAt.isBefore(expiresAt)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text(
                'Show on map time must be before the end time.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
          return;
        }
      }
    }

    setState(() => isSaving = true);

    try {
      final finalPhotoUrls = <String>[...existingPhotoUrls];

      for (final localPhotoPath in newPhotoPaths) {
        final uploadIndex = finalPhotoUrls.length;
        final uploadedUrl = await uploadSpotPhoto(
          spotId: widget.spot.id,
          localPhotoPath: localPhotoPath,
          userId: firebaseUser.uid,
          photoIndex: uploadIndex,
        );
        finalPhotoUrls.add(uploadedUrl);
      }

      final updatedSpot = widget.spot.copyWith(
        name: cleanName,
        cityCountry: cleanCity.isEmpty ? widget.spot.cityCountry : cleanCity,
        description: cleanDescription,
        coordinates: safeLatLng(editedLatitude, editedLongitude),
        categories: [selectedCategory],
        reelLink: cleanReel,
        contactPhone: supportsContacts ? cleanPhone : '',
        contactInstagram: supportsContacts ? cleanInstagram : '',
        contactEmail: supportsContacts ? cleanEmail : '',
        openingHours: supportsContacts ? openingHours : const {},
        ownerUid: supportsContacts ? (owner?.uid ?? '') : '',
        ownerUsername: supportsContacts ? (owner?.username ?? '') : '',
        photoUrl: finalPhotoUrls.isEmpty ? '' : finalPhotoUrls.first,
        photoUrls: finalPhotoUrls,
        verifiedOnly: verifiedOnlySpot,
        isTemporary: isTemporarySpot,
        startsAtMillis: isTemporarySpot
            ? temporaryStartsAt!.millisecondsSinceEpoch
            : null,
        expiresAtMillis: isTemporarySpot
            ? temporaryExpiresAt!.millisecondsSinceEpoch
            : null,
        showOnMapAtMillis: isTemporarySpot && temporaryShowOnMapAtEnabled
            ? temporaryShowOnMapAt!.millisecondsSinceEpoch
            : null,
        clearTemporarySchedule: !isTemporarySpot,
        clearTemporaryMapReveal:
            !isTemporarySpot || !temporaryShowOnMapAtEnabled,
      );

      final editChangeSummary = <String>[];
      if (widget.spot.name != updatedSpot.name)
        editChangeSummary.add(
          'Name: ${widget.spot.name} → ${updatedSpot.name}',
        );
      if (widget.spot.cityCountry != updatedSpot.cityCountry)
        editChangeSummary.add(
          'Location text: ${widget.spot.cityCountry} → ${updatedSpot.cityCountry}',
        );
      if (widget.spot.description != updatedSpot.description)
        editChangeSummary.add('Description changed');
      if ((widget.spot.coordinates.latitude - updatedSpot.coordinates.latitude)
                  .abs() >
              0.000001 ||
          (widget.spot.coordinates.longitude -
                      updatedSpot.coordinates.longitude)
                  .abs() >
              0.000001) {
        editChangeSummary.add('Map position changed');
      }
      if (primarySpotCategory(widget.spot) !=
          primarySpotCategory(updatedSpot)) {
        editChangeSummary.add(
          'Category: ${primarySpotCategory(widget.spot)} → ${primarySpotCategory(updatedSpot)}',
        );
      }
      if (widget.spot.photoUrls.length != updatedSpot.photoUrls.length ||
          widget.spot.photoUrl != updatedSpot.photoUrl) {
        editChangeSummary.add('Photos changed');
      }
      if (widget.spot.isTemporary != updatedSpot.isTemporary ||
          widget.spot.startsAtMillis != updatedSpot.startsAtMillis ||
          widget.spot.expiresAtMillis != updatedSpot.expiresAtMillis ||
          widget.spot.showOnMapAtMillis != updatedSpot.showOnMapAtMillis) {
        editChangeSummary.add('Temporary schedule changed');
      }

      final needsEditReview =
          !userRoleIsStaff(currentUser.role) &&
          widget.spot.addedByUid == currentUser.uid;

      await spotsCollection().doc(widget.spot.id).update({
        'name': updatedSpot.name,
        'cityCountry': updatedSpot.cityCountry,
        'description': updatedSpot.description,
        'lat': updatedSpot.coordinates.latitude,
        'lng': updatedSpot.coordinates.longitude,
        'coordinates': GeoPoint(
          updatedSpot.coordinates.latitude,
          updatedSpot.coordinates.longitude,
        ),
        'categories': updatedSpot.categories,
        'reelLink': updatedSpot.reelLink,
        'contactPhone': updatedSpot.contactPhone,
        'contactInstagram': updatedSpot.contactInstagram,
        'contactEmail': updatedSpot.contactEmail,
        'openingHours': openingHoursToFirebase(updatedSpot.openingHours),
        'ownerUid': updatedSpot.ownerUid,
        'ownerUsername': updatedSpot.ownerUsername,
        'photoUrl': updatedSpot.photoUrl,
        'photoUrls': updatedSpot.photoUrls,
        'verifiedOnly': updatedSpot.verifiedOnly,
        'isTemporary': updatedSpot.isTemporary,
        'startsAt': updatedSpot.startsAtMillis == null
            ? null
            : Timestamp.fromMillisecondsSinceEpoch(updatedSpot.startsAtMillis!),
        'expiresAt': updatedSpot.expiresAtMillis == null
            ? null
            : Timestamp.fromMillisecondsSinceEpoch(
                updatedSpot.expiresAtMillis!,
              ),
        'showOnMapAt': updatedSpot.showOnMapAtMillis == null
            ? null
            : Timestamp.fromMillisecondsSinceEpoch(
                updatedSpot.showOnMapAtMillis!,
              ),
        if (needsEditReview) 'status': 'edited',
        if (needsEditReview) 'editReviewStatus': 'pending',
        if (needsEditReview) 'editChangeSummary': editChangeSummary,
        'editedBy': currentUser.username,
        'editedByUid': currentUser.uid,
        'editedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final visibleUpdatedSpot = needsEditReview
          ? updatedSpot.copyWith(status: SpotStatus.edited)
          : updatedSpot;

      reviewSpots.value = reviewSpots.value
          .map(
            (item) => isSameSpot(item, widget.spot) ? visibleUpdatedSpot : item,
          )
          .toList();
      submittedSpots.value = submittedSpots.value
          .map(
            (item) => isSameSpot(item, widget.spot) ? visibleUpdatedSpot : item,
          )
          .toList();
      savedSpots.value = savedSpots.value
          .map(
            (item) => isSameSpot(item, widget.spot) ? visibleUpdatedSpot : item,
          )
          .toList();

      await refreshFirebaseSpotsFromServer();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: blue,
          content: Text(
            needsEditReview ? 'Spot edit sent for review.' : 'Spot updated.',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAdminActionError(
        context,
        message: 'Could not save spot',
        error: error,
      );
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  Widget photoThumb({
    required int index,
    required String label,
    required String source,
    required VoidCallback onRemove,
    required bool isLocal,
  }) {
    final image = isLocal
        ? Image.file(
            File(source),
            width: 88,
            height: 88,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                _SpotPhotoPlaceholder(width: 88, height: 88),
          )
        : Image.network(
            source,
            width: 88,
            height: 88,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                _SpotPhotoPlaceholder(width: 88, height: 88),
          );

    return Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(14), child: image),
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: index == 0
                  ? blue.withValues(alpha: 0.9)
                  : Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canAddMore = totalPhotoCount < maxSpotGalleryPhotos;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Edit Spot'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          _AddSpotSection(
            title: 'Basic info',
            children: [
              _CcsTextField(
                controller: nameController,
                label: 'Spot name',
                hint: 'Andrejsala Harbor',
                icon: Icons.place,
              ),
              _CcsTextField(
                controller: cityController,
                label: 'City / country',
                hint: 'Riga, Latvia',
                icon: Icons.location_city,
              ),
              Row(
                children: [
                  Expanded(
                    child: _CcsTextField(
                      controller: latController,
                      label: 'Latitude',
                      hint: '56.949600',
                      icon: Icons.my_location,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CcsTextField(
                      controller: lngController,
                      label: 'Longitude',
                      hint: '24.105200',
                      icon: Icons.explore,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                  ),
                ],
              ),
              _CcsTextField(
                controller: descriptionController,
                label: 'Description',
                hint: 'What makes this spot good for car photos?',
                icon: Icons.notes,
                maxLines: 4,
              ),
              _CcsTextField(
                controller: reelController,
                label: 'Instagram / TikTok video link',
                hint: 'https://instagram.com/reel/...',
                icon: Icons.play_circle,
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (spotCategorySupportsContacts(selectedCategory)) ...[
            _AddSpotSection(
              title: 'Contacts',
              children: [
                _CcsTextField(
                  controller: phoneController,
                  label: 'Phone',
                  hint: '+371 20 000 000',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
                _CcsTextField(
                  controller: instagramController,
                  label: 'Instagram',
                  hint: '@ccs.lv or https://instagram.com/ccs.lv',
                  icon: Icons.alternate_email,
                  keyboardType: TextInputType.url,
                ),
                _CcsTextField(
                  controller: emailController,
                  label: 'Email',
                  hint: 'hello@ccs.lv',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                SpotOwnerSelector(
                  selectedOwner: selectedOwner,
                  onChanged: (owner) => setState(() => selectedOwner = owner),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _AddSpotSection(
              title: 'Opening hours',
              children: [
                OpeningHoursEditor(
                  openingHours: openingHours,
                  onChanged: (value) => setState(() => openingHours = value),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          _AddSpotSection(
            title: 'Category',
            children: [
              _SpotCategoryDropdown(
                value: selectedCategory,
                categories: spotCategoryOptions,
                onChanged: (category) {
                  if (category == null) {
                    return;
                  }
                  setState(() => selectedCategory = category);
                },
              ),
            ],
          ),
          if (currentUserCanUseVerifiedOnlySpots) ...[
            const SizedBox(height: 16),
            _AddSpotSection(
              title: 'Visibility',
              children: [
                _SettingsSwitchTile(
                  icon: Icons.verified_user,
                  title: 'Verified only',
                  subtitle:
                      'Only verified users and admins can see this spot after approval',
                  value: verifiedOnlySpot,
                  onChanged: (value) =>
                      setState(() => verifiedOnlySpot = value),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _AddSpotSection(
            title: 'Temporary schedule',
            children: [
              _TemporarySpotScheduleCard(
                enabled: isTemporarySpot,
                startsAt: temporaryStartsAt,
                expiresAt: temporaryExpiresAt,
                showOnMapAtEnabled: temporaryShowOnMapAtEnabled,
                showOnMapAt: temporaryShowOnMapAt,
                onEnabledChanged: (value) {
                  setState(() {
                    isTemporarySpot = value;
                    if (value && temporaryStartsAt == null) {
                      final start = DateTime.now().add(
                        const Duration(hours: 1),
                      );
                      temporaryStartsAt = start;
                      temporaryExpiresAt = start.add(const Duration(hours: 3));
                    }
                    if (!value) {
                      temporaryShowOnMapAtEnabled = false;
                      temporaryShowOnMapAt = null;
                    }
                  });
                },
                onShowOnMapAtEnabledChanged: (value) {
                  setState(() {
                    temporaryShowOnMapAtEnabled = value;
                    if (value &&
                        temporaryShowOnMapAt == null &&
                        temporaryStartsAt != null) {
                      temporaryShowOnMapAt = DateTime(
                        temporaryStartsAt!.year,
                        temporaryStartsAt!.month,
                        temporaryStartsAt!.day,
                      );
                    }
                    if (!value) {
                      temporaryShowOnMapAt = null;
                    }
                  });
                },
                onPickStart: chooseTemporaryStart,
                onPickEnd: chooseTemporaryEnd,
                onPickShowOnMapAt: chooseTemporaryShowOnMapAt,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AddSpotSection(
            title: 'Photos',
            children: [
              InkWell(
                onTap: canAddMore ? addPhoto : null,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: totalPhotoCount > 0
                          ? blue.withValues(alpha: 0.7)
                          : Colors.white12,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          canAddMore ? Icons.add_photo_alternate : Icons.check,
                          color: blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              totalPhotoCount == 0
                                  ? 'Upload photos'
                                  : '$totalPhotoCount/$maxSpotGalleryPhotos photos selected',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              canAddMore
                                  ? 'Add or remove spot photos. The first photo becomes the Explore thumbnail.'
                                  : 'Maximum 4 photos selected. First photo is the spot thumbnail.',
                              style: const TextStyle(
                                color: Colors.white54,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        canAddMore ? Icons.chevron_right : Icons.lock,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ),
              ),
              if (totalPhotoCount > 0) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (
                      var index = 0;
                      index < existingPhotoUrls.length;
                      index++
                    )
                      photoThumb(
                        index: index,
                        label: index == 0 ? 'Cover' : '${index + 1}',
                        source: existingPhotoUrls[index],
                        isLocal: false,
                        onRemove: () => removeExistingPhotoAt(index),
                      ),
                    for (var index = 0; index < newPhotoPaths.length; index++)
                      photoThumb(
                        index: existingPhotoUrls.length + index,
                        label: existingPhotoUrls.length + index == 0
                            ? 'Cover'
                            : '${existingPhotoUrls.length + index + 1}',
                        source: newPhotoPaths[index],
                        isLocal: true,
                        onRemove: () => removeNewPhotoAt(index),
                      ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: isSaving ? null : saveSpot,
              icon: Icon(isSaving ? Icons.hourglass_top : Icons.save),
              label: Text(isSaving ? 'Saving...' : 'Save Changes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminSpotReviewScreen extends StatelessWidget {
  final CarSpot spot;

  const AdminSpotReviewScreen({super.key, required this.spot});

  Future<void> approveSpot(BuildContext context) async {
    try {
      await updateSpotStatus(spot, SpotStatus.approved);

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
            'Spot approved. It is now public.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      showAdminActionError(
        context,
        message: 'Could not approve spot',
        error: error,
      );
    }
  }

  Future<String?> askRejectionReason(BuildContext context) async {
    final controller = TextEditingController();

    return await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111827),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Reject spot?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            minLines: 3,
            maxLength: 300,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              counterStyle: const TextStyle(color: Colors.white38),
              hintText: 'Write the reason the user will see...',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.redAccent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final reason = controller.text.trim();
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.redAccent,
                      content: Text(
                        'Write a rejection reason first.',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                  return;
                }

                Navigator.pop(dialogContext, reason);
              },
              icon: const Icon(Icons.close),
              label: const Text('Reject'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> rejectSpot(BuildContext context) async {
    final reason = await askRejectionReason(context);
    if (reason == null || reason.trim().isEmpty) {
      return;
    }

    try {
      await updateSpotStatus(
        spot,
        SpotStatus.rejected,
        rejectionReason: reason,
      );

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Spot rejected and reason sent to the user.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      showAdminActionError(
        context,
        message: 'Could not reject spot',
        error: error,
      );
    }
  }

  Future<void> deleteSpot(BuildContext context) async {
    await deleteAdminSpot(context, spot, popAfterDelete: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Manage Spot'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: [
          IconButton(
            tooltip: 'Edit spot',
            onPressed: () =>
                openAdminEditSpot(context, spot, popAfterSave: true),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          SpotPhoto(
            spot: spot,
            height: 250,
            width: double.infinity,
            borderRadius: BorderRadius.circular(22),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _AdminStatusBadge(status: spot.status),
              const Spacer(),
              Flexible(
                child: spot.addedByUid.trim().isEmpty
                    ? Text(
                        'Added by ${spot.addedBy}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54),
                      )
                    : InkWell(
                        onTap: () => openUserProfile(
                          context,
                          uid: spot.addedByUid,
                          fallbackUsername: spot.addedBy,
                        ),
                        borderRadius: BorderRadius.circular(999),
                        child: Text(
                          'Added by ${displayUsername(spot.addedBy)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: blue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            spot.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(spot.cityCountry, style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 16),
          Text(
            spot.description,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              height: 1.45,
            ),
          ),
          if (spot.status == SpotStatus.rejected &&
              spot.rejectionReason.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Colors.redAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Rejection reason',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          spot.rejectionReason,
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (spot.verifiedOnly)
                _SmallTag(label: 'Verified only', icon: Icons.verified_user),
              for (final category in spot.categories)
                _SmallTag(label: category, icon: Icons.local_offer),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    rejectSpot(context);
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    approveSpot(context);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () =>
                  openAdminEditSpot(context, spot, popAfterSave: true),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Spot'),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                deleteSpot(context);
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete Spot'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppPage extends StatelessWidget {
  final String title;
  final String text;

  const AppPage({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsAppBarLogo(),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: ccsAppBarActions(),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
