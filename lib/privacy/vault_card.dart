import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'vault_crypto.dart';

/// Generated entirely on the patient's device. No network fonts, remote QR
/// service, or server-side PDF rendering may be used here.
Future<Uint8List> buildVaultCard(VaultRecovery card) async {
  final doc = pw.Document(title: 'Carte privée i-ENTIER', author: 'i-ENTIER');
  final code = card.code;
  final lines = [
    for (var i = 0; i < code.length; i += 42)
      code.substring(i, (i + 42).clamp(0, code.length)),
  ];
  doc.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(
        85.60 * PdfPageFormat.mm,
        53.98 * PdfPageFormat.mm,
      ),
      margin: const pw.EdgeInsets.all(11),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'i-ENTIER',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#143C65'),
                ),
              ),
              pw.Text('CARTE PRIVÉE', style: const pw.TextStyle(fontSize: 7)),
            ],
          ),
          pw.SizedBox(height: 7),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                color: PdfColors.white,
                padding: const pw.EdgeInsets.all(4),
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: code,
                  width: 69,
                  height: 69,
                  drawText: false,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Clé du dossier',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.Spacer(),
          pw.Text(
            lines.join('\n'),
            style: pw.TextStyle(
              font: pw.Font.courier(),
              fontSize: 5.6,
              lineSpacing: 1,
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
