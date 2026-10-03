import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'navegacion.dart';
import 'screens/home_screen.dart';
import 'services/background_service.dart';
import 'services/notificacion_alarma.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final lanzamiento = await iniciarNotificaciones(
    alTocar: (respuesta) {
      if (respuesta.payload == payloadAlarma) abrirPantallaAlarma();
    },
  );
  final porAlarma = abiertaPorAlarma(lanzamiento);
  // Si la abrió el full-screen intent, la alarma va primero: nada de diálogos.
  if (!porAlarma) await _solicitarPermisosCriticos();
  await configurarServicioSegundoPlano();
  runApp(const MyApp());
  if (porAlarma) {
    WidgetsBinding.instance.addPostFrameCallback((_) => abrirPantallaAlarma());
  }
}

Future<void> _solicitarPermisosCriticos() async {
  final permisos = <Permission>[
    Permission.notification,
    Permission.microphone,
    Permission.locationWhenInUse,
    Permission.sms,
    Permission.phone,
  ];

  for (final permiso in permisos) {
    final estado = await permiso.status;
    if (estado.isDenied || estado.isLimited) {
      final resultado = await permiso.request();
      debugPrint('🔐 Permiso $permiso: $resultado');
    }
  }

  // Android 14+: pantalla completa es un permiso especial que se concede en
  // Ajustes. Se pide una sola vez para no abrir Ajustes en cada arranque.
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool('permiso_pantalla_completa_pedido') ?? false)) {
    await prefs.setBool('permiso_pantalla_completa_pedido', true);
    try {
      final concedido = await solicitarPermisoPantallaCompleta();
      debugPrint('🔐 Pantalla completa: $concedido');
    } catch (e) {
      debugPrint('⚠️ No se pudo pedir pantalla completa: $e');
      await openAppSettings();
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Centinela',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.red, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
