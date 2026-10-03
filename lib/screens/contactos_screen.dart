import 'package:flutter/material.dart';
import '../models/contacto.dart';
import '../services/database_service.dart';

class ContactosScreen extends StatefulWidget {
  const ContactosScreen({super.key});

  @override
  State<ContactosScreen> createState() => _ContactosScreenState();
}

class _ContactosScreenState extends State<ContactosScreen> {
  final _db = DatabaseService();
  List<Contacto> _contactos = [];
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final lista = await _db.obtenerContactos();
    setState(() => _contactos = lista);
  }

  Future<void> _agregar() async {
    final nombre = _nombreCtrl.text.trim();
    final telefono = _telefonoCtrl.text.trim();
    if (nombre.isEmpty || telefono.isEmpty) return;

    await _db.insertarContacto(Contacto(nombre: nombre, telefono: telefono));
    _nombreCtrl.clear();
    _telefonoCtrl.clear();
    _cargar();
  }

  Future<void> _eliminar(int id) async {
    await _db.eliminarContacto(id);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contactos de Emergencia'),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _telefonoCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono (con código de país)',
                hintText: '+59170000000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _agregar,
              icon: const Icon(Icons.add),
              label: const Text('Agregar contacto'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
            const Divider(height: 30),
            Expanded(
              child: _contactos.isEmpty
                  ? const Center(child: Text('No hay contactos guardados'))
                  : ListView.builder(
                      itemCount: _contactos.length,
                      itemBuilder: (context, index) {
                        final c = _contactos[index];
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.red,
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                            title: Text(c.nombre),
                            subtitle: Text(c.telefono),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _eliminar(c.id!),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
