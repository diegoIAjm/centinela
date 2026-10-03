package com.example.centinela_nativo;

import android.Manifest;
import android.app.Activity;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.telephony.SmsManager;
import android.telephony.SubscriptionInfo;
import android.telephony.SubscriptionManager;
import android.util.Log;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Se registra en cada FlutterEngine, incluido el del servicio en segundo
 * plano, y no necesita Activity (a diferencia de telephony o record).
 */
public class CentinelaNativoPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private static final String TAG = "CentinelaNativo";
  private static final long ESPERA_CONFIRMACION_MS = 15_000;
  private static final AtomicInteger contador = new AtomicInteger();

  private MethodChannel canal;
  private Context contexto;
  private final Handler principal = new Handler(Looper.getMainLooper());

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    contexto = binding.getApplicationContext();
    canal = new MethodChannel(binding.getBinaryMessenger(), "centinela_nativo");
    canal.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    canal.setMethodCallHandler(null);
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    switch (call.method) {
      case "enviarSms":
        enviarSms(call.argument("telefonos"), call.argument("mensaje"), result);
        break;
      case "abrirAlarma":
        result.success(abrirAlarma());
        break;
      case "puedeAbrirSobreBloqueo":
        result.success(puedeAbrirSobreBloqueo());
        break;
      default:
        result.notImplemented();
    }
  }

  // ===================== SMS =====================

  /**
   * Envía a todos los teléfonos y responde cuando el sistema confirma cada
   * parte (o a los 30 s): {despachados, fallidos: [..]}.
   */
  private void enviarSms(List<String> telefonos, String mensaje, MethodChannel.Result result) {
    if (telefonos == null || telefonos.isEmpty() || mensaje == null) {
      result.error("ARGUMENTOS", "Faltan teléfonos o mensaje", null);
      return;
    }
    if (Build.VERSION.SDK_INT >= 23
        && contexto.checkSelfPermission(Manifest.permission.SEND_SMS)
            != PackageManager.PERMISSION_GRANTED) {
      result.error("SIN_PERMISO", "Permiso SEND_SMS no concedido", null);
      return;
    }

    final SmsManager sms;
    try {
      sms = obtenerSmsManager();
    } catch (Exception e) {
      result.error("SIN_SIM", "No hay SIM disponible para SMS: " + e.getMessage(), null);
      return;
    }

    final String accion = contexto.getPackageName() + ".SMS_ENVIADO." + contador.incrementAndGet();
    final Map<String, Integer> pendientes = new HashMap<>();
    final List<String> fallidos = new ArrayList<>();
    final int[] despachados = {0};
    final boolean[] respondido = {false};

    final Runnable responder = new Runnable() {
      @Override
      public void run() {
        if (respondido[0]) return;
        respondido[0] = true;
        Map<String, Object> r = new HashMap<>();
        r.put("despachados", despachados[0]);
        r.put("fallidos", new ArrayList<>(fallidos));
        r.put("sinConfirmar", new ArrayList<>(pendientes.keySet()));
        result.success(r);
      }
    };

    final BroadcastReceiver receptor = new BroadcastReceiver() {
      @Override
      public void onReceive(Context c, Intent intent) {
        String tel = intent.getStringExtra("tel");
        if (tel == null || !pendientes.containsKey(tel)) return;
        if (getResultCode() != Activity.RESULT_OK) {
          Log.w(TAG, "SMS a " + tel + " falló, código " + getResultCode());
          if (!fallidos.contains(tel)) fallidos.add(tel);
        }
        int quedan = pendientes.get(tel) - 1;
        if (quedan <= 0) pendientes.remove(tel); else pendientes.put(tel, quedan);
        if (pendientes.isEmpty()) {
          try { contexto.unregisterReceiver(this); } catch (Exception ignored) {}
          principal.post(responder);
        }
      }
    };
    IntentFilter filtro = new IntentFilter(accion);
    if (Build.VERSION.SDK_INT >= 33) {
      contexto.registerReceiver(receptor, filtro, Context.RECEIVER_NOT_EXPORTED);
    } else {
      contexto.registerReceiver(receptor, filtro);
    }

    for (String original : telefonos) {
      String tel = original.replaceAll("[^0-9+]", "");
      if (tel.isEmpty()) continue;
      try {
        ArrayList<String> partes = sms.divideMessage(mensaje);
        ArrayList<PendingIntent> avisos = new ArrayList<>();
        for (int i = 0; i < partes.size(); i++) {
          Intent aviso = new Intent(accion).setPackage(contexto.getPackageName()).putExtra("tel", tel);
          avisos.add(PendingIntent.getBroadcast(
              contexto, contador.incrementAndGet(), aviso,
              PendingIntent.FLAG_ONE_SHOT | PendingIntent.FLAG_IMMUTABLE));
        }
        pendientes.put(tel, partes.size());
        sms.sendMultipartTextMessage(tel, null, partes, avisos, null);
        despachados[0]++;
        Log.i(TAG, "SMS despachado a " + tel + " (" + partes.size() + " partes)");
      } catch (Exception e) {
        Log.e(TAG, "Error enviando SMS a " + tel, e);
        pendientes.remove(tel);
        fallidos.add(tel);
      }
    }

    if (pendientes.isEmpty()) {
      try { contexto.unregisterReceiver(receptor); } catch (Exception ignored) {}
      responder.run();
      return;
    }
    principal.postDelayed(() -> {
      try { contexto.unregisterReceiver(receptor); } catch (Exception ignored) {}
      responder.run();
    }, ESPERA_CONFIRMACION_MS);
  }

  /** SIM predeterminada para SMS; si no hay ("preguntar siempre"), la primera activa. */
  private SmsManager obtenerSmsManager() {
    int subId = SubscriptionManager.getDefaultSmsSubscriptionId();
    if (subId == SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
      try {
        SubscriptionManager sm = contexto.getSystemService(SubscriptionManager.class);
        List<SubscriptionInfo> activas = sm != null ? sm.getActiveSubscriptionInfoList() : null;
        if (activas != null && !activas.isEmpty()) subId = activas.get(0).getSubscriptionId();
      } catch (SecurityException e) {
        Log.w(TAG, "Sin READ_PHONE_STATE para elegir SIM", e);
      }
    }
    if (Build.VERSION.SDK_INT >= 31) {
      SmsManager base = contexto.getSystemService(SmsManager.class);
      return subId != SubscriptionManager.INVALID_SUBSCRIPTION_ID
          ? base.createForSubscriptionId(subId)
          : base;
    }
    return subId != SubscriptionManager.INVALID_SUBSCRIPTION_ID
        ? SmsManager.getSmsManagerForSubscriptionId(subId)
        : SmsManager.getDefault();
  }

  // ===================== ABRIR ALARMA =====================

  /**
   * Abre MainActivity con el mismo intent que la notificación de alarma.
   * Android solo lo permite desde segundo plano con "Mostrar sobre otras apps".
   */
  private boolean abrirAlarma() {
    try {
      Intent intent = contexto.getPackageManager().getLaunchIntentForPackage(contexto.getPackageName());
      if (intent == null) return false;
      intent.setAction("SELECT_NOTIFICATION");
      intent.putExtra("payload", "alarma_activa");
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
      contexto.startActivity(intent);
      return true;
    } catch (Exception e) {
      Log.w(TAG, "No se pudo abrir la alarma", e);
      return false;
    }
  }

  private Map<String, Boolean> puedeAbrirSobreBloqueo() {
    Map<String, Boolean> r = new HashMap<>();
    boolean pantallaCompleta = true;
    if (Build.VERSION.SDK_INT >= 34) {
      NotificationManager nm = contexto.getSystemService(NotificationManager.class);
      pantallaCompleta = nm != null && nm.canUseFullScreenIntent();
    }
    r.put("pantallaCompleta", pantallaCompleta);
    r.put("superponer", Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(contexto));
    return r;
  }
}
