"""
Routes API pour le système d'alertes
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import text
from typing import Optional
from uuid import UUID

from app.database import get_db
from app.schemas.alert import AlertResponse, AlertList, AlertAcknowledgeRequest
from app.models.alert import Alert
from app.models.user import User
from app.api.deps import get_current_user, require_role

router = APIRouter(prefix="/api/v1/alerts", tags=["Alerts"])


# ============================================================================
# GET /api/v1/alerts - Liste des alertes actives
# ============================================================================

@router.get('', response_model=AlertList)
def get_alerts(
    skip: int = Query(0, ge=0, description='Nombre d\'éléments à sauter'),
    limit: int = Query(10, ge=1, le=100, description='Nombre d\'éléments à retourner'),
    severity: Optional[str] = Query(None, description='Filtrer par sévérité (info, warning, critical)'),
    alert_type: Optional[str] = Query(None, description='Filtrer par type d\'alerte'),
    unacknowledged_only: bool = Query(False, description='Afficher uniquement les alertes non acquittées'),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Liste des alertes actives avec pagination et filtres.
    
    Permissions:
    - Admin: Voit toutes les alertes
    - Médecin: Voit les alertes de ses patients
    - Patient: Voit uniquement ses propres alertes
    """
    # Construire la requête de base
    query = db.query(Alert)
    
    # Filtrer selon les permissions
    if current_user.role == 'patient':
        # Patient: uniquement ses propres alertes
        query = query.filter(Alert.patient_id == current_user.id)
    
    elif current_user.role == 'medecin':
        # Médecin: alertes de ses patients uniquement
        result = db.execute(
            text("SELECT patient_id FROM medecin_patients WHERE medecin_id = :medecin_id"),
            {"medecin_id": str(current_user.id)}
        )
        patient_ids = [row[0] for row in result.fetchall()]
        
        if not patient_ids:
            # Si le médecin n'a pas de patients, retourner une liste vide
            return {
                'alerts': [],
                'total': 0,
                'unacknowledged': 0,
                'critical': 0
            }
        
        query = query.filter(Alert.patient_id.in_(patient_ids))
    
    # Admin voit toutes les alertes (pas de filtre supplémentaire)
    
    # Filtrer par sévérité si spécifié
    if severity:
        query = query.filter(Alert.severity == severity)
    
    # Filtrer par type d'alerte si spécifié
    if alert_type:
        query = query.filter(Alert.alert_type == alert_type)
    
    # Filtrer les alertes non acquittées si demandé
    if unacknowledged_only:
        query = query.filter(Alert.acknowledged_at.is_(None))
    
    # Compter le total
    total = query.count()
    
    # Compter les alertes non acquittées
    unacknowledged_query = query.filter(Alert.acknowledged_at.is_(None))
    unacknowledged = unacknowledged_query.count()
    
    # Compter les alertes critiques
    critical_query = query.filter(Alert.severity == 'critical')
    critical = critical_query.count()
    
    # Pagination et tri (plus récentes en premier)
    alerts = query.order_by(Alert.triggered_at.desc()).offset(skip).limit(limit).all()
    
    # Convertir en dictionnaires
    alerts_list = []
    for alert in alerts:
        alerts_list.append({
            'id': str(alert.id),
            'patient_device_id': str(alert.patient_device_id),
            'patient_id': str(alert.patient_id),
            'device_id': str(alert.device_id),
            'measurement_id': str(alert.measurement_id) if alert.measurement_id else None,
            'alert_type': alert.alert_type,
            'severity': alert.severity,
            'title': alert.title,
            'message': alert.message,
            'current_value': float(alert.current_value) if alert.current_value else None,
            'threshold_value': float(alert.threshold_value) if alert.threshold_value else None,
            'triggered_at': alert.triggered_at,
            'acknowledged_at': alert.acknowledged_at,
            'acknowledged_by': str(alert.acknowledged_by) if alert.acknowledged_by else None,
            'resolved_at': alert.resolved_at,
            'resolved_by': str(alert.resolved_by) if alert.resolved_by else None,
            'resolution_note': alert.resolution_note,
            'notification_sent': alert.notification_sent,
            'notification_method': alert.notification_method,
            'notification_sent_at': alert.notification_sent_at
        })
    
    return {
        'alerts': alerts_list,
        'total': total,
        'unacknowledged': unacknowledged,
        'critical': critical
    }


# ============================================================================
# GET /api/v1/alerts/patient/{patient_id} - Alertes d'un patient
# ============================================================================

@router.get('/patient/{patient_id}', response_model=AlertList)
def get_patient_alerts(
    patient_id: str,
    skip: int = Query(0, ge=0, description='Nombre d\'éléments à sauter'),
    limit: int = Query(10, ge=1, le=100, description='Nombre d\'éléments à retourner'),
    severity: Optional[str] = Query(None, description='Filtrer par sévérité'),
    unacknowledged_only: bool = Query(False, description='Afficher uniquement les alertes non acquittées'),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Récupérer les alertes d'un patient spécifique.
    
    Permissions:
    - Admin: Peut voir les alertes de n'importe quel patient
    - Médecin: Peut voir les alertes de ses patients uniquement
    - Patient: Peut voir uniquement ses propres alertes
    """
    # Convertir patient_id en UUID
    try:
        patient_uuid = UUID(patient_id)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='ID patient invalide'
        )
    
    # Vérifier les permissions
    if current_user.role == 'patient':
        # Patient: uniquement ses propres alertes
        if str(current_user.id) != patient_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Accès refusé. Vous ne pouvez consulter que vos propres alertes.'
            )
    
    elif current_user.role == 'medecin':
        # Médecin: vérifier que c'est un de ses patients
        result = db.execute(
            text("SELECT id FROM medecin_patients WHERE medecin_id = :medecin_id AND patient_id = :patient_id"),
            {"medecin_id": str(current_user.id), "patient_id": patient_id}
        )
        if not result.fetchone():
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Accès refusé. Ce patient n\'est pas sous votre responsabilité.'
            )
    
    # Admin peut voir toutes les alertes (pas de vérification supplémentaire)
    
    # Construire la requête
    query = db.query(Alert).filter(Alert.patient_id == patient_uuid)
    
    # Filtrer par sévérité si spécifié
    if severity:
        query = query.filter(Alert.severity == severity)
    
    # Filtrer les alertes non acquittées si demandé
    if unacknowledged_only:
        query = query.filter(Alert.acknowledged_at.is_(None))
    
    # Compter le total
    total = query.count()
    
    # Compter les alertes non acquittées
    unacknowledged_query = query.filter(Alert.acknowledged_at.is_(None))
    unacknowledged = unacknowledged_query.count()
    
    # Compter les alertes critiques
    critical_query = query.filter(Alert.severity == 'critical')
    critical = critical_query.count()
    
    # Pagination et tri
    alerts = query.order_by(Alert.triggered_at.desc()).offset(skip).limit(limit).all()
    
    # Convertir en dictionnaires
    alerts_list = []
    for alert in alerts:
        alerts_list.append({
            'id': str(alert.id),
            'patient_device_id': str(alert.patient_device_id),
            'patient_id': str(alert.patient_id),
            'device_id': str(alert.device_id),
            'measurement_id': str(alert.measurement_id) if alert.measurement_id else None,
            'alert_type': alert.alert_type,
            'severity': alert.severity,
            'title': alert.title,
            'message': alert.message,
            'current_value': float(alert.current_value) if alert.current_value else None,
            'threshold_value': float(alert.threshold_value) if alert.threshold_value else None,
            'triggered_at': alert.triggered_at,
            'acknowledged_at': alert.acknowledged_at,
            'acknowledged_by': str(alert.acknowledged_by) if alert.acknowledged_by else None,
            'resolved_at': alert.resolved_at,
            'resolved_by': str(alert.resolved_by) if alert.resolved_by else None,
            'resolution_note': alert.resolution_note,
            'notification_sent': alert.notification_sent,
            'notification_method': alert.notification_method,
            'notification_sent_at': alert.notification_sent_at
        })
    
    return {
        'alerts': alerts_list,
        'total': total,
        'unacknowledged': unacknowledged,
        'critical': critical
    }


# ============================================================================
# PUT /api/v1/alerts/{id}/acknowledge - Acquitter une alerte
# ============================================================================

@router.put('/{alert_id}/acknowledge', response_model=AlertResponse)
def acknowledge_alert(
    alert_id: str,
    acknowledge_data: AlertAcknowledgeRequest = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Acquitter une alerte (marquer comme vue).
    
    Permissions:
    - Admin: Peut acquitter n'importe quelle alerte
    - Médecin: Peut acquitter les alertes de ses patients
    - Patient: Peut acquitter uniquement ses propres alertes
    """
    # Convertir alert_id en UUID
    try:
        alert_uuid = UUID(alert_id)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='ID alerte invalide'
        )
    
    # Chercher l'alerte
    alert = db.query(Alert).filter(Alert.id == alert_uuid).first()
    if not alert:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Alerte non trouvée'
        )
    
    # Vérifier les permissions
    if current_user.role == 'patient':
        # Patient: uniquement ses propres alertes
        if str(alert.patient_id) != str(current_user.id):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Accès refusé. Vous ne pouvez acquitter que vos propres alertes.'
            )
    
    elif current_user.role == 'medecin':
        # Médecin: vérifier que c'est un de ses patients
        result = db.execute(
            text("SELECT id FROM medecin_patients WHERE medecin_id = :medecin_id AND patient_id = :patient_id"),
            {"medecin_id": str(current_user.id), "patient_id": str(alert.patient_id)}
        )
        if not result.fetchone():
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Accès refusé. Cette alerte n\'appartient pas à un de vos patients.'
            )
    
    # Admin peut acquitter toutes les alertes (pas de vérification supplémentaire)
    
    # Vérifier que l'alerte n'est pas déjà acquittée
    if alert.acknowledged_at:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Cette alerte a déjà été acquittée'
        )
    
    # Acquitter l'alerte
    from datetime import datetime
    alert.acknowledged_at = datetime.utcnow()
    alert.acknowledged_by = current_user.id
    
    db.commit()
    db.refresh(alert)
    
    # Retourner l'alerte mise à jour
    return {
        'id': str(alert.id),
        'patient_device_id': str(alert.patient_device_id),
        'patient_id': str(alert.patient_id),
        'device_id': str(alert.device_id),
        'measurement_id': str(alert.measurement_id) if alert.measurement_id else None,
        'alert_type': alert.alert_type,
        'severity': alert.severity,
        'title': alert.title,
        'message': alert.message,
        'current_value': float(alert.current_value) if alert.current_value else None,
        'threshold_value': float(alert.threshold_value) if alert.threshold_value else None,
        'triggered_at': alert.triggered_at,
        'acknowledged_at': alert.acknowledged_at,
        'acknowledged_by': str(alert.acknowledged_by) if alert.acknowledged_by else None,
        'resolved_at': alert.resolved_at,
        'resolved_by': str(alert.resolved_by) if alert.resolved_by else None,
        'resolution_note': alert.resolution_note,
        'notification_sent': alert.notification_sent,
        'notification_method': alert.notification_method,
        'notification_sent_at': alert.notification_sent_at
    }

