import 'package:flutter/material.dart';
import 'consultation_repository.dart';

IconData consultationIcon(ConsultationKind kind) => switch (kind) {
  ConsultationKind.diagnosis => Icons.assignment_outlined,
  ConsultationKind.prescription => Icons.medication_outlined,
  ConsultationKind.exams => Icons.biotech_rounded,
  ConsultationKind.followup => Icons.event_available_outlined,
};

String consultationDate(BuildContext context, DateTime date) {
  final local = date.toLocal();
  final l = MaterialLocalizations.of(context);
  return '${l.formatMediumDate(local)} · ${l.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: true)}';
}

class ConsultationDocumentView extends StatelessWidget {
  final ConsultationKind kind;
  final Map<String, dynamic> payload;
  const ConsultationDocumentView({
    super.key,
    required this.kind,
    required this.payload,
  });

  @override
  Widget build(BuildContext context) {
    String text(String key) => payload[key]?.toString().trim() ?? '';
    Widget field(String title, String value) => value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  value,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    height: 1.5,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          );
    final entries = (payload['items'] as List? ?? const []).cast<Map>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kind == ConsultationKind.diagnosis) ...[
          field('Diagnostic', text('diagnosis')),
          field('Symptômes', text('symptoms')),
          field('Observations cliniques', text('observations')),
          field('Conduite à tenir', text('plan')),
        ],
        if (kind == ConsultationKind.prescription) ...[
          for (var i = 0; i < entries.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: .12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}. ${entries[i]['medication_name']}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    '${entries[i]['dosage']} · ${entries[i]['frequency']} · ${entries[i]['duration_days']} jours',
                    style: const TextStyle(height: 1.5),
                  ),
                  if (entries[i]['administration_route']
                          ?.toString()
                          .isNotEmpty ??
                      false)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        entries[i]['administration_route'].toString(),
                      ),
                    ),
                  if (entries[i]['instructions']?.toString().isNotEmpty ??
                      false)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SelectableText(
                        entries[i]['instructions'].toString(),
                      ),
                    ),
                ],
              ),
            ),
          field('Consignes', text('notes')),
        ],
        if (kind == ConsultationKind.exams) ...[
          if (text('priority') == 'urgent')
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Urgent',
                style: TextStyle(
                  color: Color(0xFFB94432),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          field('Indication', text('indication')),
          for (final item in entries)
            field(
              item['name'].toString(),
              (item['instructions']?.toString().trim().isNotEmpty ?? false)
                  ? item['instructions'].toString()
                  : 'À réaliser',
            ),
        ],
        if (kind == ConsultationKind.followup) ...[
          field(
            'Date et heure',
            DateTime.tryParse(text('scheduled_at')) == null
                ? ''
                : consultationDate(
                    context,
                    DateTime.parse(text('scheduled_at')),
                  ),
          ),
          field('Consultation', switch (text('mode')) {
            'video' => 'Vidéo',
            'homeVisit' => 'À domicile',
            _ => 'Sur place',
          }),
          field('Lieu', text('location')),
          field('Note', text('note')),
        ],
      ],
    );
  }
}
