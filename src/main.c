// #include <zephyr/kernel.h>
// #include <zephyr/drivers/adc.h>
// #include <zephyr/logging/log.h>
// #include <zephyr/bluetooth/bluetooth.h>
// #include <zephyr/bluetooth/uuid.h>
// #include <zephyr/bluetooth/gatt.h>
// #include <bluetooth/scan.h>
// #include <zephyr/data/json.h> // <--- L'INCLUDE OFFICIEL
// #include "my_service.h"
// #include "my_central.h"

// LOG_MODULE_REGISTER(main_app);

// /* ================= CONFIGURATION MANUELLE ADC ================= */

// #define ADC_NODE DT_NODELABEL(adc)
// static const struct device *adc_dev = DEVICE_DT_GET(ADC_NODE);
// int16_t sample_buffer[1];
// struct adc_sequence sequence = {
//     .buffer = sample_buffer,
//     .buffer_size = sizeof(sample_buffer),
//     .resolution = 12,
//     .oversampling = 0,
//     .calibrate = 0,
// };
// static struct adc_channel_cfg channel_0_cfg = {
//     .gain = ADC_GAIN_1_6, .reference = ADC_REF_INTERNAL, .acquisition_time = ADC_ACQ_TIME_DEFAULT, .channel_id = 0,
// };

// /* ================= CONFIGURATION BLE (Advertising) ================= */
// static const struct bt_data ad[] = {
//     BT_DATA_BYTES(BT_DATA_FLAGS, (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
//     BT_DATA_BYTES(BT_DATA_UUID128_ALL, MY_SERVICE_UUID),
// };
// static const struct bt_data sd[] = {
//     BT_DATA(BT_DATA_NAME_COMPLETE, CONFIG_BT_DEVICE_NAME, sizeof(CONFIG_BT_DEVICE_NAME) - 1),
// };

// static void bt_ready_cb(int err) {
//     if (err) { LOG_ERR("Bluetooth init failed (err %d)", err); return; }

//     // 1. Périphérique (Advertise)
//     err = bt_le_adv_start(BT_LE_ADV_CONN, ad, ARRAY_SIZE(ad), sd, ARRAY_SIZE(sd));
//     if (err) { LOG_ERR("Advertising failed (err %d)", err); }
//     else { LOG_INF("Advertising started!"); }

//     // 2. Central (Scan)
//     scan_init();
//     err = bt_scan_start(BT_SCAN_TYPE_SCAN_PASSIVE);
//     if (err) { LOG_ERR("Impossible de scanner (err %d)", err); }
//     else { LOG_INF("Scanner démarré !"); }
// }
// /* === 1. Définition de la structure de données === */
// struct my_data_t {
//     int adc_val;
//     const char *status; // Exemple pour montrer qu'on peut ajouter du texte
// };

// /* === 2. Mapping pour la librairie JSON Zephyr === */
// static const struct json_obj_descr my_data_descr[] = {
//     // On associe la variable C 'adc_val' à la clé JSON "adc"
//     JSON_OBJ_DESCR_PRIM(struct my_data_t, adc_val, JSON_TOK_NUMBER),
//     // On associe la variable C 'status' à la clé JSON "msg"
//     JSON_OBJ_DESCR_PRIM(struct my_data_t, status, JSON_TOK_STRING),
// };

// /* ================= MAIN LOOP ================= */
// int main(void) {
//     int err;
//     // Buffer pour stocker la chaîne JSON finale
//     char json_buffer[100];
//     struct my_data_t data_to_send;

//     /* Init ADC */
//     if (!device_is_ready(adc_dev)) return 0;
//     adc_channel_setup(adc_dev, &channel_0_cfg);
//     sequence.channels = BIT(0);

//     /* Init BLE (qui lancera l'adv et le scan dans le callback) */
//     err = bt_enable(bt_ready_cb);
//     if (err) return 0;

//     /* Boucle */
//     while (1) {
//         err = adc_read(adc_dev, &sequence);
//         if (err == 0) {
//             int32_t raw_value = sample_buffer[0];
//             // 1. Remplissage de la structure C
//             data_to_send.adc_val = raw_value;
//             data_to_send.status = "OK"; // Juste pour l'exemple

//             // 2. Encodage : Struct C -> Chaîne JSON
//             // json_obj_encode_buf(descr, count, data, buffer, size)
//             int ret = json_obj_encode_buf(my_data_descr,
//                                           ARRAY_SIZE(my_data_descr),
//                                           &data_to_send,
//                                           json_buffer,
//                                           sizeof(json_buffer));
//             if (ret == 0) {
//                 LOG_INF("JSON généré : %s", json_buffer);
//                 // 3. Envoi via BLE (on envoie strlen(json_buffer))
//                 my_service_send_json(json_buffer, strlen(json_buffer));

//             //my_service_send_adc_value((uint16_t)raw_value);
//         } else {
//                 LOG_ERR("Erreur encodage JSON : %d", ret);
//             }

//         }
//     k_sleep(K_SECONDS(1));
//     }
//     return 0;
// }

#include <zephyr/kernel.h>
#include <zephyr/drivers/adc.h>
#include <zephyr/logging/log.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/conn.h> // Utile pour les connexions
#include <bluetooth/scan.h>
#include <zephyr/data/json.h> // <--- L'INCLUDE OFFICIEL

#include "my_service.h"
#include "my_central.h"

LOG_MODULE_REGISTER(main_app);

/* ================= CONFIGURATION MANUELLE ADC ================= */

#define ADC_NODE DT_NODELABEL(adc)
static const struct device *adc_dev = DEVICE_DT_GET(ADC_NODE);
int16_t sample_buffer[1];
struct adc_sequence sequence = {
    .buffer = sample_buffer,
    .buffer_size = sizeof(sample_buffer),
    .resolution = 12,
    .oversampling = 0,
    .calibrate = 0,
};
static struct adc_channel_cfg channel_0_cfg = {
    .gain = ADC_GAIN_1_6,
    .reference = ADC_REF_INTERNAL,
    .acquisition_time = ADC_ACQ_TIME_DEFAULT,
    .channel_id = 0,
};

/* ================= GESTION DU MTU (Nouveau code ajouté ici) ================= */

/* 1. Callback appelé une fois que l'échange MTU est terminé */
static void exchange_func(struct bt_conn *conn, uint8_t att_err,
                          struct bt_gatt_exchange_params *params)
{
    if (!att_err)
    {
        LOG_INF("MTU mis a jour ! Nouvelle taille : %d", bt_gatt_get_mtu(conn));
    }
    else
    {
        LOG_ERR("Echec negociation MTU : %d", att_err);
    }
}

static struct bt_gatt_exchange_params exchange_params = {
    .func = exchange_func,
};

/* 2. Callbacks de connexion / déconnexion */
static void connected(struct bt_conn *conn, uint8_t err)
{
    if (err)
    {
        LOG_ERR("Erreur de connexion (err %u)", err);
        return;
    }
    LOG_INF("Connecte !");

    // Lancement de la négociation MTU pour supporter les gros JSON
    int ret = bt_gatt_exchange_mtu(conn, &exchange_params);
    if (ret)
    {
        LOG_ERR("Impossible de lancer l'echange MTU (err %d)", ret);
    }
}

static void disconnected(struct bt_conn *conn, uint8_t reason)
{
    LOG_INF("Deconnecte (reason 0x%02x)", reason);
}

/* Enregistrement des callbacks de connexion */
BT_CONN_CB_DEFINE(conn_callbacks) = {
    .connected = connected,
    .disconnected = disconnected,
};

/* ================= CONFIGURATION BLE (Advertising) ================= */
static const struct bt_data ad[] = {
    BT_DATA_BYTES(BT_DATA_FLAGS, (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
    BT_DATA_BYTES(BT_DATA_UUID128_ALL, MY_SERVICE_UUID),
};
static const struct bt_data sd[] = {
    BT_DATA(BT_DATA_NAME_COMPLETE, CONFIG_BT_DEVICE_NAME, sizeof(CONFIG_BT_DEVICE_NAME) - 1),
};

static void bt_ready_cb(int err)
{
    if (err)
    {
        LOG_ERR("Bluetooth init failed (err %d)", err);
        return;
    }

    // 1. Périphérique (Advertise)
    err = bt_le_adv_start(BT_LE_ADV_CONN, ad, ARRAY_SIZE(ad), sd, ARRAY_SIZE(sd));
    if (err)
    {
        LOG_ERR("Advertising failed (err %d)", err);
    }
    else
    {
        LOG_INF("Advertising started!");
    }

    // 2. Central (Scan)
    scan_init();
    err = bt_scan_start(BT_SCAN_TYPE_SCAN_PASSIVE);
    if (err)
    {
        LOG_ERR("Impossible de scanner (err %d)", err);
    }
    else
    {
        LOG_INF("Scanner démarré !");
    }
}

/* === 1. Définition de la structure de données === */
struct my_data_t
{
    int adc_val;
    const char *status;
};

/* === 2. Mapping pour la librairie JSON Zephyr === */
static const struct json_obj_descr my_data_descr[] = {
    JSON_OBJ_DESCR_PRIM(struct my_data_t, adc_val, JSON_TOK_NUMBER),
    JSON_OBJ_DESCR_PRIM(struct my_data_t, status, JSON_TOK_STRING),
};

/* ================= MAIN LOOP ================= */
int main(void)
{
    int err;
    char json_buffer[128]; // J'ai augmenté un peu la taille par sécurité (100 -> 128)
    struct my_data_t data_to_send;

    /* Init ADC */
    if (!device_is_ready(adc_dev))
        return 0;
    adc_channel_setup(adc_dev, &channel_0_cfg);
    sequence.channels = BIT(0);

    /* Init BLE */
    err = bt_enable(bt_ready_cb);
    if (err)
        return 0;

    /* Boucle */
    while (1)
    {
        err = adc_read(adc_dev, &sequence);
        if (err == 0)
        {
            int32_t raw_value = sample_buffer[0];

            // 1. Remplissage
            data_to_send.adc_val = raw_value;
            data_to_send.status = "OK";

            memset(json_buffer, 0, sizeof(json_buffer));

            // 2. Encodage JSON
            int ret = json_obj_encode_buf(my_data_descr,
                                          ARRAY_SIZE(my_data_descr),
                                          &data_to_send,
                                          json_buffer,
                                          sizeof(json_buffer));
            if (ret == 0)
            {
                LOG_INF("JSON genere : %s", json_buffer);
                // 3. Envoi via BLE
                my_service_send_json(json_buffer, strlen(json_buffer));
            }
            else
            {
                LOG_ERR("Erreur encodage JSON : %d", ret);
            }
        }

        // Pause d'une seconde (en dehors du IF pour éviter le blocage)
        k_sleep(K_SECONDS(1));
    }
    return 0;
}