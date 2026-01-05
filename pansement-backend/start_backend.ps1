# Script pour demarrer le backend avec Docker
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DEMARRAGE DU BACKEND" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Etape 1: Verifier Docker Desktop
Write-Host "ETAPE 1/4: Verification de Docker Desktop" -ForegroundColor Yellow
Write-Host ""

$maxAttempts = 30
$attempt = 0
$dockerReady = $false

while ($attempt -lt $maxAttempts -and -not $dockerReady) {
    try {
        docker ps | Out-Null
        $dockerReady = $true
        Write-Host "   [OK] Docker Desktop est pret!" -ForegroundColor Green
    } catch {
        $attempt++
        if ($attempt -eq 1) {
            Write-Host "   [ATTENTE] Docker Desktop n'est pas demarre..." -ForegroundColor Yellow
            Write-Host "   [INFO] Veuillez demarrer Docker Desktop maintenant" -ForegroundColor Cyan
            Write-Host "   [ATTENTE] Tentative $attempt/$maxAttempts..." -ForegroundColor Gray
        } else {
            Write-Host "   [ATTENTE] Tentative $attempt/$maxAttempts..." -ForegroundColor Gray
        }
        Start-Sleep -Seconds 2
    }
}

if (-not $dockerReady) {
    Write-Host ""
    Write-Host "   [ERREUR] Docker Desktop n'est pas demarre" -ForegroundColor Red
    Write-Host ""
    Write-Host "   Veuillez:" -ForegroundColor Yellow
    Write-Host "   1. Demarrer Docker Desktop depuis le menu Demarrer" -ForegroundColor White
    Write-Host "   2. Attendre que l'icone Docker soit verte" -ForegroundColor White
    Write-Host "   3. Reessayer ce script" -ForegroundColor White
    Write-Host ""
    Write-Host "   Appuyez sur une touche pour quitter..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Etape 2: Verifier les services de base de donnees
Write-Host ""
Write-Host "ETAPE 2/4: Verification des services de base de donnees" -ForegroundColor Yellow
Write-Host ""

$dbPath = "..\pansement-connecte-db"
if (Test-Path $dbPath) {
    Write-Host "   [OK] Dossier pansement-connecte-db trouve" -ForegroundColor Green
    
    $postgresRunning = docker ps --format "{{.Names}}" | Select-String "pansement_postgres"
    $redisRunning = docker ps --format "{{.Names}}" | Select-String "pansement_redis"
    $minioRunning = docker ps --format "{{.Names}}" | Select-String "pansement_minio"
    
    if ($postgresRunning -and $redisRunning -and $minioRunning) {
        Write-Host "   [OK] Tous les services sont demarres" -ForegroundColor Green
    } else {
        Write-Host "   [INFO] Demarrage des services de base de donnees..." -ForegroundColor Cyan
        
        Push-Location $dbPath
        docker-compose up -d
        Pop-Location
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   [OK] Services demarres" -ForegroundColor Green
            Write-Host "   [ATTENTE] Attente du demarrage complet (10 secondes)..." -ForegroundColor Gray
            Start-Sleep -Seconds 10
        } else {
            Write-Host "   [AVERTISSEMENT] Erreur lors du demarrage des services" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "   [INFO] Dossier pansement-connecte-db non trouve" -ForegroundColor Yellow
    Write-Host "   [INFO] Le backend utilisera les services existants" -ForegroundColor Gray
}

# Etape 3: Arreter le backend existant
Write-Host ""
Write-Host "ETAPE 3/4: Preparation du backend" -ForegroundColor Yellow
Write-Host ""

$backendRunning = docker ps --format "{{.Names}}" | Select-String "pansement_backend"
if ($backendRunning) {
    Write-Host "   [INFO] Le backend est deja en cours d'execution" -ForegroundColor Yellow
    Write-Host "   [INFO] Arret du backend existant..." -ForegroundColor Cyan
    docker-compose down
    Start-Sleep -Seconds 2
}

# Etape 4: Construire et demarrer le backend
Write-Host ""
Write-Host "ETAPE 4/4: Construction et demarrage du backend" -ForegroundColor Yellow
Write-Host ""

Write-Host "   [INFO] Construction de l'image Docker..." -ForegroundColor Cyan
Write-Host "   [INFO] Cette etape peut prendre quelques minutes la premiere fois" -ForegroundColor Gray
docker-compose build

if ($LASTEXITCODE -ne 0) {
    Write-Host "   [ERREUR] Erreur lors de la construction" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "   [INFO] Demarrage du backend..." -ForegroundColor Cyan
docker-compose up -d

if ($LASTEXITCODE -ne 0) {
    Write-Host "   [ERREUR] Erreur lors du demarrage" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "   [ATTENTE] Attente du demarrage complet (5 secondes)..." -ForegroundColor Gray
Start-Sleep -Seconds 5

# Verifier que le backend repond
Write-Host ""
Write-Host "   [INFO] Verification de la sante du backend..." -ForegroundColor Cyan
$maxAttempts = 12
$attempt = 0
$backendReady = $false

while ($attempt -lt $maxAttempts -and -not $backendReady) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8000/health" -TimeoutSec 2 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $backendReady = $true
        }
    } catch {
        $attempt++
        if ($attempt -lt $maxAttempts) {
            Write-Host "   [ATTENTE] Tentative $attempt/$maxAttempts..." -ForegroundColor Gray
            Start-Sleep -Seconds 2
        }
    }
}

# Resultat final
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan

if ($backendReady) {
    Write-Host "[SUCCES] BACKEND DEMARRE AVEC SUCCES!" -ForegroundColor Green
} else {
    Write-Host "[AVERTISSEMENT] Le backend semble demarrer lentement" -ForegroundColor Yellow
    Write-Host "   Verifiez les logs avec: docker-compose logs -f backend" -ForegroundColor Cyan
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Application Mobile:" -ForegroundColor Yellow
Write-Host "   Android Emulator: http://10.0.2.2:8000/api/v1" -ForegroundColor White
Write-Host "   iOS Simulator:     http://localhost:8000/api/v1" -ForegroundColor White
Write-Host ""
Write-Host "Documentation API:" -ForegroundColor Yellow
Write-Host "   Swagger UI:        http://localhost:8000/api/docs" -ForegroundColor White
Write-Host "   Health Check:      http://localhost:8000/health" -ForegroundColor White
Write-Host ""
Write-Host "Commandes utiles:" -ForegroundColor Yellow
Write-Host "   Voir les logs:     docker-compose logs -f backend" -ForegroundColor White
Write-Host "   Arreter:           docker-compose down" -ForegroundColor White
Write-Host "   Redemarrer:        docker-compose restart backend" -ForegroundColor White
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Afficher les logs
Write-Host "Logs du backend (Ctrl+C pour quitter):" -ForegroundColor Cyan
Write-Host ""
docker-compose logs -f backend

