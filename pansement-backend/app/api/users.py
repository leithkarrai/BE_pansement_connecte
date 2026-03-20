from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import text
from typing import Optional
from uuid import UUID

from app.database import get_db
from app.schemas.user import UserCreate, UserUpdate, UserResponse, UserList
from app.models.user import User
from app.models.patient_device import PatientDevice
from app.models.patient_medecin import PatientMedecin
from app.core.security import hash_password
from app.api.deps import get_current_user, require_role
from app.core.redis_client import cache_get, cache_set, cache_delete

router = APIRouter(prefix="/api/v1/users", tags=["Users"])

# ============================================================================
# GET /api/v1/users - Liste des utilisateurs
# ============================================================================

@router.get('', response_model=UserList)
def get_users(
    skip: int = Query(0, ge=0, description='Nombre d\'éléments à sauter'),
    limit: int = Query(10, ge=1, le=100, description='Nombre d\'éléments à retourner'),
    role: Optional[str] = Query(None, description='Filtrer par rôle'),
    search: Optional[str] = Query(None, description='Rechercher par nom ou email'),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    '''
    Liste des utilisateurs avec pagination et filtres.
    
    Permissions:
    - Admin: Voit tous les utilisateurs
    - Médecin: Voit uniquement ses patients
    - Patient: Accès refusé

    Notes:
    - Le provider mobile admin agrège souvent patients + médecins via le filtre role.
    - Le retour est paginé (skip/limit) et trié du plus récent au plus ancien.
    '''
    # Vérifier les permissions
    if current_user.role == 'patient':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Accès refusé. Réservé aux médecins et admins.'
        )
    
    # Construire la requête de base
    query = db.query(User)
    
    # Si médecin: filtrer uniquement ses patients.
    # La relation est lue via la table medecin_patients (compat héritage SQL existant).
    if current_user.role == 'medecin':
        # Récupérer les IDs des patients du médecin via SQL
        result = db.execute(
            text("SELECT patient_id FROM medecin_patients WHERE medecin_id = :medecin_id"),
            {"medecin_id": str(current_user.id)}
        )
        patient_ids = [row[0] for row in result.fetchall()]
        
        if not patient_ids:
            # Si le médecin n'a pas de patients, retourner une liste vide
            return {
                'users': [],
                'total': 0,
                'page': 1,
                'per_page': limit
            }
        
        query = query.filter(User.id.in_(patient_ids))
    
    # Filtrer par rôle si spécifié
    if role:
        query = query.filter(User.role == role)
    
    # Recherche par nom ou email
    if search:
        search_pattern = f'%{search}%'
        query = query.filter(
            (User.first_name.ilike(search_pattern)) |
            (User.last_name.ilike(search_pattern)) |
            (User.email.ilike(search_pattern))
        )
    
    # Compter le total
    total = query.count()
    
    # Pagination
    users = query.order_by(User.created_at.desc()).offset(skip).limit(limit).all()
    
    # Convertir les objets User en dictionnaires pour UserResponse
    users_list = []
    for user in users:
        users_list.append({
            'id': str(user.id),
            'email': user.email,
            'role': user.role,
            'first_name': user.first_name,
            'last_name': user.last_name,
            'phone': user.phone,
            'date_of_birth': user.date_of_birth,
            'gender': user.gender,
            'created_at': user.created_at,
            'updated_at': user.updated_at,
            'last_login': user.last_login,
            'is_active': user.is_active,
            'medical_record_number': user.medical_record_number,
            'blood_type': user.blood_type
        })
    
    return {
        'users': users_list,
        'total': total,
        'page': skip // limit + 1 if limit > 0 else 1,
        'per_page': limit
    }

# ============================================================================
# GET /api/v1/users/{user_id} - Détails d'un utilisateur
# ============================================================================

@router.get('/{user_id}', response_model=UserResponse)
def get_user(
    user_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    '''
    Récupérer les détails d'un utilisateur.
    
    Permissions:
    - Admin: Peut voir n'importe quel utilisateur
    - Médecin: Peut voir ses patients
    - Patient: Peut voir uniquement ses propres infos
    '''
    # Convertir user_id en UUID
    try:
        user_uuid = UUID(user_id)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='ID utilisateur invalide'
        )
    
    # Cache Redis (lecture) pour réduire la charge sur la fiche utilisateur.
    cache_key = f"user:{user_id}"
    cached_user = cache_get(cache_key)
    if cached_user:
        user_dict = cached_user
    else:
        # Chercher l'utilisateur dans la base de données
        user = db.query(User).filter(User.id == user_uuid).first()
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail='Utilisateur non trouvé'
            )
        
        # Construire le dictionnaire utilisateur
        user_dict = {
            'id': str(user.id),
            'email': user.email,
            'role': user.role,
            'first_name': user.first_name,
            'last_name': user.last_name,
            'phone': user.phone,
            'date_of_birth': user.date_of_birth,
            'gender': user.gender,
            'created_at': user.created_at,
            'updated_at': user.updated_at,
            'last_login': user.last_login,
            'is_active': user.is_active,
            'medical_record_number': user.medical_record_number,
            'blood_type': user.blood_type
        }
        
        # Cache write-through (1h) après lecture DB.
        cache_set(cache_key, user_dict, expire=3600)
    
    # Vérifier les permissions
    if current_user.role == 'admin':
        # Admin peut tout voir
        return user_dict
    
    elif current_user.role == 'medecin':
        # Médecin peut voir ses patients ou lui-même
        if user_dict['id'] == str(current_user.id):
            return user_dict
        
        # Vérifier si c'est un de ses patients
        if user_dict['role'] == 'patient':
            result = db.execute(
                text("SELECT id FROM medecin_patients WHERE medecin_id = :medecin_id AND patient_id = :patient_id"),
                {"medecin_id": str(current_user.id), "patient_id": user_dict['id']}
            )
            relation = result.fetchone()
            
            if relation:
                return user_dict
        
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Accès refusé. Ce patient n\'est pas sous votre responsabilité.'
        )
    
    elif current_user.role == 'patient':
        # Patient peut voir uniquement ses propres infos
        if user_dict['id'] != str(current_user.id):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Accès refusé. Vous ne pouvez consulter que vos propres informations.'
            )
        return user_dict

# ============================================================================
# POST /api/v1/users - Créer un utilisateur (Admin uniquement)
# ============================================================================

@router.post('', response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def create_user(
    user_data: UserCreate,
    current_user: User = Depends(require_role(['admin'])),
    db: Session = Depends(get_db)
):
    '''
    Créer un nouvel utilisateur.
    
    Permissions: Admin uniquement.

    Important:
    - L'endpoint peut créer patient, medecin ou admin selon `role`.
    - Le mot de passe est hashé côté backend (jamais stocké en clair).
    '''
    # Vérifier si l'email existe déjà
    existing_user = db.query(User).filter(User.email == user_data.email).first()
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Cet email est déjà utilisé'
        )
    
    # Créer l'utilisateur
    role_value = user_data.role.value if hasattr(user_data.role, 'value') else str(user_data.role)
    
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
        allergies=user_data.allergies
    )
    
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    # ✨ Invalider le cache des listes d'utilisateurs
    cache_delete("users:list:*")
    
    return {
        'id': str(new_user.id),
        'email': new_user.email,
        'role': new_user.role,
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

# ============================================================================
# PUT /api/v1/users/{user_id} - Modifier un utilisateur
# ============================================================================

@router.put('/{user_id}', response_model=UserResponse)
def update_user(
    user_id: str,
    user_data: UserUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    '''
    Modifier un utilisateur.
    
    Permissions:
    - Admin: Peut modifier n'importe qui
    - Médecin: Peut modifier ses propres infos uniquement
    - Patient: Peut modifier ses propres infos uniquement
    '''
    # Convertir user_id en UUID
    try:
        user_uuid = UUID(user_id)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='ID utilisateur invalide'
        )
    
    # Chercher l'utilisateur à modifier
    user = db.query(User).filter(User.id == user_uuid).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Utilisateur non trouvé'
        )
    
    # Vérifier les permissions
    if current_user.role != 'admin' and str(user.id) != str(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Accès refusé. Vous ne pouvez modifier que vos propres informations.'
        )
    
    # Mettre à jour les champs fournis
    update_data = user_data.dict(exclude_unset=True)
    # Seul l'admin peut activer/désactiver un compte (is_active)
    if 'is_active' in update_data and (getattr(current_user, 'role', None) or '').strip().lower() != 'admin':
        del update_data['is_active']
    
    # Si le mot de passe est fourni, le hasher
    if 'password' in update_data and update_data['password']:
        update_data['password_hash'] = hash_password(update_data['password'])
        del update_data['password']
    
    # Vérifier unicité email si modifié
    if 'email' in update_data and update_data['email'] != user.email:
        existing = db.query(User).filter(User.email == update_data['email']).first()
        if existing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail='Cet email est déjà utilisé'
            )
    
    # Appliquer les modifications
    for key, value in update_data.items():
        if hasattr(user, key):
            setattr(user, key, value)
    
    db.commit()
    db.refresh(user)
    
    # ✨ Invalider le cache de cet utilisateur et des listes
    cache_delete(f"user:{user_id}")
    cache_delete("users:list:*")
    
    return {
        'id': str(user.id),
        'email': user.email,
        'role': user.role,
        'first_name': user.first_name,
        'last_name': user.last_name,
        'phone': user.phone,
        'date_of_birth': user.date_of_birth,
        'gender': user.gender,
        'created_at': user.created_at,
        'updated_at': user.updated_at,
        'last_login': user.last_login,
        'is_active': user.is_active,
        'is_verified': user.is_verified,
        'two_factor_enabled': user.two_factor_enabled,
        'medical_record_number': user.medical_record_number,
        'blood_type': user.blood_type
    }

# ============================================================================
# DELETE /api/v1/users/{user_id} - Supprimer un utilisateur (Admin uniquement)
# ============================================================================

@router.delete('/{user_id}', status_code=status.HTTP_204_NO_CONTENT)
def delete_user(
    user_id: str,
    current_user: User = Depends(require_role(['admin'])),
    db: Session = Depends(get_db)
):
    '''
    Supprimer un utilisateur (soft delete: is_active = False).
    
    Permissions: Admin uniquement.

    Règle métier:
    - Soft delete uniquement (historique conservé).
    - Interdiction de supprimer son propre compte admin.
    '''
    # Convertir user_id en UUID
    try:
        user_uuid = UUID(user_id)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='ID utilisateur invalide'
        )
    
    # Chercher l'utilisateur
    user = db.query(User).filter(User.id == user_uuid).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Utilisateur non trouvé'
        )
    
    # Empêcher la suppression de soi-même
    if str(user.id) == str(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Vous ne pouvez pas supprimer votre propre compte'
        )
    
    # Soft delete: désactiver le compte
    user.is_active = False
    db.commit()
    
    # ✨ Invalider le cache de cet utilisateur et des listes
    cache_delete(f"user:{user_id}")
    cache_delete("users:list:*")
    
    return None

# ============================================================================
# DELETE /api/v1/users/{user_id}/hard - Suppression définitive (Admin uniquement)
# ============================================================================

@router.delete('/{user_id}/hard', status_code=status.HTTP_204_NO_CONTENT)
def hard_delete_user(
    user_id: str,
    current_user: User = Depends(require_role(['admin'])),
    db: Session = Depends(get_db),
):
    '''
    Suppression définitive (hard delete) d'un utilisateur.

    Permissions:
    - Admin uniquement.

    Règle métier:
    - Ne pas supprimer son propre compte admin.
    - (Objectif sécurité) Avant de supprimer l'utilisateur, on purge les
      associations `patient_devices` car `patient_devices.patient_id`
      n'a pas de `ON DELETE CASCADE` (sinon PostgreSQL refusera le DELETE).
    - Les autres dépendances (commentaires, alertes, associations patient/medecin)
      sont supprimées via `ON DELETE CASCADE` selon le schéma existant.
    '''
    try:
        user_uuid = UUID(user_id)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='ID utilisateur invalide',
        )

    user = db.query(User).filter(User.id == user_uuid).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Utilisateur non trouvé',
        )

    # On interdit la suppression de son propre compte admin.
    if str(user.id) == str(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Vous ne pouvez pas supprimer votre propre compte',
        )

    # On limite volontairement à patient + medecin (pas d'admin purge).
    if user.role not in ['patient', 'medecin']:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Suppression définitive uniquement pour patient ou medecin',
        )

    import traceback
    print(
        f"[hard_delete_user] called by admin={current_user.id} "
        f"target={user_id} role={getattr(current_user, 'role', None)}"
    )

    try:
        # IMPORTANT:
        # Utiliser uniquement des DELETE SQL directs pour éviter que l'ORM
        # tente des UPDATE du type `SET patient_id=NULL` (ce qui casse
        # les NOT NULL avant que la cascade DB s'applique).
        pid = str(user_uuid)

        # 1) Purger les commentaires (référence NOT NULL sur patient_id/medecin_id)
        db.execute(
            text("""
                DELETE FROM comments
                WHERE patient_id = CAST(:pid AS uuid)
                   OR medecin_id = CAST(:pid AS uuid)
            """),
            {"pid": pid},
        )

        # 2) Purger patient_devices (patient_id n'a pas de ON DELETE CASCADE)
        db.execute(
            text("""
                DELETE FROM patient_devices
                WHERE patient_id = CAST(:pid AS uuid)
            """),
            {"pid": pid},
        )

        # 3) Purge table d'association patient/medecin (cascade théorique, mais
        #    on la sécurise pour réduire le risque de contraintes).
        db.execute(
            text("""
                DELETE FROM medecin_patients
                WHERE patient_id = CAST(:pid AS uuid)
                   OR medecin_id = CAST(:pid AS uuid)
            """),
            {"pid": pid},
        )

        # 4) Hard delete de l'utilisateur
        db.execute(
            text("""
                DELETE FROM users
                WHERE id = CAST(:pid AS uuid)
            """),
            {"pid": pid},
        )

        db.commit()
    except Exception as e:
        db.rollback()
        # Loguer le traceback complet: indispensable pour diagnostiquer
        # les erreurs de contraintes FK lors d'un hard delete.
        print("[hard_delete_user] Exception during db operations:", type(e).__name__, str(e))
        print(traceback.format_exc())
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f'Erreur lors de la suppression définitive: {str(e)}',
        )

    # Invalidation cache.
    try:
        cache_delete(f"user:{user_id}")
        cache_delete("users:list:*")
    except Exception as e:
        # Ne pas fail la suppression si Redis est down.
        print("[hard_delete_user] Cache invalidation failed:", type(e).__name__, str(e))
        print(traceback.format_exc())

    return None


# ============================================================================
# GET /api/v1/users/{patient_id}/medecin
# Médecin assigné à un patient (utilisé par le mobile)
# ============================================================================
@router.get('/{patient_id}/medecin')
def get_patient_medecin(
    patient_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retourne le médecin assigné à un patient.

    - Admin : peut consulter pour n'importe quel patient
    - Médecin : (optionnel) peut consulter son propre assignement (facultatif côté UI)
    - Patient : uniquement pour lui-même
    """
    try:
        patient_uuid = UUID(patient_id)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="ID utilisateur invalide",
        )

    # Permission patient: uniquement son propre dossier
    if current_user.role == "patient" and str(current_user.id) != patient_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Accès refusé",
        )

    assignment_query = db.query(PatientMedecin).filter(
        PatientMedecin.patient_id == patient_uuid,
    )

    # Permission médecin: limiter à ses propres assignations (optionnel)
    if current_user.role == "medecin":
        assignment_query = assignment_query.filter(
            PatientMedecin.medecin_id == current_user.id
        )

    assignment = (
        assignment_query.order_by(PatientMedecin.assigned_at.desc()).first()
    )

    if not assignment:
        # Conserver la compatibilité mobile: le provider considère `{"medecin": None}` comme "aucun médecin"
        return {"medecin": None, "patient_id": patient_id}

    medecin = db.query(User).filter(User.id == assignment.medecin_id).first()
    if not medecin:
        return {"medecin": None, "patient_id": patient_id}

    # Eviter un ValidationError Pydantic: `UserResponse.id` attend un `str`,
    # alors que `medecin.id` est un `UUID` SQLAlchemy.
    medecin_json = {
        "id": str(medecin.id),
        "email": medecin.email,
        "role": medecin.role,
        "first_name": medecin.first_name,
        "last_name": medecin.last_name,
        "phone": medecin.phone,
        "blood_type": getattr(medecin, "blood_type", None),
        "is_active": medecin.is_active,
        "is_verified": medecin.is_verified,
        "two_factor_enabled": medecin.two_factor_enabled,
        "rpps_number": getattr(medecin, "rpps_number", None),
        "specialty": getattr(medecin, "specialty", None),
        "establishment": getattr(medecin, "establishment", None),
        "date_of_birth": getattr(medecin, "date_of_birth", None),
        "created_at": getattr(medecin, "created_at", None),
    }

    return {"medecin": medecin_json, "patient_id": patient_id}


# ============================================================================
# POST /api/v1/users/{patient_id}/assign-medecin/{medecin_id}
# Compatibilité (ancienne route)
# ============================================================================
@router.post('/{patient_id}/assign-medecin/{medecin_id}', status_code=status.HTTP_201_CREATED)
def assign_patient_to_medecin_compat(
    patient_id: str,
    medecin_id: str,
    current_user: User = Depends(require_role(['admin'])),
    db: Session = Depends(get_db),
):
    """
    Assigner un patient à un médecin (ancienne route API).

    La route "courante" du projet est POST /api/v1/comments/assign-patient.
    Cette route est conservée pour compatibilité UI / versions précédentes.
    """
    try:
        patient_uuid = UUID(patient_id)
        medecin_uuid = UUID(medecin_id)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='ID utilisateur invalide',
        )

    # Vérifier patient
    patient = db.query(User).filter(
        User.id == patient_uuid,
        User.role == 'patient',
    ).first()
    if not patient:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Patient non trouvé',
        )

    # Vérifier médecin
    medecin = db.query(User).filter(
        User.id == medecin_uuid,
        User.role == 'medecin',
    ).first()
    if not medecin:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Médecin non trouvé',
        )

    # Vérifier existence
    existing = db.execute(
        text("""
            SELECT id
            FROM medecin_patients
            WHERE patient_id = CAST(:pid AS uuid)
              AND medecin_id = CAST(:mid AS uuid)
        """),
        {"pid": str(patient_uuid), "mid": str(medecin_uuid)},
    ).fetchone()

    if existing:
        return {
            "success": True,
            "message": "Association déjà existante",
        }

    # Insertion (is_primary/assigned_date ont des defaults en DB)
    db.execute(
        text("""
            INSERT INTO medecin_patients (patient_id, medecin_id)
            VALUES (CAST(:pid AS uuid), CAST(:mid AS uuid))
        """),
        {"pid": str(patient_uuid), "mid": str(medecin_uuid)},
    )
    db.commit()

    # Invalider cache (si présent)
    try:
        cache_delete(f"user:{patient_id}")
        cache_delete("users:list:*")
    except Exception:
        pass

    return {
        "success": True,
        "message": "Patient assigné au médecin avec succès",
    }


# ============================================================================
# DELETE /api/v1/users/{patient_id}/assign-medecin/{medecin_id}
# Compatibilité (ancienne route)
# ============================================================================
@router.delete(
    '/{patient_id}/assign-medecin/{medecin_id}',
    status_code=status.HTTP_204_NO_CONTENT,
)
def unassign_patient_from_medecin_compat(
    patient_id: str,
    medecin_id: str,
    current_user: User = Depends(require_role(['admin'])),
    db: Session = Depends(get_db),
):
    """Retirer l'association patient <-> médecin (ancienne route API)."""
    try:
        patient_uuid = UUID(patient_id)
        medecin_uuid = UUID(medecin_id)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='ID utilisateur invalide',
        )

    db.execute(
        text("""
            DELETE FROM medecin_patients
            WHERE patient_id = CAST(:pid AS uuid)
              AND medecin_id = CAST(:mid AS uuid)
        """),
        {"pid": str(patient_uuid), "mid": str(medecin_uuid)},
    )
    db.commit()

    try:
        cache_delete(f"user:{patient_id}")
        cache_delete("users:list:*")
    except Exception:
        pass

    return None
