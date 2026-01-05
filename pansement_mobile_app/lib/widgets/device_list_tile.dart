import 'package:flutter/material.dart';
import '../models/device.dart';

class DeviceListTile extends StatelessWidget {
  final Device device;
  final VoidCallback onTap;

  const DeviceListTile({
    super.key,
    required this.device,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(device.status),
          child: Icon(
            Icons.medical_services,
            color: Colors.white,
          ),
        ),
        title: Text(
          device.serialNumber,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Modèle: ${device.model}'),
            if (device.patientName != null) Text('👤 ${device.patientName}'),
            if (device.batteryLevel != null) Text('🔋 ${device.batteryLevel}%'),
            if (device.firmwareVersion != null)
              Text('📱 Firmware: ${device.firmwareVersion}'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getStatusColor(device.status).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _getStatusColor(device.status),
                  width: 1,
                ),
              ),
              child: Text(
                _getStatusLabel(device.status),
                style: TextStyle(
                  color: _getStatusColor(device.status),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.grey;
      case 'maintenance':
        return Colors.orange;
      case 'retired':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return 'Actif';
      case 'inactive':
        return 'Inactif';
      case 'maintenance':
        return 'Maintenance';
      case 'retired':
        return 'Retiré';
      default:
        return status;
    }
  }
}
