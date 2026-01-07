from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import desc
from typing import Optional
from uuid import UUID

from app.database import get_db
from app.schemas.comment import (
    CommentCreate, CommentUpdate, CommentResponse, PatientAssignment,
    CommentListResponse, UnreadCountResponse
)
from app.models import Comment, User, PatientMedecin
from app.api.deps import get_current_user

router = APIRouter(prefix="/api/v1/comments", tags=["Comments"])

# ============================================================================
# GET /api/v1/comments/patient/{patient_id}
# Récupérer tous les commentaires d'un patient
# ============================================================================

@router.get("/patient/{patient_id}", response_model=CommentListResponse)
def get_patient_comments(
    patient_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Récupérer tous les commentaires d'un patient.
    
    - **patient_id**: UUID du patient
    
    Accessible par : Patient (ses propres commentaires), Médecin (ses patients), Admin (tous)
    """
    # Vérification des permissions
    try:
        patient_uuid = UUID(patient_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="ID patient invalide"
        )
    
    if current_user.role == "patient" and str(current_user.id) != patient_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Accès refusé"
        )
    
    if current_user.role == "medecin":
        # Vérifier que le patient est bien assigné à ce médecin
        assignment = db.query(PatientMedecin).filter(
            PatientMedecin.patient_id == patient_uuid,
            PatientMedecin.medecin_id == current_user.id
        ).first()
        
        if not assignment:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Ce patient ne vous est pas assigné"
            )
    
    # Récupérer les commentaires avec les infos du médecin
    comments = db.query(Comment).filter(
        Comment.patient_id == patient_uuid
    ).order_by(desc(Comment.created_at)).all()
    
    # Enrichir avec le nom du médecin
    comments_data = []
    for comment in comments:
        medecin = db.query(User).filter(User.id == comment.medecin_id).first()
        medecin_name = f"{medecin.first_name} {medecin.last_name}" if medecin else "Inconnu"
        
        comments_data.append(CommentResponse(
            id=str(comment.id),
            patient_id=str(comment.patient_id),
            medecin_id=str(comment.medecin_id),
            medecin_name=medecin_name,
            comment_text=comment.comment_text,
            is_read=comment.is_read,
            measurement_id=str(comment.measurement_id) if comment.measurement_id else None,
            created_at=comment.created_at,
            updated_at=comment.updated_at if comment.updated_at else comment.created_at
        ))
    
    return CommentListResponse(
        success=True,
        comments=comments_data,
        total=len(comments_data)
    )

# ============================================================================
# GET /api/v1/comments/unread/patient/{patient_id}
# Nombre de commentaires non lus
# ============================================================================

@router.get("/unread/patient/{patient_id}", response_model=UnreadCountResponse)
def get_unread_count(
    patient_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Récupérer le nombre de commentaires non lus d'un patient.
    
    Accessible par : Patient uniquement (ses propres commentaires)
    """
    # Seul le patient peut voir ses propres non-lus
    try:
        patient_uuid = UUID(patient_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="ID patient invalide"
        )
    
    if current_user.role == "patient" and str(current_user.id) != patient_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Accès refusé"
        )
    
    unread_count = db.query(Comment).filter(
        Comment.patient_id == patient_uuid,
        Comment.is_read == False
    ).count()
    
    return UnreadCountResponse(
        success=True,
        unread_count=unread_count
    )

# ============================================================================
# POST /api/v1/comments
# Créer un nouveau commentaire
# ============================================================================

@router.post("", response_model=dict, status_code=status.HTTP_201_CREATED)
def create_comment(
    comment_data: CommentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Créer un nouveau commentaire pour un patient.
    
    Accessible par : Médecin, Admin
    """
    # Vérifier que l'utilisateur est médecin ou admin
    if current_user.role not in ["medecin", "admin"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Seuls les médecins et admins peuvent ajouter des commentaires"
        )
    
    # Validation
    if not comment_data.comment_text or len(comment_data.comment_text.strip()) == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Le commentaire ne peut pas être vide"
        )
    
    # Si médecin, vérifier qu'il est assigné au patient
    if current_user.role == "medecin":
        try:
            patient_uuid = UUID(comment_data.patient_id)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="ID patient invalide"
            )
        
        assignment = db.query(PatientMedecin).filter(
            PatientMedecin.patient_id == patient_uuid,
            PatientMedecin.medecin_id == current_user.id
        ).first()
        
        if not assignment:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Ce patient ne vous est pas assigné"
            )
    
    # Vérifier que le patient existe
    try:
        patient_uuid = UUID(comment_data.patient_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="ID patient invalide"
        )
    
    patient = db.query(User).filter(
        User.id == patient_uuid,
        User.role == "patient"
    ).first()
    
    if not patient:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Patient non trouvé"
        )
    
    # Créer le commentaire
    new_comment = Comment(
        patient_id=patient_uuid,
        medecin_id=current_user.id,
        comment_text=comment_data.comment_text.strip(),
        measurement_id=UUID(comment_data.measurement_id) if comment_data.measurement_id else None,
        is_read=False
    )
    
    db.add(new_comment)
    db.commit()
    db.refresh(new_comment)
    
    # Récupérer le nom du médecin
    medecin = db.query(User).filter(User.id == current_user.id).first()
    medecin_name = f"{medecin.first_name} {medecin.last_name}" if medecin else "Inconnu"
    
    # TODO: Envoyer une notification push au patient
    
    return {
        "success": True,
        "comment": {
            "id": str(new_comment.id),
            "patient_id": str(new_comment.patient_id),
            "medecin_id": str(new_comment.medecin_id),
            "medecin_name": medecin_name,
            "comment_text": new_comment.comment_text,
            "is_read": new_comment.is_read,
            "measurement_id": str(new_comment.measurement_id) if new_comment.measurement_id else None,
            "created_at": new_comment.created_at.isoformat(),
            "updated_at": new_comment.updated_at.isoformat() if new_comment.updated_at else new_comment.created_at.isoformat()
        },
        "message": "Commentaire créé avec succès"
    }

# ============================================================================
# PUT /api/v1/comments/{comment_id}
# Modifier un commentaire
# ============================================================================

@router.put("/{comment_id}", response_model=dict)
def update_comment(
    comment_id: str,
    comment_data: CommentUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Modifier un commentaire existant.
    
    Accessible par : Médecin (son propre commentaire), Admin
    """
    # Vérifier que l'utilisateur est médecin ou admin
    if current_user.role not in ["medecin", "admin"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Accès refusé"
        )
    
    # Validation
    if not comment_data.comment_text or len(comment_data.comment_text.strip()) == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Le commentaire ne peut pas être vide"
        )
    
    # Récupérer le commentaire
    try:
        comment_uuid = UUID(comment_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="ID commentaire invalide"
        )
    
    comment = db.query(Comment).filter(Comment.id == comment_uuid).first()
    
    if not comment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Commentaire non trouvé"
        )
    
    # Si médecin, vérifier qu'il est l'auteur
    if current_user.role == "medecin" and str(comment.medecin_id) != str(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Vous ne pouvez modifier que vos propres commentaires"
        )
    
    # Mettre à jour
    comment.comment_text = comment_data.comment_text.strip()
    db.commit()
    db.refresh(comment)
    
    return {
        "success": True,
        "comment": {
            "id": str(comment.id),
            "comment_text": comment.comment_text,
            "updated_at": comment.updated_at.isoformat() if comment.updated_at else None
        },
        "message": "Commentaire mis à jour"
    }

# ============================================================================
# DELETE /api/v1/comments/{comment_id}
# Supprimer un commentaire
# ============================================================================

@router.delete("/{comment_id}", response_model=dict)
def delete_comment(
    comment_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Supprimer un commentaire.
    
    Accessible par : Médecin (son propre commentaire), Admin
    """
    # Vérifier que l'utilisateur est médecin ou admin
    if current_user.role not in ["medecin", "admin"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Accès refusé"
        )
    
    # Récupérer le commentaire
    try:
        comment_uuid = UUID(comment_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="ID commentaire invalide"
        )
    
    comment = db.query(Comment).filter(Comment.id == comment_uuid).first()
    
    if not comment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Commentaire non trouvé"
        )
    
    # Si médecin, vérifier qu'il est l'auteur
    if current_user.role == "medecin" and str(comment.medecin_id) != str(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Vous ne pouvez supprimer que vos propres commentaires"
        )
    
    # Supprimer
    db.delete(comment)
    db.commit()
    
    return {
        "success": True,
        "message": "Commentaire supprimé"
    }

# ============================================================================
# PATCH /api/v1/comments/{comment_id}/read
# Marquer un commentaire comme lu
# ============================================================================

@router.patch("/{comment_id}/read", response_model=dict)
def mark_comment_as_read(
    comment_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Marquer un commentaire comme lu.
    
    Accessible par : Patient uniquement (ses propres commentaires)
    """
    # Seul un patient peut marquer ses commentaires comme lus
    if current_user.role != "patient":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Seuls les patients peuvent marquer les commentaires comme lus"
        )
    
    # Récupérer le commentaire
    try:
        comment_uuid = UUID(comment_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="ID commentaire invalide"
        )
    
    comment = db.query(Comment).filter(
        Comment.id == comment_uuid,
        Comment.patient_id == current_user.id
    ).first()
    
    if not comment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Commentaire non trouvé"
        )
    
    # Marquer comme lu
    comment.is_read = True
    db.commit()
    db.refresh(comment)
    
    return {
        "success": True,
        "comment": {
            "id": str(comment.id),
            "is_read": comment.is_read
        }
    }

# ============================================================================
# POST /api/v1/comments/assign-patient
# Assigner un patient à un médecin
# ============================================================================

@router.post("/assign-patient", response_model=dict, status_code=status.HTTP_201_CREATED)
def assign_patient_to_medecin(
    assignment_data: PatientAssignment,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Assigner un patient à un médecin.
    
    Accessible par : Admin uniquement
    """
    # Seul un admin peut assigner
    if current_user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Seuls les administrateurs peuvent assigner des patients"
        )
    
    # Vérifier que le patient existe
    try:
        patient_uuid = UUID(assignment_data.patient_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="ID patient invalide"
        )
    
    patient = db.query(User).filter(
        User.id == patient_uuid,
        User.role == "patient"
    ).first()
    
    if not patient:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Patient non trouvé"
        )
    
    # Vérifier que le médecin existe
    try:
        medecin_uuid = UUID(assignment_data.medecin_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="ID médecin invalide"
        )
    
    medecin = db.query(User).filter(
        User.id == medecin_uuid,
        User.role == "medecin"
    ).first()
    
    if not medecin:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Médecin non trouvé"
        )
    
    # Vérifier si l'association existe déjà
    existing = db.query(PatientMedecin).filter(
        PatientMedecin.patient_id == patient_uuid,
        PatientMedecin.medecin_id == medecin_uuid
    ).first()
    
    if existing:
        return {
            "success": True,
            "message": "Association déjà existante"
        }
    
    # Créer l'association
    new_assignment = PatientMedecin(
        patient_id=patient_uuid,
        medecin_id=medecin_uuid
    )
    
    db.add(new_assignment)
    db.commit()
    db.refresh(new_assignment)
    
    return {
        "success": True,
        "assignment": {
            "id": str(new_assignment.id),
            "patient_id": str(new_assignment.patient_id),
            "medecin_id": str(new_assignment.medecin_id),
            "assigned_at": new_assignment.assigned_at.isoformat()
        },
        "message": "Patient assigné au médecin avec succès"
    }
