from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from datetime import datetime

from app.database import get_db
from app.schemas.auth import LoginRequest, LoginResponse, RefreshTokenRequest, RefreshTokenResponse
from app.schemas.user import UserCreate, UserResponse
from app.models.user import User
from app.core.security import verify_password, hash_password, create_access_token, create_refresh_token, decode_token
from app.api.deps import get_current_user

router = APIRouter(prefix="/api/v1/auth", tags=["Authentication"])

@router.post('/register', response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def register(user_data: UserCreate, db: Session = Depends(get_db)):
    '''
    Inscription d'un nouvel utilisateur.
    '''
    try:
        # Vérifier si l'email existe déjà
        existing_user = db.query(User).filter(User.email == user_data.email).first()
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail='Cet email est déjà utilisé'
            )
        
        # Créer le nouvel utilisateur
        # Convertir le rôle Pydantic en string (la colonne role est maintenant String au lieu d'Enum)
        role_value = user_data.role.value if hasattr(user_data.role, 'value') else str(user_data.role)
        
        new_user = User(
            email=user_data.email,
            password_hash=hash_password(user_data.password),
            role=role_value,  # Utiliser directement la valeur string ('patient', 'medecin', ou 'admin')
            first_name=user_data.first_name,
            last_name=user_data.last_name,
            phone=user_data.phone,
            date_of_birth=user_data.date_of_birth,
            gender=user_data.gender,
            medical_record_number=user_data.medical_record_number,
            blood_type=user_data.blood_type,
            allergies=user_data.allergies
        )
        
        db.add(new_user)
        db.commit()
        db.refresh(new_user)
        
        # Convertir l'objet User en UserResponse
        # UserResponse attend id: str, donc on convertit l'UUID
        return {
            'id': str(new_user.id),
            'email': new_user.email,
            'role': new_user.role,  # role est maintenant un string directement
            'first_name': new_user.first_name,
            'last_name': new_user.last_name,
            'phone': new_user.phone,
            'date_of_birth': new_user.date_of_birth,
            'gender': new_user.gender,
            'created_at': new_user.created_at,
            'updated_at': new_user.updated_at,
            'last_login': new_user.last_login,
            'is_active': new_user.is_active,
            'medical_record_number': new_user.medical_record_number,
            'blood_type': new_user.blood_type
        }
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f'Erreur lors de l\'inscription: {str(e)}'
        )

@router.post('/login', response_model=LoginResponse)
def login(credentials: LoginRequest, db: Session = Depends(get_db)):
    '''
    Connexion utilisateur.
    Retourne un access token (15 min) et un refresh token (7 jours).
    '''
    # Trouver l'utilisateur
    user = db.query(User).filter(User.email == credentials.email).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Email ou mot de passe incorrect'
        )
    
    # Vérifier le mot de passe
    if not verify_password(credentials.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Email ou mot de passe incorrect'
        )
    
    # Vérifier que le compte est actif
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Compte désactivé. Contactez un administrateur.'
        )
    
    # Mettre à jour last_login
    user.last_login = datetime.utcnow()
    db.commit()
    
    # Créer les tokens
    token_data = {'sub': str(user.id), 'role': user.role}  # role est maintenant un string
    access_token = create_access_token(token_data)
    refresh_token = create_refresh_token(token_data)
    
    return {
        'access_token': access_token,
        'refresh_token': refresh_token,
        'token_type': 'bearer',
        'user': {
            'id': str(user.id),
            'email': user.email,
            'role': user.role,  # role est maintenant un string
            'first_name': user.first_name,
            'last_name': user.last_name
        }
    }

@router.post('/refresh', response_model=RefreshTokenResponse)
def refresh_token(token_data: RefreshTokenRequest):
    '''
    Rafraîchir l'access token avec un refresh token.
    '''
    payload = decode_token(token_data.refresh_token)
    if payload is None or payload.get('type') != 'refresh':
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Refresh token invalide ou expiré'
        )
    
    # Créer un nouveau access token
    new_token_data = {'sub': payload.get('sub'), 'role': payload.get('role')}
    new_access_token = create_access_token(new_token_data)
    
    return {
        'access_token': new_access_token,
        'token_type': 'bearer'
    }

@router.get('/me', response_model=UserResponse)
def get_current_user_info(current_user: User = Depends(get_current_user)):
    '''
    Obtenir les informations de l'utilisateur connecté.
    '''
    # Convertir l'objet User en UserResponse
    # UserResponse attend id: str, donc on convertit l'UUID
    return {
        'id': str(current_user.id),
        'email': current_user.email,
        'role': current_user.role,  # role est maintenant un string
        'first_name': current_user.first_name,
        'last_name': current_user.last_name,
        'phone': current_user.phone,
        'date_of_birth': current_user.date_of_birth,
        'gender': current_user.gender,
        'created_at': current_user.created_at,
        'updated_at': current_user.updated_at,
        'last_login': current_user.last_login,
        'is_active': current_user.is_active,
        'medical_record_number': current_user.medical_record_number,
        'blood_type': current_user.blood_type
    }
