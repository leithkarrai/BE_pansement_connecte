-- Ajout des colonnes freq_hz et phase_deg pour le balayage Bode (impédance)
-- À exécuter sur la base utilisée par pansement-backend

ALTER TABLE measurements
ADD COLUMN IF NOT EXISTS freq_hz DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS phase_deg DOUBLE PRECISION;

COMMENT ON COLUMN measurements.freq_hz IS 'Fréquence en Hz (balayage Bode)';
COMMENT ON COLUMN measurements.phase_deg IS 'Phase en degrés (balayage Bode)';
