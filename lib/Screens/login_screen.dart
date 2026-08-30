import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService.instance;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _isCreateAccountMode = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();

    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();

    super.dispose();
  }

  Future<void> _submitEmailForm() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final displayName = _nameController.text.trim();

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      if (_isCreateAccountMode) {
        await _authService.createAccountWithEmail(
          email: email,
          password: password,
          displayName: displayName,
        );
      } else {
        await _authService.signInWithEmail(
          email: email,
          password: password,
        );
      }
    } on AuthServiceException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Noget gik galt. Prøv igen.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await _authService.signInWithGoogle();
    } on AuthServiceException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'Google-login kunne ikke gennemføres.',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithApple() async {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await _authService.signInWithApple();
    } on AuthServiceException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'Apple-login kunne ikke gennemføres.',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Indtast din e-mailadresse først.';
        _successMessage = null;
      });

      _emailFocusNode.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await _authService.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      setState(() {
        _successMessage =
            'Vi har sendt et link til nulstilling af adgangskoden.';
      });
    } on AuthServiceException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Nulstilling af adgangskoden kunne ikke gennemføres.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleMode() {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isCreateAccountMode = !_isCreateAccountMode;
      _errorMessage = null;
      _successMessage = null;
      _passwordController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.viewInsets.bottom;
    final screenHeight = mediaQuery.size.height;

    final isAppleDevice =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final isAndroidDevice =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final showGoogleLogin = kIsWeb || isAndroidDevice;

    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: _LoginBackground()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    22,
                    18,
                    22,
                    28 + bottomPadding,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - bottomPadding,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: screenHeight < 760 ? 8 : 18),
                          const _BrandHeader(),
                          SizedBox(height: screenHeight < 760 ? 24 : 36),
                          Text(
                            _isCreateAccountMode
                                ? 'Opret din Munja-konto'
                                : 'Velkommen tilbage',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: screenHeight < 760 ? 29 : 34,
                              height: 1.04,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _isCreateAccountMode
                                ? 'Byg din digitale cykel, forbind dine produkter og saml dine ture ét sted.'
                                : 'Fortsæt til din cykel, dine ture og din digitale verden.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: MunjaColors.textSoft,
                              fontSize: 15,
                              height: 1.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: screenHeight < 760 ? 22 : 28),
                          _LoginCard(
                            child: AutofillGroup(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  if (_isCreateAccountMode) ...[
                                    _LoginTextField(
                                      controller: _nameController,
                                      focusNode: _nameFocusNode,
                                      label: 'Navn',
                                      hintText: 'Dit navn',
                                      icon: Icons.person_outline_rounded,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [
                                        AutofillHints.name,
                                      ],
                                      onSubmitted: (_) {
                                        _emailFocusNode.requestFocus();
                                      },
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  _LoginTextField(
                                    controller: _emailController,
                                    focusNode: _emailFocusNode,
                                    label: 'E-mail',
                                    hintText: 'navn@email.dk',
                                    icon: Icons.mail_outline_rounded,
                                    keyboardType:
                                        TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [
                                      AutofillHints.email,
                                      AutofillHints.username,
                                    ],
                                    onSubmitted: (_) {
                                      _passwordFocusNode.requestFocus();
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  _LoginTextField(
                                    controller: _passwordController,
                                    focusNode: _passwordFocusNode,
                                    label: 'Adgangskode',
                                    hintText: 'Mindst 6 tegn',
                                    icon: Icons.lock_outline_rounded,
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.done,
                                    autofillHints: [
                                      _isCreateAccountMode
                                          ? AutofillHints.newPassword
                                          : AutofillHints.password,
                                    ],
                                    suffixIcon: IconButton(
                                      onPressed: _isLoading
                                          ? null
                                          : () {
                                              setState(() {
                                                _obscurePassword =
                                                    !_obscurePassword;
                                              });
                                            },
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons
                                                .visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: Colors.white54,
                                      ),
                                    ),
                                    onSubmitted: (_) {
                                      _submitEmailForm();
                                    },
                                  ),
                                  if (!_isCreateAccountMode) ...[
                                    const SizedBox(height: 7),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: _isLoading
                                            ? null
                                            : _resetPassword,
                                        child: const Text(
                                          'Glemt adgangskode?',
                                          style: TextStyle(
                                            color: MunjaColors.mint,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ] else
                                    const SizedBox(height: 18),
                                  if (_errorMessage != null) ...[
                                    _StatusMessage(
                                      message: _errorMessage!,
                                      isError: true,
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  if (_successMessage != null) ...[
                                    _StatusMessage(
                                      message: _successMessage!,
                                      isError: false,
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  SizedBox(
                                    height: 58,
                                    child: FilledButton(
                                      onPressed: _isLoading
                                          ? null
                                          : _submitEmailForm,
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            MunjaColors.mintStrong,
                                        foregroundColor:
                                            const Color(0xFF03130F),
                                        disabledBackgroundColor:
                                            MunjaColors.mintStrong
                                                .withValues(alpha: 0.45),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(21),
                                        ),
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 23,
                                              height: 23,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2.4,
                                                color:
                                                    Color(0xFF03130F),
                                              ),
                                            )
                                          : Text(
                                              _isCreateAccountMode
                                                  ? 'Opret konto'
                                                  : 'Log ind',
                                              style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight:
                                                    FontWeight.w900,
                                              ),
                                            ),
                                    ),
                                  ),
                                  if (isAppleDevice ||
                                      showGoogleLogin) ...[
                                    const SizedBox(height: 22),
                                    const _OrDivider(),
                                    const SizedBox(height: 22),
                                  ],
                                  if (isAppleDevice)
                                    _SocialLoginButton(
                                      onPressed: _isLoading
                                          ? null
                                          : _signInWithApple,
                                      icon: const Icon(
                                        Icons.apple,
                                        size: 25,
                                        color: Colors.black,
                                      ),
                                      label: 'Fortsæt med Apple',
                                      foregroundColor: Colors.black,
                                      backgroundColor: Colors.white,
                                      borderColor: Colors.white,
                                    ),
                                  if (isAppleDevice && showGoogleLogin)
                                    const SizedBox(height: 12),
                                  if (showGoogleLogin)
                                    _SocialLoginButton(
                                      onPressed: _isLoading
                                          ? null
                                          : _signInWithGoogle,
                                      icon: const _GoogleMark(),
                                      label: 'Fortsæt med Google',
                                      foregroundColor: Colors.white,
                                      backgroundColor:
                                          Colors.white.withValues(
                                        alpha: 0.045,
                                      ),
                                      borderColor:
                                          Colors.white.withValues(
                                        alpha: 0.13,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  _isCreateAccountMode
                                      ? 'Har du allerede en konto?'
                                      : 'Har du ikke en konto?',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: MunjaColors.textSoft,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              TextButton(
                                onPressed:
                                    _isLoading ? null : _toggleMode,
                                child: Text(
                                  _isCreateAccountMode
                                      ? 'Log ind'
                                      : 'Opret konto',
                                  style: const TextStyle(
                                    color: MunjaColors.mint,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          const SizedBox(height: 16),
                          const _FooterBrand(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                MunjaColors.mint.withValues(alpha: 0.18),
                MunjaColors.mint.withValues(alpha: 0.035),
              ],
            ),
            border: Border.all(
              color: MunjaColors.mint.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: MunjaColors.mint.withValues(alpha: 0.18),
                blurRadius: 36,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Image.asset(
              'assets/munja-logo-icon_2.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.bolt_rounded,
                  color: MunjaColors.mint,
                  size: 42,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 17),
        const Text(
          'MUNJA',
          style: TextStyle(
            color: Colors.white,
            fontSize: 31,
            fontWeight: FontWeight.w900,
            letterSpacing: 8.5,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'DIGITAL CYCLING PLATFORM',
          style: TextStyle(
            color: MunjaColors.mint.withValues(alpha: 0.72),
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.4,
          ),
        ),
      ],
    );
  }
}

class _LoginCard extends StatelessWidget {
  final Widget child;

  const _LoginCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF07130F).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.075),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 44,
            offset: const Offset(0, 22),
          ),
          BoxShadow(
            color: MunjaColors.mint.withValues(alpha: 0.075),
            blurRadius: 42,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF041610),
            Color(0xFF020B08),
            Color(0xFF010504),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            top: -110,
            left: -90,
            child: _GlowOrb(size: 320, opacity: 0.16),
          ),
          const Positioned(
            top: 280,
            right: -130,
            child: _GlowOrb(size: 300, opacity: 0.10),
          ),
          const Positioned(
            bottom: -170,
            left: 30,
            child: _GlowOrb(size: 340, opacity: 0.08),
          ),
          IgnorePointer(
            child: Center(
              child: Opacity(
                opacity: 0.040,
                child: Image.asset(
                  'assets/munja-logo-icon_2.png',
                  width: width * 1.18,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: const _GridTexturePainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final double opacity;

  const _GlowOrb({
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            MunjaColors.mint.withValues(alpha: opacity),
            MunjaColors.mint.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class _GridTexturePainter extends CustomPainter {
  const _GridTexturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.012)
      ..strokeWidth = 0.7;

    const spacing = 20.0;

    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GridTexturePainter oldDelegate) {
    return false;
  }
}

class _LoginTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hintText;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final bool obscureText;
  final List<String>? autofillHints;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;

  const _LoginTextField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hintText,
    required this.icon,
    required this.textInputAction,
    this.keyboardType,
    this.obscureText = false,
    this.autofillHints,
    this.suffixIcon,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      autofillHints: autofillHints,
      autocorrect: false,
      enableSuggestions: !obscureText,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(
          icon,
          color: MunjaColors.mint,
          size: 23,
        ),
        suffixIcon: suffixIcon,
        labelStyle: const TextStyle(
          color: Colors.white60,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.25),
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.034),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 17,
          vertical: 20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(21),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(21),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(21),
          borderSide: const BorderSide(
            color: MunjaColors.mintStrong,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

class _SocialLoginButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String label;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color borderColor;

  const _SocialLoginButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor,
          disabledForegroundColor:
              foregroundColor.withValues(alpha: 0.55),
          disabledBackgroundColor:
              backgroundColor.withValues(alpha: 0.55),
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(21),
          ),
        ),
        icon: icon,
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  final String message;
  final bool isError;

  const _StatusMessage({
    required this.message,
    required this.isError,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? const Color(0xFFFF7D7D)
        : MunjaColors.mint;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: color,
            size: 21,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: Colors.white.withValues(alpha: 0.09),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'ELLER',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
        ),
        Expanded(
          child: Divider(
            color: Colors.white.withValues(alpha: 0.09),
          ),
        ),
      ],
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 25,
      height: 25,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'G',
        style: TextStyle(
          color: Color(0xFF4285F4),
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _FooterBrand extends StatelessWidget {
  const _FooterBrand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          AppText.t('appTitle'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.24),
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 3.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'RIDE • CONNECT • EVOLVE',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: MunjaColors.mint.withValues(alpha: 0.34),
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.8,
          ),
        ),
      ],
    );
  }
}
