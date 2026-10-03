import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Control "desliza para confirmar": solo dispara [onConfirmado] si el pulgar
/// llega al final del riel; si se suelta antes, vuelve al inicio.
class DeslizarParaConfirmar extends StatefulWidget {
  final String texto;
  final VoidCallback onConfirmado;
  final Color color;
  final IconData icono;

  const DeslizarParaConfirmar({
    super.key,
    required this.texto,
    required this.onConfirmado,
    this.color = Colors.green,
    this.icono = Icons.check,
  });

  @override
  State<DeslizarParaConfirmar> createState() => _DeslizarParaConfirmarState();
}

class _DeslizarParaConfirmarState extends State<DeslizarParaConfirmar>
    with SingleTickerProviderStateMixin {
  static const _alto = 64.0;
  static const _umbral = 0.9;

  late final AnimationController _regreso = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..addListener(() => setState(() => _progreso = _regreso.value));
  double _progreso = 0;
  bool _confirmado = false;

  void _arrastrar(DragUpdateDetails d, double recorrido) {
    if (_confirmado) return;
    _regreso.stop();
    setState(() {
      _progreso = (_progreso + d.delta.dx / recorrido).clamp(0.0, 1.0);
    });
  }

  void _soltar() {
    if (_confirmado) return;
    if (_progreso >= _umbral) {
      setState(() {
        _progreso = 1;
        _confirmado = true;
      });
      HapticFeedback.heavyImpact();
      widget.onConfirmado();
    } else {
      _regreso.value = _progreso;
      _regreso.animateTo(0, curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, restricciones) {
        final ancho = restricciones.maxWidth;
        final recorrido = ancho - _alto;
        final pulgar = _progreso * recorrido;
        return Semantics(
          button: true,
          label: widget.texto,
          onTap: _confirmado ? null : widget.onConfirmado,
          child: Container(
            height: _alto,
            width: ancho,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(_alto / 2),
              border: Border.all(color: Colors.white54),
            ),
            child: Stack(
              children: [
                // Relleno que sigue al pulgar
                Container(
                  width: pulgar + _alto,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(
                      alpha: 0.35 + 0.65 * _progreso,
                    ),
                    borderRadius: BorderRadius.circular(_alto / 2),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(left: _alto),
                    child: Opacity(
                      opacity: (1 - _progreso * 1.5).clamp(0.0, 1.0),
                      child: Text(
                        '${widget.texto}  ›››',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: pulgar,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (d) => _arrastrar(d, recorrido),
                    onHorizontalDragEnd: (_) => _soltar(),
                    onHorizontalDragCancel: _soltar,
                    child: Container(
                      width: _alto,
                      height: _alto,
                      padding: const EdgeInsets.all(4),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _confirmado ? Icons.check : widget.icono,
                          color: widget.color,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _regreso.dispose();
    super.dispose();
  }
}
