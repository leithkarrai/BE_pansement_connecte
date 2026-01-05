import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/alert.dart';

class AlertListTile extends StatelessWidget {
  final Alert alert;
  final VoidCallback? onTap;
  final VoidCallback? onAcknowledge;

  const AlertListTile({
    super.key,
    required this.alert,
    this.onTap,
    this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      elevation: alert.isAcknowledged ? 1 : 3,
      color: alert.isAcknowledged
          ? Colors.grey[100]
          : _getSeverityColor(alert.severity).withValues(alpha: 0.1),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getSeverityColor(alert.severity),
          child: Icon(
            _getAlertIcon(alert.alertType),
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          alert.title,
          style: TextStyle(
            fontWeight:
                alert.isAcknowledged ? FontWeight.normal : FontWeight.bold,
            decoration:
                alert.isAcknowledged ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(alert.message),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time, size: 12, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(alert.triggeredAt),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if (alert.currentValue != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    'Valeur: ${alert.currentValue!.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getSeverityColor(alert.severity),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _getSeverityLabel(alert.severity),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (!alert.isAcknowledged && onAcknowledge != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.check_circle_outline),
                onPressed: onAcknowledge,
                tooltip: 'Acquitter',
                color: Colors.green,
              ),
            ],
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      case 'info':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getSeverityLabel(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return 'CRITIQUE';
      case 'warning':
        return 'AVERTISSEMENT';
      case 'info':
        return 'INFO';
      default:
        return severity.toUpperCase();
    }
  }

  IconData _getAlertIcon(String alertType) {
    switch (alertType.toLowerCase()) {
      case 'temperature':
        return Icons.thermostat;
      case 'impedance':
      case 'orp':
        return Icons.water_drop;
      case 'infection':
        return Icons.warning;
      case 'battery':
        return Icons.battery_alert;
      case 'device_error':
        return Icons.error;
      default:
        return Icons.notifications;
    }
  }
}
