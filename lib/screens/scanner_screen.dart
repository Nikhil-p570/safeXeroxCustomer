import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../widgets/scanner_overlay.dart';

class ScannerScreen extends StatefulWidget {
  final VoidCallback onClose;
  const ScannerScreen({Key? key, required this.onClose}) : super(key: key);

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();

  static Widget buildShopFoundDialog(BuildContext context, String shopId, String shopName, {bool startImmediately = false}) {
    return ShopFoundDialog(shopId: shopId, shopName: shopName, startImmediately: startImmediately);
  }

  static Future<void> _staticPickAndUploadFiles(
    BuildContext context, String shopId, String shopName, String customerName, 
    Function(bool) setLoading, {bool autoCloseOnCancel = false}
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
      );

      if (result == null) {
        setLoading(false);
        if (autoCloseOnCancel && Navigator.canPop(context)) Navigator.pop(context);
        return;
      }

      await uploadFiles(context, shopId, shopName, customerName, result.files, setLoading);
    } catch (e) {
      setLoading(false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  static Future<void> uploadFiles(
    BuildContext context, String shopId, String shopName, String customerName, 
    List<PlatformFile> files, Function(bool) setLoading
  ) async {
    try {
      setLoading(true);
      final prefs = await SharedPreferences.getInstance();
      final customerId = prefs.getString('customer_id');

      for (final file in files) {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
        final path = 'uploads/$shopId/$fileName';
        bool uploadSuccess = false;

        try {
          if (kIsWeb) {
            if (file.bytes != null) {
              await Supabase.instance.client.storage.from('print-files').uploadBinary(path, file.bytes!);
              uploadSuccess = true;
            }
          } else {
            if (file.path != null) {
              await Supabase.instance.client.storage.from('print-files').upload(path, File(file.path!));
              uploadSuccess = true;
            }
          }
        } catch (e) { debugPrint('Upload error: $e'); }

        if (uploadSuccess) {
          final fileUrl = Supabase.instance.client.storage.from('print-files').getPublicUrl(path);
          await Supabase.instance.client.from('print_requests').insert({
            'shop_id': shopId, 'shop_name': shopName,
            'file_url': fileUrl, 'file_name': file.name,
            'status': 'pending', 'customer_id': customerId, 'customer_name': customerName,
          });
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Files sent successfully!'), backgroundColor: Colors.green));
        if (Navigator.canPop(context)) Navigator.pop(context);
      }
    } catch (e) {
      setLoading(false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  static Future<void> showDirectUpload(BuildContext context, String shopId, String shopName) async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('customer_display_name');

    if (savedName != null && savedName.isNotEmpty) {
      // Trigger picker immediately
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
      );

      if (result == null || result.files.isEmpty) return;

      if (!context.mounted) return;

      // Show upload progress dialog
      showModalBottomSheet(
        context: context,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) => ShopFoundDialog(
          shopId: shopId, 
          shopName: shopName, 
          initialFiles: result.files,
        ),
      );
    } else {
      // Fallback to name input dialog
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) => ScannerScreen.buildShopFoundDialog(context, shopId, shopName, startImmediately: true),
      );
    }
  }
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isScanning = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleShopQr(BuildContext context, String code) {
    if (!_isScanning) return;
    
    _isScanning = false;
    _controller.stop(); // Stop scanner immediately to prevent multiple triggers
    
    try {
      final uri = Uri.parse(code);
      String? shopId = uri.queryParameters['id'];
      String? shopName = uri.queryParameters['name'] ?? 'Unknown Shop';
      if (shopId != null) {
        _showShopFoundDialog(context, shopId, shopName);
      } else {
        // Not a valid shop QR, resume scanning
        _resumeScanning();
      }
    } catch (e) {
      _resumeScanning();
    }
  }

  void _resumeScanning() {
    if (mounted) {
      setState(() {
        _isScanning = true;
        _controller.start();
      });
    }
  }

  void _showShopFoundDialog(BuildContext context, String shopId, String shopName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => ScannerScreen.buildShopFoundDialog(context, shopId, shopName),
    ).whenComplete(() {
      _resumeScanning();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (!_isScanning) return;
              for (final barcode in capture.barcodes) {
                final String? code = barcode.rawValue;
                if (code != null && (code.startsWith('safexerox://shop') || code.contains('safe-xerox-customer.vercel.app'))) {
                  _handleShopQr(context, code);
                  break;
                }
              }
            },
          ),
          const ScannerOverlay(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [Text('Scan Shop QR', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))],
              ),
            ),
          ),
          Positioned(top: 40, left: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 28), onPressed: widget.onClose)),
        ],
      ),
    );
  }
}

class ShopFoundDialog extends StatefulWidget {
  final String shopId;
  final String shopName;
  final bool startImmediately;
  final List<PlatformFile>? initialFiles;

  const ShopFoundDialog({
    Key? key,
    required this.shopId,
    required this.shopName,
    this.startImmediately = false,
    this.initialFiles,
  }) : super(key: key);

  @override
  State<ShopFoundDialog> createState() => _ShopFoundDialogState();
}

class _ShopFoundDialogState extends State<ShopFoundDialog> {
  bool _isUploading = false;
  final _nameController = TextEditingController();
  bool _hasSavedName = false;
  bool _initialized = false;
  bool _alreadyTriggeredPicker = false;

  @override
  void initState() {
    super.initState();
    _loadSavedName();
  }

  Future<void> _loadSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('customer_display_name');
    if (mounted) {
      setState(() {
        if (savedName != null && savedName.isNotEmpty) {
          _nameController.text = savedName;
          _hasSavedName = true;
        }
        _initialized = true;
      });

      if (widget.initialFiles != null && widget.initialFiles!.isNotEmpty) {
        // Direct upload mode
        _alreadyTriggeredPicker = true;
        Future.delayed(Duration.zero, () => _performUpload(widget.initialFiles!));
      } else if (widget.startImmediately && !_alreadyTriggeredPicker && _hasSavedName && !kIsWeb) {
        _alreadyTriggeredPicker = true;
        Future.delayed(Duration.zero, () => _pickAndUpload());
      }
    }
  }

  Future<void> _performUpload(List<PlatformFile> files) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    
    if (mounted) {
      await ScannerScreen.uploadFiles(
        context, 
        widget.shopId, 
        widget.shopName, 
        name, 
        files, 
        (uploading) {
          if (mounted) setState(() => _isUploading = uploading);
        }
      );
    }
  }

  Future<void> _pickAndUpload() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customer_display_name', name);

    if (mounted) {
      await ScannerScreen._staticPickAndUploadFiles(
        context, 
        widget.shopId, 
        widget.shopName, 
        name, 
        (uploading) {
          if (mounted) setState(() => _isUploading = uploading);
        },
        autoCloseOnCancel: widget.startImmediately && !kIsWeb,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(color: Color(0xFF1B5E20))),
      );
    }

    if (_isUploading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF1B5E20)),
            const SizedBox(height: 24),
            const Text('Uploading your files...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            Text('Sending securely to ${widget.shopName}', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 60, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1B5E20).withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.storefront_outlined, color: Color(0xFF1B5E20), size: 40),
          ),
          const SizedBox(height: 16),
          Text('Connected to ${widget.shopName}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          if (_hasSavedName) ...[
            const SizedBox(height: 8),
            Text('Welcome back, ${_nameController.text}!', style: TextStyle(color: Colors.grey[600], fontSize: 15)),
          ],
          const SizedBox(height: 32),
          if (!_hasSavedName) ...[
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Enter Your Name',
                hintText: 'This will be shown to the shop owner',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1B5E20), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _pickAndUpload,
              icon: const Icon(Icons.upload_file),
              label: const Text('SELECT & UPLOAD FILES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20), foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }
}
