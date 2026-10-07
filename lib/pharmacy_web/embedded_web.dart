import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class EmbeddedPharmacy extends StatelessWidget {
  final Uri uri;
  const EmbeddedPharmacy({super.key, required this.uri});

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      final frame = element as web.HTMLIFrameElement;
      frame
        ..src = uri.toString()
        ..title = 'Pharmacie'
        ..allow = 'camera; geolocation'
        ..referrerPolicy = 'no-referrer';
      frame.style
        ..border = '0'
        ..width = '100%'
        ..height = '100%';
    },
  );
}
