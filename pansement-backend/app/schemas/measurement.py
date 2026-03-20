from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from enum import Enum

# ============================================================================
# Enums
# ============================================================================

class MeasurementType(str, Enum):
    '''Type de mesure'''
    TEMPERATURE = 'temperature'
    HUMIDITY = 'humidity'
    PH = 'ph'
    EXUDATE = 'exudate'
    IMPEDANCE = 'impedance'  # Balayage Bode (impédance vs fréquence)

# ============================================================================
# Schémas de base
# ============================================================================

class MeasurementBase(BaseModel):
    '''Champs communs pour Measurement'''
    device_id: str = Field(..., description='UUID du pansement')
    measurement_type: MeasurementType = Field(..., description='Type de mesure')
    value: float = Field(..., description='Valeur mesurée')
    unit: str = Field(..., description='Unité de mesure (°C, %, etc.)')
    quality_score: Optional[float] = Field(None, ge=0, le=100, description='Score qualité (0-100)')

class MeasurementCreate(MeasurementBase):
    '''Schéma pour créer une mesure (depuis pansement BLE)'''
    pass


class MeasurementCreateOpen(BaseModel):
    '''Création mesure avec type libre (adc, s1, s2, impedance, etc.) pour éviter 422'''
    device_id: str = Field(..., description='UUID du pansement')
    measurement_type: str = Field(..., min_length=1, max_length=50, description='Type de mesure')
    value: float = Field(..., description='Valeur mesurée')
    unit: Optional[str] = Field(default='', max_length=20, description='Unité de mesure')
    quality_score: Optional[float] = Field(None, ge=0, le=100)
    patient_id: Optional[str] = Field(None, description='UUID du patient (optionnel)')
    freq_hz: Optional[float] = Field(None, description='Fréquence en Hz (balayage Bode)')
    phase_deg: Optional[float] = Field(None, description='Phase en degrés (balayage Bode)')


class MeasurementResponse(BaseModel):
    '''Schéma de réponse avec toutes les infos'''
    id: str
    device_id: str
    measurement_type: Optional[str] = Field(None, description='Type de mesure')
    value: float
    unit: str
    quality_score: Optional[float] = None
    timestamp: datetime
    device_serial: Optional[str] = None
    patient_id: Optional[str] = None
    patient_name: Optional[str] = None
    freq_hz: Optional[float] = None
    phase_deg: Optional[float] = None

    model_config = {'from_attributes': True}

class MeasurementList(BaseModel):
    '''Schéma pour liste paginée de mesures'''
    measurements: list[MeasurementResponse]
    total: int
    page: int
    per_page: int

class MeasurementStats(BaseModel):
    '''Schéma pour statistiques'''
    measurement_type: str
    count: int
    avg: Optional[float] = None
    min: Optional[float] = None
    max: Optional[float] = None
    latest_value: Optional[float] = None
    latest_timestamp: Optional[datetime] = None
    trend: Optional[str] = None  # 'increasing', 'decreasing', 'stable'

class PatientMeasurementStats(BaseModel):
    '''Schéma pour statistiques complètes d'un patient'''
    patient_id: str
    patient_name: str
    device_serial: Optional[str] = None
    total_measurements: int
    date_range: dict  # {'start': datetime, 'end': datetime}
    stats_by_type: list[MeasurementStats]
