import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/api_discovery.dart';
import '../services/api_settings.dart';
import '../state/auth_state.dart';
import '../theme/app_theme.dart';

/// Change API server (LAN IP) without rebuilding the APK.
Future<void> showServerConnectionSheet(BuildContext context) async {
  final api = context.read<ApiClient>();
  final current = ApiSettings.current;
  final usesEmulatorHost = current.contains('10.0.2.2');
  final controller = TextEditingController(
    text: usesEmulatorHost ? '' : ApiSettings.displayHostPort(current),
  );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      var testing = false;
      var scanning = false;
      String? testResult;
      var testOk = false;

      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewPaddingOf(sheetContext).bottom,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'API server',
              style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.maroon,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              usesEmulatorHost
                  ? '10.0.2.2 only works on the Android emulator. On a real phone, enter your PC’s Wi‑Fi IP (same network). Example: 192.168.1.60:8000'
                  : 'Use your office PC address while on the same Wi‑Fi. Example: 192.168.1.60:8000',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Server (IP or URL)',
                hintText: '192.168.1.60:8000',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: (testing || scanning)
                  ? null
                  : () async {
                      setSheetState(() {
                        scanning = true;
                        testResult = null;
                        testOk = false;
                      });
                      final found = await ApiDiscovery.discover();
                      if (found != null) {
                        controller.text = ApiSettings.displayHostPort(found);
                      }
                      setSheetState(() {
                        scanning = false;
                        testOk = found != null;
                        testResult = found != null
                            ? 'Found server at $found'
                            : 'No server on this Wi‑Fi. Is npm start running on your PC?';
                      });
                    },
              icon: scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find_outlined, size: 18),
              label: Text(scanning ? 'Searching…' : 'Find server on Wi‑Fi'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: testing
                  ? null
                  : () async {
                      setSheetState(() {
                        testing = true;
                        testResult = null;
                        testOk = false;
                      });
                      final err = await api.pingHealth(baseUrlOverride: controller.text);
                      setSheetState(() {
                        testing = false;
                        testOk = err == null;
                        testResult = err ?? 'Connected to ${ApiSettings.normalize(controller.text)}';
                      });
                    },
              icon: testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering_outlined, size: 18),
              label: Text(testing ? 'Testing…' : 'Test connection'),
            ),
            if (testResult != null) ...[
              const SizedBox(height: 8),
              Text(
                testResult!,
                style: TextStyle(
                  fontSize: 12,
                  color: testOk ? AppTheme.successText : AppTheme.errorText,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await api.resetSavedConnection();
                controller.text = usesEmulatorHost ? '' : ApiSettings.displayHostPort(ApiSettings.builtinDefault);
                setSheetState(() {
                  testResult = 'Server and offline lists reset to default.';
                  testOk = true;
                });
              },
              child: const Text('Reset saved server & clear offline lists'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                final raw = controller.text.trim();
                if (raw.isEmpty) {
                  setSheetState(() {
                    testOk = false;
                    testResult = 'Enter your PC IP, e.g. 192.168.1.60:8000';
                  });
                  return;
                }
                await api.updateBaseUrl(raw);
                await context.read<AuthState>().bootstrap();
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Server set to ${ApiSettings.current}'),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
            );
          },
        ),
      );
    },
  );

  controller.dispose();
}
