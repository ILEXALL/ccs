import 'dart:io';

/// Run from the project root: dart tool/check_module_boundaries.dart
/// No third-party packages or network access are needed.
void main() {
  final lib = Directory('lib').absolute;
  final graph = <String, Set<String>>{};
  final errors = <String>[];
  final directive = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );

  for (final file in lib.listSync(recursive: true, followLinks: false)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    final name = file.path.substring(lib.path.length + 1).replaceAll('\\', '/');
    final source = file.readAsStringSync();
    final dependencies = <String>{};
    for (final match in directive.allMatches(source)) {
      final uri = match.group(1)!;
      String? target;
      if (uri.startsWith('package:ccs_app/')) {
        target = uri.substring('package:ccs_app/'.length);
      } else if (!uri.contains(':')) {
        final resolved = file.uri.resolve(uri).toFilePath();
        if (resolved.startsWith('${lib.path}${Platform.pathSeparator}')) {
          target = resolved
              .substring(lib.path.length + 1)
              .replaceAll('\\', '/');
        }
      }
      if (target == null) continue;
      dependencies.add(target);
      if (target == 'main.dart') errors.add('$name imports the entry point');
      if (name.startsWith('core/') &&
          (target.startsWith('features/') || target.startsWith('app/'))) {
        errors.add('$name depends on application/feature code: $target');
      }
      if (name.startsWith('shared/') && target.contains('/screens/')) {
        errors.add('$name depends on a feature screen: $target');
      }
      if (name.startsWith('features/') &&
          {
            'app/bootstrap.dart',
            'app/ccs_app.dart',
            'app/app_shell.dart',
          }.contains(target)) {
        errors.add('$name depends on the application root: $target');
      }
    }
    if (RegExp(r'''part\s+of\s+['"][^'"]*main\.dart['"]''').hasMatch(source)) {
      errors.add('$name is still part of the main.dart library');
    }
    graph[name] = dependencies;
  }

  final visited = <String>{};
  final active = <String>[];
  void visit(String name) {
    final cycleStart = active.indexOf(name);
    if (cycleStart >= 0) {
      errors.add(
        'Import cycle: ${[...active.skip(cycleStart), name].join(' -> ')}',
      );
      return;
    }
    if (!visited.add(name)) return;
    active.add(name);
    for (final next in graph[name] ?? <String>{}) {
      if (!graph.containsKey(next)) {
        errors.add('$name references missing library $next');
      } else {
        visit(next);
      }
    }
    active.removeLast();
  }

  for (final name in graph.keys) {
    visit(name);
  }
  if (errors.isNotEmpty) {
    for (final error in errors.toSet()) {
      stderr.writeln(error);
    }
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Module boundaries pass: ${graph.length} libraries, no import cycles.',
  );
}
