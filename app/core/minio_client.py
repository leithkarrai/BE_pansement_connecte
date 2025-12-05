"""
Client MinIO pour stockage de fichiers (S3-compatible)
"""
from minio import Minio
from minio.error import S3Error
import os
from typing import Optional
from datetime import timedelta

# Configuration MinIO
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "localhost:9000")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY", "minioadmin_password_change_me")
MINIO_SECURE = os.getenv("MINIO_SECURE", "false").lower() == "true"

# Buckets par défaut
BUCKET_PHOTOS = "wound-photos"
BUCKET_DOCUMENTS = "documents"
BUCKET_AVATARS = "avatars"

# Client global (singleton)
_minio_client: Optional[Minio] = None


def get_minio_client() -> Minio:
    """
    Obtenir le client MinIO (singleton)
    Crée une seule connexion réutilisable
    """
    global _minio_client
    if _minio_client is None:
        try:
            _minio_client = Minio(
                MINIO_ENDPOINT,
                access_key=MINIO_ACCESS_KEY,
                secret_key=MINIO_SECRET_KEY,
                secure=MINIO_SECURE
            )
            # Tester la connexion en listant les buckets
            _minio_client.list_buckets()
        except Exception as e:
            print(f"⚠️ Erreur connexion MinIO: {e}")
            _minio_client = None
    return _minio_client


def create_bucket_if_not_exists(bucket_name: str) -> bool:
    """
    Créer un bucket MinIO s'il n'existe pas
    
    Args:
        bucket_name: Nom du bucket
    
    Returns:
        True si succès, False sinon
    """
    try:
        client = get_minio_client()
        if client is None:
            return False
        
        if not client.bucket_exists(bucket_name):
            client.make_bucket(bucket_name)
            print(f"✅ Bucket '{bucket_name}' créé")
        return True
    except S3Error as e:
        print(f"⚠️ Erreur MinIO lors de la création du bucket '{bucket_name}': {e}")
        return False
    except Exception as e:
        print(f"⚠️ Erreur inattendue lors de la création du bucket '{bucket_name}': {e}")
        return False


def upload_file(
    bucket_name: str,
    object_name: str,
    file_data: bytes,
    content_type: str = "application/octet-stream",
    metadata: Optional[dict] = None
) -> Optional[str]:
    """
    Uploader un fichier dans MinIO
    
    Args:
        bucket_name: Nom du bucket
        object_name: Nom de l'objet (chemin dans le bucket)
        file_data: Données du fichier (bytes)
        content_type: Type MIME du fichier
        metadata: Métadonnées optionnelles
    
    Returns:
        URL du fichier ou None si erreur
    """
    try:
        client = get_minio_client()
        if client is None:
            return None
        
        # Créer le bucket s'il n'existe pas
        create_bucket_if_not_exists(bucket_name)
        
        # Uploader le fichier
        from io import BytesIO
        file_stream = BytesIO(file_data)
        
        client.put_object(
            bucket_name,
            object_name,
            file_stream,
            len(file_data),
            content_type=content_type,
            metadata=metadata
        )
        
        # Retourner le chemin du fichier
        return f"/{bucket_name}/{object_name}"
    except S3Error as e:
        print(f"⚠️ Erreur MinIO lors de l'upload de '{object_name}': {e}")
        return None
    except Exception as e:
        print(f"⚠️ Erreur inattendue lors de l'upload de '{object_name}': {e}")
        return None


def download_file(bucket_name: str, object_name: str) -> Optional[bytes]:
    """
    Télécharger un fichier depuis MinIO
    
    Args:
        bucket_name: Nom du bucket
        object_name: Nom de l'objet
    
    Returns:
        Données du fichier (bytes) ou None si erreur
    """
    try:
        client = get_minio_client()
        if client is None:
            return None
        
        response = client.get_object(bucket_name, object_name)
        data = response.read()
        response.close()
        response.release_conn()
        return data
    except S3Error as e:
        print(f"⚠️ Erreur MinIO lors du téléchargement de '{object_name}': {e}")
        return None
    except Exception as e:
        print(f"⚠️ Erreur inattendue lors du téléchargement de '{object_name}': {e}")
        return None


def delete_file(bucket_name: str, object_name: str) -> bool:
    """
    Supprimer un fichier de MinIO
    
    Args:
        bucket_name: Nom du bucket
        object_name: Nom de l'objet
    
    Returns:
        True si succès, False sinon
    """
    try:
        client = get_minio_client()
        if client is None:
            return False
        
        client.remove_object(bucket_name, object_name)
        return True
    except S3Error as e:
        print(f"⚠️ Erreur MinIO lors de la suppression de '{object_name}': {e}")
        return False
    except Exception as e:
        print(f"⚠️ Erreur inattendue lors de la suppression de '{object_name}': {e}")
        return False


def get_file_url(bucket_name: str, object_name: str, expires: int = 3600) -> Optional[str]:
    """
    Générer une URL temporaire (presigned) pour accéder à un fichier
    
    Args:
        bucket_name: Nom du bucket
        object_name: Nom de l'objet
        expires: Durée de validité en secondes (défaut: 1 heure)
    
    Returns:
        URL presigned ou None si erreur
    """
    try:
        client = get_minio_client()
        if client is None:
            return None
        
        url = client.presigned_get_object(bucket_name, object_name, expires=timedelta(seconds=expires))
        return url
    except S3Error as e:
        print(f"⚠️ Erreur MinIO lors de la génération de l'URL pour '{object_name}': {e}")
        return None
    except Exception as e:
        print(f"⚠️ Erreur inattendue lors de la génération de l'URL pour '{object_name}': {e}")
        return None


def file_exists(bucket_name: str, object_name: str) -> bool:
    """
    Vérifier si un fichier existe dans MinIO
    
    Args:
        bucket_name: Nom du bucket
        object_name: Nom de l'objet
    
    Returns:
        True si le fichier existe, False sinon
    """
    try:
        client = get_minio_client()
        if client is None:
            return False
        
        client.stat_object(bucket_name, object_name)
        return True
    except S3Error:
        return False
    except Exception:
        return False


def test_minio_connection() -> bool:
    """
    Tester la connexion MinIO
    
    Returns:
        True si connexion OK, False sinon
    """
    try:
        client = get_minio_client()
        if client is None:
            return False
        # Lister les buckets pour tester la connexion
        client.list_buckets()
        return True
    except S3Error as e:
        print(f"⚠️ Erreur connexion MinIO: {e}")
        return False
    except Exception as e:
        print(f"⚠️ Erreur inattendue lors de la connexion MinIO: {e}")
        return False


def initialize_buckets():
    """
    Initialiser tous les buckets nécessaires au démarrage
    """
    buckets = [BUCKET_PHOTOS, BUCKET_DOCUMENTS, BUCKET_AVATARS]
    for bucket in buckets:
        create_bucket_if_not_exists(bucket)

