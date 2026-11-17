import 'package:flutter_test/flutter_test.dart';

import 'dictado_soporte.dart';

void main() {
  testWidgets('Dicta aunque locales() nunca responda', (tester) async {
    final idiomas = await abrirDictado(tester);
    expect(idiomas, ['es_ES']);
    expect(find.textContaining('TimeoutException'), findsNothing);
  });
}
