-- =====================================================
--  MARK'S - Migración 005: programa de lealtad (PASO 11)
--  Reglas: 1 punto por cada $10 pagados, productos locales x2,
--          100 puntos = $10 de descuento (hasta 50% de la compra).
--  No borra ni cambia datos existentes.
-- =====================================================
USE marks_db;

-- -----------------------------------------------------
-- Ventas: cuántos puntos se usaron y cuántos se ganaron
--   subtotal - ahorro - descuento_puntos = total (lo cobrado a la tarjeta)
-- -----------------------------------------------------
ALTER TABLE ventas
    ADD COLUMN puntos_usados    INT UNSIGNED  NOT NULL DEFAULT 0    AFTER ahorro,
    ADD COLUMN descuento_puntos DECIMAL(10,2) NOT NULL DEFAULT 0.00 AFTER puntos_usados,
    ADD COLUMN puntos_ganados   INT UNSIGNED  NOT NULL DEFAULT 0    AFTER total;

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

-- Revisión rápida
SHOW COLUMNS FROM ventas LIKE '%puntos%';
DESCRIBE movimientos_puntos;