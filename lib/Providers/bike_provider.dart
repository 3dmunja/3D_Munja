import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/firestore_bike.dart';
import '../services/firestore_bike_service.dart';
import '../services/storage_service.dart';

class BikeProvider extends ChangeNotifier {
  BikeProvider({FirebaseAuth? firebaseAuth, FirestoreBikeService? bikeService})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _bikeService = bikeService ?? FirestoreBikeService.instance {
    _authSubscription = _firebaseAuth.authStateChanges().listen(
      _handleAuthStateChanged,
      onError: _handleAuthStreamError,
    );

    _handleAuthStateChanged(_firebaseAuth.currentUser);
  }

  final FirebaseAuth _firebaseAuth;
  final FirestoreBikeService _bikeService;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<List<FirestoreBike>>? _bikesSubscription;

  List<FirestoreBike> _bikes = const <FirestoreBike>[];
  FirestoreBike? _activeBike;

  bool _isLoading = false;
  bool _isInitialized = false;
  bool _isCreating = false;
  bool _isUpdating = false;
  bool _isDeleting = false;
  bool _isChangingActiveBike = false;
  bool _isUploadingBikeImage = false;
  bool _isUploadingBikeModel = false;
  bool _isDeletingBikeImage = false;
  bool _isDeletingBikeModel = false;

  double _bikeImageUploadProgress = 0;
  double _bikeModelUploadProgress = 0;

  String? _errorMessage;
  String? _errorCode;

  String? _observedUserId;
  bool _disposed = false;

  List<FirestoreBike> get bikes => List<FirestoreBike>.unmodifiable(_bikes);

  FirestoreBike? get activeBike => _activeBike;

  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  bool get isCreating => _isCreating;
  bool get isUpdating => _isUpdating;
  bool get isDeleting => _isDeleting;
  bool get isChangingActiveBike => _isChangingActiveBike;
  bool get isUploadingBikeImage => _isUploadingBikeImage;
  bool get isUploadingBikeModel => _isUploadingBikeModel;
  bool get isDeletingBikeImage => _isDeletingBikeImage;
  bool get isDeletingBikeModel => _isDeletingBikeModel;

  double get bikeImageUploadProgress => _bikeImageUploadProgress;
  double get bikeModelUploadProgress => _bikeModelUploadProgress;

  int get bikeImageUploadPercent =>
      (_bikeImageUploadProgress.clamp(0.0, 1.0) * 100).round();

  int get bikeModelUploadPercent =>
      (_bikeModelUploadProgress.clamp(0.0, 1.0) * 100).round();

  bool get isBusy =>
      _isLoading ||
      _isCreating ||
      _isUpdating ||
      _isDeleting ||
      _isChangingActiveBike ||
      _isUploadingBikeImage ||
      _isUploadingBikeModel ||
      _isDeletingBikeImage ||
      _isDeletingBikeModel;

  String? get errorMessage => _errorMessage;
  String? get errorCode => _errorCode;
  bool get hasError => _errorMessage != null;
  bool get hasBikes => _bikes.isNotEmpty;
  bool get hasActiveBike => _activeBike != null;
  int get bikeCount => _bikes.length;

  String? get currentUserId => _firebaseAuth.currentUser?.uid;

  FirestoreBike? bikeById(String bikeId) {
    final normalizedBikeId = bikeId.trim();

    if (normalizedBikeId.isEmpty) {
      return null;
    }

    for (final bike in _bikes) {
      if (bike.id == normalizedBikeId) {
        return bike;
      }
    }

    return null;
  }

  Future<void> refresh() async {
    final user = _firebaseAuth.currentUser;

    if (user == null) {
      _resetState(markInitialized: true, notify: true);
      return;
    }

    _setLoading(true);
    clearError(notify: false);

    try {
      final bikes = await _bikeService.getCurrentUserBikes();
      _applyBikes(bikes);
      _isInitialized = true;
    } catch (error, stackTrace) {
      _setErrorFromException(error);
      debugPrint('BIKE PROVIDER REFRESH ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _setLoading(false);
    }
  }

  Future<FirestoreBike?> createBike(
    FirestoreBike bike, {
    bool makeActive = false,
  }) async {
    if (_isCreating) {
      return null;
    }

    _isCreating = true;
    clearError(notify: false);
    _safeNotifyListeners();

    try {
      final createdBike = await _bikeService.createBike(
        bike,
        makeActive: makeActive,
      );

      return createdBike;
    } catch (error, stackTrace) {
      _setErrorFromException(error);
      debugPrint('BIKE PROVIDER CREATE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    } finally {
      _isCreating = false;
      _safeNotifyListeners();
    }
  }

  Future<bool> updateBike(FirestoreBike bike) async {
    if (_isUpdating) {
      return false;
    }

    _isUpdating = true;
    clearError(notify: false);
    _safeNotifyListeners();

    try {
      await _bikeService.updateBike(bike);
      return true;
    } catch (error, stackTrace) {
      _setErrorFromException(error);
      debugPrint('BIKE PROVIDER UPDATE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    } finally {
      _isUpdating = false;
      _safeNotifyListeners();
    }
  }

  Future<bool> updateBikeFields({
    required String bikeId,
    String? name,
    String? brand,
    String? model,
    FirestoreBikeType? type,
    String? color,
    String? frameSize,
    String? wheelSize,
    String? serialNumber,
    String? imageUrl,
    String? glbModelUrl,
    String? firmwareVersion,
    bool? digitalTwinEnabled,
    String? notes,
  }) async {
    if (_isUpdating) {
      return false;
    }

    _isUpdating = true;
    clearError(notify: false);
    _safeNotifyListeners();

    try {
      await _bikeService.updateBikeFields(
        bikeId: bikeId,
        name: name,
        brand: brand,
        model: model,
        type: type,
        color: color,
        frameSize: frameSize,
        wheelSize: wheelSize,
        serialNumber: serialNumber,
        imageUrl: imageUrl,
        glbModelUrl: glbModelUrl,
        firmwareVersion: firmwareVersion,
        digitalTwinEnabled: digitalTwinEnabled,
        notes: notes,
      );

      return true;
    } catch (error, stackTrace) {
      _setErrorFromException(error);
      debugPrint('BIKE PROVIDER UPDATE FIELDS ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    } finally {
      _isUpdating = false;
      _safeNotifyListeners();
    }
  }

  Future<bool> deleteBike(String bikeId) async {
    if (_isDeleting) {
      return false;
    }

    _isDeleting = true;
    clearError(notify: false);
    _safeNotifyListeners();

    try {
      await _bikeService.deleteBike(bikeId);
      return true;
    } catch (error, stackTrace) {
      _setErrorFromException(error);
      debugPrint('BIKE PROVIDER DELETE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    } finally {
      _isDeleting = false;
      _safeNotifyListeners();
    }
  }

  Future<bool> setActiveBike(String bikeId) async {
    if (_isChangingActiveBike) {
      return false;
    }

    _isChangingActiveBike = true;
    clearError(notify: false);
    _safeNotifyListeners();

    try {
      await _bikeService.setActiveBike(bikeId);
      return true;
    } catch (error, stackTrace) {
      _setErrorFromException(error);
      debugPrint('BIKE PROVIDER SET ACTIVE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    } finally {
      _isChangingActiveBike = false;
      _safeNotifyListeners();
    }
  }

  Future<bool> clearActiveBike() async {
    if (_isChangingActiveBike) {
      return false;
    }

    _isChangingActiveBike = true;
    clearError(notify: false);
    _safeNotifyListeners();

    try {
      await _bikeService.clearActiveBike();
      return true;
    } catch (error, stackTrace) {
      _setErrorFromException(error);
      debugPrint('BIKE PROVIDER CLEAR ACTIVE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    } finally {
      _isChangingActiveBike = false;
      _safeNotifyListeners();
    }
  }

  Future<StorageUploadResult?> uploadBikeImage({
    required String bikeId,
    required String filePath,
  }) async {
    if (_isUploadingBikeImage || _isDeletingBikeImage) {
      return null;
    }

    final bike = bikeById(bikeId);

    if (bike == null) {
      _setError(code: 'bike-not-found', message: 'Cyklen kunne ikke findes.');
      _safeNotifyListeners();
      return null;
    }

    _isUploadingBikeImage = true;
    _bikeImageUploadProgress = 0;
    clearError(notify: false);
    _safeNotifyListeners();

    StorageUploadResult? uploadedFile;

    try {
      uploadedFile = await StorageService.uploadBikeImage(
        bikeId: bike.id,
        filePath: filePath,
        onProgress: (progress) {
          _bikeImageUploadProgress = progress.clamp(0.0, 1.0);
          _safeNotifyListeners();
        },
      );

      await _bikeService.updateImageUrl(
        bikeId: bike.id,
        imageUrl: uploadedFile.downloadUrl,
      );

      final previousImageUrl = bike.imageUrl.trim();

      if (previousImageUrl.isNotEmpty &&
          previousImageUrl != uploadedFile.downloadUrl) {
        await _deleteStorageFileQuietly(previousImageUrl);
      }

      _bikeImageUploadProgress = 1;
      return uploadedFile;
    } catch (error, stackTrace) {
      if (uploadedFile != null) {
        await _deleteStorageFileQuietly(uploadedFile.downloadUrl);
      }

      _setErrorFromException(error);
      debugPrint('BIKE PROVIDER UPLOAD IMAGE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    } finally {
      _isUploadingBikeImage = false;
      _safeNotifyListeners();
    }
  }

  Future<StorageUploadResult?> uploadBikeModel({
    required String bikeId,
    required String filePath,
    bool enableDigitalTwin = true,
  }) async {
    if (_isUploadingBikeModel || _isDeletingBikeModel) {
      return null;
    }

    final bike = bikeById(bikeId);

    if (bike == null) {
      _setError(code: 'bike-not-found', message: 'Cyklen kunne ikke findes.');
      _safeNotifyListeners();
      return null;
    }

    _isUploadingBikeModel = true;
    _bikeModelUploadProgress = 0;
    clearError(notify: false);
    _safeNotifyListeners();

    StorageUploadResult? uploadedFile;

    try {
      uploadedFile = await StorageService.uploadBikeModel(
        bikeId: bike.id,
        filePath: filePath,
        onProgress: (progress) {
          _bikeModelUploadProgress = progress.clamp(0.0, 1.0);
          _safeNotifyListeners();
        },
      );

      await _bikeService.updateGlbModelUrl(
        bikeId: bike.id,
        glbModelUrl: uploadedFile.downloadUrl,
        enableDigitalTwin: enableDigitalTwin,
      );

      final previousModelUrl = bike.glbModelUrl.trim();

      if (previousModelUrl.isNotEmpty &&
          previousModelUrl != uploadedFile.downloadUrl) {
        await _deleteStorageFileQuietly(previousModelUrl);
      }

      _bikeModelUploadProgress = 1;
      return uploadedFile;
    } catch (error, stackTrace) {
      if (uploadedFile != null) {
        await _deleteStorageFileQuietly(uploadedFile.downloadUrl);
      }

      _setErrorFromException(error);
      debugPrint('BIKE PROVIDER UPLOAD MODEL ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    } finally {
      _isUploadingBikeModel = false;
      _safeNotifyListeners();
    }
  }

  Future<bool> deleteBikeImage({required String bikeId}) async {
    if (_isDeletingBikeImage || _isUploadingBikeImage) {
      return false;
    }

    final bike = bikeById(bikeId);

    if (bike == null) {
      _setError(code: 'bike-not-found', message: 'Cyklen kunne ikke findes.');
      _safeNotifyListeners();
      return false;
    }

    _isDeletingBikeImage = true;
    clearError(notify: false);
    _safeNotifyListeners();

    try {
      final previousImageUrl = bike.imageUrl.trim();

      await _bikeService.updateImageUrl(bikeId: bike.id, imageUrl: '');

      if (previousImageUrl.isNotEmpty) {
        await _deleteStorageFileQuietly(previousImageUrl);
      }

      _bikeImageUploadProgress = 0;
      return true;
    } catch (error, stackTrace) {
      _setErrorFromException(error);
      debugPrint('BIKE PROVIDER DELETE IMAGE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    } finally {
      _isDeletingBikeImage = false;
      _safeNotifyListeners();
    }
  }

  Future<bool> deleteBikeModel({
    required String bikeId,
    bool disableDigitalTwin = true,
  }) async {
    if (_isDeletingBikeModel || _isUploadingBikeModel) {
      return false;
    }

    final bike = bikeById(bikeId);

    if (bike == null) {
      _setError(code: 'bike-not-found', message: 'Cyklen kunne ikke findes.');
      _safeNotifyListeners();
      return false;
    }

    _isDeletingBikeModel = true;
    clearError(notify: false);
    _safeNotifyListeners();

    try {
      final previousModelUrl = bike.glbModelUrl.trim();

      await _bikeService.updateBikeFields(
        bikeId: bike.id,
        glbModelUrl: '',
        digitalTwinEnabled: disableDigitalTwin
            ? false
            : bike.digitalTwinEnabled,
      );

      if (previousModelUrl.isNotEmpty) {
        await _deleteStorageFileQuietly(previousModelUrl);
      }

      _bikeModelUploadProgress = 0;
      return true;
    } catch (error, stackTrace) {
      _setErrorFromException(error);
      debugPrint('BIKE PROVIDER DELETE MODEL ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    } finally {
      _isDeletingBikeModel = false;
      _safeNotifyListeners();
    }
  }

  Future<bool> updateImageUrl({
    required String bikeId,
    required String imageUrl,
  }) async {
    return _runUpdateAction(
      () => _bikeService.updateImageUrl(bikeId: bikeId, imageUrl: imageUrl),
      debugLabel: 'UPDATE IMAGE',
    );
  }

  Future<bool> updateGlbModelUrl({
    required String bikeId,
    required String glbModelUrl,
    bool enableDigitalTwin = true,
  }) async {
    return _runUpdateAction(
      () => _bikeService.updateGlbModelUrl(
        bikeId: bikeId,
        glbModelUrl: glbModelUrl,
        enableDigitalTwin: enableDigitalTwin,
      ),
      debugLabel: 'UPDATE GLB MODEL',
    );
  }

  Future<bool> updateFirmwareVersion({
    required String bikeId,
    required String firmwareVersion,
  }) async {
    return _runUpdateAction(
      () => _bikeService.updateFirmwareVersion(
        bikeId: bikeId,
        firmwareVersion: firmwareVersion,
      ),
      debugLabel: 'UPDATE FIRMWARE',
    );
  }

  Future<bool> addInstalledProduct({
    required String bikeId,
    required String productId,
  }) async {
    return _runUpdateAction(
      () => _bikeService.addInstalledProduct(
        bikeId: bikeId,
        productId: productId,
      ),
      debugLabel: 'ADD INSTALLED PRODUCT',
    );
  }

  Future<bool> removeInstalledProduct({
    required String bikeId,
    required String productId,
  }) async {
    return _runUpdateAction(
      () => _bikeService.removeInstalledProduct(
        bikeId: bikeId,
        productId: productId,
      ),
      debugLabel: 'REMOVE INSTALLED PRODUCT',
    );
  }

  void clearError({bool notify = true}) {
    final hadError = _errorMessage != null || _errorCode != null;

    _errorMessage = null;
    _errorCode = null;

    if (notify && hadError) {
      _safeNotifyListeners();
    }
  }

  Future<bool> _runUpdateAction(
    Future<void> Function() action, {
    required String debugLabel,
  }) async {
    if (_isUpdating) {
      return false;
    }

    _isUpdating = true;
    clearError(notify: false);
    _safeNotifyListeners();

    try {
      await action();
      return true;
    } catch (error, stackTrace) {
      _setErrorFromException(error);
      debugPrint('BIKE PROVIDER $debugLabel ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    } finally {
      _isUpdating = false;
      _safeNotifyListeners();
    }
  }

  Future<void> _handleAuthStateChanged(User? user) async {
    if (_disposed) {
      return;
    }

    final newUserId = user?.uid;

    if (_observedUserId == newUserId && _bikesSubscription != null) {
      return;
    }

    _observedUserId = newUserId;

    await _bikesSubscription?.cancel();
    _bikesSubscription = null;

    if (user == null) {
      _resetState(markInitialized: true, notify: true);
      return;
    }

    _resetState(markInitialized: false, notify: false);

    _setLoading(true);
    clearError(notify: false);
    _safeNotifyListeners();

    _bikesSubscription = _bikeService
        .watchUserBikes(user.uid)
        .listen(_handleBikesChanged, onError: _handleBikesStreamError);
  }

  void _handleBikesChanged(List<FirestoreBike> bikes) {
    if (_disposed) {
      return;
    }

    _applyBikes(bikes);
    _isInitialized = true;
    _isLoading = false;
    clearError(notify: false);
    _safeNotifyListeners();
  }

  void _handleBikesStreamError(Object error, StackTrace stackTrace) {
    if (_disposed) {
      return;
    }

    _setErrorFromException(error);
    _isInitialized = true;
    _isLoading = false;

    debugPrint('BIKE PROVIDER STREAM ERROR: $error');
    debugPrintStack(stackTrace: stackTrace);

    _safeNotifyListeners();
  }

  void _handleAuthStreamError(Object error, StackTrace stackTrace) {
    if (_disposed) {
      return;
    }

    _setError(
      code: 'auth-stream-failed',
      message: 'Loginstatus kunne ikke overvåges.',
    );

    _isInitialized = true;
    _isLoading = false;

    debugPrint('BIKE PROVIDER AUTH STREAM ERROR: $error');
    debugPrintStack(stackTrace: stackTrace);

    _safeNotifyListeners();
  }

  void _applyBikes(List<FirestoreBike> bikes) {
    _bikes = List<FirestoreBike>.unmodifiable(bikes);

    FirestoreBike? activeBike;

    for (final bike in bikes) {
      if (bike.active) {
        activeBike = bike;
        break;
      }
    }

    _activeBike = activeBike;
  }

  void _setLoading(bool value) {
    if (_isLoading == value) {
      return;
    }

    _isLoading = value;
    _safeNotifyListeners();
  }

  void _setErrorFromException(Object error) {
    if (error is StorageServiceException) {
      _setError(code: error.code ?? 'storage-error', message: error.message);
      return;
    }

    if (error is FirestoreBikeServiceException) {
      _setError(code: error.code, message: error.message);
      return;
    }

    _setError(
      code: 'unknown-bike-error',
      message: 'Der opstod en ukendt fejl med cykeldata.',
    );
  }

  Future<void> _deleteStorageFileQuietly(String downloadUrl) async {
    final trimmedUrl = downloadUrl.trim();

    if (trimmedUrl.isEmpty ||
        !trimmedUrl.startsWith('https://firebasestorage.googleapis.com/')) {
      return;
    }

    try {
      await StorageService.deleteFileByDownloadUrl(trimmedUrl);
    } catch (error, stackTrace) {
      debugPrint('BIKE PROVIDER STORAGE CLEANUP WARNING: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _setError({required String code, required String message}) {
    _errorCode = code;
    _errorMessage = message;
  }

  void _resetState({required bool markInitialized, required bool notify}) {
    _bikes = const <FirestoreBike>[];
    _activeBike = null;

    _isLoading = false;
    _isInitialized = markInitialized;
    _isCreating = false;
    _isUpdating = false;
    _isDeleting = false;
    _isChangingActiveBike = false;
    _isUploadingBikeImage = false;
    _isUploadingBikeModel = false;
    _isDeletingBikeImage = false;
    _isDeletingBikeModel = false;

    _bikeImageUploadProgress = 0;
    _bikeModelUploadProgress = 0;

    _errorMessage = null;
    _errorCode = null;

    if (notify) {
      _safeNotifyListeners();
    }
  }

  void _safeNotifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;

    _authSubscription?.cancel();
    _bikesSubscription?.cancel();

    _authSubscription = null;
    _bikesSubscription = null;

    super.dispose();
  }
}
