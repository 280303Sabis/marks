-- =====================================================
-- MIGRACIÓN 002: fecha de nacimiento y sexo del cliente
-- Fecha: 2026-10-10
-- Ejecutar UNA sola vez en marks_db. No borra datos.
-- =====================================================
USE marks_db;

ALTER TABLE usuarios
    ADD COLUMN fecha_nacimiento DATE NULL AFTER telefono,
    ADD COLUMN sexo ENUM('F','M','N') NULL
        COMMENT 'F = femenino, M = masculino, N = prefiere no decirlo'
        AFTER fecha_nacimiento;