import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../models/munja_device.dart';
import '../models/ride_route_plan.dart';
import '../models/trip.dart';
import '../models/user_profile.dart';

typedef StorageUploadProgressCallback = void Function(double progress);

enum StorageUploadType { profileImage, bikeImage, bikeModel, firmware, other }

class StorageUploadResult {
  const StorageUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.uploadType,
  });

  final String downloadUrl;
  final String storagePath;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final StorageUploadType uploadType;
}

class StorageServiceException implements Exception {
  const StorageServiceException(this.message, {this.code, this.originalError});

  final String message;
  final String? code;
  final Object? originalError;

  @override
  String toString() {
    if (code == null || code!.isEmpty) {
      return 'StorageServiceException: $message';
    }

    return 'StorageServiceException($code): $message';
  }
}

class StorageService {
  StorageService._();

  static const String activeRouteKey = 'munja_active_route';
  static const String userPhotoPathKey = 'profile_photo_path_v1';

  static const int maxProfileImageBytes = 15 * 1024 * 1024;
  static const int maxBikeImageBytes = 20 * 1024 * 1024;
  static const int maxBikeModelBytes = 250 * 1024 * 1024;
  static const int maxFirmwareBytes = 50 * 1024 * 1024;

  static FirebaseStorage get _firebaseStorage => FirebaseStorage.instance;
  static FirebaseAuth get _firebaseAuth => FirebaseAuth.instance;

  static String? get currentUserId => _firebaseAuth.currentUser?.uid;
  static bool get isSignedIn => currentUserId != null;

  static Future<StorageUploadResult> uploadProfileImage({
    required String filePath,
    StorageUploadProgressCallback? onProgress,
  }) async {
    final userId = _requireUserId();
    final file = File(filePath);

    return _uploadFile(
      file: file,
      storagePath:
          'users/$userId/profile/${_timestampedFileName(file.path, fallbackExtension: 'jpg')}',
      uploadType: StorageUploadType.profileImage,
      maximumBytes: maxProfileImageBytes,
      allowedExtensions: const {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'},
      onProgress: onProgress,
    );
  }

  static Future<StorageUploadResult> uploadBikeImage({
    required String bikeId,
    required String filePath,
    StorageUploadProgressCallback? onProgress,
  }) async {
    final userId = _requireUserId();
    final safeBikeId = _requireSafeId(bikeId, fieldName: 'bikeId');
    final file = File(filePath);

    return _uploadFile(
      file: file,
      storagePath:
          'users/$userId/bikes/$safeBikeId/images/${_timestampedFileName(file.path, fallbackExtension: 'jpg')}',
      uploadType: StorageUploadType.bikeImage,
      maximumBytes: maxBikeImageBytes,
      allowedExtensions: const {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'},
      onProgress: onProgress,
    );
  }

  static Future<StorageUploadResult> uploadBikeModel({
    required String bikeId,
    required String filePath,
    StorageUploadProgressCallback? onProgress,
  }) async {
    final userId = _requireUserId();
    final safeBikeId = _requireSafeId(bikeId, fieldName: 'bikeId');
    final file = File(filePath);

    return _uploadFile(
      file: file,
      storagePath:
          'users/$userId/bikes/$safeBikeId/models/${_timestampedFileName(file.path, fallbackExtension: 'glb')}',
      uploadType: StorageUploadType.bikeModel,
      maximumBytes: maxBikeModelBytes,
      allowedExtensions: const {'glb', 'gltf'},
      onProgress: onProgress,
    );
  }

  static Future<StorageUploadResult> uploadFirmware({
    required String deviceId,
    required String filePath,
    StorageUploadProgressCallback? onProgress,
  }) async {
    final userId = _requireUserId();
    final safeDeviceId = _requireSafeId(deviceId, fieldName: 'deviceId');
    final file = File(filePath);

    return _uploadFile(
      file: file,
      storagePath:
          'users/$userId/devices/$safeDeviceId/firmware/${_timestampedFileName(file.path, fallbackExtension: 'bin')}',
      uploadType: StorageUploadType.firmware,
      maximumBytes: maxFirmwareBytes,
      allowedExtensions: const {'bin', 'hex', 'uf2'},
      onProgress: onProgress,
    );
  }

  static Future<StorageUploadResult> uploadBytes({
    required Uint8List bytes,
    required String storagePath,
    required String fileName,
    required StorageUploadType uploadType,
    String? contentType,
    int? maximumBytes,
    StorageUploadProgressCallback? onProgress,
  }) async {
    if (bytes.isEmpty) {
      throw const StorageServiceException(
        'The selected file is empty.',
        code: 'empty-file',
      );
    }

    if (maximumBytes != null && bytes.lengthInBytes > maximumBytes) {
      throw StorageServiceException(
        'The selected file is too large. Maximum size is ${_formatBytes(maximumBytes)}.',
        code: 'file-too-large',
      );
    }

    final safePath = _normalizeStoragePath(storagePath);
    final safeFileName = _sanitizeFileName(fileName);
    final resolvedContentType =
        contentType ?? _contentTypeForExtension(_fileExtension(safeFileName));

    final reference = _firebaseStorage.ref().child('$safePath/$safeFileName');

    final metadata = SettableMetadata(
      contentType: resolvedContentType,
      customMetadata: {
        'ownerId': currentUserId ?? '',
        'uploadType': uploadType.name,
        'originalFileName': safeFileName,
        'uploadedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );

    try {
      final uploadTask = reference.putData(bytes, metadata);
      final subscription = uploadTask.snapshotEvents.listen((snapshot) {
        _emitProgress(snapshot, onProgress);
      });

      try {
        final snapshot = await uploadTask;
        final downloadUrl = await snapshot.ref.getDownloadURL();
        onProgress?.call(1);

        return StorageUploadResult(
          downloadUrl: downloadUrl,
          storagePath: snapshot.ref.fullPath,
          fileName: safeFileName,
          contentType: resolvedContentType,
          sizeBytes: snapshot.totalBytes,
          uploadType: uploadType,
        );
      } finally {
        await subscription.cancel();
      }
    } on FirebaseException catch (error) {
      throw _mapFirebaseStorageException(error);
    } catch (error) {
      throw StorageServiceException(
        'The file could not be uploaded.',
        code: 'upload-failed',
        originalError: error,
      );
    }
  }

  static Future<void> deleteFileAtPath(String storagePath) async {
    final normalizedPath = _normalizeStoragePath(storagePath);

    try {
      await _firebaseStorage.ref().child(normalizedPath).delete();
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') return;
      throw _mapFirebaseStorageException(error);
    }
  }

  static Future<void> deleteFileByDownloadUrl(String downloadUrl) async {
    final trimmedUrl = downloadUrl.trim();
    if (trimmedUrl.isEmpty) return;

    try {
      await _firebaseStorage.refFromURL(trimmedUrl).delete();
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') return;
      throw _mapFirebaseStorageException(error);
    } on ArgumentError catch (error) {
      throw StorageServiceException(
        'The supplied Firebase Storage URL is invalid.',
        code: 'invalid-download-url',
        originalError: error,
      );
    }
  }

  static Future<bool> fileExistsAtPath(String storagePath) async {
    final normalizedPath = _normalizeStoragePath(storagePath);

    try {
      await _firebaseStorage.ref().child(normalizedPath).getMetadata();
      return true;
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') return false;
      throw _mapFirebaseStorageException(error);
    }
  }

  static Future<String> getDownloadUrl(String storagePath) async {
    final normalizedPath = _normalizeStoragePath(storagePath);

    try {
      return await _firebaseStorage
          .ref()
          .child(normalizedPath)
          .getDownloadURL();
    } on FirebaseException catch (error) {
      throw _mapFirebaseStorageException(error);
    }
  }

  static Future<StorageUploadResult> _uploadFile({
    required File file,
    required String storagePath,
    required StorageUploadType uploadType,
    required int maximumBytes,
    required Set<String> allowedExtensions,
    StorageUploadProgressCallback? onProgress,
  }) async {
    if (!await file.exists()) {
      throw const StorageServiceException(
        'The selected file does not exist.',
        code: 'file-not-found',
      );
    }

    final fileSize = await file.length();

    if (fileSize <= 0) {
      throw const StorageServiceException(
        'The selected file is empty.',
        code: 'empty-file',
      );
    }

    if (fileSize > maximumBytes) {
      throw StorageServiceException(
        'The selected file is too large. Maximum size is ${_formatBytes(maximumBytes)}.',
        code: 'file-too-large',
      );
    }

    final extension = _fileExtension(file.path);

    if (!allowedExtensions.contains(extension)) {
      throw StorageServiceException(
        'Unsupported file type: .$extension',
        code: 'unsupported-file-type',
      );
    }

    final normalizedPath = _normalizeStoragePath(storagePath);
    final contentType = _contentTypeForExtension(extension);
    final reference = _firebaseStorage.ref().child(normalizedPath);

    final metadata = SettableMetadata(
      contentType: contentType,
      customMetadata: {
        'ownerId': currentUserId ?? '',
        'uploadType': uploadType.name,
        'originalFileName': _fileNameFromPath(file.path),
        'uploadedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );

    try {
      final uploadTask = reference.putFile(file, metadata);
      final subscription = uploadTask.snapshotEvents.listen((snapshot) {
        _emitProgress(snapshot, onProgress);
      });

      try {
        final snapshot = await uploadTask;
        final downloadUrl = await snapshot.ref.getDownloadURL();
        onProgress?.call(1);

        return StorageUploadResult(
          downloadUrl: downloadUrl,
          storagePath: snapshot.ref.fullPath,
          fileName: snapshot.ref.name,
          contentType: contentType,
          sizeBytes: snapshot.totalBytes,
          uploadType: uploadType,
        );
      } finally {
        await subscription.cancel();
      }
    } on FirebaseException catch (error) {
      throw _mapFirebaseStorageException(error);
    } catch (error) {
      throw StorageServiceException(
        'The file could not be uploaded.',
        code: 'upload-failed',
        originalError: error,
      );
    }
  }

  static void _emitProgress(
    TaskSnapshot snapshot,
    StorageUploadProgressCallback? onProgress,
  ) {
    if (onProgress == null) return;

    if (snapshot.totalBytes <= 0) {
      onProgress(0);
      return;
    }

    onProgress(
      (snapshot.bytesTransferred / snapshot.totalBytes).clamp(0.0, 1.0),
    );
  }

  static String _requireUserId() {
    final userId = currentUserId;

    if (userId == null || userId.trim().isEmpty) {
      throw const StorageServiceException(
        'You must be signed in before uploading files.',
        code: 'not-authenticated',
      );
    }

    return userId;
  }

  static String _requireSafeId(String value, {required String fieldName}) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      throw StorageServiceException(
        '$fieldName cannot be empty.',
        code: 'invalid-id',
      );
    }

    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  static String _normalizeStoragePath(String value) {
    final normalized = value
        .trim()
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+'), '/')
        .replaceFirst(RegExp(r'^/+'), '')
        .replaceFirst(RegExp(r'/+$'), '');

    if (normalized.isEmpty || normalized.contains('..')) {
      throw const StorageServiceException(
        'Firebase Storage path is invalid.',
        code: 'invalid-storage-path',
      );
    }

    return normalized;
  }

  static String _timestampedFileName(
    String path, {
    required String fallbackExtension,
  }) {
    final foundExtension = _fileExtension(path);
    final extension = foundExtension.isEmpty
        ? fallbackExtension
        : foundExtension;
    final originalName = _fileNameWithoutExtension(path);
    final safeName = _sanitizeFileName(
      originalName.isEmpty ? 'file' : originalName,
    );

    return '${DateTime.now().millisecondsSinceEpoch}_$safeName.$extension';
  }

  static String _sanitizeFileName(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    return sanitized.isEmpty ? 'file' : sanitized;
  }

  static String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  static String _fileNameWithoutExtension(String path) {
    final fileName = _fileNameFromPath(path);
    final lastDot = fileName.lastIndexOf('.');

    if (lastDot <= 0) return fileName;
    return fileName.substring(0, lastDot);
  }

  static String _fileExtension(String path) {
    final fileName = _fileNameFromPath(path);
    final lastDot = fileName.lastIndexOf('.');

    if (lastDot < 0 || lastDot == fileName.length - 1) return '';
    return fileName.substring(lastDot + 1).toLowerCase();
  }

  static String _contentTypeForExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'glb':
        return 'model/gltf-binary';
      case 'gltf':
        return 'model/gltf+json';
      case 'hex':
        return 'text/plain';
      case 'json':
        return 'application/json';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  static StorageServiceException _mapFirebaseStorageException(
    FirebaseException error,
  ) {
    switch (error.code) {
      case 'unauthenticated':
        return StorageServiceException(
          'You must be signed in before using Firebase Storage.',
          code: error.code,
          originalError: error,
        );
      case 'unauthorized':
        return StorageServiceException(
          'You do not have permission to access this file.',
          code: error.code,
          originalError: error,
        );
      case 'object-not-found':
        return StorageServiceException(
          'The requested file was not found.',
          code: error.code,
          originalError: error,
        );
      case 'bucket-not-found':
      case 'project-not-found':
        return StorageServiceException(
          'Firebase Storage is not configured correctly.',
          code: error.code,
          originalError: error,
        );
      case 'quota-exceeded':
        return StorageServiceException(
          'Firebase Storage quota has been exceeded.',
          code: error.code,
          originalError: error,
        );
      case 'retry-limit-exceeded':
        return StorageServiceException(
          'The upload took too long. Check the connection and try again.',
          code: error.code,
          originalError: error,
        );
      case 'canceled':
        return StorageServiceException(
          'The upload was cancelled.',
          code: error.code,
          originalError: error,
        );
      default:
        return StorageServiceException(
          error.message ?? 'Firebase Storage operation failed.',
          code: error.code,
          originalError: error,
        );
    }
  }

  static String _formatBytes(int bytes) {
    const kilobyte = 1024;
    const megabyte = 1024 * kilobyte;
    const gigabyte = 1024 * megabyte;

    if (bytes >= gigabyte) {
      return '${(bytes / gigabyte).toStringAsFixed(1)} GB';
    }

    if (bytes >= megabyte) {
      return '${(bytes / megabyte).toStringAsFixed(1)} MB';
    }

    if (bytes >= kilobyte) {
      return '${(bytes / kilobyte).toStringAsFixed(1)} KB';
    }

    return '$bytes bytes';
  }

  static Future<List<Trip>> loadTrips() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(tripsKey);

    if (raw == null) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      return decoded
          .whereType<Map>()
          .map((item) => Trip.fromJson(item.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveTrips(List<Trip> trips) async {
    final sp = await SharedPreferences.getInstance();

    await sp.setString(
      tripsKey,
      jsonEncode(trips.map((trip) => trip.toJson()).toList()),
    );
  }

  static Future<void> saveTrip(Trip trip) async {
    final trips = await loadTrips();

    final exists = trips.any(
      (savedTrip) =>
          savedTrip.startedAtMs == trip.startedAtMs &&
          savedTrip.endedAtMs == trip.endedAtMs,
    );

    if (!exists) {
      trips.insert(0, trip);
    }

    await saveTrips(trips);
  }

  static Future<RideRoutePlan?> loadActiveRoute() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(activeRouteKey);

    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);

      if (decoded is Map<String, dynamic>) {
        return RideRoutePlan.fromJson(decoded);
      }

      if (decoded is Map) {
        return RideRoutePlan.fromJson(decoded.cast<String, dynamic>());
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveActiveRoute(RideRoutePlan route) async {
    final sp = await SharedPreferences.getInstance();

    await sp.setString(activeRouteKey, jsonEncode(route.toJson()));
  }

  static Future<void> clearActiveRoute() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(activeRouteKey);
  }

  static Future<List<MunjaDevice>> loadSavedDevices() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(savedDevicesKey);

    if (raw == null) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      return decoded
          .whereType<Map>()
          .map((item) => MunjaDevice.fromJson(item.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveDevice(MunjaDevice device) async {
    final sp = await SharedPreferences.getInstance();
    final current = await loadSavedDevices();
    final index = current.indexWhere(
      (savedDevice) => savedDevice.id == device.id,
    );

    if (index >= 0) {
      current[index] = device;
    } else {
      current.add(device);
    }

    await sp.setString(
      savedDevicesKey,
      jsonEncode(current.map((item) => item.toJson()).toList()),
    );

    await sp.setString(lastDeviceKey, device.id);
  }

  static Future<UserProfile> loadUserProfile() async {
    final sp = await SharedPreferences.getInstance();

    return UserProfile(
      name: sp.getString(userNameKey) ?? 'Rider',
      age: sp.getInt(userAgeKey) ?? 24,
      city: sp.getString(userCityKey) ?? 'Copenhagen',
      avatarIndex: sp.getInt(userAvatarKey) ?? 0,
      photoPath: sp.getString(userPhotoPathKey),
    );
  }

  static Future<void> saveUserProfile(UserProfile profile) async {
    final sp = await SharedPreferences.getInstance();

    await sp.setString(userNameKey, profile.name.trim());
    await sp.setInt(userAgeKey, profile.age);
    await sp.setString(userCityKey, profile.city.trim());
    await sp.setInt(userAvatarKey, profile.avatarIndex);

    final photoPath = profile.photoPath?.trim();

    if (photoPath == null || photoPath.isEmpty) {
      await sp.remove(userPhotoPathKey);
    } else {
      await sp.setString(userPhotoPathKey, photoPath);
    }
  }

  static Future<String?> loadUserPhotoPath() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(userPhotoPathKey);
  }

  static Future<void> saveUserPhotoPath(String path) async {
    final sp = await SharedPreferences.getInstance();
    final trimmedPath = path.trim();

    if (trimmedPath.isEmpty) {
      await sp.remove(userPhotoPathKey);
      return;
    }

    await sp.setString(userPhotoPathKey, trimmedPath);
  }

  static Future<void> clearUserPhotoPath() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(userPhotoPathKey);
  }

  static Future<Map<String, dynamic>?> loadBgTripState() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(bgTripStateKey);

    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw);

      if (decoded is Map<String, dynamic>) return decoded;

      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveBgTripState(Map<String, dynamic> data) async {
    final sp = await SharedPreferences.getInstance();

    await sp.setString(bgTripStateKey, jsonEncode(data));
  }

  static Future<void> clearBgTripState() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(bgTripStateKey);
  }

  static Future<void> setOnboardingDone(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(onboardingDoneKey, value);
  }

  static Future<bool> isOnboardingDone() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(onboardingDoneKey) ?? false;
  }

  static Future<void> saveChallenge({
    required bool accepted,
    required String plan,
    required double weeklyGoalKm,
    DateTime? deadline,
  }) async {
    final sp = await SharedPreferences.getInstance();

    await sp.setBool(challengeAcceptedKey, accepted);
    await sp.setString(challengePlanKey, plan);
    await sp.setDouble(weeklyGoalKmKey, weeklyGoalKm);

    if (deadline == null) {
      await sp.remove(challengeDeadlineKey);
    } else {
      await sp.setInt(challengeDeadlineKey, deadline.millisecondsSinceEpoch);
    }
  }

  static Future<void> setBackgroundTrackingEnabled(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(bgTrackingEnabledKey, value);
  }

  static Future<bool> isBackgroundTrackingEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(bgTrackingEnabledKey) ?? false;
  }
}
