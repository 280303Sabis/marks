import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/opinion.dart';
import '../services/api_service.dart';
import '../services/opiniones_service.dart';
import '../theme/colores.dart';
import '../widgets/opiniones_ui.dart';
import '../widgets/soft_ui.dart';

/// Abre la pantalla para calificar un producto (o editar mi opinión).
/// Devuelve true si se guardó o se borró algo (para recargar la pantalla anterior).
Future<bool> abrirOpinar(
  BuildContext context, {
  required int productoId,
  required String nombre,
  Opinion? existente,
}) async {
  final cambio = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => OpinarScreen(productoId: productoId, nombre: nombre, existente: existente),
    ),
  );
  return cambio == true;
}

/// Calificar un producto (PASO 13): estrellas, comentario y hasta 3 fotos.
/// Si [existente] no es null, es para editar esa opinión (y permite borrarla).
class OpinarScreen extends StatefulWidget {
  final int productoId;
  final String nombre;
  final Opinion? existente;

  const OpinarScreen({
    super.key,
    required this.productoId,
    required this.nombre,
    this.existente,
  });

  @override
  State<OpinarScreen> createState() => _OpinarScreenState();
}

class _OpinarScreenState extends State<OpinarScreen> {
  final ImagePicker _selector = ImagePicker();
  late final TextEditingController _comentario =
      TextEditingController(text: widget.existente?.comentario ?? '');
  late int _estrellas = widget.existente?.estrellas ?? 0;

  /// Fotos que ya estaban publicadas y se quedan (solo al editar).
  late final List<FotoOpinion> _conservadas = [...?widget.existente?.fotos];

  /// Fotos nuevas tomadas o elegidas en el celular.
  final List<XFile> _nuevas = [];

  bool _enviando = false;
  String? _error;

  bool get _editando => widget.existente != null;
  int get _totalFotos => _conservadas.length + _nuevas.length;
  int get _restantes => OpinionesService.maxFotos - _totalFotos;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  void _aviso(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  // ------------------------------------------------------------------
  // Fotos
  // ------------------------------------------------------------------

  /// Pregunta si la foto viene de la cámara o de la galería.
  Future<void> _agregarFoto() async {
    if (_restantes <= 0) return;
    final origen = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: MarksColores.fondo,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(PhosphorIconsLight.camera, color: MarksColores.azul),
                title: const Text('Tomar foto', style: TextStyle(color: MarksColores.azul)),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(PhosphorIconsLight.images, color: MarksColores.azul),
                title: const Text('Elegir de la galería', style: TextStyle(color: MarksColores.azul)),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (origen == null) return;

    // El celular reduce la foto antes de subirla (más rápido y gasta menos datos).
    // La API la vuelve a revisar, la reduce a 1280 px y le borra los metadatos.
    const ancho = 1600.0;
    const calidad = 85;
    try {
      final List<XFile> elegidas;
      if (origen == ImageSource.gallery && _restantes > 1) {
        elegidas = await _selector.pickMultiImage(
          maxWidth: ancho,
          maxHeight: ancho,
          imageQuality: calidad,
          limit: _restantes,
        );
      } else {
        final una = await _selector.pickImage(
          source: origen,
          maxWidth: ancho,
          maxHeight: ancho,
          imageQuality: calidad,
        );
        elegidas = una == null ? const [] : [una];
      }
      if (!mounted || elegidas.isEmpty) return;
      final caben = _restantes;
      setState(() {
        // Por si la galería no respeta el límite, solo se toman las que caben
        _nuevas.addAll(elegidas.take(caben));
        _error = null;
      });
      if (elegidas.length > caben) {
        _aviso('Máximo ${OpinionesService.maxFotos} fotos: solo se agregaron las que caben');
      }
    } on PlatformException {
      if (mounted) {
        _aviso('No se pudo abrir la ${origen == ImageSource.camera ? 'cámara' : 'galería'}. '
            'Revisa los permisos de MARK\'S en los ajustes del celular.');
      }
    }
  }

  // ------------------------------------------------------------------
  // Guardar y borrar
  // ------------------------------------------------------------------

  Future<void> _guardar() async {
    if (_estrellas == 0) {
      setState(() => _error = 'Toca las estrellas para calificar de 1 a 5');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final rutas = _nuevas.map((f) => f.path).toList();
      if (_editando) {
        await OpinionesService.editar(
          opinionId: widget.existente!.id,
          estrellas: _estrellas,
          comentario: _comentario.text,
          conservar: _conservadas.map((f) => f.id).toList(),
          fotosNuevas: rutas,
        );
      } else {
        await OpinionesService.opinar(
          productoId: widget.productoId,
          estrellas: _estrellas,
          comentario: _comentario.text,
          fotos: rutas,
        );
      }
      if (!mounted) return;
      _aviso(_editando ? 'Tu opinión se actualizó' : 'Gracias por tu opinión');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _borrar() async {
    final confirmar = await mostrarConfirmacion(
      context,
      titulo: '¿Borrar tu opinión?',
      mensaje: 'Se borrarán tus estrellas, tu comentario y tus fotos. No se puede deshacer.',
      textoConfirmar: 'Borrar',
      icono: PhosphorIconsLight.trash,
      peligro: true,
    );
    if (!confirmar || !mounted) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await OpinionesService.borrar(widget.existente!.id);
      if (!mounted) return;
      _aviso('Tu opinión se borró');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  // ------------------------------------------------------------------
  // Pantalla
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_enviando, // no se puede salir mientras sube
      child: Scaffold(
        backgroundColor: MarksColores.fondo,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Encabezado
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Regresar',
                      icon: const Icon(PhosphorIconsLight.arrowLeft, color: MarksColores.azul),
                      onPressed: _enviando ? null : () => Navigator.of(context).pop(false),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _editando ? 'Editar opinión' : 'Calificar producto',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: MarksColores.azul,
                            ),
                          ),
                          Text(
                            widget.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: MarksColores.textoSuave),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    // Estrellas
                    TarjetaSuave(
                      padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
                      child: Column(
                        children: [
                          const Text(
                            '¿Qué te pareció?',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: MarksColores.azul,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SelectorEstrellas(
                            valor: _estrellas,
                            alCambiar: (n) => setState(() {
                              _estrellas = n;
                              _error = null;
                            }),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _estrellas == 0
                                ? 'Toca una estrella'
                                : SelectorEstrellas.textos[_estrellas],
                            style: const TextStyle(fontSize: 14, color: MarksColores.textoSuave),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Comentario
                    const _Titulo('Cuéntanos más (opcional)'),
                    TextField(
                      controller: _comentario,
                      enabled: !_enviando,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: OpinionesService.maxComentario,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: '¿Qué te gustó? ¿Qué no? ¿Lo volverías a comprar?',
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Fotos
                    _Titulo('Fotos (opcional) · $_totalFotos de ${OpinionesService.maxFotos}'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final foto in _conservadas)
                          _FotoQuitable(
                            alQuitar: _enviando
                                ? null
                                : () => setState(() => _conservadas.remove(foto)),
                            child: MiniaturaFoto(foto: foto, tamano: 92),
                          ),
                        for (final foto in _nuevas)
                          _FotoQuitable(
                            alQuitar: _enviando ? null : () => setState(() => _nuevas.remove(foto)),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(foto.path),
                                width: 92,
                                height: 92,
                                fit: BoxFit.cover,
                                cacheWidth: 276,
                              ),
                            ),
                          ),
                        if (_restantes > 0)
                          _BotonAgregarFoto(alTocar: _enviando ? null : _agregarFoto),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Qué se publica
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(PhosphorIconsLight.info, size: 16, color: MarksColores.textoSuave),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tu opinión se publica con tu nombre y la inicial de tu apellido. '
                            'Las fotos se publican sin ubicación ni datos de la cámara.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: MarksColores.textoSuave,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Error
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: MarksColores.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),

                    BotonPrincipal(
                      texto: _enviando
                          ? 'Enviando...'
                          : (_editando ? 'Guardar cambios' : 'Publicar opinión'),
                      icono: PhosphorIconsLight.paperPlaneTilt,
                      onPressed: _enviando ? null : _guardar,
                    ),
                    if (_editando) ...[
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _enviando ? null : _borrar,
                        icon: const Icon(PhosphorIconsLight.trash, size: 18),
                        label: const Text('Borrar mi opinión'),
                        style: TextButton.styleFrom(foregroundColor: MarksColores.error),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
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
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: MarksColores.azul,
        ),
      ),
    );
  }
}

/// Foto con una "x" en la esquina para quitarla.
class _FotoQuitable extends StatelessWidget {
  final Widget child;
  final VoidCallback? alQuitar;

  const _FotoQuitable({required this.child, required this.alQuitar});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -8,
          right: -8,
          child: Material(
            color: MarksColores.azul,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: alQuitar,
              child: const Padding(
                padding: EdgeInsets.all(5),
                child: Icon(PhosphorIconsLight.x, size: 14, color: MarksColores.blanco),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cuadro "+ Agregar foto".
class _BotonAgregarFoto extends StatelessWidget {
  final VoidCallback? alTocar;

  const _BotonAgregarFoto({required this.alTocar});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Agregar foto',
      child: Material(
        color: MarksColores.blanco,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: alTocar,
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MarksColores.borde, width: 1.5),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(PhosphorIconsLight.cameraPlus, color: MarksColores.verdeOscuro, size: 26),
                SizedBox(height: 4),
                Text(
                  'Agregar',
                  style: TextStyle(fontSize: 12, color: MarksColores.verdeOscuro),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}