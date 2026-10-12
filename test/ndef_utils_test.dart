// Pruebas unitarias de NdefUtils (no necesitan celular ni NFC).
// Ejecutar con:  flutter test
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_demo/utils/ndef_utils.dart';

void main() {
  test('Registro de texto se codifica y se describe correctamente', () {
    final r = NdefUtils.texto('Hola NFC');
    expect(String.fromCharCodes(r.type), 'T');
    expect(r.payload[0], 2); // largo de "es"
    expect(NdefUtils.describir(r), '📝 Texto (es): Hola NFC');
  });

  test('Registro URI usa el prefijo https:// abreviado', () {
    final r = NdefUtils.uri('https://github.com');
    expect(r.payload[0], 4); // 4 = "https://"
    expect(NdefUtils.describir(r), '🔗 URL: https://github.com');
  });

  test('Prefijo https://www. tiene prioridad por ser más largo', () {
    final r = NdefUtils.uri('https://www.google.com');
    expect(r.payload[0], 2);
  });
}
