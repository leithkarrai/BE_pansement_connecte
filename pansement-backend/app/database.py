import os
from sqlalchemy import create_engine, text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from typing import Generator

# URL de connexion PostgreSQL
# - En Docker : DATABASE_URL fourni par docker-compose (pansement_postgres)
# - En local : utiliser .env avec DATABASE_URL=...@localhost:5432/... ou défaut ci-dessous
DATABASE_URL = os.getenv(
    'DATABASE_URL',
    'postgresql://postgres:postgres_password_change_me@localhost:5432/pansement_connecte'
)

# Créer l'engine SQLAlchemy
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,  # Vérifier la connexion avant usage
    echo=False,  # Mettre True pour voir les requêtes SQL
    pool_size=10,
    max_overflow=20
)

# Session factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Base pour les modèles
Base = declarative_base()

# ============================================================================
# DÉPENDANCE FASTAPI
# ============================================================================

def get_db() -> Generator[Session, None, None]:
    '''
    Dépendance FastAPI pour obtenir une session de base de données.
    Usage: db: Session = Depends(get_db)
    '''
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# ============================================================================
# FONCTIONS UTILITAIRES
# ============================================================================

def _safe_print(msg: str) -> None:
    """Affiche un message en ASCII pour eviter UnicodeEncodeError sur Windows (cp1252)."""
    safe = (msg or "").encode("ascii", "replace").decode("ascii")
    try:
        print(safe)
    except Exception:
        import sys
        sys.stderr.buffer.write(safe.encode("ascii") + b"\n")
        sys.stderr.buffer.flush()

def check_db_connection() -> bool:
    '''Vérifier que la connexion PostgreSQL fonctionne'''
    try:
        db = SessionLocal()
        # Exécuter une requête simple
        result = db.execute(text('SELECT 1'))
        db.close()
        return True
    except Exception as e:
        _safe_print(f'[ERR] Connexion PostgreSQL: {e}')
        return False

def get_db_info() -> dict:
    '''Obtenir des informations sur la base de données'''
    try:
        db = SessionLocal()
        
        # Compter les tables
        result = db.execute(text('''
            SELECT COUNT(*) 
            FROM information_schema.tables 
            WHERE table_schema = 'public'
        '''))
        nb_tables = result.scalar()
        
        # Compter les users
        try:
            result = db.execute(text('SELECT COUNT(*) FROM users'))
            nb_users = result.scalar()
        except:
            nb_users = 0
        
        # Compter les devices
        try:
            result = db.execute(text('SELECT COUNT(*) FROM devices'))
            nb_devices = result.scalar()
        except:
            nb_devices = 0
        
        # Compter les measurements
        try:
            result = db.execute(text('SELECT COUNT(*) FROM measurements'))
            nb_measurements = result.scalar()
        except:
            nb_measurements = 0
        
        db.close()
        
        return {
            'connected': True,
            'tables': nb_tables,
            'users': nb_users,
            'devices': nb_devices,
            'measurements': nb_measurements
        }
    except Exception as e:
        return {
            'connected': False,
            'error': str(e)
        }

def run_measurements_freq_phase_migration():
    '''
    Ajoute freq_hz et phase_deg à measurements si besoin (balayage Bode).

    Contexte:
    - Le mobile envoie des points d'impédance avec fréquence/phase.
    - Cette migration "runtime" évite de casser un environnement de dev non migré.
    '''
    try:
        db = SessionLocal()
        db.execute(text('''
            ALTER TABLE measurements
            ADD COLUMN IF NOT EXISTS freq_hz DOUBLE PRECISION,
            ADD COLUMN IF NOT EXISTS phase_deg DOUBLE PRECISION
        '''))
        db.commit()
        db.close()
        _safe_print('[OK] Colonnes freq_hz/phase_deg sur measurements (migration)')
    except Exception as e:
        _safe_print(f'[WARN] Migration measurements freq/phase: {e}')


def run_alert_type_enum_migration():
    '''
    Ajoute la valeur new_measurements au type enum alert_type si nécessaire.

    Note PostgreSQL:
    - ALTER TYPE ... ADD VALUE peut nécessiter AUTOCOMMIT selon version PG,
      d'où l'usage d'une connexion dédiée avec isolation_level='AUTOCOMMIT'.
    '''
    enum_name = None
    try:
        db = SessionLocal()
        try:
            r = db.execute(text('''
                SELECT t.typname
                FROM pg_attribute a
                JOIN pg_type t ON a.atttypid = t.oid
                JOIN pg_class c ON a.attrelid = c.oid
                JOIN pg_namespace n ON c.relnamespace = n.oid
                WHERE n.nspname = 'public' AND c.relname = 'alerts' AND a.attname = 'alert_type'
                  AND a.attnum > 0 AND NOT a.attisdropped
                  AND t.typtype = 'e'
            ''')).fetchone()
            if r:
                enum_name = str(r[0]).strip()
        finally:
            db.close()
    except Exception:
        pass

    if not enum_name:
        return
    # ALTER TYPE ADD VALUE ne peut pas s'executer dans une transaction (PG < 12) -> connexion AUTOCOMMIT
    try:
        with engine.connect().execution_options(isolation_level='AUTOCOMMIT') as conn:
            try:
                conn.execute(text(f"ALTER TYPE {enum_name} ADD VALUE IF NOT EXISTS 'new_measurements'"))
            except Exception as e:
                if 'already exists' not in str(e).lower() and 'duplicate' not in str(e).lower():
                    conn.execute(text(f"ALTER TYPE {enum_name} ADD VALUE 'new_measurements'"))
        print(f'[OK] Enum {enum_name}: valeur new_measurements ajoutee')
    except Exception as e:
        _safe_print(f'[WARN] Enum {enum_name} new_measurements: {e}')


def run_alerts_ack_by_role_migration():
    '''
    Ajoute acknowledged_by_medecin_at et acknowledged_by_admin_at à alerts si absentes.

    Objectif:
    - acquittement indépendant par rôle (médecin/admin), sans impacter la vue patient.
    '''
    try:
        db = SessionLocal()
        try:
            for col in ('acknowledged_by_medecin_at', 'acknowledged_by_admin_at'):
                r = db.execute(text('''
                    SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'alerts' AND column_name = :col
                '''), {'col': col}).fetchone()
                if not r:
                    db.execute(text(f'''
                        ALTER TABLE alerts ADD COLUMN IF NOT EXISTS {col} TIMESTAMP WITH TIME ZONE
                    '''))
                    db.commit()
                    print(f'[OK] alerts: colonne {col} ajoutee')
        finally:
            db.close()
    except Exception as e:
        _safe_print(f'[WARN] Migration alerts ack par role: {e}')


def run_comments_delete_by_role_migration():
    '''
    Ajoute deleted_by_medecin_at et deleted_by_admin_at à comments si absentes.

    Objectif:
    - masquer un commentaire côté médecin/admin sans le supprimer pour le patient.
    '''
    try:
        db = SessionLocal()
        try:
            for col in ('deleted_at', 'deleted_by_medecin_at', 'deleted_by_admin_at'):
                r = db.execute(text('''
                    SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'comments' AND column_name = :col
                '''), {'col': col}).fetchone()
                if not r:
                    db.execute(text(f'''
                        ALTER TABLE comments ADD COLUMN IF NOT EXISTS {col} TIMESTAMP WITH TIME ZONE
                    '''))
                    db.commit()
                    print(f'[OK] comments: colonne {col} ajoutee')
        finally:
            db.close()
    except Exception as e:
        _safe_print(f'[WARN] Migration comments delete par role: {e}')


def init_db():
    '''
    Créer toutes les tables (utiliser Alembic en production).

    En dev:
    - create_all + migrations légères de compatibilité sont exécutées au démarrage.
    En prod:
    - privilégier des migrations versionnées (Alembic) pour la traçabilité.
    '''
    # Importer tous les modeles pour les enregistrer dans Base.metadata (ordre des FKs correct)
    from app.models import (  # noqa: F401
        User, Device, Measurement, Alert, Comment,
        PatientMedecin, PatientDevice,
    )
    Base.metadata.create_all(bind=engine)
    _safe_print('[OK] Tables creees')
    run_measurements_freq_phase_migration()
    run_alert_type_enum_migration()
    run_alerts_ack_by_role_migration()
    run_comments_delete_by_role_migration()
