# 🗄️ BASE DE DONNÉES PostgreSQL - Pansement Connecté

Documentation complète pour démarrer et utiliser la base de données du système de pansement connecté.

---

## 📋 TABLE DES MATIÈRES

1. [Prérequis](#prérequis)
2. [Installation Rapide](#installation-rapide)
3. [Structure de la Base](#structure-de-la-base)
4. [Comptes de Test](#comptes-de-test)
5. [Requêtes Utiles](#requêtes-utiles)
6. [Connexion depuis votre Backend](#connexion-depuis-votre-backend)
7. [Maintenance](#maintenance)
8. [Troubleshooting](#troubleshooting)

---

## ✅ PRÉREQUIS

### Option A : Avec Docker (Recommandé)
```bash
# Docker & Docker Compose installés
docker --version  # Doit afficher v20.10+
docker-compose --version  # Doit afficher v2.0+
```

### Option B : Sans Docker (Installation locale)
```bash
# PostgreSQL 15+
psql --version  # Doit afficher PostgreSQL 15 ou supérieur
```

---

## 🚀 INSTALLATION RAPIDE

### Méthode 1 : Docker Compose (RECOMMANDÉ)

```bash
# 1. Créer un dossier pour le projet
mkdir pansement-connecte-db
cd pansement-connecte-db

# 2. Placer les fichiers
# - docker-compose.yml
# - init_database.sql

# 3. Démarrer tous les services
docker-compose up -d

# 4. Vérifier que tout est OK
docker-compose ps

# Résultat attendu:
# NAME                    STATUS              PORTS
# pansement_postgres      Up (healthy)        0.0.0.0:5432->5432/tcp
# pansement_influxdb      Up (healthy)        0.0.0.0:8086->8086/tcp
# pansement_redis         Up (healthy)        0.0.0.0:6379->6379/tcp
# pansement_pgadmin       Up                  0.0.0.0:5050->80/tcp
# pansement_minio         Up (healthy)        0.0.0.0:9000-9001->9000-9001/tcp

# 5. La base de données est automatiquement initialisée ! ✅
```

#### Accès aux interfaces web (dev)

```
┌─────────────────────────────────────────────────────────────┐
│ 🌐 pgAdmin (PostgreSQL)                                     │
│ URL: http://localhost:5050                                  │
│ Email: admin@pansement-connecte.com                         │
│ Pass: admin_password_change_me                              │
├─────────────────────────────────────────────────────────────┤
│ 🌐 InfluxDB UI                                              │
│ URL: http://localhost:8086                                  │
│ User: admin                                                 │
│ Pass: influx_password_change_me                             │
├─────────────────────────────────────────────────────────────┤
│ 🌐 Redis Commander                                          │
│ URL: http://localhost:8081                                  │
├─────────────────────────────────────────────────────────────┤
│ 🌐 MinIO Console (S3-like)                                  │
│ URL: http://localhost:9001                                  │
│ User: minioadmin                                            │
│ Pass: minioadmin_password_change_me                         │
└─────────────────────────────────────────────────────────────┘
```

### Méthode 2 : Installation Locale PostgreSQL

```bash
# 1. Créer la base de données
createdb pansement_connecte

# 2. Exécuter le script d'initialisation
psql -U postgres -d pansement_connecte -f init_database.sql

# Résultat attendu:
# CREATE TYPE
# CREATE TABLE
# CREATE INDEX
# ...
# ╔════════════════════════════════════════════════════════╗
# ║   BASE DE DONNÉES INITIALISÉE AVEC SUCCÈS ✅          ║
# ╠════════════════════════════════════════════════════════╣
# ║ Users total       :   6 ( 3 patients,  2 médecins)    ║
# ║ Devices           :   4                                ║
# ║ Measurements      : 146                                ║
# ║ Alerts            :   2                                ║
# ╚════════════════════════════════════════════════════════╝
```

---

## 📊 STRUCTURE DE LA BASE

### Tables Principales (9)

```
┌──────────────────────┬────────────────────────────────────────┐
│ Table                │ Description                            │
├──────────────────────┼────────────────────────────────────────┤
│ users                │ Tous les utilisateurs (3 rôles)        │
│ devices              │ Pansements physiques (ID unique)       │
│ patient_devices      │ ⭐ LIEN CLÉ: Device ↔ Patient         │
│ medecin_patients     │ Relations Médecin ↔ Patients          │
│ measurements         │ Mesures capteurs (temp, imp, ORP)     │
│ alerts               │ Historique des alertes                 │
│ wound_photos         │ Photos suivi plaie                     │
│ medical_notes        │ Notes médicales des médecins           │
│ audit_logs           │ Traçabilité complète (RGPD)           │
└──────────────────────┴────────────────────────────────────────┘
```

### Relations Clés

```
users (patient) ←──┐
                   ├──→ patient_devices ←── devices
users (medecin) ←──┘
                   
patient_devices ──→ measurements
patient_devices ──→ alerts
patient_devices ──→ wound_photos
```

### Types Énumérés

```sql
user_role:       'patient', 'medecin', 'admin'
device_status:   'active', 'inactive', 'maintenance', 'retired'
wound_type:      'chirurgicale', 'brulure', 'chronique', 'traumatique', 'autre'
alert_severity:  'info', 'warning', 'critical'
alert_type:      'temperature', 'impedance', 'orp', 'infection', 'battery', 'device_error'
```

---

## 👥 COMPTES DE TEST

### Admin

```
Email: admin@pansement-connecte.com
Mot de passe: password123 (à hasher avec bcrypt)
Rôle: admin
Accès: TOUT le système
```

### Médecins

```
┌────────────────────────────────────────────────────────┐
│ Dr. Jean Martin                                        │
├────────────────────────────────────────────────────────┤
│ Email: dr.martin@hopital.fr                            │
│ Pass: password123                                      │
│ Patients: Marie Dupont, Paul Bernard                   │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│ Dr. Sophie Dubois                                      │
├────────────────────────────────────────────────────────┤
│ Email: dr.dubois@clinique.fr                           │
│ Pass: password123                                      │
│ Patients: Claire Petit                                 │
└────────────────────────────────────────────────────────┘
```

### Patients

```
┌────────────────────────────────────────────────────────┐
│ Marie Dupont (52 ans)                                  │
├────────────────────────────────────────────────────────┤
│ Email: marie.dupont@email.com                          │
│ Pass: password123                                      │
│ Pansement: PANS-00001234                               │
│ Plaie: Chirurgicale, jambe droite                      │
│ État: Cicatrisation normale ✅                         │
│ Mesures: ~73 sur 3 jours                               │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│ Paul Bernard (39 ans)                                  │
├────────────────────────────────────────────────────────┤
│ Email: paul.bernard@email.com                          │
│ Pass: password123                                      │
│ Pansement: PANS-00001235                               │
│ Plaie: Brûlure, avant-bras gauche                      │
│ État: Début infection possible ⚠️                      │
│ Alertes: 2 (warning + critical)                        │
│ Mesures: ~73 sur 3 jours (dégradation progressive)    │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│ Claire Petit (34 ans)                                  │
├────────────────────────────────────────────────────────┤
│ Email: claire.petit@email.com                          │
│ Pass: password123                                      │
│ Pansement: Aucun (pas encore assigné)                  │
└────────────────────────────────────────────────────────┘
```

**⚠️ IMPORTANT:** Les mots de passe dans le script SQL sont des exemples. 
En production, utilisez bcrypt pour hasher les mots de passe:

```javascript
// Node.js
const bcrypt = require('bcrypt');
const hash = await bcrypt.hash('password123', 10);
console.log(hash);  // $2b$10$...
```

---

## 🔍 REQUÊTES UTILES

### Connexion à la base

```bash
# Via Docker
docker exec -it pansement_postgres psql -U postgres -d pansement_connecte

# Installation locale
psql -U postgres -d pansement_connecte
```

### Requêtes Essentielles

#### 1. Lister tous les patients actifs avec leur pansement

```sql
SELECT * FROM v_active_patients;

-- Ou version détaillée:
SELECT 
    u.first_name || ' ' || u.last_name AS patient,
    u.email,
    d.device_id,
    pd.wound_type,
    pd.application_date,
    COUNT(DISTINCT a.id) FILTER (WHERE a.resolved_at IS NULL) AS alertes_actives
FROM users u
JOIN patient_devices pd ON u.id = pd.patient_id
JOIN devices d ON pd.device_id = d.id
LEFT JOIN alerts a ON u.id = a.patient_id
WHERE u.role = 'patient' AND pd.is_active = TRUE
GROUP BY u.id, d.id, pd.id;
```

#### 2. Dernière mesure d'un patient

```sql
-- Via fonction
SELECT * FROM get_latest_measurement(
    (SELECT id FROM users WHERE email = 'marie.dupont@email.com')
);

-- Ou requête directe
SELECT 
    m.temperature,
    m.impedance,
    m.orp,
    m.infection_score,
    m.measured_at
FROM measurements m
JOIN patient_devices pd ON m.patient_device_id = pd.id
WHERE pd.patient_id = (SELECT id FROM users WHERE email = 'marie.dupont@email.com')
  AND pd.is_active = TRUE
ORDER BY m.measured_at DESC
LIMIT 1;
```

#### 3. Historique des mesures (graphique 24h)

```sql
SELECT 
    DATE_TRUNC('hour', measured_at) AS hour,
    AVG(temperature) AS temp_avg,
    AVG(impedance) AS imp_avg,
    AVG(orp) AS orp_avg,
    AVG(infection_score) AS score_avg
FROM measurements m
JOIN patient_devices pd ON m.patient_device_id = pd.id
WHERE pd.patient_id = (SELECT id FROM users WHERE email = 'paul.bernard@email.com')
  AND measured_at > NOW() - INTERVAL '24 hours'
GROUP BY DATE_TRUNC('hour', measured_at)
ORDER BY hour;
```

#### 4. Patients d'un médecin

```sql
SELECT 
    u.first_name || ' ' || u.last_name AS patient,
    u.email,
    pd.wound_type,
    d.device_id,
    (SELECT COUNT(*) FROM alerts a 
     WHERE a.patient_id = u.id AND a.resolved_at IS NULL) AS alertes
FROM users medecin
JOIN medecin_patients mp ON medecin.id = mp.medecin_id
JOIN users u ON mp.patient_id = u.id
LEFT JOIN patient_devices pd ON u.id = pd.patient_id AND pd.is_active = TRUE
LEFT JOIN devices d ON pd.device_id = d.id
WHERE medecin.email = 'dr.martin@hopital.fr';
```

#### 5. Alertes critiques non résolues

```sql
SELECT * FROM v_critical_alerts;

-- Ou version détaillée
SELECT 
    a.triggered_at,
    u.first_name || ' ' || u.last_name AS patient,
    u.phone,
    a.title,
    a.message,
    a.current_value,
    a.threshold_value
FROM alerts a
JOIN users u ON a.patient_id = u.id
WHERE a.severity = 'critical'
  AND a.resolved_at IS NULL
ORDER BY a.triggered_at DESC;
```

#### 6. Statistiques par médecin

```sql
SELECT * FROM v_medecin_stats;
```

#### 7. Calculer baseline impédance après 24h

```sql
-- Pour un patient spécifique
SELECT calculate_baseline_impedance(
    (SELECT id FROM patient_devices 
     WHERE patient_id = (SELECT id FROM users WHERE email = 'marie.dupont@email.com')
     AND is_active = TRUE)
);

-- Mettre à jour la baseline
UPDATE patient_devices
SET baseline_impedance = calculate_baseline_impedance(id)
WHERE id = (
    SELECT id FROM patient_devices 
    WHERE patient_id = (SELECT id FROM users WHERE email = 'marie.dupont@email.com')
    AND is_active = TRUE
);
```

#### 8. Assigner un pansement à un patient

```sql
-- 1. Vérifier qu'un device est disponible
SELECT device_id, status 
FROM devices 
WHERE status = 'inactive' 
LIMIT 5;

-- 2. Créer l'association
INSERT INTO patient_devices 
    (patient_id, device_id, wound_type, wound_location, application_date)
VALUES (
    (SELECT id FROM users WHERE email = 'claire.petit@email.com'),
    (SELECT id FROM devices WHERE device_id = 'PANS-00001236'),
    'chronique',
    'Pied gauche, talon',
    CURRENT_TIMESTAMP
);

-- 3. Activer le device
UPDATE devices 
SET status = 'active' 
WHERE device_id = 'PANS-00001236';
```

#### 9. Ajouter une mesure

```sql
INSERT INTO measurements 
    (device_id, patient_device_id, temperature, impedance, orp, 
     battery_level, signal_quality, infection_score, measured_at)
VALUES (
    (SELECT id FROM devices WHERE device_id = 'PANS-00001234'),
    (SELECT id FROM patient_devices 
     WHERE device_id = (SELECT id FROM devices WHERE device_id = 'PANS-00001234')
     AND is_active = TRUE),
    36.8,
    455,
    315,
    82,
    95,
    18,
    CURRENT_TIMESTAMP
);
```

#### 10. Audit - Actions d'un utilisateur

```sql
SELECT 
    action,
    entity_type,
    ip_address,
    created_at
FROM audit_logs
WHERE user_id = (SELECT id FROM users WHERE email = 'dr.martin@hopital.fr')
ORDER BY created_at DESC
LIMIT 50;
```

---

## 🔌 CONNEXION DEPUIS VOTRE BACKEND

### Node.js (avec Sequelize ORM)

```javascript
// config/database.js
const { Sequelize } = require('sequelize');

const sequelize = new Sequelize({
    dialect: 'postgres',
    host: 'localhost',  // ou 'postgres' si dans Docker
    port: 5432,
    database: 'pansement_connecte',
    username: 'postgres',
    password: 'postgres_password_change_me',
    logging: false,  // ou console.log pour debug
    pool: {
        max: 10,
        min: 0,
        acquire: 30000,
        idle: 10000
    }
});

// Test connexion
sequelize.authenticate()
    .then(() => console.log('✅ Connexion PostgreSQL OK'))
    .catch(err => console.error('❌ Erreur connexion:', err));

module.exports = sequelize;
```

### Node.js (avec pg - driver natif)

```javascript
// config/database.js
const { Pool } = require('pg');

const pool = new Pool({
    host: 'localhost',
    port: 5432,
    database: 'pansement_connecte',
    user: 'postgres',
    password: 'postgres_password_change_me',
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 2000,
});

// Test connexion
pool.query('SELECT NOW()', (err, res) => {
    if (err) {
        console.error('❌ Erreur connexion:', err);
    } else {
        console.log('✅ Connexion PostgreSQL OK:', res.rows[0].now);
    }
});

module.exports = pool;
```

### Python (avec psycopg2)

```python
# config/database.py
import psycopg2
from psycopg2 import pool

# Pool de connexions
connection_pool = psycopg2.pool.SimpleConnectionPool(
    1, 20,
    host='localhost',
    port=5432,
    database='pansement_connecte',
    user='postgres',
    password='postgres_password_change_me'
)

# Test connexion
def test_connection():
    conn = connection_pool.getconn()
    try:
        cur = conn.cursor()
        cur.execute('SELECT NOW()')
        result = cur.fetchone()
        print(f'✅ Connexion PostgreSQL OK: {result[0]}')
        cur.close()
    except Exception as e:
        print(f'❌ Erreur connexion: {e}')
    finally:
        connection_pool.putconn(conn)

test_connection()
```

### String de connexion (environnement)

```bash
# .env
DATABASE_URL=postgresql://postgres:postgres_password_change_me@localhost:5432/pansement_connecte

# Avec SSL (production)
DATABASE_URL=postgresql://postgres:password@db.example.com:5432/pansement_connecte?sslmode=require
```

---

## 🔧 MAINTENANCE

### Backup de la base

```bash
# Backup complet
docker exec pansement_postgres pg_dump -U postgres pansement_connecte > backup_$(date +%Y%m%d).sql

# Ou sans Docker
pg_dump -U postgres pansement_connecte > backup_$(date +%Y%m%d).sql

# Backup uniquement les données (pas le schéma)
pg_dump -U postgres --data-only pansement_connecte > data_backup_$(date +%Y%m%d).sql
```

### Restauration

```bash
# Restaurer backup
docker exec -i pansement_postgres psql -U postgres pansement_connecte < backup_20241202.sql

# Ou sans Docker
psql -U postgres pansement_connecte < backup_20241202.sql
```

### Nettoyage des vieilles mesures

```sql
-- Supprimer mesures > 90 jours (à mettre dans un CRON)
DELETE FROM measurements 
WHERE measured_at < NOW() - INTERVAL '90 days';

-- Ou archiver dans une table séparée
CREATE TABLE measurements_archive AS 
SELECT * FROM measurements 
WHERE measured_at < NOW() - INTERVAL '90 days';

DELETE FROM measurements 
WHERE measured_at < NOW() - INTERVAL '90 days';
```

### Vacuum & Analyze (performance)

```sql
-- Nettoyer et optimiser
VACUUM ANALYZE measurements;
VACUUM ANALYZE alerts;

-- Ou toutes les tables
VACUUM ANALYZE;
```

### Statistiques de taille

```sql
-- Taille de chaque table
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Taille totale de la base
SELECT pg_size_pretty(pg_database_size('pansement_connecte'));
```

---

## 🐛 TROUBLESHOOTING

### Erreur: "database does not exist"

```bash
# Créer la base manuellement
docker exec -it pansement_postgres createdb -U postgres pansement_connecte

# Puis réexécuter le script
docker exec -i pansement_postgres psql -U postgres pansement_connecte < init_database.sql
```

### Erreur: "role does not exist"

```bash
# Créer l'utilisateur
docker exec -it pansement_postgres psql -U postgres -c "CREATE USER your_user WITH PASSWORD 'your_password';"
docker exec -it pansement_postgres psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE pansement_connecte TO your_user;"
```

### Réinitialiser complètement la base

```bash
# ATTENTION: Supprime toutes les données !
docker-compose down -v  # Supprime aussi les volumes
docker-compose up -d    # Recrée tout from scratch
```

### Connexion refusée depuis l'extérieur

```bash
# Vérifier que PostgreSQL écoute sur toutes les interfaces
docker exec -it pansement_postgres cat /var/lib/postgresql/data/postgresql.conf | grep listen_addresses

# Devrait être: listen_addresses = '*'
```

### Logs PostgreSQL

```bash
# Voir les logs en temps réel
docker logs -f pansement_postgres

# Dernières 100 lignes
docker logs --tail 100 pansement_postgres
```

---

## 📚 RESSOURCES SUPPLÉMENTAIRES

- **Documentation PostgreSQL:** https://www.postgresql.org/docs/15/
- **Sequelize ORM (Node.js):** https://sequelize.org/
- **psycopg2 (Python):** https://www.psycopg.org/
- **pgAdmin:** https://www.pgadmin.org/

---

## ✅ CHECKLIST DE DÉMARRAGE

- [ ] Docker & Docker Compose installés
- [ ] Fichiers `docker-compose.yml` et `init_database.sql` présents
- [ ] `docker-compose up -d` exécuté avec succès
- [ ] Tous les conteneurs sont "healthy" (`docker-compose ps`)
- [ ] Connexion à pgAdmin OK (http://localhost:5050)
- [ ] Base de données initialisée (6 users, 4 devices, ~146 measurements)
- [ ] Test de requête SQL réussi
- [ ] Connexion depuis le backend OK

**🎉 Si tout est coché, votre base de données est prête ! Vous pouvez maintenant développer votre backend API.**

---

## 🚀 PROCHAINES ÉTAPES

1. ✅ **Base de données** - TERMINÉ !
2. ⏭️ **Backend API** - Créer les routes REST avec Node.js/Express
3. ⏭️ **Authentication** - JWT + Permissions (patient/médecin/admin)
4. ⏭️ **App Mobile** - Flutter (Patient + Médecin)
5. ⏭️ **Tests** - Unit tests + Integration tests

---

**Besoin d'aide ?** 
- Consultez la documentation dans `ARCHITECTURE_GLOBALE_COMPLETE.md`
- Référez-vous au schéma BDD dans `Architecture_BDD_MultiRoles.md`