-- =====================================================
-- MARK'S - Migración 007 (PASO 14)
-- Nuevo evento en la bitácora: AVISO_ACEPTADO
-- (cuando un usuario acepta una versión nueva del Aviso de Privacidad)
-- =====================================================
USE marks_db;

ALTER TABLE bitacora_accesos
    MODIFY evento ENUM('REGISTRO','LOGIN_OK','LOGIN_FALLIDO','CUENTA_BLOQUEADA',
                       'CAMBIO_PASSWORD','RECUPERACION_SOLICITADA','RECUPERACION_OK',
                       'CORREO_CONFIRMADO','DATOS_EXPORTADOS','CUENTA_ELIMINADA',
                       'PERFIL_ACTUALIZADO','COMPRA_PAGADA','AVISO_ACEPTADO') NOT NULL;

-- Revisión: debe terminar en ...'COMPRA_PAGADA','AVISO_ACEPTADO')
SHOW COLUMNS FROM bitacora_accesos LIKE 'evento';

-- Quién tiene una versión vieja del aviso (se le pedirá aceptar la 1.2)
SELECT version_aviso_privacidad AS version, COUNT(*) AS usuarios
FROM usuarios GROUP BY version_aviso_privacidad;