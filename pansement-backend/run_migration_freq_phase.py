#!/usr/bin/env python3
"""
Exécute la migration add_measurements_freq_phase.sql sur la base configurée (DATABASE_URL ou défaut).
Usage: depuis la racine du projet pansement-backend:
  python run_migration_freq_phase.py
"""
import os
import sys

# Charger .env si présent (comme le fait souvent l'app)
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# Ajouter le répertoire parent pour importer app
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sqlalchemy import text
from app.database import engine

MIGRATION_PATH = os.path.join(os.path.dirname(__file__), "migrations", "add_measurements_freq_phase.sql")

def main():
    with open(MIGRATION_PATH, "r", encoding="utf-8") as f:
        sql_content = f.read()

    # Exécuter chaque instruction (séparées par ;) en ignorant les commentaires et lignes vides
    statements = [
        s.strip() for s in sql_content.split(";")
        if s.strip() and not s.strip().startswith("--")
    ]

    with engine.connect() as conn:
        for stmt in statements:
            if stmt:
                conn.execute(text(stmt))
        conn.commit()

    print("Migration add_measurements_freq_phase.sql exécutée avec succès.")
    print("Colonnes freq_hz et phase_deg ajoutées à la table measurements (si elles n'existaient pas).")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Erreur: {e}", file=sys.stderr)
        sys.exit(1)
