import 'package:flutter/material.dart';
import 'screens/alarma_activa_screen.dart';
import 'screens/datos_incidente_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Abre la pantalla de alarma una sola vez, venga de la notificación, del
/// full-screen intent o del estado publicado por el servicio.
void abrirPantallaAlarma() {
  final navegador = navigatorKey.currentState;
  if (navegador == null || AlarmaActivaScreen.visible) return;
  navegador.push(
    MaterialPageRoute(
      builder: (_) => const AlarmaActivaScreen(alarmaYaActiva: true),
    ),
  );
}

/// Tras cancelar la alarma de verdad (PIN real o "Estoy a salvo"). Con PIN
/// falso el servicio no avisa, así que esto nunca aparece frente al agresor.
Future<void> ofrecerCompletarInforme(int idIncidente) async {
  final contexto = navigatorKey.currentContext;
  if (contexto == null) return;
  final ahora = await showDialog<bool>(
    context: contexto,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.description, size: 40),
      title: const Text('¿Quieres completar el informe ahora?'),
      content: const Text(
        'Puedes registrar quién fue y qué pasó para generar un informe de '
        'denuncia en PDF. Si prefieres, queda pendiente en el historial.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Más tarde'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Sí, ahora'),
        ),
      ],
    ),
  );
  if (ahora != true) return;
  await navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => DatosIncidenteScreen(idIncidente: idIncidente),
    ),
  );
}
