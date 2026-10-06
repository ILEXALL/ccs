import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/config/app_config.dart' show telegramAuthBaseUrl;
import 'package:ccs_app/core/network/json_http.dart' show postJsonToUrl;

class PartnerViewCounter extends StatefulWidget {
  final String partnerId;
  const PartnerViewCounter({super.key, required this.partnerId});
  @override
  State<PartnerViewCounter> createState() => _PartnerViewCounterState();
}

class _PartnerViewCounterState extends State<PartnerViewCounter> {
  late Future<int> count;
  @override
  void initState() {
    super.initState();
    count = record();
  }

  Future<int> record() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw StateError('Sign in required');
    final response = await postJsonToUrl(
      '$telegramAuthBaseUrl/api/community?endpoint=partner-view',
      {'partnerId': widget.partnerId},
      headers: {'Authorization': 'Bearer $token'},
    );
    return (response['uniqueViews'] as num).toInt();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
    future: count,
    builder: (context, snapshot) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.visibility_outlined, size: 18, color: Colors.white60),
        const SizedBox(width: 6),
        Text(
          snapshot.data?.toString() ?? '—',
          style: const TextStyle(color: Colors.white60),
        ),
        if (snapshot.hasError)
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            onPressed: () => setState(() => count = record()),
          ),
      ],
    ),
  );
}
