import 'dart:async';

import '../models/ride_route_plan.dart';
import 'storage_service.dart';

class ActiveRouteService {
  ActiveRouteService._();

  static final ActiveRouteService instance = ActiveRouteService._();

  final StreamController<RideRoutePlan?> _controller =
      StreamController<RideRoutePlan?>.broadcast();

  RideRoutePlan? _activeRoute;

  Stream<RideRoutePlan?> get stream => _controller.stream;

  RideRoutePlan? get current => _activeRoute;

  Future<void> load() async {
    _activeRoute = await StorageService.loadActiveRoute();
    _emit();
  }

  Future<void> setActiveRoute(RideRoutePlan route) async {
    _activeRoute = route;
    await StorageService.saveActiveRoute(route);
    _emit();
  }

  Future<void> clear() async {
    _activeRoute = null;
    await StorageService.clearActiveRoute();
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_activeRoute);
    }
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
