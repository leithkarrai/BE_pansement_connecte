from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session

from app.database import get_db, check_db_connection, get_db_info
from app.api import auth, users, devices, measurements, files, alerts
from app.core.redis_client import test_redis_connection
from app.core.minio_client import test_minio_connection, initialize_buckets
# Importer les modèles pour que SQLAlchemy les charge
from app.models import User, Device, Measurement, Alert

app = FastAPI(
    title='Pansement Connecté API',
    version='v1',
    description='API REST pour le système de pansement connecté IoT médical',
    docs_url='/api/docs',
    redoc_url='/api/redoc'
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*']
)

# Inclure les routes
# Note: Les routers ont déjà leur prefix défini dans leurs fichiers respectifs
app.include_router(auth.router, tags=['Authentication'])
app.include_router(users.router, tags=['Users'])
app.include_router(devices.router, tags=['Devices'])
app.include_router(measurements.router, tags=['Measurements'])
app.include_router(files.router, tags=['Files'])
app.include_router(alerts.router, tags=['Alerts'])

@app.on_event('startup')
async def startup():
    print('🚀 Démarrage de Pansement Connecté API')
    if check_db_connection():
        print('✅ PostgreSQL connecté')
        info = get_db_info()
        print(f'   📊 Tables: {info.get("tables", 0)}')
        print(f'   👥 Users: {info.get("users", 0)}')
        print(f'   📟 Devices: {info.get("devices", 0)}')
        print(f'   📈 Measurements: {info.get("measurements", 0)}')
    else:
        print('⚠️  PostgreSQL non connecté')
    
    if test_redis_connection():
        print('✅ Redis connecté (cache activé)')
    else:
        print('⚠️  Redis non connecté (cache désactivé)')
    
    if test_minio_connection():
        print('✅ MinIO connecté (stockage fichiers activé)')
        initialize_buckets()  # Créer les buckets au démarrage
    else:
        print('⚠️  MinIO non connecté (stockage fichiers désactivé)')

@app.get('/')
def root():
    return {
        'app': 'Pansement Connecté API',
        'version': 'v1',
        'status': 'running',
        'docs': '/api/docs'
    }

@app.get('/health')
def health():
    db_connected = check_db_connection()
    return {
        'status': 'healthy' if db_connected else 'degraded',
        'database': 'connected' if db_connected else 'disconnected'
    }

@app.get('/api/v1/database/info')
def database_info():
    return get_db_info()

@app.get('/api/v1/database/test')
def test_database(db: Session = Depends(get_db)):
    try:
        from sqlalchemy import text
        result = db.execute(text('SELECT COUNT(*) as count FROM users'))
        count = result.scalar()
        return {
            'success': True,
            'message': 'Connexion PostgreSQL OK',
            'users_count': count
        }
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }
