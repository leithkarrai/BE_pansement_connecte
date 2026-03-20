from sqlalchemy import Column, String, Float, DateTime, ForeignKey, Integer
from sqlalchemy.sql import func
from sqlalchemy.dialects.postgresql import UUID
import uuid

from app.database import Base

class Measurement(Base):
    __tablename__ = 'measurements'
    
    # Colonnes principales
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    device_id = Column(UUID(as_uuid=True), ForeignKey('devices.id'), nullable=False)
    # Lien direct vers la liaison patient <-> pansement au moment de la mesure.
    # Indispensable pour que les écrans admin/médecin retrouvent les mesures par patient.
    patient_device_id = Column(
        UUID(as_uuid=True),
        ForeignKey('patient_devices.id', ondelete='CASCADE'),
        nullable=True,
        index=True,
    )
    measurement_type = Column(String(50), nullable=False)
    value = Column(Float, nullable=False)
    unit = Column(String(20), nullable=False)
    quality_score = Column(Integer)
    timestamp = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    # Balayage Bode (impédance) : fréquence en Hz et phase en degrés
    freq_hz = Column(Float, nullable=True)
    phase_deg = Column(Float, nullable=True)
