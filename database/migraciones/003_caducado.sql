-- =====================================================
--  MIGRACION 003: estado "caducado" en v_inventario
--  Fecha: 2026-10-13
--  - caducado:          la fecha de caducidad ya paso
--  - caducidad_proxima: vence hoy o en los proximos 3 dias
--  Solo reemplaza la vista; no modifica datos.
-- =====================================================
USE marks_db;

CREATE OR REPLACE VIEW v_inventario AS
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