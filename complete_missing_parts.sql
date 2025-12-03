-- ============================================================================
-- SCRIPT POUR COMPLÉTER LA BASE DE DONNÉES
-- Ajoute les tables, vues et fonctions manquantes
-- ============================================================================

-- ============================================================================
-- TABLES MANQUANTES
-- ============================================================================

CREATE TABLE IF NOT EXISTS wound_photos (
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
CREATE INDEX IF NOT EXISTS idx_wound_photos_patient_device ON wound_photos(patient_device_id);
CREATE INDEX IF NOT EXISTS idx_wound_photos_patient ON wound_photos(patient_id);
CREATE INDEX IF NOT EXISTS idx_wound_photos_taken_at ON wound_photos(taken_at DESC);

COMMENT ON TABLE wound_photos IS 'Photos suivi visuel de la plaie';
COMMENT ON COLUMN wound_photos.ai_analysis IS 'JSON résultats analyse IA (type plaie, progression, etc.)';

-- ============================================================================
-- TABLE: medical_notes
-- ============================================================================

CREATE TABLE IF NOT EXISTS medical_notes (
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
CREATE INDEX IF NOT EXISTS idx_medical_notes_patient ON medical_notes(patient_id);
CREATE INDEX IF NOT EXISTS idx_medical_notes_medecin ON medical_notes(medecin_id);
CREATE INDEX IF NOT EXISTS idx_medical_notes_created_at ON medical_notes(created_at DESC);

-- Trigger updated_at
DROP TRIGGER IF EXISTS update_medical_notes_updated_at ON medical_notes;
CREATE TRIGGER update_medical_notes_updated_at BEFORE UPDATE ON medical_notes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE medical_notes IS 'Notes médicales des médecins sur leurs patients';

-- ============================================================================
-- TABLE: audit_logs
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_logs (
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
CREATE INDEX IF NOT EXISTS idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_time ON audit_logs(user_id, created_at DESC);

COMMENT ON TABLE audit_logs IS 'Traçabilité complète (qui, quand, quoi) - IMMUABLE';
COMMENT ON COLUMN audit_logs.before_value IS 'Valeur avant modification (JSON)';
COMMENT ON COLUMN audit_logs.after_value IS 'Valeur après modification (JSON)';

-- ============================================================================
-- FONCTIONS MANQUANTES
-- ============================================================================

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

COMMENT ON FUNCTION calculate_baseline_impedance IS 'Calcule la baseline d''impédance (moyenne des 10 premières mesures)';

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

COMMENT ON FUNCTION get_latest_measurement IS 'Récupère la dernière mesure d''un patient';

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

COMMENT ON FUNCTION count_unresolved_alerts IS 'Compte les alertes non résolues d''un patient';

-- ============================================================================
-- VUES MANQUANTES
-- ============================================================================

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

