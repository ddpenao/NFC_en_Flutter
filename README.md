# 📶 NFC Demo · Flutter

App de ejemplo del video tutorial **"Funcionalidades nativas con Flutter: NFC"** — Programación Móvil (SS603).

Lee y escribe tags NFC (texto y URL) en **Android** e **iOS** con `nfc_manager`, y en **Web** (Chrome Android) con la API Web NFC.

| | |
|---|---|
| 🎥 Video | _pegar enlace de YouTube (No listado)_ |
| 👥 Integrantes | _Nombre 1_ · _Nombre 2_ — Grupo _0X_ |

---

## ✨ Funcionalidades

- Verifica el estado del NFC: **activo**, **apagado**, **no soportado** o **web**.
- **Lee** un tag: UID, registros NDEF (texto/URL), capacidad y si es escribible.
- **Escribe** texto o una URL, validando que el tag no esté bloqueado y que el mensaje quepa.
- **Modo tag (emulación de tarjeta, HCE):** un segundo Android se convierte en un tag NFC que el primero puede leer y escribir. Sirve si no tienes tags físicos.
- Maneja los casos negativos:
  - NFC apagado → aviso + re-verificación automática al volver de Ajustes.
  - Sin chip / emulador → botones deshabilitados.
  - iOS: el usuario **cancela** la ventana de escaneo.
  - Web: el usuario **niega** el permiso `nfc` del navegador (`NotAllowedError`).

## 📦 Paquetes

| Paquete | Versión | Para qué |
|---|---|---|
| [`nfc_manager`](https://pub.dev/packages/nfc_manager) | ^4.1.0 | Sesión NFC en Android/iOS |
| [`nfc_manager_ndef`](https://pub.dev/packages/nfc_manager_ndef) | ^1.1.0 | Leer/escribir mensajes NDEF |
| `dart:js_interop` | (incluido en Dart) | API Web NFC del navegador |

> ⚠️ La v3 de `nfc_manager` tiene otra API. Muchos tutoriales viejos usan la v3; este proyecto usa la **v4**.

## 🗂️ Estructura

```
lib/
├── main.dart                    # Punto de entrada
├── screens/
│   ├── home_screen.dart         # UI: estado, leer, escribir, historial
│   └── tag_mode_screen.dart     # Modo tag: el celular se vuelve un tag
├── services/
│   ├── nfc_service.dart         # Android/iOS con nfc_manager
│   ├── hce_service.dart         # MethodChannel hacia el servicio HCE
│   ├── web_nfc.dart             # Importación condicional
│   ├── web_nfc_web.dart         # Web NFC (NDEFReader) con js_interop
│   └── web_nfc_stub.dart        # Vacío para móvil
└── utils/ndef_utils.dart        # Crear y describir registros NDEF
android/app/src/main/
├── AndroidManifest.xml          # Permiso NFC + servicio HCE (ya listo)
├── kotlin/co/edu/ss603/nfc_demo/
│   ├── MainActivity.kt          # MethodChannel "nfc_demo/hce"
│   └── NdefHceService.kt        # Emula un NFC Forum Type 4 Tag
└── res/xml/apduservice.xml      # AID de la aplicación NDEF
config/                          # Fragmentos de permisos (referencia y iOS)
test/ndef_utils_test.dart        # Pruebas unitarias
```

## 🚀 Cómo ejecutarlo

Requisitos: Flutter estable reciente (Dart ≥ 3.6; si `pub get` pide una versión mayor, ejecuta `flutter upgrade`), un **celular físico con NFC** y un tag NTAG213/215/216 **o un segundo Android con NFC** (Modo tag).

```bash
# 1. Crear lo que falta de las carpetas de plataforma (android, ios, web).
#    No sobrescribe los archivos que ya trae el proyecto (manifest, Kotlin).
flutter create --org co.edu.ss603 --platforms android,ios,web .

# 2. Instalar dependencias
flutter pub get

# 3. Configurar permisos (ver sección siguiente)

# 4. Ejecutar en el celular conectado por USB
flutter run

# Pruebas unitarias
flutter test
```

## 🔐 Permisos por plataforma

### 🤖 Android — `android/app/src/main/AndroidManifest.xml`

El proyecto ya trae el manifiesto configurado. Las líneas clave son:

```xml
<uses-permission android:name="android.permission.NFC" />
<uses-feature android:name="android.hardware.nfc" android:required="false" />
```

- `NFC` es un permiso **normal**: se concede al instalar, sin diálogo.
- El "permiso negado" equivalente en Android es que el usuario **tenga el NFC apagado**; la app lo detecta con `checkAvailability()`.
- `minSdk` mínimo del plugin: **24** (Android 7.0).

### 🍎 iOS — `ios/Runner/Info.plist` + capability

1. Xcode → *Runner* → **Signing & Capabilities** → **+ Capability** → **Near Field Communication Tag Reading** (crea `Runner.entitlements`, ver `config/ios/`).
2. En `Info.plist` (ver `config/ios/Info_plist_fragmento.xml`):
   ```xml
   <key>NFCReaderUsageDescription</key>
   <string>Usamos NFC para leer y escribir información en tags y stickers.</string>
   ```
- Requiere **iPhone 7+** (escritura XS/XR+), iOS 13+ y **cuenta Apple Developer paga**.
- iOS muestra su propia ventana de escaneo; si el usuario la cancela, llega `readerSessionInvalidationErrorUserCanceled`.

### 🌐 Web — API Web NFC

- `nfc_manager` **no soporta web**; usamos `NDEFReader` vía `dart:js_interop`.
- Solo **Chrome para Android**, con **HTTPS** y tras un toque del usuario.
- El navegador pide permiso la primera vez → si se niega, `scan()` falla con `NotAllowedError`.
- No funciona en iPhone (Safari), Firefox ni Chrome de computador.

Para probarlo en el celular con HTTPS:

```bash
flutter build web --base-href /NOMBRE_REPO/
# Subir build/web a GitHub Pages (rama gh-pages) y abrir el enlace en Chrome Android
```

## 📱📱 Modo tag: probar sin tags físicos

Android permite que una app **emule una tarjeta NFC** (Host Card Emulation). La app trae un servicio (`NdefHceService.kt`) que responde como un **NFC Forum Type 4 Tag**, el formato que Android e iOS leen como NDEF. Se puede leer y también escribir.

1. Instala la app en **dos Android con NFC encendido**.
2. **Celular A:** pulsa **Modo tag** (arriba a la derecha), escribe un mensaje y pulsa **Activar tag**. Deja la pantalla encendida.
3. **Celular B:** en la pantalla principal pulsa **Leer tag** y pega los celulares **espalda con espalda** (sin fundas), moviéndolos despacio hasta que vibre.
4. Para escribir: en B pulsa **Escribir texto**; el celular A muestra el nuevo contenido en vivo.

Notas:
- El UID cambia en cada lectura: los celulares usan un UID aleatorio al emular.
- Si no se detectan, cambien quién emula y quién lee; la antena no está en el mismo sitio en todos los modelos (suele estar en el centro o cerca de la cámara).
- En A, cierra el Modo tag al terminar para que el celular vuelva a leer tags normalmente.

## 🧯 Problemas comunes

| Problema | Solución |
|---|---|
| `NFC no disponible` en emulador | Los emuladores no tienen NFC: usar un celular físico |
| El tag no se detecta | Mantenerlo quieto en el centro trasero; quitar fundas metálicas |
| `Tag sin formato NDEF` | Es una tarjeta bancaria/MIFARE Classic; usar un NTAG |
| `no cabe en el tag` | NTAG213 = 144 bytes; usar un texto más corto |
| Las lecturas siguientes fallan | Siempre llamar `stopSession()` |
| iOS se cierra al escanear | Falta `NFCReaderUsageDescription` en `Info.plist` |
| Error de compilación por `minSdk` | En `android/app/build.gradle.kts` poner `minSdk = 24` |
| Dos celulares no se detectan | Pantallas encendidas, sin fundas, probar otra posición o invertir roles |

## 📚 Referencias

- [nfc_manager en pub.dev](https://pub.dev/packages/nfc_manager)
- [Android · Conceptos básicos de NFC](https://developer.android.com/develop/connectivity/nfc/nfc)
- [Apple · Core NFC](https://developer.apple.com/documentation/corenfc)
- [MDN · Web NFC API](https://developer.mozilla.org/en-US/docs/Web/API/Web_NFC_API)
