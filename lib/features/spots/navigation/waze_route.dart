import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

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
