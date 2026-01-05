-- Migration: Ajout des champs d'authentification avancée
-- Date: 2025-01-XX
-- Description: Ajoute les champs pour vérification email, réinitialisation mot de passe, 2FA et informations professionnelles

-- Champs professionnels (médecins)
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS rpps_number VARCHAR(11) UNIQUE,
ADD COLUMN IF NOT EXISTS specialty VARCHAR(100),
ADD COLUMN IF NOT EXISTS establishment VARCHAR(255);

-- Vérification email
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS email_verification_token VARCHAR(255),
ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMP;

-- Réinitialisation mot de passe
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS password_reset_token VARCHAR(255),
ADD COLUMN IF NOT EXISTS password_reset_expires_at TIMESTAMP;

-- Authentification à deux facteurs (2FA)
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS two_factor_secret VARCHAR(255),
ADD COLUMN IF NOT EXISTS two_factor_enabled BOOLEAN DEFAULT FALSE;

-- Index pour améliorer les performances
CREATE INDEX IF NOT EXISTS idx_users_email_verification_token ON users(email_verification_token);
CREATE INDEX IF NOT EXISTS idx_users_password_reset_token ON users(password_reset_token);
CREATE INDEX IF NOT EXISTS idx_users_is_verified ON users(is_verified);

-- Commentaires
COMMENT ON COLUMN users.rpps_number IS 'Numéro RPPS (11 chiffres) pour les médecins';
COMMENT ON COLUMN users.specialty IS 'Spécialité médicale';
COMMENT ON COLUMN users.establishment IS 'Établissement de santé';
COMMENT ON COLUMN users.is_verified IS 'Email vérifié ou non';
COMMENT ON COLUMN users.email_verification_token IS 'Token pour vérifier l''email';
COMMENT ON COLUMN users.password_reset_token IS 'Token pour réinitialiser le mot de passe';
COMMENT ON COLUMN users.two_factor_secret IS 'Secret pour l''authentification à deux facteurs';

