import 'package:flutter/material.dart';

import 'cycle_personal_context.dart';

String cycleLifeStageLabel(CycleLifeStage stage) => switch (stage) {
  CycleLifeStage.unspecified => 'Non renseigné',
  CycleLifeStage.menstruating => 'Cycles menstruels',
  CycleLifeStage.pregnant => 'Grossesse',
  CycleLifeStage.postpartum => 'Post-partum',
  CycleLifeStage.perimenopause => 'Périménopause',
  CycleLifeStage.menopause => 'Ménopause',
};

String cycleContraceptionLabel(CycleContraception value) => switch (value) {
  CycleContraception.unspecified => 'Non renseignée',
  CycleContraception.none => 'Aucune',
  CycleContraception.nonHormonal => 'Non hormonale',
  CycleContraception.hormonal => 'Hormonale',
};

class CycleContextForm extends StatefulWidget {
  final CyclePersonalContext initialContext;
  final DateTime today;
  final Future<void> Function(CyclePersonalContext) onSave;
  const CycleContextForm({
    super.key,
    required this.initialContext,
    required this.today,
    required this.onSave,
  });

  @override
  State<CycleContextForm> createState() => _CycleContextFormState();
}

class _CycleContextFormState extends State<CycleContextForm> {
  late CycleLifeStage _stage = widget.initialContext.lifeStage;
  late CycleContraception _contraception = widget.initialContext.contraception;
  late bool _breastfeeding = widget.initialContext.breastfeeding;
  late bool _pcos = widget.initialContext.hasPcos;
  late DateTime? _since = widget.initialContext.historyStart;
  bool _saving = false;
  String? _error;

  CyclePersonalContext get _value => CyclePersonalContext(
    lifeStage: _stage,
    contraception: _contraception,
    breastfeeding: _breastfeeding,
    hasPcos: _pcos,
    historyStart: _since,
  );

  void _change(VoidCallback action) => setState(() {
    action();
    // Recording a previously unspecified natural context need not erase history.
    // A transition from an existing context starts a fresh observation segment.
    final previous = widget.initialContext;
    if (!_value.hasSamePhysiology(previous) &&
        (previous.lifeStage != CycleLifeStage.unspecified ||
            previous.contraception != CycleContraception.unspecified ||
            previous.breastfeeding ||
            previous.hasPcos ||
            _value.suspensionReason != null ||
            _value.needsMoreHistory)) {
      _since = widget.today;
    } else if (_value.hasSamePhysiology(previous)) {
      _since = previous.historyStart;
    }
    _error = null;
  });

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _since ?? widget.today,
      firstDate: DateTime(1900),
      lastDate: widget.today,
      helpText: 'Début de ce contexte',
      cancelText: 'Annuler',
      confirmText: 'Choisir',
    );
    if (picked != null && mounted) setState(() => _since = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_value);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Enregistrement impossible. Réessayez.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        22,
        22,
        22,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Mon contexte',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Fermer',
                onPressed: _saving ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<CycleLifeStage>(
            key: const Key('cycle-context-stage'),
            initialValue: _stage,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Situation actuelle'),
            items: [
              for (final value in CycleLifeStage.values)
                DropdownMenuItem(
                  value: value,
                  child: Text(cycleLifeStageLabel(value)),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) => _change(() => _stage = value!),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<CycleContraception>(
            key: const Key('cycle-context-contraception'),
            initialValue: _contraception,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Contraception'),
            items: [
              for (final value in CycleContraception.values)
                DropdownMenuItem(
                  value: value,
                  child: Text(cycleContraceptionLabel(value)),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) => _change(() => _contraception = value!),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            key: const Key('cycle-context-breastfeeding'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Allaitement'),
            value: _breastfeeding,
            onChanged: _saving
                ? null
                : (value) => _change(() => _breastfeeding = value),
          ),
          SwitchListTile.adaptive(
            key: const Key('cycle-context-pcos'),
            contentPadding: EdgeInsets.zero,
            title: const Text('SOPK diagnostiqué'),
            value: _pcos,
            onChanged: _saving ? null : (value) => _change(() => _pcos = value),
          ),
          ListTile(
            key: const Key('cycle-context-since'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Début de ce contexte'),
            subtitle: Text(
              _since == null
                  ? 'Non renseigné'
                  : '${_since!.day}/${_since!.month}/${_since!.year}',
            ),
            trailing: const Icon(Icons.calendar_month_outlined),
            onTap: _saving ? null : _pickDate,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('cycle-save-context'),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
          ),
        ],
      ),
    ),
  );
}
