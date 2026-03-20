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


def _dt_iso(dt):
    """Retourne la date en chaîne ISO pour la sérialisation JSON (évite les soucis de parsing côté Flutter)."""
    if dt is None:
        return None
    return dt.isoformat() if hasattr(dt, 'isoformat') else str(dt)


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

    Modèle d'acquittement/suppression par rôle:
    - patient: acknowledged_at / deleted_at
    - medecin: acknowledged_by_medecin_at / deleted_by_medecin_at
    - admin: acknowledged_by_admin_at / deleted_by_admin_at

    => chaque rôle a sa propre "vue non lue/non supprimée" d'une même alerte.
    """
    # Construire la requête de base
    query = db.query(Alert)
    role = (getattr(current_user, 'role', None) or '').strip().lower()

    # Filtrer selon les permissions (insensible à la casse : Medecin, medecin, Admin, admin)
    if role == 'patient':
        # Patient: uniquement ses propres alertes
        query = query.filter(Alert.patient_id == current_user.id)

    elif role == 'medecin':
        # Médecin: alertes de ses patients assignés uniquement (pour voir "Nouvelles données patient")
        try:
            result = db.execute(
                text("SELECT patient_id FROM medecin_patients WHERE medecin_id = :medecin_id"),
                {"medecin_id": str(current_user.id)}
            )
            patient_ids = [row[0] for row in result.fetchall()]
            patient_ids = [pid if isinstance(pid, UUID) else UUID(str(pid)) for pid in patient_ids]
        except Exception:
            patient_ids = []

        if not patient_ids:
            return {
                'alerts': [],
                'total': 0,
                'unacknowledged': 0,
                'critical': 0
            }

        query = query.filter(Alert.patient_id.in_(patient_ids))

    # Admin: voit toutes les alertes (pas de filtre patient)

    # Exclure les alertes "supprimées" par le rôle courant (masquage indépendant par rôle).
    if role == 'patient':
        query = query.filter(Alert.deleted_at.is_(None))
    elif role == 'medecin':
        query = query.filter(Alert.deleted_by_medecin_at.is_(None))
    elif role == 'admin':
        query = query.filter(Alert.deleted_by_admin_at.is_(None))

    # Filtrer par sévérité si spécifié
    if severity:
        query = query.filter(Alert.severity == severity)
    
    # Filtrer par type d'alerte si spécifié
    if alert_type:
        query = query.filter(Alert.alert_type == alert_type)

    # Non acquittées : critère par rôle (acquittement indépendant).
    if role == 'admin':
        unack_filter = Alert.acknowledged_by_admin_at.is_(None)
    elif role == 'medecin':
        unack_filter = Alert.acknowledged_by_medecin_at.is_(None)
    else:
        unack_filter = Alert.acknowledged_at.is_(None)

    unacknowledged = query.filter(unack_filter).count()
    if unacknowledged_only:
        query = query.filter(unack_filter)

    # Compter le total (après filtre unacknowledged si demandé)
    total = query.count()

    # Compter les alertes critiques
    critical_query = query.filter(Alert.severity == 'critical')
    critical = critical_query.count()

    # Pagination et tri (plus récentes en premier)
    alerts = query.order_by(Alert.triggered_at.desc()).offset(skip).limit(limit).all()

    # Convertir en dictionnaires (dates en ISO pour le client Flutter)
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
            'triggered_at': _dt_iso(alert.triggered_at),
            'acknowledged_at': _dt_iso(alert.acknowledged_at),
            'acknowledged_by': str(alert.acknowledged_by) if alert.acknowledged_by else None,
            'acknowledged_by_medecin_at': _dt_iso(getattr(alert, 'acknowledged_by_medecin_at', None)),
            'acknowledged_by_admin_at': _dt_iso(getattr(alert, 'acknowledged_by_admin_at', None)),
            'resolved_at': _dt_iso(alert.resolved_at),
            'resolved_by': str(alert.resolved_by) if alert.resolved_by else None,
            'resolution_note': alert.resolution_note,
            'notification_sent': alert.notification_sent,
            'notification_method': alert.notification_method,
            'notification_sent_at': _dt_iso(alert.notification_sent_at)
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

    Cette route reprend la même logique d'acquittement/suppression par rôle que GET /alerts.
    """
    # Convertir patient_id en UUID
    try:
        patient_uuid = UUID(patient_id)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='ID patient invalide'
        )
    
    # Vérifier les permissions (insensible à la casse)
    role = (getattr(current_user, 'role', None) or '').strip().lower()
    if role == 'patient':
        # Patient: uniquement ses propres alertes
        if str(current_user.id) != patient_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Accès refusé. Vous ne pouvez consulter que vos propres alertes.'
            )
    
    elif role == 'medecin':
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
    
    # Exclure les alertes "supprimées" par le rôle courant
    if role == 'patient':
        query = query.filter(Alert.deleted_at.is_(None))
    elif role == 'medecin':
        query = query.filter(Alert.deleted_by_medecin_at.is_(None))
    elif role == 'admin':
        query = query.filter(Alert.deleted_by_admin_at.is_(None))
    
    # Filtrer par sévérité si spécifié
    if severity:
        query = query.filter(Alert.severity == severity)

    # Non acquittées : critère par rôle
    if role == 'admin':
        unack_filter = Alert.acknowledged_by_admin_at.is_(None)
    elif role == 'medecin':
        unack_filter = Alert.acknowledged_by_medecin_at.is_(None)
    else:
        unack_filter = Alert.acknowledged_at.is_(None)

    unacknowledged = query.filter(unack_filter).count()
    if unacknowledged_only:
        query = query.filter(unack_filter)

    total = query.count()

    # Compter les alertes critiques
    critical_query = query.filter(Alert.severity == 'critical')
    critical = critical_query.count()

    # Pagination et tri
    alerts = query.order_by(Alert.triggered_at.desc()).offset(skip).limit(limit).all()

    # Convertir en dictionnaires (dates en ISO pour le client Flutter)
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
            'triggered_at': _dt_iso(alert.triggered_at),
            'acknowledged_at': _dt_iso(alert.acknowledged_at),
            'acknowledged_by': str(alert.acknowledged_by) if alert.acknowledged_by else None,
            'acknowledged_by_medecin_at': _dt_iso(getattr(alert, 'acknowledged_by_medecin_at', None)),
            'acknowledged_by_admin_at': _dt_iso(getattr(alert, 'acknowledged_by_admin_at', None)),
            'resolved_at': _dt_iso(alert.resolved_at),
            'resolved_by': str(alert.resolved_by) if alert.resolved_by else None,
            'resolution_note': alert.resolution_note,
            'notification_sent': alert.notification_sent,
            'notification_method': alert.notification_method,
            'notification_sent_at': _dt_iso(alert.notification_sent_at)
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

@router.put('/{alert_id}/acknowledge')
def acknowledge_alert(
    alert_id: str,
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
    # Convertir alert_id en UUID (accepter les espaces, tolérant si format légèrement incorrect)
    alert_id_clean = (alert_id or '').strip()
    try:
        alert_uuid = UUID(alert_id_clean)
    except (ValueError, TypeError, AttributeError):
        # ID invalide : retourner 404 pour que l'app puisse rafraîchir sans afficher "erreur" (comportement idempotent)
        return {'id': alert_id_clean, 'acknowledged': False, 'message': 'ID invalide ou alerte introuvable'}
    
    # Chercher l'alerte (y compris si "supprimée" pour un autre rôle)
    alert = db.query(Alert).filter(Alert.id == alert_uuid).first()
    if not alert:
        # Idempotent : alerte déjà supprimée ou inexistante = 200 avec message
        return {'id': str(alert_uuid), 'acknowledged': False, 'message': 'Alerte introuvable'}
    
    # Vérifier les permissions (insensible à la casse)
    role = (getattr(current_user, 'role', None) or '').strip().lower()
    if role == 'patient':
        # Patient: uniquement ses propres alertes
        if str(alert.patient_id) != str(current_user.id):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Accès refusé. Vous ne pouvez acquitter que vos propres alertes.'
            )
    
    elif role == 'medecin':
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
    
    from datetime import datetime
    now = datetime.utcnow()
    
    # Acquittement par rôle (idempotent : déjà acquitté = on retourne 200 sans erreur)
    # Utiliser role normalisé pour que "Admin", "MEDECIN" etc. soient reconnus
    already_done = False
    if role == 'medecin':
        if getattr(alert, 'acknowledged_by_medecin_at', None):
            already_done = True
        else:
            alert.acknowledged_by_medecin_at = now
    elif role == 'admin':
        if getattr(alert, 'acknowledged_by_admin_at', None):
            already_done = True
        else:
            alert.acknowledged_by_admin_at = now
    else:
        # patient (ou rôle inconnu, on met acknowledged_at pour compatibilité)
        if alert.acknowledged_at:
            already_done = True
        else:
            alert.acknowledged_at = now
            alert.acknowledged_by = current_user.id
    
    if not already_done:
        db.commit()
        db.refresh(alert)
    
    # Retourner l'alerte mise à jour (dates en ISO pour le client Flutter)
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
        'triggered_at': _dt_iso(alert.triggered_at),
        'acknowledged_at': _dt_iso(alert.acknowledged_at),
        'acknowledged_by': str(alert.acknowledged_by) if alert.acknowledged_by else None,
        'acknowledged_by_medecin_at': _dt_iso(getattr(alert, 'acknowledged_by_medecin_at', None)),
        'acknowledged_by_admin_at': _dt_iso(getattr(alert, 'acknowledged_by_admin_at', None)),
        'resolved_at': _dt_iso(alert.resolved_at),
        'resolved_by': str(alert.resolved_by) if alert.resolved_by else None,
        'resolution_note': alert.resolution_note,
        'notification_sent': alert.notification_sent,
        'notification_method': alert.notification_method,
        'notification_sent_at': _dt_iso(alert.notification_sent_at)
    }


# ============================================================================
# DELETE /api/v1/alerts/{alert_id} - Supprimer une alerte
# ============================================================================

@router.delete('/{alert_id}', status_code=status.HTTP_204_NO_CONTENT)
def delete_alert(
    alert_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Supprimer une alerte.
    
    Permissions:
    - Admin: Peut supprimer n'importe quelle alerte
    - Médecin: Peut supprimer les alertes de ses patients
    - Patient: Peut supprimer uniquement ses propres alertes
    """
    try:
        alert_uuid = UUID(alert_id)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='ID alerte invalide'
        )
    
    alert = db.query(Alert).filter(Alert.id == alert_uuid).first()
    if not alert:
        # Idempotent : déjà "supprimée" pour ce rôle = succès (204)
        return None
    
    role = (getattr(current_user, 'role', None) or '').strip().lower()
    if role == 'patient':
        if str(alert.patient_id) != str(current_user.id):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Accès refusé. Vous ne pouvez supprimer que vos propres alertes.'
            )
    elif role == 'medecin':
        result = db.execute(
            text("SELECT id FROM medecin_patients WHERE medecin_id = :medecin_id AND patient_id = :patient_id"),
            {"medecin_id": str(current_user.id), "patient_id": str(alert.patient_id)}
        )
        if not result.fetchone():
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Accès refusé. Cette alerte n\'appartient pas à un de vos patients.'
            )
    
    # Marquer comme supprimée pour CE rôle uniquement (pas de vraie suppression en base)
    from datetime import datetime
    now = datetime.utcnow()
    if role == 'patient':
        db.execute(
            text("UPDATE alerts SET deleted_at = :now WHERE id = :aid"),
            {"now": now, "aid": str(alert_uuid)},
        )
    elif role == 'medecin':
        db.execute(
            text("UPDATE alerts SET deleted_by_medecin_at = :now WHERE id = :aid"),
            {"now": now, "aid": str(alert_uuid)},
        )
    elif role == 'admin':
        db.execute(
            text("UPDATE alerts SET deleted_by_admin_at = :now WHERE id = :aid"),
            {"now": now, "aid": str(alert_uuid)},
        )
    else:
        return None  # rôle inconnu, ne rien faire
    db.commit()
    return None

