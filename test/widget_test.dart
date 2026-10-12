// Prueba de humo: la app arranca y muestra el título.
// (En pruebas no hay NFC real, así que el estado será "no disponible".)
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_demo/main.dart';

void main() {
  testWidgets('La app muestra la pantalla principal', (tester) async {
    await tester.pumpWidget(const NfcDemoApp());
    await tester.pumpAndSettle();
    expect(find.text('NFC Demo · Flutter'), findsOneWidget);
    expect(find.text('Leer tag'), findsOneWidget);
  });
}
