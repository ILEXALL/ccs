import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/progression/screens/achievements_screen.dart';
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;

String xpTransactionActionLabel(String action) {
  switch (action.trim().toLowerCase()) {
    case 'achievement.unlock':
      return achievementText(
        appUiPreferences.language.name,
        'Achievement unlocked',
        'Достижение получено',
        'Sasniegums iegūts',
      );
    case 'weekly.completed':
      return achievementText(
        appUiPreferences.language.name,
        'Weekly task completed',
        'Задание недели выполнено',
        'Nedēļas uzdevums izpildīts',
      );
    case 'admin.grant':
    case 'admin_reward.completed':
      return achievementText(
        appUiPreferences.language.name,
        'Admin reward',
        'Награда от администратора',
        'Administratora atlīdzība',
      );
    case 'visit.weekly':
      return achievementText(
        appUiPreferences.language.name,
        'Weekly spot visit',
        'Посещение спота за неделю',
        'Vietas apmeklējums šonedēļ',
      );
    case 'event.attended':
      return 'Event attended';
    case 'profile.avatar':
      return 'Profile avatar';
    case 'profile.bio':
      return 'Profile bio';
    case 'profile.city':
      return 'Profile city';
    case 'profile.social':
      return 'Profile socials';
    case 'profile.full':
      return 'Full profile';
    case 'garage.first_car':
      return 'First garage car';
    case 'garage.first_car_photo':
      return 'First car photo';
    case 'garage.first_car_description':
      return 'First car description';
    case 'garage.first_car_gallery':
      return 'First car gallery';
    case 'garage.first_car_full':
      return 'Complete first car';
    case 'spot.approved':
      return 'Spot approved';
    case 'spot.description':
      return 'Spot description';
    case 'spot.photo':
      return 'Spot photo';
    case 'spot.media_bundle':
      return 'Spot media bundle';
  }

  return action.trim().isEmpty ? 'XP' : action.trim();
}

String xpTransactionObjectTypeLabel(String objectType) {
  switch (objectType.trim().toLowerCase()) {
    case 'weekly_task':
    case 'weekly_visit':
      return achievementText(
        appUiPreferences.language.name,
        'Weekly reward',
        'Недельная награда',
        'Nedēļas atlīdzība',
      );
    case 'admin_reward':
      return achievementText(
        appUiPreferences.language.name,
        'Admin reward',
        'Награда от администратора',
        'Administratora atlīdzība',
      );

    case 'achievement':
      return achievementText(
        appUiPreferences.language.name,
        'Achievement',
        'Достижение',
        'Sasniegums',
      );
    case 'profile':
      return 'Profile';
    case 'garage_car':
      return 'Garage build';
    case 'spot':
      return 'Spot';
  }

  return objectType.trim().isEmpty ? 'XP' : objectType.trim();
}

String xpTransactionStatusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case 'confirmed':
      return 'Confirmed';
    case 'blocked':
      return 'Blocked';
    case 'pending':
      return 'Pending';
    case 'rejected':
      return 'Rejected';
    case 'revoked':
      return 'Revoked';
  }

  return status.trim().isEmpty ? 'Pending' : status.trim();
}

String xpTransactionReasonLabel(String reason) {
  switch (reason.trim().toUpperCase()) {
    case 'WEEKLY_LIMIT_REACHED':
      return 'Weekly limit reached';
    case 'XP_DISABLED_BY_CONFIG':
      return 'Blocked by XP settings';
    case 'XP_USER_NOT_ENABLED':
      return 'Tester is not enabled';
    case 'DUPLICATE_XP_TRANSACTION':
      return 'Duplicate transaction';
    case 'USER_BLOCKED_OR_DELETED':
      return 'User blocked or deleted';
    case 'USER_NOT_FOUND':
      return 'User profile not found';
    case 'WEEKLY_LIMIT_PARTIAL':
      return 'Partially limited by weekly cap';
  }

  return reason.trim();
}

IconData xpTransactionIcon(String objectType) {
  switch (objectType.trim().toLowerCase()) {
    case 'profile':
      return Icons.person_outline;
    case 'garage_car':
      return Icons.directions_car_outlined;
    case 'spot':
      return Icons.add_location_alt_outlined;
  }

  return Icons.bolt_rounded;
}

Color xpTransactionStatusColor(String status) {
  switch (status.trim().toLowerCase()) {
    case 'confirmed':
      return blue;
    case 'blocked':
    case 'rejected':
      return Colors.redAccent;
    case 'pending':
      return Colors.orangeAccent;
    case 'revoked':
      return Colors.white54;
  }

  return Colors.white54;
}
