from sqlalchemy import Column, String, Boolean, DateTime, Date, Enum as SQLEnum
from sqlalchemy.dialects.postgresql import UUID
from datetime import datetime
import uuid
import enum

from app.database import Base

class UserRole(str, enum.Enum):
    PATIENT = 'patient'
    MEDECIN = 'medecin'
    ADMIN = 'admin'

class User(Base):
    __tablename__ = 'users'
    
    # ID
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    
    # Auth
    email = Column(String(255), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)
    role = Column(String(50), nullable=False)  # ← CHANGÉ: String au lieu de Enum
    
    # Info perso
    first_name = Column(String(100), nullable=False)
    last_name = Column(String(100), nullable=False)
    phone = Column(String(20))
    date_of_birth = Column(Date)
    gender = Column(String(10))
    
    # Métadonnées
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    last_login = Column(DateTime)
    is_active = Column(Boolean, default=True)
    
    # Médical (patients)
    medical_record_number = Column(String(50), unique=True)
    blood_type = Column(String(5))
    allergies = Column(String)
    
    # FCM token
    fcm_token = Column(String(500))
    
    def __repr__(self):
        return f'<User {self.email} ({self.role})>'
