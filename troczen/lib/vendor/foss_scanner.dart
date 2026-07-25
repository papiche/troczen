// FOSS-only QR scanner, API-compatible with package:mobile_scanner.
//
// mobile_scanner bundles Google ML Kit (com.google.mlkit:barcode-scanning),
// a proprietary dependency that F-Droid's inclusion policy disallows. This
// file re-implements the small subset of mobile_scanner's public API that
// the app actually uses, backed by flutter_zxing (ZXing-C++ via FFI, no
// Google dependencies) instead.
//
// The F-Droid build recipe swaps every
//   import 'package:mobile_scanner/mobile_scanner.dart';
// for
//   import 'package:troczen/vendor/foss_scanner.dart';
// and removes the mobile_scanner dependency from pubspec.yaml, so the main
// (GitHub) build is unaffected.

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;

enum CameraFacing { front, back }

enum DetectionSpeed { normal, noDuplicates, unrestricted }

enum BarcodeFormat { qrCode, any }

class Barcode {
  const Barcode({this.rawValue});

  final String? rawValue;
}

class BarcodeCapture {
  const BarcodeCapture({required this.barcodes});

  final List<Barcode> barcodes;
}

class MobileScannerController extends ChangeNotifier {
  MobileScannerController({
    this.detectionSpeed = DetectionSpeed.normal,
    this.facing = CameraFacing.back,
    this.formats = const <BarcodeFormat>[],
  });

  DetectionSpeed detectionSpeed;
  CameraFacing facing;
  List<BarcodeFormat> formats;

  void switchCamera() {
    facing = facing == CameraFacing.back ? CameraFacing.front : CameraFacing.back;
    notifyListeners();
  }
}

class MobileScanner extends StatefulWidget {
  const MobileScanner({super.key, this.controller, this.onDetect});

  final MobileScannerController? controller;
  final void Function(BarcodeCapture capture)? onDetect;

  @override
  State<MobileScanner> createState() => _MobileScannerState();
}

class _MobileScannerState extends State<MobileScanner> {
  late MobileScannerController _controller;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
  }

  @override
  void didUpdateWidget(covariant MobileScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _detachController();
      _attachController(widget.controller);
    }
  }

  void _attachController(MobileScannerController? controller) {
    _ownsController = controller == null;
    _controller = controller ?? MobileScannerController();
    _controller.addListener(_onControllerChanged);
  }

  void _detachController() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
  }

  void _onControllerChanged() => setState(() {});

  void _handleScan(zxing.Code code) {
    final String? text = code.text;
    if (text == null || text.isEmpty || !code.isValid) return;
    widget.onDetect?.call(BarcodeCapture(barcodes: [Barcode(rawValue: text)]));
  }

  int get _codeFormat {
    if (_controller.formats.isEmpty) return zxing.Format.any;
    if (_controller.formats.contains(BarcodeFormat.qrCode)) return zxing.Format.qrCode;
    return zxing.Format.any;
  }

  @override
  void dispose() {
    _detachController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return zxing.ReaderWidget(
      key: ValueKey(_controller.facing),
      onScan: _handleScan,
      onScanFailure: (_) {},
      codeFormat: _codeFormat,
      lensDirection: _controller.facing == CameraFacing.front
          ? zxing.CameraLensDirection.front
          : zxing.CameraLensDirection.back,
      showScannerOverlay: false,
      showFlashlight: true,
      showToggleCamera: false,
      showGallery: false,
    );
  }
}
