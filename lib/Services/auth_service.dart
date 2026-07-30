import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  Future<void>? _googleInitialization;

  User? get currentUser => _firebaseAuth.currentUser;

  bool get isSignedIn => currentUser != null;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  Stream<User?> get userChanges => _firebaseAuth.userChanges();

  Future<void> initialize() async {
    if (kIsWeb) return;

    _googleInitialization ??= _initializeGoogleSignIn();

    try {
      await _googleInitialization;
    } catch (_) {
      _googleInitialization = null;
      rethrow;
    }
  }

  Future<void> _initializeGoogleSignIn() async {
    await _googleSignIn.initialize();
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    if (normalizedEmail.isEmpty) {
      throw const AuthServiceException(
        code: 'missing-email',
        message: 'Indtast din e-mailadresse.',
      );
    }

    if (password.isEmpty) {
      throw const AuthServiceException(
        code: 'missing-password',
        message: 'Indtast din adgangskode.',
      );
    }

    try {
      return await _firebaseAuth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'EMAIL SIGN-IN FIREBASE ERROR: '
        'code=${error.code}, message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException.fromFirebase(error);
    } catch (error, stackTrace) {
      debugPrint('EMAIL SIGN-IN ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException(
        code: 'email-sign-in-failed',
        message: 'Login kunne ikke gennemføres. Prøv igen.',
        originalError: error,
      );
    }
  }

  Future<UserCredential> createAccountWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedName = displayName?.trim();

    if (normalizedEmail.isEmpty) {
      throw const AuthServiceException(
        code: 'missing-email',
        message: 'Indtast din e-mailadresse.',
      );
    }

    if (password.isEmpty) {
      throw const AuthServiceException(
        code: 'missing-password',
        message: 'Indtast en adgangskode.',
      );
    }

    if (password.length < 6) {
      throw const AuthServiceException(
        code: 'weak-password',
        message: 'Adgangskoden skal være på mindst 6 tegn.',
      );
    }

    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      if (normalizedName != null && normalizedName.isNotEmpty) {
        await credential.user?.updateDisplayName(normalizedName);
        await credential.user?.reload();
      }

      return credential;
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'CREATE ACCOUNT FIREBASE ERROR: '
        'code=${error.code}, message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException.fromFirebase(error);
    } catch (error, stackTrace) {
      debugPrint('CREATE ACCOUNT ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException(
        code: 'create-account-failed',
        message: 'Kontoen kunne ikke oprettes. Prøv igen.',
        originalError: error,
      );
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..setCustomParameters(const <String, String>{
            'prompt': 'select_account',
          });

        return await _firebaseAuth.signInWithPopup(provider);
      }

      await initialize();

      final googleUser = await _googleSignIn.authenticate();
      final googleAuthentication = googleUser.authentication;
      final idToken = googleAuthentication.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw const AuthServiceException(
          code: 'missing-google-id-token',
          message:
              'Google-login kunne ikke hente et gyldigt login-token. '
              'Kontrollér Firebase-konfigurationen.',
        );
      }

      final firebaseCredential = GoogleAuthProvider.credential(
        idToken: idToken,
      );

      return await _firebaseAuth.signInWithCredential(firebaseCredential);
    } on GoogleSignInException catch (error, stackTrace) {
      final code = error.code.name;
      final description = error.description?.trim();

      debugPrint(
        'GOOGLE SIGN-IN ERROR: '
        'code=$code, description=${description ?? 'none'}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (error.code == GoogleSignInExceptionCode.canceled) {
        /*
         * På Android kan google_sign_in også returnere "canceled", selv om
         * brugeren valgte en konto, når OAuth/SHA-konfigurationen er forkert.
         * Derfor viser vi en mere præcis tekst end blot "annulleret".
         */
        if (description != null && description.isNotEmpty) {
          throw AuthServiceException(
            code: 'google-sign-in-cancelled-or-config-error',
            message:
                'Google-login blev afbrudt eller er ikke korrekt konfigureret. '
                'Teknisk besked: $description',
            originalError: error,
          );
        }

        throw const AuthServiceException(
          code: 'google-sign-in-cancelled-or-config-error',
          message:
              'Google-login blev afbrudt. Hvis du valgte en konto, skal '
              'Android SHA-1/SHA-256 og Google-login i Firebase kontrolleres.',
        );
      }

      if (error.code == GoogleSignInExceptionCode.clientConfigurationError) {
        throw AuthServiceException(
          code: 'google-client-configuration-error',
          message:
              'Google-login er ikke korrekt konfigureret til Android. '
              'Kontrollér SHA-1, SHA-256 og google-services.json.'
              '${description == null || description.isEmpty ? '' : ' $description'}',
          originalError: error,
        );
      }

      throw AuthServiceException(
        code: code,
        message: description == null || description.isEmpty
            ? 'Google-login kunne ikke gennemføres. Fejlkode: $code.'
            : 'Google-login kunne ikke gennemføres: $description',
        originalError: error,
      );
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'GOOGLE FIREBASE AUTH ERROR: '
        'code=${error.code}, message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException.fromFirebase(error);
    } on AuthServiceException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('GOOGLE SIGN-IN UNKNOWN ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException(
        code: 'google-sign-in-failed',
        message: 'Google-login fejlede: $error',
        originalError: error,
      );
    }
  }

  Future<UserCredential> signInWithApple() async {
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.iOS) {
      throw const AuthServiceException(
        code: 'apple-sign-in-unsupported-platform',
        message: 'Apple-login er kun tilgængeligt på Apple-enheder.',
      );
    }

    try {
      final provider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');

      if (kIsWeb) {
        return await _firebaseAuth.signInWithPopup(provider);
      }

      return await _firebaseAuth.signInWithProvider(provider);
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'APPLE FIREBASE AUTH ERROR: '
        'code=${error.code}, message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (error.code == 'web-context-canceled' ||
          error.code == 'popup-closed-by-user' ||
          error.code == 'canceled') {
        throw AuthServiceException(
          code: 'apple-sign-in-cancelled',
          message: 'Apple-login blev annulleret.',
          originalError: error,
        );
      }

      throw AuthServiceException.fromFirebase(error);
    } on AuthServiceException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('APPLE SIGN-IN UNKNOWN ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException(
        code: 'apple-sign-in-failed',
        message: 'Apple-login kunne ikke gennemføres. Prøv igen.',
        originalError: error,
      );
    }
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    final normalizedEmail = email.trim().toLowerCase();

    if (normalizedEmail.isEmpty) {
      throw const AuthServiceException(
        code: 'missing-email',
        message: 'Indtast din e-mailadresse.',
      );
    }

    try {
      await _firebaseAuth.sendPasswordResetEmail(email: normalizedEmail);
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'PASSWORD RESET FIREBASE ERROR: '
        'code=${error.code}, message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException.fromFirebase(error);
    } catch (error, stackTrace) {
      debugPrint('PASSWORD RESET ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException(
        code: 'password-reset-failed',
        message: 'Nulstilling af adgangskoden kunne ikke gennemføres.',
        originalError: error,
      );
    }
  }

  Future<void> sendEmailVerification() async {
    final user = currentUser;

    if (user == null) {
      throw const AuthServiceException(
        code: 'not-signed-in',
        message: 'Du skal være logget ind først.',
      );
    }

    if (user.emailVerified) return;

    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'EMAIL VERIFICATION FIREBASE ERROR: '
        'code=${error.code}, message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException.fromFirebase(error);
    } catch (error, stackTrace) {
      debugPrint('EMAIL VERIFICATION ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException(
        code: 'email-verification-failed',
        message: 'Bekræftelsesmailen kunne ikke sendes. Prøv igen.',
        originalError: error,
      );
    }
  }

  Future<void> reloadCurrentUser() async {
    final user = currentUser;

    if (user == null) return;

    try {
      await user.reload();
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'RELOAD USER FIREBASE ERROR: '
        'code=${error.code}, message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException.fromFirebase(error);
    } catch (error, stackTrace) {
      debugPrint('RELOAD USER ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException(
        code: 'reload-user-failed',
        message: 'Brugeren kunne ikke opdateres.',
        originalError: error,
      );
    }
  }

  Future<void> updateDisplayName(String displayName) async {
    final user = currentUser;
    final normalizedName = displayName.trim();

    if (user == null) {
      throw const AuthServiceException(
        code: 'not-signed-in',
        message: 'Du skal være logget ind først.',
      );
    }

    if (normalizedName.isEmpty) {
      throw const AuthServiceException(
        code: 'missing-display-name',
        message: 'Indtast et navn.',
      );
    }

    try {
      await user.updateDisplayName(normalizedName);
      await user.reload();
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'UPDATE DISPLAY NAME FIREBASE ERROR: '
        'code=${error.code}, message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException.fromFirebase(error);
    } catch (error, stackTrace) {
      debugPrint('UPDATE DISPLAY NAME ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException(
        code: 'update-display-name-failed',
        message: 'Navnet kunne ikke opdateres.',
        originalError: error,
      );
    }
  }

  Future<void> signOut() async {
    Object? googleSignOutError;

    /*
     * Google-sessionen forsøges lukket først, men en fejl her må ikke
     * forhindre Firebase i at logge brugeren ud af Munja.
     */
    if (!kIsWeb) {
      try {
        await initialize();
        await _googleSignIn.signOut();
      } catch (error, stackTrace) {
        googleSignOutError = error;

        debugPrint('GOOGLE SIGN-OUT ERROR: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    try {
      await _firebaseAuth.signOut();
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'FIREBASE SIGN-OUT ERROR: '
        'code=${error.code}, message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException.fromFirebase(error);
    } catch (error, stackTrace) {
      debugPrint('FIREBASE SIGN-OUT UNKNOWN ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException(
        code: 'sign-out-failed',
        message: 'Log ud kunne ikke gennemføres.',
        originalError: error,
      );
    }

    /*
     * Firebase er nu logget ud, og AuthGate sender brugeren tilbage til
     * LoginScreen. En eventuel Google-fejl logges kun til debug-konsollen.
     */
    if (googleSignOutError != null) {
      debugPrint(
        'Firebase logout completed despite Google logout error: '
        '$googleSignOutError',
      );
    }
  }

  Future<void> deleteCurrentUser() async {
    final user = currentUser;

    if (user == null) {
      throw const AuthServiceException(
        code: 'not-signed-in',
        message: 'Der er ingen aktiv bruger at slette.',
      );
    }

    try {
      await user.delete();
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'DELETE USER FIREBASE ERROR: '
        'code=${error.code}, message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException.fromFirebase(error);
    } catch (error, stackTrace) {
      debugPrint('DELETE USER ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw AuthServiceException(
        code: 'delete-user-failed',
        message: 'Kontoen kunne ikke slettes.',
        originalError: error,
      );
    }

    if (!kIsWeb) {
      try {
        await initialize();
        await _googleSignIn.signOut();
      } catch (error, stackTrace) {
        debugPrint('GOOGLE SIGN-OUT AFTER DELETE ERROR: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }
}

class AuthServiceException implements Exception {
  final String code;
  final String message;
  final Object? originalError;

  const AuthServiceException({
    required this.code,
    required this.message,
    this.originalError,
  });

  factory AuthServiceException.fromFirebase(FirebaseAuthException error) {
    return AuthServiceException(
      code: error.code,
      message: _messageForFirebaseCode(
        error.code,
        firebaseMessage: error.message,
      ),
      originalError: error,
    );
  }

  static String _messageForFirebaseCode(
    String code, {
    String? firebaseMessage,
  }) {
    switch (code) {
      case 'invalid-email':
        return 'E-mailadressen er ugyldig.';

      case 'user-disabled':
        return 'Denne bruger er blevet deaktiveret.';

      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Forkert e-mail eller adgangskode.';

      case 'email-already-in-use':
        return 'Der findes allerede en konto med denne e-mail.';

      case 'weak-password':
        return 'Adgangskoden er for svag.';

      case 'operation-not-allowed':
        return 'Denne loginmetode er ikke aktiveret.';

      case 'too-many-requests':
        return 'For mange forsøg. Vent lidt, og prøv igen.';

      case 'network-request-failed':
        return 'Netværksfejl. Kontrollér din internetforbindelse.';

      case 'account-exists-with-different-credential':
        return 'Der findes allerede en konto med en anden loginmetode.';

      case 'requires-recent-login':
        return 'Log ind igen, før du kan udføre denne handling.';

      case 'popup-closed-by-user':
      case 'web-context-canceled':
        return 'Loginvinduet blev lukket.';

      case 'popup-blocked':
        return 'Browseren blokerede loginvinduet.';

      case 'credential-already-in-use':
        return 'Loginoplysningerne bruges allerede af en anden konto.';

      case 'invalid-api-key':
        return 'Firebase API-nøglen er ugyldig.';

      case 'app-not-authorized':
        return 'Appen er ikke godkendt til Firebase Authentication.';

      case 'unauthorized-domain':
        return 'Domænet er ikke godkendt til Firebase-login.';

      default:
        if (kDebugMode &&
            firebaseMessage != null &&
            firebaseMessage.trim().isNotEmpty) {
          return 'Login kunne ikke gennemføres: '
              '${firebaseMessage.trim()}';
        }

        return 'Login kunne ikke gennemføres. Prøv igen.';
    }
  }

  @override
  String toString() {
    return 'AuthServiceException(code: $code, message: $message)';
  }
}
