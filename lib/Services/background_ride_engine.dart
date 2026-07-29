import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/trip.dart';
import 'live_ride_bus.dart';
import 'ride_controller_service.dart';

class BackgroundRideEngine {
  BackgroundRideEngine._();

  static final BackgroundRideEngine instance = BackgroundRideEngine._();

  bool _initialized = false;
  bool _starting = false;
  bool _stopping = false;

  StreamSubscription<LiveRideEngineEvent>? _eventSub;

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

    _eventSub?.cancel();
    _eventSub = LiveRideEngineEventBus.instance.stream.listen(_handleEvent);

    _initialized = true;

    debugPrint('BackgroundRideEngine initialized');
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

      LiveRideBus.instance.start();

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

    final running = await FlutterForegroundTask.isRunningService;

    if (!running) {
      await start();
    } else {
      await WakelockPlus.enable();
      await _syncNotification();
    }

    debugPrint('BackgroundRideEngine recovery checked');
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
    await _syncFromController();

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

  void _handleEvent(LiveRideEngineEvent event) {
    switch (event.type) {
      case LiveRideEngineEventType.syncNotification:
        _syncNotification();
        break;
      case LiveRideEngineEventType.stopRide:
        stop();
        break;
      case LiveRideEngineEventType.recover:
        recoverIfNeeded();
        break;
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
    await _eventSub?.cancel();
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
      LiveRideEngineEventBus.instance.emit(
        const LiveRideEngineEvent.syncNotification(),
      );
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    LiveRideEngineEventBus.instance.emit(
      const LiveRideEngineEvent.syncNotification(),
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void onReceiveData(Object data) {
    if (data == 'STOP_RIDE') {
      LiveRideEngineEventBus.instance.emit(
        const LiveRideEngineEvent.stopRide(),
      );
    }

    if (data == 'RECOVER_RIDE') {
      LiveRideEngineEventBus.instance.emit(const LiveRideEngineEvent.recover());
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      LiveRideEngineEventBus.instance.emit(
        const LiveRideEngineEvent.stopRide(),
      );
    }
  }

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}

enum LiveRideEngineEventType { syncNotification, stopRide, recover }

class LiveRideEngineEvent {
  final LiveRideEngineEventType type;

  const LiveRideEngineEvent._(this.type);

  const LiveRideEngineEvent.syncNotification()
    : this._(LiveRideEngineEventType.syncNotification);

  const LiveRideEngineEvent.stopRide()
    : this._(LiveRideEngineEventType.stopRide);

  const LiveRideEngineEvent.recover() : this._(LiveRideEngineEventType.recover);
}

class LiveRideEngineEventBus {
  LiveRideEngineEventBus._();

  static final LiveRideEngineEventBus instance = LiveRideEngineEventBus._();

  final StreamController<LiveRideEngineEvent> _controller =
      StreamController<LiveRideEngineEvent>.broadcast();

  Stream<LiveRideEngineEvent> get stream => _controller.stream;

  void emit(LiveRideEngineEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
