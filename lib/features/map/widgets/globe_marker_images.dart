import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:ccs_app/core/theme/app_theme.dart'
    show blue, sosAlertColor, policeAlertColor, panelGlass;

/// Rasterize the original Material glyphs once, not on every animation frame.
Future<Map<String, String>> globeMarkerImages() async {
  final images = <String, String>{};
  Future<void> draw(String id, double size, void Function(Canvas) paint) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(128 / size);
    paint(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(128, 128);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      images[id] =
          'data:image/png;base64,${base64Encode(bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes))}';
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  void glyph(
    Canvas canvas,
    IconData icon,
    Color color,
    double size,
    double box,
  ) {
    final text = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          color: color,
        ),
      ),
    )..layout();
    text.paint(canvas, Offset((box - text.width) / 2, (box - text.height) / 2));
    text.dispose();
  }

  for (final entry in {
    'blue': blue,
    'amber': Colors.orangeAccent,
    'red': Colors.redAccent,
  }.entries) {
    await draw(
      'ccs-pin-${entry.key}',
      56,
      (canvas) => glyph(canvas, Icons.location_on, entry.value, 56, 56),
    );
  }
  for (var i = 0; i <= 16; i++) {
    final color = policeAlertColor(i / 16);
    await draw('ccs-police-$i', 34, (canvas) {
      canvas.drawCircle(const Offset(17, 17), 16, Paint()..color = panelGlass);
      canvas.drawCircle(
        const Offset(17, 17),
        16,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      glyph(canvas, Icons.local_police, color, 21, 34);
    });
  }
  await draw('ccs-sos', 38, (canvas) {
    canvas.drawCircle(const Offset(19, 19), 18, Paint()..color = panelGlass);
    canvas.drawCircle(
      const Offset(19, 19),
      18,
      Paint()
        ..color = sosAlertColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final text = TextPainter(
      textDirection: TextDirection.ltr,
      text: const TextSpan(
        text: 'SOS',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    )..layout();
    text.paint(canvas, Offset((38 - text.width) / 2, (38 - text.height) / 2));
    text.dispose();
  });
  return images;
}
