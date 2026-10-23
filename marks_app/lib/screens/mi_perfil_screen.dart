import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/usuario.dart';
import '../services/api_service.dart';
import '../services/carrito_service.dart';
import '../services/cuenta_service.dart';
import '../theme/colores.dart';
import '../utils/mis_datos_texto.dart';
import '../widgets/campos_registro.dart' show fechaLarga;
import '../widgets/soft_ui.dart';
import 'aviso_privacidad_screen.dart';
import 'bienvenida_screen.dart';
import 'cambiar_password_screen.dart';
import 'editar_perfil_screen.dart';
import 'eliminar_cuenta_screen.dart';

/// Mi perfil (PASO 14): mis datos, seguridad y privacidad.
class MiPerfilScreen extends StatefulWidget {
  final Usuario usuario;

  const MiPerfilScreen({super.key, required this.usuario});

  @override
  State<MiPerfilScreen> createState() => _MiPerfilScreenState();
}

class _MiPerfilScreenState extends State<MiPerfilScreen> {
  late Usuario _usuario = widget.usuario;
  bool _ocupado = false; // descargando datos o cerrando sesiones

  static const Map<String, String> _sexos = {
    'F': 'Femenino',
    'M': 'Masculino',
    'N': 'Prefiero no decirlo',
  };

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  /// El usuario del Inicio puede venir sin el perfil completo: se pide a la API.
  Future<void> _recargar() async {
    try {
      final perfil = await CuentaService.miPerfil();
      if (mounted) setState(() => _usuario = perfil);
    } on ApiException {
      // Sin conexión: se muestran los datos que ya había
    }
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Cambiar contraseña: al terminar muestra el mensaje de la API.
  Future<void> _cambiarPassword() async {
    final mensaje = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => CambiarPasswordScreen(correo: _usuario.correo)),
    );
    if (mensaje != null) _aviso(mensaje);
  }

  /// Eliminar mi cuenta: si se elimina, esa pantalla manda a la bienvenida.
  void _eliminarCuenta() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EliminarCuentaScreen(puntos: _usuario.puntos)),
    );
  }

  // ------------------------------------------------------------------
  // Acciones
  // ------------------------------------------------------------------

  Future<void> _editarDatos() async {
    final actualizado = await Navigator.of(context).push<Usuario>(
      MaterialPageRoute(builder: (_) => EditarPerfilScreen(usuario: _usuario)),
    );
    if (actualizado != null && mounted) {
      setState(() => _usuario = actualizado);
      _aviso('Tus datos se actualizaron');
    }
  }

  void _verAviso() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AvisoPrivacidadScreen()),
    );
  }

   /// Crea 2 archivos y abre el menú "Compartir" del celular:
  ///  - mis_datos_marks.txt: fácil de leer, se abre en cualquier celular
  ///  - mis_datos_marks.json: los mismos datos en formato de datos (portabilidad)
  Future<void> _descargarDatos() async {
    setState(() => _ocupado = true);
    try {
      final datos = await CuentaService.exportarDatos();
      // Carpeta temporal de la app: el sistema la limpia solo
      final carpeta = await getTemporaryDirectory();
      final archivoTexto = File('${carpeta.path}/mis_datos_marks.txt');
      await archivoTexto.writeAsString(misDatosComoTexto(datos), flush: true);
      final archivoJson = File('${carpeta.path}/mis_datos_marks.json');
      await archivoJson.writeAsString(
        const JsonEncoder.withIndent('  ').convert(datos),
        flush: true,
      );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(archivoTexto.path, mimeType: 'text/plain'),
            XFile(archivoJson.path, mimeType: 'application/json'),
          ],
          // Sin "text": WhatsApp descarta los archivos si va texto junto con varios
          subject: 'Mis datos de MARK\'S', // solo lo usan las apps de correo
        ),
      );
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    } on FileSystemException {
      _aviso('No se pudo crear el archivo. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Cierra la sesión en todos los dispositivos (también en este) y regresa a la bienvenida.
  Future<void> _cerrarSesiones() async {
    final confirmar = await mostrarConfirmacion(
      context,
      titulo: '¿Cerrar sesión en todos lados?',
      mensaje: 'Se cerrará tu sesión en este celular y en cualquier otro dispositivo o '
          'navegador donde hayas entrado. Úsalo si perdiste tu celular o crees que '
          'alguien más usa tu cuenta.',
      textoConfirmar: 'Sí, cerrar',
      icono: PhosphorIconsLight.devices,
      peligro: true,
    );
    if (!confirmar || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await CuentaService.cerrarSesionesEnTodos();
      await CarritoService.instancia.vaciar(); // que la siguiente persona no vea el carrito
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const BienvenidaScreen()),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _ocupado = false);
      _aviso(e.mensaje);
    }
  }

  // ------------------------------------------------------------------
  // Pantalla
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final u = _usuario;
    return Scaffold(
      backgroundColor: MarksColores.fondo,
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              color: MarksColores.verde,
              onRefresh: _recargar,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  // Encabezado
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Regresar',
                        icon: const Icon(PhosphorIconsLight.arrowLeft, color: MarksColores.azul),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Text(
                        'Mi perfil',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: MarksColores.azul,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Tarjeta con nombre y correo
                  TarjetaSuave(
                    child: Row(
                      children: [
                        const IconoCirculo(icono: PhosphorIconsLight.userCircle, tamano: 56),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                u.nombreCompleto,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: MarksColores.azul,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                u.correo,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: MarksColores.textoSuave,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Mis datos
                  const _Titulo('Mis datos'),
                  TarjetaSuave(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
                    child: Column(
                      children: [
                        _Dato(etiqueta: 'Nombre', valor: u.nombre),
                        _Dato(etiqueta: 'Apellidos', valor: u.apellidos ?? 'Sin capturar'),
                        _Dato(etiqueta: 'Teléfono', valor: u.telefono ?? 'Sin capturar'),
                        _Dato(
                          etiqueta: 'Fecha de nacimiento',
                          valor: u.fechaNacimiento == null
                              ? 'Sin capturar'
                              : fechaLarga(u.fechaNacimiento!),
                        ),
                        _Dato(etiqueta: 'Sexo', valor: _sexos[u.sexo] ?? 'Sin capturar'),
                        _Dato(etiqueta: 'Correo', valor: u.correo, ultimo: true),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _ocupado ? null : _editarDatos,
                            icon: const Icon(PhosphorIconsLight.pencilSimple, size: 18),
                            label: const Text('Editar mis datos'),
                            style: TextButton.styleFrom(foregroundColor: MarksColores.verdeOscuro),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(6, 8, 6, 0),
                    child: Text(
                      'El correo no se puede cambiar porque es con el que inicias sesión.',
                      style: TextStyle(fontSize: 12, color: MarksColores.textoSuave),
                    ),
                  ),

                  // Seguridad
                  const _Titulo('Seguridad'),
                  _Opcion(
                    icono: PhosphorIconsLight.lockKey,
                    titulo: 'Cambiar contraseña',
                    onTap: _ocupado ? null : _cambiarPassword,
                  ),
                  _Opcion(
                    icono: PhosphorIconsLight.devices,
                    titulo: 'Cerrar sesión en todos mis dispositivos',
                    onTap: _ocupado ? null : _cerrarSesiones,
                  ),

                  // Privacidad
                  const _Titulo('Privacidad'),
                  _Opcion(
                    icono: PhosphorIconsLight.shieldCheck,
                    titulo: 'Aviso de Privacidad',
                    subtitulo: u.avisoVigente == null ? null : 'Versión ${u.avisoVigente}',
                    onTap: _ocupado ? null : _verAviso,
                  ),
                  _Opcion(
                    icono: PhosphorIconsLight.downloadSimple,
                    titulo: 'Descargar mis datos',
                    subtitulo: 'Perfil, compras, puntos y opiniones',
                    onTap: _ocupado ? null : _descargarDatos,
                  ),
                  _Opcion(
                    icono: PhosphorIconsLight.trash,
                    titulo: 'Eliminar mi cuenta',
                    peligro: true,
                    onTap: _ocupado ? null : _eliminarCuenta,
                  ),
                ],
              ),
            ),

            // Cargando (descargar datos / cerrar sesiones)
            if (_ocupado)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x33FFFFFF),
                  child: Center(child: CircularProgressIndicator(color: MarksColores.verde)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  final String texto;

  const _Titulo(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 24, 6, 10),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: MarksColores.azul,
        ),
      ),
    );
  }
}

/// Renglón "Etiqueta ........ valor" de Mis datos.
class _Dato extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final bool ultimo;

  const _Dato({required this.etiqueta, required this.valor, this.ultimo = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: ultimo ? null : const Border(bottom: BorderSide(color: MarksColores.borde)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiqueta,
            style: const TextStyle(fontSize: 13.5, color: MarksColores.textoSuave),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: MarksColores.azul,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opción tocable con ícono, título y flecha.
class _Opcion extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final VoidCallback? onTap;
  final bool peligro;

  const _Opcion({
    required this.icono,
    required this.titulo,
    this.subtitulo,
    this.onTap,
    this.peligro = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = peligro ? MarksColores.error : MarksColores.azul;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TarjetaSuave(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        onTap: onTap,
        child: Row(
          children: [
            IconoCirculo(
              icono: icono,
              color: peligro ? MarksColores.error : MarksColores.verde,
              tamano: 42,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color),
                  ),
                  if (subtitulo != null)
                    Text(
                      subtitulo!,
                      style: const TextStyle(fontSize: 12.5, color: MarksColores.textoSuave),
                    ),
                ],
              ),
            ),
            Icon(PhosphorIconsLight.caretRight, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}