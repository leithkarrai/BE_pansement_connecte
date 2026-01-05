# Script complet pour démarrer le backend avec toutes les dépendances
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "🚀 DÉMARRAGE COMPLET DU BACKEND" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

# Étape 1 : Vérifier Docker Desktop
Write-Host "📋 ÉTAPE 1/4 : Vérification de Docker Desktop" -ForegroundColor Yellow
Write-Host ""
$maxAttempts = 30
$attempt = 0
$dockerReady = $false

while ($attempt -lt $maxAttempts -and -not $dockerReady) {
    try {
        docker ps | Out-Null
        $dockerReady = $true
        Write-Host "   ✅ Docker Desktop est prêt!" -ForegroundColor Green
    } catch {
        $attempt++
        if ($attempt -eq 1) {
            Write-Host "   ⏳ Docker Desktop n'est pas démarré..." -ForegroundColor Yellow
            Write-Host "   💡 Veuillez démarrer Docker Desktop maintenant" -ForegroundColor Cyan
            Write-Host "   ⏳ Attente de Docker Desktop (tentative $attempt/$maxAttempts)..." -ForegroundColor Gray
        } else {
            Write-Host "   ⏳ Attente... (tentative $attempt/$maxAttempts)" -ForegroundColor Gray
        }
        Start-Sleep -Seconds 2
    }
}

if (-not $dockerReady) {
    Write-Host ""
    Write-Host "   [ERREUR] Docker Desktop n'est pas demarre apres $maxAttempts tentatives" -ForegroundColor Red
    Write-Host ""
    Write-Host "   Veuillez:" -ForegroundColor Yellow
    Write-Host "   1. Démarrer Docker Desktop depuis le menu Démarrer" -ForegroundColor White
    Write-Host "   2. Attendre que l'icône Docker dans la barre des tâches soit verte" -ForegroundColor White
    Write-Host "   3. Réessayer ce script" -ForegroundColor White
    Write-Host ""
    Write-Host "   Appuyez sur une touche pour quitter..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Étape 2 : Vérifier et démarrer les services de base de données
Write-Host ""
Write-Host "📋 ÉTAPE 2/4 : Vérification des services de base de données" -ForegroundColor Yellow
Write-Host ""

$dbPath = "..\pansement-connecte-db"
if (Test-Path $dbPath) {
    Write-Host "   ✅ Dossier pansement-connecte-db trouvé" -ForegroundColor Green
    
    $postgresRunning = docker ps --format "{{.Names}}" | Select-String "pansement_postgres"
    $redisRunning = docker ps --format "{{.Names}}" | Select-String "pansement_redis"
    $minioRunning = docker ps --format "{{.Names}}" | Select-String "pansement_minio"
    
    if ($postgresRunning -and $redisRunning -and $minioRunning) {
        Write-Host "   ✅ Tous les services de base de données sont démarrés" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  Certains services ne sont pas démarrés" -ForegroundColor Yellow
        Write-Host "   🔄 Démarrage des services de base de données..." -ForegroundColor Cyan
        
        Push-Location $dbPath
        docker-compose up -d
        Pop-Location
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   ✅ Services de base de données démarrés" -ForegroundColor Green
            Write-Host "   ⏳ Attente du démarrage complet (10 secondes)..." -ForegroundColor Gray
            Start-Sleep -Seconds 10
        } else {
            Write-Host "   ⚠️  Erreur lors du démarrage des services" -ForegroundColor Yellow
            Write-Host "   Le backend pourrait ne pas fonctionner correctement" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "   ⚠️  Dossier pansement-connecte-db non trouvé" -ForegroundColor Yellow
    Write-Host "   Le backend utilisera les services existants" -ForegroundColor Gray
}

# Étape 3 : Arrêter le backend existant s'il tourne
Write-Host ""
Write-Host "📋 ÉTAPE 3/4 : Préparation du backend" -ForegroundColor Yellow
Write-Host ""

$backendRunning = docker ps --format "{{.Names}}" | Select-String "pansement_backend"
if ($backendRunning) {
    Write-Host "   ⚠️  Le backend est déjà en cours d'exécution" -ForegroundColor Yellow
    Write-Host "   🔄 Arrêt du backend existant..." -ForegroundColor Cyan
    docker-compose down
    Start-Sleep -Seconds 2
}

# Étape 4 : Construire et démarrer le backend
Write-Host ""
Write-Host "📋 ÉTAPE 4/4 : Construction et démarrage du backend" -ForegroundColor Yellow
Write-Host ""

Write-Host "   🔨 Construction de l'image Docker..." -ForegroundColor Cyan
Write-Host "   (Cette étape peut prendre quelques minutes la première fois)" -ForegroundColor Gray
docker-compose build

if ($LASTEXITCODE -ne 0) {
    Write-Host "   [ERREUR] Erreur lors de la construction de l image" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "   🚀 Démarrage du backend..." -ForegroundColor Cyan
docker-compose up -d

if ($LASTEXITCODE -ne 0) {
    Write-Host "   [ERREUR] Erreur lors du demarrage du backend" -ForegroundColor Red
    exit 1
}

# Attendre que le backend soit prêt
Write-Host ""
Write-Host "   ⏳ Attente du démarrage complet (5 secondes)..." -ForegroundColor Gray
Start-Sleep -Seconds 5

# Vérifier que le backend répond
Write-Host ""
Write-Host "   🔍 Vérification de la santé du backend..." -ForegroundColor Cyan
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
            Write-Host "   ⏳ Tentative $attempt/$maxAttempts..." -ForegroundColor Gray
            Start-Sleep -Seconds 2
        }
    }
}

# Résultat final
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

if ($backendReady) {
    Write-Host "✅ BACKEND DÉMARRÉ AVEC SUCCÈS!" -ForegroundColor Green
} else {
    Write-Host "⚠️  Le backend semble démarrer lentement" -ForegroundColor Yellow
    Write-Host "   Vérifiez les logs avec: docker-compose logs -f backend" -ForegroundColor Cyan
}

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""
Write-Host "📱 Application Mobile:" -ForegroundColor Yellow
Write-Host "   • Android Emulator: http://10.0.2.2:8000/api/v1" -ForegroundColor White
Write-Host "   • iOS Simulator:     http://localhost:8000/api/v1" -ForegroundColor White
Write-Host ""
Write-Host "📖 Documentation API:" -ForegroundColor Yellow
Write-Host "   • Swagger UI:        http://localhost:8000/api/docs" -ForegroundColor White
Write-Host "   • Health Check:      http://localhost:8000/health" -ForegroundColor White
Write-Host ""
Write-Host "🔧 Commandes utiles:" -ForegroundColor Yellow
Write-Host "   • Voir les logs:     docker-compose logs -f backend" -ForegroundColor White
Write-Host "   • Arrêter:           docker-compose down" -ForegroundColor White
Write-Host "   • Redémarrer:        docker-compose restart backend" -ForegroundColor White
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

# Afficher les logs
Write-Host "📋 Logs du backend (Ctrl+C pour quitter):" -ForegroundColor Cyan
Write-Host ""
docker-compose logs -f backend

