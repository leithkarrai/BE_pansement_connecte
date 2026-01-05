from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
import secrets
import uuid

from app.database import get_db
from app.schemas.auth import (
    LoginRequest, LoginResponse, RefreshTokenRequest, RefreshTokenResponse,
    ChangePasswordRequest, ForgotPasswordRequest, ResetPasswordRequest,
    VerifyEmailRequest, ResendVerificationRequest
)
from app.schemas.user import UserCreate, UserResponse
from app.models.user import User
from app.core.security import (
    verify_password, hash_password, validate_password_strength,
    create_access_token, create_refresh_token, decode_token
)
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
        
        # Valider la force du mot de passe
        is_valid, error_message = validate_password_strength(user_data.password)
        if not is_valid:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message
            )
        
        # Créer le nouvel utilisateur
        # Convertir le rôle Pydantic en string (la colonne role est maintenant String au lieu d'Enum)
        role_value = user_data.role.value if hasattr(user_data.role, 'value') else str(user_data.role)
        
        # Générer un token de vérification email
        verification_token = secrets.token_urlsafe(32)
        
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
            allergies=user_data.allergies,
            is_verified=False,  # Email non vérifié par défaut
            email_verification_token=verification_token
        )
        
        db.add(new_user)
        db.commit()
        db.refresh(new_user)
        
        # TODO: Envoyer l'email de vérification
        # Exemple: send_verification_email(new_user.email, verification_token)
        print(f"Token de vérification pour {new_user.email}: {verification_token}")
        
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
        'is_verified': current_user.is_verified,
        'two_factor_enabled': current_user.two_factor_enabled,
        'medical_record_number': current_user.medical_record_number,
        'blood_type': current_user.blood_type
    }

@router.post('/change-password', status_code=status.HTTP_200_OK)
def change_password(
    password_data: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    '''
    Changer le mot de passe de l'utilisateur connecté.
    
    L'utilisateur doit fournir son ancien mot de passe pour confirmer l'identité.
    '''
    # Vérifier l'ancien mot de passe
    if not verify_password(password_data.old_password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Ancien mot de passe incorrect'
        )
    
    # Valider la force du nouveau mot de passe
    is_valid, error_message = validate_password_strength(password_data.new_password)
    if not is_valid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_message
        )
    
    # Mettre à jour avec le nouveau mot de passe
    current_user.password_hash = hash_password(password_data.new_password)
    db.commit()
    
    return {
        'message': 'Mot de passe modifié avec succès'
    }

@router.post('/forgot-password', status_code=status.HTTP_200_OK)
def forgot_password(
    request: ForgotPasswordRequest,
    db: Session = Depends(get_db)
):
    '''
    Demander une réinitialisation de mot de passe.
    Génère un token et l'envoie par email (à implémenter).
    '''
    user = db.query(User).filter(User.email == request.email).first()
    
    # Pour la sécurité, on ne révèle pas si l'email existe ou non
    if user:
        # Générer un token de réinitialisation
        reset_token = secrets.token_urlsafe(32)
        user.password_reset_token = reset_token
        user.password_reset_expires_at = datetime.utcnow() + timedelta(hours=1)  # Expire dans 1h
        db.commit()
        
        # TODO: Envoyer l'email avec le lien de réinitialisation
        # Exemple: send_reset_email(user.email, reset_token)
        print(f"Token de réinitialisation pour {user.email}: {reset_token}")
    
    # Toujours retourner le même message pour ne pas révéler si l'email existe
    return {
        'message': 'Si cet email existe, un lien de réinitialisation a été envoyé.'
    }

@router.post('/reset-password', status_code=status.HTTP_200_OK)
def reset_password(
    request: ResetPasswordRequest,
    db: Session = Depends(get_db)
):
    '''
    Réinitialiser le mot de passe avec un token.
    '''
    # Trouver l'utilisateur avec ce token valide
    user = db.query(User).filter(
        User.password_reset_token == request.token,
        User.password_reset_expires_at > datetime.utcnow()
    ).first()
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Token invalide ou expiré'
        )
    
    # Valider la force du nouveau mot de passe
    is_valid, error_message = validate_password_strength(request.new_password)
    if not is_valid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_message
        )
    
    # Mettre à jour le mot de passe
    user.password_hash = hash_password(request.new_password)
    user.password_reset_token = None
    user.password_reset_expires_at = None
    db.commit()
    
    return {
        'message': 'Mot de passe réinitialisé avec succès'
    }

@router.post('/verify-email', status_code=status.HTTP_200_OK)
def verify_email(
    request: VerifyEmailRequest,
    db: Session = Depends(get_db)
):
    '''
    Vérifier l'email d'un utilisateur avec un token.
    '''
    user = db.query(User).filter(
        User.email_verification_token == request.token
    ).first()
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Token de vérification invalide'
        )
    
    if user.is_verified:
        return {
            'message': 'Email déjà vérifié'
        }
    
    # Marquer l'email comme vérifié
    user.is_verified = True
    user.email_verified_at = datetime.utcnow()
    user.email_verification_token = None
    db.commit()
    
    return {
        'message': 'Email vérifié avec succès'
    }

@router.post('/resend-verification', status_code=status.HTTP_200_OK)
def resend_verification(
    request: ResendVerificationRequest,
    db: Session = Depends(get_db)
):
    '''
    Renvoyer l'email de vérification.
    '''
    user = db.query(User).filter(User.email == request.email).first()
    
    if not user:
        # Ne pas révéler si l'email existe
        return {
            'message': 'Si cet email existe, un email de vérification a été envoyé.'
        }
    
    if user.is_verified:
        return {
            'message': 'Cet email est déjà vérifié'
        }
    
    # Générer un nouveau token de vérification
    verification_token = secrets.token_urlsafe(32)
    user.email_verification_token = verification_token
    db.commit()
    
    # TODO: Envoyer l'email de vérification
    # Exemple: send_verification_email(user.email, verification_token)
    print(f"Token de vérification pour {user.email}: {verification_token}")
    
    return {
        'message': 'Si cet email existe, un email de vérification a été envoyé.'
    }
