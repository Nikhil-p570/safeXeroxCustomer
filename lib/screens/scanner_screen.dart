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

  static Widget buildShopFoundDialog(BuildContext context, String shopId, String shopName) {
    bool isUploading = false;
    final nameController = TextEditingController();
    
    return StatefulBuilder(
      builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 24),
              if (isUploading)
                const Column(
                  children: [
                    CircularProgressIndicator(color: Colors.green),
                    SizedBox(height: 16),
                    Text('Uploading your files...', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('Please do not close this window', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                )
              else
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.storefront_outlined, color: Colors.green, size: 40),
                    ),
                    const SizedBox(height: 16),
                    Text('Connected to $shopName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Your Name',
                        hintText: 'Enter your name for the owner',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (nameController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter your name first')),
                            );
                            return;
                          }
                          try {
                            final scannerState = context.findAncestorStateOfType<_ScannerScreenState>();
                            if (scannerState != null) {
                              await scannerState._pickAndUploadFiles(context, shopId, nameController.text.trim(), (uploading) {
                                setModalState(() => isUploading = uploading);
                              });
                            } else {
                              await _staticPickAndUploadFiles(context, shopId, nameController.text.trim(), (uploading) {
                                setModalState(() => isUploading = uploading);
                              });
                            }
                          } catch (e) {
                            setModalState(() => isUploading = false);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[800],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('SELECT & UPLOAD FILES', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
                    ),
                  ],
                ),
            ],
          ),
        ),
    );
  }

  static Future<void> _staticPickAndUploadFiles(BuildContext context, String shopId, String customerName, Function(bool) setLoading) async {
    final state = _ScannerScreenState();
    await state._pickAndUploadFiles(context, shopId, customerName, setLoading);
  }

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _isScanning = true;

  void _handleShopQr(BuildContext context, String code) {
    if (!_isScanning) return;
    setState(() => _isScanning = false);

    try {
      final uri = Uri.parse(code);
      String? shopId;
      String? shopName;

      if (code.contains('safe-xerox-customer.vercel.app')) {
        shopId = uri.queryParameters['id'];
        shopName = uri.queryParameters['name'] ?? 'Unknown Shop';
      } else {
        shopId = uri.queryParameters['id'];
        shopName = uri.queryParameters['name'] ?? 'Unknown Shop';
      }

      if (shopId != null) {
        _showShopFoundDialog(context, shopId, shopName);
      }
    } catch (e) {
      debugPrint('Error parsing QR code: $e');
      setState(() => _isScanning = true);
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
      if (mounted) setState(() => _isScanning = true);
    });
  }

  Future<void> _pickAndUploadFiles(BuildContext context, String shopId, String customerName, Function(bool) setLoading) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
      );

      if (result == null) {
        setLoading(false);
        return;
      }

      setLoading(true);

      for (final file in result.files) {
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
        } catch (storageError) {
          debugPrint('Storage upload error: $storageError');
        }

        if (uploadSuccess) {
          final fileUrl = Supabase.instance.client.storage.from('print-files').getPublicUrl(path);
          final prefs = await SharedPreferences.getInstance();
          final customerId = prefs.getString('customer_id');

          await Supabase.instance.client.from('print_requests').insert({
            'shop_id': shopId,
            'file_url': fileUrl,
            'file_name': file.name,
            'status': 'pending',
            'customer_id': customerId,
            'customer_name': customerName, // Storing the name!
          });
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Files sent successfully!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      setLoading(false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text('Scan Shop QR', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ],
              ),
            ),
          ),
          Positioned(top: 40, left: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 28), onPressed: widget.onClose)),
        ],
      ),
    );
  }
}
