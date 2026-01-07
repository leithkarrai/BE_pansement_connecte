# ============================================
# Schemas Pydantic - Comments
# ============================================
# Fichier : app/schemas/comment.py

from pydantic import BaseModel, Field, field_validator
from typing import Optional
from datetime import datetime

# ============================================
# SCHÉMAS POUR LES REQUÊTES (INPUT)
# ============================================

class CommentCreate(BaseModel):
    """Schéma pour créer un commentaire"""
    patient_id: str = Field(..., description="UUID du patient")
    comment_text: str = Field(..., min_length=10, max_length=500, description="Texte du commentaire")
    measurement_id: Optional[str] = Field(None, description="UUID de la mesure associée (optionnel)")
    
    @field_validator('comment_text')
    @classmethod
    def comment_text_not_empty(cls, v):
        if not v or len(v.strip()) == 0:
            raise ValueError('Le commentaire ne peut pas être vide')
        return v.strip()
    
    class Config:
        json_schema_extra = {
            "example": {
                "patient_id": "123e4567-e89b-12d3-a456-426614174000",
                "comment_text": "La plaie est en bonne voie de guérison, continuez les soins",
                "measurement_id": None
            }
        }

class CommentUpdate(BaseModel):
    """Schéma pour modifier un commentaire"""
    comment_text: str = Field(..., min_length=10, max_length=500, description="Nouveau texte du commentaire")
    
    @field_validator('comment_text')
    @classmethod
    def comment_text_not_empty(cls, v):
        if not v or len(v.strip()) == 0:
            raise ValueError('Le commentaire ne peut pas être vide')
        return v.strip()
    
    class Config:
        json_schema_extra = {
            "example": {
                "comment_text": "Mise à jour : la plaie guérit bien, pas d'inquiétude"
            }
        }

class PatientAssignment(BaseModel):
    """Schéma pour assigner un patient à un médecin"""
    patient_id: str = Field(..., description="UUID du patient")
    medecin_id: str = Field(..., description="UUID du médecin")
    
    class Config:
        json_schema_extra = {
            "example": {
                "patient_id": "123e4567-e89b-12d3-a456-426614174000",
                "medecin_id": "987e6543-e21b-12d3-a456-426614174000"
            }
        }

# ============================================
# SCHÉMAS POUR LES RÉPONSES (OUTPUT)
# ============================================

class CommentResponse(BaseModel):
    """Schéma de réponse pour un commentaire"""
    id: str
    patient_id: str
    medecin_id: str
    medecin_name: str
    comment_text: str
    is_read: bool
    measurement_id: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    
    model_config = {
        'from_attributes': True,
        'json_schema_extra': {
            "example": {
                "id": "456e7890-e12c-34d5-b678-901234567890",
                "patient_id": "123e4567-e89b-12d3-a456-426614174000",
                "medecin_id": "987e6543-e21b-12d3-a456-426614174000",
                "medecin_name": "Dr. Dupont",
                "comment_text": "La plaie est en bonne voie de guérison",
                "is_read": False,
                "measurement_id": None,
                "created_at": "2026-01-05T10:30:00",
                "updated_at": "2026-01-05T10:30:00"
            }
        }
    }

class CommentListResponse(BaseModel):
    """Schéma de réponse pour une liste de commentaires"""
    success: bool
    comments: list[CommentResponse]
    total: int
    
    class Config:
        json_schema_extra = {
            "example": {
                "success": True,
                "comments": [
                    {
                        "id": "456e7890-e12c-34d5-b678-901234567890",
                        "patient_id": "123e4567-e89b-12d3-a456-426614174000",
                        "medecin_id": "987e6543-e21b-12d3-a456-426614174000",
                        "medecin_name": "Dr. Dupont",
                        "comment_text": "Tout va bien",
                        "is_read": False,
                        "measurement_id": None,
                        "created_at": "2026-01-05T10:30:00",
                        "updated_at": "2026-01-05T10:30:00"
                    }
                ],
                "total": 1
            }
        }

class UnreadCountResponse(BaseModel):
    """Schéma de réponse pour le nombre de non-lus"""
    success: bool
    unread_count: int
    
    class Config:
        json_schema_extra = {
            "example": {
                "success": True,
                "unread_count": 3
            }
        }

# ============================================================================
# Alias pour compatibilité avec l'ancien code
# ============================================================================
CommentList = CommentListResponse  # Alias pour compatibilité
