package co.edu.ss603.nfc_demo

import android.content.Context
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.util.Base64

/**
 * EMULACIÓN DE TARJETA (HCE): este celular se hace pasar por un tag NFC.
 *
 * Implementa un "NFC Forum Type 4 Tag", el formato que Android e iOS leen
 * como NDEF. El otro celular (el lector) le manda comandos APDU y aquí
 * respondemos como lo haría un tag real:
 *
 *   1. SELECT de la aplicación NDEF (AID D2760000850101)
 *   2. SELECT del archivo CC (E103)  -> READ BINARY: capacidades del tag
 *   3. SELECT del archivo NDEF (E104) -> READ BINARY: el mensaje
 *   4. UPDATE BINARY (si el lector ESCRIBE en el tag)
 *
 * Toda respuesta termina en un "status word": 90 00 = OK, 6A 82 = no encontrado.
 */
class NdefHceService : HostApduService() {

    companion object {
        private val AID_NDEF = byteArrayOf(0xD2.toByte(), 0x76, 0x00, 0x00, 0x85.toByte(), 0x01, 0x01)
        private val FILE_CC = byteArrayOf(0xE1.toByte(), 0x03)
        private val FILE_NDEF = byteArrayOf(0xE1.toByte(), 0x04)

        private val OK = byteArrayOf(0x90.toByte(), 0x00)
        private val NO_ENCONTRADO = byteArrayOf(0x6A, 0x82.toByte())
        private val NO_PERMITIDO = byteArrayOf(0x69, 0x86.toByte())
        private val ERROR = byteArrayOf(0x6F, 0x00)

        /** Tamaño máximo del archivo NDEF (incluye los 2 bytes de longitud). */
        const val MAX_ARCHIVO = 1024

        /** Archivo CC (Capability Container): 15 bytes que describen el tag. */
        private val CC = byteArrayOf(
            0x00, 0x0F,             // largo del CC
            0x20,                   // versión 2.0
            0x00, 0x3B,             // máximo de bytes por lectura (MLe)
            0x00, 0x34,             // máximo de bytes por escritura (MLc)
            0x04, 0x06,             // TLV del archivo NDEF
            0xE1.toByte(), 0x04,    // id del archivo NDEF
            (MAX_ARCHIVO shr 8).toByte(), (MAX_ARCHIVO and 0xFF).toByte(),
            0x00,                   // lectura: libre
            0x00,                   // escritura: libre (00) -> el tag se puede escribir
        )
    }

    private enum class Archivo { NINGUNO, CC, NDEF }

    private var seleccionado = Archivo.NINGUNO
    private var appSeleccionada = false

    override fun processCommandApdu(apdu: ByteArray, extras: Bundle?): ByteArray {
        val almacen = AlmacenTag(this)
        // Si el "Modo tag" está apagado en la app, nos comportamos como si no existiera.
        if (!almacen.activo || apdu.size < 4) return NO_ENCONTRADO

        val ins = apdu[1].toInt() and 0xFF
        val p1 = apdu[2].toInt() and 0xFF
        val p2 = apdu[3].toInt() and 0xFF

        return try {
            when {
                // SELECT por nombre (AID)
                ins == 0xA4 && p1 == 0x04 -> {
                    val lc = apdu[4].toInt() and 0xFF
                    val aid = apdu.copyOfRange(5, 5 + lc)
                    if (aid.contentEquals(AID_NDEF)) {
                        appSeleccionada = true
                        seleccionado = Archivo.NINGUNO
                        OK
                    } else NO_ENCONTRADO
                }

                // SELECT por id de archivo
                ins == 0xA4 && p1 == 0x00 && appSeleccionada -> {
                    val id = apdu.copyOfRange(5, 7)
                    seleccionado = when {
                        id.contentEquals(FILE_CC) -> Archivo.CC
                        id.contentEquals(FILE_NDEF) -> Archivo.NDEF
                        else -> return NO_ENCONTRADO
                    }
                    OK
                }

                // READ BINARY
                ins == 0xB0 -> {
                    val offset = (p1 shl 8) or p2
                    var le = if (apdu.size > 4) apdu[4].toInt() and 0xFF else 0
                    if (le == 0) le = 256
                    val archivo = when (seleccionado) {
                        Archivo.CC -> CC
                        Archivo.NDEF -> almacen.archivoNdef()
                        Archivo.NINGUNO -> return NO_PERMITIDO
                    }
                    if (offset > archivo.size) return ERROR
                    val fin = minOf(offset + le, archivo.size)
                    archivo.copyOfRange(offset, fin) + OK
                }

                // UPDATE BINARY: el otro celular está ESCRIBIENDO en nuestro tag
                ins == 0xD6 && seleccionado == Archivo.NDEF -> {
                    val offset = (p1 shl 8) or p2
                    val lc = apdu[4].toInt() and 0xFF
                    val datos = apdu.copyOfRange(5, 5 + lc)
                    if (offset + lc > MAX_ARCHIVO) return ERROR
                    almacen.escribirEnArchivo(offset, datos)
                    OK
                }

                else -> NO_PERMITIDO
            }
        } catch (e: Exception) {
            ERROR
        }
    }

    override fun onDeactivated(reason: Int) {
        // El lector se alejó: reiniciamos la selección.
        seleccionado = Archivo.NINGUNO
        appSeleccionada = false
    }
}

/**
 * Guarda el contenido del tag emulado en SharedPreferences para que
 * la app Flutter (vía MethodChannel) y el servicio compartan los datos.
 *
 * Se guarda el ARCHIVO NDEF completo tal como lo vería un tag real:
 * [NLEN alto][NLEN bajo][mensaje NDEF...] con tamaño fijo MAX_ARCHIVO.
 */
class AlmacenTag(context: Context) {
    private val prefs = context.getSharedPreferences("nfc_demo_tag", Context.MODE_PRIVATE)

    var activo: Boolean
        get() = prefs.getBoolean("activo", false)
        set(valor) { prefs.edit().putBoolean("activo", valor).commit() }

    /** Archivo crudo de MAX_ARCHIVO bytes. */
    private var crudo: ByteArray
        get() {
            val guardado = Base64.decode(prefs.getString("archivo", "") ?: "", Base64.NO_WRAP)
            val archivo = ByteArray(NdefHceService.MAX_ARCHIVO)
            guardado.copyInto(archivo, 0, 0, minOf(guardado.size, archivo.size))
            return archivo
        }
        set(valor) { prefs.edit().putString("archivo", Base64.encodeToString(valor, Base64.NO_WRAP)).commit() }

    private fun nlen(archivo: ByteArray): Int {
        val n = ((archivo[0].toInt() and 0xFF) shl 8) or (archivo[1].toInt() and 0xFF)
        return minOf(n, archivo.size - 2)
    }

    /** Mensaje NDEF actual (sin los 2 bytes de longitud). */
    var mensaje: ByteArray
        get() {
            val archivo = crudo
            return archivo.copyOfRange(2, 2 + nlen(archivo))
        }
        set(valor) {
            val archivo = ByteArray(NdefHceService.MAX_ARCHIVO)
            val n = minOf(valor.size, archivo.size - 2)
            archivo[0] = (n shr 8).toByte()
            archivo[1] = (n and 0xFF).toByte()
            valor.copyInto(archivo, 2, 0, n)
            crudo = archivo
        }

    /** Lo que devuelve READ BINARY: NLEN + mensaje. */
    fun archivoNdef(): ByteArray {
        val archivo = crudo
        return archivo.copyOfRange(0, 2 + nlen(archivo))
    }

    /**
     * UPDATE BINARY. El lector escribe en este orden (estándar NFC Forum):
     * 1) NLEN = 0, 2) el mensaje desde el byte 2, 3) el NLEN real.
     * Como guardamos el archivo completo, cualquier orden funciona.
     */
    fun escribirEnArchivo(offset: Int, datos: ByteArray) {
        val archivo = crudo
        datos.copyInto(archivo, offset)
        crudo = archivo
    }
}
