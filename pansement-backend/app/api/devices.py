# ============================================================================
# IMPORTS
# ============================================================================
# FastAPI : Framework web pour créer l'API
from fastapi import APIRouter, Depends, HTTPException, status
# SQLAlchemy : ORM pour interagir avec PostgreSQL
from sqlalchemy.orm import Session
from sqlalchemy import text  # Pour exécuter des requêtes SQL brutes
# Utilitaires Python
from datetime import datetime
from typing import List, Optional  # Pour typer les listes
from uuid import UUID  # Pour les identifiants UUID

# Nos modules locaux
from app.database import get_db  # Fonction pour obtenir une connexion DB
from app.schemas.device import DeviceCreate, DeviceResponse, DeviceUpdate, DeviceAssign, DeviceAssignToMe, RegisterByMacRequest  # Schémas de validation
from app.models.device import DeviceStatus  # Enum pour le statut du device
from app.api.deps import get_current_user, require_role  # Auth
from app.models.user import User  # Pour le typage

# ============================================================================
# CONFIGURATION DU ROUTER
# ============================================================================
# Créer un router FastAPI pour grouper toutes les routes des devices (pansements)
# prefix : Toutes les routes commenceront par /api/v1/devices
# tags : Permet de regrouper les routes dans la documentation Swagger
router = APIRouter(prefix="/api/v1/devices", tags=["Devices"])

# ============================================================================
# ROUTE PATIENT (avant /{device_id} pour éviter que "patient" soit pris pour un device_id)
# POST /api/v1/devices/patient/assign-device
# ============================================================================

@router.post("/patient/assign-device", response_model=DeviceResponse)
def assign_device_to_me(
    body: DeviceAssignToMe,
    current_user: User = Depends(require_role(["patient"])),
    db: Session = Depends(get_db),
):
    """
    Un patient s'assigne un pansement à lui-même (body: {"device_id": "<uuid>"}).
    Nécessaire pour que le backend crée les alertes médecin/admin à la réception des mesures.

    Règles:
    - Une seule liaison active par device (on ferme l'ancienne avant insertion).
    - Après assignation, les alertes patient non acquittées sont marquées comme lues
      côté patient pour repartir d'un état propre.
    """
    try:
        device_uuid = UUID(body.device_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="device_id invalide",
        )
    device_result = db.execute(
        text("SELECT * FROM devices WHERE id = :device_id"),
        {"device_id": str(device_uuid)},
    )
    device_row = device_result.fetchone()
    if not device_row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Pansement non trouvé",
        )
    patient_id = str(current_user.id)
    # Désactiver toute liaison active précédente pour ce device.
    db.execute(
        text("""
            DELETE FROM patient_devices
            WHERE device_id = :device_id AND is_active = true
        """),
        {"device_id": str(device_uuid)},
    )
    # Créer la nouvelle liaison active patient <-> device.
    db.execute(
        text("""
            INSERT INTO patient_devices (patient_id, device_id, application_date, is_active)
            VALUES (:patient_id, :device_id, CURRENT_TIMESTAMP, true)
        """),
        {"patient_id": patient_id, "device_id": str(device_uuid)},
    )
    # Acquitter les alertes du patient pour ce rôle (patient) après assignation
    db.execute(
        text("""
            UPDATE alerts
            SET acknowledged_at = CURRENT_TIMESTAMP, acknowledged_by = :user_id
            WHERE patient_id = :patient_id AND acknowledged_at IS NULL
        """),
        {"patient_id": patient_id, "user_id": str(current_user.id)},
    )
    db.commit()
    device_dict = dict(device_row._mapping)
    patient_result = db.execute(
        text("""
            SELECT pd.patient_id, pd.application_date as assigned_at,
                   u.first_name || ' ' || u.last_name as patient_name
            FROM patient_devices pd
            LEFT JOIN users u ON pd.patient_id = u.id
            WHERE pd.device_id = :device_id AND pd.is_active = true
        """),
        {"device_id": str(device_uuid)},
    ).fetchone()
    patient_info = dict(patient_result._mapping) if patient_result else None
    # Éviter None pour model/status (Pydantic exige une chaîne / enum valide)
    model_val = (device_dict.get("hardware_version") or "") or "PansConnect-V1"
    raw_status = (device_dict.get("status") or "inactive")
    try:
        status_enum = DeviceStatus(str(raw_status).lower())
    except ValueError:
        status_enum = DeviceStatus.INACTIVE
    return {
        "id": str(device_dict["id"]),
        "serial_number": device_dict.get("device_id", ""),
        "model": model_val,
        "firmware_version": device_dict.get("firmware_version"),
        "hardware_version": device_dict.get("hardware_version"),
        "battery_level": device_dict.get("battery_level"),
        "last_calibration_date": device_dict.get("calibration_date"),
        "status": status_enum,
        "patient_id": str(patient_info["patient_id"]) if patient_info and patient_info.get("patient_id") else None,
        "assigned_at": patient_info["assigned_at"] if patient_info and patient_info.get("assigned_at") else None,
        "created_at": device_dict["created_at"],
        "updated_at": device_dict["updated_at"],
        "last_connection": device_dict.get("last_seen"),
        "patient_name": patient_info["patient_name"] if patient_info and patient_info.get("patient_name") else None,
    }


# ============================================================================
# ROUTES CRUD DEVICES
# ============================================================================

@router.get("", response_model=List[DeviceResponse])
def get_devices(
    skip: int = 0,
    limit: int = 100,
    status: Optional[DeviceStatus] = None,
    patient_id: Optional[str] = None,
    db: Session = Depends(get_db)
):
    """
    Lister les pansements (devices).

    Notes:
    - Cette route sert aux écrans de liste (admin/soignant) et aux vues filtrées patient.
    - Le mapping final normalise certains champs DB vers `DeviceResponse`
      (ex: `device_id` -> `serial_number`, fallback du `model`).

    - **skip**: Nombre d'éléments à sauter (pagination)
    - **limit**: Nombre maximum d'éléments à retourner
    - **status**: Filtrer par statut (optionnel)
    - **patient_id**: Filtrer par patient assigné (optionnel)
    """
    # Si patient_id est fourni, joindre avec patient_devices pour filtrer
    if patient_id:
        query = """
            SELECT d.*, pd.patient_id, pd.application_date as assigned_at, u.first_name || ' ' || u.last_name as patient_name
            FROM devices d
            INNER JOIN patient_devices pd ON d.id = pd.device_id
            LEFT JOIN users u ON pd.patient_id = u.id
            WHERE pd.patient_id = :patient_id AND pd.is_active = true
        """
        params = {"patient_id": patient_id}
    else:
        query = "SELECT d.*, NULL as patient_id, NULL as assigned_at, NULL as patient_name FROM devices d WHERE 1=1"
        params = {}
    
    if status:
        query += " AND d.status = :status"
        params["status"] = status.value
    
    query += " ORDER BY d.created_at DESC LIMIT :limit OFFSET :skip"
    params["limit"] = limit
    params["skip"] = skip
    
    result = db.execute(text(query), params)
    rows = result.fetchall()
    devices = []
    for row in rows:
        device_dict = dict(row._mapping)
        device_id_val = device_dict.get("id")
        if device_id_val is None:
            continue
        status_raw = (device_dict.get("status") or "inactive").strip().lower()
        try:
            status_enum = DeviceStatus(status_raw)
        except ValueError:
            status_enum = DeviceStatus.INACTIVE
        created = device_dict.get("created_at") or datetime.utcnow()
        updated = device_dict.get("updated_at") or datetime.utcnow()
        device_response = {
            "id": str(device_id_val),
            "serial_number": device_dict.get("device_id") or "",
            "model": (device_dict.get("hardware_version") or "") or "PansConnect-V1",
            "firmware_version": device_dict.get("firmware_version"),
            "hardware_version": device_dict.get("hardware_version"),
            "battery_level": device_dict.get("battery_level"),
            "last_calibration_date": device_dict.get("calibration_date"),
            "status": status_enum,
            "patient_id": str(device_dict["patient_id"]) if device_dict.get("patient_id") else None,
            "assigned_at": device_dict.get("assigned_at"),
            "created_at": created,
            "updated_at": updated,
            "last_connection": device_dict.get("last_seen"),
            "patient_name": device_dict.get("patient_name"),
        }
        devices.append(device_response)
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
    
    # Mapper les champs de la base de données vers le schéma DeviceResponse
    device_response = {
        "id": str(device_dict["id"]),
        "serial_number": device_dict.get("device_id", ""),
        "model": (device_dict.get("hardware_version") or "") or "PansConnect-V1",
        "firmware_version": device_dict.get("firmware_version"),
        "hardware_version": device_dict.get("hardware_version"),
        "battery_level": device_dict.get("battery_level"),
        "last_calibration_date": device_dict.get("calibration_date"),
        "status": DeviceStatus(device_dict["status"]),
        "patient_id": None,
        "assigned_at": None,
        "created_at": device_dict["created_at"],
        "updated_at": device_dict["updated_at"],
        "last_connection": device_dict.get("last_seen"),
        "patient_name": None,
    }
    
    return device_response


# ============================================================================
# POST /api/v1/devices/register-by-mac - Enregistrer par MAC (app patient)
# ============================================================================

@router.post("/register-by-mac", response_model=DeviceResponse, status_code=status.HTTP_201_CREATED)
def register_device_by_mac(
    body: RegisterByMacRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Enregistrer un pansement par son adresse MAC. Crée le device si la MAC n'existe pas.
    Retourne toujours l'UUID du device (id) pour assign-device et create_measurement.
    """
    mac = (body.mac_address or "").replace(" ", "").replace("-", ":").upper()
    if len(mac) < 12 or ":" not in mac:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Format d'adresse MAC invalide (ex: E8:AD:59:A7:7B:E1)",
        )
    existing = db.execute(
        text("SELECT id, device_id, mac_address, status, firmware_version, hardware_version, last_seen, created_at, updated_at FROM devices WHERE mac_address = :mac"),
        {"mac": mac},
    ).first()
    if existing:
        device_dict = dict(existing._mapping)
        return {
            "id": str(device_dict["id"]),
            "serial_number": device_dict.get("device_id", ""),
            "model": device_dict.get("hardware_version") or "PansConnect-V1",
            "firmware_version": device_dict.get("firmware_version"),
            "hardware_version": device_dict.get("hardware_version"),
            "battery_level": device_dict.get("battery_level"),
            "last_calibration_date": device_dict.get("calibration_date"),
            "status": DeviceStatus(device_dict.get("status") or "inactive"),
            "patient_id": None,
            "assigned_at": None,
            "created_at": device_dict.get("created_at") or datetime.utcnow(),
            "updated_at": device_dict.get("updated_at") or datetime.utcnow(),
            "last_connection": device_dict.get("last_seen"),
            "patient_name": None,
        }
    device_id_val = f"PANS-MAC-{mac.replace(':', '')}"
    result = db.execute(
        text("""
            INSERT INTO devices (device_id, mac_address, status, created_at, updated_at)
            VALUES (:device_id, :mac_address, 'active', :created_at, :updated_at)
            RETURNING id, device_id, mac_address, firmware_version, hardware_version, status, last_seen, created_at, updated_at
        """),
        {"device_id": device_id_val, "mac_address": mac, "created_at": datetime.utcnow(), "updated_at": datetime.utcnow()},
    )
    db.commit()
    row = result.fetchone()
    device_dict = dict(row._mapping)
    return {
        "id": str(device_dict["id"]),
        "serial_number": device_dict.get("device_id", ""),
        "model": "PansConnect-V1",
        "firmware_version": device_dict.get("firmware_version"),
        "hardware_version": device_dict.get("hardware_version"),
        "battery_level": None,
        "last_calibration_date": None,
        "status": DeviceStatus(device_dict.get("status", "active")),
        "patient_id": None,
        "assigned_at": None,
        "created_at": device_dict.get("created_at"),
        "updated_at": device_dict.get("updated_at"),
        "last_connection": device_dict.get("last_seen"),
        "patient_name": None,
    }


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
    
    # Récupérer les infos patient si assigné
    patient_result = db.execute(
        text("""
            SELECT pd.patient_id, pd.application_date as assigned_at,
                   u.first_name || ' ' || u.last_name as patient_name
            FROM patient_devices pd
            LEFT JOIN users u ON pd.patient_id = u.id
            WHERE pd.device_id = :device_id AND pd.is_active = true
        """),
        {"device_id": str(device_id)}
    ).fetchone()
    
    # Convertir le résultat en dictionnaire si présent
    patient_info = dict(patient_result._mapping) if patient_result else None
    
    # Mapper les champs de la base de données vers le schéma DeviceResponse
    device_response = {
        "id": str(device_dict["id"]),
        "serial_number": device_dict.get("device_id", ""),
        "model": (device_dict.get("hardware_version") or "") or "PansConnect-V1",
        "firmware_version": device_dict.get("firmware_version"),
        "hardware_version": device_dict.get("hardware_version"),
        "battery_level": device_dict.get("battery_level"),
        "last_calibration_date": device_dict.get("calibration_date"),
        "status": DeviceStatus(device_dict["status"]),
        "patient_id": str(patient_info["patient_id"]) if patient_info and patient_info.get("patient_id") else None,
        "assigned_at": patient_info["assigned_at"] if patient_info and patient_info.get("assigned_at") else None,
        "created_at": device_dict["created_at"],
        "updated_at": device_dict["updated_at"],
        "last_connection": device_dict.get("last_seen"),
        "patient_name": patient_info["patient_name"] if patient_info and patient_info.get("patient_name") else None,
    }
    
    return device_response

@router.patch("/{device_id}", response_model=DeviceResponse)
def update_device(
    device_id: UUID,
    device_update: DeviceUpdate,
    db: Session = Depends(get_db)
):
    """
    Mettre à jour un pansement (device)
    - Permet de modifier le statut, firmware, etc.
    """
    # Vérifier que le device existe
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
    
    # Construire la requête UPDATE dynamiquement
    update_fields = []
    params = {"device_id": str(device_id)}
    
    update_data = device_update.model_dump(exclude_unset=True)
    
    if "status" in update_data:
        update_fields.append("status = :status")
        params["status"] = update_data["status"].value if hasattr(update_data["status"], "value") else update_data["status"]
    
    if "firmware_version" in update_data and update_data["firmware_version"] is not None:
        update_fields.append("firmware_version = :firmware_version")
        params["firmware_version"] = update_data["firmware_version"]
    
    if "battery_level" in update_data and update_data["battery_level"] is not None:
        update_fields.append("battery_level = :battery_level")
        params["battery_level"] = update_data["battery_level"]
    
    if not update_fields:
        # Aucun champ à mettre à jour, retourner le device tel quel
        device_dict = dict(row._mapping)
        patient_result = db.execute(
            text("""
                SELECT pd.patient_id, pd.application_date as assigned_at,
                       u.first_name || ' ' || u.last_name as patient_name
                FROM patient_devices pd
                LEFT JOIN users u ON pd.patient_id = u.id
                WHERE pd.device_id = :device_id AND pd.is_active = true
            """),
            {"device_id": str(device_id)}
        ).fetchone()
        patient_info = dict(patient_result._mapping) if patient_result else None
        return {
            "id": str(device_dict["id"]),
            "serial_number": device_dict.get("device_id", ""),
            "model": (device_dict.get("hardware_version") or "") or "PansConnect-V1",
            "firmware_version": device_dict.get("firmware_version"),
            "hardware_version": device_dict.get("hardware_version"),
            "battery_level": device_dict.get("battery_level"),
            "last_calibration_date": device_dict.get("calibration_date"),
            "status": DeviceStatus(device_dict["status"]),
            "patient_id": str(patient_info["patient_id"]) if patient_info and patient_info.get("patient_id") else None,
            "assigned_at": patient_info["assigned_at"] if patient_info and patient_info.get("assigned_at") else None,
            "created_at": device_dict["created_at"],
            "updated_at": device_dict["updated_at"],
            "last_connection": device_dict.get("last_seen"),
            "patient_name": patient_info["patient_name"] if patient_info and patient_info.get("patient_name") else None,
        }
    
    update_fields.append("updated_at = CURRENT_TIMESTAMP")
    
    update_query = f"""
        UPDATE devices 
        SET {', '.join(update_fields)}
        WHERE id = :device_id
        RETURNING *
    """
    
    result = db.execute(text(update_query), params)
    db.commit()
    
    row = result.fetchone()
    device_dict = dict(row._mapping)
    
    # Récupérer les infos patient si assigné
    patient_result = db.execute(
        text("""
            SELECT pd.patient_id, pd.application_date as assigned_at, 
                   u.first_name || ' ' || u.last_name as patient_name
            FROM patient_devices pd
            LEFT JOIN users u ON pd.patient_id = u.id
            WHERE pd.device_id = :device_id AND pd.is_active = true
        """),
        {"device_id": str(device_id)}
    ).fetchone()
    patient_info = dict(patient_result._mapping) if patient_result else None
    
    device_response = {
        "id": str(device_dict["id"]),
        "serial_number": device_dict.get("device_id", ""),
        "model": (device_dict.get("hardware_version") or "") or "PansConnect-V1",
        "firmware_version": device_dict.get("firmware_version"),
        "hardware_version": device_dict.get("hardware_version"),
        "battery_level": device_dict.get("battery_level"),
        "last_calibration_date": device_dict.get("calibration_date"),
        "status": DeviceStatus(device_dict["status"]),
        "patient_id": str(patient_info["patient_id"]) if patient_info and patient_info.get("patient_id") else None,
        "assigned_at": patient_info["assigned_at"] if patient_info and patient_info.get("assigned_at") else None,
        "created_at": device_dict["created_at"],
        "updated_at": device_dict["updated_at"],
        "last_connection": device_dict.get("last_seen"),
        "patient_name": patient_info["patient_name"] if patient_info and patient_info.get("patient_name") else None,
    }
    
    return device_response


@router.post("/{device_id}/assign", response_model=DeviceResponse)
def assign_device_to_patient(
    device_id: UUID,
    assign_data: DeviceAssign,

    current_user: User = Depends(require_role(["admin", "medecin"])),
    db: Session = Depends(get_db)
):
    """
    Assigner un device à un patient (admin ou médecin uniquement).
    Après assignation, les alertes de ce patient sont acquittées pour le rôle courant (médecin/admin).
    """
    # Vérifier que le device existe
    device_result = db.execute(
        text("SELECT * FROM devices WHERE id = :device_id"),
        {"device_id": str(device_id)}
    )
    device_row = device_result.fetchone()
    
    if not device_row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Device {device_id} non trouvé"
        )
    
    # Vérifier que le patient existe
    patient_result = db.execute(
        text("SELECT id FROM users WHERE id = :patient_id AND role = 'patient'"),
        {"patient_id": assign_data.patient_id}
    )
    if not patient_result.fetchone():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Patient non trouvé"
        )
    
    # Supprimer toute assignation active existante pour ce device
    # (on supprime au lieu de désactiver pour éviter les problèmes de contrainte unique)
    db.execute(
        text("""
            DELETE FROM patient_devices 
            WHERE device_id = :device_id AND is_active = true
        """),
        {"device_id": str(device_id)}
    )
    
    # Créer la nouvelle assignation
    db.execute(
        text("""
            INSERT INTO patient_devices (patient_id, device_id, application_date, is_active)
            VALUES (:patient_id, :device_id, CURRENT_TIMESTAMP, true)
        """),
        {
            "patient_id": assign_data.patient_id,
            "device_id": str(device_id)
        }
    )
    # Acquitter les alertes de ce patient pour le rôle courant (médecin ou admin)
    now = datetime.utcnow()
    if current_user.role == "medecin":
        db.execute(
            text("""
                UPDATE alerts
                SET acknowledged_by_medecin_at = :now
                WHERE patient_id = :patient_id AND acknowledged_by_medecin_at IS NULL
            """),
            {"patient_id": assign_data.patient_id, "now": now},
        )
    elif current_user.role == "admin":
        db.execute(
            text("""
                UPDATE alerts
                SET acknowledged_by_admin_at = :now
                WHERE patient_id = :patient_id AND acknowledged_by_admin_at IS NULL
            """),
            {"patient_id": assign_data.patient_id, "now": now},
        )
    
    db.commit()
    
    # Récupérer le device mis à jour avec les infos patient
    device_dict = dict(device_row._mapping)
    patient_result = db.execute(
        text("""
            SELECT pd.patient_id, pd.application_date as assigned_at,
                   u.first_name || ' ' || u.last_name as patient_name
            FROM patient_devices pd
            LEFT JOIN users u ON pd.patient_id = u.id
            WHERE pd.device_id = :device_id AND pd.is_active = true
        """),
        {"device_id": str(device_id)}
    ).fetchone()
    patient_info = dict(patient_result._mapping) if patient_result else None
    
    device_response = {
        "id": str(device_dict["id"]),
        "serial_number": device_dict.get("device_id", ""),
        "model": (device_dict.get("hardware_version") or "") or "PansConnect-V1",
        "firmware_version": device_dict.get("firmware_version"),
        "hardware_version": device_dict.get("hardware_version"),
        "battery_level": device_dict.get("battery_level"),
        "last_calibration_date": device_dict.get("calibration_date"),
        "status": DeviceStatus(device_dict["status"]),
        "patient_id": str(patient_info["patient_id"]) if patient_info and patient_info.get("patient_id") else None,
        "assigned_at": patient_info["assigned_at"] if patient_info and patient_info.get("assigned_at") else None,
        "created_at": device_dict["created_at"],
        "updated_at": device_dict["updated_at"],
        "last_connection": device_dict.get("last_seen"),
        "patient_name": patient_info["patient_name"] if patient_info and patient_info.get("patient_name") else None,
    }
    
    return device_response

@router.delete("/{device_id}/assign", status_code=status.HTTP_204_NO_CONTENT)
def unassign_device(
    device_id: UUID,
    db: Session = Depends(get_db)
):
    """
    Retirer l'assignation d'un device (le rendre disponible)
    """
    # Vérifier que le device existe
    device_result = db.execute(
        text("SELECT id FROM devices WHERE id = :device_id"),
        {"device_id": str(device_id)}
    )
    if not device_result.fetchone():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Device {device_id} non trouvé"
        )
    
    # Vérifier s'il existe une assignation active
    check_result = db.execute(
        text("""
            SELECT id FROM patient_devices 
            WHERE device_id = :device_id AND is_active = true
        """),
        {"device_id": str(device_id)}
    )
    
    if not check_result.fetchone():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Aucune assignation active trouvée pour ce device"
        )
    
    # Supprimer toutes les assignations actives pour ce device
    # (on supprime au lieu de désactiver pour éviter les problèmes de contrainte unique)
    db.execute(
        text("""
            DELETE FROM patient_devices 
            WHERE device_id = :device_id AND is_active = true
        """),
        {"device_id": str(device_id)}
    )
    
    db.commit()
    return None

