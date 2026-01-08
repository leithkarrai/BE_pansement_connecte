# Guide de déploiement sur Railway

## Configuration requise

### Variables d'environnement à configurer dans Railway

1. **DATABASE_URL** (automatique si vous ajoutez PostgreSQL)
   - Railway fournit automatiquement cette variable quand vous ajoutez un service PostgreSQL
   - Format : `postgresql://user:password@host:port/database`

2. **JWT_SECRET_KEY** (requis)
   - Clé secrète pour signer les tokens JWT
   - Minimum 32 caractères
   - Exemple : `your-super-secret-jwt-key-change-me-min-32-chars-random-string`

3. **REDIS_URL** (optionnel - si vous utilisez Redis)
   - Format : `redis://:password@host:port`

4. **MINIO_ENDPOINT** (optionnel - si vous utilisez MinIO)
   - Exemple : `your-minio-endpoint.railway.app:9000`

5. **MINIO_ACCESS_KEY** (optionnel)
   - Clé d'accès MinIO

6. **MINIO_SECRET_KEY** (optionnel)
   - Clé secrète MinIO

7. **INFLUXDB_URL** (optionnel - si vous utilisez InfluxDB)
   - Exemple : `http://your-influxdb.railway.app:8086`

## Étapes de déploiement

1. **Créer un projet Railway**
   - Allez sur https://railway.app
   - Connectez-vous avec GitHub
   - Créez un nouveau projet

2. **Ajouter le service backend**
   - Cliquez sur "New" → "GitHub Repo"
   - Sélectionnez `leithkarrai/BE_pansement_connecte`
   - Railway détectera automatiquement Python

3. **Ajouter PostgreSQL**
   - Cliquez sur "New" → "Database" → "PostgreSQL"
   - Railway créera automatiquement la base de données
   - La variable `DATABASE_URL` sera automatiquement ajoutée

4. **Configurer les variables d'environnement**
   - Allez dans "Variables" de votre service
   - Ajoutez `JWT_SECRET_KEY` avec une valeur sécurisée
   - Ajoutez les autres variables optionnelles si nécessaire

5. **Déployer**
   - Railway déploiera automatiquement
   - L'URL de votre API sera disponible dans l'onglet "Settings" → "Domains"

## Migration de la base de données

Après le premier déploiement, vous devrez initialiser la base de données :

1. Connectez-vous au service Railway via SSH ou utilisez Railway CLI
2. Exécutez les scripts SQL d'initialisation :
   ```bash
   psql $DATABASE_URL < init_database.sql
   ```

Ou utilisez Alembic pour les migrations :
```bash
alembic upgrade head
```

## Vérification

Une fois déployé, testez :
- `https://votre-app.railway.app/` → Page d'accueil
- `https://votre-app.railway.app/health` → Health check
- `https://votre-app.railway.app/api/docs` → Documentation Swagger

