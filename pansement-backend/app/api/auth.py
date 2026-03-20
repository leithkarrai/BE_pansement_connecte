from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from datetime import datetime, timedelta, timezone
import secrets
import uuid

from app.database import get_db
from app.schemas.auth import (
    LoginRequest, LoginResponse, RefreshTokenRequest, RefreshTokenResponse,
    ChangePasswordRequest, ForgotPasswordRequest, ResetPasswordRequest,
    VerifyEmailRequest, ResendVerificationRequest
)
from app.schemas.user import UserCreate, UserResponse, UserRole, RegisterRequest
from app.models.user import User
from app.core.security import (
    verify_password, hash_password, validate_password_strength,
    create_access_token, create_refresh_token, decode_token
)
from app.api.deps import get_current_user

router = APIRouter(prefix="/api/v1/auth", tags=["Authentication"])

@router.post('/register', response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def register(user_data: RegisterRequest, db: Session = Depends(get_db)):
    '''
    Inscription d'un nouvel utilisateur.
    Si role est omis, il est inféré :
    - medecin si des infos pro sont renseignées (rpps/specialty/establishment),
    - sinon patient.

    Important:
    - Le compte est créé inactif (is_active=False) et doit être validé par un admin.
    - Le rôle admin n'est pas auto-attribué ici par défaut.
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
        
        # Rôle : utiliser celui envoyé, sinon inférer selon les infos professionnelles.
        if user_data.role is not None:
            role_value = user_data.role.value if hasattr(user_data.role, 'value') else str(user_data.role)
        else:
            is_medecin = bool(
                (user_data.rpps_number and user_data.rpps_number.strip()) or
                (user_data.specialty and user_data.specialty.strip()) or
                (user_data.establishment and user_data.establishment.strip())
            )
            role_value = UserRole.MEDECIN.value if is_medecin else UserRole.PATIENT.value
        
        # Générer un token de vérification email (placeholder tant que l'envoi email n'est pas branché).
        verification_token = secrets.token_urlsafe(32)
        
        new_user = User(
            email=user_data.email,
            password_hash=hash_password(user_data.password),
            role=role_value,
            first_name=user_data.first_name,
            last_name=user_data.last_name,
            phone=user_data.phone,
            date_of_birth=user_data.date_of_birth,
            gender=user_data.gender,
            medical_record_number=user_data.medical_record_number,
            blood_type=user_data.blood_type,
            allergies=user_data.allergies,
            rpps_number=user_data.rpps_number,
            specialty=user_data.specialty,
            establishment=user_data.establishment,
            is_active=False,  # L'admin doit activer le compte pour que l'utilisateur puisse se connecter
            is_verified=False,
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
    Retourne:
    - access token (court)
    - refresh token (7 jours)

    Le login échoue volontairement avec un message générique sur les erreurs
    d'identifiants/hash pour éviter de divulguer la nature exacte de l'échec.
    '''
    try:
        # Trouver l'utilisateur
        user = db.query(User).filter(User.email == credentials.email).first()
        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail='Votre compte a été supprimé par un administrateur'
            )
        
        # Vérifier que le hash existe (ancienne BDD peut avoir NULL)
        if not user.password_hash:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail='Email ou mot de passe incorrect'
            )
        
        # Vérifier le mot de passe (éviter 500 si hash invalide en BDD)
        try:
            if not verify_password(credentials.password, user.password_hash):
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail='Email ou mot de passe incorrect'
                )
        except HTTPException:
            raise
        except Exception:
            # Hash bcrypt invalide ou autre erreur passlib
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail='Email ou mot de passe incorrect'
            )
        
        # Vérifier que le compte est actif.
        # Politique du projet: inscription => compte en attente de validation admin.
        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Compte en attente de validation. Un administrateur doit activer votre compte pour que vous puissiez vous connecter.'
            )
        
        # Mettre à jour last_login (ne pas faire échouer le login si erreur)
        try:
            user.last_login = datetime.now(timezone.utc)
            db.commit()
        except Exception:
            db.rollback()
            # Continuer sans mettre à jour last_login
        
        # Créer les tokens.
        # Payload minimal: sub + role, utilisé ensuite par deps.get_current_user / require_role.
        token_data = {'sub': str(user.id), 'role': str(user.role) if user.role else 'patient'}
        access_token = create_access_token(token_data)
        refresh_token = create_refresh_token(token_data)
        if isinstance(access_token, bytes):
            access_token = access_token.decode('utf-8')
        if isinstance(refresh_token, bytes):
            refresh_token = refresh_token.decode('utf-8')
        
        return {
            'access_token': access_token,
            'refresh_token': refresh_token,
            'token_type': 'bearer',
            'user': {
                'id': str(user.id),
                'email': str(user.email),
                'role': str(user.role) if user.role else 'patient',
                'first_name': str(user.first_name) if user.first_name else '',
                'last_name': str(user.last_name) if user.last_name else ''
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        # Message sûr pour le client (éviter caractères ou erreurs OS qui perturbent le parsing)
        err_msg = str(e).strip() or "Erreur inconnue"
        if "Errno 22" in err_msg or "Invalid argument" in err_msg:
            err_msg = "Erreur serveur lors de la connexion. Réessayez ou contactez l'administrateur."
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=err_msg[:500]
        )

@router.post('/refresh', response_model=RefreshTokenResponse)
def refresh_token(token_data: RefreshTokenRequest):
    '''
    Rafraîchir l'access token avec un refresh token.
    Vérifie explicitement payload['type'] == 'refresh'.
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
