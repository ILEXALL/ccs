import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide Text;

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

Future<Map<String, dynamic>> postJsonToUrl(
  String url,
  Map<String, Object?> body, {
  Map<String, String> headers = const {},
  bool logResponse = true,
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
    if (logResponse) {
      debugPrint('POST $url -> ${response.statusCode}: $responseBody');
    }

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
