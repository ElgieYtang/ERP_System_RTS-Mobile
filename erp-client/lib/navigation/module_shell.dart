import 'package:flutter/material.dart';

import 'app_navigation.dart';
import 'mobile_modules.dart';
import 'module_navigation_scope.dart';
import '../services/api_client.dart';

class ModuleShell extends StatelessWidget {
  const ModuleShell({
    super.key,
    required this.module,
    required this.api,
    required this.onOpenModule,
  });

  final MobileModule module;
  final ApiClient api;
  final void Function(BuildContext context, MobileModule module) onOpenModule;

  @override
  Widget build(BuildContext context) {
    final info = mobileModules.firstWhere((item) => item.id == module);

    return ModuleNavigationScope(
      onOpenModule: onOpenModule,
      child: Scaffold(
        appBar: transactionAppBar(context, title: info.title, showBack: true),
        body: buildMobileModulePage(module, api),
      ),
    );
  }
}
