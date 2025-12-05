from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, desc, text
from typing import Optional
from datetime import datetime, timedelta
from uuid import UUID

from app.database import get_db
from app.schemas.measurement import (
    MeasurementCreate, 
    MeasurementResponse, 
    MeasurementList,
    MeasurementStats,
    PatientMeasurementStats,
    MeasurementType
)
from app.models import Measurement, Device, User
from app.api.deps import get_current_user, require_role

router = APIRouter(prefix="/api/v1/measurements", tags=["Measurements"])

# ============================================================================
# POST /api/v1/measurements - Recevoir mesure depuis pansement BLE
# ============================================================================

@router.post('', response_model=MeasurementResponse, status_code=status.HTTP_201_CREATED)
def create_measurement(
    measurement_data: MeasurementCreate,
    db: Session = Depends(get_db)
):
    '''
    Recevoir une mesure depuis un pansement connecté (BLE).
    
    Pas d'authentification requise car appelé par le pansement IoT.
    
    Note: Le modèle Measurement réel utilise temperature, impedance, orp
    au lieu d'un champ value générique. On doit mapper measurement_type vers
    le bon champ.
    '''
    # Vérifier que le device existe
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
    
    # Récupérer le patient_id associé à ce device (via patient_devices)
    patient_device_result = db.execute(
        text("""
            SELECT patient_id FROM patient_devices 
            WHERE device_id = CAST(:device_id AS uuid) AND is_active = TRUE
            LIMIT 1
        """),
        {"device_id": str(device.id)}
    ).first()
    
    patient_id = patient_device_result[0] if patient_device_result else None
    
    # Créer la mesure avec le nouveau modèle simplifié
    new_measurement = Measurement(
        device_id=device.id,
        measurement_type=measurement_data.measurement_type.value,
        value=float(measurement_data.value),
        unit=measurement_data.unit,
        quality_score=measurement_data.quality_score,
        timestamp=datetime.utcnow()
    )
    
    # Mettre à jour last_connection du device
    device.last_seen = datetime.utcnow()
    
    db.add(new_measurement)
    db.commit()
    db.refresh(new_measurement)
    
    # ✨ Écrire automatiquement dans InfluxDB (temps réel)
    try:
        from app.core.influxdb_client import write_measurement
        write_measurement(
            device_id=device.device_id,  # Numéro de série du device
            patient_id=str(patient_id) if patient_id else None,
            measurement_type=measurement_data.measurement_type.value,
            value=float(measurement_data.value),
            unit=measurement_data.unit,
            quality_score=measurement_data.quality_score,
            timestamp=new_measurement.timestamp
        )
    except Exception as e:
        # Ne pas bloquer si InfluxDB est indisponible
        print(f"⚠️ Impossible d'écrire dans InfluxDB: {e}")
    
    # Enrichir avec infos device/patient
    patient = db.query(User).filter(User.id == patient_id).first() if patient_id else None
    
    return MeasurementResponse(
        id=str(new_measurement.id),
        device_id=str(new_measurement.device_id),
        measurement_type=measurement_data.measurement_type,
        value=new_measurement.value,
        unit=new_measurement.unit,
        quality_score=new_measurement.quality_score,
        timestamp=new_measurement.timestamp,
        device_serial=device.device_id,
        patient_id=str(patient_id) if patient_id else None,
        patient_name=f'{patient.first_name} {patient.last_name}' if patient else None
    )

# ============================================================================
# GET /api/v1/measurements/patient/{patient_id} - Historique mesures patient
# ============================================================================

@router.get('/patient/{patient_id}', response_model=MeasurementList)
def get_patient_measurements(
    patient_id: str,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
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
        relation = db.execute(
            text("""
                SELECT id FROM medecin_patients 
                WHERE medecin_id = CAST(:medecin_id AS uuid) 
                AND patient_id = CAST(:patient_id AS uuid)
            """),
            {"medecin_id": str(current_user.id), "patient_id": patient_id}
        ).first()
        
        if not relation:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Ce patient n\'est pas sous votre responsabilité'
            )
    
    # Récupérer les device_ids associés à ce patient
    device_ids_result = db.execute(
        text("""
            SELECT device_id FROM patient_devices 
            WHERE patient_id = CAST(:patient_id AS uuid) AND is_active = TRUE
        """),
        {"patient_id": patient_id}
    ).fetchall()
    
    if not device_ids_result:
        return {
            'measurements': [],
            'total': 0,
            'page': 1,
            'per_page': limit
        }
    
    device_ids = [row[0] for row in device_ids_result]
    
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
            measurement_type=measurement_type_enum,
            value=m.value,
            unit=m.unit,
            quality_score=m.quality_score,
            timestamp=m.timestamp,
            device_serial=device.device_id if device else None,
            patient_id=patient_id,
            patient_name=f'{patient.first_name} {patient.last_name}' if patient else None
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
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Aucune mesure trouvée'
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
        measurement_type=measurement_type_enum,
        value=latest.value,
        unit=latest.unit,
        quality_score=latest.quality_score,
        timestamp=latest.timestamp,
        device_serial=device.device_id if device else None,
        patient_id=patient_id,
        patient_name=f'{patient.first_name} {patient.last_name}' if patient else None
    )

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
