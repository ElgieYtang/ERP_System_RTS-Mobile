import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';

/// Result from continuous scan handler — scanner stays open unless [closeScanner] is true.
class BarcodeContinuousScanResult {
  const BarcodeContinuousScanResult({
    this.message,
    this.isError = false,
    this.closeScanner = false,
  });

  final String? message;
  final bool isError;
  final bool closeScanner;

  static const keepOpen = BarcodeContinuousScanResult();
  static BarcodeContinuousScanResult ok(String message) =>
      BarcodeContinuousScanResult(message: message);
  static BarcodeContinuousScanResult error(String message) =>
      BarcodeContinuousScanResult(message: message, isError: true);
}

typedef BarcodeScanValidator = String? Function(String value);

/// Return an error message to reject the code and keep scanning; null to accept.
typedef BarcodeScanResolver = Future<String?> Function(String value);

/// Full-screen camera barcode scanner.
///
/// Single-scan: stable read + confirm before returning.
/// Continuous: stable read + validation; stays open until Done (or [closeScanner]).
class BarcodeCameraScanPage extends StatefulWidget {
  const BarcodeCameraScanPage({
    super.key,
    required this.title,
    this.hint,
    this.continuous = false,
    this.onContinuousScan,
    this.validate,
    this.resolveBeforeClose,
  });

  final String title;
  final String? hint;
  final bool continuous;
  final Future<BarcodeContinuousScanResult> Function(String value)? onContinuousScan;
  final BarcodeScanValidator? validate;
  final BarcodeScanResolver? resolveBeforeClose;

  static Future<String?> scan(
    BuildContext context, {
    required String title,
    String? hint,
    BarcodeScanValidator? validate,
    BarcodeScanResolver? resolveBeforeClose,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => BarcodeCameraScanPage(
          title: title,
          hint: hint,
          validate: validate,
          resolveBeforeClose: resolveBeforeClose,
        ),
      ),
    );
  }

  static Future<void> scanContinuous(
    BuildContext context, {
    required String title,
    String? hint,
    BarcodeScanValidator? validate,
    required Future<BarcodeContinuousScanResult> Function(String value) onScan,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BarcodeCameraScanPage(
          title: title,
          hint: hint,
          continuous: true,
          validate: validate,
          onContinuousScan: onScan,
        ),
      ),
    );
  }

  @override
  State<BarcodeCameraScanPage> createState() => _BarcodeCameraScanPageState();
}

class _BarcodeCameraScanPageState extends State<BarcodeCameraScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  static const _stableReadsRequired = 3;
  static const _stableWindow = Duration(milliseconds: 900);
  static const _minHoldDuration = Duration(milliseconds: 650);
  static const _cooldownAfterAccept = Duration(milliseconds: 1200);

  String? _stableValue;
  int _stableCount = 0;
  DateTime? _stableSince;
  DateTime? _cooldownUntil;

  String? _pendingValue;
  String? _statusMessage;
  bool _statusIsError = false;
  bool _processing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _inCooldown =>
      _cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!);

  void _resetStable() {
    _stableValue = null;
    _stableCount = 0;
    _stableSince = null;
  }

  void _setStatus(String? message, {bool isError = false}) {
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
  }

  String? _runValidator(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      return 'Code too short — hold steady and scan again.';
    }
    if (trimmed.length > 128) {
      return 'Code too long to be valid.';
    }
    final custom = widget.validate?.call(trimmed);
    if (custom != null && custom.isNotEmpty) return custom;
    return null;
  }

  Future<void> _pauseCamera() async {
    try {
      await _controller.stop();
    } catch (_) {}
  }

  Future<void> _resumeCamera() async {
    try {
      await _controller.start();
    } catch (_) {}
  }

  void _noteDetection(String value) {
    if (_processing || _inCooldown) return;
    if (_pendingValue != null && !widget.continuous) return;

    final now = DateTime.now();
    if (_stableValue != value) {
      _stableValue = value;
      _stableCount = 1;
      _stableSince = now;
      return;
    }

    if (_stableSince == null || now.difference(_stableSince!) > _stableWindow) {
      _stableCount = 1;
      _stableSince = now;
      return;
    }

    _stableCount++;
    if (_stableCount < _stableReadsRequired) return;
    if (now.difference(_stableSince!) < _minHoldDuration) return;

    if (!widget.continuous) {
      _pauseCamera();
      setState(() => _pendingValue = value);
      _setStatus('Tap Use code when this matches the label.');
      return;
    }

    _acceptValue(value);
  }

  Future<void> _acceptValue(String value) async {
    final trimmed = value.trim();
    final validationError = _runValidator(trimmed);
    if (validationError != null) {
      _resetStable();
      _setStatus(validationError, isError: true);
      return;
    }

    if (!widget.continuous) {
      final resolver = widget.resolveBeforeClose;
      if (resolver != null) {
        setState(() => _processing = true);
        _setStatus('Checking barcode…');
        final resolveError = await resolver(trimmed);
        if (!mounted) return;
        setState(() => _processing = false);
        if (resolveError != null && resolveError.isNotEmpty) {
          _setStatus(resolveError, isError: true);
          _resetStable();
          setState(() => _pendingValue = null);
          await _resumeCamera();
          return;
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(trimmed);
      return;
    }

    final handler = widget.onContinuousScan;
    if (handler == null) return;

    setState(() => _processing = true);
    _setStatus('Saving…');

    final result = await handler(trimmed);
    if (!mounted) return;

    setState(() => _processing = false);
    _resetStable();
    _cooldownUntil = DateTime.now().add(_cooldownAfterAccept);

    if (result.message != null && result.message!.isNotEmpty) {
      _setStatus(result.message, isError: result.isError);
    } else if (!result.isError) {
      _setStatus('Saved. Scan next.');
    } else {
      _setStatus(null);
    }

    if (result.closeScanner) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_processing || _inCooldown) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      _noteDetection(value);
      return;
    }
  }

  Future<void> _discardPending() async {
    setState(() {
      _pendingValue = null;
      _statusMessage = null;
      _statusIsError = false;
    });
    _resetStable();
    await _resumeCamera();
    _setStatus('Scan again — align code inside the frame.');
  }

  Future<void> _confirmPending() async {
    if (_processing) return;
    final value = _pendingValue?.trim();
    if (value == null || value.isEmpty) return;
    final validationError = _runValidator(value);
    if (validationError != null) {
      _setStatus(validationError, isError: true);
      return;
    }
    await _acceptValue(value);
  }

  @override
  Widget build(BuildContext context) {
    final showConfirm = !widget.continuous && _pendingValue != null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Toggle torch',
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flash_on_outlined),
          ),
          if (widget.continuous)
            TextButton(
              onPressed: _processing ? null : () => Navigator.of(context).pop(),
              child: const Text('Done', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _cameraErrorMessage(error),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.maroon, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          if (showConfirm)
            Align(
              alignment: Alignment.center,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Detected code',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _pendingValue!,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _processing ? null : _discardPending,
                            child: const Text('Scan again'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _processing ? null : _confirmPending,
                            child: Text(_processing ? 'Checking…' : 'Use code'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.hint ?? 'Align the barcode inside the frame.',
                    style: const TextStyle(color: Colors.white, height: 1.35),
                  ),
                  if (widget.continuous) ...[
                    const SizedBox(height: 8),
                    Text(
                      _processing
                          ? 'Saving…'
                          : 'Hold steady until the code is accepted. Tap Done when finished.',
                      style: TextStyle(
                        color: _processing ? AppTheme.brandOrange : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ] else if (!showConfirm) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Hold the code in the frame until it is detected, then confirm.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _statusMessage!,
                      style: TextStyle(
                        color: _statusIsError ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _cameraErrorMessage(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Camera permission is required to scan barcodes. Enable it in device settings.';
      case MobileScannerErrorCode.unsupported:
        return 'Camera scanning is not supported on this device.';
      default:
        return 'Could not open the camera. ${error.errorDetails?.message ?? ''}'.trim();
    }
  }
}
