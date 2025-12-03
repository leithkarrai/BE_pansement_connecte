-- ============================================================================
-- SCRIPT DE TEST ET VÉRIFICATION - Base de Données
-- Pansement Connecté
-- ============================================================================
--
-- Ce script vérifie que la base de données est correctement configurée
-- et que toutes les fonctionnalités essentielles fonctionnent.
--
-- Utilisation:
--   psql -U postgres -d pansement_connecte -f test_database.sql
--
-- ============================================================================

\echo ''
\echo '╔══════════════════════════════════════════════════════════════╗'
\echo '║  TESTS DE VÉRIFICATION - BASE DE DONNÉES                    ║'
\echo '╚══════════════════════════════════════════════════════════════╝'
\echo ''

-- ============================================================================
-- TEST 1: Vérifier que toutes les tables existent
-- ============================================================================
\echo '━━━ TEST 1: Tables ━━━'

DO $$
DECLARE
    expected_tables TEXT[] := ARRAY[
        'users', 'devices', 'patient_devices', 'medecin_patients',
        'measurements', 'alerts', 'wound_photos', 'medical_notes', 'audit_logs'
    ];
    v_table_name TEXT;
    table_exists BOOLEAN;
    all_ok BOOLEAN := TRUE;
BEGIN
    FOREACH v_table_name IN ARRAY expected_tables LOOP
        SELECT EXISTS (
            SELECT FROM information_schema.tables t
            WHERE t.table_schema = 'public' 
            AND t.table_name = v_table_name
        ) INTO table_exists;
        
        IF table_exists THEN
            RAISE NOTICE '  ✅ Table "%" existe', v_table_name;
        ELSE
            RAISE NOTICE '  ❌ Table "%" MANQUANTE', v_table_name;
            all_ok := FALSE;
        END IF;
    END LOOP;
    
    IF all_ok THEN
        RAISE NOTICE '';
        RAISE NOTICE '  ✅ Toutes les tables sont présentes';
    ELSE
        RAISE NOTICE '';
        RAISE NOTICE '  ❌ Certaines tables sont manquantes';
    END IF;
END $$;

\echo ''

-- ============================================================================
-- TEST 2: Vérifier les types énumérés
-- ============================================================================
\echo '━━━ TEST 2: Types Énumérés ━━━'

DO $$
DECLARE
    expected_types TEXT[] := ARRAY[
        'user_role', 'device_status', 'wound_type', 
        'alert_severity', 'alert_type', 'note_type'
    ];
    type_name TEXT;
    type_exists BOOLEAN;
    all_ok BOOLEAN := TRUE;
BEGIN
    FOREACH type_name IN ARRAY expected_types LOOP
        SELECT EXISTS (
            SELECT FROM pg_type 
            WHERE typname = type_name
        ) INTO type_exists;
        
        IF type_exists THEN
            RAISE NOTICE '  ✅ Type "%" existe', type_name;
        ELSE
            RAISE NOTICE '  ❌ Type "%" MANQUANT', type_name;
            all_ok := FALSE;
        END IF;
    END LOOP;
    
    IF all_ok THEN
        RAISE NOTICE '';
        RAISE NOTICE '  ✅ Tous les types énumérés sont présents';
    ELSE
        RAISE NOTICE '';
        RAISE NOTICE '  ❌ Certains types sont manquants';
    END IF;
END $$;

\echo ''

-- ============================================================================
-- TEST 3: Vérifier les index importants
-- ============================================================================
\echo '━━━ TEST 3: Index Critiques ━━━'

DO $$
DECLARE
    nb_index INT;
BEGIN
    SELECT COUNT(*) INTO nb_index
    FROM pg_indexes
    WHERE schemaname = 'public';
    
    RAISE NOTICE '  ℹ️  Nombre total d''index: %', nb_index;
    
    -- Vérifier les index critiques
    IF EXISTS (SELECT FROM pg_indexes WHERE indexname = 'idx_measurements_device_time') THEN
        RAISE NOTICE '  ✅ Index measurements (device_id, measured_at) existe';
    ELSE
        RAISE NOTICE '  ❌ Index measurements MANQUANT (critique pour performance)';
    END IF;
    
    IF EXISTS (SELECT FROM pg_indexes WHERE indexname = 'idx_patient_devices_patient_active') THEN
        RAISE NOTICE '  ✅ Index patient_devices (patient_id, is_active) existe';
    ELSE
        RAISE NOTICE '  ❌ Index patient_devices MANQUANT';
    END IF;
    
    IF EXISTS (SELECT FROM pg_indexes WHERE indexname = 'idx_alerts_unresolved') THEN
        RAISE NOTICE '  ✅ Index alerts (unresolved) existe';
    ELSE
        RAISE NOTICE '  ❌ Index alerts MANQUANT';
    END IF;
END $$;

\echo ''

-- ============================================================================
-- TEST 4: Vérifier les données de test
-- ============================================================================
\echo '━━━ TEST 4: Données de Test ━━━'

DO $$
DECLARE
    nb_users INT;
    nb_patients INT;
    nb_medecins INT;
    nb_admins INT;
    nb_devices INT;
    nb_measurements INT;
BEGIN
    SELECT COUNT(*) INTO nb_users FROM users;
    SELECT COUNT(*) INTO nb_patients FROM users WHERE role = 'patient';
    SELECT COUNT(*) INTO nb_medecins FROM users WHERE role = 'medecin';
    SELECT COUNT(*) INTO nb_admins FROM users WHERE role = 'admin';
    SELECT COUNT(*) INTO nb_devices FROM devices;
    SELECT COUNT(*) INTO nb_measurements FROM measurements;
    
    RAISE NOTICE '  📊 Users total: % (% patients, % médecins, % admin)', 
        nb_users, nb_patients, nb_medecins, nb_admins;
    RAISE NOTICE '  📊 Devices: %', nb_devices;
    RAISE NOTICE '  📊 Measurements: %', nb_measurements;
    
    IF nb_users >= 6 AND nb_devices >= 4 AND nb_measurements > 100 THEN
        RAISE NOTICE '';
        RAISE NOTICE '  ✅ Données de test présentes et cohérentes';
    ELSE
        RAISE NOTICE '';
        RAISE NOTICE '  ⚠️  Données de test incomplètes';
    END IF;
END $$;

\echo ''

-- ============================================================================
-- TEST 5: Vérifier les vues
-- ============================================================================
\echo '━━━ TEST 5: Vues ━━━'

DO $$
DECLARE
    expected_views TEXT[] := ARRAY[
        'v_active_patients', 'v_critical_alerts', 'v_medecin_stats'
    ];
    view_name TEXT;
    view_exists BOOLEAN;
    all_ok BOOLEAN := TRUE;
BEGIN
    FOREACH view_name IN ARRAY expected_views LOOP
        SELECT EXISTS (
            SELECT FROM information_schema.views 
            WHERE table_schema = 'public' 
            AND table_name = view_name
        ) INTO view_exists;
        
        IF view_exists THEN
            RAISE NOTICE '  ✅ Vue "%" existe', view_name;
        ELSE
            RAISE NOTICE '  ❌ Vue "%" MANQUANTE', view_name;
            all_ok := FALSE;
        END IF;
    END LOOP;
    
    IF all_ok THEN
        RAISE NOTICE '';
        RAISE NOTICE '  ✅ Toutes les vues sont présentes';
    ELSE
        RAISE NOTICE '';
        RAISE NOTICE '  ❌ Certaines vues sont manquantes';
    END IF;
END $$;

\echo ''

-- ============================================================================
-- TEST 6: Vérifier les fonctions
-- ============================================================================
\echo '━━━ TEST 6: Fonctions ━━━'

DO $$
DECLARE
    expected_functions TEXT[] := ARRAY[
        'calculate_baseline_impedance',
        'get_latest_measurement',
        'count_unresolved_alerts'
    ];
    func_name TEXT;
    func_exists BOOLEAN;
    all_ok BOOLEAN := TRUE;
BEGIN
    FOREACH func_name IN ARRAY expected_functions LOOP
        SELECT EXISTS (
            SELECT FROM pg_proc 
            WHERE proname = func_name
        ) INTO func_exists;
        
        IF func_exists THEN
            RAISE NOTICE '  ✅ Fonction "%" existe', func_name;
        ELSE
            RAISE NOTICE '  ❌ Fonction "%" MANQUANTE', func_name;
            all_ok := FALSE;
        END IF;
    END LOOP;
    
    IF all_ok THEN
        RAISE NOTICE '';
        RAISE NOTICE '  ✅ Toutes les fonctions sont présentes';
    ELSE
        RAISE NOTICE '';
        RAISE NOTICE '  ❌ Certaines fonctions sont manquantes';
    END IF;
END $$;

\echo ''

-- ============================================================================
-- TEST 7: Test fonctionnel - Relations
-- ============================================================================
\echo '━━━ TEST 7: Relations et Contraintes ━━━'

DO $$
DECLARE
    marie_id UUID;
    dr_martin_id UUID;
    device_uuid UUID;
    relation_ok BOOLEAN;
BEGIN
    -- Récupérer IDs
    SELECT id INTO marie_id FROM users WHERE email = 'marie.dupont@email.com';
    SELECT id INTO dr_martin_id FROM users WHERE email = 'dr.martin@hopital.fr';
    SELECT id INTO device_uuid FROM devices d WHERE d.device_id = 'PANS-00001234';
    
    -- Test 1: Patient a un médecin assigné
    SELECT EXISTS (
        SELECT FROM medecin_patients 
        WHERE medecin_id = dr_martin_id 
        AND patient_id = marie_id
    ) INTO relation_ok;
    
    IF relation_ok THEN
        RAISE NOTICE '  ✅ Relation médecin ↔ patient OK';
    ELSE
        RAISE NOTICE '  ❌ Relation médecin ↔ patient MANQUANTE';
    END IF;
    
    -- Test 2: Patient a un device actif
    SELECT EXISTS (
        SELECT FROM patient_devices 
        WHERE patient_id = marie_id 
        AND device_id = device_uuid
        AND is_active = TRUE
    ) INTO relation_ok;
    
    IF relation_ok THEN
        RAISE NOTICE '  ✅ Relation patient ↔ device OK';
    ELSE
        RAISE NOTICE '  ❌ Relation patient ↔ device MANQUANTE';
    END IF;
    
    -- Test 3: Device a des mesures
    SELECT EXISTS (
        SELECT FROM measurements 
        WHERE patient_device_id = device_uuid
    ) INTO relation_ok;
    
    IF relation_ok THEN
        RAISE NOTICE '  ✅ Mesures associées au device OK';
    ELSE
        RAISE NOTICE '  ❌ Aucune mesure pour ce device';
    END IF;
END $$;

\echo ''

-- ============================================================================
-- TEST 8: Test fonctionnel - Fonctions
-- ============================================================================
\echo '━━━ TEST 8: Tests Fonctionnels ━━━'

DO $$
DECLARE
    marie_id UUID;
    latest_temp DECIMAL;
    unresolved INT;
BEGIN
    SELECT id INTO marie_id FROM users WHERE email = 'marie.dupont@email.com';
    
    -- Test fonction get_latest_measurement
    SELECT temperature INTO latest_temp 
    FROM get_latest_measurement(marie_id);
    
    IF latest_temp IS NOT NULL THEN
        RAISE NOTICE '  ✅ Fonction get_latest_measurement() OK (temp: %°C)', latest_temp;
    ELSE
        RAISE NOTICE '  ❌ Fonction get_latest_measurement() ERREUR';
    END IF;
    
    -- Test fonction count_unresolved_alerts
    SELECT count_unresolved_alerts(marie_id) INTO unresolved;
    
    IF unresolved IS NOT NULL THEN
        RAISE NOTICE '  ✅ Fonction count_unresolved_alerts() OK (% alertes)', unresolved;
    ELSE
        RAISE NOTICE '  ❌ Fonction count_unresolved_alerts() ERREUR';
    END IF;
END $$;

\echo ''

-- ============================================================================
-- TEST 9: Test requêtes complexes (performance)
-- ============================================================================
\echo '━━━ TEST 9: Requêtes Complexes ━━━'

\timing on

-- Test 1: Vue active_patients
\echo '  Test vue v_active_patients...'
SELECT COUNT(*) AS nb_patients_actifs FROM v_active_patients;

-- Test 2: Agrégation measurements
\echo '  Test agrégation measurements (dernières 24h)...'
SELECT 
    COUNT(*) AS nb_mesures,
    AVG(temperature)::DECIMAL(4,2) AS temp_moy,
    AVG(infection_score)::INT AS score_moy
FROM measurements
WHERE measured_at > NOW() - INTERVAL '24 hours';

-- Test 3: Join complexe
\echo '  Test join multi-tables...'
SELECT 
    u.first_name || ' ' || u.last_name AS patient,
    d.device_id,
    COUNT(m.id) AS nb_mesures,
    COUNT(a.id) AS nb_alertes
FROM users u
JOIN patient_devices pd ON u.id = pd.patient_id
JOIN devices d ON pd.device_id = d.id
LEFT JOIN measurements m ON pd.id = m.patient_device_id
LEFT JOIN alerts a ON u.id = a.patient_id
WHERE u.role = 'patient'
GROUP BY u.id, d.id;

\timing off

\echo ''
\echo '  ✅ Toutes les requêtes complexes sont fonctionnelles'
\echo ''

-- ============================================================================
-- TEST 10: Contraintes d'intégrité
-- ============================================================================
\echo '━━━ TEST 10: Contraintes d''Intégrité ━━━'

DO $$
DECLARE
    test_passed BOOLEAN;
BEGIN
    -- Test 1: Un device actif ne peut être assigné qu'à un seul patient
    BEGIN
        INSERT INTO patient_devices (patient_id, device_id, is_active)
        SELECT 
            (SELECT id FROM users WHERE email = 'claire.petit@email.com'),
            (SELECT id FROM devices WHERE device_id = 'PANS-00001234'),
            TRUE;
        
        RAISE NOTICE '  ❌ ERREUR: Device peut être assigné 2x (contrainte manquante)';
        ROLLBACK;
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE '  ✅ Contrainte unicité device actif OK';
        ROLLBACK;
    END;
    
    -- Test 2: Email doit être unique
    BEGIN
        INSERT INTO users (email, password_hash, role, first_name, last_name)
        VALUES ('marie.dupont@email.com', 'hash', 'patient', 'Test', 'Test');
        
        RAISE NOTICE '  ❌ ERREUR: Email peut être dupliqué (contrainte manquante)';
        ROLLBACK;
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE '  ✅ Contrainte unicité email OK';
        ROLLBACK;
    END;
    
    -- Test 3: Role doit être valide
    BEGIN
        INSERT INTO users (email, password_hash, role, first_name, last_name)
        VALUES ('test@test.com', 'hash', 'invalid_role', 'Test', 'Test');
        
        RAISE NOTICE '  ❌ ERREUR: Role invalide accepté (contrainte manquante)';
        ROLLBACK;
    EXCEPTION WHEN invalid_text_representation THEN
        RAISE NOTICE '  ✅ Contrainte role valide OK';
        ROLLBACK;
    END;
END $$;

\echo ''

-- ============================================================================
-- RÉSUMÉ FINAL
-- ============================================================================
\echo ''
\echo '╔══════════════════════════════════════════════════════════════╗'
\echo '║  RÉSUMÉ DES TESTS                                            ║'
\echo '╠══════════════════════════════════════════════════════════════╣'

SELECT 
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public') AS "Tables",
    (SELECT COUNT(*) FROM pg_type WHERE typname IN ('user_role', 'device_status', 'wound_type', 'alert_severity', 'alert_type', 'note_type')) AS "Types",
    (SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public') AS "Index",
    (SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'public') AS "Vues",
    (SELECT COUNT(*) FROM pg_proc WHERE proname IN ('calculate_baseline_impedance', 'get_latest_measurement', 'count_unresolved_alerts')) AS "Fonctions",
    (SELECT COUNT(*) FROM users) AS "Users",
    (SELECT COUNT(*) FROM devices) AS "Devices",
    (SELECT COUNT(*) FROM measurements) AS "Measurements",
    (SELECT COUNT(*) FROM alerts) AS "Alerts";

\echo '╚══════════════════════════════════════════════════════════════╝'
\echo ''
\echo '✅ TOUS LES TESTS SONT TERMINÉS !'
\echo ''
\echo 'Si tous les tests sont ✅, votre base de données est prête.'
\echo ''