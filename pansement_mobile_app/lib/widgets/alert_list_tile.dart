import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/alert.dart';

class AlertListTile extends StatelessWidget {
  final Alert alert;
  final VoidCallback? onTap;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onDelete;
  /// Rôle de l'utilisateur connecté (medecin, admin, patient) pour afficher "lu" selon le rôle.
  final String? userRole;

  const AlertListTile({
    super.key,
    required this.alert,
    this.onTap,
    this.onAcknowledge,
    this.onDelete,
    this.userRole,
  });

  /// État "acquitté" pour le rôle courant (backend ou provider). Pilote tout le style.
  bool get isAcknowledged => alert.isAcknowledgedForRole(userRole);

  @override
  Widget build(BuildContext context) {
    // Style du texte selon isAcknowledged : barré + gris quand lu, sinon normal
    final TextStyle titleStyle = TextStyle(
      fontSize: 15,
      fontWeight: isAcknowledged ? FontWeight.normal : FontWeight.bold,
      decoration: isAcknowledged ? TextDecoration.lineThrough : TextDecoration.none,
      color: isAcknowledged ? Colors.grey[600] : Colors.black87,
      decorationColor: Colors.grey,
      decorationThickness: 1.5,
    );
    final TextStyle messageStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.normal,
      decoration: isAcknowledged ? TextDecoration.lineThrough : TextDecoration.none,
      color: isAcknowledged ? Colors.grey[600] : Colors.black87,
      decorationColor: Colors.grey,
      decorationThickness: 1.5,
    );
    final mutedColor = Colors.grey[600]!;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      elevation: isAcknowledged ? 1 : 3,
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: _getSeverityColor(alert.severity),
                radius: 20,
                child: Icon(
                  _getAlertIcon(alert.alertType),
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      alert.title,
                      style: titleStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.message,
                      style: messageStyle,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 12, color: mutedColor),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            DateFormat('dd/MM/yyyy HH:mm').format(alert.triggeredAt),
                            style: TextStyle(fontSize: 12, color: mutedColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (alert.currentValue != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Valeur: ${alert.currentValue!.toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 12, color: mutedColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isAcknowledged)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[700]!, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, size: 14, color: Colors.green[700]),
                          const SizedBox(width: 4),
                          Text(
                            'Lu',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isAcknowledged) const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                  if (!isAcknowledged && onAcknowledge != null) ...[
                    const SizedBox(height: 4),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: const Icon(Icons.check_circle_outline, size: 22),
                      onPressed: onAcknowledge,
                      tooltip: 'Acquitter',
                      color: Colors.green,
                    ),
                  ],
                  if (onDelete != null) ...[
                    const SizedBox(height: 2),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: const Icon(Icons.delete_outline, size: 22),
                      onPressed: onDelete,
                      tooltip: 'Supprimer',
                      color: Colors.red[700],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
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
