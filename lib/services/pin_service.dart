import 'package:shared_preferences/shared_preferences.dart';

class PinService {
  static const _keyPinReal = 'pin_real';
  static const _keyPinFalso = 'pin_falso';
  static const _keyConfigurado = 'pin_configurado';

  // Guardar ambos PINs
  Future<void> guardarPines(String pinReal, String pinFalso) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPinReal, pinReal);
    await prefs.setString(_keyPinFalso, pinFalso);
    await prefs.setBool(_keyConfigurado, true);
  }

  // Obtener PIN real
  Future<String?> obtenerPinReal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPinReal);
  }

  // Obtener PIN falso
  Future<String?> obtenerPinFalso() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPinFalso);
  }

  // Verificar si ya está configurado
  Future<bool> estaConfigurado() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyConfigurado) ?? false;
  }

  // Verificar qué tipo de PIN ingresó el usuario
  // Retorna: 'real', 'falso' o 'invalido'
  Future<String> verificarPin(String pinIngresado) async {
    final pinReal = await obtenerPinReal();
    final pinFalso = await obtenerPinFalso();

    if (pinIngresado == pinReal) return 'real';
    if (pinIngresado == pinFalso) return 'falso';
    return 'invalido';
  }

  // Borrar PINs (para pruebas o reset)
  Future<void> borrarPines() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPinReal);
    await prefs.remove(_keyPinFalso);
    await prefs.remove(_keyConfigurado);
  }
}
