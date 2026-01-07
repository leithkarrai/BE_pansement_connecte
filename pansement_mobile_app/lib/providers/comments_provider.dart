// ============================================
// Provider Comments - Flutter
// ============================================
// Fichier : lib/providers/comments_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/comment.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

// ============================================
// PROVIDERS
// ============================================

/// Provider pour récupérer les commentaires d'un patient
final patientCommentsProvider = FutureProvider.family<List<Comment>, String>(
  (ref, patientId) async {
    final apiService = ref.watch(apiServiceProvider);

    try {
      final comments =
          await apiService.getPatientComments(patientId, limit: 100);
      return comments;
    } catch (e) {
      throw Exception('Erreur de chargement des commentaires: $e');
    }
  },
);

/// Provider pour le nombre de commentaires non lus
final unreadCommentsCountProvider = FutureProvider.family<int, String>(
  (ref, patientId) async {
    final apiService = ref.watch(apiServiceProvider);

    try {
      return await apiService.getUnreadCommentsCount(patientId);
    } catch (e) {
      return 0;
    }
  },
);

/// Notifier pour gérer les actions sur les commentaires
final commentsNotifierProvider =
    StateNotifierProvider<CommentsNotifier, CommentsState>((ref) {
  return CommentsNotifier(ref.read(apiServiceProvider));
});

// ============================================
// ÉTAT
// ============================================

class CommentsState {
  final bool isLoading;
  final String? error;
  final String? successMessage;

  CommentsState({
    this.isLoading = false,
    this.error,
    this.successMessage,
  });

  CommentsState copyWith({
    bool? isLoading,
    String? error,
    String? successMessage,
  }) {
    return CommentsState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      successMessage: successMessage,
    );
  }
}

// ============================================
// NOTIFIER
// ============================================

class CommentsNotifier extends StateNotifier<CommentsState> {
  final ApiService apiService;

  CommentsNotifier(this.apiService) : super(CommentsState());

  /// Créer un nouveau commentaire
  Future<bool> createComment({
    required String patientId,
    required String commentText,
    String? measurementId,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await apiService.createComment(
        patientId: patientId,
        commentText: commentText,
        measurementId: measurementId,
      );

      state = state.copyWith(
        isLoading: false,
        successMessage: 'Commentaire ajouté avec succès',
      );

      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur lors de l\'ajout du commentaire: $e',
      );
      return false;
    }
  }

  /// Modifier un commentaire existant
  Future<bool> updateComment({
    required String commentId,
    required String commentText,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await apiService.updateComment(
        commentId: commentId,
        commentText: commentText,
      );

      state = state.copyWith(
        isLoading: false,
        successMessage: 'Commentaire modifié',
      );

      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur lors de la modification: $e',
      );
      return false;
    }
  }

  /// Supprimer un commentaire
  Future<bool> deleteComment(String commentId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await apiService.deleteComment(commentId);

      state = state.copyWith(
        isLoading: false,
        successMessage: 'Commentaire supprimé',
      );

      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur lors de la suppression: $e',
      );
      return false;
    }
  }

  /// Marquer un commentaire comme lu
  Future<bool> markAsRead(String commentId) async {
    try {
      await apiService.markCommentAsRead(commentId);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Réinitialiser l'état
  void resetState() {
    state = CommentsState();
  }
}
