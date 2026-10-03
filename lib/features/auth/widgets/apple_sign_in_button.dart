import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Apple's own localized button, rendered by AuthenticationServices on iOS.
class AppleSignInButton extends StatefulWidget {
  final VoidCallback? onPressed;

  const AppleSignInButton({super.key, required this.onPressed});

  @override
  State<AppleSignInButton> createState() => _AppleSignInButtonState();
}

class _AppleSignInButtonState extends State<AppleSignInButton> {
  MethodChannel? _channel;

  void _created(int id) {
    final channel = MethodChannel('ccs/apple_sign_in_button/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (mounted && call.method == 'pressed') widget.onPressed?.call();
    });
    unawaited(_updateEnabled());
  }

  Future<void> _updateEnabled() async {
    await _channel?.invokeMethod<void>('setEnabled', widget.onPressed != null);
  }

  @override
  void didUpdateWidget(covariant AppleSignInButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.onPressed == null) != (widget.onPressed == null)) {
      unawaited(_updateEnabled());
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    width: double.infinity,
    child: UiKitView(
      viewType: 'ccs/apple_sign_in_button',
      creationParams: {'enabled': widget.onPressed != null},
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _created,
    ),
  );
}
