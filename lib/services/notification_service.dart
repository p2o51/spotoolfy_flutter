import 'package:flutter/material.dart';

class NotificationService {
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;

  NotificationService(this.scaffoldMessengerKey);

  void showSnackBar(
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    scaffoldMessengerKey.currentState?.removeCurrentSnackBar(); // Remove previous snackbar
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Colors.redAccent // Use a distinct color for errors
            : null, // Default SnackBar color for non-errors
        duration: duration,
        action: action,
        behavior: SnackBarBehavior.floating, // Consistent behavior
        shape: RoundedRectangleBorder( // Consistent shape
          borderRadius: BorderRadius.circular(10.0),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0), // Consistent margin
      ),
    );
  }

  void showSuccessSnackBar(String message, {Duration duration = const Duration(seconds: 3)}) {
    showSnackBar(message, isError: false, duration: duration);
  }

  void showErrorSnackBar(
      String message,
      {Duration duration = const Duration(seconds: 8),
      String? actionLabel,
      VoidCallback? onActionPressed}) {
        
    SnackBarAction? snackBarAction;
    if (actionLabel != null && onActionPressed != null) {
      snackBarAction = SnackBarAction(
        label: actionLabel,
        onPressed: onActionPressed,
      );
    }
    
    showSnackBar(message, isError: true, duration: duration, action: snackBarAction);
  }
} 