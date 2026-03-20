"""
Client Redis pour cache et sessions
"""
import redis
import json
from typing import Optional, Any
import os
from datetime import timedelta


def _safe_print(msg: str) -> None:
    """Message ASCII pour eviter UnicodeEncodeError (Windows cp1252)."""
    safe = (msg or "").encode("ascii", "replace").decode("ascii")
    try:
        print(safe)
    except Exception:
        import sys
        sys.stderr.buffer.write(safe.encode("ascii") + b"\n")
        sys.stderr.buffer.flush()

# Configuration Redis
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "redis_password_change_me")
REDIS_DB = int(os.getenv("REDIS_DB", "0"))

# Client global (singleton)
_redis_client: Optional[redis.Redis] = None


def get_redis_client() -> redis.Redis:
    """
    Obtenir le client Redis (singleton)
    Crée une seule connexion réutilisable
    """
    global _redis_client
    if _redis_client is None:
        try:
            _redis_client = redis.Redis(
                host=REDIS_HOST,
                port=REDIS_PORT,
                password=REDIS_PASSWORD,
                db=REDIS_DB,
                decode_responses=True,  # Décode automatiquement en UTF-8
                socket_connect_timeout=5,
                socket_timeout=5
            )
            # Tester la connexion
            _redis_client.ping()
        except Exception as e:
            _safe_print(f"[WARN] Erreur connexion Redis: {e}")
            _redis_client = None
    return _redis_client


def cache_set(key: str, value: Any, expire: int = 3600) -> bool:
    """
    Stocker une valeur dans Redis avec expiration
    
    Args:
        key: Clé Redis (ex: "user:123", "devices:list")
        value: Valeur à stocker (sera convertie en JSON)
        expire: Durée d'expiration en secondes (défaut: 1 heure)
    
    Returns:
        True si succès, False sinon
    """
    try:
        client = get_redis_client()
        if client is None:
            return False
        
        # Convertir en JSON si ce n'est pas une string
        if isinstance(value, (dict, list)):
            json_value = json.dumps(value, default=str)
        elif isinstance(value, str):
            json_value = value
        else:
            json_value = json.dumps(value, default=str)
        
        return client.setex(key, expire, json_value)
    except Exception as e:
        _safe_print(f"[WARN] Erreur Redis SET '{key}': {e}")
        return False


def cache_get(key: str) -> Optional[Any]:
    """
    Récupérer une valeur depuis Redis
    
    Args:
        key: Clé Redis
    
    Returns:
        Valeur décodée ou None si introuvable
    """
    try:
        client = get_redis_client()
        if client is None:
            return None
        
        value = client.get(key)
        if value is None:
            return None
        
        # Essayer de décoder en JSON
        try:
            return json.loads(value)
        except (json.JSONDecodeError, TypeError):
            return value
    except Exception as e:
        _safe_print(f"[WARN] Erreur Redis GET '{key}': {e}")
        return None


def cache_delete(key: str) -> bool:
    """
    Supprimer une clé Redis
    
    Args:
        key: Clé Redis ou pattern (ex: "user:*")
    
    Returns:
        True si succès
    """
    try:
        client = get_redis_client()
        if client is None:
            return False
        
        # Si pattern avec *, utiliser scan
        if '*' in key:
            keys = []
            for k in client.scan_iter(match=key):
                keys.append(k)
            if keys:
                return bool(client.delete(*keys))
            return True
        else:
            return bool(client.delete(key))
    except Exception as e:
        _safe_print(f"[WARN] Erreur Redis DELETE '{key}': {e}")
        return False


def cache_increment(key: str, amount: int = 1, expire: int = 3600) -> int:
    """
    Incrémenter un compteur dans Redis
    
    Args:
        key: Clé Redis
        amount: Montant à incrémenter
        expire: Durée d'expiration en secondes
    
    Returns:
        Nouvelle valeur du compteur
    """
    try:
        client = get_redis_client()
        if client is None:
            return 0
        
        value = client.incrby(key, amount)
        client.expire(key, expire)
        return value
    except Exception as e:
        _safe_print(f"[WARN] Erreur Redis INCR '{key}': {e}")
        return 0


def test_redis_connection() -> bool:
    """
    Tester la connexion Redis
    
    Returns:
        True si connexion OK, False sinon
    """
    try:
        client = get_redis_client()
        if client is None:
            return False
        return client.ping()
    except Exception as e:
        _safe_print(f"[WARN] Erreur connexion Redis: {e}")
        return False

