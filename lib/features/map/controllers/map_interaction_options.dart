import 'package:flutter_map/flutter_map.dart';

// Simultaneous pinch/pan/rotation avoids flutter_map 8.3's gesture-race
// scale correction becoming negative during fast pinch reversals.
const InteractionOptions ccsMapInteractionOptions = InteractionOptions(
  flags: InteractiveFlag.all,
  enableMultiFingerGestureRace: false,
);
