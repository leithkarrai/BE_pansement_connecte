-- ============================================================================
-- DONNÃ‰ES DE TEST
-- ============================================================================

-- Insertion des donnÃ©es de test
-- ATTENTION: Mot de passe hashÃ© avec bcrypt (Ã  gÃ©nÃ©rer avec votre backend)
-- Exemple: bcrypt.hash('password123', 10) en Node.js

-- Admin
INSERT INTO users (email, password_hash, role, first_name, last_name, phone, is_active)
VALUES 
('admin@pansement-connecte.com', '$2b$10$ExampleHashForPassword123Admin', 'admin', 'Admin', 'System', '+33 1 23 45 67 89', TRUE);

-- MÃ©decins
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

-- Association mÃ©decin â†” patients
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

-- Association device â†” patient (pansement posÃ©)
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
    36.5 + (random() * 0.5),  -- TempÃ©rature normale 36.5-37.0
    450 + (random() * 30 - 15)::INT,  -- ImpÃ©dance stable autour de 450
    320 + (random() * 40 - 20)::INT,  -- ORP normal autour de 320
    85 - (gs.i / 144),  -- Batterie dÃ©croit lentement
    95,
    15 + (random() * 10)::INT,  -- Score infection bas
    CURRENT_TIMESTAMP - (gs.i || ' hours')::INTERVAL
FROM generate_series(0, 72) AS gs(i);

-- Paul Bernard - Mesures avec dÃ©but d'infection
INSERT INTO measurements (device_id, patient_device_id, temperature, impedance, orp, battery_level, signal_quality, infection_score, measured_at)
SELECT 
    (SELECT id FROM devices WHERE device_id = 'PANS-00001235'),
    (SELECT id FROM patient_devices WHERE patient_id = (SELECT id FROM users WHERE email = 'paul.bernard@email.com') AND is_active = TRUE),
    36.8 + (gs.i / 72.0 * 1.5),  -- TempÃ©rature augmente progressivement
    380 - (gs.i / 72.0 * 50)::INT,  -- ImpÃ©dance diminue
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
    'TempÃ©rature lÃ©gÃ¨rement Ã©levÃ©e',
    'La tempÃ©rature mesurÃ©e (37.8Â°C) dÃ©passe lÃ©gÃ¨rement le seuil normal. Surveillez l''Ã©volution.',
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
    'âš ï¸ Risque d''infection dÃ©tectÃ©',
    'Les paramÃ¨tres indiquent un risque Ã©levÃ© d''infection (score: 75/100). Contactez rapidement votre mÃ©decin.',
    75,
    60,
    TRUE,
    'push'
FROM patient_devices pd
WHERE pd.patient_id = (SELECT id FROM users WHERE email = 'paul.bernard@email.com')
  AND pd.is_active = TRUE;

-- Notes mÃ©dicales (exemples)
INSERT INTO medical_notes (patient_id, medecin_id, patient_device_id, note_type, title, content)
SELECT 
    (SELECT id FROM users WHERE email = 'marie.dupont@email.com'),
    (SELECT id FROM users WHERE email = 'dr.martin@hopital.fr'),
    pd.id,
    'observation',
    'ContrÃ´le post-opÃ©ratoire J+3',
    'Cicatrisation conforme aux attentes. Pas de signe d''infection. Poursuite antibioprophylaxie 7 jours. RDV contrÃ´le prÃ©vu J+14.'
FROM patient_devices pd
WHERE pd.patient_id = (SELECT id FROM users WHERE email = 'marie.dupont@email.com')
  AND pd.is_active = TRUE;

-- ============================================================================
-- STATISTIQUES ET INFORMATIONS
-- ============================================================================

-- Afficher rÃ©sumÃ© de la base
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
    RAISE NOTICE 'â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—';
    RAISE NOTICE 'â•‘   BASE DE DONNÃ‰ES INITIALISÃ‰E AVEC SUCCÃˆS âœ…          â•‘';
    RAISE NOTICE 'â• â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•£';
    RAISE NOTICE 'â•‘ Users total       : % (% patients, % mÃ©decins)    â•‘', 
        LPAD(v_nb_users::TEXT, 3), 
        LPAD(v_nb_patients::TEXT, 2),
        LPAD(v_nb_medecins::TEXT, 2);
    RAISE NOTICE 'â•‘ Devices (pansements) : %                              â•‘', LPAD(v_nb_devices::TEXT, 3);
    RAISE NOTICE 'â•‘ Measurements      : %                             â•‘', LPAD(v_nb_measurements::TEXT, 4);
    RAISE NOTICE 'â•‘ Alerts            : %                                â•‘', LPAD(v_nb_alerts::TEXT, 3);
    RAISE NOTICE 'â• â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•£';
    RAISE NOTICE 'â•‘ Tables crÃ©Ã©es     : 9                                  â•‘';
    RAISE NOTICE 'â•‘ Vues crÃ©Ã©es       : 3                                  â•‘';
    RAISE NOTICE 'â•‘ Fonctions crÃ©Ã©es  : 3                                  â•‘';
    RAISE NOTICE 'â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- FIN DU SCRIPT
-- ============================================================================
