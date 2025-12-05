# ============================================================================
# Makefile - Pansement Connecté
# Commandes pratiques pour gérer la base de données et les services
# ============================================================================

.PHONY: help start stop restart logs clean backup restore test psql

# Couleurs pour les messages
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Variables
COMPOSE_FILE := docker-compose.yml
DB_CONTAINER := pansement_postgres
DB_NAME := pansement_connecte
DB_USER := postgres
BACKUP_DIR := ./backups

## help: Affiche cette aide
help:
	@echo ""
	@echo "$(GREEN)╔═══════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║  PANSEMENT CONNECTÉ - Commandes Makefile                 ║$(NC)"
	@echo "$(GREEN)╚═══════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)🚀 Démarrage & Arrêt:$(NC)"
	@echo "  make start          - Démarrer tous les services Docker"
	@echo "  make stop           - Arrêter tous les services"
	@echo "  make restart        - Redémarrer tous les services"
	@echo "  make status         - Voir l'état des services"
	@echo ""
	@echo "$(YELLOW)📊 Base de Données:$(NC)"
	@echo "  make psql           - Se connecter à PostgreSQL (psql)"
	@echo "  make init-db        - Initialiser la base de données"
	@echo "  make test-db        - Tester la base de données"
	@echo "  make backup         - Créer un backup de la base"
	@echo "  make restore        - Restaurer un backup (BACKUP=fichier.sql)"
	@echo ""
	@echo "$(YELLOW)🧹 Maintenance:$(NC)"
	@echo "  make clean          - Nettoyer (ATTENTION: supprime les données)"
	@echo "  make clean-logs     - Nettoyer les fichiers logs"
	@echo "  make vacuum         - VACUUM ANALYZE (optimisation PostgreSQL)"
	@echo ""
	@echo "$(YELLOW)📋 Logs & Debug:$(NC)"
	@echo "  make logs           - Voir tous les logs en temps réel"
	@echo "  make logs-db        - Voir logs PostgreSQL uniquement"
	@echo "  make logs-redis     - Voir logs Redis uniquement"
	@echo "  make logs-influx    - Voir logs InfluxDB uniquement"
	@echo ""
	@echo "$(YELLOW)🔍 Informations:$(NC)"
	@echo "  make stats          - Statistiques de la base de données"
	@echo "  make size           - Taille de la base de données"
	@echo "  make tables         - Lister toutes les tables"
	@echo ""

## start: Démarrer tous les services
start:
	@echo "$(GREEN)🚀 Démarrage des services...$(NC)"
	docker-compose -f $(COMPOSE_FILE) up -d
	@echo "$(GREEN)✅ Services démarrés !$(NC)"
	@echo ""
	@echo "$(YELLOW)📝 Services disponibles:$(NC)"
	@echo "  - PostgreSQL:      http://localhost:5432"
	@echo "  - pgAdmin:         http://localhost:5050"
	@echo "  - InfluxDB:        http://localhost:8086"
	@echo "  - Redis:           http://localhost:6379"
	@echo "  - Redis Commander: http://localhost:8081"
	@echo "  - MinIO:           http://localhost:9001"
	@echo ""
	@make status

## stop: Arrêter tous les services
stop:
	@echo "$(YELLOW)⏸️  Arrêt des services...$(NC)"
	docker-compose -f $(COMPOSE_FILE) stop
	@echo "$(GREEN)✅ Services arrêtés$(NC)"

## restart: Redémarrer tous les services
restart:
	@echo "$(YELLOW)🔄 Redémarrage des services...$(NC)"
	docker-compose -f $(COMPOSE_FILE) restart
	@echo "$(GREEN)✅ Services redémarrés$(NC)"

## status: Voir l'état des services
status:
	@echo "$(YELLOW)📊 État des services:$(NC)"
	@docker-compose -f $(COMPOSE_FILE) ps

## logs: Voir tous les logs en temps réel
logs:
	@echo "$(YELLOW)📋 Logs en temps réel (Ctrl+C pour quitter):$(NC)"
	docker-compose -f $(COMPOSE_FILE) logs -f

## logs-db: Voir logs PostgreSQL
logs-db:
	@echo "$(YELLOW)📋 Logs PostgreSQL (Ctrl+C pour quitter):$(NC)"
	docker logs -f $(DB_CONTAINER)

## logs-redis: Voir logs Redis
logs-redis:
	@echo "$(YELLOW)📋 Logs Redis (Ctrl+C pour quitter):$(NC)"
	docker logs -f pansement_redis

## logs-influx: Voir logs InfluxDB
logs-influx:
	@echo "$(YELLOW)📋 Logs InfluxDB (Ctrl+C pour quitter):$(NC)"
	docker logs -f pansement_influxdb

## psql: Se connecter à PostgreSQL
psql:
	@echo "$(GREEN)🔌 Connexion à PostgreSQL...$(NC)"
	docker exec -it $(DB_CONTAINER) psql -U $(DB_USER) -d $(DB_NAME)

## init-db: Initialiser la base de données
init-db:
	@echo "$(GREEN)🗄️  Initialisation de la base de données...$(NC)"
	docker exec -i $(DB_CONTAINER) psql -U $(DB_USER) -d $(DB_NAME) < init_database.sql
	@echo "$(GREEN)✅ Base de données initialisée !$(NC)"

## test-db: Tester la base de données
test-db:
	@echo "$(GREEN)🧪 Tests de la base de données...$(NC)"
	docker exec -i $(DB_CONTAINER) psql -U $(DB_USER) -d $(DB_NAME) < test_database.sql

## backup: Créer un backup de la base
backup:
	@echo "$(GREEN)💾 Création du backup...$(NC)"
	@mkdir -p $(BACKUP_DIR)
	@docker exec $(DB_CONTAINER) pg_dump -U $(DB_USER) $(DB_NAME) > $(BACKUP_DIR)/backup_$$(date +%Y%m%d_%H%M%S).sql
	@echo "$(GREEN)✅ Backup créé dans $(BACKUP_DIR)$(NC)"
	@ls -lh $(BACKUP_DIR)/*.sql | tail -n 1

## restore: Restaurer un backup (usage: make restore BACKUP=backup_20241202_143000.sql)
restore:
	@if [ -z "$(BACKUP)" ]; then \
		echo "$(RED)❌ Erreur: Spécifiez le fichier backup avec BACKUP=fichier.sql$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)⚠️  ATTENTION: Cela va remplacer toutes les données actuelles !$(NC)"
	@echo "$(YELLOW)Appuyez sur Entrée pour continuer, Ctrl+C pour annuler...$(NC)"
	@read -r
	@echo "$(GREEN)📥 Restauration du backup $(BACKUP)...$(NC)"
	docker exec -i $(DB_CONTAINER) psql -U $(DB_USER) -d $(DB_NAME) < $(BACKUP_DIR)/$(BACKUP)
	@echo "$(GREEN)✅ Backup restauré !$(NC)"

## clean: Nettoyer complètement (ATTENTION: supprime les données!)
clean:
	@echo "$(RED)⚠️  ATTENTION: Cela va supprimer TOUTES les données !$(NC)"
	@echo "$(RED)Tapez 'yes' pour confirmer:$(NC)"
	@read -r confirm; \
	if [ "$$confirm" = "yes" ]; then \
		echo "$(YELLOW)🧹 Nettoyage en cours...$(NC)"; \
		docker-compose -f $(COMPOSE_FILE) down -v; \
		echo "$(GREEN)✅ Nettoyage terminé$(NC)"; \
	else \
		echo "$(YELLOW)❌ Annulé$(NC)"; \
	fi

## clean-logs: Nettoyer les fichiers logs
clean-logs:
	@echo "$(YELLOW)🧹 Nettoyage des logs...$(NC)"
	@rm -rf ./logs/*.log
	@echo "$(GREEN)✅ Logs nettoyés$(NC)"

## vacuum: VACUUM ANALYZE (optimisation PostgreSQL)
vacuum:
	@echo "$(GREEN)🔧 Optimisation PostgreSQL (VACUUM ANALYZE)...$(NC)"
	@docker exec -i $(DB_CONTAINER) psql -U $(DB_USER) -d $(DB_NAME) -c "VACUUM ANALYZE;"
	@echo "$(GREEN)✅ Optimisation terminée$(NC)"

## stats: Statistiques de la base
stats:
	@echo "$(GREEN)📊 Statistiques de la base de données:$(NC)"
	@echo ""
	@docker exec -i $(DB_CONTAINER) psql -U $(DB_USER) -d $(DB_NAME) -c "\
		SELECT \
			'Users' AS table_name, COUNT(*) AS count FROM users \
		UNION ALL \
		SELECT 'Patients', COUNT(*) FROM users WHERE role = 'patient' \
		UNION ALL \
		SELECT 'Médecins', COUNT(*) FROM users WHERE role = 'medecin' \
		UNION ALL \
		SELECT 'Devices', COUNT(*) FROM devices \
		UNION ALL \
		SELECT 'Measurements', COUNT(*) FROM measurements \
		UNION ALL \
		SELECT 'Alerts', COUNT(*) FROM alerts \
		UNION ALL \
		SELECT 'Alertes non résolues', COUNT(*) FROM alerts WHERE resolved_at IS NULL \
		UNION ALL \
		SELECT 'Photos', COUNT(*) FROM wound_photos \
		UNION ALL \
		SELECT 'Notes médicales', COUNT(*) FROM medical_notes;"

## size: Taille de la base
size:
	@echo "$(GREEN)💾 Taille de la base de données:$(NC)"
	@echo ""
	@docker exec -i $(DB_CONTAINER) psql -U $(DB_USER) -d $(DB_NAME) -c "\
		SELECT \
			pg_size_pretty(pg_database_size('$(DB_NAME)')) AS \"Taille totale\", \
			pg_size_pretty(pg_total_relation_size('measurements')) AS \"measurements\", \
			pg_size_pretty(pg_total_relation_size('alerts')) AS \"alerts\", \
			pg_size_pretty(pg_total_relation_size('users')) AS \"users\";"

## tables: Lister toutes les tables
tables:
	@echo "$(GREEN)📋 Tables de la base de données:$(NC)"
	@echo ""
	@docker exec -i $(DB_CONTAINER) psql -U $(DB_USER) -d $(DB_NAME) -c "\dt"

## shell: Ouvrir un shell bash dans le conteneur PostgreSQL
shell:
	@echo "$(GREEN)🐚 Shell PostgreSQL (tapez 'exit' pour quitter):$(NC)"
	docker exec -it $(DB_CONTAINER) /bin/bash

## install: Installation complète (première fois)
install:
	@echo "$(GREEN)╔═══════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║  INSTALLATION COMPLÈTE                                    ║$(NC)"
	@echo "$(GREEN)╚═══════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)1️⃣  Vérification des prérequis...$(NC)"
	@command -v docker >/dev/null 2>&1 || { echo "$(RED)❌ Docker n'est pas installé$(NC)"; exit 1; }
	@command -v docker-compose >/dev/null 2>&1 || { echo "$(RED)❌ Docker Compose n'est pas installé$(NC)"; exit 1; }
	@echo "$(GREEN)✅ Docker et Docker Compose sont installés$(NC)"
	@echo ""
	@echo "$(YELLOW)2️⃣  Création du fichier .env...$(NC)"
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "$(GREEN)✅ Fichier .env créé (pensez à le configurer !)$(NC)"; \
	else \
		echo "$(YELLOW)⚠️  Fichier .env existe déjà$(NC)"; \
	fi
	@echo ""
	@echo "$(YELLOW)3️⃣  Création du dossier backups...$(NC)"
	@mkdir -p $(BACKUP_DIR)
	@echo "$(GREEN)✅ Dossier backups créé$(NC)"
	@echo ""
	@echo "$(YELLOW)4️⃣  Démarrage des services Docker...$(NC)"
	@make start
	@echo ""
	@echo "$(YELLOW)5️⃣  Attente du démarrage de PostgreSQL (15s)...$(NC)"
	@sleep 15
	@echo ""
	@echo "$(YELLOW)6️⃣  Initialisation de la base de données...$(NC)"
	@make init-db
	@echo ""
	@echo "$(GREEN)╔═══════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║  ✅ INSTALLATION TERMINÉE !                               ║$(NC)"
	@echo "$(GREEN)╚═══════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)📝 Prochaines étapes:$(NC)"
	@echo "  1. Vérifier le fichier .env et adapter les mots de passe"
	@echo "  2. Tester la base: make test-db"
	@echo "  3. Se connecter: make psql"
	@echo ""
	@echo "$(YELLOW)🌐 Interfaces web disponibles:$(NC)"
	@echo "  - pgAdmin:         http://localhost:5050"
	@echo "  - InfluxDB:        http://localhost:8086"
	@echo "  - Redis Commander: http://localhost:8081"
	@echo "  - MinIO:           http://localhost:9001"
	@echo ""

## dev: Lancer en mode développement avec logs
dev:
	@echo "$(GREEN)🔧 Mode développement (logs en temps réel)$(NC)"
	docker-compose -f $(COMPOSE_FILE) up

# Définir 'help' comme commande par défaut
.DEFAULT_GOAL := help