import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onStartScanning;
  const HomeScreen({Key? key, required this.onStartScanning}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  List<Map<String, dynamic>> _myUploads = [];
  bool _isLoading = true;
  StreamSubscription<List<Map<String, dynamic>>>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);
    _animationController.forward();
    _initMyUploadsStream();
  }

  void _initMyUploadsStream() async {
    final prefs = await SharedPreferences.getInstance();
    final customerId = prefs.getString('customer_id');
    if (customerId == null) return;

    _streamSubscription = Supabase.instance.client
        .from('print_requests')
        .stream(primaryKey: ['id'])
        .eq('customer_id', customerId)
        .order('created_at')
        .listen((data) {
          if (mounted) {
            setState(() {
              _myUploads = List<Map<String, dynamic>>.from(data)
                ..sort((a, b) => b['created_at'].compareTo(a['created_at']));
              _isLoading = false;
            });
          }
        });
  }

  Map<String, List<Map<String, dynamic>>> _getGroupedUploads() {
    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var upload in _myUploads) {
      String name = upload['shop_name'] ?? 'Unknown Shop';
      if (!grouped.containsKey(name)) {
        grouped[name] = [];
      }
      grouped[name]!.add(upload);
    }
    return grouped;
  }

  Future<void> _deleteUpload(Map<String, dynamic> upload) async {
    try {
      final fileUrl = upload['file_url'] as String;
      final fileName = Uri.parse(fileUrl).pathSegments.last;
      final storagePath = 'uploads/${upload['shop_id']}/$fileName';
      await Supabase.instance.client.storage.from('print-files').remove([storagePath]);
      await Supabase.instance.client.from('print_requests').delete().eq('id', upload['id']);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File deleted permanently')));
    } catch (e) {
      debugPrint('Error deleting: $e');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _streamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupedUploads = _getGroupedUploads();
    final shopNames = groupedUploads.keys.toList();

    return SingleChildScrollView(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Safe Xerox', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                        Text('Secure Printing', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      ]),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFF1B5E20).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.security, color: Color(0xFF1B5E20), size: 28),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.onStartScanning,
                    icon: const Icon(Icons.qr_code_scanner, size: 28),
                    label: const Text('Start Scanning'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20), foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                const Text('Your Recent History', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_myUploads.isEmpty)
                  Center(child: Text('No history yet.', style: TextStyle(color: Colors.grey[600])))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: shopNames.length,
                    itemBuilder: (context, index) {
                      final shopName = shopNames[index];
                      final files = groupedUploads[shopName]!;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(children: [
                                const Icon(Icons.storefront, color: Color(0xFF1B5E20), size: 20),
                                const SizedBox(width: 8),
                                Text(shopName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1B5E20))),
                              ]),
                            ),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: files.length,
                              itemBuilder: (context, fIndex) {
                                final file = files[fIndex];
                                final time = DateTime.parse(file['created_at']);
                                return ListTile(
                                  leading: const Icon(Icons.insert_drive_file_outlined),
                                  title: Text(file['file_name'] ?? 'File'),
                                  subtitle: Text(DateFormat('hh:mm a').format(time.toLocal())),
                                  trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _deleteUpload(file)),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
