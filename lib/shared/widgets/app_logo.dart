import 'package:flutter/material.dart' hide Text;

class CcsWordmark extends StatelessWidget {
  final double width;

  const CcsWordmark({super.key, this.width = 213});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Image.asset(
        'assets/ccs_logo.png',
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class CcsAppBarLogo extends StatelessWidget {
  const CcsAppBarLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Image.asset(
        'assets/ccs_logo.png',
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
