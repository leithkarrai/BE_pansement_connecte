-- Migration: Mise à jour de la table comments
-- Ajout du champ is_read et renommage de content en comment_text
-- Date: 2024

-- Renommer la colonne content en comment_text
ALTER TABLE comments RENAME COLUMN content TO comment_text;

-- Ajouter la colonne is_read
ALTER TABLE comments ADD COLUMN IF NOT EXISTS is_read BOOLEAN NOT NULL DEFAULT FALSE;

-- Créer un index sur is_read pour améliorer les performances
CREATE INDEX IF NOT EXISTS idx_comments_is_read ON comments(is_read);

-- Mettre à jour les commentaires existants comme non lus
UPDATE comments SET is_read = FALSE WHERE is_read IS NULL;

