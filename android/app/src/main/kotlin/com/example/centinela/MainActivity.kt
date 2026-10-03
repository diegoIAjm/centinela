package com.example.centinela

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CANAL_PANTALLA = "com.example.centinela/pantalla"

    override fun onCreate(savedInstanceState: Bundle?) {
        // Antes de super: la ventana debe nacer ya sobre el bloqueo.
        if (esIntentDeAlarma(intent)) mostrarSobreBloqueo(true)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        if (esIntentDeAlarma(intent)) mostrarSobreBloqueo(true)
        super.onNewIntent(intent)
    }

    /// Intent del full-screen intent / toque en la notificación de alarma
    /// (acción y extra que usa flutter_local_notifications).
    private fun esIntentDeAlarma(intent: Intent?): Boolean {
        if (intent == null) return false
        // Reabrir desde Recientes reutiliza el intent viejo: no cuenta.
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return false
        return intent.action == "SELECT_NOTIFICATION" &&
            intent.getStringExtra("payload") == "alarma_activa"
    }

    /// Solo durante la alarma: si quedara fijo en el manifest, cualquiera
    /// podría ver contactos o cambiar los PINs sin desbloquear el teléfono.
    private fun mostrarSobreBloqueo(activo: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(activo)
            setTurnScreenOn(activo)
        } else {
            @Suppress("DEPRECATION")
            val banderas = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (activo) window.addFlags(banderas) else window.clearFlags(banderas)
        }
        if (activo) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_PANTALLA)
            .setMethodCallHandler { call, result ->
                if (call.method == "mostrarSobreBloqueo") {
                    mostrarSobreBloqueo(call.arguments as? Boolean ?: false)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

    }
}
