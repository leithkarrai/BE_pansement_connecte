# Guide de dépannage Railway

## Si le build échoue

### 1. Vérifier le Root Directory dans Railway

Si votre code est dans le dossier `BE_pansement_connecte` :

1. Allez dans Railway → Votre service → **Settings**
2. Dans la section **Source**, vérifiez **Root Directory**
3. Si le champ est vide, entrez : `BE_pansement_connecte`
4. Sauvegardez et redéployez

### 2. Vérifier les fichiers de configuration

Assurez-vous que ces fichiers existent à la racine du projet (dans `BE_pansement_connecte/`) :

- ✅ `Procfile` - Contient : `web: uvicorn app.main:app --host 0.0.0.0 --port $PORT`
- ✅ `requirements.txt` - Liste des dépendances Python
- ✅ `railway.json` - Configuration Railway (optionnel)
- ✅ `runtime.txt` - Version Python (optionnel, Railway détecte automatiquement)

### 3. Vérifier les logs de build

Dans Railway :
1. Allez dans **Deployments**
2. Cliquez sur le dernier déploiement
3. Cliquez sur **View logs**
4. Regardez les erreurs dans la section "Build"

### 4. Erreurs courantes

#### Erreur : "No module named 'app'"
**Solution** : Vérifiez que le Root Directory est bien configuré sur `BE_pansement_connecte`

#### Erreur : "Command not found: uvicorn"
**Solution** : Vérifiez que `uvicorn[standard]` est dans `requirements.txt`

#### Erreur : "Error creating build plan"
**Solution** : Railway devrait détecter automatiquement Python. Si ça ne marche pas :
- Vérifiez que `requirements.txt` existe
- Vérifiez que `Procfile` existe
- Supprimez `nixpacks.toml` si présent (laissez Railway détecter automatiquement)

### 5. Configuration manuelle dans Railway

Si la détection automatique ne fonctionne pas :

1. Allez dans **Settings** → **Build & Deploy**
2. **Build Command** : `pip install -r requirements.txt`
3. **Start Command** : `uvicorn app.main:app --host 0.0.0.0 --port $PORT`

### 6. Variables d'environnement requises

Dans **Variables**, ajoutez au minimum :

```
JWT_SECRET_KEY=votre-cle-secrete-minimum-32-caracteres
```

Railway ajoutera automatiquement `DATABASE_URL` si vous ajoutez PostgreSQL.

