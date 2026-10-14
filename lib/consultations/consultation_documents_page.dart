import '../privacy/vault_table.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'consultation_document_view.dart';
import 'consultation_repository.dart';

class ConsultationDocumentsPage extends StatefulWidget {
  final String patientId;
  final String? appointmentId, documentId, prescriptionId;
  final ConsultationKind? kind;
  final Future<List<ConsultationDocument>> Function()? loader;
  const ConsultationDocumentsPage({
    super.key,
    required this.patientId,
    this.appointmentId,
    this.documentId,
    this.prescriptionId,
    this.kind,
    this.loader,
  });

  @override
  State<ConsultationDocumentsPage> createState() =>
      _ConsultationDocumentsPageState();
}

class _ConsultationDocumentsPageState extends State<ConsultationDocumentsPage> {
  late Future<List<ConsultationDocument>> _documents = _load();

  Future<List<ConsultationDocument>> _load() async {
    if (widget.loader != null) return widget.loader!();
    final client = Supabase.instance.client;
    if (widget.patientId.isEmpty ||
        client.auth.currentUser?.id != widget.patientId) {
      throw StateError('Session requise');
    }
    var query = VaultTable(client, 'consultation_documents')
        .select(
          'document_id,patient_name,provider_name,kind,payload,created_at',
        )
        .eq('patient_id', widget.patientId);
    if (widget.appointmentId != null) {
      query = query.eq('appointment_id', widget.appointmentId!);
    }
    if (widget.documentId != null) {
      query = query.eq('document_id', widget.documentId!);
    }
    if (widget.prescriptionId != null) {
      query = query.eq('prescription_id', widget.prescriptionId!);
    }
    if (widget.kind != null) query = query.eq('kind', widget.kind!.name);
    final rows = await query
        .order('created_at', ascending: false)
        .limit(100)
        .timeout(const Duration(seconds: 20));
    if (client.auth.currentUser?.id != widget.patientId) {
      throw StateError('Session terminée');
    }
    return rows.map(ConsultationDocument.fromJson).toList();
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _documents = future;
    });
    try {
      await future;
    } catch (_) {
      /* The view exposes retry. */
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F7FB),
    appBar: AppBar(
      title: Text(
        widget.kind == ConsultationKind.exams
            ? 'Examens prescrits'
            : 'Mes consultations',
      ),
      actions: [
        IconButton(
          tooltip: 'Actualiser',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<ConsultationDocument>>(
        future: _documents,
        builder: (context, snapshot) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (snapshot.hasError) ...[
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Documents indisponibles',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Réessayer'),
                        ),
                      ),
                    ] else if (snapshot.data!.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Aucun document',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      for (final document in snapshot.data!)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0xFFE1E9F1)),
                          ),
                          child: ExpansionTile(
                            key: ValueKey(document.id),
                            initiallyExpanded:
                                widget.documentId != null ||
                                widget.prescriptionId != null ||
                                snapshot.data!.length == 1,
                            shape: const Border(),
                            collapsedShape: const Border(),
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFE5F3F4),
                              child: Icon(
                                consultationIcon(document.kind),
                                color: const Color(0xFF087F8C),
                              ),
                            ),
                            title: Text(
                              document.kind == ConsultationKind.prescription
                                  ? 'Ordonnance'
                                  : document.kind.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '${document.providerName}\n${consultationDate(context, document.createdAt)}',
                                style: const TextStyle(height: 1.5),
                              ),
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              20,
                              4,
                              20,
                              20,
                            ),
                            children: [
                              ConsultationDocumentView(
                                kind: document.kind,
                                payload: document.payload,
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
