"""
Modèle SQLAlchemy pour la table alerts
"""
from sqlalchemy import Column, String, Boolean, DateTime, Numeric, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID
from datetime import datetime
import uuid

from app.database import Base


class Alert(Base):
    __tablename__ = 'alerts'
    
    # ID
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    
    # Relations
    patient_device_id = Column(UUID(as_uuid=True), ForeignKey('patient_devices.id', ondelete='CASCADE'), nullable=False)
    patient_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    device_id = Column(UUID(as_uuid=True), ForeignKey('devices.id', ondelete='CASCADE'), nullable=False)
    measurement_id = Column(UUID(as_uuid=True), ForeignKey('measurements.id', ondelete='SET NULL'), nullable=True)
    
    # Type et sévérité
    alert_type = Column(String(50), nullable=False)  # temperature, impedance, orp, infection, battery, device_error
    severity = Column(String(50), nullable=False)  # info, warning, critical
    
    # Détails
    title = Column(String(200), nullable=False)
    message = Column(Text, nullable=False)
    
    # Valeurs déclenchantes
    current_value = Column(Numeric(10, 2), nullable=True)
    threshold_value = Column(Numeric(10, 2), nullable=True)
    
    # État de l'alerte
    triggered_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    acknowledged_at = Column(DateTime, nullable=True)
    acknowledged_by = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True)
    resolved_at = Column(DateTime, nullable=True)
    resolved_by = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True)
    resolution_note = Column(Text, nullable=True)
    
    # Notification
    notification_sent = Column(Boolean, default=False)
    notification_method = Column(String(50), nullable=True)  # push, sms, email
    notification_sent_at = Column(DateTime, nullable=True)
    
    def __repr__(self):
        return f'<Alert {self.id} - {self.alert_type} ({self.severity})>'

