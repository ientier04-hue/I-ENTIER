import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _primary = Color(0xFF176BFF);
const _primarySoft = Color(0xFFEAF1FF);
const _navy = Color(0xFF102A56);
const _muted = Color(0xFF667085);
const _border = Color(0xFFE4EAF2);

enum HealthMetric { bloodPressure, bloodGlucose, weight, temperature, oxygen }

extension HealthMetricDetails on HealthMetric {
  String get id => switch (this) {
    HealthMetric.bloodPressure => 'bloodPressure',
    HealthMetric.bloodGlucose => 'bloodGlucose',
    HealthMetric.weight => 'weight',
    HealthMetric.temperature => 'temperature',
    HealthMetric.oxygen => 'oxygen',
  };

  String get label => switch (this) {
    HealthMetric.bloodPressure => 'Tension artérielle',
    HealthMetric.bloodGlucose => 'Glycémie',
    HealthMetric.weight => 'Poids',
    HealthMetric.temperature => 'Température',
    HealthMetric.oxygen => 'Saturation O₂',
  };

  String get shortLabel => switch (this) {
    HealthMetric.bloodPressure => 'Tension',
    HealthMetric.bloodGlucose => 'Glycémie',
    HealthMetric.weight => 'Poids',
    HealthMetric.temperature => 'Température',
    HealthMetric.oxygen => 'O₂',
  };

  String get unit => switch (this) {
    HealthMetric.bloodPressure => 'mmHg',
    HealthMetric.bloodGlucose => 'mg/dL',
    HealthMetric.weight => 'kg',
    HealthMetric.temperature => '°C',
    HealthMetric.oxygen => '%',
  };

  String get valueLabel => switch (this) {
    HealthMetric.bloodPressure => 'Systolique',
    HealthMetric.bloodGlucose => 'Glycémie',
    HealthMetric.weight => 'Poids',
    HealthMetric.temperature => 'Température',
    HealthMetric.oxygen => 'Saturation',
  };

  String get example => switch (this) {
    HealthMetric.bloodPressure => '120',
    HealthMetric.bloodGlucose => '95',
    HealthMetric.weight => '70',
    HealthMetric.temperature => '37,0',
    HealthMetric.oxygen => '98',
  };

  double get minimum => switch (this) {
    HealthMetric.bloodPressure => 40,
    HealthMetric.bloodGlucose => 10,
    HealthMetric.weight => 1,
    HealthMetric.temperature => 25,
    HealthMetric.oxygen => 50,
  };

  double get maximum => switch (this) {
    HealthMetric.bloodPressure => 300,
    HealthMetric.bloodGlucose => 1000,
    HealthMetric.weight => 500,
    HealthMetric.temperature => 45,
    HealthMetric.oxygen => 100,
  };

  IconData get icon => switch (this) {
    HealthMetric.bloodPressure => Icons.favorite_outline_rounded,
    HealthMetric.bloodGlucose => Icons.water_drop_outlined,
    HealthMetric.weight => Icons.monitor_weight_outlined,
    HealthMetric.temperature => Icons.thermostat_rounded,
    HealthMetric.oxygen => Icons.air_rounded,
  };

  Color get color => switch (this) {
    HealthMetric.bloodPressure => const Color(0xFFE94C65),
    HealthMetric.bloodGlucose => const Color(0xFF8B5CF6),
    HealthMetric.weight => const Color(0xFF176BFF),
    HealthMetric.temperature => const Color(0xFFF79009),
    HealthMetric.oxygen => const Color(0xFF0A9F8F),
  };

  static HealthMetric? fromId(String value) {
    for (final metric in HealthMetric.values) {
      if (metric.id == value) return metric;
    }
    return null;
  }
}

class HealthTrackingPage extends StatefulWidget {
  final String patientId;

  const HealthTrackingPage({super.key, required this.patientId});

  @override
  State<HealthTrackingPage> createState() => _HealthTrackingPageState();
}

class _HealthTrackingPageState extends State<HealthTrackingPage> {
  HealthMetric? _filter;

  CollectionReference<Map<String, dynamic>> get _measurements =>
      FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.patientId)
          .collection('healthMeasurements');

  Future<void> _openMeasurementForm() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MeasurementForm(measurements: _measurements),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mesure enregistrée avec succès.')),
      );
    }
  }

  Future<void> _deleteMeasurement(_HealthMeasurement measurement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette mesure ?'),
        content: Text(
          '${measurement.metric.label} · ${measurement.displayValue}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _measurements.doc(measurement.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Mesure supprimée.')));
      }
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de supprimer la mesure.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _TrackingHeader(onAdd: _openMeasurementForm),
      const SizedBox(height: 18),
      const _PrivacyNotice(),
      const SizedBox(height: 24),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _measurements
            .orderBy('measuredAt', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _TrackingFeedback(
              icon: Icons.lock_outline_rounded,
              title: 'Suivi indisponible',
              message:
                  'La lecture de vos mesures est momentanément impossible.',
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 52),
              child: Center(child: CircularProgressIndicator(color: _primary)),
            );
          }

          final measurements = snapshot.data!.docs
              .map(_HealthMeasurement.fromFirestore)
              .whereType<_HealthMeasurement>()
              .toList();
          if (measurements.isEmpty) {
            return _TrackingFeedback(
              icon: Icons.monitor_heart_outlined,
              title: 'Commencez votre suivi',
              message:
                  'Enregistrez votre première mesure pour la retrouver ici.',
              actionLabel: 'Ajouter une mesure',
              onAction: _openMeasurementForm,
            );
          }

          final latest = <HealthMetric, _HealthMeasurement>{};
          for (final measurement in measurements) {
            latest.putIfAbsent(measurement.metric, () => measurement);
          }
          final filtered = _filter == null
              ? measurements
              : measurements
                    .where((measurement) => measurement.metric == _filter)
                    .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dernières mesures',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 12),
              _LatestMeasurements(latest: latest),
              const SizedBox(height: 28),
              const Text(
                'Historique',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 12),
              _MetricFilters(
                selected: _filter,
                onSelected: (metric) => setState(() => _filter = metric),
              ),
              const SizedBox(height: 14),
              if (filtered.isEmpty)
                const _TrackingFeedback(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'Aucune mesure pour ce filtre',
                  message: 'Choisissez un autre type ou ajoutez une mesure.',
                )
              else
                for (var index = 0; index < filtered.length; index++) ...[
                  _MeasurementTile(
                    measurement: filtered[index],
                    onDelete: () => _deleteMeasurement(filtered[index]),
                  ),
                  if (index != filtered.length - 1) const SizedBox(height: 10),
                ],
            ],
          );
        },
      ),
    ],
  );
}

class _TrackingHeader extends StatelessWidget {
  final VoidCallback onAdd;

  const _TrackingHeader({required this.onAdd});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 520;
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Suivi santé',
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              color: _navy,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'Consignez vos constantes et suivez leur évolution.',
            style: TextStyle(color: _muted),
          ),
        ],
      );
      final button = FilledButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle mesure'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        ),
      );
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [title, const SizedBox(height: 16), button],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: title),
          const SizedBox(width: 20),
          button,
        ],
      );
    },
  );
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _primarySoft,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFD6E4FF)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, color: _primary, size: 22),
        SizedBox(width: 11),
        Expanded(
          child: Text(
            'Ces données sont privées et liées à votre compte. Ce suivi ne '
            'remplace pas l’avis d’un professionnel de santé.',
            style: TextStyle(color: _navy, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _LatestMeasurements extends StatelessWidget {
  final Map<HealthMetric, _HealthMeasurement> latest;

  const _LatestMeasurements({required this.latest});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 12.0;
      final columns = constraints.maxWidth >= 900
          ? 5
          : constraints.maxWidth >= 580
          ? 3
          : 2;
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final metric in HealthMetric.values)
            SizedBox(
              width: width,
              child: _LatestMeasurementCard(
                metric: metric,
                measurement: latest[metric],
              ),
            ),
        ],
      );
    },
  );
}

class _LatestMeasurementCard extends StatelessWidget {
  final HealthMetric metric;
  final _HealthMeasurement? measurement;

  const _LatestMeasurementCard({required this.metric, this.measurement});

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 142),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: metric.color.withValues(alpha: .11),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(metric.icon, color: metric.color, size: 20),
        ),
        const SizedBox(height: 12),
        Text(
          metric.shortLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          measurement?.displayValue ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (measurement != null) ...[
          const SizedBox(height: 4),
          Text(
            _shortDate(measurement!.measuredAt),
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ],
    ),
  );
}

class _MetricFilters extends StatelessWidget {
  final HealthMetric? selected;
  final ValueChanged<HealthMetric?> onSelected;

  const _MetricFilters({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        ChoiceChip(
          label: const Text('Tout'),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final metric in HealthMetric.values) ...[
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(metric.shortLabel),
            selected: selected == metric,
            onSelected: (_) => onSelected(metric),
          ),
        ],
      ],
    ),
  );
}

class _MeasurementTile extends StatelessWidget {
  final _HealthMeasurement measurement;
  final VoidCallback onDelete;

  const _MeasurementTile({required this.measurement, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final metric = measurement.metric;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 7, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: metric.color.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(metric.icon, color: metric.color, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  style: const TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _fullDate(measurement.measuredAt),
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                if (measurement.details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    measurement.details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            measurement.displayValue,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: _navy,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Options',
            onSelected: (value) {
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded),
                    SizedBox(width: 10),
                    Text('Supprimer'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackingFeedback extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _TrackingFeedback({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _border),
    ),
    child: Column(
      children: [
        Icon(icon, color: _primary, size: 38),
        const SizedBox(height: 11),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _navy,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, height: 1.4),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded),
            label: Text(actionLabel!),
          ),
        ],
      ],
    ),
  );
}

class _MeasurementForm extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> measurements;

  const _MeasurementForm({required this.measurements});

  @override
  State<_MeasurementForm> createState() => _MeasurementFormState();
}

class _MeasurementFormState extends State<_MeasurementForm> {
  final _formKey = GlobalKey<FormState>();
  final _valueController = TextEditingController();
  final _secondaryValueController = TextEditingController();
  final _pulseController = TextEditingController();
  final _noteController = TextEditingController();
  HealthMetric _metric = HealthMetric.bloodPressure;
  DateTime _measuredAt = DateTime.now();
  String _glucoseContext = 'Non précisé';
  bool _saving = false;

  static const _glucoseContexts = [
    'Non précisé',
    'À jeun',
    'Avant repas',
    'Après repas',
    'Au coucher',
  ];

  @override
  void dispose() {
    _valueController.dispose();
    _secondaryValueController.dispose();
    _pulseController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double? _number(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  String? _validatePrimary(String? value) {
    final number = _number(value ?? '');
    if (number == null ||
        number < _metric.minimum ||
        number > _metric.maximum) {
      return 'Entrez une valeur entre ${_plainNumber(_metric.minimum)} et '
          '${_plainNumber(_metric.maximum)}.';
    }
    return null;
  }

  String? _validateSecondary(String? value) {
    if (_metric != HealthMetric.bloodPressure) return null;
    final number = _number(value ?? '');
    if (number == null || number < 20 || number > 200) {
      return 'Entrez une valeur entre 20 et 200.';
    }
    return null;
  }

  String? _validatePulse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final number = _number(value);
    if (number == null || number < 20 || number > 250) {
      return 'Entrez une valeur entre 20 et 250.';
    }
    return null;
  }

  void _changeMetric(HealthMetric metric) {
    setState(() {
      _metric = metric;
      _valueController.clear();
      _secondaryValueController.clear();
      _pulseController.clear();
    });
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _measuredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    setState(() {
      _measuredAt = DateTime(
        date.year,
        date.month,
        date.day,
        _measuredAt.hour,
        _measuredAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_measuredAt),
    );
    if (time == null || !mounted) return;
    final candidate = DateTime(
      _measuredAt.year,
      _measuredAt.month,
      _measuredAt.day,
      time.hour,
      time.minute,
    );
    setState(() {
      _measuredAt = candidate.isAfter(DateTime.now())
          ? DateTime.now()
          : candidate;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final pulse = _number(_pulseController.text);
    final secondary = _number(_secondaryValueController.text);
    try {
      await widget.measurements.add({
        'kind': _metric.id,
        'value': _number(_valueController.text),
        if (_metric == HealthMetric.bloodPressure) 'secondaryValue': secondary,
        'pulseBpm': ?pulse,
        'unit': _metric.unit,
        if (_metric == HealthMetric.bloodGlucose &&
            _glucoseContext != 'Non précisé')
          'context': _glucoseContext,
        if (_noteController.text.trim().isNotEmpty)
          'note': _noteController.text.trim(),
        'measuredAt': Timestamp.fromDate(_measuredAt),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context, true);
    } on FirebaseException {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enregistrement impossible. Vérifiez votre connexion et réessayez.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      constraints: const BoxConstraints(maxWidth: 720),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFD),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD0D5DD),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Nouvelle mesure',
                      style: TextStyle(
                        color: _navy,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const _FormLabel('Type de mesure'),
              DropdownButtonFormField<HealthMetric>(
                initialValue: _metric,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.add_chart),
                ),
                items: [
                  for (final metric in HealthMetric.values)
                    DropdownMenuItem(value: metric, child: Text(metric.label)),
                ],
                onChanged: _saving
                    ? null
                    : (metric) {
                        if (metric != null) _changeMetric(metric);
                      },
              ),
              const SizedBox(height: 18),
              if (_metric == HealthMetric.bloodPressure)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _NumberField(
                        controller: _valueController,
                        label: 'Systolique',
                        hint: '120',
                        suffix: 'mmHg',
                        validator: _validatePrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _NumberField(
                        controller: _secondaryValueController,
                        label: 'Diastolique',
                        hint: '80',
                        suffix: 'mmHg',
                        validator: _validateSecondary,
                      ),
                    ),
                  ],
                )
              else
                _NumberField(
                  controller: _valueController,
                  label: _metric.valueLabel,
                  hint: _metric.example,
                  suffix: _metric.unit,
                  validator: _validatePrimary,
                ),
              if (_metric == HealthMetric.bloodPressure ||
                  _metric == HealthMetric.oxygen) ...[
                const SizedBox(height: 18),
                _NumberField(
                  controller: _pulseController,
                  label: 'Pouls (optionnel)',
                  hint: '72',
                  suffix: 'bpm',
                  validator: _validatePulse,
                ),
              ],
              if (_metric == HealthMetric.bloodGlucose) ...[
                const SizedBox(height: 18),
                const _FormLabel('Contexte'),
                DropdownButtonFormField<String>(
                  initialValue: _glucoseContext,
                  items: [
                    for (final context in _glucoseContexts)
                      DropdownMenuItem(value: context, child: Text(context)),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _glucoseContext = value);
                          }
                        },
                ),
              ],
              const SizedBox(height: 18),
              const _FormLabel('Date et heure'),
              Row(
                children: [
                  Expanded(
                    child: _DateTimeButton(
                      icon: Icons.calendar_today_outlined,
                      label: _dateOnly(_measuredAt),
                      onTap: _saving ? null : _pickDate,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateTimeButton(
                      icon: Icons.schedule_rounded,
                      label: _timeOnly(_measuredAt),
                      onTap: _saving ? null : _pickTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const _FormLabel('Note (optionnelle)'),
              TextFormField(
                controller: _noteController,
                enabled: !_saving,
                maxLength: 300,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Ex. après une marche, avant le petit-déjeuner…',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 17),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormLabel extends StatelessWidget {
  final String text;

  const _FormLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(color: _navy, fontWeight: FontWeight.w800),
    ),
  );
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final String suffix;
  final String? Function(String?) validator;

  const _NumberField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.suffix,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _FormLabel(label),
      TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
        ],
        decoration: InputDecoration(hintText: hint, suffixText: suffix),
        validator: validator,
      ),
    ],
  );
}

class _DateTimeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _DateTimeButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Ink(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: _primary, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}

class _HealthMeasurement {
  final String id;
  final HealthMetric metric;
  final double value;
  final double? secondaryValue;
  final double? pulseBpm;
  final String context;
  final String note;
  final DateTime measuredAt;

  const _HealthMeasurement({
    required this.id,
    required this.metric,
    required this.value,
    required this.measuredAt,
    this.secondaryValue,
    this.pulseBpm,
    this.context = '',
    this.note = '',
  });

  static _HealthMeasurement? fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final metric = HealthMetricDetails.fromId(data['kind']?.toString() ?? '');
    final value = data['value'];
    final measuredAt = data['measuredAt'];
    if (metric == null || value is! num || measuredAt is! Timestamp) {
      return null;
    }
    final secondary = data['secondaryValue'];
    final pulse = data['pulseBpm'];
    return _HealthMeasurement(
      id: document.id,
      metric: metric,
      value: value.toDouble(),
      secondaryValue: secondary is num ? secondary.toDouble() : null,
      pulseBpm: pulse is num ? pulse.toDouble() : null,
      context: data['context']?.toString() ?? '',
      note: data['note']?.toString() ?? '',
      measuredAt: measuredAt.toDate(),
    );
  }

  String get displayValue {
    if (metric == HealthMetric.bloodPressure && secondaryValue != null) {
      return '${_plainNumber(value)}/${_plainNumber(secondaryValue!)} '
          '${metric.unit}';
    }
    return '${_plainNumber(value)} ${metric.unit}';
  }

  String get details => [
    if (pulseBpm != null) 'Pouls ${_plainNumber(pulseBpm!)} bpm',
    if (context.isNotEmpty) context,
    if (note.isNotEmpty) note,
  ].join(' · ');
}

const _months = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _plainNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1).replaceAll('.', ',');

String _dateOnly(DateTime date) =>
    '${_twoDigits(date.day)}/${_twoDigits(date.month)}/${date.year}';

String _timeOnly(DateTime date) =>
    '${_twoDigits(date.hour)}:${_twoDigits(date.minute)}';

String _shortDate(DateTime date) => '${date.day} ${_months[date.month - 1]}';

String _fullDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year} à ${_timeOnly(date)}';
