import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/monthly_special_service.dart';

/// Current Munja subscription tier.
///
/// Keep the tier separate from individual feature checks so we can later add
/// additional plans without rewriting the rest of the app.
enum MunjaProTier { free, pro }

/// Features that can be protected by Munja Pro.
///
/// Screens should preferably ask:
///
///   MunjaProService.instance.hasFeature(
///     MunjaProFeature.advancedAnalytics,
///   );
///
/// instead of checking `isPro` directly. This gives us one central place to
/// change the Free/Pro structure later.
enum MunjaProFeature {
  /// Core ride recording remains available to everyone.
  basicRideTracking,

  /// Basic statistics remain available to everyone.
  basicAnalytics,

  /// Normal rider-vs-rider challenges remain available to everyone.
  standardChallenges,

  /// Crystal earning and the normal Crystal shop remain available to everyone.
  crystals,

  /// Bike Digital Twin remains part of the core Munja experience.
  digitalTwin,

  /// More detailed performance insights and trends.
  advancedAnalytics,

  /// AI-based analysis of completed rides.
  aiRideAnalysis,

  /// Personal AI Ride Coach.
  aiRideCoach,

  /// Advanced route planning.
  advancedRoutePlanner,

  /// Extended challenge functionality.
  proChallenges,

  /// Additional long-term statistics/history.
  advancedRideHistory,

  /// Pro-only cosmetic items.
  proSkinsAndFrames,

  /// Pro access to special monthly functionality.
  monthlySpecialPro,
}

/// Immutable representation of the current Munja Pro entitlement.
@immutable
class MunjaProState {
  const MunjaProState({
    required this.tier,
    required this.isPro,
    this.expiresAt,
    this.source,
    this.productId,
  });

  const MunjaProState.free()
    : tier = MunjaProTier.free,
      isPro = false,
      expiresAt = null,
      source = null,
      productId = null;

  final MunjaProTier tier;
  final bool isPro;

  /// Optional expiration time.
  ///
  /// For subscriptions this will later be populated by the validated
  /// Apple/Google entitlement.
  final DateTime? expiresAt;

  /// Examples later:
  /// - apple
  /// - google
  /// - promo
  /// - admin
  final String? source;

  /// Store product identifier when real subscriptions are connected.
  final String? productId;

  bool get hasExpiration => expiresAt != null;

  bool get isExpired {
    final expiry = expiresAt;

    if (expiry == null) {
      return false;
    }

    return !expiry.isAfter(DateTime.now());
  }

  bool get hasActivePro {
    if (!isPro) {
      return false;
    }

    return !isExpired;
  }

  MunjaProState copyWith({
    MunjaProTier? tier,
    bool? isPro,
    DateTime? expiresAt,
    String? source,
    String? productId,
  }) {
    return MunjaProState(
      tier: tier ?? this.tier,
      isPro: isPro ?? this.isPro,
      expiresAt: expiresAt ?? this.expiresAt,
      source: source ?? this.source,
      productId: productId ?? this.productId,
    );
  }

  @override
  String toString() {
    return 'MunjaProState('
        'tier: $tier, '
        'isPro: $isPro, '
        'expiresAt: $expiresAt, '
        'source: $source, '
        'productId: $productId'
        ')';
  }
}

/// Central Munja Pro entitlement service.
///
/// Firestore:
///
/// users/{uid}
///
/// Suggested fields:
///
///   proStatus: "free" | "pro"
///   isPro: true | false
///   proExpiresAt: Timestamp?
///   proSource: "apple" | "google" | "promo" | "admin"
///   proProductId: String?
///
/// IMPORTANT:
///
/// These Firestore values are useful for the UI, but when Apple/Google
/// subscriptions are introduced we must NOT trust a client-side write to grant
/// Pro. Store purchases should be validated by the backend/store integration
/// and only then reflected in the user's account document.
class MunjaProService {
  MunjaProService._();

  static final MunjaProService instance = MunjaProService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final ValueNotifier<MunjaProState> state = ValueNotifier<MunjaProState>(
    const MunjaProState.free(),
  );

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSubscription;

  StreamSubscription<User?>? _authSubscription;

  bool _initialized = false;

  /// Prevent overlapping Monthly Special activation attempts when the live
  /// entitlement emits several account updates close together.
  bool _monthlySpecialActivationInFlight = false;

  // ---------------------------------------------------------------------------
  // PUBLIC GETTERS
  // ---------------------------------------------------------------------------

  String? get currentUid => _auth.currentUser?.uid;

  MunjaProState get current => state.value;

  bool get isPro => state.value.hasActivePro;

  MunjaProTier get tier => isPro ? MunjaProTier.pro : MunjaProTier.free;

  DateTime? get expiresAt => state.value.expiresAt;

  // ---------------------------------------------------------------------------
  // INITIALIZATION
  // ---------------------------------------------------------------------------

  /// Start listening to the signed-in user's Munja Pro entitlement.
  ///
  /// Safe to call multiple times.
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _initialized = true;

    _authSubscription = _auth.authStateChanges().listen(
      (user) {
        unawaited(_handleAuthChanged(user));
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('MUNJA PRO AUTH ERROR: $error');
        debugPrint('$stackTrace');
      },
    );

    await _handleAuthChanged(_auth.currentUser);
  }

  Future<void> _handleAuthChanged(User? user) async {
    await _userSubscription?.cancel();
    _userSubscription = null;

    if (user == null) {
      _setState(const MunjaProState.free());

      return;
    }

    _listenToUser(user.uid);
  }

  // ---------------------------------------------------------------------------
  // FIRESTORE LISTENER
  // ---------------------------------------------------------------------------

  void _listenToUser(String uid) {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      _setState(const MunjaProState.free());

      return;
    }

    _userSubscription = _db
        .collection('users')
        .doc(normalizedUid)
        .snapshots()
        .listen(
          (snapshot) {
            if (!snapshot.exists) {
              _setState(const MunjaProState.free());

              return;
            }

            final data = snapshot.data() ?? const <String, dynamic>{};

            final next = _stateFromFirestore(data);

            _setState(next);
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('MUNJA PRO FIRESTORE ERROR: $error');

            debugPrint('$stackTrace');
          },
        );
  }

  MunjaProState _stateFromFirestore(Map<String, dynamic> data) {
    final status = _readString(data['proStatus']).toLowerCase();

    final rawIsPro = _readBool(data['isPro']);

    final expiresAt = _readDateTime(data['proExpiresAt']);

    final source = _nullableString(data['proSource']);

    final productId = _nullableString(data['proProductId']);

    final statusSaysPro = status == 'pro' || status == 'active';

    final requestedPro = rawIsPro || statusSaysPro;

    final expired = expiresAt != null && !expiresAt.isAfter(DateTime.now());

    final active = requestedPro && !expired;

    return MunjaProState(
      tier: active ? MunjaProTier.pro : MunjaProTier.free,
      isPro: active,
      expiresAt: expiresAt,
      source: source,
      productId: productId,
    );
  }

  // ---------------------------------------------------------------------------
  // FEATURE ACCESS
  // ---------------------------------------------------------------------------

  /// Returns true when the current user may access [feature].
  ///
  /// Keep ALL Free/Pro decisions here instead of scattering them throughout
  /// screens.
  bool hasFeature(MunjaProFeature feature) {
    switch (feature) {
      // FREE / CORE MUNJA
      case MunjaProFeature.basicRideTracking:
      case MunjaProFeature.basicAnalytics:
      case MunjaProFeature.standardChallenges:
      case MunjaProFeature.crystals:
      case MunjaProFeature.digitalTwin:
        return true;

      // MUNJA PRO
      case MunjaProFeature.advancedAnalytics:
      case MunjaProFeature.aiRideAnalysis:
      case MunjaProFeature.aiRideCoach:
      case MunjaProFeature.advancedRoutePlanner:
      case MunjaProFeature.proChallenges:
      case MunjaProFeature.advancedRideHistory:
      case MunjaProFeature.proSkinsAndFrames:
      case MunjaProFeature.monthlySpecialPro:
        return isPro;
    }
  }

  /// Convenience method for UI code.
  ///
  /// Example:
  ///
  ///   if (!MunjaProService.instance.canUse(
  ///     MunjaProFeature.aiRideCoach,
  ///   )) {
  ///     openProScreen();
  ///     return;
  ///   }
  bool canUse(MunjaProFeature feature) {
    return hasFeature(feature);
  }

  /// Returns whether a feature should visually show a PRO badge/lock.
  bool shouldShowProLock(MunjaProFeature feature) {
    return !hasFeature(feature);
  }

  // ---------------------------------------------------------------------------
  // LIVE STREAM
  // ---------------------------------------------------------------------------

  /// Convenient stream for screens that prefer StreamBuilder.
  Stream<MunjaProState> watch() async* {
    yield state.value;

    await for (final _ in _stateChanges()) {
      yield state.value;
    }
  }

  Stream<void> _stateChanges() {
    late StreamController<void> controller;

    void listener() {
      if (!controller.isClosed) {
        controller.add(null);
      }
    }

    controller = StreamController<void>(
      onListen: () {
        state.addListener(listener);
      },
      onCancel: () {
        state.removeListener(listener);
      },
    );

    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // REFRESH
  // ---------------------------------------------------------------------------

  /// Force-read the current account once.
  ///
  /// Normally unnecessary because the service uses a live Firestore listener,
  /// but useful after login or during debugging.
  Future<MunjaProState> refresh() async {
    final uid = _auth.currentUser?.uid.trim();

    if (uid == null || uid.isEmpty) {
      const free = MunjaProState.free();

      _setState(free);

      return free;
    }

    try {
      final snapshot = await _db.collection('users').doc(uid).get();

      if (!snapshot.exists) {
        const next = MunjaProState.free();

        _setState(next);

        return next;
      }

      final next = _stateFromFirestore(
        snapshot.data() ?? const <String, dynamic>{},
      );

      _setState(next);

      return next;
    } catch (error, stackTrace) {
      debugPrint('MUNJA PRO REFRESH ERROR: $error');

      debugPrint('$stackTrace');

      return state.value;
    }
  }

  // ---------------------------------------------------------------------------
  // STATE
  // ---------------------------------------------------------------------------

  void _setState(MunjaProState next) {
    final current = state.value;
    final wasActive = current.hasActivePro;
    final isActiveNow = next.hasActivePro;

    if (_sameState(current, next)) {
      // App startup can restore an already-active account/store entitlement.
      // Ensure its Monthly Special exists even when the entitlement object
      // itself did not change.
      if (isActiveNow) {
        unawaited(_ensureMonthlySpecialForActivePro());
      }
      return;
    }

    state.value = next;

    debugPrint(
      'MUNJA PRO STATE: '
      'tier=${next.tier.name} '
      'active=${next.hasActivePro} '
      'expiresAt=${next.expiresAt} '
      'source=${next.source}',
    );

    // Production rule:
    // A Monthly Special starts automatically when Pro becomes active.
    // activateCurrentSpecial() is idempotent, so retries/app restarts are safe.
    if (isActiveNow) {
      if (!wasActive) {
        debugPrint(
          'MUNJA PRO MONTHLY SPECIAL: entitlement became active -> auto activate',
        );
      }

      unawaited(_ensureMonthlySpecialForActivePro());
    }
  }

  Future<void> _ensureMonthlySpecialForActivePro() async {
    if (_monthlySpecialActivationInFlight || !state.value.hasActivePro) {
      return;
    }

    final uid = _auth.currentUser?.uid.trim();
    if (uid == null || uid.isEmpty) {
      return;
    }

    _monthlySpecialActivationInFlight = true;

    try {
      final result = await MonthlySpecialService.instance
          .activateCurrentSpecial();

      debugPrint(
        'MUNJA PRO MONTHLY SPECIAL AUTO: '
        'activationId=${result.activation.id} '
        'created=${result.created} '
        'endsAt=${result.activation.endsAt.toIso8601String()}',
      );
    } catch (error, stackTrace) {
      // Entitlement must remain valid even if Monthly Special activation
      // temporarily fails (offline/rules/etc.). A later state refresh retries.
      debugPrint('MUNJA PRO MONTHLY SPECIAL AUTO ERROR: $error');
      debugPrint('$stackTrace');
    } finally {
      _monthlySpecialActivationInFlight = false;
    }
  }

  bool _sameState(MunjaProState a, MunjaProState b) {
    return a.tier == b.tier &&
        a.isPro == b.isPro &&
        a.expiresAt == b.expiresAt &&
        a.source == b.source &&
        a.productId == b.productId;
  }

  // ---------------------------------------------------------------------------
  // PARSING
  // ---------------------------------------------------------------------------

  static String _readString(Object? value) {
    if (value == null) {
      return '';
    }

    return value.toString().trim();
  }

  static String? _nullableString(Object? value) {
    final result = _readString(value);

    if (result.isEmpty) {
      return null;
    }

    return result;
  }

  static bool _readBool(Object? value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      final normalized = value.trim().toLowerCase();

      return normalized == 'true' ||
          normalized == '1' ||
          normalized == 'yes' ||
          normalized == 'active' ||
          normalized == 'pro';
    }

    return false;
  }

  static DateTime? _readDateTime(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }

    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }

    if (value is String) {
      return DateTime.tryParse(value.trim());
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // CLEANUP
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    await _userSubscription?.cancel();
    await _authSubscription?.cancel();

    _userSubscription = null;
    _authSubscription = null;

    _initialized = false;
    state.value = const MunjaProState.free();
  }
}
