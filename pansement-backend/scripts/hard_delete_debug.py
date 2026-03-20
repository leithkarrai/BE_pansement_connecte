import re
import traceback
from uuid import UUID

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.models.user import User
from app.models.patient_device import PatientDevice


def load_database_url(env_path: str) -> str:
    try:
        content = open(env_path, "r", encoding="utf-8").read()
    except Exception as e:
        raise RuntimeError(f"Impossible de lire {env_path}: {e}")

    m = re.search(r"^DATABASE_URL=(.*)$", content, re.M)
    if not m:
        raise RuntimeError("DATABASE_URL introuvable dans le fichier .env")
    return m.group(1).strip()


def simulate_hard_delete(user_id: str) -> None:
    db_url = load_database_url(".env")
    engine = create_engine(db_url)
    Session = sessionmaker(bind=engine)

    user_uuid = UUID(user_id)
    session = Session()
    trans = session.begin()
    try:
        # Purge patient_devices (meme logique que l'endpoint)
        deleted_pd = (
            session.query(PatientDevice)
            .filter(PatientDevice.patient_id == user_uuid)
            .delete(synchronize_session=False)
        )

        user = session.query(User).filter(User.id == user_uuid).first()
        print(f"[debug] user found: {user is not None}")
        print(f"[debug] patient_devices purged: {deleted_pd}")

        if user is None:
            raise RuntimeError("User non trouve")

        session.delete(user)
        session.flush()
        # Ne pas commit, on annule pour ne rien supprimer.
        trans.rollback()
        print("[debug] Simulation OK (rollback)")
    except Exception as e:
        try:
            trans.rollback()
        except Exception:
            pass
        print("[debug] Exception:", type(e).__name__, str(e))
        traceback.print_exc()
    finally:
        try:
            session.close()
        except Exception:
            pass


if __name__ == "__main__":
    # ID du patient qui déclenche l'erreur chez toi dans les logs.
    simulate_hard_delete("1fdadbb2-7869-4549-a98d-1b10461798aa")

