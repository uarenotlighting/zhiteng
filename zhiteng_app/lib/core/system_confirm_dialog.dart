import 'package:flutter/services.dart';

const _systemDialogChannel = MethodChannel('zhiteng/system_dialog');

/// Shows the platform's native confirmation alert.
///
/// Returns true when the destructive action is chosen, false when the user
/// stays on the page, and null when the native dialog is cancelled externally.
Future<bool?> showSystemConfirm({
  required String title,
  required String message,
  required String stay,
  required String discard,
}) {
  return _systemDialogChannel.invokeMethod<bool>('confirm', {
    'title': title,
    'message': message,
    'stay': stay,
    'discard': discard,
  });
}
