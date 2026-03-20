# Guide : Démarrer le Backend avec Docker

## Prérequis

1. **Docker Desktop doit être démarré** ✅
   - Vérifiez que Docker Desktop est en cours d'exécution
   - L'icône Docker doit être visible dans la barre des tâches

2. **Les services de base de données doivent être démarrés** ✅
   - PostgreSQL, Redis, MinIO doivent être en cours d'exécution
   - Ils sont généralement dans un autre docker-compose (pansement-connecte-db)

## 📋 Étapes pour démarrer le backend

### Étape 1 : Vérifier que Docker Desktop est démarré

```powershell
# Tester la connexion Docker
docker ps
```

Si vous voyez une erreur, démarrez Docker Desktop.

### Étape 2 : Vérifier que les services de base de données sont démarrés

```powershell
# Vérifier les conteneurs en cours d'exécution
docker ps

# Vous devriez voir :
# - pansement_postgres (PostgreSQL)
# - pansement_redis (Redis)
# - pansement_minio (MinIO)
```

Si ces conteneurs ne sont pas démarrés, allez dans le dossier `pansement-connecte-db` et démarrez-les :

```powershell
cd ..\pansement-connecte-db
docker-compose up -d
```

### Étape 3 : Démarrer le backend

```powershell
# Dans le dossier pansement-backend
cd pansement-backend

# Construire l'image (première fois seulement)
docker-compose build

# Démarrer le backend
docker-compose up
```

### Étape 4 : Vérifier que le backend fonctionne

Ouvrez votre navigateur et allez sur :
- **Documentation API** : http://localhost:8000/api/docs
- **Health Check** : http://localhost:8000/health

Si vous voyez la documentation Swagger, le backend est démarré ! ✅

## 🔧 Commandes utiles

### Voir les logs du backend
```powershell
docker-compose logs -f backend
```

### Arrêter le backend
```powershell
docker-compose down
```

### Redémarrer le backend
```powershell
docker-compose restart backend
```

### Reconstruire l'image (après modification du code)
```powershell
docker-compose up --build
```

## ⚠️ Problèmes courants

### Erreur : "network not found"
Le réseau Docker n'existe pas. Démarrez d'abord les services de base de données :
```powershell
cd ..\pansement-connecte-db
docker-compose up -d
```

### Erreur : "port already in use"
Le port 8000 est déjà utilisé. Vérifiez si un autre processus utilise ce port :
```powershell
netstat -ano | findstr :8000
```

### Le backend ne démarre pas
Vérifiez les logs :
```powershell
docker-compose logs backend
```

## 📱 Configuration pour l'application mobile

Une fois le backend démarré, l'application mobile peut se connecter via :
- **Android Emulator** : `http://10.0.2.2:8000/api/v1` (déjà configuré)
- **iOS Simulator** : `http://localhost:8000/api/v1`
- **Device physique** : `http://192.168.X.X:8000/api/v1` (remplacer X.X par l'IP de votre PC)


