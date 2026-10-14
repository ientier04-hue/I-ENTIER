import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'patient_vault.dart';
import 'vault_card.dart';
import 'vault_crypto.dart';

class VaultGate extends StatefulWidget {
  final SupabaseClient client;
  final Widget child;
  const VaultGate({super.key, required this.client, required this.child});
  @override
  State<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends State<VaultGate> {
  late final vault = PatientVault(widget.client);
  final _code = TextEditingController();
  VaultRecovery? _newCard;
  bool _loading = true, _exists = true, _busy = false, _downloaded = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    _newCard?.destroy();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _exists = await vault.metadata() != null;
      if (_exists) await vault.restoreDevice();
      if (vault.unlocked) await vault.removeLegacyFiles();
      if (!_exists) _newCard = VaultRecovery.create(vault.userId);
    } catch (_) {
      _error = 'Accès au coffre impossible. Réessayez.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      _code.clear();
    } catch (_) {
      _error = 'Opération impossible. Vérifiez votre carte et votre connexion.';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return StreamBuilder<void>(
      stream: vault.changes.stream,
      builder: (context, _) {
        if (vault.unlocked && _error == null) return widget.child;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Mon coffre'),
            actions: [
              IconButton(
                tooltip: 'Déconnexion',
                onPressed: _busy ? null : () => widget.client.auth.signOut(),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.lock_outline, size: 48),
                    const SizedBox(height: 24),
                    if (!_exists && _newCard != null) ...[
                      AspectRatio(
                        aspectRatio: 85.60 / 53.98,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xff143c65),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'i-ENTIER',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Spacer(),
                              Icon(Icons.key, color: Colors.white, size: 30),
                              SizedBox(height: 12),
                              Text(
                                'CARTE PRIVÉE',
                                style: TextStyle(
                                  color: Colors.white,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                final saved = await Printing.sharePdf(
                                  bytes: await buildVaultCard(_newCard!),
                                  filename: 'carte-privee-ientier.pdf',
                                );
                                if (saved) _downloaded = true;
                              }),
                        icon: const Icon(Icons.download),
                        label: const Text('Télécharger ma carte'),
                      ),
                      if (_downloaded) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _code,
                          autocorrect: false,
                          enableSuggestions: false,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText:
                                '6 derniers caractères du code de la carte',
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  final code = _newCard!.code;
                                  if (_code.text.trim() !=
                                      code.substring(code.length - 6)) {
                                    throw const FormatException();
                                  }
                                  await vault.activate(_newCard!);
                                }),
                          child: const Text('Activer mon coffre'),
                        ),
                      ],
                    ] else ...[
                      TextField(
                        controller: _code,
                        autocorrect: false,
                        enableSuggestions: false,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Code de ma carte privée',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await vault.unlock(_code.text);
                                await vault.removeLegacyFiles();
                              }),
                        child: const Text('Déverrouiller'),
                      ),
                    ],
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                setState(() {
                                  _loading = true;
                                  _error = null;
                                });
                                _load();
                              },
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
