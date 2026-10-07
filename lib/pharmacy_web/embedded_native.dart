import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:image_picker/image_picker.dart';

class EmbeddedPharmacy extends StatefulWidget {
  final Uri uri;
  const EmbeddedPharmacy({super.key, required this.uri});
  @override
  State<EmbeddedPharmacy> createState() => _EmbeddedPharmacyState();
}

class _EmbeddedPharmacyState extends State<EmbeddedPharmacy> {
  WebViewController? _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (!const [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ].contains(defaultTargetPlatform)) {
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null &&
                uri.hasAuthority &&
                uri.origin == widget.uri.origin) {
              return NavigationDecision.navigate;
            }
            if (uri != null && const ['https', 'tel'].contains(uri.scheme)) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            return NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _failed = false;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() {
                _failed = true;
                _loading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(widget.uri);
    final platform = _controller!.platform;
    if (platform is AndroidWebViewController) {
      platform.setOnShowFileSelector((params) async {
        final image = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        return image == null ? <String>[] : [Uri.file(image.path).toString()];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return Center(
        child: FilledButton(
          onPressed: () =>
              launchUrl(widget.uri, mode: LaunchMode.externalApplication),
          child: const Text('Ouvrir la pharmacie'),
        ),
      );
    }
    return Stack(
      children: [
        WebViewWidget(controller: controller),
        if (_loading) const LinearProgressIndicator(),
        if (_failed)
          ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Pharmacie indisponible'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => controller.loadRequest(widget.uri),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
