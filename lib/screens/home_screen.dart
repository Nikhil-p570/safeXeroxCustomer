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
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
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

  Future<void> _deleteUpload(Map<String, dynamic> upload) async {
    try {
      // Optimistic UI update
      if (mounted) {
        setState(() {
          _myUploads.removeWhere((item) => item['id'] == upload['id']);
        });
      }

      final fileUrl = upload['file_url'] as String;
      final uri = Uri.parse(fileUrl);
      final fileName = uri.pathSegments.last;
      final shopId = upload['shop_id'];
      final storagePath = 'uploads/$shopId/$fileName';

      await Supabase.instance.client.storage
          .from('print-files')
          .remove([storagePath]);

      await Supabase.instance.client
          .from('print_requests')
          .delete()
          .eq('id', upload['id']);

      // No need to fetch manually, the stream handles it
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File deleted permanently')),
        );
      }
    } catch (e) {
      debugPrint('Error deleting file: $e');
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Safe Xerox',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1B5E20),
                            ),
                          ),
                          Text(
                            'Secure Printing',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B5E20).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.security, color: Color(0xFF1B5E20), size: 28),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.onStartScanning,
                    icon: const Icon(Icons.qr_code_scanner, size: 28),
                    label: const Text('Start Scanning'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Your Recent Uploads',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    if (_myUploads.isNotEmpty)
                      TextButton(onPressed: _initMyUploadsStream, child: const Text('Refresh')),
                  ],
                ),
                const SizedBox(height: 16),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_myUploads.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text('No files uploaded yet.', style: TextStyle(color: Colors.grey[600])),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _myUploads.length,
                    itemBuilder: (context, index) {
                      final upload = _myUploads[index];
                      final time = DateTime.parse(upload['created_at']);
                      final formattedTime = DateFormat('MMM dd, hh:mm a').format(time.toLocal());
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey[200]!),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                          title: Text(upload['file_name'] ?? 'File', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('Sent at $formattedTime'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _deleteUpload(upload),
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
