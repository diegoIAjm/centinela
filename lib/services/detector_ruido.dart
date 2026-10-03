/// Ruido sobre el umbral durante 1,5 s; tolera pausas breves (gritos, golpes
/// seguidos) pero un golpe aislado no activa.
class DetectorRuido {
  static const duracion = Duration(milliseconds: 1500);
  static const pausaTolerada = Duration(milliseconds: 400);

  Duration? _inicio;
  Duration? _ultimo;

  bool agregar(bool sobreUmbral, Duration instante) {
    if (!sobreUmbral) {
      if (_ultimo != null && instante - _ultimo! > pausaTolerada) resetear();
      return false;
    }
    if (_ultimo == null || instante - _ultimo! > pausaTolerada) {
      _inicio = instante;
    }
    _ultimo = instante;
    if (instante - _inicio! < duracion) return false;
    resetear();
    return true;
  }

  void resetear() {
    _inicio = null;
    _ultimo = null;
  }
}
