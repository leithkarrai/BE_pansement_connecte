from sqlalchemy import Column, Integer, Boolean, DateTime, Numeric, String, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID
from datetime import datetime
import uuid

from app.database import Base

class PatientDevice(Base):
    __tablename__ = 'patient_devices'
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    
    # Relations (clés étrangères)
    patient_id = Column(UUID(as_uuid=True), ForeignKey('users.id'), nullable=False, index=True)
    device_id = Column(UUID(as_uuid=True), ForeignKey('devices.id'), nullable=False, index=True)
    
    # Informations sur la plaie
    wound_type = Column(String(50))  # Enum: 'acute', 'chronic', 'surgical', 'burn', 'ulcer'
    wound_location = Column(String(100))  # Ex: "Jambe droite, mollet"
    wound_size_cm2 = Column(Numeric(6, 2))
    wound_depth_mm = Column(Numeric(4, 1))
    
    # Dates
    application_date = Column(DateTime, nullable=False, default=datetime.utcnow)
    expected_removal_date = Column(DateTime)
    actual_removal_date = Column(DateTime)
    
    # Configuration des seuils d'alerte (personnalisables par patient)
    temp_threshold_high = Column(Numeric(4, 2), default=37.5)
    temp_threshold_low = Column(Numeric(4, 2), default=32.0)
    impedance_variation_threshold = Column(Integer, default=20)  # en %
    orp_threshold_low = Column(Integer, default=150)  # en mV
    
    # Baseline impédance (calculée sur 24h après pose)
    baseline_impedance = Column(Integer)
    
    # Notes médicales liées à l'application
    prescription = Column(Text)
    notes = Column(Text)
    
    # État
    is_active = Column(Boolean, default=True, index=True)
    
    # Métadonnées
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    def __repr__(self):
        return f'<PatientDevice {self.id} - Patient: {self.patient_id}, Device: {self.device_id}>'

