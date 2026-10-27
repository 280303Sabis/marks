-- ⚠️⚠️ ADVERTENCIA: ESTE SCRIPT BORRA TODA LA BASE marks_db ⚠️⚠️
-- Úsalo SOLO para instalar desde cero. Para cambios usa /migraciones
-- =====================================================
--  MARK'S - Base de datos (MySQL 8.4 en Aiven / MySQL 9.3 local)
--  PASO 1: roles, usuarios y sucursales
--  PASO 2: categorias, productores, productos e inventario
--  PASO 4: seguridad (bloqueo, aviso de privacidad, bitácora,
--          códigos de verificación)
--  PASO 10: ventas y detalle de venta
--  PASO 11: programa de lealtad (puntos)
--  PASO 13: calificaciones, opiniones, fotos y reportes
--
--  Actualizado el 2026-10-27: ya incluye las migraciones 001 a 007.
--  Una base creada con este archivo queda igual que una base vieja
--  a la que se le aplicaron todas las migraciones.
--  Las migraciones se conservan en /migraciones como historial.
-- =====================================================
DROP DATABASE IF EXISTS marks_db;
CREATE DATABASE marks_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE marks_db;

-- =====================================================
--  PASO 1
-- =====================================================

-- -----------------------------------------------------
-- 1. ROLES (CLIENTE, ADMIN, GUARDIA)
-- -----------------------------------------------------
CREATE TABLE roles (
    id          TINYINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    nombre      VARCHAR(20) NOT NULL UNIQUE,
    descripcion VARCHAR(120)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 2. USUARIOS  (+ campos de seguridad del PASO 4)
-- -----------------------------------------------------
CREATE TABLE usuarios (
    id                       INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    nombre                   VARCHAR(80)  NOT NULL,
    apellidos                VARCHAR(100),
    correo                   VARCHAR(120) NOT NULL UNIQUE,
    password_hash            VARCHAR(255) NOT NULL,
    telefono                 VARCHAR(20),
    fecha_nacimiento         DATE NULL,                        -- mayoría de edad (18+)
    sexo                     ENUM('F','M','N') NULL,           -- N = prefiere no decirlo
    rol_id                   TINYINT UNSIGNED NOT NULL DEFAULT 1,
    puntos_saldo             INT UNSIGNED NOT NULL DEFAULT 0,
    activo                   BOOLEAN NOT NULL DEFAULT TRUE,
    -- Seguridad
    correo_verificado        BOOLEAN NOT NULL DEFAULT FALSE,
    acepto_privacidad_en     DATETIME NULL,          -- cuándo aceptó el aviso
    version_aviso_privacidad VARCHAR(10) NULL,       -- qué versión aceptó
    intentos_fallidos        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    bloqueado_hasta          DATETIME NULL,          -- bloqueo temporal
    token_version            INT UNSIGNED NOT NULL DEFAULT 1,  -- invalida sesiones viejas
    password_actualizada_en  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ultimo_acceso            DATETIME NULL,
    creado_en                DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_usuarios_rol FOREIGN KEY (rol_id) REFERENCES roles(id)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 3. SUCURSALES
-- -----------------------------------------------------
CREATE TABLE sucursales (
    id         SMALLINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    nombre     VARCHAR(100) NOT NULL,
    direccion  VARCHAR(200),
    municipio  VARCHAR(80),
    activa     BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB;

-- =====================================================
--  PASO 2: ALMACÉN
-- =====================================================

-- -----------------------------------------------------
-- 4. CATEGORIAS (Lácteos, Frutas, Carnes...)
-- -----------------------------------------------------
CREATE TABLE categorias (
    id      SMALLINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    nombre  VARCHAR(60) NOT NULL UNIQUE
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 5. PRODUCTORES LOCALES (emprendimientos de Nuevo León)
-- -----------------------------------------------------
CREATE TABLE productores_locales (
    id           INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    nombre       VARCHAR(120) NOT NULL,
    municipio    VARCHAR(80),
    descripcion  VARCHAR(255),
    logo_url     VARCHAR(255)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 6. PRODUCTOS (catálogo, igual para todas las sucursales)
--    tipo_venta UNIDAD -> precio por pieza
--    tipo_venta GRANEL -> precio por kg
--    productor_id con valor -> es producto LOCAL de NL
-- -----------------------------------------------------
CREATE TABLE productos (
    id             INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    codigo_barras  VARCHAR(20)  NOT NULL UNIQUE,
    plu            CHAR(5)      NULL UNIQUE,
    nombre         VARCHAR(120) NOT NULL,
    descripcion    VARCHAR(255),
    categoria_id   SMALLINT UNSIGNED,
    productor_id   INT UNSIGNED NULL,
    tipo_venta     ENUM('UNIDAD','GRANEL') NOT NULL DEFAULT 'UNIDAD',
    precio         DECIMAL(10,2) NOT NULL,
    precio_oferta  DECIMAL(10,2) NULL,
    imagen_url     VARCHAR(255),
    activo         BOOLEAN NOT NULL DEFAULT TRUE,
    opiniones_activas BOOLEAN NOT NULL DEFAULT TRUE,   -- el admin puede apagar sus opiniones (006)
    creado_en      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_precio        CHECK (precio > 0),
    CONSTRAINT chk_precio_oferta CHECK (precio_oferta IS NULL OR (precio_oferta > 0 AND precio_oferta < precio)),
    CONSTRAINT chk_plu_granel    CHECK (plu IS NULL OR tipo_venta = 'GRANEL'),
    CONSTRAINT fk_productos_categoria FOREIGN KEY (categoria_id) REFERENCES categorias(id),
    CONSTRAINT fk_productos_productor FOREIGN KEY (productor_id) REFERENCES productores_locales(id),
    INDEX idx_productos_nombre (nombre)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 7. INVENTARIO (stock de cada producto en cada sucursal)
--    DECIMAL(10,3) para aceptar kg en granel (ej. 25.750)
-- -----------------------------------------------------
CREATE TABLE inventario (
    id               INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    producto_id      INT UNSIGNED NOT NULL,
    sucursal_id      SMALLINT UNSIGNED NOT NULL,
    stock            DECIMAL(10,3) NOT NULL DEFAULT 0,
    stock_minimo     DECIMAL(10,3) NOT NULL DEFAULT 0,
    fecha_caducidad  DATE NULL,
    ubicacion        VARCHAR(40),
    actualizado_en   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_inventario UNIQUE (producto_id, sucursal_id),
    CONSTRAINT fk_inventario_producto FOREIGN KEY (producto_id) REFERENCES productos(id),
    CONSTRAINT fk_inventario_sucursal FOREIGN KEY (sucursal_id) REFERENCES sucursales(id)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 8. MOVIMIENTOS DE INVENTARIO (bitácora / kardex)
--    cantidad positiva = entra, negativa = sale
--    venta_id: de qué venta salió (SALIDA_VENTA). Su llave foránea
--    se agrega más abajo, cuando ya existe la tabla ventas (004).
-- -----------------------------------------------------
CREATE TABLE movimientos_inventario (
    id           INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    producto_id  INT UNSIGNED NOT NULL,
    sucursal_id  SMALLINT UNSIGNED NOT NULL,
    tipo         ENUM('ENTRADA','SALIDA_VENTA','AJUSTE','MERMA') NOT NULL,
    cantidad     DECIMAL(10,3) NOT NULL,
    stock_final  DECIMAL(10,3) NOT NULL,
    usuario_id   INT UNSIGNED NULL,
    venta_id     INT UNSIGNED NULL,
    nota         VARCHAR(200),
    fecha        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_movinv_producto FOREIGN KEY (producto_id) REFERENCES productos(id),
    CONSTRAINT fk_movinv_sucursal FOREIGN KEY (sucursal_id) REFERENCES sucursales(id),
    CONSTRAINT fk_movinv_usuario  FOREIGN KEY (usuario_id)  REFERENCES usuarios(id),
    INDEX idx_movinv_fecha (fecha)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 9. VISTA para el panel de almacén
--    Junta producto + categoría + productor + stock
--    caducado:          la fecha de caducidad ya pasó (003)
--    caducidad_proxima: vence hoy o en los próximos 3 días
-- -----------------------------------------------------
CREATE VIEW v_inventario AS
SELECT  p.id                          AS producto_id,
        p.codigo_barras,
        p.plu,
        p.nombre,
        p.tipo_venta,
        p.precio,
        p.precio_oferta,
        p.activo,
        c.nombre                      AS categoria,
        (p.productor_id IS NOT NULL)  AS es_local,
        pl.nombre                     AS productor,
        s.id                          AS sucursal_id,
        s.nombre                      AS sucursal,
        i.stock,
        i.stock_minimo,
        (i.stock <= i.stock_minimo)   AS stock_bajo,
        i.fecha_caducidad,
        (i.fecha_caducidad IS NOT NULL
         AND i.fecha_caducidad < CURDATE())                    AS caducado,
        (i.fecha_caducidad IS NOT NULL
         AND i.fecha_caducidad >= CURDATE()
         AND i.fecha_caducidad <= CURDATE() + INTERVAL 3 DAY)  AS caducidad_proxima
FROM productos p
LEFT JOIN categorias c           ON c.id  = p.categoria_id
LEFT JOIN productores_locales pl ON pl.id = p.productor_id
JOIN inventario i                ON i.producto_id = p.id
JOIN sucursales s                ON s.id = i.sucursal_id;

-- =====================================================
--  PASO 4: SEGURIDAD
-- =====================================================

-- -----------------------------------------------------
-- 10. CÓDIGOS DE VERIFICACIÓN (recuperar contraseña,
--     confirmar correo). Se guarda el HASH del código,
--     nunca el código en texto plano.
-- -----------------------------------------------------
CREATE TABLE codigos_verificacion (
    id           INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    usuario_id   INT UNSIGNED NOT NULL,
    tipo         ENUM('RECUPERAR_PASSWORD','CONFIRMAR_CORREO') NOT NULL,
    codigo_hash  VARCHAR(255) NOT NULL,
    intentos     TINYINT UNSIGNED NOT NULL DEFAULT 0,
    expira_en    DATETIME NOT NULL,
    usado_en     DATETIME NULL,
    creado_en    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_codigos_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE,
    INDEX idx_codigos_usuario (usuario_id, tipo)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 11. BITÁCORA DE ACCESOS (auditoría de seguridad)
-- -----------------------------------------------------
CREATE TABLE bitacora_accesos (
    id          INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    usuario_id  INT UNSIGNED NULL,
    correo      VARCHAR(120),
    evento      ENUM('REGISTRO','LOGIN_OK','LOGIN_FALLIDO','CUENTA_BLOQUEADA',
                     'CAMBIO_PASSWORD','RECUPERACION_SOLICITADA','RECUPERACION_OK',
                     'CORREO_CONFIRMADO','DATOS_EXPORTADOS','CUENTA_ELIMINADA',
                     'PERFIL_ACTUALIZADO','COMPRA_PAGADA','AVISO_ACEPTADO') NOT NULL,
    ip          VARCHAR(45),
    detalle     VARCHAR(200),
    fecha       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_bitacora_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE SET NULL,
    INDEX idx_bitacora_fecha (fecha)
) ENGINE=InnoDB;

-- =====================================================
--  PASO 10: VENTAS (migración 004)
-- =====================================================

-- -----------------------------------------------------
-- 12. VENTAS (una fila por compra pagada)
--     estado PAGADA   -> el cliente pagó y tiene su QR
--     estado VALIDADA -> el guardia ya escaneó el QR en la salida
--     estado CANCELADA-> reservado para devoluciones (más adelante)
--     subtotal - ahorro - descuento_puntos = total (lo cobrado a la tarjeta)
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
    puntos_usados      INT UNSIGNED  NOT NULL DEFAULT 0,     -- (005)
    descuento_puntos   DECIMAL(10,2) NOT NULL DEFAULT 0.00,  -- (005)
    total              DECIMAL(10,2) NOT NULL,            -- lo que se cobró
    puntos_ganados     INT UNSIGNED  NOT NULL DEFAULT 0,     -- (005)
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

-- Kárdex: cada SALIDA_VENTA guarda de qué venta salió
ALTER TABLE movimientos_inventario
    ADD CONSTRAINT fk_movinv_venta FOREIGN KEY (venta_id) REFERENCES ventas(id);

-- =====================================================
--  PASO 11: PROGRAMA DE LEALTAD (migración 005)
--  1 punto por cada $10 pagados, productos locales x2,
--  100 puntos = $10 de descuento (hasta 50% de la compra).
-- =====================================================

-- -----------------------------------------------------
-- 14. MOVIMIENTOS DE PUNTOS (como un estado de cuenta)
--     puntos positivo = gana, negativo = usa
-- -----------------------------------------------------
CREATE TABLE movimientos_puntos (
    id           INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    usuario_id   INT UNSIGNED NOT NULL,
    venta_id     INT UNSIGNED NULL,
    tipo         ENUM('GANADOS','CANJEADOS','AJUSTE') NOT NULL,
    puntos       INT NOT NULL,
    saldo_final  INT UNSIGNED NOT NULL,
    nota         VARCHAR(200),
    fecha        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_movpuntos_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id),
    CONSTRAINT fk_movpuntos_venta   FOREIGN KEY (venta_id)   REFERENCES ventas(id),
    INDEX idx_movpuntos_usuario (usuario_id, fecha)
) ENGINE=InnoDB;

-- =====================================================
--  PASO 13: CALIFICACIONES Y OPINIONES (migración 006)
--  1 a 5 estrellas y comentario opcional. Solo opina quien compró;
--  una opinión por producto por cliente. El admin puede ocultarlas.
-- =====================================================

-- -----------------------------------------------------
-- 15. OPINIONES (una por producto por cliente)
--     estado PUBLICADA -> la ven todos
--     estado OCULTA    -> la ocultó el admin (solo la ve su autor)
-- -----------------------------------------------------
CREATE TABLE opiniones (
    id             INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    producto_id    INT UNSIGNED NOT NULL,
    usuario_id     INT UNSIGNED NOT NULL,
    estrellas      TINYINT UNSIGNED NOT NULL,
    comentario     VARCHAR(500) NULL,
    estado         ENUM('PUBLICADA','OCULTA') NOT NULL DEFAULT 'PUBLICADA',
    motivo_oculta  VARCHAR(200) NULL,                 -- por qué la ocultó el admin
    oculta_por     INT UNSIGNED NULL,                 -- admin que la ocultó
    creada_en      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    editada_en     DATETIME NULL,
    CONSTRAINT chk_opiniones_estrellas CHECK (estrellas BETWEEN 1 AND 5),
    CONSTRAINT uq_opinion_cliente  UNIQUE (producto_id, usuario_id),
    CONSTRAINT fk_opiniones_producto FOREIGN KEY (producto_id) REFERENCES productos(id),
    CONSTRAINT fk_opiniones_usuario  FOREIGN KEY (usuario_id)  REFERENCES usuarios(id),
    CONSTRAINT fk_opiniones_admin    FOREIGN KEY (oculta_por)  REFERENCES usuarios(id),
    INDEX idx_opiniones_producto (producto_id, estado, creada_en)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 16. FOTOS DE LAS OPINIONES (hasta 3 por opinión)
--     La imagen se guarda como archivo en el servidor (carpeta uploads);
--     aquí solo se guarda su nombre, que es aleatorio y no se puede adivinar.
-- -----------------------------------------------------
CREATE TABLE opinion_fotos (
    id           INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    opinion_id   INT UNSIGNED NOT NULL,
    archivo      VARCHAR(80)  NOT NULL UNIQUE,       -- ej. 3f9c...e1.jpg
    ancho        SMALLINT UNSIGNED NOT NULL,
    alto         SMALLINT UNSIGNED NOT NULL,
    bytes        INT UNSIGNED NOT NULL,
    creada_en    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_fotos_opinion FOREIGN KEY (opinion_id) REFERENCES opiniones(id) ON DELETE CASCADE,
    INDEX idx_fotos_opinion (opinion_id)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 17. REPORTES DE OPINIONES (avisan al admin)
--     Un cliente puede reportar una opinión una sola vez.
-- -----------------------------------------------------
CREATE TABLE reportes_opinion (
    id           INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    opinion_id   INT UNSIGNED NOT NULL,
    usuario_id   INT UNSIGNED NOT NULL,              -- quién reporta
    motivo       ENUM('OFENSIVA','SPAM','FALSA','OTRO') NOT NULL,
    revisado     BOOLEAN NOT NULL DEFAULT FALSE,     -- el admin ya lo vio
    creado_en    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_reporte_cliente UNIQUE (opinion_id, usuario_id),
    CONSTRAINT fk_reportes_opinion FOREIGN KEY (opinion_id) REFERENCES opiniones(id) ON DELETE CASCADE,
    CONSTRAINT fk_reportes_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id),
    INDEX idx_reportes_pendientes (revisado, creado_en)
) ENGINE=InnoDB;

-- =====================================================
--  DATOS INICIALES
-- =====================================================

-- PASO 1
INSERT INTO roles (id, nombre, descripcion) VALUES
 (1, 'CLIENTE', 'Usuario que compra con Scan & Go'),
 (2, 'ADMIN',   'Gestor de almacén / administrador'),
 (3, 'GUARDIA', 'Valida el QR de salida');

INSERT INTO sucursales (id, nombre, direccion, municipio) VALUES
 (1, 'MARK''S Santa Catarina', 'Av. Manuel Ordóñez 100',   'Santa Catarina'),
 (2, 'MARK''S Valle Oriente',  'Av. Lázaro Cárdenas 1000', 'San Pedro Garza García');

-- PASO 2
INSERT INTO categorias (id, nombre) VALUES
 (1, 'Lácteos'), (2, 'Panadería'), (3, 'Bebidas'),
 (4, 'Abarrotes'), (5, 'Frutas y verduras'), (6, 'Carnes');

INSERT INTO productores_locales (id, nombre, municipio, descripcion) VALUES
 (1, 'Café de la Sierra NL', 'Santiago',               'Tostadores artesanales de la Sierra Madre'),
 (2, 'Salsas La Regia',      'San Pedro Garza García', 'Salsas artesanales hechas en Nuevo León');

-- 5 productos por UNIDAD + 3 a GRANEL (estos llevan PLU de báscula)
INSERT INTO productos
 (id, codigo_barras, plu, nombre, descripcion, categoria_id, productor_id, tipo_venta, precio, precio_oferta) VALUES
 (1, '7501000000012', NULL,    'Leche entera 1 L',             'Leche pasteurizada',   1, NULL, 'UNIDAD',  28.50, NULL),
 (2, '7501000000029', NULL,    'Pan de caja blanco 680 g',     'Pan de molde',         2, NULL, 'UNIDAD',  52.00, 39.00),
 (3, '7501000000036', NULL,    'Refresco de cola 600 ml',      'Bebida gaseosa',       3, NULL, 'UNIDAD',  19.00, NULL),
 (4, '7501000000043', NULL,    'Café de olla molido 250 g',    'Producto local de NL', 4, 1,    'UNIDAD',  89.00, NULL),
 (5, '7501000000050', NULL,    'Salsa macha artesanal 300 ml', 'Producto local de NL', 4, 2,    'UNIDAD',  65.00, 55.00),
 (6, 'GR-40001',      '40001', 'Manzana roja',                 'Precio por kg',        5, NULL, 'GRANEL',  54.90, NULL),
 (7, 'GR-40002',      '40002', 'Plátano',                      'Precio por kg',        5, NULL, 'GRANEL',  24.50, NULL),
 (8, 'GR-20001',      '20001', 'Carne molida de res',          'Precio por kg',        6, NULL, 'GRANEL', 189.00, NULL);

-- Inventario inicial (sucursal 1 completa, sucursal 2 parcial)
INSERT INTO inventario (producto_id, sucursal_id, stock, stock_minimo, fecha_caducidad, ubicacion) VALUES
 (1, 1,  60,     10,     CURDATE() + INTERVAL 10 DAY, 'Pasillo 1'),
 (2, 1,  40,      8,     CURDATE() + INTERVAL 2 DAY,  'Pasillo 2'),
 (3, 1, 120,     24,     CURDATE() + INTERVAL 180 DAY,'Pasillo 3'),
 (4, 1,  25,      5,     CURDATE() + INTERVAL 365 DAY,'Pasillo 4'),
 (5, 1,  30,      5,     CURDATE() + INTERVAL 90 DAY, 'Pasillo 4'),
 (6, 1,  80.000, 10.000, NULL,                        'Frutas'),
 (7, 1, 100.000, 15.000, NULL,                        'Frutas'),
 (8, 1,  35.000,  5.000, CURDATE() + INTERVAL 3 DAY,  'Carnicería'),
 (1, 2,  50,     10,     CURDATE() + INTERVAL 12 DAY, 'Pasillo 1'),
 (3, 2,  90,     24,     CURDATE() + INTERVAL 180 DAY,'Pasillo 2');

-- Bitácora: registramos el inventario inicial como ENTRADA
INSERT INTO movimientos_inventario (producto_id, sucursal_id, tipo, cantidad, stock_final, nota)
SELECT producto_id, sucursal_id, 'ENTRADA', stock, stock, 'Inventario inicial'
FROM inventario;