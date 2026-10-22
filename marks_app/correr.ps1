# correr.ps1 - Abre MARK'S en el celular conectado por USB.
# adb reverse hace que el 127.0.0.1:5000 del celular llegue a la API de esta computadora
# por el cable, así no importa a qué internet estés conectada.

$adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) { $adb = "adb" }   # por si adb está en el PATH

& $adb reverse tcp:5000 tcp:5000
if ($LASTEXITCODE -ne 0) {
    Write-Host "No se encontró el celular. Revisa el cable y la depuración USB." -ForegroundColor Red
    exit 1
}
Write-Host "Celular conectado a la API por USB (127.0.0.1:5000)" -ForegroundColor Green

flutter run