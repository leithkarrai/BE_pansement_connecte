"""
Routes API pour le stockage de fichiers (MinIO)
"""
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from typing import Optional
from uuid import uuid4
import io

from app.database import get_db
from app.api.deps import get_current_user, require_role
from app.models.user import User
from app.core.minio_client import (
    upload_file,
    download_file,
    delete_file,
    get_file_url,
    file_exists,
    BUCKET_PHOTOS,
    BUCKET_DOCUMENTS,
    BUCKET_AVATARS
)

router = APIRouter(prefix="/api/v1/files", tags=["Files"])


# ============================================================================
# POST /api/v1/files/upload/photo - Uploader une photo de plaie
# ============================================================================

@router.post("/upload/photo")
def upload_photo(
    file: UploadFile = File(...),
    patient_id: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Uploader une photo de plaie.
    
    Permissions:
    - Admin: Peut uploader pour n'importe quel patient
    - Médecin: Peut uploader pour ses patients
    - Patient: Peut uploader uniquement pour lui-même

    Convention de stockage:
    - object_name est préfixé par `{patient_id}/...` pour simplifier les contrôles d'accès
      sur download/delete.
    """
    # Vérifier les permissions
    if patient_id:
        try:
            from uuid import UUID
            patient_uuid = UUID(patient_id)
            
            if current_user.role == 'patient' and str(current_user.id) != patient_id:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail='Vous ne pouvez uploader que vos propres photos'
                )
            
            if current_user.role == 'medecin':
                # Vérifier que c'est un de ses patients
                from sqlalchemy import text
                result = db.execute(
                    text("SELECT id FROM medecin_patients WHERE medecin_id = :medecin_id AND patient_id = :patient_id"),
                    {"medecin_id": str(current_user.id), "patient_id": patient_id}
                )
                if not result.fetchone():
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail='Ce patient n\'est pas sous votre responsabilité'
                    )
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail='ID patient invalide'
            )
    else:
        # Si pas de patient_id, utiliser l'utilisateur connecté
        patient_id = str(current_user.id)
    
    # Vérifier le type de fichier (MVP: contrôle MIME uniquement).
    # En production, ajouter une validation plus stricte du contenu binaire.
    if not file.content_type or not file.content_type.startswith('image/'):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Le fichier doit être une image'
        )
    
    # Lire le fichier
    file_data = file.file.read()
    
    # Générer un nom unique pour le fichier
    file_extension = file.filename.split('.')[-1] if '.' in file.filename else 'jpg'
    object_name = f"{patient_id}/{uuid4()}.{file_extension}"
    
    # Uploader dans MinIO
    file_path = upload_file(
        bucket_name=BUCKET_PHOTOS,
        object_name=object_name,
        file_data=file_data,
        content_type=file.content_type,
        metadata={
            'patient_id': patient_id,
            'uploaded_by': str(current_user.id),
            'original_filename': file.filename
        }
    )
    
    if not file_path:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail='Erreur lors de l\'upload du fichier'
        )
    
    return {
        'success': True,
        'file_path': file_path,
        'object_name': object_name,
        'bucket': BUCKET_PHOTOS,
        'size': len(file_data),
        'content_type': file.content_type
    }


# ============================================================================
# POST /api/v1/files/upload/avatar - Uploader une photo de profil
# ============================================================================

@router.post("/upload/avatar")
def upload_avatar(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Uploader une photo de profil.
    
    Permissions: Tous les utilisateurs peuvent uploader leur propre avatar.

    Notes:
    - La taille est limitée à 5MB pour éviter les uploads excessifs.
    - L'URL MinIO est persistée dans `users.profile_photo_url`.
    """
    # Vérifier le type de fichier
    if not file.content_type or not file.content_type.startswith('image/'):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Le fichier doit être une image'
        )
    
    # Lire le fichier
    file_data = file.file.read()
    
    # Limiter la taille (max 5MB)
    if len(file_data) > 5 * 1024 * 1024:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Le fichier est trop volumineux (max 5MB)'
        )
    
    # Générer un nom unique pour le fichier
    file_extension = file.filename.split('.')[-1] if '.' in file.filename else 'jpg'
    object_name = f"{current_user.id}/{uuid4()}.{file_extension}"
    
    # Uploader dans MinIO
    file_path = upload_file(
        bucket_name=BUCKET_AVATARS,
        object_name=object_name,
        file_data=file_data,
        content_type=file.content_type,
        metadata={
            'user_id': str(current_user.id),
            'original_filename': file.filename
        }
    )
    
    if not file_path:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail='Erreur lors de l\'upload du fichier'
        )
    
    # Mettre à jour l'URL dans la base de données
    from app.models.user import User
    user = db.query(User).filter(User.id == current_user.id).first()
    if user:
        user.profile_photo_url = file_path
        db.commit()
    
    return {
        'success': True,
        'file_path': file_path,
        'object_name': object_name,
        'bucket': BUCKET_AVATARS,
        'size': len(file_data),
        'content_type': file.content_type
    }


# ============================================================================
# GET /api/v1/files/download/{bucket}/{object_name} - Télécharger un fichier
# ============================================================================

@router.get("/download/{bucket}/{object_name:path}")
def download_file_route(
    bucket: str,
    object_name: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Télécharger un fichier depuis MinIO.
    
    Permissions:
    - Admin: Peut télécharger n'importe quel fichier
    - Médecin: Peut télécharger les fichiers de ses patients
    - Patient: Peut télécharger uniquement ses propres fichiers

    Règle d'autorisation:
    - le propriétaire est déduit du préfixe `object_name` (`{owner_id}/filename`).
    - pour un médecin, l'accès est conditionné par la relation `medecin_patients`.
    """
    # Vérifier que le bucket est autorisé
    allowed_buckets = [BUCKET_PHOTOS, BUCKET_DOCUMENTS, BUCKET_AVATARS]
    if bucket not in allowed_buckets:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Bucket non autorisé'
        )
    
    # Vérifier que le fichier existe
    if not file_exists(bucket, object_name):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Fichier non trouvé'
        )
    
    # Vérifier les permissions (basé sur le chemin du fichier)
    # Le format est: {user_id}/{filename}
    if '/' in object_name:
        file_owner_id = object_name.split('/')[0]
        
        if current_user.role == 'patient' and str(current_user.id) != file_owner_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Accès refusé. Vous ne pouvez télécharger que vos propres fichiers.'
            )
        
        if current_user.role == 'medecin' and str(current_user.id) != file_owner_id:
            # Vérifier que c'est un de ses patients
            from sqlalchemy import text
            from uuid import UUID
            try:
                patient_uuid = UUID(file_owner_id)
                result = db.execute(
                    text("SELECT id FROM medecin_patients WHERE medecin_id = :medecin_id AND patient_id = :patient_id"),
                    {"medecin_id": str(current_user.id), "patient_id": file_owner_id}
                )
                if not result.fetchone():
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail='Accès refusé. Ce fichier n\'appartient pas à un de vos patients.'
                    )
            except ValueError:
                pass
    
    # Télécharger le fichier
    file_data = download_file(bucket, object_name)
    if not file_data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail='Erreur lors du téléchargement du fichier'
        )
    
    # Déterminer le content-type
    content_type = "application/octet-stream"
    if object_name.endswith('.jpg') or object_name.endswith('.jpeg'):
        content_type = "image/jpeg"
    elif object_name.endswith('.png'):
        content_type = "image/png"
    elif object_name.endswith('.pdf'):
        content_type = "application/pdf"
    
    # Retourner le fichier
    return StreamingResponse(
        io.BytesIO(file_data),
        media_type=content_type,
        headers={
            "Content-Disposition": f'attachment; filename="{object_name.split("/")[-1]}"'
        }
    )


# ============================================================================
# DELETE /api/v1/files/{bucket}/{object_name} - Supprimer un fichier
# ============================================================================

@router.delete("/{bucket}/{object_name:path}")
def delete_file_route(
    bucket: str,
    object_name: str,
    current_user: User = Depends(require_role(['admin'])),
    db: Session = Depends(get_db)
):
    """
    Supprimer un fichier depuis MinIO.
    
    Permissions: Admin uniquement.

    Note:
    - suppression physique dans MinIO (contrairement à d'autres ressources backend en soft-delete).
    """
    # Vérifier que le bucket est autorisé
    allowed_buckets = [BUCKET_PHOTOS, BUCKET_DOCUMENTS, BUCKET_AVATARS]
    if bucket not in allowed_buckets:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Bucket non autorisé'
        )
    
    # Supprimer le fichier
    success = delete_file(bucket, object_name)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail='Erreur lors de la suppression du fichier'
        )
    
    return {
        'success': True,
        'message': 'Fichier supprimé avec succès'
    }

