#!/usr/bin/env python3
"""
Commande pour créer un utilisateur administrateur dans la base de données.

À utiliser quand un admin existe déjà et que vous voulez ajouter un autre admin
sans passer par l'API (ou pour le tout premier admin si la base est vide).

Usage (depuis le dossier pansement-backend) :
  python scripts/create_admin.py --email admin@exemple.fr --password "MotDePasseSecurise123!"

Options :
  --email       Email de l'administrateur (obligatoire)
  --password    Mot de passe (obligatoire, 12 car. min, maj, min, chiffre, symbole)
  --first-name  Prénom (défaut : Admin)
  --last-name   Nom (défaut : Administrateur)

La variable d'environnement DATABASE_URL est utilisée (ou la valeur par défaut du backend).
"""
import argparse
import os
import sys

# Charger .env si présent
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# Rendre le package app importable (exécution depuis pansement-backend)
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_BACKEND_ROOT = os.path.dirname(_SCRIPT_DIR)
if _BACKEND_ROOT not in sys.path:
    sys.path.insert(0, _BACKEND_ROOT)

from app.database import SessionLocal, check_db_connection
from app.models.user import User
from app.core.security import hash_password, validate_password_strength


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Créer un utilisateur administrateur dans la base de données."
    )
    parser.add_argument(
        "--email",
        required=True,
        help="Email de l'administrateur",
    )
    parser.add_argument(
        "--password",
        required=True,
        help="Mot de passe (12 car. min, maj, min, chiffre, symbole)",
    )
    parser.add_argument(
        "--first-name",
        default="Admin",
        dest="first_name",
        help="Prénom (défaut: Admin)",
    )
    parser.add_argument(
        "--last-name",
        default="Administrateur",
        dest="last_name",
        help="Nom (défaut: Administrateur)",
    )
    args = parser.parse_args()

    email = args.email.strip()
    password = args.password
    first_name = (args.first_name or "Admin").strip()
    last_name = (args.last_name or "Administrateur").strip()

    if not email:
        print("Erreur: l'email ne peut pas être vide.", file=sys.stderr)
        return 1

    # Validation du mot de passe (même règles que l'API)
    is_valid, err_msg = validate_password_strength(password)
    if not is_valid:
        print(f"Erreur mot de passe: {err_msg}", file=sys.stderr)
        return 1

    if not check_db_connection():
        print("Erreur: impossible de se connecter à la base de données. Vérifiez DATABASE_URL.", file=sys.stderr)
        return 1

    db = SessionLocal()
    try:
        existing = db.query(User).filter(User.email == email).first()
        if existing:
            print(f"Erreur: un utilisateur avec l'email '{email}' existe déjà.", file=sys.stderr)
            return 1

        user = User(
            email=email,
            password_hash=hash_password(password),
            role="admin",
            first_name=first_name,
            last_name=last_name,
            is_active=True,
            is_verified=False,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        print(f"Administrateur créé avec succès: {first_name} {last_name} <{email}> (id: {user.id})")
        return 0
    except Exception as e:
        db.rollback()
        print(f"Erreur: {e}", file=sys.stderr)
        return 1
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
