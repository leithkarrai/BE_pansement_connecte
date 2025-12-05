from pydantic import BaseModel, EmailStr, Field
from typing import Optional
from datetime import datetime, date
from enum import Enum


class UserRole(str, Enum):
    PATIENT = 'patient'
    MEDECIN = 'medecin'
    ADMIN = 'admin'


# Schéma de base (commun)
class UserBase(BaseModel):
    email: EmailStr
    role: UserRole
    first_name: str = Field(..., min_length=1, max_length=100)
    last_name: str = Field(..., min_length=1, max_length=100)
    phone: Optional[str] = Field(None, max_length=20)
    date_of_birth: Optional[date] = None
    gender: Optional[str] = Field(None, max_length=10)


# Création d'utilisateur (avec mot de passe)
class UserCreate(UserBase):
    password: str = Field(..., min_length=8, max_length=100)
    
    # Champs spécifiques patients
    medical_record_number: Optional[str] = None
    blood_type: Optional[str] = None
    allergies: Optional[str] = None


# Mise à jour d'utilisateur (tout optionnel)
class UserUpdate(BaseModel):
    email: Optional[EmailStr] = None
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    phone: Optional[str] = None
    date_of_birth: Optional[date] = None
    gender: Optional[str] = None
    password: Optional[str] = Field(None, min_length=8)
    
    # Métadonnées patients
    blood_type: Optional[str] = None
    allergies: Optional[str] = None
    
    # Status
    is_active: Optional[bool] = None


# Réponse (ce qu'on retourne, sans mot de passe)
class UserResponse(UserBase):
    id: str
    created_at: datetime
    updated_at: datetime
    last_login: Optional[datetime] = None
    is_active: bool
    
    # Métadonnées patients
    medical_record_number: Optional[str] = None
    blood_type: Optional[str] = None
    
    class Config:
        from_attributes = True  # Permet conversion depuis ORM


# Liste d'utilisateurs (pagination)
class UserList(BaseModel):
    users: list[UserResponse]
    total: int
    page: int
    per_page: int
