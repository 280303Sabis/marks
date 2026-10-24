# Genera el APK de MARK'S para compartir (WhatsApp, Drive, etc.).
# La app queda apuntando a la API publicada en Render.
#
# Uso (desde la carpeta marks_app):
#   .\generar_apk.ps1 https://marks-api.onrender.com
#
# El archivo queda en: build\app\outputs\flutter-apk\MARKS.apk

param([Parameter(Mandatory = $true)][string]$ApiUrl)

$ApiUrl = $ApiUrl.TrimEnd("/")
if ($ApiUrl -notmatch "^https://") {
    Write-Host "La dirección debe empezar con https:// (la de Render)." -ForegroundColor Red
    exit 1
}

flutter build apk --release --dart-define=API_URL=$ApiUrl
if ($LASTEXITCODE -ne 0) {
    Write-Host "No se pudo generar el APK." -ForegroundColor Red
    exit 1
}

$salida = "build\app\outputs\flutter-apk"
Copy-Item "$salida\app-release.apk" "$salida\MARKS.apk" -Force
Write-Host "Listo: $salida\MARKS.apk (apunta a $ApiUrl)" -ForegroundColor Green
