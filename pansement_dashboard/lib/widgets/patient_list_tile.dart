import 'package:flutter/material.dart';
import '../models/user.dart';

class PatientListTile extends StatelessWidget {
  final User patient;
  final VoidCallback onTap;

  const PatientListTile({
    super.key,
    required this.patient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).primaryColor,
          child: Text(
            patient.firstName[0].toUpperCase(),
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(
          patient.fullName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(patient.email),
            if (patient.phone != null) Text('📞 ${patient.phone}'),
            const SizedBox(height: 4),
            // Badge du rôle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getRoleColor(patient.role),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _getRoleLabel(patient.role),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: patient.isActive ? Colors.green[100] : Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                patient.isActive ? 'Actif' : 'Inactif',
                style: TextStyle(
                  color:
                      patient.isActive ? Colors.green[800] : Colors.grey[700],
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

  // Helper pour obtenir la couleur du rôle
  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Colors.red;
      case 'medecin':
        return Colors.green;
      case 'patient':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  // Helper pour obtenir le label du rôle
  String _getRoleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return '👑 Admin';
      case 'medecin':
        return '🩺 Médecin';
      case 'patient':
        return '👤 Patient';
      default:
        return role;
    }
  }
}
