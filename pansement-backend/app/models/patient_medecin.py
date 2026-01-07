# ============================================
# Models SQLAlchemy - PatientMedecin (Association)
# ============================================
# Fichier : app/models/patient_medecin.py

from sqlalchemy import Column, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import uuid

from app.database import Base

# ============================================
# MODÈLE : PatientMedecin (Association)
# ============================================

class PatientMedecin(Base):
    """
    Modèle pour l'association entre patients et médecins
    Note: Le nom de la table est 'medecin_patients' pour rester cohérent avec le code existant
    """
    __tablename__ = "medecin_patients"
    __table_args__ = (
        UniqueConstraint('patient_id', 'medecin_id', name='uq_patient_medecin'),
    )
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    
    # Relations
    patient_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    medecin_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # Timestamp
    # Note: La colonne dans la base de données s'appelle 'assigned_date' mais on utilise 'assigned_at' dans le code
    assigned_at = Column('assigned_date', DateTime(timezone=True), server_default=func.now(), nullable=False)
    
    # Relations SQLAlchemy
    patient = relationship("User", foreign_keys=[patient_id], backref="assigned_medecins")
    medecin = relationship("User", foreign_keys=[medecin_id], backref="assigned_patients")
    
    def __repr__(self):
        return f"<PatientMedecin(patient_id={self.patient_id}, medecin_id={self.medecin_id})>"
