import 'package:ccs_app/features/auth/widgets/login_intro_item.dart'
    show SplashIntroItem;
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/app/gates/maintenance_state.dart'
    show currentAppVersion;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/screens/login_screen.dart'
    show LoginScreen;
import 'package:ccs_app/shared/widgets/app_logo.dart' show CcsWordmark;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController introController;
  late final Animation<double> ccsSlide;
  late final Animation<double> subtitleSlide;
  late final Animation<double> taglineSlide;
  late final Animation<double> buttonSlide;
  late final Animation<double> ccsFade;
  late final Animation<double> subtitleFade;
  late final Animation<double> taglineFade;
  late final Animation<double> buttonFade;

  @override
  void initState() {
    super.initState();

    introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );

    ccsSlide = _slideAnimation(0.00, 0.58);
    subtitleSlide = _slideAnimation(0.14, 0.68);
    taglineSlide = _slideAnimation(0.28, 0.78);
    buttonSlide = _slideAnimation(0.44, 1.00);
    ccsFade = _fadeAnimation(0.00, 0.42);
    subtitleFade = _fadeAnimation(0.14, 0.52);
    taglineFade = _fadeAnimation(0.28, 0.66);
    buttonFade = _fadeAnimation(0.44, 0.88);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        introController.forward();
      }
    });
  }

  Animation<double> _slideAnimation(double begin, double end) {
    return CurvedAnimation(
      parent: introController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  Animation<double> _fadeAnimation(double begin, double end) {
    return CurvedAnimation(
      parent: introController,
      curve: Interval(begin, end, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    introController.dispose();
    super.dispose();
  }

  void openLogin() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 650),
        reverseTransitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (context, animation, secondaryAnimation) {
          return const LoginScreen(showBackground: false);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/bg.webp', fit: BoxFit.cover),
              Container(color: Colors.black.withValues(alpha: 0.42)),
              SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(curvedAnimation),
                child: FadeTransition(opacity: curvedAnimation, child: child),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg.webp', fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.42)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Stack(
                children: [
                  Align(
                    alignment: const Alignment(0, -0.62),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SplashIntroItem(
                          animation: ccsSlide,
                          fadeAnimation: ccsFade,
                          travel: 118,
                          child: const CcsWordmark(),
                        ),
                        const SizedBox(height: 16),
                        SplashIntroItem(
                          animation: subtitleSlide,
                          fadeAnimation: subtitleFade,
                          travel: 104,
                          child: const CcsText(
                            'COMMUNITY CAR SPOTS',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              letterSpacing: 4.2,
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        SplashIntroItem(
                          animation: taglineSlide,
                          fadeAnimation: taglineFade,
                          travel: 90,
                          child: const CcsText(
                            'FIND - DRIVE - SHOOT',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              letterSpacing: 4.4,
                              color: Colors.white54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 12),
                      child: CcsText(
                        currentAppVersion.trim().isEmpty
                            ? 'version -'
                            : 'version $currentAppVersion',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10.5,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.76),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SplashIntroItem(
                        animation: buttonSlide,
                        fadeAnimation: buttonFade,
                        travel: 78,
                        child: ElevatedButton(
                          onPressed: openLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: blue,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 42,
                              vertical: 16,
                            ),
                            elevation: 12,
                            shadowColor: blue.withValues(alpha: 0.35),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const CcsText(
                            'ENTER CCS',
                            style: TextStyle(
                              fontSize: 16,
                              letterSpacing: 2,
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
