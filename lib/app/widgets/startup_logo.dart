import 'dart:async';
import 'package:flutter/material.dart';

class StartupLogo extends StatefulWidget {
  final Widget child;
  const StartupLogo({super.key, required this.child});
  @override
  State<StartupLogo> createState() => _StartupLogoState();
}

class _StartupLogoState extends State<StartupLogo> {
  bool finished = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => finished = true);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => finished
      ? widget.child
      : Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Image.asset('assets/icon.png', width: 160),
            ),
          ),
        );
}
