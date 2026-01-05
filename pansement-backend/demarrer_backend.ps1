# Script PowerShell pour démarrer le backend avec Docker
# Usage: .\demarrer_backend.ps1

Write-Host "🐳 Démarrage du Backend avec Docker" -ForegroundColor Cyan
Write-Host ""

# Vérifier que Docker est disponible
Write-Host "1️⃣ Vérification de Docker Desktop..." -ForegroundColor Yellow
try {
    docker ps | Out-Null
    Write-Host "   ✅ Docker Desktop est démarré" -ForegroundColor Green
} catch {
    Write-Host "   ❌ ERREUR: Docker Desktop n'est pas démarré!" -ForegroundColor Red
    Write-Host "   Veuillez démarrer Docker Desktop et réessayer." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   Appuyez sur une touche pour quitter..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Vérifier que le réseau existe
Write-Host ""
Write-Host "2️⃣ Vérification du réseau Docker..." -ForegroundColor Yellow
$networkExists = docker network ls --format "{{.Name}}" | Select-String "pansement-connecte-db_pansement_network"
if ($networkExists) {
    Write-Host "   ✅ Réseau Docker trouvé" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  Réseau Docker non trouvé" -ForegroundColor Yellow
    Write-Host "   Le réseau sera créé automatiquement si nécessaire" -ForegroundColor Yellow
}

# Vérifier les services de base de données
Write-Host ""
Write-Host "3️⃣ Vérification des services de base de données..." -ForegroundColor Yellow
$postgresRunning = docker ps --format "{{.Names}}" | Select-String "pansement_postgres"
$redisRunning = docker ps --format "{{.Names}}" | Select-String "pansement_redis"
$minioRunning = docker ps --format "{{.Names}}" | Select-String "pansement_minio"

if ($postgresRunning) {
    Write-Host "   ✅ PostgreSQL est démarré" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  PostgreSQL n'est pas démarré" -ForegroundColor Yellow
}

if ($redisRunning) {
    Write-Host "   ✅ Redis est démarré" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  Redis n'est pas démarré" -ForegroundColor Yellow
}

if ($minioRunning) {
    Write-Host "   ✅ MinIO est démarré" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  MinIO n'est pas démarré" -ForegroundColor Yellow
}

if (-not ($postgresRunning -and $redisRunning -and $minioRunning)) {
    Write-Host ""
    Write-Host "   ⚠️  ATTENTION: Certains services de base de données ne sont pas démarrés!" -ForegroundColor Yellow
    Write-Host "   Le backend pourrait ne pas fonctionner correctement." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   Pour démarrer les services de base de données:" -ForegroundColor Cyan
    Write-Host "   cd ..\pansement-connecte-db" -ForegroundColor White
    Write-Host "   docker-compose up -d" -ForegroundColor White
    Write-Host ""
    $continue = Read-Host "   Voulez-vous continuer quand même? (o/N)"
    if ($continue -ne "o" -and $continue -ne "O") {
        Write-Host "   Arrêt du script." -ForegroundColor Yellow
        exit 1
    }
}

# Vérifier si le backend est déjà en cours d'exécution
Write-Host ""
Write-Host "4️⃣ Vérification du backend existant..." -ForegroundColor Yellow
$backendRunning = docker ps --format "{{.Names}}" | Select-String "pansement_backend"
if ($backendRunning) {
    Write-Host "   ⚠️  Le backend est déjà en cours d'exécution" -ForegroundColor Yellow
    $restart = Read-Host "   Voulez-vous le redémarrer? (o/N)"
    if ($restart -eq "o" -or $restart -eq "O") {
        Write-Host "   Arrêt du backend existant..." -ForegroundColor Yellow
        docker-compose down
    } else {
        Write-Host "   Le backend continue de fonctionner." -ForegroundColor Green
        Write-Host ""
        Write-Host "   📱 L'application mobile peut se connecter à:" -ForegroundColor Cyan
        Write-Host "   http://10.0.2.2:8000/api/v1 (Android Emulator)" -ForegroundColor White
        Write-Host "   http://localhost:8000/api/v1 (iOS Simulator)" -ForegroundColor White
        Write-Host ""
        Write-Host "   📖 Documentation API: http://localhost:8000/api/docs" -ForegroundColor Cyan
        exit 0
    }
}

# Construire l'image si nécessaire
Write-Host ""
Write-Host "5️⃣ Construction de l'image Docker..." -ForegroundColor Yellow
Write-Host "   (Cette étape peut prendre quelques minutes la première fois)" -ForegroundColor Gray
docker-compose build

if ($LASTEXITCODE -ne 0) {
    Write-Host "   ❌ Erreur lors de la construction de l'image" -ForegroundColor Red
    exit 1
}

# Démarrer le backend
Write-Host ""
Write-Host "6️⃣ Démarrage du backend..." -ForegroundColor Yellow
docker-compose up -d

if ($LASTEXITCODE -ne 0) {
    Write-Host "   ❌ Erreur lors du démarrage du backend" -ForegroundColor Red
    exit 1
}

# Attendre que le backend soit prêt
Write-Host ""
Write-Host "7️⃣ Attente du démarrage du backend..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Vérifier que le backend répond
Write-Host ""
Write-Host "8️⃣ Vérification de la santé du backend..." -ForegroundColor Yellow
$maxAttempts = 12
$attempt = 0
$backendReady = $false

while ($attempt -lt $maxAttempts -and -not $backendReady) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8000/health" -TimeoutSec 2 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $backendReady = $true
            Write-Host "   ✅ Backend démarré avec succès!" -ForegroundColor Green
        }
    } catch {
        $attempt++
        Write-Host "   Tentative $attempt/$maxAttempts..." -ForegroundColor Gray
        Start-Sleep -Seconds 2
    }
}

if (-not $backendReady) {
    Write-Host "   ⚠️  Le backend semble démarrer lentement" -ForegroundColor Yellow
    Write-Host "   Vérifiez les logs avec: docker-compose logs -f backend" -ForegroundColor Cyan
}

# Afficher les informations de connexion
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "✅ BACKEND DÉMARRÉ AVEC SUCCÈS!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""
Write-Host "📱 Application Mobile:" -ForegroundColor Yellow
Write-Host "   • Android Emulator: http://10.0.2.2:8000/api/v1" -ForegroundColor White
Write-Host "   • iOS Simulator:     http://localhost:8000/api/v1" -ForegroundColor White
Write-Host "   • Device physique:   http://192.168.X.X:8000/api/v1" -ForegroundColor White
Write-Host ""
Write-Host "📖 Documentation API:" -ForegroundColor Yellow
Write-Host "   • Swagger UI:        http://localhost:8000/api/docs" -ForegroundColor White
Write-Host "   • ReDoc:             http://localhost:8000/api/redoc" -ForegroundColor White
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


