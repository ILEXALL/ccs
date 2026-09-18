import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory('build/ui-explorer/${DateTime.now().millisecondsSinceEpoch}');
  await directory.create(recursive: true);
  print('UI exploration artifacts: ${directory.absolute.path}');
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      await File('${directory.path}/$safe.png').writeAsBytes(bytes);
      if (args != null) {
        await File('${directory.path}/steps.json').writeAsString(const JsonEncoder.withIndent('  ').convert(args));
      }
      return true;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {});
      report.remove('screenshots');
      final errors = '${report['error']} ${report['frameworkErrors']}';
      report['classification'] = errors.contains('[core/no-app]')
          ? 'Test environment incomplete: no local Firebase fixture; not a confirmed app bug'
          : report['status'] == 'passed'
              ? 'No failure in exercised actions; untested features remain'
              : 'Needs review: framework, application or test-runner failure';
      await File('${directory.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      final steps = (report['steps'] as List?) ?? [];
      await File('${directory.path}/REPORT.md').writeAsString([
        '# UI exploration: ${report['status'] ?? 'unknown'}',
        '',
        'Seed: ${report['seed']}. Scope: ${report['scope']}.',
        'Classification: ${report['classification']}.',
        '',
        '## Reproduction',
        'Open the isolated screen named in Scope with the same seed and build, then:',
        ...steps.map((step) => '${step['step']}. ${jsonEncode(step)}'),
        '',
        '## Observed',
        '${report['error'] ?? 'No assertion failed in the exercised actions.'}',
        ...((report['frameworkErrors'] as List?) ?? []).map((error) => '$error'),
        '',
        'Screenshots are stored next to this report. Framework assertions need review;',
        'they do not by themselves prove a release-build crash.',
      ].join('\n'));
    },
  );
}
