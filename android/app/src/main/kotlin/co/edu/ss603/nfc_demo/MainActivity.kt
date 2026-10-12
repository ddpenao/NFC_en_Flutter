package co.edu.ss603.nfc_demo

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Actividad principal. Además de Flutter, expone un MethodChannel para que
 * la pantalla "Modo tag" controle el servicio de emulación (NdefHceService).
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nfc_demo/hce")
            .setMethodCallHandler { call, result ->
                val almacen = AlmacenTag(this)
                when (call.method) {
                    // ¿El celular puede emular tarjetas (HCE)?
                    "soportado" -> result.success(
                        packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)
                    )
                    // Guarda el mensaje NDEF y activa el tag emulado.
                    "activar" -> {
                        val bytes = call.argument<ByteArray>("ndef")
                        if (bytes == null) {
                            result.error("sin_datos", "Falta el mensaje NDEF", null)
                        } else {
                            almacen.mensaje = bytes
                            almacen.activo = true
                            result.success(null)
                        }
                    }
                    "desactivar" -> {
                        almacen.activo = false
                        result.success(null)
                    }
                    // Devuelve lo que tiene el tag ahora (puede haberlo escrito el otro celular).
                    "contenido" -> result.success(almacen.mensaje)
                    else -> result.notImplemented()
                }
            }
    }
}
