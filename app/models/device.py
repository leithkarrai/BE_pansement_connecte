from sqlalchemy import Column, String, Integer, DateTime, Date, Enum as SQLEnum, JSON
from sqlalchemy.dialects.postgresql import UUID
from datetime import datetime
import uuid
import enum

from app.database import Base

class DeviceStatus(str, enum.Enum):
    ACTIVE = 'active'
    INACTIVE = 'inactive'
    MAINTENANCE = 'maintenance'
    RETIRED = 'retired'

class Device(Base):
    __tablename__ = 'devices'
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    
    # Identification unique
    device_id = Column(String(50), unique=True, nullable=False, index=True)
    mac_address = Column(String(17), unique=True, nullable=False)
    
    # Versions
    firmware_version = Column(String(20))
    hardware_version = Column(String(20))
    
    # Fabrication
    manufacture_date = Column(Date)
    batch_number = Column(String(50))
    
    # État
    # Utiliser String au lieu de SQLEnum pour éviter les problèmes de casse avec PostgreSQL
    status = Column(String(50), default='inactive')
    battery_level = Column(Integer)
    last_seen = Column(DateTime)
    
    # Calibration
    calibration_date = Column(DateTime)
    calibration_data = Column(JSON)
    
    # Métadonnées
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    notes = Column(String)
    
    def __repr__(self):
        return f'<Device {self.device_id} ({self.status})>'
