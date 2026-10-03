class Contacto {
  final int? id;
  final String nombre;
  final String telefono;

  Contacto({this.id, required this.nombre, required this.telefono});

  Map<String, dynamic> toMap() {
    return {'id': id, 'nombre': nombre, 'telefono': telefono};
  }

  factory Contacto.fromMap(Map<String, dynamic> map) {
    return Contacto(
      id: map['id'],
      nombre: map['nombre'],
      telefono: map['telefono'],
    );
  }
}
