import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_client/web_socket_client.dart';

/// Client for the Waflo Builder backend (HTTP + live progress WebSocket).
///
/// The backend address matches the rest of the app (chat uses
/// ws://localhost:8000/ws/chat); keep in sync if the backend moves.
class BuilderWebService {
  BuilderWebService._internal();

  static final BuilderWebService _instance = BuilderWebService._internal();

  factory BuilderWebService() => _instance;

  static const String baseUrl = 'http://127.0.0.1:8000';
  static const String wsBase = 'ws://127.0.0.1:8000';

  // ---------------------------------------------------------------------------
  // REST
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> createGeneration({
    required String prompt,
    String? url,
    String mode = 'prompt',
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/builder/generate'),
      headers: const {'Content-Type': 'application/json'},
      body: json.encode({'prompt': prompt, 'url': url, 'mode': mode}),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> fetchJob(String jobId) async {
    final res =
        await http.get(Uri.parse('$baseUrl/api/builder/jobs/$jobId'));
    return _decode(res);
  }

  Future<bool> cancelJob(String jobId) async {
    try {
      final res = await http
          .post(Uri.parse('$baseUrl/api/builder/jobs/$jobId/cancel'));
      final data = _decode(res);
      return data['cancelled'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<dynamic>> fetchProjects() async {
    final res = await http.get(Uri.parse('$baseUrl/api/builder/projects'));
    final decoded = json.decode(res.body.isEmpty ? '[]' : res.body);
    return decoded is List ? decoded : <dynamic>[];
  }

  Future<Map<String, dynamic>?> fetchProjectFile(
    String projectId,
    String path,
  ) async {
    final uri = Uri.parse('$baseUrl/api/builder/projects/$projectId/file')
        .replace(queryParameters: {'path': path});
    final res = await http.get(uri);
    if (res.statusCode == 404) return null;
    return _decode(res);
  }

  // ---------------------------------------------------------------------------
  // Live progress (WebSocket). Emits `snapshot` then repeated `progress`
  // events; completes when the job reaches a terminal status.
  // ---------------------------------------------------------------------------

  Stream<Map<String, dynamic>> progressStream(String jobId) {
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    final ws = WebSocket(Uri.parse('$wsBase/ws/builder'));
    var subscribed = false;

    void subscribe() {
      if (subscribed) return;
      subscribed = true;
      ws.send(json.encode({'action': 'subscribe', 'job_id': jobId}));
    }

    Future<void> ensureConnected() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (true) {
        final state = ws.connection.state;
        if (state is Connected || state is Reconnected) return;
        if (DateTime.now().isAfter(deadline)) return;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }

    unawaited(ensureConnected().then((_) => subscribe()));

    ws.connection.listen((state) {
      if (state is Reconnected) subscribe();
    });

    late final StreamSubscription<dynamic> sub;
    sub = ws.messages.listen(
      (message) {
        Map<String, dynamic> data;
        try {
          data = json.decode(message) as Map<String, dynamic>;
        } catch (_) {
          return;
        }
        controller.add(data);
        final status = data['status'];
        if (status == 'completed' ||
            status == 'failed' ||
            status == 'cancelled') {
          sub.cancel();
          ws.close();
          if (!controller.isClosed) controller.close();
        }
      },
      onError: (_) {
        if (!controller.isClosed) controller.close();
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
    );

    return controller.stream;
  }

  static Map<String, dynamic> _decode(http.Response res) {
    final body = res.body.isEmpty ? '{}' : res.body;
    return json.decode(body) as Map<String, dynamic>;
  }
}