-- =====================================================
--  MARK'S - Migración 004: ventas (PASO 10)
--  Agrega las tablas para guardar las compras pagadas
--  y liga el kárdex con la venta que hizo cada salida.
--  No borra ni cambia datos existentes.
-- =====================================================
USE marks_db;

-- -----------------------------------------------------
-- 12. VENTAS (una fila por compra pagada)
--     estado PAGADA   -> el cliente pagó y tiene su QR
--     estado VALIDADA -> el guardia ya escaneó el QR en la salida
--     estado CANCELADA-> reservado para devoluciones (más adelante)
-- -----------------------------------------------------
CREATE TABLE ventas (
    id                 INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    folio              VARCHAR(20)  NULL UNIQUE,          -- MK-261022-000001 (se asigna al guardar)
    clave_pago         CHAR(36)     NOT NULL UNIQUE,      -- la manda la app: evita cobrar dos veces
    usuario_id         INT UNSIGNED NOT NULL,
    sucursal_id        SMALLINT UNSIGNED NOT NULL,
    articulos          SMALLINT UNSIGNED NOT NULL,
    subtotal           DECIMAL(10,2) NOT NULL,            -- a precio normal
    ahorro             DECIMAL(10,2) NOT NULL DEFAULT 0,  -- por ofertas
    total              DECIMAL(10,2) NOT NULL,            -- lo que se cobró
    metodo_pago        ENUM('TARJETA') NOT NULL DEFAULT 'TARJETA',
    tarjeta_marca      VARCHAR(20)  NOT NULL,             -- VISA, MASTERCARD, AMEX...
    tarjeta_ultimos4   CHAR(4)      NOT NULL,             -- NUNCA el número completo
    estado             ENUM('PAGADA','VALIDADA','CANCELADA') NOT NULL DEFAULT 'PAGADA',
    pagada_en          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    validada_en        DATETIME NULL,
    validada_por       INT UNSIGNED NULL,                 -- guardia que escaneó el QR
    CONSTRAINT chk_ventas_total   CHECK (total > 0 AND subtotal >= total AND ahorro >= 0),
    CONSTRAINT chk_ventas_ult4    CHECK (tarjeta_ultimos4 REGEXP '^[0-9]{4}$'),
    CONSTRAINT fk_ventas_usuario  FOREIGN KEY (usuario_id)   REFERENCES usuarios(id),
    CONSTRAINT fk_ventas_sucursal FOREIGN KEY (sucursal_id)  REFERENCES sucursales(id),
    CONSTRAINT fk_ventas_guardia  FOREIGN KEY (validada_por) REFERENCES usuarios(id),
    INDEX idx_ventas_usuario (usuario_id, pagada_en)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 13. DETALLE DE VENTA (los productos de cada compra)
--     Se copian nombre y precios del momento de la compra:
--     si mañana cambia el precio, el ticket no cambia.
-- -----------------------------------------------------
CREATE TABLE venta_detalle (
    id               INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    venta_id         INT UNSIGNED NOT NULL,
    producto_id      INT UNSIGNED NOT NULL,
    codigo           VARCHAR(20)  NOT NULL,               -- lo que se escaneó
    nombre           VARCHAR(120) NOT NULL,
    tipo_venta       ENUM('UNIDAD','GRANEL') NOT NULL,
    cantidad         DECIMAL(10,3) NOT NULL,              -- piezas o kg
    precio           DECIMAL(10,2) NOT NULL,              -- precio normal
    precio_final     DECIMAL(10,2) NOT NULL,              -- con oferta si había
    importe          DECIMAL(10,2) NOT NULL,              -- lo que se cobró de esta línea
    importe_normal   DECIMAL(10,2) NOT NULL,
    es_local         BOOLEAN NOT NULL DEFAULT FALSE,      -- para los puntos (PASO 11)
    CONSTRAINT chk_detalle_cantidad CHECK (cantidad > 0),
    CONSTRAINT fk_detalle_venta    FOREIGN KEY (venta_id)    REFERENCES ventas(id) ON DELETE CASCADE,
    CONSTRAINT fk_detalle_producto FOREIGN KEY (producto_id) REFERENCES productos(id),
    INDEX idx_detalle_producto (producto_id)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Kárdex: cada SALIDA_VENTA guarda de qué venta salió
-- -----------------------------------------------------
ALTER TABLE movimientos_inventario
    ADD COLUMN venta_id INT UNSIGNED NULL AFTER usuario_id,
    ADD CONSTRAINT fk_movinv_venta FOREIGN KEY (venta_id) REFERENCES ventas(id);

-- -----------------------------------------------------
-- Bitácora: nuevo evento de pago
-- -----------------------------------------------------
ALTER TABLE bitacora_accesos
    MODIFY evento ENUM('REGISTRO','LOGIN_OK','LOGIN_FALLIDO','CUENTA_BLOQUEADA',
                       'CAMBIO_PASSWORD','RECUPERACION_SOLICITADA','RECUPERACION_OK',
                       'CORREO_CONFIRMADO','DATOS_EXPORTADOS','CUENTA_ELIMINADA',
                       'PERFIL_ACTUALIZADO','COMPRA_PAGADA') NOT NULL;

-- Revisión rápida
SHOW TABLES;
DESCRIBE ventas;