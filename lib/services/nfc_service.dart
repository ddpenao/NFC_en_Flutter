// Servicio NFC para Android e iOS.
//
// Flujo de una lectura (lo explicamos en el video):
//   1. Verificar disponibilidad  -> checkAvailability()
//   2. Abrir la sesión           -> startSession()
//   3. Recibir el tag            -> onDiscovered(tag)
//   4. Leer/escribir NDEF        -> Ndef.from(tag)
//   5. Cerrar la sesión SIEMPRE  -> stopSession()
import 'package:flutter/foundation.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

import '../utils/ndef_utils.dart';

/// Estado del NFC en el dispositivo.
enum EstadoNfc {
  activo, // Hay chip y está encendido
  apagado, // Hay chip pero el usuario lo apagó en Ajustes
  noSoportado, // El celular no tiene chip NFC (o es un emulador)
  web, // Corriendo en navegador: se usa Web NFC (ver web_nfc_web.dart)
}

/// Datos que mostramos en pantalla después de leer un tag.
class LecturaTag {
  const LecturaTag({
    required this.uid,
    required this.registros,
    required this.capacidad,
    required this.escribible,
  });

  final String uid;
  final List<String> registros;
  final int? capacidad;
  final bool? escribible;
}

class NfcService {
  /// Paso 1: ¿el dispositivo tiene NFC y está encendido?
  Future<EstadoNfc> verificarEstado() async {
    // En web NO se puede usar nfc_manager (solo soporta Android/iOS).
    if (kIsWeb) return EstadoNfc.web;

    try {
      final disponibilidad = await NfcManager.instance.checkAvailability();
      return switch (disponibilidad) {
        NfcAvailability.enabled => EstadoNfc.activo,
        NfcAvailability.disabled => EstadoNfc.apagado,
        NfcAvailability.unsupported => EstadoNfc.noSoportado,
      };
    } catch (_) {
      // Escritorio, emulador sin plugin, etc.
      return EstadoNfc.noSoportado;
    }
  }

  /// Pasos 2 a 5: LEER un tag.
  Future<void> leer({
    required void Function(LecturaTag lectura) alLeer,
    required void Function(String mensaje) alError,
  }) async {
    await NfcManager.instance.startSession(
      // ISO 14443 cubre NTAG, MIFARE y la mayoría de stickers/tarjetas.
      pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
      // Texto que iOS muestra en su ventana de escaneo del sistema.
      alertMessageIos: 'Acerca un tag NFC a la parte superior del iPhone',
      // iOS: el usuario puede CANCELAR la ventana (equivale a "negar").
      onSessionErrorIos: (error) => alError(_mensajeErrorIos(error)),
      onDiscovered: (NfcTag tag) async {
        try {
          final ndef = Ndef.from(tag);
          final uid = _leerUid(tag);

          if (ndef == null) {
            // El tag existe pero no usa formato NDEF (ej. tarjeta bancaria).
            alLeer(LecturaTag(
              uid: uid,
              registros: const ['⚠️ Tag sin formato NDEF (no se puede leer su contenido)'],
              capacidad: null,
              escribible: null,
            ));
            await NfcManager.instance.stopSession(alertMessageIos: 'Tag detectado');
            return;
          }

          // cachedMessage = mensaje leído al momento de detectar el tag.
          final mensaje = ndef.cachedMessage;
          final registros = (mensaje == null || mensaje.records.isEmpty)
              ? const ['📭 Tag vacío']
              : mensaje.records.map(NdefUtils.describir).toList();

          alLeer(LecturaTag(
            uid: uid,
            registros: registros,
            capacidad: ndef.maxSize,
            escribible: ndef.isWritable,
          ));
          // Paso 5: cerrar la sesión. Si no se cierra, las siguientes lecturas fallan.
          await NfcManager.instance.stopSession(alertMessageIos: 'Lectura exitosa ✅');
        } catch (e) {
          alError('Error al leer: $e');
          await NfcManager.instance.stopSession(errorMessageIos: 'No se pudo leer el tag');
        }
      },
    );
  }

  /// ESCRIBIR un mensaje NDEF (texto o URL) en el tag.
  Future<void> escribir({
    required NdefRecord registro,
    required void Function() alEscribir,
    required void Function(String mensaje) alError,
  }) async {
    await NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
      alertMessageIos: 'Acerca el tag para ESCRIBIR',
      onSessionErrorIos: (error) => alError(_mensajeErrorIos(error)),
      onDiscovered: (NfcTag tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef == null) {
            throw 'el tag no es compatible con NDEF';
          }
          if (!ndef.isWritable) {
            throw 'el tag es de solo lectura (bloqueado)';
          }

          final mensaje = NdefMessage(records: [registro]);
          // Validamos el tamaño ANTES de escribir.
          if (mensaje.byteLength > ndef.maxSize) {
            throw 'el mensaje (${mensaje.byteLength} B) no cabe en el tag (${ndef.maxSize} B)';
          }

          await ndef.write(message: mensaje);
          alEscribir();
          await NfcManager.instance.stopSession(alertMessageIos: 'Escritura exitosa ✅');
        } catch (e) {
          alError('No se pudo escribir: $e');
          await NfcManager.instance.stopSession(errorMessageIos: 'Error al escribir');
        }
      },
    );
  }

  /// Cancela la sesión (botón "Cancelar" en Android).
  Future<void> cancelar() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {
      // No había sesión abierta: no pasa nada.
    }
  }

  /// El UID (número de serie) se lee con las clases propias de cada plataforma.
  String _leerUid(NfcTag tag) {
    final android = NfcTagAndroid.from(tag);
    if (android != null) return NdefUtils.hex(android.id);
    final mifareIos = MiFareIos.from(tag);
    if (mifareIos != null) return NdefUtils.hex(mifareIos.identifier);
    return 'No disponible';
  }

  /// Traduce los errores de la sesión de iOS a mensajes para el usuario.
  String _mensajeErrorIos(NfcReaderSessionErrorIos error) {
    return switch (error.code) {
      NfcReaderErrorCodeIos.readerSessionInvalidationErrorUserCanceled =>
        'Cancelaste el escaneo. Puedes intentarlo de nuevo cuando quieras.',
      NfcReaderErrorCodeIos.readerSessionInvalidationErrorSessionTimeout =>
        'Se acabó el tiempo (60 s) sin detectar un tag.',
      _ => 'Error de iOS: ${error.message}',
    };
  }
}
