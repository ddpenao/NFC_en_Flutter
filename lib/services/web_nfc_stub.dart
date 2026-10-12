// Versión vacía de WebNfc para Android/iOS (nunca se llama allí).
class WebNfc {
  static bool get soportado => false;
  static bool get contextoSeguro => false;

  static Future<String> estadoPermiso() async => 'no aplica';

  static Future<void> escanear({
    required void Function(String serial, List<String> registros) alLeer,
    required void Function(String mensaje) alError,
  }) async {
    alError('Web NFC solo existe en el navegador.');
  }

  static Future<void> escribirTexto(String texto) async {}
}
