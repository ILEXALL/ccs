import 'package:ccs_app/core/platform/platform_bridges.dart';
import 'package:ccs_app/shared/media/photo_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'camera uses its native action and cancellation preserves no attachment',
    (tester) async {
      final methods = <String>[];
      String? response = '/cache/camera/capture.jpg';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(photoPickerChannel, (call) async {
            methods.add(call.method);
            return response;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(photoPickerChannel, null),
      );
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const Scaffold();
            },
          ),
        ),
      );
      expect(
        await pickPhotoFromPhone(context, useCamera: true, cropPhoto: false),
        '/cache/camera/capture.jpg',
      );
      response = null;
      expect(
        await pickPhotoFromPhone(context, useCamera: true, cropPhoto: false),
        isNull,
      );
      expect(methods, ['takePhoto', 'takePhoto']);
      await pickPhotoFromPhone(context, cropPhoto: false);
      expect(methods.last, 'pickPhoto');
    },
  );
}
