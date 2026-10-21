import 'package:geolocator/geolocator.dart';

/// One GPS fix per batch. Failed requests can be retried; concurrent callers
/// share the same request. Create a new instance or clear after ending a batch.
class BatchScanLocation {
  final Future<Position> Function() _locate;
  Future<Position>? _position;

  BatchScanLocation({Future<Position> Function()? locate})
    : _locate = locate ?? _getCurrentLocation;

  Future<Position> get() => _position ??= _load();

  Future<Position> _load() async {
    try {
      return await _locate();
    } catch (_) {
      _position = null;
      rethrow;
    }
  }

  void clear() => _position = null;

  static Future<Position> _getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception(
        'Location services are turned off. Please enable GPS and try again.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is required. Please enable location access in your device settings.',
      );
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }
}
