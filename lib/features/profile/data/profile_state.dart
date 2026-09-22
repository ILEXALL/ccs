import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/models/garage_car.dart' show GarageCar;
import 'package:ccs_app/features/profile/models/user_settings.dart'
    show UserSettingsData, defaultUserSettings;

final userSettings = ValueNotifier<UserSettingsData>(defaultUserSettings());

final garageCars = ValueNotifier<List<GarageCar>>(const []);
