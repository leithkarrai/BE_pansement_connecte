-- Migration: Création de la table comments
-- Date: 2024

CREATE TABLE IF NOT EXISTS comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    medecin_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    measurement_id UUID REFERENCES measurements(id) ON DELETE SET NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE
);

-- Index pour améliorer les performances
CREATE INDEX IF NOT EXISTS idx_comments_patient_id ON comments(patient_id);
CREATE INDEX IF NOT EXISTS idx_comments_medecin_id ON comments(medecin_id);
CREATE INDEX IF NOT EXISTS idx_comments_measurement_id ON comments(measurement_id);
CREATE INDEX IF NOT EXISTS idx_comments_created_at ON comments(created_at DESC);

-- Commentaires
COMMENT ON TABLE comments IS 'Commentaires médicaux des médecins pour les patients';
COMMENT ON COLUMN comments.patient_id IS 'ID du patient qui reçoit le commentaire';
COMMENT ON COLUMN comments.medecin_id IS 'ID du médecin qui écrit le commentaire';
COMMENT ON COLUMN comments.measurement_id IS 'ID de la mesure associée (optionnel)';
COMMENT ON COLUMN comments.content IS 'Contenu du commentaire';
COMMENT ON COLUMN comments.created_at IS 'Date de création du commentaire';
COMMENT ON COLUMN comments.updated_at IS 'Date de dernière modification du commentaire';

