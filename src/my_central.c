#include <bluetooth/scan.h> // La librairie facile de Nordic
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <bluetooth/scan.h> 
#include "my_central.h"
#include "my_service.h"
#include <bluetooth/gatt_dm.h> // Le Discovery Manager


LOG_MODULE_REGISTER(central);
/* L'UUID du capteur que l'on cherche.
   Pour l'exercice, disons qu'on cherche un autre appareil qui a le MÊME service que nous.
   (Ou un UUID standard comme Heart Rate si tu as un capteur cardiaque) */
#define REMOTE_SERVICE_UUID  MY_TARGET_UUID


static struct bt_uuid_128 service_uuid_target = BT_UUID_INIT_128(MY_TARGET_UUID);

// Variable globale pour stocker le pointeur vers la connexion du capteur
static struct bt_conn *conn_to_sensor = NULL; 

static void scan_filter_match(struct bt_scan_device_info *device_info,
                              struct bt_scan_filter_match *filter_match,
                              bool connectable)
{
    char addr[BT_ADDR_LE_STR_LEN];
    struct bt_conn *conn; // <--- 1. On crée une variable temporaire
    int err;

    if (conn_to_sensor) {
        return; 
    }

    bt_addr_le_to_str(device_info->recv_info->addr, addr, sizeof(addr));
    LOG_INF("CIBLE TROUVÉE ! Tentative de connexion à %s", addr);

    bt_scan_stop();
    
    // 2. LANCER la connexion (Avec le 4ème argument !)
    err = bt_conn_le_create(
        device_info->recv_info->addr,
        BT_CONN_LE_CREATE_CONN,
        BT_LE_CONN_PARAM_DEFAULT,
        &conn // <--- C'est LUI qui manquait ! Le pointeur pour récupérer la connexion.
    );

    if (err) {
        LOG_ERR("Erreur creation connexion (err %d). Relance scan.", err);
        bt_scan_start(BT_SCAN_TYPE_SCAN_PASSIVE); 
    } else {
        // Si la création a réussi, on libère notre référence locale.
        // Pourquoi ? Parce que la connexion "officielle" sera gérée et stockée 
        // dans la fonction callback 'connected' que nous avons définie plus bas.
        // Si on ne fait pas ça, on garde une référence inutile en mémoire.
        bt_conn_unref(conn);
    }
}

/* On enregistre nos fonctions de rappel */
BT_SCAN_CB_INIT(scan_cb, scan_filter_match, NULL, NULL, NULL);

void scan_init(void) // Pas de static ici !
{
    int err;

    struct bt_le_scan_param scan_param = {
        .type       = BT_LE_SCAN_TYPE_PASSIVE,
        .options    = BT_LE_SCAN_OPT_NONE,
        .interval   = BT_GAP_SCAN_FAST_INTERVAL,
        .window     = BT_GAP_SCAN_FAST_WINDOW,
    };

    struct bt_scan_init_param scan_init = {
        .connect_if_match = 0, // On met 0 pour l'instant (mode manuel)
        .scan_param = &scan_param,
        .conn_param = BT_LE_CONN_PARAM_DEFAULT
    };

    bt_scan_init(&scan_init);
    bt_scan_cb_register(&scan_cb);

    /* Ajout du filtre UUID */
    /* Attention : on caste le pointeur en (struct bt_uuid*) pour que la fonction l'accepte */
    err = bt_scan_filter_add(BT_SCAN_FILTER_TYPE_UUID, (struct bt_uuid *)&service_uuid_target);
    if (err) {
        LOG_ERR("Erreur ajout filtre (err %d)", err);
        return;
    }

    err = bt_scan_filter_enable(BT_SCAN_UUID_FILTER, false);
    if (err) {
        LOG_ERR("Erreur activation filtre (err %d)", err);
    }
    
    LOG_INF("Scanner initialisé.");
}


/* --- Callbacks du Discovery Manager --- */

/* Appelé quand la découverte est terminée avec succès */
static void discovery_completed(struct bt_gatt_dm *dm, void *context)
{
    LOG_INF("Service découvert avec succès !");
    
    /* C'est ICI qu'on va chercher notre caractéristique spécifique 
       et s'abonner (on le fera à l'étape suivante).
       Pour l'instant, on veut juste voir ce message. */

    /* IMPORTANT : Il faut toujours libérer la mémoire du DM à la fin */
    bt_gatt_dm_data_release(dm);
}

/* Appelé si le service n'est pas trouvé */
static void discovery_service_not_found(struct bt_conn *conn, void *context)
{
    LOG_WRN("Service non trouvé sur cet appareil.");
}

/* Appelé s'il y a une erreur technique */
static void discovery_error(struct bt_conn *conn, int err, void *context)
{
    LOG_ERR("Erreur lors de la découverte (err %d)", err);
}

/* Structure qui regroupe nos callbacks */
static struct bt_gatt_dm_cb discovery_cb = {
    .completed = discovery_completed,
    .service_not_found = discovery_service_not_found,
    .error_found = discovery_error,
};



/* Fonctions de rappel du lien (S'exécutent lors de la connexion/déconnexion) */

void connected(struct bt_conn *conn, uint8_t err)
{
    char addr[BT_ADDR_LE_STR_LEN];
    bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));

    if (err) {
        LOG_ERR("Connexion échouée à %s (err %d)", addr, err);
        return;
    }

    LOG_INF("Connexion établie avec succès avec %s", addr);

    // Stocker la connexion et arrêter le scan pour économiser la batterie
    conn_to_sensor = bt_conn_ref(conn); // Conserve la référence
    bt_le_scan_stop(); // On arrête le scan une fois qu'on a notre cible !

    /* Prochaine étape : Lancer le service discovery (GATT) */
        /* --- LE NOUVEAU CODE COMMENCE ICI --- */
    
    /* On lance la découverte UNIQUEMENT pour le service qu'on cherche (Remote UUID) */
    /* Le NULL à la fin est le contexte (pas utilisé ici) */
    err = bt_gatt_dm_start(conn, (struct bt_uuid *)&service_uuid_target, &discovery_cb, NULL);
    
    if (err) {
        LOG_ERR("Impossible de lancer la découverte (err %d)", err);
    } else {
        LOG_INF("Lancement de la découverte des services...");
    }
}

void disconnected(struct bt_conn *conn, uint8_t reason)
{
    char addr[BT_ADDR_LE_STR_LEN];
    bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));

    LOG_INF("Déconnexion de %s (Raison: 0x%02x)", addr, reason);

    // Libérer la référence et relancer le scan pour retrouver le capteur
    if (conn_to_sensor) {
        bt_conn_unref(conn_to_sensor);
        conn_to_sensor = NULL;
    }
    
    // On pourrait relancer le scan ici si la cible est perdue
}

// Macro Zephyr pour enregistrer les callbacks de connexion
BT_CONN_CB_DEFINE(conn_callbacks) = {
    .connected    = connected,
    .disconnected = disconnected,
};