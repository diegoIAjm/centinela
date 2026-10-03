import 'package:flutter_test/flutter_test.dart';
import 'package:centinela/services/dictado_parser.dart';

void main() {
  test('Dictado completo del denunciante', () {
    final r = interpretarDenunciante(
      'Mi nombre es maría pérez gutiérrez, mi carnet es 12345678 LP, '
      'nací el 5 de marzo de 1990, mi domicilio es calle Sucre número 45 '
      'zona central, mi teléfono es 7 1234 567 y trabajo como enfermera.',
    );
    expect(r['nombre_completo'], 'María Pérez Gutiérrez');
    expect(r['ci'], '12345678');
    expect(r['ci_ext'], 'LP');
    expect(r['fecha_nacimiento'], '1990-03-05');
    expect(r['domicilio'], 'Calle Sucre número 45 zona central');
    expect(r['telefono'], '71234567');
    expect(r['ocupacion'], 'Enfermera');
  });

  test('Extensión del CI dicha como departamento', () {
    final r = interpretarDenunciante('carnet 9876543 santa cruz');
    expect(r['ci'], '9876543');
    expect(r['ci_ext'], 'SC');
  });

  test('Campos faltantes no se inventan', () {
    final r = interpretarDenunciante('me llamo Ana Rojas');
    expect(r, {'nombre_completo': 'Ana Rojas'});
  });

  test('Dictado del agresor', () {
    final r = interpretarAgresor(
      'Se llama Juan Mamani, es mi ex pareja, vive en la avenida Blanco '
      'Galindo kilómetro 5, descripción física alto moreno con cicatriz.',
    );
    expect(r['nombre_agresor'], 'Juan Mamani');
    expect(r['relacion_agresor'], 'Ex pareja');
    expect(r['domicilio_agresor'], 'Avenida Blanco Galindo kilómetro 5');
    expect(r['descripcion_agresor'], 'Alto moreno con cicatriz');
  });

  test('Relación reconocida por palabras sueltas', () {
    expect(relacionDesdeTexto('es mi vecino del frente'), 'Vecino');
    expect(relacionDesdeTexto('mi tío'), 'Familiar');
    expect(relacionDesdeTexto('no lo conozco'), 'Desconocido');
    expect(relacionDesdeTexto('mi jefe'), 'Compañero de trabajo');
    expect(relacionDesdeTexto('nada que ver'), isNull);
  });

  test('Fechas', () {
    expect(interpretarFecha('12/11/1985'), '1985-11-12');
    expect(interpretarFecha('31 de febrero de 2000'), isNull);
    expect(interpretarFecha('1 de setiembre del 2001'), '2001-09-01');
  });
}
