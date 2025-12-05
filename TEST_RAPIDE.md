# 🧪 Guide de Test Rapide

## ✅ Étape 1 : Démarrer le serveur

```bash
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

**Résultat attendu :**
```
🚀 Démarrage de Pansement Connecté API
✅ PostgreSQL connecté
   📊 Tables: 12
   👥 Users: 6
   📟 Devices: 5
   📈 Measurements: 10
✅ Redis connecté (cache activé)
✅ MinIO connecté (stockage fichiers activé)
```

---

## ✅ Étape 2 : Tester l'API (Swagger)

1. **Ouvrir Swagger :** http://127.0.0.1:8000/api/docs

2. **Tester l'authentification :**
   - `POST /api/v1/auth/login`
   - Email: `admin.test@example.com`
   - Password: `admin123`
   - ✅ Vous devriez recevoir un `access_token`

3. **Utiliser le token :**
   - Cliquez sur le bouton **"Authorize"** (cadenas en haut)
   - Collez votre `access_token`
   - Cliquez sur **"Authorize"**

---

## ✅ Étape 3 : Tester Redis (Cache)

1. **Faire une requête :**
   - `GET /api/v1/users/{user_id}` (avec votre token)
   - Notez le temps de réponse

2. **Faire la même requête 2-3 fois :**
   - Les requêtes suivantes devraient être plus rapides (cache)

3. **Vérifier dans Redis Commander :**
   - Ouvrir : http://localhost:8081
   - Vous devriez voir une clé : `user:{user_id}`
   - Cliquez dessus pour voir les données en cache

---

## ✅ Étape 4 : Tester InfluxDB (Mesures)

1. **Créer une mesure :**
   - `POST /api/v1/measurements`
   - Body exemple :
   ```json
   {
     "device_id": "votre-device-id",
     "measurement_type": "temperature",
     "value": 37.5,
     "unit": "celsius",
     "quality_score": 95
   }
   ```

2. **Vérifier dans InfluxDB :**
   - Ouvrir : http://localhost:8086
   - User: `admin`
   - Password: `influx_password_change_me`
   - Aller dans **Data Explorer**
   - Vous devriez voir la mesure automatiquement enregistrée

---

## ✅ Étape 5 : Tester MinIO (Fichiers)

1. **Uploader une photo :**
   - `POST /api/v1/files/upload/photo`
   - Sélectionner un fichier image
   - ✅ Vous devriez recevoir un `file_path`

2. **Vérifier dans MinIO Console :**
   - Ouvrir : http://localhost:9001
   - User: `minioadmin`
   - Password: `minioadmin_password_change_me`
   - Cliquez sur le bucket `wound-photos`
   - Vous devriez voir votre fichier uploadé

3. **Télécharger le fichier :**
   - `GET /api/v1/files/download/wound-photos/{object_name}`
   - Le fichier devrait se télécharger

---

## ✅ Étape 6 : Vérifier les services

### PostgreSQL
- **Interface :** pgAdmin - http://localhost:5050
- **Email :** admin@pansement-connecte.com
- **Password :** admin_password_change_me

### Redis
- **Interface :** Redis Commander - http://localhost:8081
- Aucune authentification

### InfluxDB
- **Interface :** http://localhost:8086
- **User :** admin
- **Password :** influx_password_change_me

### MinIO
- **Interface :** http://localhost:9001
- **User :** minioadmin
- **Password :** minioadmin_password_change_me

---

## 🎯 Tests rapides (PowerShell)

### Test 1 : Health Check
```powershell
Invoke-RestMethod -Uri "http://127.0.0.1:8000/health" -Method Get
```

### Test 2 : Login
```powershell
$body = @{
    email = "admin.test@example.com"
    password = "admin123"
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri "http://127.0.0.1:8000/api/v1/auth/login" -Method Post -Body $body -ContentType "application/json"
$token = $response.access_token
Write-Host "Token: $token"
```

### Test 3 : Get User (avec cache)
```powershell
$headers = @{
    Authorization = "Bearer $token"
}

# Première requête (depuis PostgreSQL)
Measure-Command { Invoke-RestMethod -Uri "http://127.0.0.1:8000/api/v1/users/$($response.user.id)" -Method Get -Headers $headers }

# Deuxième requête (depuis Redis cache - plus rapide)
Measure-Command { Invoke-RestMethod -Uri "http://127.0.0.1:8000/api/v1/users/$($response.user.id)" -Method Get -Headers $headers }
```

---

## ✅ Checklist de vérification

- [ ] Serveur démarre sans erreur
- [ ] PostgreSQL connecté
- [ ] Redis connecté
- [ ] MinIO connecté
- [ ] Swagger accessible (http://127.0.0.1:8000/api/docs)
- [ ] Login fonctionne
- [ ] Cache Redis fonctionne (clé visible dans Redis Commander)
- [ ] Upload fichier fonctionne (fichier visible dans MinIO)
- [ ] Mesure créée (visible dans InfluxDB)

---

## 🎉 Si tout fonctionne

Vous avez maintenant :
- ✅ **PostgreSQL** : Base de données principale
- ✅ **Redis** : Cache automatique (25-100x plus rapide)
- ✅ **InfluxDB** : Stockage temps réel des mesures
- ✅ **MinIO** : Stockage de fichiers (photos, documents)

**Tout fonctionne automatiquement !** 🚀

