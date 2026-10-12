// Pantalla principal: estado del NFC, leer y escribir tags.
//
// Casos que manejamos (y mostramos en la demo):
//  ✅ NFC activo           -> se puede leer y escribir
//  ⛔ NFC apagado          -> aviso + botón "Reintentar" (y se re-verifica al volver de Ajustes)
//  ❌ Sin chip / emulador  -> aviso, botones deshabilitados
//  🚫 Usuario cancela/niega -> iOS: cancela la ventana; Web: niega el permiso
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/hce_service.dart';
import '../services/nfc_service.dart';
import '../services/web_nfc.dart';
import '../utils/ndef_utils.dart';
import 'tag_mode_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _nfc = NfcService();
  final _textoCtrl = TextEditingController(text: 'Hola desde Flutter 👋');

  EstadoNfc? _estado;
  String _permisoWeb = '...';
  final List<_Evento> _historial = [];

  bool get _esIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    // Observamos el ciclo de vida para re-verificar cuando el usuario
    // vuelve de Ajustes después de encender el NFC.
    WidgetsBinding.instance.addObserver(this);
    _verificar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textoCtrl.dispose();
    _nfc.cancelar();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _verificar();
  }

  Future<void> _verificar() async {
    final estado = await _nfc.verificarEstado();
    if (estado == EstadoNfc.web) {
      _permisoWeb = await WebNfc.estadoPermiso();
    }
    if (mounted) setState(() => _estado = estado);
  }

  void _registrar(String titulo, List<String> detalle, {bool error = false}) {
    if (!mounted) return;
    setState(() => _historial.insert(0, _Evento(titulo, detalle, error)));
  }

  // ---------------- Acciones ----------------

  Future<void> _leer() async {
    if (kIsWeb) {
      await WebNfc.escanear(
        alLeer: (serial, registros) => _registrar('Tag leído (Web) · $serial', registros),
        alError: (m) => _registrar('Error', [m], error: true),
      );
      _permisoWeb = await WebNfc.estadoPermiso();
      if (mounted) setState(() {});
      return;
    }

    _mostrarEsperandoTag('Acerca el tag para LEER');
    await _nfc.leer(
      alLeer: (l) {
        _cerrarEsperando();
        _registrar('Tag leído · UID ${l.uid}', [
          ...l.registros,
          if (l.capacidad != null) '💾 Capacidad: ${l.capacidad} bytes',
          if (l.escribible != null) l.escribible! ? '✏️ Se puede escribir' : '🔒 Solo lectura',
        ]);
      },
      alError: (m) {
        _cerrarEsperando();
        _registrar('Error', [m], error: true);
      },
    );
  }

  Future<void> _escribir({required bool comoUrl}) async {
    final valor = _textoCtrl.text.trim();
    if (valor.isEmpty) return;

    if (kIsWeb) {
      try {
        await WebNfc.escribirTexto(valor);
        _registrar('Escrito (Web)', ['📝 $valor']);
      } catch (e) {
        _registrar('Error', ['No se pudo escribir: $e'], error: true);
      }
      return;
    }

    final registro = comoUrl ? NdefUtils.uri(valor) : NdefUtils.texto(valor);
    _mostrarEsperandoTag('Acerca el tag para ESCRIBIR');
    await _nfc.escribir(
      registro: registro,
      alEscribir: () {
        _cerrarEsperando();
        _registrar('Escritura exitosa', [comoUrl ? '🔗 $valor' : '📝 $valor']);
      },
      alError: (m) {
        _cerrarEsperando();
        _registrar('Error', [m], error: true);
      },
    );
  }

  // Android no muestra ninguna ventana del sistema al escanear, así que
  // mostramos la nuestra. iOS ya muestra la suya, por eso ahí no.
  bool _esperandoAbierto = false;

  void _mostrarEsperandoTag(String texto) {
    if (_esIos) return;
    _esperandoAbierto = true;
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.nfc, size: 72),
          const SizedBox(height: 12),
          Text(texto, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Mantenlo quieto en la parte trasera del celular'),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {
              _nfc.cancelar();
              _cerrarEsperando();
              _registrar('Cancelado', ['El usuario canceló el escaneo'], error: true);
            },
            child: const Text('Cancelar'),
          ),
        ]),
      ),
    ).whenComplete(() => _esperandoAbierto = false);
  }

  void _cerrarEsperando() {
    if (_esperandoAbierto && mounted) {
      _esperandoAbierto = false;
      Navigator.of(context).pop();
    }
  }

  // ---------------- Interfaz ----------------

  @override
  Widget build(BuildContext context) {
    final puedeUsar = _estado == EstadoNfc.activo || (_estado == EstadoNfc.web && WebNfc.soportado);

    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC Demo · Flutter'),
        actions: [
          // Modo tag: este celular se convierte en un tag (solo Android).
          if (HceService.plataformaCompatible)
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TagModeScreen()),
              ),
              icon: const Icon(Icons.phonelink_ring),
              label: const Text('Modo tag'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TarjetaEstado(estado: _estado, permisoWeb: _permisoWeb, alReintentar: _verificar),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: puedeUsar ? _leer : null,
            icon: const Icon(Icons.contactless),
            label: const Text('Leer tag'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _textoCtrl,
            decoration: const InputDecoration(
              labelText: 'Texto o URL para escribir',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: puedeUsar ? () => _escribir(comoUrl: false) : null,
                icon: const Icon(Icons.edit),
                label: const Text('Escribir texto'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: puedeUsar && !kIsWeb ? () => _escribir(comoUrl: true) : null,
                icon: const Icon(Icons.link),
                label: const Text('Escribir URL'),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          Text('Historial', style: Theme.of(context).textTheme.titleMedium),
          if (_historial.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Aún no has leído ningún tag.'),
            ),
          ..._historial.map((e) => Card(
                color: e.error ? Theme.of(context).colorScheme.errorContainer : null,
                child: ListTile(
                  leading: Icon(e.error ? Icons.error_outline : Icons.check_circle_outline),
                  title: Text(e.titulo),
                  subtitle: Text(e.detalle.join('\n')),
                ),
              )),
        ],
      ),
    );
  }
}

class _Evento {
  _Evento(this.titulo, this.detalle, this.error);
  final String titulo;
  final List<String> detalle;
  final bool error;
}

/// Tarjeta que muestra el estado del NFC con color e ícono.
class _TarjetaEstado extends StatelessWidget {
  const _TarjetaEstado({required this.estado, required this.permisoWeb, required this.alReintentar});

  final EstadoNfc? estado;
  final String permisoWeb;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    final (IconData icono, Color color, String titulo, String detalle) = switch (estado) {
      null => (Icons.hourglass_empty, Colors.grey, 'Verificando NFC...', ''),
      EstadoNfc.activo => (Icons.nfc, Colors.green, 'NFC activo', 'Listo para leer y escribir tags.'),
      EstadoNfc.apagado => (
          Icons.portable_wifi_off,
          Colors.orange,
          'NFC apagado',
          'Actívalo en Ajustes > Conexiones > NFC y vuelve a la app.'
        ),
      EstadoNfc.noSoportado => (
          Icons.block,
          Colors.red,
          'NFC no disponible',
          'Este dispositivo no tiene chip NFC (los emuladores tampoco).'
        ),
      EstadoNfc.web => WebNfc.soportado
          ? (
              Icons.language,
              Colors.blue,
              'Web NFC disponible',
              'Permiso "nfc": $permisoWeb · HTTPS: ${WebNfc.contextoSeguro ? "sí" : "no"}'
            )
          : (
              Icons.language,
              Colors.red,
              'Web NFC no soportado',
              'Solo funciona en Chrome para Android con HTTPS. No funciona en iPhone ni en PC.'
            ),
    };

    return Card(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(icono, color: color, size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: Theme.of(context).textTheme.titleMedium),
              if (detalle.isNotEmpty) Text(detalle),
            ]),
          ),
          if (estado == EstadoNfc.apagado)
            TextButton(onPressed: alReintentar, child: const Text('Reintentar')),
        ]),
      ),
    );
  }
}
