# 📦 Guide MinIO - Stockage de fichiers

## 📋 Vue d'ensemble

MinIO est utilisé pour **stocker les fichiers** (photos de plaies, avatars, documents) de manière sécurisée et scalable.

---

## 🌐 Accès à l'interface MinIO Console

**URL:** http://localhost:9001

**Identifiants:**
- **User:** `minioadmin`
- **Password:** `minioadmin_password_change_me`

---

## ✨ Routes API disponibles

### 1. **POST /api/v1/files/upload/photo** - Uploader une photo de plaie

**Permissions:**
- Admin: Peut uploader pour n'importe quel patient
- Médecin: Peut uploader pour ses patients
- Patient: Peut uploader uniquement pour lui-même

**Exemple avec Swagger:**
1. Allez sur `/api/docs`
2. Trouvez `POST /api/v1/files/upload/photo`
3. Cliquez sur "Try it out"
4. Sélectionnez un fichier image
5. Optionnel: Ajoutez `patient_id` si vous êtes admin/médecin
6. Cliquez sur "Execute"

**Réponse:**
```json
{
  "success": true,
  "file_path": "/wound-photos/{patient_id}/{uuid}.jpg",
  "object_name": "{patient_id}/{uuid}.jpg",
  "bucket": "wound-photos",
  "size": 123456,
  "content_type": "image/jpeg"
}
```

---

### 2. **POST /api/v1/files/upload/avatar** - Uploader une photo de profil

**Permissions:** Tous les utilisateurs peuvent uploader leur propre avatar

**Exemple avec Swagger:**
1. Allez sur `/api/docs`
2. Trouvez `POST /api/v1/files/upload/avatar`
3. Cliquez sur "Try it out"
4. Sélectionnez un fichier image (max 5MB)
5. Cliquez sur "Execute"

**Réponse:**
```json
{
  "success": true,
  "file_path": "/avatars/{user_id}/{uuid}.jpg",
  "object_name": "{user_id}/{uuid}.jpg",
  "bucket": "avatars",
  "size": 45678,
  "content_type": "image/jpeg"
}
```

---

### 3. **GET /api/v1/files/download/{bucket}/{object_name}** - Télécharger un fichier

**Permissions:**
- Admin: Peut télécharger n'importe quel fichier
- Médecin: Peut télécharger les fichiers de ses patients
- Patient: Peut télécharger uniquement ses propres fichiers

**Exemple:**
```
GET /api/v1/files/download/wound-photos/{patient_id}/{filename}.jpg
```

---

### 4. **DELETE /api/v1/files/{bucket}/{object_name}** - Supprimer un fichier

**Permissions:** Admin uniquement

---

## 🧪 Comment tester dans MinIO Console

### Étape 1 : Se connecter à MinIO Console

1. Ouvrez votre navigateur
2. Allez sur **http://localhost:9001**
3. Connectez-vous avec :
   - **User:** `minioadmin`
   - **Password:** `minioadmin_password_change_me`

### Étape 2 : Voir les buckets créés automatiquement

Après le démarrage de l'API, vous devriez voir 3 buckets :

1. **`wound-photos`** - Photos de plaies
2. **`documents`** - Documents médicaux
3. **`avatars`** - Photos de profil

### Étape 3 : Tester l'upload via API

1. **Dans Swagger** (`/api/docs`):
   - Utilisez `POST /api/v1/files/upload/photo`
   - Uploader une image de test

2. **Dans MinIO Console**:
   - Cliquez sur le bucket `wound-photos`
   - Vous devriez voir votre fichier uploadé !

### Étape 4 : Voir les détails d'un fichier

1. Cliquez sur un fichier dans MinIO Console
2. Vous verrez :
   - **Nom du fichier**
   - **Taille**
   - **Date de création**
   - **Métadonnées** (patient_id, uploaded_by, etc.)

### Étape 5 : Télécharger un fichier

1. Cliquez sur un fichier
2. Cliquez sur le bouton **"Download"**
3. Le fichier se télécharge

---

## 📊 Structure des buckets

### Bucket: `wound-photos`

**Structure:**
```
wound-photos/
  └── {patient_id}/
      ├── {uuid1}.jpg
      ├── {uuid2}.png
      └── ...
```

**Usage:** Photos de plaies pour suivi visuel

### Bucket: `avatars`

**Structure:**
```
avatars/
  └── {user_id}/
      └── {uuid}.jpg
```

**Usage:** Photos de profil des utilisateurs

### Bucket: `documents`

**Structure:**
```
documents/
  └── {patient_id}/
      ├── {uuid1}.pdf
      └── ...
```

**Usage:** Documents médicaux (rapports, prescriptions, etc.)

---

## 🔒 Sécurité et permissions

### Vérification automatique

L'API vérifie automatiquement les permissions :

- ✅ **Patient** → Peut uploader/télécharger uniquement ses propres fichiers
- ✅ **Médecin** → Peut uploader/télécharger les fichiers de ses patients
- ✅ **Admin** → Accès complet à tous les fichiers

### Métadonnées stockées

Chaque fichier stocke automatiquement :
- `patient_id` ou `user_id`
- `uploaded_by` (ID de l'utilisateur qui a uploadé)
- `original_filename` (nom original du fichier)

---

## 🚀 Avantages de MinIO

### 1. **Performance**

- ⚡ Upload/téléchargement rapide
- 📦 Stockage optimisé pour les fichiers
- 🔄 Pas de charge sur PostgreSQL

### 2. **Scalabilité**

- 📈 Support de millions de fichiers
- 💾 Stockage illimité (selon disque)
- 🎯 Organisation par buckets

### 3. **Compatibilité S3**

- ✅ API compatible Amazon S3
- ✅ Migration facile vers AWS S3 si besoin
- ✅ Outils standard (boto3, etc.)

---

## ✅ Vérification que MinIO fonctionne

### Test 1 : Vérifier la connexion

Au démarrage de l'API, vous devriez voir :
```
✅ MinIO connecté (stockage fichiers activé)
```

### Test 2 : Vérifier les buckets

Dans MinIO Console, vous devriez voir les 3 buckets créés automatiquement.

### Test 3 : Uploader un fichier

1. Utilisez Swagger pour uploader une photo
2. Vérifiez dans MinIO Console que le fichier apparaît

---

## 📝 Résumé

✅ **Stockage automatique** des fichiers dans MinIO  
✅ **Buckets créés automatiquement** au démarrage  
✅ **Permissions vérifiées** automatiquement  
✅ **Interface MinIO Console** pour visualiser les fichiers  
✅ **Routes API** pour uploader/télécharger/supprimer  

**Tout fonctionne automatiquement !** 🚀

