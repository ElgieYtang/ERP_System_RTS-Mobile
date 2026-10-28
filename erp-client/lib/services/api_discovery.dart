import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api_settings.dart';

/// Finds the office PC API on the same Wi‑Fi via UDP broadcast (erp-server discovery).
class ApiDiscovery {
  ApiDiscovery._();

  static const discoverPort = 8001;
  static const probe = 'RC_ERP_DISCOVER';

  static Future<String?> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (kIsWeb) return null;
    if (!Platform.isAndroid && !Platform.isIOS) return null;

    RawDatagramSocket? socketRef;
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socketRef = socket;
      socket.broadcastEnabled = true;
      final message = utf8.encode(probe);

      final completer = Completer<String?>();
      late final Timer timer;

      void finish(String? value) {
        if (!completer.isCompleted) {
          completer.complete(value);
        }
        timer.cancel();
        socketRef?.close();
      }

      timer = Timer(timeout, () => finish(null));

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = socket.receive();
        if (packet == null) return;
        try {
          final json = jsonDecode(utf8.decode(packet.data)) as Map<String, dynamic>;
          final api = json['api'];
          if (api is String && api.isNotEmpty) {
            finish(ApiSettings.normalize(api));
          }
        } catch (_) {
          // ignore malformed replies
        }
      });

      void sendProbes() {
        socket.send(message, InternetAddress('255.255.255.255'), discoverPort);
      }

      sendProbes();
      unawaited(_sendSubnetBroadcastsAsync(socket, message));
      unawaited(Future<void>.delayed(const Duration(milliseconds: 250), sendProbes));

      return await completer.future;
    } catch (_) {
      socketRef?.close();
      return null;
    }
  }

  static Future<void> _sendSubnetBroadcastsAsync(
    RawDatagramSocket socket,
    List<int> message,
  ) async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          final parts = ip.split('.');
          if (parts.length != 4) continue;
          final a = int.tryParse(parts[0]);
          final b = int.tryParse(parts[1]);
          if (a == null || b == null) continue;
          final isPrivate = a == 10 ||
              (a == 172 && b >= 16 && b <= 31) ||
              (a == 192 && b == 168);
          if (!isPrivate) continue;
          final broadcast = InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
          socket.send(message, broadcast, discoverPort);
        }
      }
    } catch (_) {
      // Subnet broadcast is best-effort.
    }
  }
}
