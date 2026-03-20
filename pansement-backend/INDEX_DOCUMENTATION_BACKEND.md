# Index Documentation Technique Backend

Ce document sert de plan rapide pour le dossier de recette.  
Il référence les modules backend critiques, les endpoints principaux, les permissions et les points de sécurité/métier.

## 1) Contexte technique backend

- **Framework API**: FastAPI
- **ORM/DB**: SQLAlchemy + PostgreSQL
- **Auth**: JWT (access + refresh), bcrypt via passlib
- **Stockage objet**: MinIO (photos, avatars, documents)
- **Cache**: Redis (ex: fiches utilisateur, invalidation listes)
- **Rôles**: `patient`, `medecin`, `admin`

## 2) Authentification et sécurité

### `app/api/auth.py`

- `POST /api/v1/auth/register`
  - Inscription utilisateur.
  - Rôle inféré si non fourni (`medecin` si infos pro, sinon `patient`).
  - Compte créé inactif (`is_active=False`) en attente validation admin.
- `POST /api/v1/auth/login`
  - Vérifie email/mot de passe, compte actif.
  - Retourne `access_token` + `refresh_token`.
- `POST /api/v1/auth/refresh`
  - Génère un nouvel access token depuis refresh token valide.
- Endpoints complémentaires (mot de passe, vérification email) selon implémentation du module.

### `app/api/deps.py`

- `get_current_user`
  - Validation chaîne complète: JWT -> `sub` UUID -> user DB existant -> user actif.
- `require_role([...])`
  - Contrôle d’accès par rôles (insensible à la casse).
  - Le backend reste la source d’autorité (même si l’UI masque des actions).

### `app/core/security.py`

- Hash/verify mot de passe (`bcrypt`).
- Création et décodage JWT.
- Conventions payload token: `sub` (UUID user), `role`.

## 3) Gestion des utilisateurs

### `app/api/users.py`

- `GET /api/v1/users`
  - Admin: tous les utilisateurs.
  - Médecin: ses patients.
  - Patient: accès refusé.
  - Pagination + filtres (`role`, `search`).
- `GET /api/v1/users/{user_id}`
  - Permissions selon rôle + cache Redis.
- `POST /api/v1/users` (admin)
  - Création user (patient/médecin/admin).
  - Mot de passe hashé côté backend.
- `PUT /api/v1/users/{user_id}`
  - Mise à jour user avec contrôles d’accès.
- `DELETE /api/v1/users/{user_id}` (admin)
  - Soft delete (`is_active=False`).
  - Règle: admin ne peut pas supprimer son propre compte.

## 4) Devices et liaison patient-device

### `app/api/devices.py`

- `POST /api/v1/devices/patient/assign-device` (patient)
  - Liaison active patient-device.
  - Ferme la liaison active précédente du device avant insertion.
  - Acquitte les alertes patient non lues après assignation.
- `GET /api/v1/devices`
  - Liste devices avec filtres (`status`, `patient_id`).
  - Mapping normalisé vers `DeviceResponse`.
- `POST /api/v1/devices`
  - Création device (unicité `device_id`, `mac_address`).
- `POST /api/v1/devices/register-by-mac`
  - Enregistrement/récupération d’un device à partir de l’adresse MAC.

## 5) Mesures et logique clinique technique

### `app/api/measurements.py`

- `POST /api/v1/measurements`
  - Ingestion mesures depuis app/pansement.
  - Type de mesure ouvert (`MeasurementCreateOpen`) pour compat firmware.
  - Auto-liaison patient-device en filet de sécurité si nécessaire.
  - Création d’alerte en mode best effort (ne bloque pas la sauvegarde mesure).
- Endpoints de listing/historique selon rôle et périmètre patient/device.

## 6) Alertes et acquittement par rôle

### `app/api/alerts.py`

- `GET /api/v1/alerts`
  - Admin: toutes alertes.
  - Médecin: alertes de ses patients assignés.
  - Patient: ses alertes.
  - Filtres: sévérité, type, non-acquittées.
- `GET /api/v1/alerts/patient/{patient_id}`
  - Même logique sur un patient donné avec vérifications d’accès.
- Acquittement/suppression indépendants par rôle:
  - patient: `acknowledged_at` / `deleted_at`
  - medecin: `acknowledged_by_medecin_at` / `deleted_by_medecin_at`
  - admin: `acknowledged_by_admin_at` / `deleted_by_admin_at`

## 7) Commentaires cliniques

### `app/api/comments.py`

- `GET /api/v1/comments/patient/{patient_id}`
  - Patient: ses commentaires.
  - Médecin: patient assigné obligatoire + ne voit que ses propres commentaires.
  - Admin: vue globale.
- `POST /api/v1/comments`
  - Auteur autorisé: médecin ou admin.
  - Validation patient, texte non vide, assignation médecin vérifiée.
  - Insert SQL explicite avec `CAST(:param AS uuid)` pour robustesse PostgreSQL.
- `PUT /api/v1/comments/{comment_id}`
  - Médecin: seulement ses propres commentaires.
  - Admin: tous les commentaires.

## 8) Fichiers (MinIO)

### `app/api/files.py`

- `POST /api/v1/files/upload/photo`
  - Upload image patient selon permissions rôle.
  - Convention objet: `{patient_id}/{uuid.ext}`.
- `POST /api/v1/files/upload/avatar`
  - Upload avatar utilisateur (limite 5MB).
  - Persistance URL dans `users.profile_photo_url`.
- `GET /api/v1/files/download/{bucket}/{object_name}`
  - Contrôle d’accès basé sur owner dans `object_name` + relation médecin-patient.
- `DELETE /api/v1/files/{bucket}/{object_name}` (admin)
  - Suppression physique dans MinIO.

## 9) Base de données et migrations de compatibilité

### `app/database.py`

- Connexion SQLAlchemy via `DATABASE_URL`.
- `init_db()`:
  - `create_all` (dev) + migrations runtime de compatibilité.
- Migrations runtime présentes:
  - colonnes `measurements.freq_hz` / `phase_deg`,
  - valeur enum `alerts.alert_type = new_measurements`,
  - colonnes acquittement par rôle (`acknowledged_by_medecin_at`, `acknowledged_by_admin_at`).
- En production: privilégier Alembic (migrations versionnées, traçabilité).

## 10) Script d’administration hors API

### `scripts/create_admin.py`

- Création d’un administrateur initial/supplémentaire sans passer par l’API.
- Usage:
  - `python scripts/create_admin.py --email administrateur@votredomaine.fr --password "MotDePasseFort123!"`
  - optionnel: `--first-name`, `--last-name`.
- Prérequis:
  - PostgreSQL accessible (`DATABASE_URL`),
  - politique mot de passe respectée.

## 11) Checklist recette (backend)

- Démarrage services DB puis backend Docker.
- Test auth: register -> activation admin -> login -> refresh.
- Test rôles: patient/médecin/admin sur users, alerts, comments, files.
- Test mesure end-to-end: assign device -> create measurement -> alerte visible.
- Test règle métier commentaire: un médecin ne voit pas les commentaires admin.
- Test soft delete user + blocage connexion compte désactivé.
