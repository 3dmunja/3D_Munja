import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/trip.dart';
import '../Services/live_ride_bus.dart';
import 'ride_controller_service.dart';

class BackgroundRideEngine {
  BackgroundRideEngine._();

  static final BackgroundRideEngine instance = BackgroundRideEngine._();

  bool _initialized = false;
  bool _starting = false;
  bool _stopping = false;

  Future<void> initialize() async {
    if (_initialized) return;

    FlutterForegroundTask.initCommunicationPort();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'munja_ride_engine_channel',
        channelName: 'Munja Ride Engine',
        channelDescription: 'Keeps Munja ride tracking active in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        showWhen: true,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    await LiveRideBus.instance.initialize();

    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

    _initialized = true;

    debugPrint(
      'BackgroundRideEngine initialized: '
      'bus=${LiveRideBus.instance.debugInstanceId}',
    );
  }

  Future<void> start() async {
    if (_starting) return;
    _starting = true;

    try {
      await initialize();

      final permissionOk = await _ensurePermissions();

      if (!permissionOk) {
        debugPrint('BackgroundRideEngine permission denied');
        return;
      }

      await WakelockPlus.enable();

      final running = await FlutterForegroundTask.isRunningService;

      if (!running) {
        await FlutterForegroundTask.startService(
          serviceId: 3001,
          notificationTitle: 'Munja Ride Active',
          notificationText: 'Starting ride tracking...',
          notificationIcon: null,
          notificationInitialRoute: '/',
          callback: backgroundRideStartCallback,
        );
      }

      await RideControllerService.instance.startRide();

      await _syncFromController();
      await _syncNotification();

      debugPrint('BackgroundRideEngine started');
    } catch (e) {
      debugPrint('BackgroundRideEngine start error: $e');
    } finally {
      _starting = false;
    }
  }

  Future<Trip?> stop() async {
    if (_stopping) return null;
    _stopping = true;

    Trip? completedTrip;

    try {
      completedTrip = await RideControllerService.instance.stopRide();

      final running = await FlutterForegroundTask.isRunningService;

      if (running) {
        await FlutterForegroundTask.stopService();
      }

      await WakelockPlus.disable();

      await LiveRideBus.instance.stop();

      debugPrint('BackgroundRideEngine stopped');
    } catch (e) {
      debugPrint('BackgroundRideEngine stop error: $e');
    } finally {
      _stopping = false;
    }

    return completedTrip;
  }

  Future<void> recoverIfNeeded() async {
    await initialize();

    final state = LiveRideBus.instance.state.value;

    if (!state.isActive) return;

    await RideControllerService.instance.startRide();
    await _syncFromController();

    final running = await FlutterForegroundTask.isRunningService;

    if (!running) {
      await FlutterForegroundTask.startService(
        serviceId: 3001,
        notificationTitle: 'Munja Ride Active',
        notificationText: 'Recovering ride tracking...',
        notificationIcon: null,
        notificationInitialRoute: '/',
        callback: backgroundRideStartCallback,
      );
    }

    await WakelockPlus.enable();
    await _syncNotification();

    debugPrint(
      'BackgroundRideEngine recovery checked: '
      'active=${LiveRideBus.instance.state.value.isActive}',
    );
  }

  Future<void> _syncFromController() async {
    final controller = RideControllerService.instance;
    final current = LiveRideBus.instance.state.value;

    LiveRideBus.instance.patch(
      isActive: controller.isRideActive.value,
      speedKmh: controller.speedKmh.value,
      averageSpeedKmh: controller.averageSpeedKmh.value,
      maxSpeedKmh: controller.speedKmh.value > current.maxSpeedKmh
          ? controller.speedKmh.value
          : current.maxSpeedKmh,
      distanceKm: controller.distanceKm.value,
      duration: controller.rideDuration.value,
      lastUpdate: DateTime.now(),
    );
  }

  Future<void> _syncNotification() async {
    final state = LiveRideBus.instance.state.value;

    if (!state.isActive) return;

    final distance = state.distanceKm.toStringAsFixed(2);
    final speed = state.speedKmh.toStringAsFixed(1);
    final time = _formatDuration(state.duration);

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Munja Ride Active',
      notificationText: '$distance km · $speed km/h · $time',
    );
  }

  void _onReceiveTaskData(Object data) {
    if (data is! String) {
      debugPrint(
        'BackgroundRideEngine ignored non-string task data: '
        '${data.runtimeType}',
      );
      return;
    }

    switch (data) {
      case 'syncNotification':
        unawaited(_syncNotification());
        break;
      case 'stopRide':
        unawaited(stop());
        break;
      case 'recoverRide':
        unawaited(recoverIfNeeded());
        break;
      default:
        debugPrint('BackgroundRideEngine ignored task data: $data');
    }
  }

  Future<bool> _ensurePermissions() async {
    final locationEnabled = await Geolocator.isLocationServiceEnabled();

    if (!locationEnabled) return false;

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();

    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    return true;
  }

  String _formatDuration(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);

    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Future<void> dispose() async {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
  }
}

@pragma('vm:entry-point')
void backgroundRideStartCallback() {
  FlutterForegroundTask.setTaskHandler(BackgroundRideTaskHandler());
}

class BackgroundRideTaskHandler extends TaskHandler {
  Timer? _timer;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      FlutterForegroundTask.sendDataToMain('syncNotification');
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.sendDataToMain('syncNotification');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void onReceiveData(Object data) {
    if (data == 'STOP_RIDE') {
      FlutterForegroundTask.sendDataToMain('stopRide');
    }

    if (data == 'RECOVER_RIDE') {
      FlutterForegroundTask.sendDataToMain('recoverRide');
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      FlutterForegroundTask.sendDataToMain('stopRide');
    }
  }

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}
