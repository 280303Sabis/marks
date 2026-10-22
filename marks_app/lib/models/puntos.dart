/// Modelos de "Mis puntos" (PASO 12): saldo, reglas y estado de cuenta.

double _numero(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

/// Un renglón del estado de cuenta de puntos.
class MovimientoPuntos {
  final String tipo;       // GANADOS, CANJEADOS o AJUSTE
  final int puntos;        // positivo = gana, negativo = usa
  final int saldoFinal;
  final String nota;
  final DateTime? fecha;
  final String? folio;     // compra relacionada (null en un AJUSTE)

  const MovimientoPuntos({
    required this.tipo,
    required this.puntos,
    required this.saldoFinal,
    required this.nota,
    required this.fecha,
    required this.folio,
  });

  bool get esGanancia => puntos > 0;

  factory MovimientoPuntos.fromJson(Map<String, dynamic> j) => MovimientoPuntos(
        tipo: (j['tipo'] ?? '') as String,
        puntos: (j['puntos'] as num?)?.toInt() ?? 0,
        saldoFinal: (j['saldo_final'] as num?)?.toInt() ?? 0,
        nota: (j['nota'] ?? '') as String,
        fecha: DateTime.tryParse((j['fecha'] ?? '').toString()),
        folio: j['folio'] as String?,
      );
}

/// Reglas del programa de lealtad (vienen de la API, no se escriben a mano).
class ReglasPuntos {
  final int pesosPorPunto;        // 1 punto por cada $10
  final int multiplicadorLocal;   // productos locales x2
  final int puntosPorBloque;      // 100 puntos...
  final double valorBloque;       // ...= $10
  final int maxPorcentajeCanje;   // hasta 50% de la compra

  const ReglasPuntos({
    required this.pesosPorPunto,
    required this.multiplicadorLocal,
    required this.puntosPorBloque,
    required this.valorBloque,
    required this.maxPorcentajeCanje,
  });

  factory ReglasPuntos.fromJson(Map<String, dynamic> j) => ReglasPuntos(
        pesosPorPunto: _numero(j['pesos_por_punto']).toInt(),
        multiplicadorLocal: _numero(j['multiplicador_local']).toInt(),
        puntosPorBloque: _numero(j['puntos_por_bloque']).toInt(),
        valorBloque: _numero(j['valor_bloque']),
        maxPorcentajeCanje: _numero(j['max_porcentaje_canje']).toInt(),
      );
}

/// Respuesta de GET /api/puntos/movimientos.
class EstadoCuentaPuntos {
  final int saldo;
  final ReglasPuntos reglas;
  final List<MovimientoPuntos> movimientos;

  const EstadoCuentaPuntos({
    required this.saldo,
    required this.reglas,
    required this.movimientos,
  });

  factory EstadoCuentaPuntos.fromJson(Map<String, dynamic> j) => EstadoCuentaPuntos(
        saldo: (j['saldo'] as num?)?.toInt() ?? 0,
        reglas: ReglasPuntos.fromJson((j['reglas'] as Map<String, dynamic>?) ?? const {}),
        movimientos: ((j['movimientos'] as List?) ?? const [])
            .map((m) => MovimientoPuntos.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}