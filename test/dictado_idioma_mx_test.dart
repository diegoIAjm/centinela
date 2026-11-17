import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'dictado_soporte.dart';

void main() {
  testWidgets('Sin es_ES prueba es_MX una sola vez', (tester) async {
    String? mensaje;
    final idiomas = await abrirDictado(
      tester,
      luego: (evento) async {
        for (var n = 0; n < 2; n++) {
          await evento(
            'notifyError',
            jsonEncode({
              'errorMsg': 'error_language_unavailable',
              'permanent': true,
            }),
          );
        }
        mensaje = find.textContaining('español para dictado').evaluate().isEmpty
            ? null
            : 'mostrado';
      },
    );
    expect(idiomas, ['es_ES', 'es_MX']);
    expect(mensaje, 'mostrado');
  });
}
