import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'patient_vault.dart';
import 'vault_card.dart';
import 'vault_schema.dart';

class PatientVaultPage extends StatefulWidget {
  final SupabaseClient client;
  const PatientVaultPage({super.key, required this.client});
  @override
  State<PatientVaultPage> createState() => _PatientVaultPageState();
}

class _PatientVaultPageState extends State<PatientVaultPage> {
  late final vault = PatientVault(widget.client);
  List<Map<String, dynamic>> _appointments = [], _grants = [], _events = [];
  final _groups = <String>{'Profil médical'};
  String? _appointment, _code, _error;
  int _minutes = 30;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _run(_load);
  }

  Future<void> _load() async {
    final client = widget.client;
    _appointments = await client
        .schema('ientier')
        .from('appointments')
        .select(
          'appointment_id,provider_id,provider_name_snapshot,scheduled_at',
        )
        .eq('patient_id', vault.userId)
        .inFilter('status', ['pending', 'confirmed'])
        .order('scheduled_at', ascending: false)
        .limit(100);
    _grants = await client
        .schema('ientier')
        .from('vault_grants')
        .select('grant_id,provider_id,appointment_id,expires_at,revoked_at')
        .eq('patient_id', vault.userId)
        .order('created_at', ascending: false)
        .limit(100);
    _events = await client
        .schema('ientier')
        .from('vault_access_events')
        .select('action,created_at,actor_id')
        .eq('patient_id', vault.userId)
        .order('created_at', ascending: false)
        .limit(30);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      await action();
    } catch (_) {
      _error = 'Opération impossible. Réessayez.';
    }
    if (mounted) setState(() => _busy = false);
  }

  String _date(dynamic value) {
    final d = DateTime.parse(value.toString()).toLocal();
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Mon coffre'),
      actions: [
        IconButton(
          tooltip: 'Actualiser',
          onPressed: _busy ? null : () => _run(_load),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      await Printing.sharePdf(
                        bytes: await buildVaultCard(vault.recovery),
                        filename: 'carte-privee-ientier.pdf',
                      );
                    }),
              icon: const Icon(Icons.download),
              label: const Text('Télécharger ma carte privée'),
            ),
            const SizedBox(height: 28),
            Text(
              'Autoriser une consultation',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _appointment,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Professionnel et rendez-vous',
              ),
              items: _appointments
                  .map(
                    (a) => DropdownMenuItem(
                      value: a['appointment_id'] as String,
                      child: Text(
                        '${a['provider_name_snapshot']} · ${_date(a['scheduled_at'])}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _busy ? null : (v) => setState(() => _appointment = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _minutes,
              decoration: const InputDecoration(labelText: 'Durée'),
              items: const [
                DropdownMenuItem(value: 15, child: Text('15 minutes')),
                DropdownMenuItem(value: 30, child: Text('30 minutes')),
                DropdownMenuItem(value: 60, child: Text('1 heure')),
                DropdownMenuItem(value: 120, child: Text('2 heures')),
                DropdownMenuItem(value: 1440, child: Text('24 heures')),
              ],
              onChanged: _busy ? null : (v) => setState(() => _minutes = v!),
            ),
            const SizedBox(height: 12),
            for (final group in vaultShareGroups.keys)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(group),
                value: _groups.contains(group),
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                        v! ? _groups.add(group) : _groups.remove(group);
                      }),
              ),
            FilledButton(
              onPressed: _busy || _appointment == null || _groups.isEmpty
                  ? null
                  : () => _run(() async {
                      final a = _appointments.firstWhere(
                        (r) => r['appointment_id'] == _appointment,
                      );
                      _code = await vault.authorize(
                        providerId: a['provider_id'],
                        appointmentId: _appointment!,
                        groups: _groups,
                        minutes: _minutes,
                      );
                      await _load();
                    }),
              child: const Text('Autoriser'),
            ),
            if (_code != null) ...[
              const SizedBox(height: 20),
              const Text('Code à transmettre au professionnel'),
              const SizedBox(height: 8),
              SelectableText(
                _code!,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              TextButton(
                onPressed: () => setState(() => _code = null),
                child: const Text('Masquer'),
              ),
            ],
            const SizedBox(height: 28),
            Text(
              'Autorisations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final grant in _grants)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _appointments
                          .where(
                            (a) =>
                                a['appointment_id'] == grant['appointment_id'],
                          )
                          .map((a) => a['provider_name_snapshot'].toString())
                          .firstOrNull ??
                      'Professionnel',
                ),
                subtitle: Text(
                  grant['revoked_at'] != null
                      ? 'Révoquée'
                      : 'Jusqu’au ${_date(grant['expires_at'])}',
                ),
                trailing:
                    grant['revoked_at'] != null ||
                        DateTime.parse(
                          grant['expires_at'],
                        ).isBefore(DateTime.now())
                    ? null
                    : TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await widget.client
                                    .schema('ientier')
                                    .rpc(
                                      'vault_revoke',
                                      params: {'p_grant_id': grant['grant_id']},
                                    );
                                _code = null;
                                await _load();
                              }),
                        child: const Text('Révoquer'),
                      ),
              ),
            const SizedBox(height: 20),
            Text('Historique', style: Theme.of(context).textTheme.titleLarge),
            for (final event in _events)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(switch (event['action']) {
                  'read' => 'Dossier consulté',
                  'revoked' => 'Accès révoqué',
                  'document' => 'Document reçu',
                  _ => 'Accès autorisé',
                }),
                subtitle: Text(_date(event['created_at'])),
              ),
            if (_busy) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
  );
}
