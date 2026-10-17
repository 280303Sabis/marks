-- ⚠️⚠️ ADVERTENCIA: ESTE SCRIPT BORRA TODA LA BASE marks_db ⚠️⚠️
-- Úsalo SOLO para instalar desde cero. Para cambios usa /migraciones
-- =====================================================
--  MARK'S - Base de datos (MySQL 9.3)
--  PASO 1: roles, usuarios y sucursales
--  PASO 2: categorias, productores, productos e inventario
--  PASO 4: seguridad (bloqueo, aviso de privacidad, bitácora,
--          códigos de verificación)
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
-- -----------------------------------------------------
CREATE TABLE movimientos_inventario (
    id           INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    producto_id  INT UNSIGNED NOT NULL,
    sucursal_id  SMALLINT UNSIGNED NOT NULL,
    tipo         ENUM('ENTRADA','SALIDA_VENTA','AJUSTE','MERMA') NOT NULL,
    cantidad     DECIMAL(10,3) NOT NULL,
    stock_final  DECIMAL(10,3) NOT NULL,
    usuario_id   INT UNSIGNED NULL,
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
         AND i.fecha_caducidad <= CURDATE() + INTERVAL 3 DAY) AS caducidad_proxima
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
                     'CORREO_CONFIRMADO','DATOS_EXPORTADOS','CUENTA_ELIMINADA') NOT NULL,
    ip          VARCHAR(45),
    detalle     VARCHAR(200),
    fecha       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_bitacora_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE SET NULL,
    INDEX idx_bitacora_fecha (fecha)
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