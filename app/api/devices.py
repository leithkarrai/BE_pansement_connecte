# ============================================================================
# IMPORTS
# ============================================================================
# FastAPI : Framework web pour créer l'API
from fastapi import APIRouter, Depends, HTTPException, status
# SQLAlchemy : ORM pour interagir avec PostgreSQL
from sqlalchemy.orm import Session
from sqlalchemy import text  # Pour exécuter des requêtes SQL brutes
# Utilitaires Python
from typing import List  # Pour typer les listes
from uuid import UUID  # Pour les identifiants UUID

# Nos modules locaux
from app.database import get_db  # Fonction pour obtenir une connexion DB
from app.schemas.device import DeviceCreate, DeviceResponse  # Schémas de validation
from app.models.device import DeviceStatus  # Enum pour le statut du device

# ============================================================================
# CONFIGURATION DU ROUTER
# ============================================================================
# Créer un router FastAPI pour grouper toutes les routes des devices (pansements)
# prefix : Toutes les routes commenceront par /api/v1/devices
# tags : Permet de regrouper les routes dans la documentation Swagger
router = APIRouter(prefix="/api/v1/devices", tags=["Devices"])
# ============================================================================
# ROUTES CRUD DEVICES
# ============================================================================

@router.get("", response_model=List[DeviceResponse])
def get_devices(
    skip: int = 0,
    limit: int = 100,
    status: DeviceStatus = None,
    db: Session = Depends(get_db)
):
    """
    Lister tous les pansements (devices)
    - **skip**: Nombre d'éléments à sauter (pagination)
    - **limit**: Nombre maximum d'éléments à retourner
    - **status**: Filtrer par statut (optionnel)
    """
    query = "SELECT * FROM devices WHERE 1=1"
    params = {}
    
    if status:
        query += " AND status = :status"
        params["status"] = status.value
    
    query += " ORDER BY created_at DESC LIMIT :limit OFFSET :skip"
    params["limit"] = limit
    params["skip"] = skip
    
    result = db.execute(text(query), params)
    rows = result.fetchall()
    
    devices = []
    for row in rows:
        device_dict = dict(row._mapping)
        device_dict["status"] = DeviceStatus(device_dict["status"])
        devices.append(device_dict)
    
    return devices

@router.post("", response_model=DeviceResponse, status_code=status.HTTP_201_CREATED)
def create_device(device: DeviceCreate, db: Session = Depends(get_db)):
    """
    ROUTE : Enregistrer un nouveau pansement (device)
    
    Cette route permet d'enregistrer un nouveau pansement connecté dans le système.
    
    Le body de la requête doit contenir :
    - device_id : Identifiant unique du device (ex: "PANS-00001234")
    - mac_address : Adresse MAC du device (format: "AA:BB:CC:DD:EE:FF")
    - firmware_version : Version du firmware (ex: "v1.0.2")
    - hardware_version : Version du hardware (ex: "hw-v1.0")
    - manufacture_date : Date de fabrication (optionnel)
    - batch_number : Numéro de lot (optionnel)
    - status : Statut du device (active, inactive, maintenance, retired)
    
    ⚠️ IMPORTANT : 
    - device_id doit être unique
    - mac_address doit être unique
    - Le format de mac_address est validé automatiquement
    
    URL : POST /api/v1/devices
    """
    # ÉTAPE 1 : Vérifier que device_id n'existe pas déjà
    # Chaque pansement doit avoir un identifiant unique
    result = db.execute(
        text("SELECT id FROM devices WHERE device_id = :device_id"),
        {"device_id": device.device_id}
    )
    if result.fetchone():  # Si on trouve un résultat, le device_id existe déjà
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Le device {device.device_id} existe déjà"
        )
    
    # ÉTAPE 2 : Vérifier que mac_address n'existe pas déjà
    # Chaque pansement doit avoir une adresse MAC unique
    result = db.execute(
        text("SELECT id FROM devices WHERE mac_address = :mac_address"),
        {"mac_address": device.mac_address}
    )
    if result.fetchone():  # Si on trouve un résultat, la MAC existe déjà
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"L'adresse MAC {device.mac_address} est déjà utilisée"
        )
    
    # ÉTAPE 3 : Insérer le nouveau device dans la table devices
    # RETURNING * permet de récupérer toutes les colonnes du device créé
    insert_query = """
        INSERT INTO devices (
            device_id, mac_address, firmware_version, hardware_version,
            manufacture_date, batch_number, status
        )
        VALUES (
            :device_id, :mac_address, :firmware_version, :hardware_version,
            :manufacture_date, :batch_number, :status
        )
        RETURNING *
    """
    
    # Exécuter la requête avec les paramètres (protection contre les injections SQL)
    result = db.execute(text(insert_query), {
        "device_id": device.device_id,
        "mac_address": device.mac_address,
        "firmware_version": device.firmware_version,
        "hardware_version": device.hardware_version,
        "manufacture_date": device.manufacture_date,
        "batch_number": device.batch_number,
        "status": device.status.value  # Convertir l'enum en string
    })
    
    # Sauvegarder les changements dans la base de données
    db.commit()
    
    # Récupérer le résultat de l'insertion
    row = result.fetchone()
    device_dict = dict(row._mapping)
    device_dict["status"] = DeviceStatus(device_dict["status"])  # Convertir le statut en enum
    
    return device_dict

@router.get("/{device_id}", response_model=DeviceResponse)
def get_device(device_id: UUID, db: Session = Depends(get_db)):
    """
    Détails d'un pansement par son ID
    """
    result = db.execute(
        text("SELECT * FROM devices WHERE id = :device_id"),
        {"device_id": str(device_id)}
    )
    row = result.fetchone()
    
    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Device {device_id} non trouvé"
        )
    
    device_dict = dict(row._mapping)
    device_dict["status"] = DeviceStatus(device_dict["status"])
    return device_dict


