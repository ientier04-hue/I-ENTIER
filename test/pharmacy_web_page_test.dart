import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/pharmacy_web_page.dart';

void main() {
  test('conserve la recherche sans transmettre identité ou session', () {
    final uri = pharmacyUri('https://pharmacy.example/', 'Vitamine C');
    expect(uri!.queryParameters, {'embedded': '1', 'q': 'Vitamine C'});
  });
  test('refuse les URL dangereuses et autorise le serveur local', () {
    expect(pharmacyUri('', ''), isNull);
    expect(pharmacyUri('javascript:alert(1)', ''), isNull);
    expect(pharmacyUri('http://example.com', ''), isNull);
    expect(pharmacyUri('http://localhost:8081', ''), isNotNull);
  });
}
