import 'dart:io';

// Use a real font for layout previews on developer machines and Linux CI.
String get previewFontPath {
  const candidates = [
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    'C:/Windows/Fonts/arial.ttf',
    '/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ];
  return candidates.firstWhere(
    (path) => File(path).existsSync(),
    orElse: () => throw StateError('Install Arial, Liberation Sans or DejaVu Sans for UI previews.'),
  );
}
