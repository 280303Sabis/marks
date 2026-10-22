-- =====================================================
--  MARK'S - Migración 006: calificaciones y opiniones (PASO 13)
--  Reglas: 1 a 5 estrellas y comentario opcional.
--          Solo opina quien compró el producto; una opinión por
--          producto por cliente (se puede editar o borrar).
--          Se publican de inmediato; el admin puede ocultarlas.
--          Los reportes de clientes solo avisan al admin.
--          Hasta 3 fotos por opinión (se guardan en el servidor,
--          en la base solo va el nombre del archivo).
--  No borra ni cambia datos existentes.
-- =====================================================
USE marks_db;

-- -----------------------------------------------------
-- El admin puede apagar las opiniones de un producto
-- -----------------------------------------------------
ALTER TABLE productos
    ADD COLUMN opiniones_activas BOOLEAN NOT NULL DEFAULT TRUE AFTER activo;

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

-- Revisión rápida
SHOW COLUMNS FROM productos LIKE 'opiniones_activas';
DESCRIBE opiniones;
DESCRIBE opinion_fotos;
DESCRIBE reportes_opinion;