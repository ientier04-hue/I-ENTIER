import 'package:flutter/material.dart';
import 'pharmacy_page.dart';
import 'pharmacy_web/embedded_native.dart'
    if (dart.library.js_interop) 'pharmacy_web/embedded_web.dart';

const pharmacyWebUrl = String.fromEnvironment('PHARMACY_WEB_URL');

Uri? pharmacyUri(String base, String query) {
  final uri = Uri.tryParse(base);
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme != 'https' &&
          !(uri.scheme == 'http' &&
              const [
                'localhost',
                '127.0.0.1',
                '10.0.2.2',
              ].contains(uri.host)))) {
    return null;
  }
  return uri.replace(
    queryParameters: {
      ...uri.queryParameters,
      'embedded': '1',
      if (query.isNotEmpty) 'q': query,
    },
  );
}

class PharmacyWebPage extends StatelessWidget {
  final String patientId;
  final String initialQuery;
  final String url;
  const PharmacyWebPage({
    super.key,
    required this.patientId,
    this.initialQuery = '',
    this.url = pharmacyWebUrl,
  });

  @override
  Widget build(BuildContext context) {
    final uri = pharmacyUri(url, initialQuery);
    // Keep the current service available in builds without a deployed web URL.
    if (uri == null) {
      return PharmacyPage(patientId: patientId, initialQuery: initialQuery);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Pharmacie')),
      body: SafeArea(child: EmbeddedPharmacy(uri: uri)),
    );
  }
}
