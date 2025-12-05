# 📖 Explication détaillée des routes de mesures

Ce document explique en détail ce que fait chaque route de l'API `/api/v1/measurements`.

---

## 🔵 Route 1 : `POST /api/v1/measurements`

### 📝 Description
**Créer une nouvelle mesure** - Cette route permet de recevoir une mesure depuis un pansement connecté (via Bluetooth Low Energy - BLE).

### 🎯 Objectif
Quand un pansement IoT envoie une mesure (température, humidité, pH, etc.), cette route l'enregistre dans la base de données.

### 🔐 Authentification
**Aucune authentification requise** - Le pansement IoT n'a pas de compte utilisateur, donc cette route est publique.

### 📥 Données reçues (Body JSON)
```json
{
  "device_id": "0a008b59-fac6-4b9a-b50a-0a17d561f12a",  // ID du pansement
  "measurement_type": "temperature",                     // Type : temperature, humidity, ph, exudate
  "value": 37.2,                                         // Valeur mesurée
  "unit": "°C",                                          // Unité (°C, %, etc.)
  "quality_score": 95                                    // Score de qualité (0-100)
}
```

### ⚙️ Ce que fait la route

1. **Vérifie que le pansement existe**
   - Cherche le device dans la base de données
   - Si introuvable → Erreur 404

2. **Trouve le patient associé**
   - Cherche dans la table `patient_devices` quel patient utilise ce pansement
   - Si aucun patient → `patient_id` reste `None`

3. **Crée la mesure**
   - Enregistre la mesure dans la table `measurements`
   - Ajoute automatiquement un `timestamp` (date/heure actuelle)
   - Génère un `id` unique pour la mesure

4. **Met à jour le pansement**
   - Met à jour `last_seen` du device avec l'heure actuelle
   - Permet de savoir quand le pansement a envoyé sa dernière mesure

5. **Retourne la mesure créée**
   - Avec toutes les informations enrichies (nom du patient, numéro de série du pansement, etc.)

### 📤 Réponse
```json
{
  "id": "7b5763d8-160a-45aa-b35b-1661b88f97d4",
  "device_id": "0a008b59-fac6-4b9a-b50a-0a17d561f12a",
  "measurement_type": "temperature",
  "value": 37.2,
  "unit": "°C",
  "quality_score": 95,
  "timestamp": "2025-12-05T10:47:40.683149Z",
  "device_serial": "PANS-00001234",
  "patient_id": "1df48cb6-fc92-4221-a4f3-49f3baf6845a",
  "patient_name": "Marie Dupont"
}
```

### ✅ Cas d'usage
- Un pansement IoT envoie une mesure de température toutes les heures
- Un pansement détecte une anomalie et envoie une mesure urgente

---

## 🟢 Route 2 : `GET /api/v1/measurements/patient/{patient_id}`

### 📝 Description
**Historique des mesures d'un patient** - Cette route retourne toutes les mesures d'un patient avec pagination et filtres.

### 🎯 Objectif
Permettre aux médecins, admins ou patients de consulter l'historique complet des mesures d'un patient.

### 🔐 Authentification
**Authentification requise** avec permissions :
- **Admin** : Peut voir tous les patients
- **Médecin** : Peut voir uniquement ses patients (vérifié via table `medecin_patients`)
- **Patient** : Peut voir uniquement ses propres mesures

### 📥 Paramètres de l'URL
- `patient_id` (obligatoire) : ID du patient (UUID)
- `skip` (optionnel, défaut=0) : Nombre de mesures à sauter (pour pagination)
- `limit` (optionnel, défaut=50, max=200) : Nombre de mesures à retourner
- `measurement_type` (optionnel) : Filtrer par type (`temperature`, `humidity`, `ph`, `exudate`)
- `start_date` (optionnel) : Date de début (format ISO)
- `end_date` (optionnel) : Date de fin (format ISO)

### ⚙️ Ce que fait la route

1. **Vérifie les permissions**
   - Si patient : vérifie que `patient_id` correspond à l'utilisateur connecté
   - Si médecin : vérifie dans `medecin_patients` que c'est bien son patient
   - Si admin : accès autorisé

2. **Trouve les pansements du patient**
   - Cherche dans `patient_devices` tous les pansements actifs du patient
   - Si aucun pansement → Retourne une liste vide

3. **Récupère les mesures**
   - Cherche toutes les mesures de ces pansements
   - Applique les filtres (type, dates) si fournis
   - Trie par date décroissante (plus récentes en premier)

4. **Pagination**
   - Saut les `skip` premières mesures
   - Limite à `limit` mesures
   - Compte le total de mesures (sans pagination)

5. **Enrichit les données**
   - Ajoute le nom du patient
   - Ajoute le numéro de série du pansement
   - Convertit les types de mesures en enum

### 📤 Réponse
```json
{
  "measurements": [
    {
      "id": "7b5763d8-160a-45aa-b35b-1661b88f97d4",
      "device_id": "0a008b59-fac6-4b9a-b50a-0a17d561f12a",
      "measurement_type": "temperature",
      "value": 36.8,
      "unit": "°C",
      "quality_score": 95,
      "timestamp": "2025-12-05T10:47:40.683149Z",
      "device_serial": "PANS-00001234",
      "patient_id": "1df48cb6-fc92-4221-a4f3-49f3baf6845a",
      "patient_name": "Marie Dupont"
    },
    // ... autres mesures
  ],
  "total": 74,        // Nombre total de mesures (sans pagination)
  "page": 1,          // Page actuelle
  "per_page": 50      // Nombre de mesures par page
}
```

### ✅ Cas d'usage
- Un médecin consulte l'historique complet d'un patient
- Un patient veut voir ses mesures des 7 derniers jours
- Filtrer uniquement les mesures de température

---

## 🟡 Route 3 : `GET /api/v1/measurements/latest/{patient_id}`

### 📝 Description
**Dernière mesure d'un patient** - Cette route retourne la mesure la plus récente d'un patient.

### 🎯 Objectif
Obtenir rapidement la dernière mesure d'un patient sans avoir à charger tout l'historique.

### 🔐 Authentification
**Authentification requise** avec les mêmes permissions que la route 2 (historique).

### 📥 Paramètres de l'URL
- `patient_id` (obligatoire) : ID du patient (UUID)
- `measurement_type` (optionnel) : Si fourni, retourne la dernière mesure de ce type spécifique

### ⚙️ Ce que fait la route

1. **Vérifie les permissions** (identique à la route 2)

2. **Trouve les pansements du patient**

3. **Récupère la dernière mesure**
   - Si `measurement_type` est fourni : dernière mesure de ce type
   - Sinon : dernière mesure toutes catégories confondues
   - Trie par `timestamp` décroissant et prend la première

4. **Enrichit les données** (identique à la route 2)

### 📤 Réponse
```json
{
  "id": "7b5763d8-160a-45aa-b35b-1661b88f97d4",
  "device_id": "0a008b59-fc92-4221-a4f3-49f3baf6845a",
  "measurement_type": "temperature",
  "value": 36.8,
  "unit": "°C",
  "quality_score": 95,
  "timestamp": "2025-12-05T10:47:40.683149Z",
  "device_serial": "PANS-00001234",
  "patient_id": "1df48cb6-fc92-4221-a4f3-49f3baf6845a",
  "patient_name": "Marie Dupont"
}
```

### ✅ Cas d'usage
- Afficher la dernière température d'un patient sur un tableau de bord
- Vérifier rapidement l'état actuel d'un patient
- Obtenir la dernière mesure d'un type spécifique (ex: dernière température)

---

## 🟣 Route 4 : `GET /api/v1/measurements/stats/{patient_id}`

### 📝 Description
**Statistiques des mesures d'un patient** - Cette route calcule des statistiques (moyenne, min, max, tendance) sur une période donnée.

### 🎯 Objectif
Fournir une vue d'ensemble des mesures d'un patient avec des analyses statistiques pour aider au diagnostic.

### 🔐 Authentification
**Authentification requise** avec les mêmes permissions que les routes précédentes.

### 📥 Paramètres de l'URL
- `patient_id` (obligatoire) : ID du patient (UUID)
- `days` (optionnel, défaut=7, min=1, max=90) : Nombre de jours d'historique à analyser

### ⚙️ Ce que fait la route

1. **Vérifie les permissions** (identique aux autres routes)

2. **Trouve le patient et ses pansements**

3. **Calcule la période**
   - `end_date` = maintenant
   - `start_date` = maintenant - `days` jours

4. **Calcule les statistiques par type de mesure**
   Pour chaque type (temperature, humidity, ph, exudate) :
   - **Count** : Nombre de mesures
   - **Avg** : Moyenne des valeurs
   - **Min** : Valeur minimale
   - **Max** : Valeur maximale
   - **Latest value** : Dernière valeur mesurée
   - **Latest timestamp** : Date/heure de la dernière mesure
   - **Trend** : Tendance (calculée en comparant la moyenne de la première moitié de la période avec la deuxième moitié)
     - `increasing` : Augmentation de plus de 5%
     - `decreasing` : Diminution de plus de 5%
     - `stable` : Variation inférieure à 5%

5. **Calcule la tendance**
   - Divise la période en deux moitiés
   - Compare la moyenne de la première moitié avec la deuxième moitié
   - Détermine si la valeur augmente, diminue ou reste stable

### 📤 Réponse
```json
{
  "patient_id": "1df48cb6-fc92-4221-a4f3-49f3baf6845a",
  "patient_name": "Marie Dupont",
  "device_serial": "PANS-00001234",
  "total_measurements": 74,
  "date_range": {
    "start": "2025-11-28T11:35:37.605148",
    "end": "2025-12-05T11:35:37.605148"
  },
  "stats_by_type": [
    {
      "measurement_type": "temperature",
      "count": 74,
      "avg": 36.76,
      "min": 36.5,
      "max": 36.99,
      "latest_value": 36.8,
      "latest_timestamp": "2025-12-05T10:47:40.683149Z",
      "trend": "stable"
    }
  ]
}
```

### ✅ Cas d'usage
- Un médecin veut voir l'évolution de la température d'un patient sur 7 jours
- Détecter des tendances (fièvre qui monte/descend)
- Avoir une vue d'ensemble pour un rapport médical
- Comparer les statistiques entre différentes périodes

---

## 📊 Résumé des routes

| Route | Méthode | Description | Auth | Permissions |
|-------|---------|-------------|------|-------------|
| `/api/v1/measurements` | POST | Créer une mesure | ❌ Non | Public (pansement IoT) |
| `/api/v1/measurements/patient/{id}` | GET | Historique mesures | ✅ Oui | Admin, Médecin, Patient (ses propres) |
| `/api/v1/measurements/latest/{id}` | GET | Dernière mesure | ✅ Oui | Admin, Médecin, Patient (ses propres) |
| `/api/v1/measurements/stats/{id}` | GET | Statistiques | ✅ Oui | Admin, Médecin, Patient (ses propres) |

---

## 🔍 Détails techniques

### Types de mesures supportés
- `temperature` : Température corporelle (°C)
- `humidity` : Humidité (%)
- `ph` : Niveau de pH
- `exudate` : Quantité d'exsudat

### Pagination
- `skip` : Nombre d'éléments à sauter
- `limit` : Nombre d'éléments à retourner (max 200)
- `page` : Numéro de page calculé automatiquement

### Filtres disponibles
- Par type de mesure
- Par date de début
- Par date de fin
- Par nombre de jours (pour les statistiques)

### Gestion des erreurs
- **400 Bad Request** : Paramètres invalides (UUID mal formé, etc.)
- **401 Unauthorized** : Token manquant ou invalide
- **403 Forbidden** : Permissions insuffisantes
- **404 Not Found** : Patient, pansement ou mesure introuvable
- **500 Internal Server Error** : Erreur serveur (base de données, etc.)

---

**Document créé pour faciliter la compréhension de l'API de mesures ! 📚**

