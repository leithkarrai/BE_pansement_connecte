# Script pour vérifier que Docker Desktop est prêt
Write-Host "🔍 Vérification de Docker Desktop..." -ForegroundColor Cyan
Write-Host ""

$maxAttempts = 30
$attempt = 0
$dockerReady = $false

while ($attempt -lt $maxAttempts -and -not $dockerReady) {
    try {
        docker ps | Out-Null
        $dockerReady = $true
        Write-Host "✅ Docker Desktop est prêt!" -ForegroundColor Green
        exit 0
    } catch {
        $attempt++
        Write-Host "⏳ Tentative $attempt/$maxAttempts - En attente de Docker Desktop..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
}

if (-not $dockerReady) {
    Write-Host ""
    Write-Host "❌ Docker Desktop n'est pas démarré après $maxAttempts tentatives" -ForegroundColor Red
    Write-Host ""
    Write-Host "Veuillez:" -ForegroundColor Yellow
    Write-Host "1. Démarrer Docker Desktop depuis le menu Démarrer" -ForegroundColor White
    Write-Host "2. Attendre que l'icône Docker dans la barre des tâches soit verte" -ForegroundColor White
    Write-Host "3. Réessayer ce script" -ForegroundColor White
    exit 1
}

