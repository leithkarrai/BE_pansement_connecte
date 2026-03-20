# Index Documentation Technique Mobile

Ce document sert de plan rapide pour la partie mobile dans le dossier de recette.  
Il résume l’architecture Flutter, les dépendances clés, les parcours BLE/NFC, la sécurité et les tests de validation.

## 1) Contexte technique mobile

- **Framework**: Flutter (Dart)
- **State management**: Riverpod
- **Client HTTP**: Dio
- **Stockage local**:
  - `flutter_secure_storage` (token/auth)
  - `shared_preferences` (config non sensible, ex: URL backend)
- **Communication dispositif**:
  - BLE: `flutter_blue_plus` + `flutter_reactive_ble`
  - NFC: `nfc_manager` (+ `nfc_manager_ndef`)
- **Notifications**: `flutter_local_notifications` + `timezone`
- **Visualisation**: `fl_chart`

Source dépendances: `pubspec.yaml`.

## 2) Démarrage application et cycle de vie

### `lib/main.dart`

- Initialisation Flutter (`WidgetsFlutterBinding.ensureInitialized()`).
- Demande des permissions BLE/location au démarrage (Android).
- Initialisation notifications locales.
- Chargement de l’URL backend depuis `ApiConfig`.
- Injection Riverpod (`ProviderScope`).
- Observer lifecycle pour stopper le scan BLE en arrière-plan:
  - évite erreurs de canal Flutter fermé,
  - réduit consommation et instabilités.

## 3) Architecture interne (mobile)

### 3.1 Models

Exemples: `User`, `Device`, `Measurement`, `Alert`, `Comment` (`lib/models/`).

Rôle:
- typage métier côté UI,
- parsing structuré des réponses backend,
- meilleure maintenabilité que des maps dynamiques.

### 3.2 Services

Exemples: `api_service.dart`, `auth_service.dart`, `ble_service.dart`, `nfc_service.dart`, `notification_service.dart`.

Rôle:
- encapsuler la logique technique (réseau, BLE, NFC, auth, notifications),
- éviter d’alourdir les écrans.

### 3.3 Providers (Riverpod)

Exemples: `auth_provider.dart`, `ble_provider.dart`, `measurements_provider.dart`, `alerts_provider.dart`, `comments_provider.dart`, `nfc_provider.dart`.

Rôle:
- centraliser l’état applicatif,
- exposer les actions (login, scan, chargement données),
- propager l’état vers l’UI.

## 4) API et sécurité côté mobile

### `lib/services/api_service.dart`

- Initialisation Dio avec URL dynamique (`ApiConfig`).
- Interceptor d’ajout automatique du header `Authorization: Bearer ...`.
- Timeout réseau et normalisation des messages d’erreur FastAPI.
- Méthodes utilitaires de test de disponibilité backend (`/health`).

### Auth mobile (services + providers)

- `AuthService` gère login/logout/session.
- `AuthProvider` expose l’état `isLoading`, `user`, `error`.
- Le token est conservé côté stockage sécurisé (via `flutter_secure_storage`).

## 5) BLE (canal principal)

### `lib/services/ble_service.dart`

- Scan BLE avec timeout.
- Connexion device avec stabilisation GATT (délais, MTU, retries).
- Découverte service/caractéristique (UUID pansement + fallback Nordic NUS).
- Activation notifications (`setNotifyValue`) et écoute continue des paquets.
- Gestion robustesse:
  - déconnexions,
  - nettoyage des subscriptions,
  - messages d’erreur explicites.

Points importants recette:
- Bluetooth activé + permissions accordées.
- Device visible au scan.
- Notification characteristic correctement trouvée.

## 6) NFC (facilitateur de pairing)

### `lib/services/nfc_service.dart`

- Vérification disponibilité NFC.
- Session de détection tag (`startSession`).
- Déclenchement d’un callback au tag détecté pour lancer le flux BLE.
- V1: NFC sert de déclencheur UX, pas de transport principal de mesures.

## 7) Navigation et écrans

Écrans principaux (`lib/screens/`):
- Auth: login, register, forgot password.
- Dashboards: admin, médecin, patient.
- BLE/NFC: scan, device connection, nfc pairing/test.
- Suivi clinique: mesures, alertes, commentaires, détail patient/device.
- Paramètres: settings, sécurité, support.

Principe:
- écrans = présentation + interactions utilisateur,
- logique technique déportée dans services/providers.

## 8) Algorithme état de plaie (mobile)

### `lib/utils/wound_status_helper.dart`

- Évaluation principale basée sur impédance par bandes de fréquence.
- Ratio par bande: `R = Zplaie / Zpeau_saine_fixe`.
- Seuils métier:
  - écart > 10% => plaie,
  - écart > 20% => plaie infectée.
- Agrégation par bandes (basse/moyenne/haute).
- Fallback possible sur indicateurs classiques si besoin.

### `lib/screens/patient_wound_status_screen.dart`

- Vue patient: statut simplifié (ex: normal / à surveiller / critique).
- Vue médecin: détails supplémentaires possibles (ratios par bande).

## 9) Notifications locales

### `lib/services/notification_service.dart`

- Initialisation canaux au démarrage.
- Déclenchement local selon événements applicatifs (alertes/rappels).
- Gestion timezone pour programmations cohérentes.

## 10) Configuration et environnement

### `lib/config/api_config.dart`

- URL backend configurable (utile en dev/réseau local).
- Persistance locale de l’URL sélectionnée.
- Endpoints centralisés.

### Dépendances Flutter

- Équivalent `requirements.txt` pour Flutter:
  - `pubspec.yaml` (dépendances déclarées),
  - `pubspec.lock` (versions résolues, à versionner).

## 11) Plan de tests mobile (recette)

- **Auth**: login/logout, erreurs identifiants, session persistante.
- **API**: backend injoignable, timeout, messages d’erreur affichés.
- **BLE**: scan -> connexion -> réception données -> déconnexion/reconnexion.
- **NFC**: détection tag -> redirection flux pairing BLE.
- **Rôles UI**: patient/médecin/admin voient les bons écrans/actions.
- **Alertes/commentaires**: affichage conforme au rôle, cohérence backend.
- **État de plaie**: classification attendue selon jeux de mesures de test.
- **Lifecycle**: passage arrière-plan/avant-plan sans crash BLE.

## 12) Points de vigilance pour amélioration

- Renforcer validation des fichiers/images côté mobile + backend.
- Ajouter tests automatisés (unitaires providers/services + widget tests).
- Uniformiser encore les messages d’erreur utilisateur.
- Ajouter métriques de fiabilité BLE (taux de connexion, latence notif).
