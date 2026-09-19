import '../models/bike_profile.dart';
import '../models/firestore_bike.dart';

class BikeModelResolver {
  const BikeModelResolver._();

  static const String roadModel = 'assets/models/Road_Bike_Master.glb';
  static const String kidsMtbModel = 'assets/models/kids_mtb_master.glb';
  static const String mtbModel = 'assets/models/kids_mtb_master.glb';
  static const String gravelModel = 'assets/models/munja_bike.glb';
  static const String cityModel = 'assets/models/munja_bike.glb';
  static const String ebikeModel = 'assets/models/munja_bike.glb';

  static String resolveModelPath({
    required BikeType type,
    BikeWheelSize wheelSize = BikeWheelSize.unknown,
  }) {
    switch (type) {
      case BikeType.road:
        return roadModel;

      case BikeType.gravel:
        return gravelModel;

      case BikeType.mtb:
        return mtbModel;

      case BikeType.city:
        return cityModel;

      case BikeType.ebike:
        return ebikeModel;

      case BikeType.kidsMtb:
        return kidsMtbModel;
    }
  }

  static String resolveFirestoreModelPath(FirestoreBikeType type) {
    switch (type) {
      case FirestoreBikeType.road:
        return roadModel;
      case FirestoreBikeType.mtb:
      case FirestoreBikeType.kids:
        return mtbModel;
      case FirestoreBikeType.gravel:
        return gravelModel;
      case FirestoreBikeType.city:
        return cityModel;
      case FirestoreBikeType.ebike:
        return ebikeModel;
      case FirestoreBikeType.other:
        return mtbModel;
    }
  }

  static String previewName(BikeType type) {
    switch (type) {
      case BikeType.road:
        return 'Road Bike';

      case BikeType.gravel:
        return 'Gravel Bike';

      case BikeType.mtb:
        return 'MTB';

      case BikeType.city:
        return 'City Bike';

      case BikeType.ebike:
        return 'E-bike';

      case BikeType.kidsMtb:
        return 'Kids MTB';
    }
  }
}
