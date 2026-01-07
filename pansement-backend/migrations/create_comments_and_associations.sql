-- ============================================
-- MIGRATION : Création de la table comments
-- ============================================

-- Table des commentaires
CREATE TABLE IF NOT EXISTS comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Relations
    patient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    medecin_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    measurement_id UUID REFERENCES measurements(id) ON DELETE SET NULL, -- Optionnel
    
    -- Contenu
    comment_text TEXT NOT NULL,
    
    -- Statut
    is_read BOOLEAN DEFAULT FALSE,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Index pour améliorer les performances
CREATE INDEX IF NOT EXISTS idx_comments_patient_id ON comments(patient_id);
CREATE INDEX IF NOT EXISTS idx_comments_medecin_id ON comments(medecin_id);
CREATE INDEX IF NOT EXISTS idx_comments_created_at ON comments(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_comments_is_read ON comments(is_read) WHERE is_read = FALSE;

-- Trigger pour mettre à jour updated_at automatiquement
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_comments_updated_at ON comments;
CREATE TRIGGER update_comments_updated_at
    BEFORE UPDATE ON comments
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- MIGRATION : Table association patient-medecin
-- ============================================

-- Table pour associer patients et médecins
-- Note: Le nom de la table est 'medecin_patients' pour rester cohérent avec le code existant
CREATE TABLE IF NOT EXISTS medecin_patients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Relations
    patient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    medecin_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Timestamps
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- Un patient ne peut être assigné qu'une seule fois à un médecin
    UNIQUE(patient_id, medecin_id)
);

-- Index
CREATE INDEX IF NOT EXISTS idx_medecin_patients_patient_id ON medecin_patients(patient_id);
CREATE INDEX IF NOT EXISTS idx_medecin_patients_medecin_id ON medecin_patients(medecin_id);

-- ============================================
-- DONNÉES DE TEST (Optionnel)
-- ============================================

-- Exemple : Assigner un patient à un médecin
-- INSERT INTO medecin_patients (patient_id, medecin_id)
-- VALUES ('uuid-patient', 'uuid-medecin');

-- Exemple : Créer un commentaire
-- INSERT INTO comments (patient_id, medecin_id, comment_text)
-- VALUES ('uuid-patient', 'uuid-medecin', 'La plaie est en bonne voie de guérison 👍');

