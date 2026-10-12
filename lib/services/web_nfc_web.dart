// Implementación WEB usando la API Web NFC del navegador (NDEFReader).
//
// LIMITACIONES (las explicamos en el video):
//  - Solo funciona en Chrome para Android (versión 89+).
//  - NO funciona en iPhone (Safari), ni en Chrome de computador, ni en Firefox.
//  - Exige HTTPS (contexto seguro) y que el usuario toque un botón.
//  - El navegador PIDE PERMISO la primera vez: el usuario puede negarlo.
//
// Usamos dart:js_interop (viene con Dart, no necesita paquetes extra).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// ---------- Declaraciones de las clases JavaScript que usamos ----------

@JS('NDEFReader')
extension type _NDEFReader._(JSObject _) implements JSObject {
  external factory _NDEFReader();
  external JSPromise<JSAny?> scan();
  external JSPromise<JSAny?> write(JSAny mensaje);
  external set onreading(JSFunction? manejador);
  external set onreadingerror(JSFunction? manejador);
}

extension type _NDEFReadingEvent._(JSObject _) implements JSObject {
  external String get serialNumber;
  external _NDEFMessage get message;
}

extension type _NDEFMessage._(JSObject _) implements JSObject {
  external JSArray<_NDEFRecord> get records;
}

extension type _NDEFRecord._(JSObject _) implements JSObject {
  external String get recordType; // "text", "url", "mime", ...
  external String? get encoding;
  external JSObject? get data; // DataView con los bytes
}

@JS('TextDecoder')
extension type _TextDecoder._(JSObject _) implements JSObject {
  external factory _TextDecoder([String etiqueta]);
  external String decode(JSObject datos);
}

extension type _EstadoPermiso._(JSObject _) implements JSObject {
  external String get state; // "granted" | "denied" | "prompt"
}

@JS('navigator.permissions.query')
external JSPromise<_EstadoPermiso> _consultarPermiso(JSObject descriptor);

@JS('isSecureContext')
external bool get _esContextoSeguro;

// ---------------------- API que usa la app ----------------------

class WebNfc {
  static _NDEFReader? _lector;

  /// ¿El navegador tiene la API Web NFC?
  static bool get soportado => globalContext.has('NDEFReader');

  /// ¿La página se abrió por HTTPS (o localhost)?
  static bool get contextoSeguro => _esContextoSeguro;

  /// Consulta el permiso "nfc" con la Permissions API.
  static Future<String> estadoPermiso() async {
    try {
      final estado = await _consultarPermiso({'name': 'nfc'}.jsify() as JSObject).toDart;
      return estado.state;
    } catch (_) {
      return 'desconocido';
    }
  }

  /// Pide permiso (si hace falta) y empieza a escuchar tags.
  static Future<void> escanear({
    required void Function(String serial, List<String> registros) alLeer,
    required void Function(String mensaje) alError,
  }) async {
    if (!soportado) {
      alError('Este navegador no soporta Web NFC. Usa Chrome en Android.');
      return;
    }
    final lector = _lector ??= _NDEFReader();

    lector.onreading = ((_NDEFReadingEvent evento) {
      final registros = <String>[];
      for (final r in evento.message.records.toDart) {
        final datos = r.data;
        final contenido = datos == null ? '' : _TextDecoder(r.encoding ?? 'utf-8').decode(datos);
        registros.add(switch (r.recordType) {
          'text' => '📝 Texto: $contenido',
          'url' => '🔗 URL: $contenido',
          _ => '❔ ${r.recordType}',
        });
      }
      alLeer(evento.serialNumber, registros.isEmpty ? ['📭 Tag vacío'] : registros);
    }).toJS;

    lector.onreadingerror = ((JSAny? _) {
      alError('No se pudo leer el tag. Intenta de nuevo.');
    }).toJS;

    try {
      // Aquí el navegador muestra el diálogo de PERMISO la primera vez.
      await lector.scan().toDart;
    } catch (e) {
      final texto = e.toString();
      if (texto.contains('NotAllowedError')) {
        alError('🚫 Permiso NFC NEGADO. Actívalo en el candado de la barra de direcciones '
            '> Permisos > NFC.');
      } else if (texto.contains('NotSupportedError')) {
        alError('El NFC del celular está apagado o no existe.');
      } else {
        alError('Error de Web NFC: $texto');
      }
    }
  }

  /// Escribe un texto en el tag (también requiere permiso).
  static Future<void> escribirTexto(String texto) async {
    final lector = _lector ??= _NDEFReader();
    await lector.write(texto.toJS).toDart;
  }
}
