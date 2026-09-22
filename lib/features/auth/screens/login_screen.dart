import 'package:ccs_app/features/auth/navigation/auth_pages.dart';
import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/auth/widgets/login_intro_item.dart'
    show SplashIntroItem;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_preferences.dart'
    show saveRememberMePreference;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show currentUser, rememberMeEnabled;
import 'package:ccs_app/features/auth/data/sign_in.dart'
    show
        isTransientFirebaseAuthNetworkError,
        signInWithGoogleAndSaveUser,
        signInWithTelegramAndSaveUser;
import 'package:ccs_app/features/auth/data/usernames.dart'
    show
        UsernameAvailability,
        checkUsernameAvailabilityForCurrentUser,
        cleanProfileUsername,
        maxProfileUsernameLength,
        minProfileUsernameLength,
        usernameAvailabilityText;
import 'package:ccs_app/shared/widgets/app_logo.dart' show CcsWordmark;

class LoginScreen extends StatefulWidget {
  final bool showBackground;

  const LoginScreen({super.key, this.showBackground = true});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin, LanguageReactiveState {
  String? signingProvider;
  bool rememberMe = rememberMeEnabled;

  bool get isSigningIn => signingProvider != null;

  late final AnimationController loginIntroController;
  late final Animation<double> loginLogoSlide;
  late final Animation<double> loginSubtitleSlide;
  late final Animation<double> loginGoogleSlide;
  late final Animation<double> loginTelegramSlide;
  late final Animation<double> loginRememberSlide;
  late final Animation<double> loginTermsSlide;
  late final Animation<double> loginLogoFade;
  late final Animation<double> loginSubtitleFade;
  late final Animation<double> loginGoogleFade;
  late final Animation<double> loginTelegramFade;
  late final Animation<double> loginRememberFade;
  late final Animation<double> loginTermsFade;

  @override
  void initState() {
    super.initState();

    loginIntroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );

    loginLogoSlide = _loginSlideAnimation(0.00, 0.50);
    loginSubtitleSlide = _loginSlideAnimation(0.12, 0.58);
    loginGoogleSlide = _loginSlideAnimation(0.28, 0.72);
    loginTelegramSlide = _loginSlideAnimation(0.40, 0.84);
    loginRememberSlide = _loginSlideAnimation(0.52, 0.92);
    loginTermsSlide = _loginSlideAnimation(0.62, 1.00);
    loginLogoFade = _loginFadeAnimation(0.00, 0.36);
    loginSubtitleFade = _loginFadeAnimation(0.12, 0.44);
    loginGoogleFade = _loginFadeAnimation(0.28, 0.62);
    loginTelegramFade = _loginFadeAnimation(0.40, 0.74);
    loginRememberFade = _loginFadeAnimation(0.52, 0.86);
    loginTermsFade = _loginFadeAnimation(0.62, 1.00);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        loginIntroController.forward();
      }
    });
  }

  Animation<double> _loginSlideAnimation(double begin, double end) {
    return CurvedAnimation(
      parent: loginIntroController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  Animation<double> _loginFadeAnimation(double begin, double end) {
    return CurvedAnimation(
      parent: loginIntroController,
      curve: Interval(begin, end, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    loginIntroController.dispose();
    super.dispose();
  }

  Widget loginButton(
    String text,
    IconData icon,
    Color color,
    VoidCallback? onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color),
        label: CcsText(text),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  String loginErrorText(String provider, Object error) {
    final errorText = error.toString();

    if (error is SocketException ||
        errorText.contains('SocketException') ||
        errorText.contains('Failed host lookup')) {
      return trText(
        'Telegram login server is not available. Check internet or backend status.',
      );
    }

    if (isTransientFirebaseAuthNetworkError(error)) {
      return trText(
        'Login connection was interrupted. Please try again or switch Wi-Fi/mobile data.',
      );
    }

    if (error is FirebaseException && error.code == 'permission-denied') {
      return trText(
        'Login could not access your account data. Try again or contact admin.',
      );
    }

    if (error is FirebaseException && error.code == 'nickname-required') {
      return trText('Nickname is required to create your account.');
    }

    return '$provider login failed. $error';
  }

  Future<String?> requestInitialNickname(
    User firebaseUser,
    String fallbackUsername,
  ) async {
    if (!mounted) {
      return null;
    }

    final controller = TextEditingController(
      text: cleanProfileUsername(fallbackUsername),
    );
    String? errorText;
    var isChecking = false;

    final selected = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (isChecking) {
                return;
              }

              final cleanNickname = cleanProfileUsername(controller.text);
              if (cleanNickname.length < minProfileUsernameLength ||
                  cleanNickname.length > maxProfileUsernameLength) {
                setDialogState(
                  () => errorText = 'Nickname must be 3 to 30 characters.',
                );
                return;
              }

              setDialogState(() {
                isChecking = true;
                errorText = null;
              });

              final availability =
                  await checkUsernameAvailabilityForCurrentUser(
                    cleanNickname,
                    currentUsername: '',
                  );

              if (!dialogContext.mounted) {
                return;
              }

              if (availability == UsernameAvailability.available ||
                  availability == UsernameAvailability.unchanged) {
                Navigator.pop(dialogContext, cleanNickname);
                return;
              }

              setDialogState(() {
                isChecking = false;
                errorText = usernameAvailabilityText(availability);
              });
            }

            return AlertDialog(
              backgroundColor: panelGlass,
              title: CcsText(trText('Choose your nickname')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CcsText(
                    trText('This nickname will be visible to other drivers.'),
                    style: const TextStyle(color: Colors.white70, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    enabled: !isChecking,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => unawaited(submit()),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: trText('Nickname'),
                      prefixIcon: const Icon(
                        Icons.alternate_email,
                        color: blue,
                      ),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    CcsText(
                      trText(errorText!),
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isChecking
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: CcsText(trText('Cancel')),
                ),
                TextButton(
                  onPressed: isChecking ? null : () => unawaited(submit()),
                  child: CcsText(
                    trText(
                      isChecking
                          ? 'Checking nickname availability...'
                          : 'Create account',
                    ),
                    style: const TextStyle(color: blue),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return selected;
  }

  Future<void> loginWithGoogle() async {
    setState(() => signingProvider = 'google');

    try {
      await signInWithGoogleAndSaveUser(
        requestNewUserNickname: requestInitialNickname,
      );
      await saveRememberMePreference(rememberMe);

      if (!mounted) {
        return;
      }

      if (currentUser.banActive) {
        return;
      }

      Navigator.pushReplacement(context, appPageRoute(builder: signedInPage));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            loginErrorText('Google', error),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => signingProvider = null);
      }
    }
  }

  Future<void> loginWithTelegram() async {
    setState(() => signingProvider = 'telegram');

    try {
      await signInWithTelegramAndSaveUser(
        requestNewUserNickname: requestInitialNickname,
      );
      await saveRememberMePreference(rememberMe);

      if (!mounted) {
        return;
      }

      if (currentUser.banActive) {
        return;
      }

      Navigator.pushReplacement(context, appPageRoute(builder: signedInPage));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            loginErrorText('Telegram', error),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => signingProvider = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.showBackground
          ? Colors.black
          : Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.showBackground) ...[
            Image.asset('assets/bg.png', fit: BoxFit.cover),
            Container(color: Colors.black.withValues(alpha: 0.42)),
          ],
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SplashIntroItem(
                  animation: loginLogoSlide,
                  fadeAnimation: loginLogoFade,
                  travel: 112,
                  child: const CcsWordmark(width: 213),
                ),
                const SizedBox(height: 14),
                SplashIntroItem(
                  animation: loginSubtitleSlide,
                  fadeAnimation: loginSubtitleFade,
                  travel: 100,
                  child: const CcsText(
                    'COMMUNITY CAR SPOTS',
                    style: TextStyle(letterSpacing: 3, color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 60),
                SplashIntroItem(
                  animation: loginGoogleSlide,
                  fadeAnimation: loginGoogleFade,
                  travel: 88,
                  child: loginButton(
                    signingProvider == 'google'
                        ? 'Signing in with Google...'
                        : 'Continue with Google',
                    Icons.g_mobiledata,
                    Colors.red,
                    isSigningIn ? null : loginWithGoogle,
                  ),
                ),
                SplashIntroItem(
                  animation: loginTelegramSlide,
                  fadeAnimation: loginTelegramFade,
                  travel: 76,
                  child: loginButton(
                    signingProvider == 'telegram'
                        ? 'Signing in with Telegram...'
                        : 'Continue with Telegram',
                    Icons.send,
                    blue,
                    isSigningIn ? null : loginWithTelegram,
                  ),
                ),
                const SizedBox(height: 4),
                SplashIntroItem(
                  animation: loginRememberSlide,
                  fadeAnimation: loginRememberFade,
                  travel: 64,
                  child: _RememberMeRow(
                    value: rememberMe,
                    enabled: !isSigningIn,
                    onChanged: (value) => setState(() => rememberMe = value),
                  ),
                ),
                const SizedBox(height: 28),
                SplashIntroItem(
                  animation: loginTermsSlide,
                  fadeAnimation: loginTermsFade,
                  travel: 52,
                  child: const CcsText(
                    'By continuing, you agree to our Terms & Privacy Policy',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RememberMeRow extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _RememberMeRow({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: enabled
                  ? (checked) => onChanged(checked ?? false)
                  : null,
              activeColor: blue,
              checkColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
            ),
            const SizedBox(width: 4),
            const CcsText(
              'Remember me',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            const Icon(Icons.lock_outline, color: Colors.white38, size: 16),
          ],
        ),
      ),
    );
  }
}
