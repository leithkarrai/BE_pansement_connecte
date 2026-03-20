"""
Schémas Pydantic pour les alertes
"""
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from enum import Enum


class AlertType(str, Enum):
    """Types d'alertes possibles"""
    TEMPERATURE = 'temperature'
    IMPEDANCE = 'impedance'
    ORP = 'orp'
    INFECTION = 'infection'
    BATTERY = 'battery'
    DEVICE_ERROR = 'device_error'
    NEW_MEASUREMENTS = 'new_measurements'


class AlertSeverity(str, Enum):
    """Niveaux de sévérité des alertes"""
    INFO = 'info'
    WARNING = 'warning'
    CRITICAL = 'critical'


# Schéma de base (commun) - alert_type/severity en str pour accepter toute valeur en BDD (ex: new_patient_data)
class AlertBase(BaseModel):
    alert_type: str = Field(..., min_length=1, max_length=50)
    severity: str = Field(..., min_length=1, max_length=50)
    title: str = Field(..., min_length=1, max_length=200)
    message: str = Field(..., min_length=1)
    current_value: Optional[float] = None
    threshold_value: Optional[float] = None


# Réponse (ce qu'on retourne) - dates acceptent str ISO ou datetime
class AlertResponse(AlertBase):
    id: str
    patient_device_id: str
    patient_id: str
    device_id: str
    measurement_id: Optional[str] = None
    triggered_at: Optional[datetime] = None  # peut être str ISO depuis la route
    acknowledged_at: Optional[datetime] = None
    acknowledged_by: Optional[str] = None
    acknowledged_by_medecin_at: Optional[datetime] = None
    acknowledged_by_admin_at: Optional[datetime] = None
    resolved_at: Optional[datetime] = None
    resolved_by: Optional[str] = None
    resolution_note: Optional[str] = None
    notification_sent: bool = False
    notification_method: Optional[str] = None
    notification_sent_at: Optional[datetime] = None
    
    class Config:
        from_attributes = True


# Liste d'alertes
class AlertList(BaseModel):
    alerts: list[AlertResponse]
    total: int
    unacknowledged: int
    critical: int


# Acquitter une alerte
class AlertAcknowledgeRequest(BaseModel):
    note: Optional[str] = Field(None, max_length=500, description='Note optionnelle lors de l\'acquittement')


# Résoudre une alerte
class AlertResolveRequest(BaseModel):
    resolution_note: Optional[str] = Field(None, max_length=500, description='Note de résolution')

