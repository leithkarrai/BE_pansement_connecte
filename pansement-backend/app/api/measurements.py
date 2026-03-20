from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, desc, text
from typing import Optional
from datetime import datetime, timedelta
from uuid import UUID

from app.database import get_db
from app.schemas.measurement import (
    MeasurementCreate,
    MeasurementCreateOpen,
    MeasurementResponse,
    MeasurementList,
    MeasurementStats,
    PatientMeasurementStats,
    MeasurementType,
)
from app.models import Measurement, Device, User, Alert
from app.models.patient_device import PatientDevice
from app.api.deps import get_current_user, require_role

router = APIRouter(prefix="/api/v1/measurements", tags=["Measurements"])


def _safe_stderr(text: str) -> None:
    """Écrit du texte sur stderr en ASCII (évite UnicodeEncodeError sur Windows cp1252)."""
    import sys
    safe = (text or "").encode("ascii", "replace").decode("ascii")
    try:
        sys.stderr.buffer.write(safe.encode("ascii") + b"\n")
        sys.stderr.buffer.flush()
    except Exception:
        pass


def create_new_measurements_alert(
    db: Session,
    *,
    patient_id: UUID,
    patient_device_id: UUID,
    device_id: UUID,
    measurement_id: Optional[UUID] = None,
    patient_name: Optional[str] = None,
    dedupe_minutes: int = 5,
) -> Optional[Alert]:
    """
    Crée une alerte "Nouvelles mesures reçues" pour notifier médecin/admin.
    Évite les doublons : au plus une alerte par patient sur les dernières dedupe_minutes.
    Ne lève pas d'exception (pour ne pas faire échouer l'enregistrement des mesures).
    """
    try:
        recent = datetime.utcnow() - timedelta(minutes=dedupe_minutes)
        existing = (
            db.query(Alert)
            .filter(
                Alert.patient_id == patient_id,
                Alert.alert_type == "new_measurements",
                Alert.triggered_at >= recent,
            )
            .first()
        )
        if existing:
            return None
        message = (
            f"{patient_name} a envoyé de nouvelles mesures."
            if patient_name
            else "Le patient a envoyé de nouvelles mesures d'impédance."
        )
        alert = Alert(
            patient_device_id=patient_device_id,
            patient_id=patient_id,
            device_id=device_id,
            measurement_id=measurement_id,
            alert_type="new_measurements",
            severity="info",
            title="Nouvelles mesures reçues",
            message=message,
        )
        db.add(alert)
        db.commit()
        return alert
    except Exception as e:
        db.rollback()
        import traceback
        _safe_stderr(f"[WARN] Creation alerte new_measurements: {e}")
        _safe_stderr(traceback.format_exc())
        return None

# ============================================================================
# POST /api/v1/measurements - Recevoir mesure depuis pansement BLE
# ============================================================================

@router.post('', response_model=MeasurementResponse, status_code=status.HTTP_201_CREATED)
def create_measurement(
    measurement_data: MeasurementCreateOpen,
    db: Session = Depends(get_db)
):
    '''
    Recevoir une mesure depuis l'app patient (pansement BLE).
    Accepte tout type de mesure (temperature, adc, s1, s2, etc.) pour éviter 422.

    Notes de fonctionnement:
    - `MeasurementCreateOpen` accepte un measurement_type libre: utile quand le firmware
      envoie des types supplémentaires (impedance, adc_raw, etc.) pendant les tests.
    - Si le pansement n'est pas encore lié à un patient mais que `patient_id` est
      fourni dans la requête, on tente une auto-liaison pour ne pas perdre les mesures.
    - La création d'alerte (new_measurements) est "best effort": un échec d'alerte
      ne doit pas faire échouer l'enregistrement de la mesure.
    '''
    try:
        device_uuid = UUID(measurement_data.device_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='ID device invalide'
        )

    device = db.query(Device).filter(Device.id == device_uuid).first()
    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Pansement non trouvé'
        )

    # Récupérer le patient_device (id + patient_id) : requis pour créer l'alerte médecin/admin
    patient_device_id = None
    patient_id = None
    try:
        patient_device_result = db.execute(
            text("""
                SELECT id, patient_id FROM patient_devices
                WHERE device_id = CAST(:device_id AS uuid) AND is_active = TRUE
                LIMIT 1
            """),
            {"device_id": str(device.id)},
        ).first()
        if patient_device_result:
            patient_device_id = patient_device_result[0]
            patient_id = patient_device_result[1]
    except Exception as e:
        _safe_stderr(f"[WARN] Requete patient_devices (alerte non creee): {e}")

    # Auto-liaison "filet de sécurité":
    # si pas de liaison active mais `patient_id` est présent, créer (ou recréer) un
    # couple patient-device actif pour rendre les mesures visibles dans les écrans patient.
    if patient_id is None and getattr(measurement_data, 'patient_id', None):
        try:
            pid_str = (measurement_data.patient_id or '').strip()
            if pid_str:
                pid_uuid = UUID(pid_str)
                db.execute(
                    text("""
                        DELETE FROM patient_devices
                        WHERE device_id = CAST(:device_id AS uuid) AND is_active = true
                    """),
                    {"device_id": str(device.id)},
                )
                db.execute(
                    text("""
                        INSERT INTO patient_devices (patient_id, device_id, application_date, is_active)
                        VALUES (:patient_id, :device_id, CURRENT_TIMESTAMP, true)
                    """),
                    {"patient_id": str(pid_uuid), "device_id": str(device.id)},
                )
                db.commit()
                patient_id = pid_uuid
                patient_device_result = db.execute(
                    text("""
                        SELECT id, patient_id FROM patient_devices
                        WHERE device_id = CAST(:device_id AS uuid) AND is_active = TRUE LIMIT 1
                    """),
                    {"device_id": str(device.id)},
                ).first()
                if patient_device_result:
                    patient_device_id = patient_device_result[0]
        except Exception as e:
            db.rollback()
            _safe_stderr(f"[WARN] Auto-liaison patient-device: {e}")

    if patient_id is None:
        _safe_stderr(f"[WARN] Pas de liaison patient-device pour device_id={device.id} (assigner le pansement au patient)")

    quality = measurement_data.quality_score
    quality_int = int(quality) if quality is not None else None
    unit_val = (measurement_data.unit or '')[:20]

    # Stocker le lien patient_device_id afin de permettre le filtrage admin/médecin
    # même si la logique basée sur `patient_devices -> device_ids` devient incohérente.
    pdid_for_measurement = patient_device_id
    if pdid_for_measurement is not None and not isinstance(pdid_for_measurement, UUID):
        pdid_for_measurement = UUID(str(pdid_for_measurement))

    new_measurement = Measurement(
        device_id=device.id,
        measurement_type=measurement_data.measurement_type,
        value=float(measurement_data.value),
        unit=unit_val,
        quality_score=quality_int,
        timestamp=datetime.utcnow(),
        freq_hz=getattr(measurement_data, 'freq_hz', None),
        phase_deg=getattr(measurement_data, 'phase_deg', None),
        patient_device_id=pdid_for_measurement,
    )

    device.last_seen = datetime.utcnow()

    try:
        db.add(new_measurement)
        db.commit()
        db.refresh(new_measurement)
    except Exception as e:
        db.rollback()
        import traceback
        _safe_stderr(traceback.format_exc())
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Erreur enregistrement mesure: {str(e)}",
        )

    # Alerte "Nouvelles mesures reçues" pour médecin/admin (ne pas faire échouer la requête)
    if patient_id is not None and patient_device_id is not None:
        pid = patient_id if isinstance(patient_id, UUID) else UUID(str(patient_id))
        pdid = patient_device_id if isinstance(patient_device_id, UUID) else UUID(str(patient_device_id))
        patient = db.query(User).filter(User.id == pid).first()
        patient_name = (
            f"{patient.first_name} {patient.last_name}".strip() if patient else None
        )
        alert = create_new_measurements_alert(
            db,
            patient_id=pid,
            patient_device_id=pdid,
            device_id=device.id,
            measurement_id=new_measurement.id,
            patient_name=patient_name,
        )
        if alert:
            _safe_stderr(f"[OK] Alerte new_measurements creee pour patient {pid}")

    try:
        from app.core.influxdb_client import write_measurement
        write_measurement(
            device_id=device.device_id or '',
            patient_id=str(patient_id) if patient_id else None,
            measurement_type=measurement_data.measurement_type,
            value=float(measurement_data.value),
            unit=measurement_data.unit or '',
            quality_score=measurement_data.quality_score,
            timestamp=new_measurement.timestamp
        )
    except Exception as e:
        _safe_stderr(f"[WARN] InfluxDB: {e}")

    patient = db.query(User).filter(User.id == patient_id).first() if patient_id else None
    patient_name = None
    if patient:
        patient_name = f"{(patient.first_name or '')} {(patient.last_name or '')}".strip() or None

    return MeasurementResponse(
        id=str(new_measurement.id),
        device_id=str(new_measurement.device_id),
        measurement_type=measurement_data.measurement_type,
        value=new_measurement.value,
        unit=(new_measurement.unit if new_measurement.unit is not None else '') or unit_val,
        quality_score=new_measurement.quality_score,
        timestamp=new_measurement.timestamp,
        device_serial=(device.device_id if device.device_id else None),
        patient_id=str(patient_id) if patient_id else None,
        patient_name=patient_name,
        freq_hz=getattr(new_measurement, 'freq_hz', None),
        phase_deg=getattr(new_measurement, 'phase_deg', None),
    )

# ============================================================================
# GET /api/v1/measurements/patient/{patient_id} - Historique mesures patient
# ============================================================================

@router.get('/patient/{patient_id}', response_model=MeasurementList)
def get_patient_measurements(
    patient_id: str,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=500),
    measurement_type: Optional[MeasurementType] = Query(None, description='Filtrer par type'),
    start_date: Optional[datetime] = Query(None, description='Date début'),
    end_date: Optional[datetime] = Query(None, description='Date fin'),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    '''
    Historique des mesures d'un patient.
    
    Permissions:
    - Admin: Tous les patients
    - Médecin: Ses patients uniquement
    - Patient: Ses propres mesures uniquement
    '''
    # Vérifier permissions
    if current_user.role == 'patient':
        if str(current_user.id) != patient_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Accès refusé'
            )
    elif current_user.role == 'medecin':
        # Vérifier que c'est un de ses patients
        try:
            relation = db.execute(
                text("""
                    SELECT id FROM medecin_patients 
                    WHERE medecin_id = CAST(:medecin_id AS uuid) 
                    AND patient_id = CAST(:patient_id AS uuid)
                """),
                {"medecin_id": str(current_user.id), "patient_id": patient_id}
            ).first()
        except Exception:
            relation = None
        if not relation:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Ce patient n\'est pas sous votre responsabilité'
            )
    
    # Récupérer les device_ids associés à ce patient (actifs, puis tous si vide)
    device_ids = []
    for active_only in (True, False):
        try:
            if active_only:
                device_ids_result = db.execute(
                    text("""
                        SELECT device_id FROM patient_devices 
                        WHERE patient_id = CAST(:patient_id AS uuid) AND is_active = TRUE
                    """),
                    {"patient_id": patient_id}
                ).fetchall()
            else:
                device_ids_result = db.execute(
                    text("""
                        SELECT device_id FROM patient_devices 
                        WHERE patient_id = CAST(:patient_id AS uuid)
                    """),
                    {"patient_id": patient_id}
                ).fetchall()
        except Exception as e:
            _safe_stderr(f"[WARN] get_patient_measurements patient_devices: {e}")
            device_ids_result = []
        try:
            device_ids = [
                row[0] if isinstance(row[0], UUID) else UUID(str(row[0]))
                for row in device_ids_result
            ]
        except (ValueError, TypeError):
            device_ids = []
        if device_ids:
            break

    if not device_ids:
        # Fallback: tenter via le lien direct stocké sur `measurements.patient_device_id`.
        # Permet de retrouver les données même si `patient_devices` est temporairement vide
        # ou si le filtrage par `is_active` ne retourne pas les device_ids attendus.
        try:
            patient_uuid = UUID(patient_id)
        except (ValueError, TypeError):
            return {
                'measurements': [],
                'total': 0,
                'page': 1,
                'per_page': limit
            }

        query = (
            db.query(Measurement)
            .join(PatientDevice, Measurement.patient_device_id == PatientDevice.id)
            .filter(PatientDevice.patient_id == patient_uuid)
        )

        if measurement_type:
            query = query.filter(Measurement.measurement_type == measurement_type.value)
        if start_date:
            query = query.filter(Measurement.timestamp >= start_date)
        if end_date:
            query = query.filter(Measurement.timestamp <= end_date)

        total = query.count()
        measurements = (
            query.order_by(desc(Measurement.timestamp))
            .offset(skip)
            .limit(limit)
            .all()
        )

        patient = db.query(User).filter(User.id == patient_uuid).first()
        devices = {}
        if device_ids:
            devices = {d.id: d for d in db.query(Device).filter(Device.id.in_(device_ids)).all()}

        measurements_response = []
        for m in measurements:
            # Récupérer device_serial (cohérent avec la logique existante).
            device = db.query(Device).filter(Device.id == m.device_id).first()
            try:
                measurement_type_enum = MeasurementType(m.measurement_type)
            except ValueError:
                measurement_type_enum = None
            measurements_response.append(MeasurementResponse(
                id=str(m.id),
                device_id=str(m.device_id),
                measurement_type=(measurement_type_enum.value if measurement_type_enum is not None else (m.measurement_type or '')),
                value=m.value,
                unit=m.unit,
                quality_score=m.quality_score,
                timestamp=m.timestamp,
                device_serial=device.device_id if device else None,
                patient_id=patient_id,
                patient_name=f'{patient.first_name} {patient.last_name}' if patient else None,
                freq_hz=getattr(m, 'freq_hz', None),
                phase_deg=getattr(m, 'phase_deg', None),
            ))

        return {
            'measurements': measurements_response,
            'total': total,
            'page': skip // limit + 1,
            'per_page': limit
        }
    
    # Construire la requête avec le nouveau modèle simplifié
    query = db.query(Measurement).filter(Measurement.device_id.in_(device_ids))
    
    # Filtrer par type de mesure
    if measurement_type:
        query = query.filter(Measurement.measurement_type == measurement_type.value)
    
    if start_date:
        query = query.filter(Measurement.timestamp >= start_date)
    
    if end_date:
        query = query.filter(Measurement.timestamp <= end_date)
    
    # Total
    total = query.count()
    
    # Pagination (ordre décroissant: plus récent d'abord)
    measurements = query.order_by(desc(Measurement.timestamp)).offset(skip).limit(limit).all()
    
    # Enrichir
    devices = {d.id: d for d in db.query(Device).filter(Device.id.in_(device_ids)).all()}
    # Convertir patient_id en UUID pour la requête
    try:
        patient_uuid = UUID(patient_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='ID patient invalide')
    patient = db.query(User).filter(User.id == patient_uuid).first()
    
    measurements_response = []
    for m in measurements:
        device = devices.get(m.device_id)
        
        # Convertir measurement_type string en enum
        try:
            measurement_type_enum = MeasurementType(m.measurement_type)
        except ValueError:
            measurement_type_enum = None
        
        measurements_response.append(MeasurementResponse(
            id=str(m.id),
            device_id=str(m.device_id),
            measurement_type=(measurement_type_enum.value if measurement_type_enum is not None else m.measurement_type),
            value=m.value,
            unit=m.unit,
            quality_score=m.quality_score,
            timestamp=m.timestamp,
            device_serial=device.device_id if device else None,
            patient_id=patient_id,
            patient_name=f'{patient.first_name} {patient.last_name}' if patient else None,
            freq_hz=getattr(m, 'freq_hz', None),
            phase_deg=getattr(m, 'phase_deg', None),
        ))
    
    return {
        'measurements': measurements_response,
        'total': total,
        'page': skip // limit + 1,
        'per_page': limit
    }

# ============================================================================
# GET /api/v1/measurements/latest/{patient_id} - Dernière mesure
# ============================================================================

@router.get('/latest/{patient_id}', response_model=MeasurementResponse)
def get_latest_measurement(
    patient_id: str,
    measurement_type: Optional[MeasurementType] = Query(None, description='Type spécifique'),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    '''
    Dernière mesure d'un patient (toutes catégories ou type spécifique).
    
    Permissions: Identiques à l'historique
    '''
    # Mêmes vérifications de permissions
    if current_user.role == 'patient':
        if str(current_user.id) != patient_id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Accès refusé')
    elif current_user.role == 'medecin':
        relation = db.execute(
            text("""
                SELECT id FROM medecin_patients 
                WHERE medecin_id = CAST(:medecin_id AS uuid) 
                AND patient_id = CAST(:patient_id AS uuid)
            """),
            {"medecin_id": str(current_user.id), "patient_id": patient_id}
        ).first()
        
        if not relation:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Accès refusé')
    
    # Récupérer les device_ids associés à ce patient
    device_ids_result = db.execute(
        text("""
            SELECT device_id FROM patient_devices 
            WHERE patient_id = CAST(:patient_id AS uuid) AND is_active = TRUE
        """),
        {"patient_id": patient_id}
    ).fetchall()
    
    if not device_ids_result:
        # Fallback: via measurements.patient_device_id.
        try:
            patient_uuid = UUID(patient_id)
        except (ValueError, TypeError):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Aucune mesure trouvée')

        query = (
            db.query(Measurement)
            .join(PatientDevice, Measurement.patient_device_id == PatientDevice.id)
            .filter(PatientDevice.patient_id == patient_uuid)
        )
        if measurement_type:
            query = query.filter(Measurement.measurement_type == measurement_type.value)

        latest = query.order_by(desc(Measurement.timestamp)).first()
        if not latest:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Aucune mesure trouvée')

        device = db.query(Device).filter(Device.id == latest.device_id).first()
        patient = db.query(User).filter(User.id == patient_uuid).first()

        # Convertir type en enum quand possible (même logique que l'autre endpoint).
        try:
            measurement_type_enum = MeasurementType(latest.measurement_type)
        except ValueError:
            measurement_type_enum = None

        return MeasurementResponse(
            id=str(latest.id),
            device_id=str(latest.device_id),
            measurement_type=(measurement_type_enum.value if measurement_type_enum is not None else latest.measurement_type),
            value=latest.value,
            unit=latest.unit,
            quality_score=latest.quality_score,
            timestamp=latest.timestamp,
            device_serial=device.device_id if device else None,
            patient_id=patient_id,
            patient_name=f'{patient.first_name} {patient.last_name}' if patient else None,
            freq_hz=getattr(latest, 'freq_hz', None),
            phase_deg=getattr(latest, 'phase_deg', None),
        )
    
    device_ids = [row[0] for row in device_ids_result]
    
    # Requête avec le nouveau modèle simplifié
    query = db.query(Measurement).filter(Measurement.device_id.in_(device_ids))
    
    if measurement_type:
        query = query.filter(Measurement.measurement_type == measurement_type.value)
    
    # Dernière mesure
    latest = query.order_by(desc(Measurement.timestamp)).first()
    
    if not latest:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Aucune mesure trouvée'
        )
    
    # Enrichir
    device = db.query(Device).filter(Device.id == latest.device_id).first()
    patient = db.query(User).filter(User.id == patient_id).first()
    
    # Convertir measurement_type string en enum
    try:
        measurement_type_enum = MeasurementType(latest.measurement_type)
    except ValueError:
        measurement_type_enum = None
    
    return MeasurementResponse(
        id=str(latest.id),
        device_id=str(latest.device_id),
        measurement_type=measurement_type_enum if measurement_type_enum is not None else latest.measurement_type,
        value=latest.value,
        unit=latest.unit,
        quality_score=latest.quality_score,
        timestamp=latest.timestamp,
        device_serial=device.device_id if device else None,
        patient_id=patient_id,
        patient_name=f'{patient.first_name} {patient.last_name}' if patient else None,
        freq_hz=getattr(latest, 'freq_hz', None),
        phase_deg=getattr(latest, 'phase_deg', None),
    )

# ============================================================================
# GET /api/v1/measurements/today-count - Nombre de mesures enregistrées aujourd'hui
# ============================================================================

@router.get('/today-count')
def get_today_measurements_count(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    '''
    Nombre de mesures créées aujourd'hui (minuit UTC -> maintenant).
    Admin: toutes les mesures. Médecin: mesures des devices de ses patients.
    '''
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    role = (getattr(current_user, 'role', None) or '').strip().lower()

    if role == 'admin':
        count = db.query(func.count(Measurement.id)).filter(
            Measurement.timestamp >= today_start,
        ).scalar() or 0
        return {'count': count}
    if role == 'medecin':
        try:
            result = db.execute(
                text("""
                    SELECT pd.device_id FROM patient_devices pd
                    INNER JOIN medecin_patients mp ON mp.patient_id = pd.patient_id
                    WHERE mp.medecin_id = CAST(:medecin_id AS uuid) AND pd.is_active = TRUE
                """),
                {"medecin_id": str(current_user.id)},
            ).fetchall()
            device_ids = [row[0] if isinstance(row[0], UUID) else UUID(str(row[0])) for row in result]
        except Exception:
            device_ids = []
        if not device_ids:
            return {'count': 0}
        count = db.query(func.count(Measurement.id)).filter(
            Measurement.timestamp >= today_start,
            Measurement.device_id.in_(device_ids),
        ).scalar() or 0
        return {'count': count}
    # Patient: ses propres devices
    try:
        result = db.execute(
            text("""
                SELECT device_id FROM patient_devices
                WHERE patient_id = CAST(:patient_id AS uuid) AND is_active = TRUE
            """),
            {"patient_id": str(current_user.id)},
        ).fetchall()
        device_ids = [row[0] if isinstance(row[0], UUID) else UUID(str(row[0])) for row in result]
    except Exception:
        device_ids = []
    if not device_ids:
        return {'count': 0}
    count = db.query(func.count(Measurement.id)).filter(
        Measurement.timestamp >= today_start,
        Measurement.device_id.in_(device_ids),
    ).scalar() or 0
    return {'count': count}

# ============================================================================
# GET /api/v1/measurements/stats/{patient_id} - Statistiques
# ============================================================================

@router.get('/stats/{patient_id}', response_model=PatientMeasurementStats)
def get_patient_stats(
    patient_id: str,
    days: int = Query(7, ge=1, le=90, description='Nombre de jours d\'historique'),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    '''
    Statistiques des mesures d'un patient (moyennes, min, max, tendances).
    
    Permissions: Identiques à l'historique
    '''
    # Vérifications permissions
    if current_user.role == 'patient':
        if str(current_user.id) != patient_id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Accès refusé')
    elif current_user.role == 'medecin':
        relation = db.execute(
            text("""
                SELECT id FROM medecin_patients 
                WHERE medecin_id = CAST(:medecin_id AS uuid) 
                AND patient_id = CAST(:patient_id AS uuid)
            """),
            {"medecin_id": str(current_user.id), "patient_id": patient_id}
        ).first()
        
        if not relation:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Accès refusé')
    
    # Patient et devices
    # Convertir patient_id en UUID pour la requête
    try:
        patient_uuid = UUID(patient_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='ID patient invalide')
    patient = db.query(User).filter(User.id == patient_uuid).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Patient non trouvé')
    
    device_ids_result = db.execute(
        text("""
            SELECT device_id FROM patient_devices 
            WHERE patient_id = CAST(:patient_id AS uuid) AND is_active = TRUE
        """),
        {"patient_id": patient_id}
    ).fetchall()
    
    if not device_ids_result:
        return PatientMeasurementStats(
            patient_id=patient_id,
            patient_name=f'{patient.first_name} {patient.last_name}',
            device_serial=None,
            total_measurements=0,
            date_range={'start': None, 'end': None},
            stats_by_type=[]
        )
    
    device_ids = [row[0] for row in device_ids_result]
    
    # Période
    end_date = datetime.utcnow()
    start_date = end_date - timedelta(days=days)
    
    # Total mesures
    total = db.query(Measurement).filter(
        Measurement.device_id.in_(device_ids),
        Measurement.timestamp >= start_date
    ).count()
    
    # Stats par type
    stats_by_type = []
    
    # Parcourir tous les types de mesures
    for mtype in MeasurementType:
        type_stats = db.query(
            func.count(Measurement.id).label('count'),
            func.avg(Measurement.value).label('avg'),
            func.min(Measurement.value).label('min'),
            func.max(Measurement.value).label('max')
        ).filter(
            Measurement.device_id.in_(device_ids),
            Measurement.measurement_type == mtype.value,
            Measurement.timestamp >= start_date
        ).first()
        
        if type_stats and type_stats.count > 0:
            latest = db.query(Measurement).filter(
                Measurement.device_id.in_(device_ids),
                Measurement.measurement_type == mtype.value
            ).order_by(desc(Measurement.timestamp)).first()
            
            # Calcul tendance
            mid_date = start_date + timedelta(days=days//2)
            avg_recent = db.query(func.avg(Measurement.value)).filter(
                Measurement.device_id.in_(device_ids),
                Measurement.measurement_type == mtype.value,
                Measurement.timestamp >= mid_date
            ).scalar()
            
            avg_old = db.query(func.avg(Measurement.value)).filter(
                Measurement.device_id.in_(device_ids),
                Measurement.measurement_type == mtype.value,
                Measurement.timestamp >= start_date,
                Measurement.timestamp < mid_date
            ).scalar()
            
            trend = 'stable'
            if avg_recent and avg_old:
                diff_percent = ((avg_recent - avg_old) / avg_old) * 100
                if diff_percent > 5:
                    trend = 'increasing'
                elif diff_percent < -5:
                    trend = 'decreasing'
            
            stats_by_type.append(MeasurementStats(
                measurement_type=mtype.value,
                count=type_stats.count,
                avg=round(float(type_stats.avg), 2) if type_stats.avg else None,
                min=round(float(type_stats.min), 2) if type_stats.min else None,
                max=round(float(type_stats.max), 2) if type_stats.max else None,
                latest_value=round(float(latest.value), 2) if latest else None,
                latest_timestamp=latest.timestamp if latest else None,
                trend=trend
            ))
    
    device = db.query(Device).filter(Device.id == device_ids[0]).first() if device_ids else None
    
    return PatientMeasurementStats(
        patient_id=patient_id,
        patient_name=f'{patient.first_name} {patient.last_name}',
        device_serial=device.device_id if device else None,
        total_measurements=total,
        date_range={'start': start_date, 'end': end_date},
        stats_by_type=stats_by_type
    )
