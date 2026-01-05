class Settings:
    # Application
    APP_NAME = "Pansement Connecté API"
    API_VERSION = "v1"
    DEBUG = True
    
    # Database
    DB_HOST = "localhost"
    DB_PORT = 5432
    DB_NAME = "pansement_connecte"
    DB_USER = "postgres"
    DB_PASSWORD = "postgres_password_change_me"
    
    DATABASE_URL = "postgresql://postgres:postgres_password_change_me@localhost:5432/pansement_connecte"
    
    # JWT
    JWT_SECRET_KEY = "your-super-secret-jwt-key-change-me-min-32-chars"
    JWT_ALGORITHM = "HS256"
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES = 15
    
    # CORS
    CORS_ORIGINS = ["*"]
    ENABLE_SWAGGER = True

settings = Settings()
