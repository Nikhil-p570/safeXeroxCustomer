import 'package:http/http.dart' as http;
import 'dart:convert';

class XeroxPrinter {
  final String id;
  final String name;
  final String model;
  final String status;
  final String location;
  final bool isConnected;

  XeroxPrinter({
    required this.id,
    required this.name,
    required this.model,
    required this.status,
    required this.location,
    required this.isConnected,
  });

  factory XeroxPrinter.fromJson(Map<String, dynamic> json) {
    return XeroxPrinter(
      id: json['id'] as String,
      name: json['name'] as String,
      model: json['model'] as String,
      status: json['status'] as String,
      location: json['location'] as String,
      isConnected: json['isConnected'] as bool,
    );
  }
}

class PrintJob {
  final String id;
  final String fileName;
  final String printerId;
  final String status;
  final DateTime createdAt;
  final DateTime? completedAt;

  PrintJob({
    required this.id,
    required this.fileName,
    required this.printerId,
    required this.status,
    required this.createdAt,
    this.completedAt,
  });

  factory PrintJob.fromJson(Map<String, dynamic> json) {
    return PrintJob(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      printerId: json['printerId'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      completedAt: json['completedAt'] != null 
          ? DateTime.parse(json['completedAt'] as String)
          : null,
    );
  }
}

class TemporaryAccount {
  final String id;
  final String accountNumber;
  final String password;
  final DateTime createdAt;
  final DateTime expiresAt;

  TemporaryAccount({
    required this.id,
    required this.accountNumber,
    required this.password,
    required this.createdAt,
    required this.expiresAt,
  });

  factory TemporaryAccount.fromJson(Map<String, dynamic> json) {
    return TemporaryAccount(
      id: json['id'] as String,
      accountNumber: json['accountNumber'] as String,
      password: json['password'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );
  }
}

class XeroxPrintService {
  static const String baseUrl = 'https://api.xerox.com/workplace/v1';
  late String _accessToken;
  late String _refreshToken;

  // Initialize with credentials
  Future<bool> initialize(String apiKey) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'api_key': apiKey}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        _refreshToken = data['refresh_token'];
        return true;
      }
      return false;
    } catch (e) {
      print('Error initializing XeroxPrintService: $e');
      return false;
    }
  }

  // Get all available printers
  Future<List<XeroxPrinter>> getAvailablePrinters() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/printers'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((p) => XeroxPrinter.fromJson(p)).toList();
      }
      throw Exception('Failed to fetch printers');
    } catch (e) {
      print('Error fetching printers: $e');
      return [];
    }
  }

  // Upload file to cloud
  Future<String?> uploadFile(String filePath, String fileName) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/files/upload'),
      );

      request.headers.addAll(_getHeaders());
      request.files.add(
        await http.MultipartFile.fromPath('file', filePath),
      );
      request.fields['fileName'] = fileName;

      final response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final data = jsonDecode(responseData);
        return data['file_id'];
      }
      return null;
    } catch (e) {
      print('Error uploading file: $e');
      return null;
    }
  }

  // Create temporary account for printing
  Future<TemporaryAccount?> createTemporaryAccount({
    int expiryMinutes = 10,
    List<String> permissions = const ['print'],
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/accounts/temporary'),
        headers: _getHeaders(),
        body: jsonEncode({
          'expiry_minutes': expiryMinutes,
          'permissions': permissions,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return TemporaryAccount.fromJson(data);
      }
      return null;
    } catch (e) {
      print('Error creating temporary account: $e');
      return null;
    }
  }

  // Send print job
  Future<PrintJob?> sendPrintJob({
    required String fileId,
    required String printerId,
    int copies = 1,
    bool doubleSided = false,
    String colorMode = 'auto',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/jobs/print'),
        headers: _getHeaders(),
        body: jsonEncode({
          'file_id': fileId,
          'printer_id': printerId,
          'copies': copies,
          'double_sided': doubleSided,
          'color_mode': colorMode,
          'encryption': true,
          'auto_delete': true,
          'delete_after_minutes': 10,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return PrintJob.fromJson(data);
      }
      return null;
    } catch (e) {
      print('Error sending print job: $e');
      return null;
    }
  }

  // Get print job status
  Future<PrintJob?> getPrintJobStatus(String jobId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/jobs/$jobId'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return PrintJob.fromJson(data);
      }
      return null;
    } catch (e) {
      print('Error fetching print job status: $e');
      return null;
    }
  }

  // Get print history
  Future<List<PrintJob>> getPrintHistory({int limit = 20}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/jobs/history?limit=$limit'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((j) => PrintJob.fromJson(j)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching print history: $e');
      return [];
    }
  }

  // Delete file from cloud
  Future<bool> deleteFile(String fileId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/files/$fileId'),
        headers: _getHeaders(),
      );

      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      print('Error deleting file: $e');
      return false;
    }
  }

  // Cancel print job
  Future<bool> cancelPrintJob(String jobId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/jobs/$jobId/cancel'),
        headers: _getHeaders(),
      );

      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      print('Error canceling print job: $e');
      return false;
    }
  }

  // Refresh access token
  Future<bool> refreshToken() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        return true;
      }
      return false;
    } catch (e) {
      print('Error refreshing token: $e');
      return false;
    }
  }

  // Helper method to get headers
  Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_accessToken',
    };
  }

  // Logout
  Future<void> logout() async {
    try {
      await http.post(
        Uri.parse('$baseUrl/auth/logout'),
        headers: _getHeaders(),
      );
    } catch (e) {
      print('Error logging out: $e');
    }
  }
}
