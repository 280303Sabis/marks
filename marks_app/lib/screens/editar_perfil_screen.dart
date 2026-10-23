import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/usuario.dart';
import '../services/api_service.dart';
import '../services/cuenta_service.dart';
import '../theme/colores.dart';
import '../widgets/campos_registro.dart';
import '../widgets/soft_ui.dart';

/// Editar mis datos (PASO 14, derecho de Rectificación).
/// Usa los mismos campos y reglas que el registro. El correo no se cambia.
/// Al guardar regresa el Usuario actualizado.
class EditarPerfilScreen extends StatefulWidget {
  final Usuario usuario;

  const EditarPerfilScreen({super.key, required this.usuario});

  @override
  State<EditarPerfilScreen> createState() => _EditarPerfilScreenState();
}

class _EditarPerfilScreenState extends State<EditarPerfilScreen> {
  static const int edadMinima = 18;

  final _formulario = GlobalKey<FormState>();
  late final TextEditingController _nombre =
      TextEditingController(text: widget.usuario.nombre);
  late final TextEditingController _apellidos =
      TextEditingController(text: widget.usuario.apellidos ?? '');
  late final TextEditingController _telefono =
      TextEditingController(text: widget.usuario.telefono ?? '');
  late DateTime? _fecha = widget.usuario.fechaNacimiento;
  late String? _sexo = widget.usuario.sexo;

  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _apellidos.dispose();
    _telefono.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formulario.currentState!.validate()) return;

    setState(() => _guardando = true);
    try {
      final actualizado = await CuentaService.editarPerfil(
        nombre: _nombre.text,
        apellidos: _apellidos.text,
        telefono: _telefono.text,
        fechaNacimiento: fechaIso(_fecha!),
        sexo: _sexo!,
      );
      if (mounted) Navigator.of(context).pop(actualizado);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_guardando,
      child: Scaffold(
        backgroundColor: MarksColores.fondo,
        body: SafeArea(
          child: Form(
            key: _formulario,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                // Encabezado
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Regresar',
                      icon: const Icon(PhosphorIconsLight.arrowLeft, color: MarksColores.azul),
                      onPressed: _guardando ? null : () => Navigator.of(context).pop(),
                    ),
                    const Text(
                      'Editar mis datos',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: MarksColores.azul,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                const _Etiqueta('Nombre'),
                CampoSuave(
                  controller: _nombre,
                  hint: 'Tu nombre',
                  icono: PhosphorIconsLight.user,
                  habilitado: !_guardando,
                  accionTeclado: TextInputAction.next,
                  formateadores: [LengthLimitingTextInputFormatter(80)],
                  validador: (v) {
                    final t = (v ?? '').trim();
                    if (t.length < 2) return 'Escribe tu nombre (mínimo 2 letras)';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                const _Etiqueta('Apellidos (opcional)'),
                CampoSuave(
                  controller: _apellidos,
                  hint: 'Tus apellidos',
                  icono: PhosphorIconsLight.user,
                  habilitado: !_guardando,
                  accionTeclado: TextInputAction.next,
                  formateadores: [LengthLimitingTextInputFormatter(80)],
                ),
                const SizedBox(height: 16),

                const _Etiqueta('Teléfono (opcional)'),
                CampoSuave(
                  controller: _telefono,
                  hint: '10 dígitos',
                  icono: PhosphorIconsLight.phone,
                  habilitado: !_guardando,
                  tipoTeclado: TextInputType.phone,
                  formateadores: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validador: (v) {
                    final t = (v ?? '').trim();
                    if (t.isNotEmpty && t.length != 10) return 'El teléfono debe tener 10 dígitos';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                const _Etiqueta('Fecha de nacimiento'),
                SelectorFecha(
                  hint: 'Elige tu fecha de nacimiento',
                  valorInicial: _fecha,
                  habilitado: !_guardando,
                  alCambiar: (f) => _fecha = f,
                  validator: (f) {
                    if (f == null) return 'Elige tu fecha de nacimiento';
                    if (calcularEdad(f) < edadMinima) {
                      return 'Debes tener al menos $edadMinima años';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                const _Etiqueta('Sexo'),
                SelectorSexo(
                  valorInicial: _sexo,
                  habilitado: !_guardando,
                  alCambiar: (s) => _sexo = s,
                  validator: (s) => s == null ? 'Selecciona una opción' : null,
                ),
                const SizedBox(height: 16),

                // Correo (solo lectura)
                TarjetaSuave(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(PhosphorIconsLight.envelopeSimple,
                          size: 22, color: MarksColores.textoSuave),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.usuario.correo,
                              style: const TextStyle(fontSize: 15, color: MarksColores.azul),
                            ),
                            const Text(
                              'El correo no se puede cambiar',
                              style: TextStyle(fontSize: 12, color: MarksColores.textoSuave),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 18),
                  TarjetaError(mensaje: _error!),
                ],
                const SizedBox(height: 24),

                BotonPrincipal(
                  texto: 'Guardar cambios',
                  icono: PhosphorIconsLight.check,
                  cargando: _guardando,
                  onPressed: _guardar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  final String texto;

  const _Etiqueta(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 8),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: MarksColores.azul,
        ),
      ),
    );
  }
}