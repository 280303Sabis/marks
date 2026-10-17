-- =====================================================
--  UTILIDAD: fechas de caducidad FIJAS para pruebas y
--  para la presentacion del 15 de noviembre de 2026.
--  Solo para desarrollo, nunca en produccion.
--
--  Estados el dia de la presentacion (sucursal 1):
--    Normal:       cafe, salsa, carne, manzana, platano
--    Por caducar:  leche (17 nov) y pan (16 nov)
--    Caducado:     refresco (5 oct)
--  Sucursal 2: leche caducada, refresco normal.
-- =====================================================
USE marks_db;

-- Por si se llego a crear el evento automatico: lo quitamos
DROP EVENT IF EXISTS ev_fechas_prueba;

SET SQL_SAFE_UPDATES = 0;

-- Sucursal 1: Santa Catarina
UPDATE inventario SET fecha_caducidad = '2026-11-17' WHERE producto_id = 1 AND sucursal_id = 1; -- Leche: por caducar el 15 nov
UPDATE inventario SET fecha_caducidad = '2026-11-16' WHERE producto_id = 2 AND sucursal_id = 1; -- Pan: por caducar el 15 nov
UPDATE inventario SET fecha_caducidad = '2026-10-05' WHERE producto_id = 3 AND sucursal_id = 1; -- Refresco: CADUCADO
UPDATE inventario SET fecha_caducidad = '2027-10-01' WHERE producto_id = 4 AND sucursal_id = 1; -- Cafe: normal
UPDATE inventario SET fecha_caducidad = '2027-01-15' WHERE producto_id = 5 AND sucursal_id = 1; -- Salsa: normal
UPDATE inventario SET fecha_caducidad = '2026-11-30' WHERE producto_id = 8 AND sucursal_id = 1; -- Carne: normal

-- Sucursal 2: Valle Oriente
UPDATE inventario SET fecha_caducidad = '2026-10-10' WHERE producto_id = 1 AND sucursal_id = 2; -- Leche: CADUCADA
UPDATE inventario SET fecha_caducidad = '2027-03-31' WHERE producto_id = 3 AND sucursal_id = 2; -- Refresco: normal

SET SQL_SAFE_UPDATES = 1;

-- Revision
SELECT producto_id, sucursal, nombre, fecha_caducidad, caducado, caducidad_proxima
FROM v_inventario
ORDER BY sucursal_id, producto_id;