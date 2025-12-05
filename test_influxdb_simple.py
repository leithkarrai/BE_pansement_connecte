"""
Script simple pour tester InfluxDB
Exécutez : python test_influxdb_simple.py
"""
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS
from datetime import datetime

# Configuration
url = "http://localhost:8086"
token = "my-super-secret-auth-token-change-me"
org = "pansement-connecte"
bucket = "measurements"

print("🔌 Connexion à InfluxDB...")
client = InfluxDBClient(url=url, token=token, org=org)
write_api = client.write_api(write_options=SYNCHRONOUS)

print("📝 Écriture d'une mesure de test...")
point = Point("temperature") \
    .tag("device_id", "PANS-00001234") \
    .tag("patient_id", "1df48cb6-fc92-4221-a4f3-49f3baf6845a") \
    .field("value", 36.8) \
    .field("quality_score", 95.0) \
    .time(datetime.utcnow())

write_api.write(bucket=bucket, org=org, record=point)
print("✅ Mesure écrite avec succès !")

# Écrire plusieurs mesures pour voir un graphique
print("📊 Écriture de 5 mesures supplémentaires...")
for i in range(5):
    value = 36.5 + (i * 0.1)  # 36.5, 36.6, 36.7, 36.8, 36.9
    point = Point("temperature") \
        .tag("device_id", "PANS-00001234") \
        .tag("patient_id", "1df48cb6-fc92-4221-a4f3-49f3baf6845a") \
        .field("value", value) \
        .field("quality_score", 95.0) \
        .time(datetime.utcnow())
    
    write_api.write(bucket=bucket, org=org, record=point)
    print(f"   ✓ Mesure {i+1}: {value}°C")

print("\n✅ Toutes les mesures ont été écrites !")
print("\n📊 Pour visualiser :")
print("   1. Allez sur http://localhost:8086")
print("   2. Cliquez sur 'Data Explorer'")
print("   3. Sélectionnez bucket: measurements")
print("   4. Sélectionnez measurement: temperature")
print("   5. Cliquez sur 'Submit'")

write_api.close()
client.close()

