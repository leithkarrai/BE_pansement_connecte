// #include <zephyr/bluetooth/bluetooth.h>
// #include <zephyr/bluetooth/gatt.h>
// #include <zephyr/bluetooth/uuid.h>
// #include <zephyr/logging/log.h>
// #include <string.h>
// #include "my_service.h"

// LOG_MODULE_REGISTER(my_service_module);

// static struct bt_uuid_128 service_uuid = BT_UUID_INIT_128(MY_SERVICE_UUID);
// static struct bt_uuid_128 char_uuid = BT_UUID_INIT_128(MY_CHARACTERISTIC_UUID);
// // static uint16_t adc_value_cache = 0;

// /* Cache pour stocker la dernière chaîne JSON envoyée (Max 100 octets pour cet exemple) (on remplace la variable envoyé par le cache)*/
// static char json_payload_cache[100];

// /* Callback appelé quand le téléphone active/désactive les notifications (CCCD) */
// static void my_ccc_cfg_changed(const struct bt_gatt_attr *attr, uint16_t value)
// {
//     LOG_INF("Notifications activées: %d", (value == BT_GATT_CCC_NOTIFY));
// }

// /* DÉFINITION STATIQUE DU SERVICE GATT */
// BT_GATT_SERVICE_DEFINE(my_service,
//                        BT_GATT_PRIMARY_SERVICE(&service_uuid),

//                        /*Caractéristique ADC (Lecture + Notification)*/
//                        BT_GATT_CHARACTERISTIC(&char_uuid.uuid,
//                                               BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
//                                               BT_GATT_PERM_READ,
//                                               NULL, NULL, json_payload_cache), // mettre ici l'addresse de la valeur qu'on veut envoyer

//                        /* Descripteur CCC (Contrôlé par l'application mobile) */
//                        BT_GATT_CCC(my_ccc_cfg_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE), );

// /* Fonction publique d'envoi (appelée par main.c) */
// // int my_service_send_adc_value(uint16_t value)
// // {
// //     // Met à jour la valeur du cache
// //     adc_value_cache = value;

// //     // Envoie la notification si l'abonnement est actif.
// //     // On cible la Déclaration de la Caractéristique (Index 1)
// //     return bt_gatt_notify(NULL, &my_service.attrs[1], &value, sizeof(value));
// // }

// int my_service_send_json(const char *data, uint16_t len)
// {
//     // Sécurité : ne pas déborder du cache
//     if (len > sizeof(json_payload_cache))
//     {
//         LOG_ERR("JSON trop grand pour le buffer !");
//         return -1;
//     }

//     // Copie dans le cache local (pour permettre la lecture 'READ')
//     memcpy(json_payload_cache, data, len);

//     // Envoi de la notification
//     // Note : attrs[1] est toujours la déclaration, attrs[2] la valeur si on compte implicitement
//     // Mais le plus sûr est souvent d'utiliser l'attribut directement si accessible,
//     // ou de garder l'index 1 si votre définition est standard. Ici index 1 pointe vers la Value attribute.
//     return bt_gatt_notify(NULL, &my_service.attrs[2], data, len);
// }


#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/logging/log.h>
#include <string.h> // Nécessaire pour memset et memcpy

#include "my_service.h"

LOG_MODULE_REGISTER(my_service_module);

static struct bt_uuid_128 service_uuid = BT_UUID_INIT_128(MY_SERVICE_UUID);
static struct bt_uuid_128 char_uuid = BT_UUID_INIT_128(MY_CHARACTERISTIC_UUID);

/* * Cache local : C'est ici que les "déchets" survivent si on ne nettoie pas.
 * On prévoit large (128 ou 247 octets) pour supporter le MTU max.
 */
static char json_payload_cache[247]; 

static void my_ccc_cfg_changed(const struct bt_gatt_attr *attr, uint16_t value) {
    LOG_INF("Notifications changees: %d", (value == BT_GATT_CCC_NOTIFY));
}

BT_GATT_SERVICE_DEFINE(my_service,
    BT_GATT_PRIMARY_SERVICE(&service_uuid),
    
    /* Caractéristique */
    BT_GATT_CHARACTERISTIC(&char_uuid.uuid,
                           BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
                           BT_GATT_PERM_READ,
                           NULL, NULL, json_payload_cache),
                           
    /* CCCD */
    BT_GATT_CCC(my_ccc_cfg_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
);

/* Fonction d'envoi */
int my_service_send_json(const char *data, uint16_t len) 
{
    // Sécurité : On vérifie qu'on ne dépasse pas la taille du cache
    if (len > sizeof(json_payload_cache)) {
        LOG_ERR("Erreur: Donnee trop grande pour le cache BLE (%d > %d)", len, sizeof(json_payload_cache));
        return -1;
    }

    /* * CORRECTION 1 : Nettoyage du cache INTERNE du service
     * Même si le main est propre, si ce cache est sale, une "lecture" (Read) donnera des déchets.
     */
    memset(json_payload_cache, 0, sizeof(json_payload_cache));

    /* Copie de la donnée propre dans le cache */
    memcpy(json_payload_cache, data, len);

    /* * CORRECTION 2 : L'envoi de la Notification
     * On utilise 'len' (la longueur réelle du texte) et NON 'sizeof' (la taille totale du tableau).
     * On pointe sur attrs[2] (la Valeur).
     */
    return bt_gatt_notify(NULL, &my_service.attrs[2], json_payload_cache, len);
}