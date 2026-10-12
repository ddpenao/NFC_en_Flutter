// Punto de entrada de la app NFC Demo.
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const NfcDemoApp());
}

class NfcDemoApp extends StatelessWidget {
  const NfcDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NFC Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF7C3AED), // morado, color del tema NFC
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
