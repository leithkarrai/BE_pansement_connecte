# ============================================
# Models SQLAlchemy - Comments
# ============================================
# Fichier : app/models/comment.py

from sqlalchemy import Column, Text, Boolean, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import uuid

from app.database import Base

# ============================================
# MODÈLE : Comment
# ============================================

class Comment(Base):
    """
    Modèle pour les commentaires des médecins sur les patients
    """
    __tablename__ = "comments"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    
    # Relations
    patient_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    medecin_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    measurement_id = Column(UUID(as_uuid=True), ForeignKey("measurements.id", ondelete="SET NULL"), nullable=True)
    
    # Contenu
    comment_text = Column(Text, nullable=False)
    
    # Statut
    is_read = Column(Boolean, default=False, nullable=False, index=True)
    
    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False, index=True)
    updated_at = Column(DateTime(timezone=True), onupdate=func.now(), nullable=True)
    
    # Relations SQLAlchemy
    patient = relationship("User", foreign_keys=[patient_id], backref="comments_received")
    medecin = relationship("User", foreign_keys=[medecin_id], backref="comments_written")
    measurement = relationship("Measurement", backref="comments")
    
    def __repr__(self):
        return f"<Comment(id={self.id}, patient_id={self.patient_id}, medecin_id={self.medecin_id})>"
