import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/theme/munja_colors.dart';
import '../services/auth_service.dart';
import '../services/firestore_user_service.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  final Widget authenticatedChild;

  const AuthGate({super.key, required this.authenticatedChild});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService.instance;
  final FirestoreUserService _firestoreUserService =
      FirestoreUserService.instance;

  late Future<void> _initializationFuture;

  Future<void>? _firestoreSyncFuture;
  String? _firestoreSyncUid;

  @override
  void initState() {
    super.initState();
    _initializationFuture = _authService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializationFuture,
      builder: (context, initializationSnapshot) {
        if (initializationSnapshot.connectionState != ConnectionState.done) {
          return const _AuthLoadingScreen(message: 'Forbinder din konto...');
        }

        if (initializationSnapshot.hasError) {
          return _AuthInitializationErrorScreen(onRetry: _retryInitialization);
        }

        return StreamBuilder<User?>(
          stream: _authService.authStateChanges,
          initialData: _authService.currentUser,
          builder: (context, authSnapshot) {
            if (authSnapshot.connectionState == ConnectionState.waiting &&
                authSnapshot.data == null) {
              return const _AuthLoadingScreen(
                message: 'Kontrollerer din loginstatus...',
              );
            }

            if (authSnapshot.hasError) {
              return _AuthStreamErrorScreen(
                onRetry: () {
                  setState(() {});
                },
              );
            }

            final user = authSnapshot.data;

            if (user == null) {
              _clearFirestoreSync();
              return const LoginScreen();
            }

            final syncFuture = _getOrCreateFirestoreSyncFuture(user);

            return FutureBuilder<void>(
              future: syncFuture,
              builder: (context, syncSnapshot) {
                if (syncSnapshot.connectionState != ConnectionState.done) {
                  return const _AuthLoadingScreen(
                    message: 'Synkroniserer din Munja-profil...',
                  );
                }

                if (syncSnapshot.hasError) {
                  return _FirestoreSyncErrorScreen(
                    onRetry: () => _retryFirestoreSync(user),
                  );
                }

                return KeyedSubtree(
                  key: ValueKey<String>(user.uid),
                  child: widget.authenticatedChild,
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _getOrCreateFirestoreSyncFuture(User user) {
    if (_firestoreSyncFuture == null || _firestoreSyncUid != user.uid) {
      _firestoreSyncUid = user.uid;
      _firestoreSyncFuture = _syncFirestoreUser(user);
    }

    return _firestoreSyncFuture!;
  }

  Future<void> _syncFirestoreUser(User user) async {
    await _firestoreUserService.ensureUserExists(
      firebaseUser: user,
      updateLastLogin: true,
    );
  }

  void _retryInitialization() {
    _clearFirestoreSync();

    setState(() {
      _initializationFuture = _authService.initialize();
    });
  }

  void _retryFirestoreSync(User user) {
    setState(() {
      _firestoreSyncUid = user.uid;
      _firestoreSyncFuture = _syncFirestoreUser(user);
    });
  }

  void _clearFirestoreSync() {
    _firestoreSyncUid = null;
    _firestoreSyncFuture = null;
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  final String message;

  const _AuthLoadingScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: _AuthBackground()),
          SafeArea(
            child: Center(child: _AuthLoadingContent(message: message)),
          ),
        ],
      ),
    );
  }
}

class _AuthLoadingContent extends StatelessWidget {
  final String message;

  const _AuthLoadingContent({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withOpacity(0.10),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: MunjaColors.mint.withOpacity(0.28)),
              boxShadow: [
                BoxShadow(
                  color: MunjaColors.mint.withOpacity(0.12),
                  blurRadius: 34,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.change_history_rounded,
              color: MunjaColors.mint,
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'MUNJA',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
            ),
          ),
          const SizedBox(height: 24),
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: MunjaColors.mint,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthInitializationErrorScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const _AuthInitializationErrorScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _AuthErrorScreen(
      title: 'Login kunne ikke startes',
      message:
          'Munja kunne ikke initialisere login-systemet. Kontrollér din internetforbindelse og prøv igen.',
      onRetry: onRetry,
    );
  }
}

class _AuthStreamErrorScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const _AuthStreamErrorScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _AuthErrorScreen(
      title: 'Kontoen kunne ikke indlæses',
      message: 'Der opstod en fejl, mens Munja kontrollerede din loginstatus.',
      onRetry: onRetry,
    );
  }
}

class _FirestoreSyncErrorScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const _FirestoreSyncErrorScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _AuthErrorScreen(
      title: 'Profilen kunne ikke synkroniseres',
      message:
          'Munja kunne ikke oprette eller hente din cloud-profil. Kontrollér internetforbindelsen og Firestore-adgangen, og prøv igen.',
      onRetry: onRetry,
    );
  }
}

class _AuthErrorScreen extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;

  const _AuthErrorScreen({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: _AuthBackground()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 460),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: MunjaColors.panel.withOpacity(0.90),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 36,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 66,
                        height: 66,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF7D7D).withOpacity(0.10),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: const Color(0xFFFF7D7D).withOpacity(0.25),
                          ),
                        ),
                        child: const Icon(
                          Icons.cloud_off_rounded,
                          color: Color(0xFFFF7D7D),
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: MunjaColors.textSoft,
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton.icon(
                          onPressed: onRetry,
                          style: FilledButton.styleFrom(
                            backgroundColor: MunjaColors.mintStrong,
                            foregroundColor: const Color(0xFF03130F),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(19),
                            ),
                          ),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text(
                            'Prøv igen',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthBackground extends StatelessWidget {
  const _AuthBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF03120F), Color(0xFF020A08), Color(0xFF010504)],
        ),
      ),
      child: Stack(
        children: const [
          Positioned(
            top: -120,
            left: -90,
            child: _AuthGlow(size: 300, opacity: 0.13),
          ),
          Positioned(
            top: 300,
            right: -130,
            child: _AuthGlow(size: 290, opacity: 0.09),
          ),
          Positioned(
            bottom: -150,
            left: 40,
            child: _AuthGlow(size: 320, opacity: 0.07),
          ),
        ],
      ),
    );
  }
}

class _AuthGlow extends StatelessWidget {
  final double size;
  final double opacity;

  const _AuthGlow({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            MunjaColors.mint.withOpacity(opacity),
            MunjaColors.mint.withOpacity(0),
          ],
        ),
      ),
    );
  }
}
