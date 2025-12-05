-- ============================================================================
-- SCRIPT D'INITIALISATION BASE DE DONNÉES PostgreSQL
-- Pansement Connecté - Système IoT Médical
-- ============================================================================
-- 
-- Ce script crée toutes les tables, index, contraintes et données de test
-- pour le système de pansement connecté.
--
-- Utilisation :
--   psql -U postgres -d pansement_connecte -f init_database.sql
--
-- ============================================================================

-- Nettoyage (si besoin de recommencer)
DROP TABLE IF EXISTS audit_logs CASCADE;
DROP TABLE IF EXISTS medical_notes CASCADE;
DROP TABLE IF EXISTS wound_photos CASCADE;
DROP TABLE IF EXISTS alerts CASCADE;
DROP TABLE IF EXISTS measurements CASCADE;
DROP TABLE IF EXISTS medecin_patients CASCADE;
DROP TABLE IF EXISTS patient_devices CASCADE;
DROP TABLE IF EXISTS devices CASCADE;
DROP TABLE IF EXISTS users CASCADE;

DROP TYPE IF EXISTS user_role CASCADE;
DROP TYPE IF EXISTS device_status CASCADE;
DROP TYPE IF EXISTS wound_type CASCADE;
DROP TYPE IF EXISTS alert_severity CASCADE;
DROP TYPE IF EXISTS alert_type CASCADE;
DROP TYPE IF EXISTS note_type CASCADE;

-- ============================================================================
-- TYPES ÉNUMÉRÉS
-- ============================================================================

CREATE TYPE user_role AS ENUM ('patient', 'medecin', 'admin');
CREATE TYPE device_status AS ENUM ('active', 'inactive', 'maintenance', 'retired');
CREATE TYPE wound_type AS ENUM ('chirurgicale', 'brulure', 'chronique', 'traumatique', 'autre');
CREATE TYPE alert_severity AS ENUM ('info', 'warning', 'critical');
CREATE TYPE alert_type AS ENUM ('temperature', 'impedance', 'orp', 'infection', 'battery', 'device_error');
CREATE TYPE note_type AS ENUM ('consultation', 'prescription', 'observation', 'autre');

-- ============================================================================
-- TABLE: users
-- Tous les utilisateurs du système (patients, médecins, admins)
-- ============================================================================

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role user_role NOT NULL,
    
    -- Informations personnelles
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    date_of_birth DATE,
    gender VARCHAR(10),
    
    -- Métadonnées système
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    profile_photo_url VARCHAR(500),
    
    -- Métadonnées médicales (pour patients)
    medical_record_number VARCHAR(50) UNIQUE,
    blood_type VARCHAR(5),
    allergies TEXT,
    chronic_conditions TEXT,
    
    -- Tokens (pour sessions)
    fcm_token VARCHAR(500),  -- Firebase Cloud Messaging
    refresh_token VARCHAR(500)
);

-- Index pour performance
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_medical_record ON users(medical_record_number) WHERE medical_record_number IS NOT NULL;
CREATE INDEX idx_users_active ON users(is_active) WHERE is_active = TRUE;

-- Trigger pour updated_at automatique
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE users IS 'Table principale des utilisateurs (patients, médecins, admins)';
COMMENT ON COLUMN users.role IS 'Rôle: patient, medecin ou admin';
COMMENT ON COLUMN users.medical_record_number IS 'Numéro dossier médical unique (patients uniquement)';

-- ============================================================================
-- TABLE: devices
-- Pansements connectés (cartes embarquées)
-- ============================================================================

CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Identification unique
    device_id VARCHAR(50) UNIQUE NOT NULL,  -- Ex: "PANS-00001234"
    mac_address VARCHAR(17) UNIQUE NOT NULL,  -- Adresse MAC BLE
    
    -- Versions firmware/hardware
    firmware_version VARCHAR(20),
    hardware_version VARCHAR(20),
    
    -- Informations fabrication
    manufacture_date DATE,
    batch_number VARCHAR(50),
    
    -- État du device
    status device_status DEFAULT 'inactive',
    battery_level INT CHECK (battery_level >= 0 AND battery_level <= 100),
    last_seen TIMESTAMP,
    
    -- Calibration
    calibration_date TIMESTAMP,
    calibration_data JSONB,  -- Paramètres calibration capteurs
    
    -- Métadonnées
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT
);

-- Index
CREATE INDEX idx_devices_device_id ON devices(device_id);
CREATE INDEX idx_devices_mac_address ON devices(mac_address);
CREATE INDEX idx_devices_status ON devices(status);
CREATE INDEX idx_devices_batch ON devices(batch_number);

-- Trigger updated_at
CREATE TRIGGER update_devices_updated_at BEFORE UPDATE ON devices
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE devices IS 'Pansements connectés (hardware physique)';
COMMENT ON COLUMN devices.device_id IS 'ID unique gravé sur la carte (ex: PANS-00001234)';
COMMENT ON COLUMN devices.mac_address IS 'Adresse MAC Bluetooth Low Energy';
COMMENT ON COLUMN devices.calibration_data IS 'JSON avec paramètres calibration des 3 capteurs';

-- ============================================================================
-- TABLE: patient_devices
-- ⭐ RELATION CLÉ : Association Device ↔ Patient
-- ============================================================================

CREATE TABLE patient_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Relations (clés étrangères)
    patient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    
    -- Informations sur la plaie
    wound_type wound_type,
    wound_location VARCHAR(100),  -- Ex: "Jambe droite, mollet"
    wound_size_cm2 DECIMAL(6,2),
    wound_depth_mm DECIMAL(4,1),
    
    -- Dates
    application_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expected_removal_date TIMESTAMP,
    actual_removal_date TIMESTAMP,
    
    -- Configuration des seuils d'alerte (personnalisables par patient)
    temp_threshold_high DECIMAL(4,2) DEFAULT 37.5,
    temp_threshold_low DECIMAL(4,2) DEFAULT 32.0,
    impedance_variation_threshold INT DEFAULT 20,  -- en %
    orp_threshold_low INT DEFAULT 150,  -- en mV
    
    -- Baseline impédance (calculée sur 24h après pose)
    baseline_impedance INT,
    
    -- Notes médicales liées à l'application
    prescription TEXT,
    notes TEXT,
    
    -- État
    is_active BOOLEAN DEFAULT TRUE,
    
    -- Métadonnées
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Contrainte: un device actif ne peut être assigné qu'à un seul patient
    UNIQUE (device_id, is_active)
);

-- Index pour requêtes fréquentes
CREATE INDEX idx_patient_devices_patient ON patient_devices(patient_id);
CREATE INDEX idx_patient_devices_device ON patient_devices(device_id);
CREATE INDEX idx_patient_devices_active ON patient_devices(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_patient_devices_patient_active ON patient_devices(patient_id, is_active);

-- Trigger updated_at
CREATE TRIGGER update_patient_devices_updated_at BEFORE UPDATE ON patient_devices
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE patient_devices IS '⭐ TABLE CLÉ: Association pansement ↔ patient avec config plaie';
COMMENT ON COLUMN patient_devices.baseline_impedance IS 'Impédance baseline calculée sur 24h initiales';
COMMENT ON COLUMN patient_devices.is_active IS 'Un seul device actif par patient à la fois';

-- ============================================================================
-- TABLE: medecin_patients
-- Relation Médecin ↔ Patients
-- ============================================================================

CREATE TABLE medecin_patients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    medecin_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    patient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    assigned_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_primary BOOLEAN DEFAULT TRUE,  -- Médecin traitant principal
    
    notes TEXT,  -- Notes du médecin sur ce patient
    
    -- Contrainte unicité
    UNIQUE (medecin_id, patient_id)
);

-- Index
CREATE INDEX idx_medecin_patients_medecin ON medecin_patients(medecin_id);
CREATE INDEX idx_medecin_patients_patient ON medecin_patients(patient_id);
CREATE INDEX idx_medecin_patients_primary ON medecin_patients(medecin_id, is_primary) WHERE is_primary = TRUE;

COMMENT ON TABLE medecin_patients IS 'Association médecins ↔ patients (qui soigne qui)';
COMMENT ON COLUMN medecin_patients.is_primary IS 'Médecin traitant principal (vs consultant)';

-- ============================================================================
-- TABLE: measurements
-- Mesures des capteurs (peut être migrée vers InfluxDB si volume trop élevé)
-- ============================================================================

CREATE TABLE measurements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    patient_device_id UUID NOT NULL REFERENCES patient_devices(id) ON DELETE CASCADE,
    
    -- Timestamps
    measured_at TIMESTAMP NOT NULL,  -- Timestamp de la mesure (device)
    received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,  -- Timestamp réception serveur
    
    -- Données capteurs
    temperature DECIMAL(4,2),  -- en °C
    impedance INT,  -- en Ω
    orp INT,  -- en mV (potentiel redox)
    
    -- Métadonnées mesure
    battery_level INT CHECK (battery_level >= 0 AND battery_level <= 100),
    signal_quality INT CHECK (signal_quality >= 0 AND signal_quality <= 100),
    
    -- Score calculé (par algorithme backend)
    infection_score INT CHECK (infection_score >= 0 AND infection_score <= 100),
    
    -- Flags
    is_anomaly BOOLEAN DEFAULT FALSE,
    anomaly_reason TEXT
);

-- Index CRITIQUES pour performance (time-series)
CREATE INDEX idx_measurements_device_time ON measurements(device_id, measured_at DESC);
CREATE INDEX idx_measurements_patient_device_time ON measurements(patient_device_id, measured_at DESC);
CREATE INDEX idx_measurements_measured_at ON measurements(measured_at DESC);
CREATE INDEX idx_measurements_infection_score ON measurements(infection_score) WHERE infection_score > 50;

-- Partitionnement par mois (recommandé pour production)
-- CREATE TABLE measurements_2024_12 PARTITION OF measurements
--     FOR VALUES FROM ('2024-12-01') TO ('2025-01-01');

COMMENT ON TABLE measurements IS 'Mesures des 3 capteurs (temp, impédance, ORP)';
COMMENT ON COLUMN measurements.infection_score IS 'Score 0-100 calculé par algo backend';
COMMENT ON COLUMN measurements.measured_at IS 'Timestamp de la mesure (horloge device)';
COMMENT ON COLUMN measurements.received_at IS 'Timestamp réception serveur (pour latence)';

-- ============================================================================
-- TABLE: alerts
-- Historique des alertes générées
-- ============================================================================

CREATE TABLE alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Relations
    patient_device_id UUID NOT NULL REFERENCES patient_devices(id) ON DELETE CASCADE,
    patient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    measurement_id UUID REFERENCES measurements(id) ON DELETE SET NULL,
    
    -- Type et sévérité
    alert_type alert_type NOT NULL,
    severity alert_severity NOT NULL,
    
    -- Détails
    title VARCHAR(200) NOT NULL,
    message TEXT NOT NULL,
    
    -- Valeurs déclenchantes
    current_value DECIMAL(10,2),
    threshold_value DECIMAL(10,2),
    
    -- État de l'alerte
    triggered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    acknowledged_at TIMESTAMP,
    acknowledged_by UUID REFERENCES users(id) ON DELETE SET NULL,
    resolved_at TIMESTAMP,
    resolved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    resolution_note TEXT,
    
    -- Notification
    notification_sent BOOLEAN DEFAULT FALSE,
    notification_method VARCHAR(50),  -- 'push', 'sms', 'email'
    notification_sent_at TIMESTAMP
);

-- Index
CREATE INDEX idx_alerts_patient ON alerts(patient_id);
CREATE INDEX idx_alerts_device ON alerts(device_id);
CREATE INDEX idx_alerts_severity ON alerts(severity);
CREATE INDEX idx_alerts_triggered_at ON alerts(triggered_at DESC);
CREATE INDEX idx_alerts_unresolved ON alerts(patient_id, resolved_at) WHERE resolved_at IS NULL;
CREATE INDEX idx_alerts_critical ON alerts(patient_id, severity) WHERE severity = 'critical';

COMMENT ON TABLE alerts IS 'Historique des alertes (temperature, infection, batterie, etc.)';
COMMENT ON COLUMN alerts.acknowledged_at IS 'Moment où l\'alerte a été vue par le patient/médecin';
COMMENT ON COLUMN alerts.resolved_at IS 'Moment où l\'alerte a été résolue';

-- ============================================================================
-- TABLE: wound_photos
-- Photos de la plaie pour suivi visuel
-- ============================================================================

CREATE TABLE wound_photos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    patient_device_id UUID NOT NULL REFERENCES patient_devices(id) ON DELETE CASCADE,
    patient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- URLs stockage (S3, GCS, etc.)
    photo_url VARCHAR(500) NOT NULL,
    thumbnail_url VARCHAR(500),
    
    -- Métadonnées
    taken_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    uploaded_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    file_size_kb INT,
    dimensions VARCHAR(20),  -- Ex: "1920x1080"
    mime_type VARCHAR(50),
    
    -- Notes
    notes TEXT,
    
    -- ML/IA (optionnel)
    ai_analysis JSONB  -- Résultats analyse IA (classification, etc.)
);

-- Index
CREATE INDEX idx_wound_photos_patient_device ON wound_photos(patient_device_id);
CREATE INDEX idx_wound_photos_patient ON wound_photos(patient_id);
CREATE INDEX idx_wound_photos_taken_at ON wound_photos(taken_at DESC);

COMMENT ON TABLE wound_photos IS 'Photos suivi visuel de la plaie';
COMMENT ON COLUMN wound_photos.ai_analysis IS 'JSON résultats analyse IA (type plaie, progression, etc.)';

-- ============================================================================
-- TABLE: medical_notes
-- Notes médicales des médecins
-- ============================================================================

CREATE TABLE medical_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    patient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    medecin_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    patient_device_id UUID REFERENCES patient_devices(id) ON DELETE SET NULL,
    
    note_type note_type,
    title VARCHAR(200),
    content TEXT NOT NULL,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index
CREATE INDEX idx_medical_notes_patient ON medical_notes(patient_id);
CREATE INDEX idx_medical_notes_medecin ON medical_notes(medecin_id);
CREATE INDEX idx_medical_notes_created_at ON medical_notes(created_at DESC);

-- Trigger updated_at
CREATE TRIGGER update_medical_notes_updated_at BEFORE UPDATE ON medical_notes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE medical_notes IS 'Notes médicales des médecins sur leurs patients';

-- ============================================================================
-- TABLE: audit_logs
-- Traçabilité complète de toutes les actions (obligatoire dispositif médical)
-- ============================================================================

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,  -- Ex: "LOGIN", "VIEW_PATIENT_DATA"
    
    entity_type VARCHAR(50),  -- Ex: "patient", "measurement", "alert"
    entity_id UUID,
    
    ip_address VARCHAR(45),
    user_agent TEXT,
    
    -- Détails (optionnel)
    before_value JSONB,
    after_value JSONB,
    
    status_code INT,  -- HTTP status code
    error_message TEXT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index
CREATE INDEX idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_logs_user_time ON audit_logs(user_id, created_at DESC);

COMMENT ON TABLE audit_logs IS 'Traçabilité complète (qui, quand, quoi) - IMMUABLE';
COMMENT ON COLUMN audit_logs.before_value IS 'Valeur avant modification (JSON)';
COMMENT ON COLUMN audit_logs.after_value IS 'Valeur après modification (JSON)';

-- ============================================================================
-- FONCTIONS UTILITAIRES
-- ============================================================================

-- Fonction: Calculer baseline impédance
CREATE OR REPLACE FUNCTION calculate_baseline_impedance(p_patient_device_id UUID)
RETURNS INT AS $$
DECLARE
    v_baseline INT;
BEGIN
    -- Moyenne impédance sur 24h après application
    SELECT AVG(impedance)::INT INTO v_baseline
    FROM measurements
    WHERE patient_device_id = p_patient_device_id
      AND measured_at >= (
          SELECT application_date 
          FROM patient_devices 
          WHERE id = p_patient_device_id
      )
      AND measured_at <= (
          SELECT application_date + INTERVAL '24 hours'
          FROM patient_devices 
          WHERE id = p_patient_device_id
      );
    
    RETURN v_baseline;
END;
$$ LANGUAGE plpgsql;

-- Fonction: Obtenir dernière mesure d'un patient
CREATE OR REPLACE FUNCTION get_latest_measurement(p_patient_id UUID)
RETURNS TABLE (
    temperature DECIMAL,
    impedance INT,
    orp INT,
    infection_score INT,
    measured_at TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        m.temperature,
        m.impedance,
        m.orp,
        m.infection_score,
        m.measured_at
    FROM measurements m
    JOIN patient_devices pd ON m.patient_device_id = pd.id
    WHERE pd.patient_id = p_patient_id
      AND pd.is_active = TRUE
    ORDER BY m.measured_at DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Fonction: Compter alertes non résolues
CREATE OR REPLACE FUNCTION count_unresolved_alerts(p_patient_id UUID)
RETURNS INT AS $$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM alerts
    WHERE patient_id = p_patient_id
      AND resolved_at IS NULL;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VUES UTILES
-- ============================================================================

-- Vue: Patients actifs avec device
CREATE OR REPLACE VIEW v_active_patients AS
SELECT 
    u.id AS patient_id,
    u.first_name,
    u.last_name,
    u.email,
    u.phone,
    d.device_id,
    d.mac_address,
    d.battery_level,
    pd.wound_type,
    pd.wound_location,
    pd.application_date,
    pd.expected_removal_date,
    (SELECT COUNT(*) FROM alerts a WHERE a.patient_id = u.id AND a.resolved_at IS NULL) AS unresolved_alerts
FROM users u
JOIN patient_devices pd ON u.id = pd.patient_id
JOIN devices d ON pd.device_id = d.id
WHERE u.role = 'patient'
  AND u.is_active = TRUE
  AND pd.is_active = TRUE;

COMMENT ON VIEW v_active_patients IS 'Vue des patients actifs avec leur pansement';

-- Vue: Alertes critiques non résolues
CREATE OR REPLACE VIEW v_critical_alerts AS
SELECT 
    a.id AS alert_id,
    a.title,
    a.message,
    a.triggered_at,
    u.id AS patient_id,
    u.first_name,
    u.last_name,
    u.phone,
    d.device_id,
    a.current_value,
    a.threshold_value
FROM alerts a
JOIN users u ON a.patient_id = u.id
JOIN devices d ON a.device_id = d.id
WHERE a.severity = 'critical'
  AND a.resolved_at IS NULL
ORDER BY a.triggered_at DESC;

COMMENT ON VIEW v_critical_alerts IS 'Alertes critiques non résolues avec infos patient';

-- Vue: Statistiques par médecin
CREATE OR REPLACE VIEW v_medecin_stats AS
SELECT 
    u.id AS medecin_id,
    u.first_name,
    u.last_name,
    COUNT(DISTINCT mp.patient_id) AS nb_patients,
    COUNT(DISTINCT CASE WHEN pd.is_active THEN mp.patient_id END) AS nb_patients_actifs,
    COUNT(DISTINCT CASE WHEN a.severity = 'critical' AND a.resolved_at IS NULL THEN a.patient_id END) AS nb_patients_alerte_critique
FROM users u
LEFT JOIN medecin_patients mp ON u.id = mp.medecin_id
LEFT JOIN patient_devices pd ON mp.patient_id = pd.patient_id
LEFT JOIN alerts a ON mp.patient_id = a.patient_id
WHERE u.role = 'medecin'
  AND u.is_active = TRUE
GROUP BY u.id, u.first_name, u.last_name;

COMMENT ON VIEW v_medecin_stats IS 'Statistiques par médecin (nb patients, alertes, etc.)';

-- ============================================================================
-- DONNÉES DE TEST
-- ============================================================================

-- Insertion des données de test
-- ATTENTION: Mot de passe hashé avec bcrypt (à générer avec votre backend)
-- Exemple: bcrypt.hash('password123', 10) en Node.js

-- Admin
INSERT INTO users (email, password_hash, role, first_name, last_name, phone, is_active)
VALUES 
('admin@pansement-connecte.com', '$2b$10$ExampleHashForPassword123Admin', 'admin', 'Admin', 'System', '+33 1 23 45 67 89', TRUE);

-- Médecins
INSERT INTO users (email, password_hash, role, first_name, last_name, phone, is_active)
VALUES 
('dr.martin@hopital.fr', '$2b$10$ExampleHashForPassword123Doc1', 'medecin', 'Jean', 'Martin', '+33 6 11 22 33 44', TRUE),
('dr.dubois@clinique.fr', '$2b$10$ExampleHashForPassword123Doc2', 'medecin', 'Sophie', 'Dubois', '+33 6 22 33 44 55', TRUE);

-- Patients
INSERT INTO users (email, password_hash, role, first_name, last_name, phone, date_of_birth, gender, medical_record_number, blood_type, is_active)
VALUES 
('marie.dupont@email.com', '$2b$10$ExampleHashForPassword123Pat1', 'patient', 'Marie', 'Dupont', '+33 6 12 34 56 78', '1972-05-15', 'F', 'MED-2024-001', 'A+', TRUE),
('paul.bernard@email.com', '$2b$10$ExampleHashForPassword123Pat2', 'patient', 'Paul', 'Bernard', '+33 6 23 45 67 89', '1985-08-22', 'M', 'MED-2024-002', 'O+', TRUE),
('claire.petit@email.com', '$2b$10$ExampleHashForPassword123Pat3', 'patient', 'Claire', 'Petit', '+33 6 34 56 78 90', '1990-11-10', 'F', 'MED-2024-003', 'B+', TRUE);

-- Devices (pansements)
INSERT INTO devices (device_id, mac_address, firmware_version, hardware_version, manufacture_date, batch_number, status)
VALUES 
('PANS-00001234', 'AA:BB:CC:DD:EE:01', 'v1.0.2', 'hw-v1.0', '2024-10-15', 'BATCH-2024-10-A', 'active'),
('PANS-00001235', 'AA:BB:CC:DD:EE:02', 'v1.0.2', 'hw-v1.0', '2024-10-15', 'BATCH-2024-10-A', 'active'),
('PANS-00001236', 'AA:BB:CC:DD:EE:03', 'v1.0.2', 'hw-v1.0', '2024-10-15', 'BATCH-2024-10-A', 'inactive'),
('PANS-00001237', 'AA:BB:CC:DD:EE:04', 'v1.0.3', 'hw-v1.0', '2024-11-20', 'BATCH-2024-11-B', 'inactive');

-- Association médecin ↔ patients
INSERT INTO medecin_patients (medecin_id, patient_id, is_primary)
SELECT 
    (SELECT id FROM users WHERE email = 'dr.martin@hopital.fr'),
    id,
    TRUE
FROM users WHERE email IN ('marie.dupont@email.com', 'paul.bernard@email.com');

INSERT INTO medecin_patients (medecin_id, patient_id, is_primary)
SELECT 
    (SELECT id FROM users WHERE email = 'dr.dubois@clinique.fr'),
    id,
    TRUE
FROM users WHERE email = 'claire.petit@email.com';

-- Association device ↔ patient (pansement posé)
INSERT INTO patient_devices (patient_id, device_id, wound_type, wound_location, wound_size_cm2, application_date, expected_removal_date, baseline_impedance, is_active)
VALUES 
(
    (SELECT id FROM users WHERE email = 'marie.dupont@email.com'),
    (SELECT id FROM devices WHERE device_id = 'PANS-00001234'),
    'chirurgicale',
    'Jambe droite, mollet',
    12.5,
    CURRENT_TIMESTAMP - INTERVAL '3 days',
    CURRENT_TIMESTAMP + INTERVAL '11 days',
    450,
    TRUE
),
(
    (SELECT id FROM users WHERE email = 'paul.bernard@email.com'),
    (SELECT id FROM devices WHERE device_id = 'PANS-00001235'),
    'brulure',
    'Avant-bras gauche',
    8.3,
    CURRENT_TIMESTAMP - INTERVAL '5 days',
    CURRENT_TIMESTAMP + INTERVAL '16 days',
    380,
    TRUE
);

-- Mesures (exemples sur 3 jours)
-- Marie Dupont - Mesures normales
INSERT INTO measurements (device_id, patient_device_id, temperature, impedance, orp, battery_level, signal_quality, infection_score, measured_at)
SELECT 
    (SELECT id FROM devices WHERE device_id = 'PANS-00001234'),
    (SELECT id FROM patient_devices WHERE patient_id = (SELECT id FROM users WHERE email = 'marie.dupont@email.com') AND is_active = TRUE),
    36.5 + (random() * 0.5),  -- Température normale 36.5-37.0
    450 + (random() * 30 - 15)::INT,  -- Impédance stable autour de 450
    320 + (random() * 40 - 20)::INT,  -- ORP normal autour de 320
    85 - (gs.i / 144),  -- Batterie décroit lentement
    95,
    15 + (random() * 10)::INT,  -- Score infection bas
    CURRENT_TIMESTAMP - (gs.i || ' hours')::INTERVAL
FROM generate_series(0, 72) AS gs(i);

-- Paul Bernard - Mesures avec début d'infection
INSERT INTO measurements (device_id, patient_device_id, temperature, impedance, orp, battery_level, signal_quality, infection_score, measured_at)
SELECT 
    (SELECT id FROM devices WHERE device_id = 'PANS-00001235'),
    (SELECT id FROM patient_devices WHERE patient_id = (SELECT id FROM users WHERE email = 'paul.bernard@email.com') AND is_active = TRUE),
    36.8 + (gs.i / 72.0 * 1.5),  -- Température augmente progressivement
    380 - (gs.i / 72.0 * 50)::INT,  -- Impédance diminue
    250 - (gs.i / 72.0 * 100)::INT,  -- ORP diminue (signe infection)
    90 - (gs.i / 144),
    92,
    20 + (gs.i / 72.0 * 60)::INT,  -- Score infection augmente
    CURRENT_TIMESTAMP - (gs.i || ' hours')::INTERVAL
FROM generate_series(0, 72) AS gs(i);

-- Alertes (exemples)
INSERT INTO alerts (patient_device_id, patient_id, device_id, alert_type, severity, title, message, current_value, threshold_value, notification_sent, notification_method)
SELECT 
    pd.id,
    pd.patient_id,
    pd.device_id,
    'temperature',
    'warning',
    'Température légèrement élevée',
    'La température mesurée (37.8°C) dépasse légèrement le seuil normal. Surveillez l''évolution.',
    37.8,
    37.5,
    TRUE,
    'push'
FROM patient_devices pd
WHERE pd.patient_id = (SELECT id FROM users WHERE email = 'paul.bernard@email.com')
  AND pd.is_active = TRUE;

INSERT INTO alerts (patient_device_id, patient_id, device_id, alert_type, severity, title, message, current_value, threshold_value, notification_sent, notification_method)
SELECT 
    pd.id,
    pd.patient_id,
    pd.device_id,
    'infection',
    'critical',
    '⚠️ Risque d''infection détecté',
    'Les paramètres indiquent un risque élevé d''infection (score: 75/100). Contactez rapidement votre médecin.',
    75,
    60,
    TRUE,
    'push'
FROM patient_devices pd
WHERE pd.patient_id = (SELECT id FROM users WHERE email = 'paul.bernard@email.com')
  AND pd.is_active = TRUE;

-- Notes médicales (exemples)
INSERT INTO medical_notes (patient_id, medecin_id, patient_device_id, note_type, title, content)
SELECT 
    (SELECT id FROM users WHERE email = 'marie.dupont@email.com'),
    (SELECT id FROM users WHERE email = 'dr.martin@hopital.fr'),
    pd.id,
    'observation',
    'Contrôle post-opératoire J+3',
    'Cicatrisation conforme aux attentes. Pas de signe d''infection. Poursuite antibioprophylaxie 7 jours. RDV contrôle prévu J+14.'
FROM patient_devices pd
WHERE pd.patient_id = (SELECT id FROM users WHERE email = 'marie.dupont@email.com')
  AND pd.is_active = TRUE;

-- ============================================================================
-- STATISTIQUES ET INFORMATIONS
-- ============================================================================

-- Afficher résumé de la base
DO $$
DECLARE
    v_nb_users INT;
    v_nb_patients INT;
    v_nb_medecins INT;
    v_nb_devices INT;
    v_nb_measurements INT;
    v_nb_alerts INT;
BEGIN
    SELECT COUNT(*) INTO v_nb_users FROM users;
    SELECT COUNT(*) INTO v_nb_patients FROM users WHERE role = 'patient';
    SELECT COUNT(*) INTO v_nb_medecins FROM users WHERE role = 'medecin';
    SELECT COUNT(*) INTO v_nb_devices FROM devices;
    SELECT COUNT(*) INTO v_nb_measurements FROM measurements;
    SELECT COUNT(*) INTO v_nb_alerts FROM alerts;
    
    RAISE NOTICE '';
    RAISE NOTICE '╔════════════════════════════════════════════════════════╗';
    RAISE NOTICE '║   BASE DE DONNÉES INITIALISÉE AVEC SUCCÈS ✅          ║';
    RAISE NOTICE '╠════════════════════════════════════════════════════════╣';
    RAISE NOTICE '║ Users total       : % (% patients, % médecins)    ║', 
        LPAD(v_nb_users::TEXT, 3), 
        LPAD(v_nb_patients::TEXT, 2),
        LPAD(v_nb_medecins::TEXT, 2);
    RAISE NOTICE '║ Devices (pansements) : %                              ║', LPAD(v_nb_devices::TEXT, 3);
    RAISE NOTICE '║ Measurements      : %                             ║', LPAD(v_nb_measurements::TEXT, 4);
    RAISE NOTICE '║ Alerts            : %                                ║', LPAD(v_nb_alerts::TEXT, 3);
    RAISE NOTICE '╠════════════════════════════════════════════════════════╣';
    RAISE NOTICE '║ Tables créées     : 9                                  ║';
    RAISE NOTICE '║ Vues créées       : 3                                  ║';
    RAISE NOTICE '║ Fonctions créées  : 3                                  ║';
    RAISE NOTICE '╚════════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- FIN DU SCRIPT
-- ============================================================================