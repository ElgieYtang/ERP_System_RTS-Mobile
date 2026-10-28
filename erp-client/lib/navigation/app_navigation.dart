import 'package:flutter/material.dart';

void goHome(BuildContext context) {
  Navigator.of(context).popUntil((route) => route.isFirst);
}

Widget homeAppBarButton(BuildContext context) {
  return IconButton(
    icon: const Icon(Icons.dashboard_rounded),
    tooltip: 'Dashboard',
    onPressed: () => goHome(context),
  );
}

Widget backAppBarButton(BuildContext context, {VoidCallback? onPressed}) {
  return IconButton(
    icon: const Icon(Icons.arrow_back_rounded),
    tooltip: 'Back',
    onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
  );
}

/// Module lists: back to dashboard + home shortcut.
/// Detail screens: back + optional actions + dashboard shortcut.
PreferredSizeWidget transactionAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? extraActions,
  bool showBack = false,
  VoidCallback? onBack,
  PreferredSizeWidget? bottom,
}) {
  return AppBar(
    automaticallyImplyLeading: false,
    leading: backAppBarButton(context, onPressed: onBack),
    title: Text(
      title,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    ),
    actions: [
      if (extraActions != null) ...extraActions,
      homeAppBarButton(context),
      const SizedBox(width: 4),
    ],
    bottom: bottom,
  );
}
