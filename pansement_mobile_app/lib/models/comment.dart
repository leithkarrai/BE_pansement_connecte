// ============================================
// Modèle Comment - Flutter
// ============================================
// Fichier : lib/models/comment.dart

class Comment {
  final String id;
  final String patientId;
  final String medecinId;
  final String medecinName;
  final String commentText;
  final bool isRead;
  final String? measurementId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Comment({
    required this.id,
    required this.patientId,
    required this.medecinId,
    required this.medecinName,
    required this.commentText,
    required this.isRead,
    this.measurementId,
    required this.createdAt,
    required this.updatedAt,
  });

  // Créer depuis JSON (API)
  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] as String,
      patientId: json['patient_id'] as String? ?? '',
      medecinId: json['medecin_id'] as String,
      medecinName: json['medecin_name'] as String? ?? 'Inconnu',
      commentText: json['comment_text'] as String,
      isRead: json['is_read'] as bool? ?? false,
      measurementId: json['measurement_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.parse(
              json['created_at'] as String), // Fallback sur created_at
    );
  }

  // Convertir en JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient_id': patientId,
      'medecin_id': medecinId,
      'medecin_name': medecinName,
      'comment_text': commentText,
      'is_read': isRead,
      'measurement_id': measurementId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Copier avec modifications
  Comment copyWith({
    String? id,
    String? patientId,
    String? medecinId,
    String? medecinName,
    String? commentText,
    bool? isRead,
    String? measurementId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Comment(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      medecinId: medecinId ?? this.medecinId,
      medecinName: medecinName ?? this.medecinName,
      commentText: commentText ?? this.commentText,
      isRead: isRead ?? this.isRead,
      measurementId: measurementId ?? this.measurementId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Formater la date de manière lisible
  String getFormattedDate() {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inMinutes < 1) {
      return 'À l\'instant';
    } else if (difference.inMinutes < 60) {
      return 'Il y a ${difference.inMinutes} min';
    } else if (difference.inHours < 24) {
      return 'Il y a ${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return 'Il y a ${difference.inDays}j';
    } else {
      return '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}';
    }
  }

  @override
  String toString() {
    return 'Comment(id: $id, medecinName: $medecinName, commentText: $commentText, isRead: $isRead)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Comment && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
