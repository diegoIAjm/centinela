import 'package:flutter/material.dart';
import '../models/contacto.dart';
import '../services/database_service.dart';
import '../tema.dart';
import '../widgets/ui.dart';

class ContactosScreen extends StatefulWidget {
  const ContactosScreen({super.key});

  @override
  State<ContactosScreen> createState() => _ContactosScreenState();
}

class _ContactosScreenState extends State<ContactosScreen> {
  final _db = DatabaseService();
  final _form = GlobalKey<FormState>();
  List<Contacto>? _contactos;
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final lista = await _db.obtenerContactos();
    if (mounted) setState(() => _contactos = lista);
  }

  Future<void> _agregar() async {
    if (!_form.currentState!.validate()) return;
    await _db.insertarContacto(
      Contacto(
        nombre: _nombreCtrl.text.trim(),
        telefono: _telefonoCtrl.text.replaceAll(' ', '').trim(),
      ),
    );
    _nombreCtrl.clear();
    _telefonoCtrl.clear();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    mostrarMensaje(context, 'Contacto agregado', tipo: TipoAviso.exito);
    _cargar();
  }

  Future<void> _eliminar(Contacto c) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Eliminar contacto'),
        content: Text(
          '${c.nombre} dejará de recibir tus alertas de emergencia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Paleta.peligro),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await _db.eliminarContacto(c.id!);
    _cargar();
  }

  String? _validarTelefono(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Ingresa un número';
    if (!RegExp(r'^\+?\d{7,15}$').hasMatch(t.replaceAll(' ', ''))) {
      return 'Solo números, de 7 a 15 dígitos. Ej.: +59170000000';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final lista = _contactos;
    return Scaffold(
      appBar: AppBar(title: const Text('Contactos de emergencia')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Aviso(
            tipo: TipoAviso.info,
            titulo: 'Quiénes reciben tu alerta',
            texto:
                'Cuando se active la alarma, cada contacto recibirá por SMS '
                'tu ubicación y los enlaces a las grabaciones.',
          ),
          const EncabezadoSeccion('Agregar contacto'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Ingresa un nombre'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _telefonoCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono con código de país',
                        hintText: '+59170000000',
                      ),
                      validator: _validarTelefono,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _agregar,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Agregar contacto'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          EncabezadoSeccion(
            lista == null || lista.isEmpty
                ? 'Contactos guardados'
                : 'Contactos guardados (${lista.length})',
          ),
          if (lista == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (lista.isEmpty)
            const EstadoVacio(
              icono: Icons.group_outlined,
              titulo: 'Aún no hay contactos',
              texto: 'Agrega al menos una persona de confianza.',
            )
          else
            GrupoOpciones([
              for (final c in lista)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Paleta.infoFondo,
                    foregroundColor: Paleta.marino,
                    child: Text(
                      c.nombre.trim().isEmpty
                          ? '?'
                          : c.nombre.trim()[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  title: Text(c.nombre),
                  subtitle: Text(c.telefono),
                  trailing: IconButton(
                    tooltip: 'Eliminar ${c.nombre}',
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Paleta.peligro,
                    ),
                    onPressed: () => _eliminar(c),
                  ),
                ),
            ]),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }
}
