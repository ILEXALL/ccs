import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as material show Text;
import 'package:ccs_app/core/localization/app_language.dart'
    show AppLanguage, appUiPreferences;
import 'package:ccs_app/core/localization/translations_lv.dart'
    show latvianTranslations;
import 'package:ccs_app/core/localization/translations_ru.dart'
    show russianTranslations;

String trText(String value, {AppLanguage? language}) {
  final selectedLanguage = language ?? appUiPreferences.language;
  final translations = switch (selectedLanguage) {
    AppLanguage.en => const <String, String>{},
    AppLanguage.ru => russianTranslations,
    AppLanguage.lv => latvianTranslations,
  };
  if (value == 'Add Spot Nav') {
    return switch (selectedLanguage) {
      AppLanguage.en => 'Add\nSpot',
      AppLanguage.ru => 'Добавить\nспот',
      AppLanguage.lv => 'Pievienot\nvietu',
    };
  }

  final mention = RegExp(
    r'^@(.+?) mentioned you: ([\s\S]*)$',
  ).firstMatch(value);
  if (mention != null) {
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru =>
        '@${mention.group(1)} упомянул(а) вас: ${mention.group(2)}',
      AppLanguage.lv =>
        '@${mention.group(1)} jūs pieminēja: ${mention.group(2)}',
    };
  }
  final exact = translations[value];

  if (exact != null) {
    return exact;
  }

  final groupRequest = RegExp(
    r'^@(.+) wants to join (.+)\.$',
  ).firstMatch(value);
  if (groupRequest != null) {
    final username = groupRequest.group(1)!;
    final group = groupRequest.group(2)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => '@$username хочет вступить в группу «$group».',
      AppLanguage.lv => '@$username vēlas pievienoties grupai «$group».',
    };
  }
  final groupDecision = RegExp(
    r'^Your request to join (.+) was (accepted|rejected)\.$',
  ).firstMatch(value);
  if (groupDecision != null) {
    final group = groupDecision.group(1)!;
    final accepted = groupDecision.group(2) == 'accepted';
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru =>
        'Ваша заявка в группу «$group» ${accepted ? 'одобрена' : 'отклонена'}.',
      AppLanguage.lv =>
        'Jūsu pieprasījums pievienoties grupai «$group» ir ${accepted ? 'apstiprināts' : 'noraidīts'}.',
    };
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

  final messageFromMatch = RegExp(r'^Message from @(.+)$').firstMatch(value);
  if (messageFromMatch != null) {
    final sender = messageFromMatch.group(1)!;
    return switch (selectedLanguage) {
      AppLanguage.en => value,
      AppLanguage.ru => 'Сообщение от @$sender',
      AppLanguage.lv => 'Ziņa no @$sender',
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

TextStyle? appTextStyle(TextStyle? style) {
  if (style == null || !appUiPreferences.lightTheme) {
    return style;
  }

  return style.copyWith(color: _lightTextColor(style.color));
}

// Rebuild translated hints, computed labels and menus without replacing the
// page State (which would discard drafts, scroll positions and subscriptions).
mixin LanguageReactiveState<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    appUiPreferences.addListener(_rebuildLanguage);
  }

  void _rebuildLanguage() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    appUiPreferences.removeListener(_rebuildLanguage);
    super.dispose();
  }
}

class CcsText extends StatelessWidget {
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

  const CcsText(
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
          style: appTextStyle(style),
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
