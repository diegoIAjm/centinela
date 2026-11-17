package com.example.centinela_nativo;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import org.json.JSONObject;
import org.vosk.Model;
import org.vosk.Recognizer;
import java.io.*;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/** Un motor por FlutterEngine; la exclusión global evita dos capturas en la app.
 * Audio transitorio en RAM, sin escribir conversaciones ni hacer peticiones de
 * reconocimiento. Internet se usa únicamente al instalar el modelo español.
 */
final class VozLocal {
  private static final String MODELO = "vosk-model-small-es-0.42";
  private static final String MODELO_URL = "https://alphacephei.com/vosk/models/" + MODELO + ".zip";
  private static final Object INSTALACION = new Object();
  private static final Object MICROFONO = new Object();
  private static VozLocal propietario;
  private final Context context;
  private final MethodChannel canal;
  private final Handler main = new Handler(Looper.getMainLooper());
  private final ExecutorService comandos = Executors.newSingleThreadExecutor();
  private final ExecutorService descargas = Executors.newSingleThreadExecutor();
  private volatile boolean cerrado;
  private volatile boolean escuchando;
  private volatile int generacion;
  private Model modelo;
  private Recognizer reconocedor;
  private AudioRecord grabador;
  private Thread captura;
  private android.media.AudioManager.AudioRecordingCallback cambioAudio;
  private PowerManager.WakeLock despierto;

  VozLocal(Context context, BinaryMessenger messenger) {
    this.context = context;
    canal = new MethodChannel(messenger, "centinela_voz");
    canal.setMethodCallHandler((call, result) -> {
      switch (call.method) {
        case "modeloDisponible": result.success(modeloDisponible()); break;
        case "descargarModelo":
          ejecutar(descargas, result, () -> { instalarModelo(); return null; }); break;
        case "iniciar":
          ejecutar(comandos, result, () -> { iniciar(); return null; }); break;
        case "detener":
          ejecutar(comandos, result, () -> { detener(); return null; }); break;
        case "mantenerServicio":
          final boolean mantener = Boolean.TRUE.equals(call.arguments);
          ejecutar(comandos, result, () -> { mantenerServicio(mantener); return null; }); break;
        default: result.notImplemented();
      }
    });
  }

  private interface Accion { Object run() throws Exception; }
  private void ejecutar(ExecutorService executor, MethodChannel.Result result, Accion accion) {
    if (cerrado) { result.error("CERRADO", "Motor desconectado", null); return; }
    executor.execute(() -> {
      try {
        if (cerrado) throw new IOException("Motor desconectado");
        Object valor = accion.run();
        main.post(() -> result.success(valor));
      } catch (Exception | LinkageError e) {
        main.post(() -> result.error("VOZ_LOCAL", e.getMessage(), null));
      }
    });
  }

  private File raizModelo() { return new File(context.getFilesDir(), "voz_modelo/" + MODELO); }
  private boolean modeloDisponible() {
    File raiz = raizModelo();
    return new File(raiz, ".instalado").isFile() &&
        new File(raiz, "am/final.mdl").isFile() && new File(raiz, "conf/model.conf").isFile();
  }

  private void instalarModelo() throws Exception {
    synchronized (INSTALACION) {
      if (modeloDisponible()) return;
      File temporal = new File(context.getCacheDir(), "voz_descarga");
      borrar(temporal);
      if (!temporal.mkdirs()) throw new IOException("No se pudo crear el directorio temporal");
      HttpURLConnection conexion = null;
      try {
        conexion = (HttpURLConnection) new URL(MODELO_URL).openConnection();
        conexion.setConnectTimeout(20000);
        conexion.setReadTimeout(30000);
        conexion.setInstanceFollowRedirects(false);
        if (conexion.getResponseCode() != 200) throw new IOException("No se pudo descargar el modelo: HTTP " + conexion.getResponseCode());
        long total = 0;
        int archivos = 0;
        long limiteTiempo = android.os.SystemClock.elapsedRealtime() + 600000;
        String prefijo = temporal.getCanonicalPath() + File.separator;
        try (ZipInputStream zip = new ZipInputStream(new BufferedInputStream(conexion.getInputStream()))) {
          ZipEntry entrada;
          byte[] buffer = new byte[32768];
          while ((entrada = zip.getNextEntry()) != null) {
            if (cerrado || android.os.SystemClock.elapsedRealtime() > limiteTiempo) throw new IOException("Descarga cancelada o agotó el tiempo");
            if (++archivos > 2000 || !entrada.getName().startsWith(MODELO + "/")) throw new IOException("Archivo de modelo no válido");
            File destino = new File(temporal, entrada.getName());
            if (!destino.getCanonicalPath().startsWith(prefijo)) throw new IOException("Ruta de archivo no válida");
            if (entrada.isDirectory()) {
              if (!destino.isDirectory() && !destino.mkdirs()) throw new IOException("No se pudo extraer el modelo");
            } else {
              File padre = destino.getParentFile();
              if (padre == null || (!padre.isDirectory() && !padre.mkdirs())) throw new IOException("No se pudo extraer el modelo");
              try (OutputStream out = new FileOutputStream(destino)) {
                int n;
                while ((n = zip.read(buffer)) != -1) {
                  total += n;
                  if (total > 250L * 1024 * 1024 || cerrado || android.os.SystemClock.elapsedRealtime() > limiteTiempo) throw new IOException("Modelo demasiado grande o descarga interrumpida");
                  out.write(buffer, 0, n);
                }
              }
            }
            zip.closeEntry();
          }
        }
        File extraido = new File(temporal, MODELO);
        if (!new File(extraido, "am/final.mdl").isFile() || !new File(extraido, "conf/model.conf").isFile()) throw new IOException("El modelo descargado está incompleto");
        // Abrirlo valida el contenido antes de publicar la instalación.
        Model comprobacion = new Model(extraido.getAbsolutePath());
        comprobacion.close();
        File raiz = raizModelo();
        if (!raiz.getParentFile().isDirectory() && !raiz.getParentFile().mkdirs()) throw new IOException("No se pudo guardar el modelo");
        borrar(raiz);
        // Cache y files pueden residir en montajes distintos: copiar en lugar de rename.
        copiar(extraido, raiz);
        if (!new File(raiz, ".instalado").createNewFile()) throw new IOException("No se pudo finalizar la instalación");
      } finally {
        if (conexion != null) conexion.disconnect();
        borrar(temporal);
      }
    }
  }

  private void iniciar() throws Exception {
    if (escuchando) return;
    if (android.os.Build.VERSION.SDK_INT >= 23 && context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) throw new IOException("Concede el permiso de micrófono");
    if (!modeloDisponible()) throw new IOException("Descarga primero el modelo español en Protección por voz");
    synchronized (MICROFONO) {
      if (propietario != null && propietario != this) throw new IOException("La escucha por voz ya está en uso");
      propietario = this;
    }
    try {
      modelo = new Model(raizModelo().getAbsolutePath());
      reconocedor = new Recognizer(modelo, 16000f);
      // Texto libre, no gramática forzada: evita forzar sonidos ajenos a una frase de auxilio.
      int minimo = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
      if (minimo <= 0) throw new IOException("El micrófono no admite audio de 16 kHz");
      grabador = new AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000,
          AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, Math.max(minimo, 8192));
      if (grabador.getState() != AudioRecord.STATE_INITIALIZED) throw new IOException("No se pudo abrir el micrófono");
      grabador.startRecording();
      if (grabador.getRecordingState() != AudioRecord.RECORDSTATE_RECORDING) throw new IOException("El micrófono está ocupado");
      escuchando = true;
      final int sesion = ++generacion;
      if (android.os.Build.VERSION.SDK_INT >= 29) {
        cambioAudio = new android.media.AudioManager.AudioRecordingCallback() {
          @Override public void onRecordingConfigChanged(java.util.List<android.media.AudioRecordingConfiguration> configs) {
            for (android.media.AudioRecordingConfiguration c : configs) {
              if (grabador != null && c.getClientAudioSessionId() == grabador.getAudioSessionId() && c.isClientSilenced()) {
                evento("error", "Android silenció el micrófono. Revisa otras apps y vuelve a activar la voz.", sesion);
              }
            }
          }
        };
        grabador.registerAudioRecordingCallback(r -> main.post(r), cambioAudio);
      }
      captura = new Thread(() -> capturar(sesion), "centinela-voz");
      captura.start();
    } catch (Exception | LinkageError e) {
      detener();
      throw e;
    }
  }

  private void capturar(int sesion) {
    try {
      short[] pcm = new short[3200];
      while (escuchando && sesion == generacion) {
        int n = grabador.read(pcm, 0, pcm.length);
        if (!escuchando) break;
        if (n < 0) throw new IOException("Se interrumpió la captura del micrófono (" + n + ")");
        if (n > 0 && reconocedor.acceptWaveForm(pcm, n)) {
          String texto = new JSONObject(reconocedor.getResult()).optString("text");
          if (!texto.isEmpty()) evento("texto", texto, sesion);
        }
      }
    } catch (Exception | LinkageError e) {
      if (escuchando) evento("error", "Se interrumpió la escucha: " + e.getMessage(), sesion);
    }
  }

  private void evento(String tipo, String valor, int sesion) {
    main.post(() -> {
      if (cerrado || !escuchando || sesion != generacion) return;
      Map<String, Object> datos = new HashMap<>();
      datos.put("tipo", tipo);
      datos.put(tipo.equals("texto") ? "texto" : "mensaje", valor);
      canal.invokeMethod("evento", datos);
    });
  }

  private void detener() throws Exception {
    escuchando = false;
    ++generacion;
    if (grabador != null && cambioAudio != null && android.os.Build.VERSION.SDK_INT >= 29) {
      grabador.unregisterAudioRecordingCallback(cambioAudio);
      cambioAudio = null;
    }
    if (grabador != null && grabador.getRecordingState() == AudioRecord.RECORDSTATE_RECORDING) grabador.stop();
    if (captura != null) {
      captura.join(5000);
      if (captura.isAlive()) throw new IOException("El micrófono aún se está liberando. Reinicia la protección.");
      captura = null;
    }
    if (grabador != null) { grabador.release(); grabador = null; }
    if (reconocedor != null) { reconocedor.close(); reconocedor = null; }
    if (modelo != null) { modelo.close(); modelo = null; }
    synchronized (MICROFONO) { if (propietario == this) propietario = null; }
  }

  private void mantenerServicio(boolean mantener) {
    if (mantener && despierto == null) {
      PowerManager power = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
      despierto = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "centinela:horario-voz");
      despierto.setReferenceCounted(false);
      despierto.acquire(); // Solo mientras el usuario mantiene armada la protección por voz.
    } else if (!mantener && despierto != null) {
      if (despierto.isHeld()) despierto.release();
      despierto = null;
    }
  }

  void cerrar() {
    cerrado = true;
    canal.setMethodCallHandler(null);
    comandos.execute(() -> {
      try { detener(); } catch (Exception ignored) { }
      finally { mantenerServicio(false); }
    });
    comandos.shutdown();
    descargas.shutdown();
  }

  private static void borrar(File f) throws IOException {
    if (!f.exists()) return;
    if (f.isDirectory()) {
      File[] hijos = f.listFiles();
      if (hijos == null) throw new IOException("No se pudo leer " + f.getName());
      for (File h : hijos) borrar(h);
    }
    if (!f.delete()) throw new IOException("No se pudo limpiar " + f.getName());
  }
  private static void copiar(File origen, File destino) throws IOException {
    if (origen.isDirectory()) {
      if (!destino.isDirectory() && !destino.mkdirs()) throw new IOException("No se pudo crear " + destino.getName());
      File[] hijos = origen.listFiles();
      if (hijos == null) throw new IOException("Modelo ilegible");
      for (File h : hijos) copiar(h, new File(destino, h.getName()));
    } else {
      try (InputStream in = new FileInputStream(origen); OutputStream out = new FileOutputStream(destino)) {
        byte[] buffer = new byte[32768]; int n;
        while ((n = in.read(buffer)) != -1) out.write(buffer, 0, n);
      }
    }
  }
}
