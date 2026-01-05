# setup_backend.ps1
# Script d'installation automatique du backend FastAPI

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "INSTALLATION BACKEND - Pansement Connecté" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Créer app/config.py
Write-Host "Création de app/config.py..." -ForegroundColor Yellow
$configContent = @'
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    APP_NAME: str = "Pansement Connecté API"
    API_VERSION: str = "v1"
    DEBUG: bool = True
    ENVIRONMENT: str = "development"
    
    DB_HOST: str = "localhost"
    DB_PORT: int = 5432
    DB_NAME: str = "pansement_connecte"
    DB_USER: str = "postgres"
    DB_PASSWORD: str = "postgres_password_change_me"
    
    @property
    def DATABASE_URL(self) -> str:
        return f"postgresql://{self.DB_USER}:{self.DB_PASSWORD}@{self.DB_HOST}:{self.DB_PORT}/{self.DB_NAME}"
    
    REDIS_HOST: str = "localhost"
    REDIS_PORT: int = 6379
    REDIS_PASSWORD: str = "redis_password_change_me"
    
    @property
    def REDIS_URL(self) -> str:
        return f"redis://:{self.REDIS_PASSWORD}@{self.REDIS_HOST}:{self.REDIS_PORT}/0"
    
    INFLUX_URL: str = "http://localhost:8086"
    INFLUX_TOKEN: str = "my-super-secret-auth-token-change-me"
    INFLUX_ORG: str = "pansement-connecte"
    INFLUX_BUCKET: str = "measurements"
    
    JWT_SECRET_KEY: str = "your-super-secret-jwt-key-change-me-min-32-chars"
    JWT_ALGORITHM: str = "HS256"
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    
    CORS_ORIGINS: list[str] = ["http://localhost:3000"]
    ENABLE_SWAGGER: bool = True
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

settings = Settings()
'@
$configContent | Out-File -FilePath "app\config.py" -Encoding UTF8
Write-Host "✅ app/config.py créé" -ForegroundColor Green

# Créer app/database.py
Write-Host "Création de app/database.py..." -ForegroundColor Yellow
$databaseContent = @'
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from typing import Generator
from app.config import settings

engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,
    echo=settings.DEBUG,
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def check_db_connection() -> bool:
    try:
        db = SessionLocal()
        db.execute("SELECT 1")
        db.close()
        return True
    except Exception as e:
        print(f"Erreur PostgreSQL: {e}")
        return False
'@
$databaseContent | Out-File -FilePath "app\database.py" -Encoding UTF8
Write-Host "✅ app/database.py créé" -ForegroundColor Green

# Créer app/core/security.py
Write-Host "Création de app/core/security.py..." -ForegroundColor Yellow
$securityContent = @'
from datetime import datetime, timedelta
from jose import jwt
from passlib.context import CryptContext
from app.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)

def decode_token(token: str):
    try:
        return jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
    except:
        return None
'@
$securityContent | Out-File -FilePath "app\core\security.py" -Encoding UTF8
Write-Host "✅ app/core/security.py créé" -ForegroundColor Green

# Créer app/main.py
Write-Host "Création de app/main.py..." -ForegroundColor Yellow
$mainContent = @'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.database import check_db_connection

app = FastAPI(
    title=settings.APP_NAME,
    version=settings.API_VERSION,
    docs_url="/api/docs" if settings.ENABLE_SWAGGER else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup():
    print(f"Démarrage de {settings.APP_NAME}")
    if check_db_connection():
        print("✅ PostgreSQL connecté")
    else:
        print("⚠️ PostgreSQL non connecté")

@app.get("/")
async def root():
    return {
        "app": settings.APP_NAME,
        "version": settings.API_VERSION,
        "status": "running",
        "docs": "/api/docs"
    }

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "database": "ok" if check_db_connection() else "error"
    }
'@
$mainContent | Out-File -FilePath "app\main.py" -Encoding UTF8
Write-Host "✅ app/main.py créé" -ForegroundColor Green

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "✅ INSTALLATION TERMINÉE !" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Prochaines étapes:" -ForegroundColor Yellow
Write-Host "1. Activer l'environnement virtuel: .\venv\Scripts\Activate.ps1"
Write-Host "2. Installer les dépendances: pip install -r requirements.txt"
Write-Host "3. Lancer l'API: uvicorn app.main:app --reload"
Write-Host ""
