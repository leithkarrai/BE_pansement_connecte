from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from enum import Enum

# ============================================================================
# Enums - ALIGNÉS AVEC POSTGRESQL
# ============================================================================

class DeviceStatus(str, Enum):
    '''Statut du pansement (valeurs PostgreSQL)'''
    ACTIVE = 'active'           # Pansement actif / en utilisation
    INACTIVE = 'inactive'       # Pansement inactif / disponible
    MAINTENANCE = 'maintenance' # En maintenance

# ============================================================================
# Schémas de base
# ============================================================================

class DeviceBase(BaseModel):
    '''Champs communs pour Device'''
    serial_number: str = Field(..., description='Numéro de série unique du pansement')
    model: str = Field(..., description='Modèle du pansement (ex: PansConnect-V2)')
    firmware_version: Optional[str] = Field(None, description='Version du firmware')
    hardware_version: Optional[str] = Field(None, description='Version du hardware')
    battery_level: Optional[int] = Field(None, ge=0, le=100, description='Niveau de batterie (0-100%)')
    last_calibration_date: Optional[datetime] = Field(None, description='Date dernière calibration')

class DeviceCreate(BaseModel):
    '''Schéma pour créer un device - champs obligatoires uniquement'''
    serial_number: str = Field(..., description='Numéro de série unique')
    model: str = Field(..., description='Modèle du pansement')
    firmware_version: Optional[str] = None
    hardware_version: Optional[str] = None
    battery_level: Optional[int] = Field(None, ge=0, le=100)
    last_calibration_date: Optional[datetime] = None
    status: DeviceStatus = DeviceStatus.INACTIVE

class DeviceUpdate(BaseModel):
    '''Schéma pour mettre à jour un device (tous champs optionnels)'''
    serial_number: Optional[str] = None
    model: Optional[str] = None
    firmware_version: Optional[str] = None
    hardware_version: Optional[str] = None
    battery_level: Optional[int] = Field(None, ge=0, le=100)
    status: Optional[DeviceStatus] = None
    last_calibration_date: Optional[datetime] = None

class DeviceAssign(BaseModel):
    '''Schéma pour assigner un device à un patient'''
    patient_id: str = Field(..., description='UUID du patient')

class DeviceResponse(DeviceBase):
    '''Schéma de réponse avec toutes les infos'''
    id: str
    status: DeviceStatus
    patient_id: Optional[str] = None
    assigned_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime
    last_connection: Optional[datetime] = None
    
    # Info patient si assigné
    patient_name: Optional[str] = None
    
    model_config = {'from_attributes': True}

class DeviceList(BaseModel):
    '''Schéma pour liste paginée de devices'''
    devices: list[DeviceResponse]
    total: int
    page: int
    per_page: int
