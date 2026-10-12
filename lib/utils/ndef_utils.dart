// Utilidades para construir y describir registros NDEF.
//
// NDEF (NFC Data Exchange Format) es el formato estándar que entienden
// Android e iOS. Un MENSAJE NDEF contiene uno o varios REGISTROS, y cada
// registro tiene: un TNF (formato del tipo), un TIPO y un PAYLOAD (datos).
//
// Los dos registros más comunes son de tipo "bien conocido" (wellKnown):
//   'T' (0x54) -> Texto
//   'U' (0x55) -> URI / URL
import 'dart:convert';
import 'dart:typed_data';

import 'package:nfc_manager/ndef_record.dart';

class NdefUtils {
  NdefUtils._();

  /// Prefijos de URI definidos por el NFC Forum. En lugar de guardar
  /// "https://" completo en el tag, se guarda un solo byte (su índice).
  /// Así se ahorra espacio: ¡un NTAG213 solo tiene 144 bytes!
  static const List<String> _prefijosUri = [
    '',
    'http://www.',
    'https://www.',
    'http://',
    'https://',
    'tel:',
    'mailto:',
    'ftp://anonymous:anonymous@',
    'ftp://ftp.',
    'ftps://',
    'sftp://',
    'smb://',
    'nfs://',
    'ftp://',
    'dav://',
    'news:',
    'telnet://',
    'imap:',
    'rtsp://',
    'urn:',
    'pop:',
    'sip:',
    'sips:',
    'tftp:',
    'btspp://',
    'btl2cap://',
    'btgoep://',
    'tcpobex://',
    'irdaobex://',
    'file://',
    'urn:epc:id:',
    'urn:epc:tag:',
    'urn:epc:pat:',
    'urn:epc:raw:',
    'urn:epc:',
    'urn:nfc:',
  ];

  /// Crea un registro de TEXTO.
  /// Payload = [byte de estado] + [código de idioma] + [texto en UTF-8].
  /// El byte de estado lleva la longitud del código de idioma ("es" = 2).
  static NdefRecord texto(String texto, {String idioma = 'es'}) {
    final codigoIdioma = ascii.encode(idioma);
    final cuerpo = utf8.encode(texto);
    return NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: Uint8List.fromList([0x54]), // 'T'
      identifier: Uint8List(0),
      payload:
          Uint8List.fromList([codigoIdioma.length, ...codigoIdioma, ...cuerpo]),
    );
  }

  /// Crea un registro URI (por ejemplo, un enlace a GitHub).
  /// Payload = [índice del prefijo] + [resto de la URL].
  static NdefRecord uri(String url) {
    var indice = 0;
    // Buscamos el prefijo más largo que coincida (empezamos en 1, el 0 es "").
    for (var i = 1; i < _prefijosUri.length; i++) {
      final p = _prefijosUri[i];
      if (url.startsWith(p) && p.length > _prefijosUri[indice].length) {
        indice = i;
      }
    }
    final resto = utf8.encode(url.substring(_prefijosUri[indice].length));
    return NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: Uint8List.fromList([0x55]), // 'U'
      identifier: Uint8List(0),
      payload: Uint8List.fromList([indice, ...resto]),
    );
  }

  /// Convierte un registro leído en un texto legible para mostrar en pantalla.
  static String describir(NdefRecord r) {
    final tipo = String.fromCharCodes(r.type);

    if (r.typeNameFormat == TypeNameFormat.wellKnown &&
        tipo == 'T' &&
        r.payload.isNotEmpty) {
      final estado = r.payload[0];
      final largoIdioma = estado & 0x3F; // bits 0-5
      final esUtf16 = (estado & 0x80) != 0; // bit 7
      final idioma = ascii.decode(r.payload.sublist(1, 1 + largoIdioma),
          allowInvalid: true);
      final datos = r.payload.sublist(1 + largoIdioma);
      final texto = esUtf16
          ? String.fromCharCodes(datos)
          : utf8.decode(datos, allowMalformed: true);
      return '📝 Texto ($idioma): $texto';
    }

    if (r.typeNameFormat == TypeNameFormat.wellKnown &&
        tipo == 'U' &&
        r.payload.isNotEmpty) {
      final indice = r.payload[0];
      final prefijo = indice < _prefijosUri.length ? _prefijosUri[indice] : '';
      return '🔗 URL: $prefijo${utf8.decode(r.payload.sublist(1), allowMalformed: true)}';
    }

    if (r.typeNameFormat == TypeNameFormat.media) {
      return '📦 MIME $tipo (${r.payload.length} bytes)';
    }

    return '❔ ${r.typeNameFormat.name} "$tipo" (${r.payload.length} bytes)';
  }

  /// Convierte bytes a hexadecimal, por ejemplo el UID: 04:A2:3F:...
  static String hex(Uint8List bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
}
