from datetime import datetime, timedelta, timezone
from jose import jwt
from passlib.context import CryptContext
from app.config import settings

# Contexte passlib centralisé pour tout le backend.
# Schéma actuel: bcrypt (compatible avec les hashs existants en base).
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def validate_password_strength(password: str) -> tuple[bool, str]:
    """
    Valider la force d'un mot de passe.
    
    Critères:
    - Minimum 12 caractères
    - Au moins une majuscule
    - Au moins une minuscule
    - Au moins un chiffre
    - Au moins un symbole
    
    Args:
        password: Le mot de passe à valider
        
    Returns:
        Tuple (is_valid, error_message)
    """
    if len(password) < 12:
        return False, "Le mot de passe doit contenir au moins 12 caractères"
    
    if not any(c.isupper() for c in password):
        return False, "Le mot de passe doit contenir au moins une majuscule"
    
    if not any(c.islower() for c in password):
        return False, "Le mot de passe doit contenir au moins une minuscule"
    
    if not any(c.isdigit() for c in password):
        return False, "Le mot de passe doit contenir au moins un chiffre"
    
    if not any(c in "!@#$%^&*(),.?\":{}|<>" for c in password):
        return False, "Le mot de passe doit contenir au moins un symbole (!@#$%^&*...)"
    
    return True, ""

def hash_password(password: str) -> str:
    """
    Hasher un mot de passe avec bcrypt.
    
    ⚠️ IMPORTANT : Bcrypt a une limitation de 72 bytes pour les mots de passe.
    Si le mot de passe dépasse 72 bytes, il sera automatiquement tronqué.
    
    Args:
        password: Le mot de passe en clair à hasher
        
    Returns:
        Le hash bcrypt du mot de passe
    """
    # Bcrypt limite les mots de passe à 72 bytes
    # On tronque automatiquement si nécessaire pour éviter l'erreur
    if len(password.encode('utf-8')) > 72:
        password = password[:72]
    
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Vérifier un mot de passe avec bcrypt.
    
    ⚠️ IMPORTANT : Bcrypt a une limitation de 72 bytes pour les mots de passe.
    Si le mot de passe dépasse 72 bytes, il sera automatiquement tronqué.
    
    Args:
        plain_password: Le mot de passe en clair à vérifier
        hashed_password: Le hash bcrypt à comparer
        
    Returns:
        True si le mot de passe correspond, False sinon
    """
    # Bcrypt limite les mots de passe à 72 bytes
    # On tronque automatiquement si nécessaire pour éviter l'erreur
    password_to_verify = plain_password
    if len(plain_password.encode('utf-8')) > 72:
        password_to_verify = plain_password[:72]
    
    return pwd_context.verify(password_to_verify, hashed_password)

def create_access_token(data: dict) -> str:
    """
    Crée un access token JWT court (durée configurable via settings).

    Convention de payload utilisée dans le projet:
    - `sub`: id utilisateur (str UUID)
    - `role`: rôle courant (patient/medecin/admin)
    """
    to_encode = data.copy()
    now = datetime.now(timezone.utc)
    expire = now + timedelta(minutes=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)

def create_refresh_token(data: dict) -> str:
    """
    Créer un refresh token (durée de vie: 7 jours).
    """
    to_encode = data.copy()
    now = datetime.now(timezone.utc)
    expire = now + timedelta(days=7)
    to_encode.update({"exp": expire, "type": "refresh"})
    return jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)

def decode_token(token: str):
    """
    Décoder un token JWT.
    
    Returns:
        dict: Le payload du token si valide, None sinon.

    Note de sécurité:
    - cette fonction ne lève pas d'exception vers l'appelant,
      elle renvoie None pour tous les cas invalides (expiré, signature invalide, format invalide).
    """
    try:
        return jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
    except jwt.ExpiredSignatureError:
        # Token expiré
        return None
    except jwt.JWTError:
        # Token invalide (signature incorrecte, format invalide, etc.)
        return None
    except Exception:
        # Autre erreur
        return None
