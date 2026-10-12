// "Modo tag": convierte ESTE celular en un tag NFC (emulación de tarjeta, HCE).
//
// Uso en la demo, con dos celulares Android:
//   Celular A -> abre esta pantalla y activa el tag.
//   Celular B -> en la pantalla principal pulsa "Leer tag" o "Escribir" y se
//                pega espalda con espalda con el celular A.
// Si B escribe, este celular muestra el nuevo contenido en vivo.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nfc_manager/ndef_record.dart';

import '../services/hce_service.dart';
import '../utils/ndef_utils.dart';

class TagModeScreen extends StatefulWidget {
  const TagModeScreen({super.key});

  @override
  State<TagModeScreen> createState() => _TagModeScreenState();
}

class _TagModeScreenState extends State<TagModeScreen> {
  final _textoCtrl = TextEditingController(text: 'Soy un tag emulado 📱');

  bool? _soportado;
  bool _activo = false;
  List<String> _contenido = const [];
  Timer? _sondeo;

  @override
  void initState() {
    super.initState();
    HceService.soportado().then((s) {
      if (mounted) setState(() => _soportado = s);
    });
  }

  @override
  void dispose() {
    _sondeo?.cancel();
    // Al salir de la pantalla apagamos el tag para no interferir con lecturas normales.
    if (_activo) HceService.desactivar();
    _textoCtrl.dispose();
    super.dispose();
  }

  Future<void> _alternar() async {
    if (_activo) {
      _sondeo?.cancel();
      await HceService.desactivar();
      setState(() {
        _activo = false;
        _contenido = const [];
      });
      return;
    }

    final mensaje = NdefMessage(records: [NdefUtils.texto(_textoCtrl.text.trim())]);
    await HceService.activar(mensaje);
    setState(() => _activo = true);
    await _refrescar();
    // Cada segundo revisamos si el otro celular escribió algo nuevo.
    _sondeo = Timer.periodic(const Duration(seconds: 1), (_) => _refrescar());
  }

  Future<void> _refrescar() async {
    final mensaje = await HceService.contenido();
    if (!mounted) return;
    setState(() {
      _contenido = mensaje == null ? ['📭 Vacío'] : mensaje.records.map(NdefUtils.describir).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Modo tag (emulación)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_soportado == false)
            Card(
              color: esquema.errorContainer,
              child: const ListTile(
                leading: Icon(Icons.block),
                title: Text('Este celular no puede emular tarjetas'),
                subtitle: Text('Necesita NFC con HCE (Android 4.4+). Solo funciona en Android.'),
              ),
            ),
          Card(
            color: (_activo ? Colors.green : Colors.grey).withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Icon(_activo ? Icons.nfc : Icons.nfc_outlined, size: 96, color: _activo ? Colors.green : Colors.grey),
                const SizedBox(height: 8),
                Text(
                  _activo ? 'Soy un tag NFC' : 'Tag apagado',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  _activo
                      ? 'Deja la pantalla encendida y acerca el otro celular por la espalda.'
                      : 'Escribe el mensaje inicial y activa el tag.',
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _textoCtrl,
            enabled: !_activo,
            decoration: const InputDecoration(
              labelText: 'Mensaje inicial del tag',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _soportado == true ? _alternar : null,
            icon: Icon(_activo ? Icons.stop : Icons.play_arrow),
            label: Text(_activo ? 'Desactivar tag' : 'Activar tag'),
          ),
          if (_activo) ...[
            const SizedBox(height: 24),
            Text('Contenido actual del tag', style: Theme.of(context).textTheme.titleMedium),
            const Text('Se actualiza solo si el otro celular escribe.'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.memory),
                title: Text(_contenido.join('\n')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
