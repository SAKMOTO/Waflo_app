/// A small, safe, in-memory project workspace used by the coding agent.
///
/// It deliberately contains no destructive-by-default behaviour: every
/// mutation is explicit, and deletes require confirmation from the caller.
/// Works on every platform including Flutter Web (no dart:io / file access).
class VirtualWorkspace {
  final Map<String, String> _files = {};

  VirtualWorkspace() {
    _seedDemoFiles();
  }

  void _seedDemoFiles() {
    _files['README.md'] = '# Waflo App\n\nAn AI-first workspace.';
    _files['lib/main.dart'] =
        "import 'package:flutter/material.dart';\n\nvoid main() => runApp(const App());\n";
    _files['lib/theme/colors.dart'] =
        "class AppColors {\n  static const background = Color(0xFF191A1A);\n}\n";
  }

  int get fileCount => _files.length;

  bool exists(String path) => _files.containsKey(path);

  String? read(String path) => _files[path];

  /// Creates or overwrites a file. Returns the previous content (if any).
  String? write(String path, String content) {
    final previous = _files[path];
    _files[path] = content;
    return previous;
  }

  bool delete(String path) => _files.remove(path) != null;

  List<String> listPaths() {
    final paths = _files.keys.toList()..sort();
    return paths;
  }

  int lineCount(String path) =>
      (_files[path] ?? '').split('\n').length;
}