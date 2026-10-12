// Importación condicional:
//  - Compilando para WEB  -> usa web_nfc_web.dart (API Web NFC del navegador)
//  - Android / iOS        -> usa web_nfc_stub.dart (no hace nada)
// Así el código de JavaScript no rompe la compilación móvil.
export 'web_nfc_stub.dart' if (dart.library.js_interop) 'web_nfc_web.dart';
