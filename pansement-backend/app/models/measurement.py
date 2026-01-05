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
    measurement_type = Column(String(50), nullable=False)
    value = Column(Float, nullable=False)
    unit = Column(String(20), nullable=False)
    quality_score = Column(Integer)
    timestamp = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    
    # Pas de patient_device_id !
