/// Tres impulsos separados por 150–800 ms; un golpe aislado no activa.
class DetectorAgitado {
  Duration? _ultimo;
  int _cuenta = 0;
  bool _sobreUmbral = false;

  bool agregar(double magnitud, Duration instante) {
    if (magnitud < 11) _sobreUmbral = false;
    if (magnitud < 15 || _sobreUmbral) return false;
    _sobreUmbral = true;
    final intervalo = _ultimo == null ? null : instante - _ultimo!;
    if (intervalo != null && intervalo.inMilliseconds < 150) return false;
    _cuenta = intervalo == null || intervalo.inMilliseconds > 800
        ? 1
        : _cuenta + 1;
    _ultimo = instante;
    if (_cuenta < 3) return false;
    resetear();
    return true;
  }

  void resetear() {
    _ultimo = null;
    _cuenta = 0;
    _sobreUmbral = false;
  }
}
