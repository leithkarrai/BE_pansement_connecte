"""
Client InfluxDB pour stocker les mesures en temps réel
"""
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS
from typing import Optional
from datetime import datetime
import os

# Configuration InfluxDB
INFLUXDB_URL = os.getenv("INFLUXDB_URL", "http://localhost:8086")
INFLUXDB_TOKEN = os.getenv("INFLUXDB_TOKEN", "my-super-secret-auth-token-change-me")
INFLUXDB_ORG = os.getenv("INFLUXDB_ORG", "pansement-connecte")
INFLUXDB_BUCKET = os.getenv("INFLUXDB_BUCKET", "measurements")

# Client global
_client: Optional[InfluxDBClient] = None
_write_api = None


def get_influxdb_client() -> InfluxDBClient:
    """Obtenir le client InfluxDB (singleton)"""
    global _client
    if _client is None:
        _client = InfluxDBClient(
            url=INFLUXDB_URL,
            token=INFLUXDB_TOKEN,
            org=INFLUXDB_ORG
        )
    return _client


def get_write_api():
    """Obtenir l'API d'écriture InfluxDB"""
    global _write_api
    if _write_api is None:
        client = get_influxdb_client()
        _write_api = client.write_api(write_options=SYNCHRONOUS)
    return _write_api


def write_measurement(
    device_id: str,
    patient_id: Optional[str],
    measurement_type: str,
    value: float,
    unit: str,
    quality_score: Optional[float] = None,
    timestamp: Optional[datetime] = None
):
    """
    Écrire une mesure dans InfluxDB
    
    Args:
        device_id: ID du pansement
        patient_id: ID du patient (optionnel)
        measurement_type: Type de mesure (temperature, humidity, etc.)
        value: Valeur mesurée
        unit: Unité de mesure
        quality_score: Score de qualité (0-100)
        timestamp: Timestamp (par défaut: maintenant)
    
    Returns:
        True si succès, False sinon
    """
    try:
        write_api = get_write_api()
        
        # Créer un point de données
        point = Point(measurement_type) \
            .tag("device_id", device_id) \
            .field("value", float(value)) \
            .field("unit", unit)
        
        if patient_id:
            point = point.tag("patient_id", patient_id)
        
        if quality_score is not None:
            point = point.field("quality_score", float(quality_score))
        
        if timestamp:
            point = point.time(timestamp)
        
        # Écrire dans InfluxDB
        write_api.write(bucket=INFLUXDB_BUCKET, org=INFLUXDB_ORG, record=point)
        
        return True
    except Exception as e:
        print(f"⚠️ Erreur InfluxDB (non bloquant): {e}")
        # Ne pas bloquer si InfluxDB est indisponible
        return False


def close_influxdb_client():
    """Fermer la connexion InfluxDB"""
    global _client, _write_api
    if _write_api:
        _write_api.close()
    if _client:
        _client.close()
        _client = None
        _write_api = None

