from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from typing import Optional
from uuid import UUID

from app.database import get_db
from app.core.security import decode_token
from app.models.user import User

# Security scheme
security = HTTPBearer()

def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db)
) -> User:
    '''
    Dépendance FastAPI pour obtenir l'utilisateur connecté.
    Vérifie le JWT token dans le header Authorization.

    Chaîne de validation:
    1) token JWT présent et valide
    2) claim `sub` présent et parseable en UUID
    3) utilisateur existant en base
    4) compte actif (is_active=True)
    '''
    token = credentials.credentials
    
    # Décoder le token
    payload = decode_token(token)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Token invalide ou expiré',
            headers={'WWW-Authenticate': 'Bearer'}
        )
    
    # Récupérer l'user_id du payload (claim standard "sub")
    user_id: str = payload.get('sub')
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Token invalide',
            headers={'WWW-Authenticate': 'Bearer'}
        )
    
    # Convertir user_id en UUID avant la requête SQL (évite toute ambiguïté)
    try:
        user_uuid = UUID(user_id)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Token invalide: ID utilisateur invalide',
            headers={'WWW-Authenticate': 'Bearer'}
        )
    
    # Chercher l'utilisateur en base: le token seul n'est jamais une autorisation suffisante.
    user = db.query(User).filter(User.id == user_uuid).first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Votre compte a été supprimé par un administrateur'
        )
    
    # Vérifier que l'utilisateur est actif (soft-delete => accès interdit)
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Compte désactivé'
        )
    
    return user

def get_current_active_user(
    current_user: User = Depends(get_current_user)
) -> User:
    '''Alias pour get_current_user (plus explicite)'''
    return current_user

def require_role(allowed_roles: list[str]):
    '''
    Dépendance pour exiger un rôle spécifique (comparaison insensible à la casse).
    Usage: current_user = Depends(require_role(['admin', 'medecin']))

    Note:
    - Le contrôle de rôle est fait côté backend (source d'autorité),
      même si l'UI masque déjà certaines actions.
    '''
    def role_checker(current_user: User = Depends(get_current_user)) -> User:
        role_lower = (current_user.role or "").strip().lower()
        allowed_lower = [r.strip().lower() for r in allowed_roles]
        if role_lower not in allowed_lower:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f'Accès réservé aux rôles: {allowed_roles}'
            )
        return current_user
    return role_checker

