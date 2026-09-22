import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/progression/screens/achievements_screen.dart';
import 'package:ccs_app/core/config/app_config.dart' show xpLeaderboardUrls;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show mapFromFirebase;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/network/json_http.dart' show postJsonToUrl;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show currentUserHomeCountryCode;
import 'package:ccs_app/features/friends/data/user_search.dart'
    show normalizeFriendSearch;
import 'package:ccs_app/features/progression/models/leaderboard_entry.dart'
    show XpLeaderboardEntry;
import 'package:ccs_app/shared/models/countries.dart' show countryIsoCode;

class XpLeaderboardPage {
  final List<XpLeaderboardEntry> entries;
  final Map<String, dynamic>? nextCursor;
  const XpLeaderboardPage({required this.entries, this.nextCursor});
}

class XpLeaderboardPageExpired implements Exception {}

typedef XpLeaderboardPageLoader =
    Future<XpLeaderboardPage> Function({
      required XpLeaderboardPeriod period,
      required String search,
      Map<String, dynamic>? cursor,
    });

Future<XpLeaderboardPage> loadXpLeaderboardEntries({
  XpLeaderboardPeriod period = XpLeaderboardPeriod.allTime,
  String search = '',
  Map<String, dynamic>? cursor,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'firebase_auth',
      code: 'not-logged-in',
      message: 'Log in before opening XP leaderboard.',
    );
  }

  final idToken = await firebaseUser.getIdToken();
  if (idToken == null || idToken.trim().isEmpty) {
    throw FirebaseException(
      plugin: 'firebase_auth',
      code: 'empty-id-token',
      message: 'Could not verify this XP leaderboard request.',
    );
  }

  Object? lastError;
  StackTrace? lastStack;

  Future<XpLeaderboardPage> loadBackendPage(
    String backendSearch,
    Map<String, dynamic>? pageCursor,
  ) async {
    for (final url in xpLeaderboardUrls) {
      try {
        final response = await postJsonToUrl(
          url,
          {
            'limit': 10,
            'period': xpLeaderboardPeriodValue(period),
            'search': backendSearch,
            'cursor': pageCursor,
          },
          headers: {HttpHeaders.authorizationHeader: 'Bearer $idToken'},
          logResponse: false,
        ).timeout(const Duration(seconds: 8));
        final result = mapFromFirebase(response['result']);
        final expectedCountry = currentUserHomeCountryCode();
        if (expectedCountry.isEmpty ||
            result['countryCode'] != expectedCountry) {
          throw StateError(
            'Ranking country mismatch. Update the backend and retry.',
          );
        }
        final rawEntries = result['entries'];
        final isSearchResponse = backendSearch.isNotEmpty;
        final hasValidPagination =
            result['hasMore'] is bool &&
            (result['hasMore'] == false || result['nextCursor'] is Map);

        // Search responses may intentionally omit pagination metadata. Normal
        // ranking pages still require it so an older deployment cannot repeat
        // the first page for every cursor.
        if (rawEntries is List &&
            (isSearchResponse || rawEntries.length <= 10) &&
            (isSearchResponse || hasValidPagination)) {
          return XpLeaderboardPage(
            entries: rawEntries
                .asMap()
                .entries
                .map(
                  (entry) => XpLeaderboardEntry.fromJson(
                    mapFromFirebase(entry.value),
                    fallbackRank: entry.key + 1,
                  ),
                )
                .where(
                  (entry) =>
                      entry.userId.trim().isNotEmpty &&
                      countryIsoCode(entry.country) ==
                          currentUserHomeCountryCode(),
                )
                .toList(),
            nextCursor: result['hasMore'] == true && result['nextCursor'] is Map
                ? mapFromFirebase(result['nextCursor'])
                : null,
          );
        }

        throw Exception('Backend returned invalid XP leaderboard data.');
      } catch (error, stack) {
        if (error.toString().contains('LEADERBOARD_CURSOR_EXPIRED')) {
          throw XpLeaderboardPageExpired();
        }
        lastError = error;
        lastStack = stack;
      }
    }

    debugPrint('XP leaderboard failed: $lastError');
    if (lastStack != null) {
      debugPrint('$lastStack');
    }

    throw Exception('Could not load XP leaderboard.');
  }

  final searchKey = normalizeFriendSearch(search);
  return loadBackendPage(searchKey.runes.length >= 2 ? searchKey : '', cursor);
}

enum XpLeaderboardPeriod { allTime, week }

String xpLeaderboardPeriodValue(XpLeaderboardPeriod period) {
  return switch (period) {
    XpLeaderboardPeriod.allTime => 'all_time',
    XpLeaderboardPeriod.week => 'weekly',
  };
}

String xpLeaderboardPeriodLabel(XpLeaderboardPeriod period) =>
    period == XpLeaderboardPeriod.week
    ? achievementText(
        appUiPreferences.language.name,
        'This week',
        'Эта неделя',
        'Šonedēļ',
      )
    : achievementText(
        appUiPreferences.language.name,
        'All time',
        'Всё время',
        'Visu laiku',
      );

String xpLeaderboardTitle(XpLeaderboardPeriod period) =>
    period == XpLeaderboardPeriod.week
    ? achievementText(
        appUiPreferences.language.name,
        'Top this week',
        'Лидеры недели',
        'Nedēļas līderi',
      )
    : achievementText(
        appUiPreferences.language.name,
        'Top drivers',
        'Лидеры рейтинга',
        'Reitinga līderi',
      );

String xpLeaderboardEmptyTitle(XpLeaderboardPeriod period) =>
    period == XpLeaderboardPeriod.week
    ? achievementText(
        appUiPreferences.language.name,
        'No weekly leaderboard yet',
        'Рейтинг недели пока пуст',
        'Nedēļas reitings vēl ir tukšs',
      )
    : achievementText(
        appUiPreferences.language.name,
        'No leaderboard yet',
        'Рейтинг пока пуст',
        'Reitings vēl ir tukšs',
      );

String xpLeaderboardEmptyText(XpLeaderboardPeriod period) => achievementText(
  appUiPreferences.language.name,
  'Earn XP to appear in the ranking.',
  'Получайте XP, чтобы попасть в рейтинг.',
  'Iegūstiet XP, lai iekļūtu reitingā.',
);
