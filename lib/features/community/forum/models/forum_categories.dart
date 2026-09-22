import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;

class ForumCategoryConfig {
  final String id;
  final String titleKey;
  final String descriptionKey;
  final IconData icon;

  const ForumCategoryConfig({
    required this.id,
    required this.titleKey,
    required this.descriptionKey,
    required this.icon,
  });
}

const List<ForumCategoryConfig> forumCategoryConfigs = [
  ForumCategoryConfig(
    id: 'meets_events',
    titleKey: 'Meets & Events',
    descriptionKey: 'Car meets, track days, cruises and community events.',
    icon: Icons.calendar_month_outlined,
  ),
  ForumCategoryConfig(
    id: 'tuning_parts',
    titleKey: 'Tuning & Parts',
    descriptionKey: 'Performance upgrades, mods, reviews and builds.',
    icon: Icons.handyman_outlined,
  ),
  ForumCategoryConfig(
    id: 'questions_help',
    titleKey: 'Questions & Help',
    descriptionKey: 'Ask questions, get advice and solve problems.',
    icon: Icons.help_outline_rounded,
  ),
  ForumCategoryConfig(
    id: 'buy_sell',
    titleKey: 'Buy / Sell',
    descriptionKey: 'Buy and sell cars, parts and automotive items.',
    icon: Icons.storefront_outlined,
  ),
];

List<String> get forumCategories =>
    forumCategoryConfigs.map((category) => category.titleKey).toList();

ForumCategoryConfig forumCategoryById(String id) {
  return forumCategoryConfigs.firstWhere(
    (category) => category.id == id,
    orElse: () => forumCategoryConfigs.first,
  );
}

String forumCategoryIdFromFirebase(Object? value) {
  final raw = stringFromFirebase(value, '').trim();
  if (raw.isEmpty) {
    return forumCategoryConfigs.first.id;
  }

  final lower = raw.toLowerCase();
  switch (lower) {
    case 'meets_events':
    case 'meets & events':
    case 'встречи и события':
    case 'tikšanās un pasākumi':
      return 'meets_events';
    case 'tuning_parts':
    case 'tuning & parts':
    case 'тюнинг и запчасти':
    case 'tūnings un detaļas':
      return 'tuning_parts';
    case 'questions_help':
    case 'questions & help':
    case 'вопросы и помощь':
    case 'jautājumi un palīdzība':
      return 'questions_help';
    case 'buy_sell':
    case 'buy / sell':
    case 'buy/sell':
    case 'купить / продать':
    case 'купить/продать':
    case 'pirkt / pārdot':
    case 'pirkt/pārdot':
      return 'buy_sell';
    default:
      return forumCategoryConfigs
          .firstWhere(
            (category) => category.titleKey.toLowerCase() == lower,
            orElse: () => forumCategoryConfigs.first,
          )
          .id;
  }
}

String forumCategoryTitle(String id) => trText(forumCategoryById(id).titleKey);

String forumCategoryDescription(String id) =>
    trText(forumCategoryById(id).descriptionKey);
