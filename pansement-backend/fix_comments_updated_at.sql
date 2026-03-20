-- Corriger la colonne updated_at de la table comments (NOT NULL sans valeur envoyée).
-- Exécuter une fois avec : psql -U postgres -d pansement_connecte -f fix_comments_updated_at.sql
-- Ou via Docker : docker exec -i pansement_postgres psql -U postgres -d pansement_connecte < fix_comments_updated_at.sql

-- Valeur par défaut : si l'app n'envoie pas updated_at, la base met NOW()
ALTER TABLE comments ALTER COLUMN updated_at SET DEFAULT NOW();
-- Accepter NULL pour éviter NotNullViolation (l'app peut envoyer NULL par erreur)
ALTER TABLE comments ALTER COLUMN updated_at DROP NOT NULL;
