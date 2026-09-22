import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

abstract interface class SpotDetailInputs {
  CarSpot get spot;
  Stream<CarSpot?>? get spotUpdates;
}

/// Screen-owned state. The widget retains lifecycle/disposal ownership;
/// action and content modules access only this typed view contract.
abstract interface class SpotDetailViewState {
  BuildContext get context;
  bool get mounted;
  SpotDetailInputs get widget;
  void updateView(VoidCallback update);
  CarSpot get spot;
  set spot(CarSpot value);
  StreamSubscription<CarSpot?>? get spotSubscription;
  set spotSubscription(StreamSubscription<CarSpot?>? value);
  bool get spotUnavailable;
  set spotUnavailable(bool value);
  SpotDetailControllerActions get controller;
}

abstract interface class SpotDetailControllerActions {
  void groupAccessChanged();
  void showSpotOnMap();
  Future<void> shareSpotLink();
}
