# Abre la app MARK'S en el celular conectado por USB.
# El celular llega a la API de esta computadora por el cable,
# sin importar en qué red Wi-Fi estés.
#
# Uso (desde la carpeta marks_app):   .\correr_celular.ps1
# Antes de usarlo, la API debe estar corriendo (python run.py).

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"

if (-not (Test-Path $adb)) {
    Write-Host "No se encontró adb en: $adb" -ForegroundColor Red
    exit 1
}

& $adb reverse tcp:5000 tcp:5000
if ($LASTEXITCODE -ne 0) {
    Write-Host "No se pudo conectar con el celular. Revisa el cable, que esté desbloqueado y que la depuración USB esté activa." -ForegroundColor Red
    exit 1
}

Write-Host "Celular conectado a la API por USB (puerto 5000)" -ForegroundColor Green
flutter run -d R5GL35PP04L