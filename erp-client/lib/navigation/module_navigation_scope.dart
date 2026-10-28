import 'package:flutter/material.dart';

import '../navigation/mobile_modules.dart';

/// Provides module navigation to pushed transaction/detail routes.
class ModuleNavigationScope extends InheritedWidget {
  const ModuleNavigationScope({
    super.key,
    required this.onOpenModule,
    required super.child,
  });

  final void Function(BuildContext context, MobileModule module) onOpenModule;

  static ModuleNavigationScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ModuleNavigationScope>();
  }

  @override
  bool updateShouldNotify(ModuleNavigationScope oldWidget) =>
      oldWidget.onOpenModule != onOpenModule;
}

/// Keeps module navigation working on pushed detail routes.
Widget wrapModuleNavigationScope(BuildContext context, Widget child) {
  final scope = ModuleNavigationScope.maybeOf(context);
  if (scope == null) return child;
  return ModuleNavigationScope(
    onOpenModule: scope.onOpenModule,
    child: child,
  );
}
