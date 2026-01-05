import os
from sqlalchemy import create_engine, text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from typing import Generator

# URL de connexion PostgreSQL
# Utiliser variable d'environnement ou valeur par défaut
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

def check_db_connection() -> bool:
    '''Vérifier que la connexion PostgreSQL fonctionne'''
    try:
        db = SessionLocal()
        # Exécuter une requête simple
        result = db.execute(text('SELECT 1'))
        db.close()
        return True
    except Exception as e:
        print(f'❌ Erreur connexion PostgreSQL: {e}')
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

def init_db():
    '''Créer toutes les tables (utiliser Alembic en production)'''
    Base.metadata.create_all(bind=engine)
    print('✅ Tables créées')
