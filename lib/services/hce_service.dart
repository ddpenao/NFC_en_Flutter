// Puente entre Flutter y el servicio nativo de emulación (NdefHceService.kt).
//
// HCE = Host Card Emulation: el celular se comporta como una tarjeta/tag.
// Solo existe en Android, así que lo hablamos con un MethodChannel propio.
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/ndef_record.dart';


class HceService {
  static const _canal = MethodChannel('nfc_demo/hce');

  /// Solo Android tiene HCE disponible para apps.
  static bool get plataformaCompatible => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// ¿El chip NFC de este celular permite emular tarjetas?
  static Future<bool> soportado() async {
    if (!plataformaCompatible) return false;
    try {
      return await _canal.invokeMethod<bool>('soportado') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Activa el tag emulado con este mensaje NDEF.
  static Future<void> activar(NdefMessage mensaje) =>
      _canal.invokeMethod('activar', {'ndef': _codificar(mensaje)});

  static Future<void> desactivar() => _canal.invokeMethod('desactivar');

  /// Lee lo que tiene el tag ahora mismo (el otro celular pudo escribirle).
  static Future<NdefMessage?> contenido() async {
    final bytes = await _canal.invokeMethod<Uint8List>('contenido');
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return _decodificar(bytes);
    } catch (_) {
      return null; // Escritura a medias: se vuelve a leer en el siguiente ciclo.
    }
  }

  // ---------------------------------------------------------------------
  // Codificación NDEF a bytes (y al revés). La hacemos aquí para no
  // depender de la versión del paquete ndef_record que instale pub.
  //
  // Cada registro: [encabezado][largo tipo][largo payload][largo id?]
  //                [tipo][id?][payload]
  // Encabezado: MB=0x80 (primero), ME=0x40 (último), SR=0x10 (payload < 256),
  //             IL=0x08 (tiene id), y los 3 bits bajos = TNF.
  // ---------------------------------------------------------------------

  static Uint8List _codificar(NdefMessage mensaje) {
    final salida = BytesBuilder();
    final registros = mensaje.records;
    for (var i = 0; i < registros.length; i++) {
      final r = registros[i];
      final corto = r.payload.length < 256;
      final conId = r.identifier.isNotEmpty;
      var encabezado = r.typeNameFormat.index & 0x07; // el orden del enum = valor TNF
      if (i == 0) encabezado |= 0x80;
      if (i == registros.length - 1) encabezado |= 0x40;
      if (corto) encabezado |= 0x10;
      if (conId) encabezado |= 0x08;

      salida.addByte(encabezado);
      salida.addByte(r.type.length);
      if (corto) {
        salida.addByte(r.payload.length);
      } else {
        final n = r.payload.length;
        salida.add([(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF]);
      }
      if (conId) salida.addByte(r.identifier.length);
      salida.add(r.type);
      if (conId) salida.add(r.identifier);
      salida.add(r.payload);
    }
    return salida.toBytes();
  }

  static NdefMessage _decodificar(Uint8List b) {
    final registros = <NdefRecord>[];
    var i = 0;
    while (i < b.length) {
      final encabezado = b[i++];
      final tnf = encabezado & 0x07;
      final corto = (encabezado & 0x10) != 0;
      final conId = (encabezado & 0x08) != 0;

      final largoTipo = b[i++];
      int largoPayload;
      if (corto) {
        largoPayload = b[i++];
      } else {
        largoPayload = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
        i += 4;
      }
      final largoId = conId ? b[i++] : 0;

      final tipo = b.sublist(i, i + largoTipo);
      i += largoTipo;
      final id = b.sublist(i, i + largoId);
      i += largoId;
      final payload = b.sublist(i, i + largoPayload);
      i += largoPayload;

      registros.add(NdefRecord(
        typeNameFormat: tnf < TypeNameFormat.values.length ? TypeNameFormat.values[tnf] : TypeNameFormat.unknown,
        type: tipo,
        identifier: id,
        payload: payload,
      ));
      if ((encabezado & 0x40) != 0) break; // ME: último registro
    }
    return NdefMessage(records: registros);
  }
}