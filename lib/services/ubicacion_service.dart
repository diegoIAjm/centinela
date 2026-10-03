import 'package:geolocator/geolocator.dart';

class UbicacionService {
  /// [limite] acota la espera del GPS; al vencer se usa la última conocida.
  Future<Position?> obtenerUbicacion({
    Duration limite = const Duration(seconds: 15),
  }) async {
    // 1. ¿Está activado el GPS?
    final servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) {
      return null;
    }

    // 2. Permisos
    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied ||
        permiso == LocationPermission.deniedForever) {
      return null;
    }

    // 3. Primero intenta la última conocida (rápida y suele existir)
    try {
      final ultima = await Geolocator.getLastKnownPosition();
      if (ultima != null) {
        // Si es reciente (menos de 2 minutos), la damos por buena
        final antiguedad = DateTime.now()
            .difference(ultima.timestamp)
            .inSeconds;
        if (antiguedad < 120) return ultima;
      }
    } catch (_) {
      // Ignoramos, seguimos con la posición actual
    }

    // 4. Posición actual, acotada por el límite
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: limite,
        ),
      );
    } catch (_) {
      // 5. Último intento: devolver la última conocida aunque sea vieja
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  String generarLinkMapa(double lat, double lon) {
    return 'https://maps.google.com/?q=$lat,$lon';
  }

  Future<String> obtenerLinkUbicacion({
    Duration limite = const Duration(seconds: 15),
  }) async {
    final pos = await obtenerUbicacion(limite: limite);
    if (pos == null) return 'Ubicación no disponible';
    return generarLinkMapa(pos.latitude, pos.longitude);
  }
}
