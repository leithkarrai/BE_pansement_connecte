from fastapi import FastAPI, Depends, Request, Response, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session
from starlette.middleware.base import BaseHTTPMiddleware

from app.database import get_db, check_db_connection, get_db_info, init_db, _safe_print
from app.api import auth, users, devices, measurements, files, alerts, comments
from app.core.redis_client import test_redis_connection
from app.core.minio_client import test_minio_connection, initialize_buckets
# Importer les modèles pour que SQLAlchemy les charge
from app.models import User, Device, Measurement, Alert, Comment

app = FastAPI(
    title='Pansement Connecté API',
    version='v1',
    description='API REST pour le système de pansement connecté IoT médical',
    docs_url='/api/docs',
    redoc_url='/api/redoc'
)

# Middleware pour forcer l'encodage UTF-8 dans les réponses
class UTF8Middleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        # Forcer le charset UTF-8 dans les headers
        if 'content-type' in response.headers:
            content_type = response.headers['content-type']
            if 'application/json' in content_type and 'charset' not in content_type:
                response.headers['content-type'] = 'application/json; charset=utf-8'
        return response

app.add_middleware(UTF8Middleware)

# CORS - Configuration pour Flutter Web
app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],  # En développement, autoriser toutes les origines
    allow_credentials=True,  # Autoriser les credentials pour les cookies/tokens
    allow_methods=['*'],  # Autoriser toutes les méthodes
    allow_headers=['*'],  # Autoriser tous les headers
    expose_headers=['*'],  # Exposer tous les headers
    max_age=3600,
)

# Inclure les routes
# Note: Les routers ont déjà leur prefix défini dans leurs fichiers respectifs
app.include_router(auth.router, tags=['Authentication'])
app.include_router(users.router, tags=['Users'])
app.include_router(devices.router, tags=['Devices'])
app.include_router(measurements.router, tags=['Measurements'])
app.include_router(files.router, tags=['Files'])
app.include_router(alerts.router, tags=['Alerts'])
app.include_router(comments.router, tags=['Comments'])


def _safe_error_detail(exc: Exception) -> str:
    """Message d'erreur ASCII pour reponse JSON (evite problemes encodage)."""
    return (str(exc) or repr(exc)).encode("ascii", "replace").decode("ascii")


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Retourne 500 avec le detail de l'erreur (sauf HTTPException geree par FastAPI)."""
    if isinstance(exc, HTTPException):
        raise exc
    detail = _safe_error_detail(exc)
    return JSONResponse(
        status_code=500,
        content={"detail": detail, "type": type(exc).__name__},
    )


@app.on_event('startup')
async def startup():
    _safe_print('[OK] Demarrage Pansement Connecte API')
    if check_db_connection():
        _safe_print('[OK] PostgreSQL connecte')
        # Créer les tables si elles n'existent pas
        try:
            init_db()
        except Exception as e:
            _safe_print(f'[WARN] Erreur creation tables: {e}')
        info = get_db_info()
        _safe_print(f'   Tables: {info.get("tables", 0)}')
        _safe_print(f'   Users: {info.get("users", 0)}')
        _safe_print(f'   Devices: {info.get("devices", 0)}')
        _safe_print(f'   Measurements: {info.get("measurements", 0)}')
    else:
        _safe_print('[WARN] PostgreSQL non connecte')
    
    if test_redis_connection():
        _safe_print('[OK] Redis connecte (cache active)')
    else:
        _safe_print('[WARN] Redis non connecte (cache desactive)')
    
    if test_minio_connection():
        _safe_print('[OK] MinIO connecte (stockage fichiers active)')
        initialize_buckets()  # Créer les buckets au démarrage
    else:
        _safe_print('[WARN] MinIO non connecte (stockage fichiers desactive)')

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
