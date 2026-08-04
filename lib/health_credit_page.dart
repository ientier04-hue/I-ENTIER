import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_theme.dart';
import 'health_credit_models.dart';
import 'health_credit_repository.dart';

const _creditBlue = Color(0xFF155EEF);
const _creditNavy = Color(0xFF12315F);
const _creditMint = Color(0xFFE9F8F3);

class HealthCreditPage extends StatefulWidget {
  final String patientId;
  final String patientName;
  final HealthCreditRepository? repository;

  const HealthCreditPage({
    super.key,
    required this.patientId,
    required this.patientName,
    this.repository,
  });

  @override
  State<HealthCreditPage> createState() => _HealthCreditPageState();
}

class _HealthCreditPageState extends State<HealthCreditPage> {
  late final HealthCreditRepository _repository =
      widget.repository ?? SupabaseHealthCreditRepository();
  late Future<HealthCreditDashboardData> _dashboard = _load();
  int _section = 0;

  Future<HealthCreditDashboardData> _load() =>
      _repository.loadDashboard(widget.patientId);

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _dashboard = next);
    await next;
  }

  Future<void> _openApplication() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HealthCreditApplicationScreen(
          patientName: widget.patientName,
          repository: _repository,
        ),
      ),
    );
    if (submitted == true && mounted) {
      setState(() => _section = 0);
      await _refresh();
    }
  }

  Future<void> _openAssessment() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HealthSocialAssessmentScreen(repository: _repository),
      ),
    );
    if (submitted == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppBar(
      title: const Text('Crédit Santé'),
      actions: [
        IconButton(
          tooltip: 'Actualiser',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: FutureBuilder<HealthCreditDashboardData>(
      future: _dashboard,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _creditBlue),
          );
        }
        if (snapshot.hasError) {
          return _CreditError(onRetry: _refresh);
        }
        final data = snapshot.data!;
        return Column(
          children: [
            _CreditSectionBar(
              selected: _section,
              onSelected: (value) => setState(() => _section = value),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  key: PageStorageKey('health-credit-section-$_section'),
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: switch (_section) {
                          0 => _CreditOverview(
                            data: data,
                            onApply: _openApplication,
                            onPayments: () => setState(() => _section = 2),
                          ),
                          1 => _CreditApplicationSection(
                            applications: data.applications,
                            credit: data.credit,
                            onApply: _openApplication,
                          ),
                          2 => _CreditRepaymentSection(
                            data: data,
                            repository: _repository,
                            onChanged: _refresh,
                          ),
                          _ => _CreditSolidaritySection(
                            data: data,
                            repository: _repository,
                            onAssessment: _openAssessment,
                            onChanged: _refresh,
                          ),
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _CreditSectionBar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;

  const _CreditSectionBar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: 0,
            icon: Icon(Icons.dashboard_outlined),
            label: Text('Aperçu'),
          ),
          ButtonSegment(
            value: 1,
            icon: Icon(Icons.request_quote_outlined),
            label: Text('Demande'),
          ),
          ButtonSegment(
            value: 2,
            icon: Icon(Icons.calendar_month_outlined),
            label: Text('Paiements'),
          ),
          ButtonSegment(
            value: 3,
            icon: Icon(Icons.volunteer_activism_outlined),
            label: Text('Solidarité'),
          ),
        ],
        selected: {selected},
        onSelectionChanged: (value) => onSelected(value.first),
      ),
    ),
  );
}

class _CreditOverview extends StatelessWidget {
  final HealthCreditDashboardData data;
  final VoidCallback onApply;
  final VoidCallback onPayments;

  const _CreditOverview({
    required this.data,
    required this.onApply,
    required this.onPayments,
  });

  @override
  Widget build(BuildContext context) {
    final credit = data.credit;
    final latest = data.applications.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_creditNavy, _creditBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: credit == null
              ? _NoCreditHero(application: latest, onApply: onApply)
              : _ActiveCreditHero(credit: credit, onPayments: onPayments),
        ),
        if (credit?.status == 'suspended') ...[
          const SizedBox(height: 16),
          _CreditNotice(
            icon: Icons.lock_clock_outlined,
            color: const Color(0xFFD92D20),
            title: 'Accès temporairement suspendu',
            message: credit!.suspendedUntil == null
                ? 'Des retards répétés nécessitent une régularisation avec l’équipe Crédit Santé.'
                : 'La suspension est prévue jusqu’au ${_date(credit.suspendedUntil!)}. Contactez l’accompagnement pour régulariser.',
          ),
        ],
        const SizedBox(height: 18),
        if (credit != null) ...[
          _CreditPanel(
            title: 'Historique du score',
            subtitle: 'Chaque variation est expliquée et traçable.',
            child: data.scoreEvents.isEmpty
                ? const _EmptyLine('Aucune variation enregistrée.')
                : Column(
                    children: [
                      for (final event in data.scoreEvents.take(6))
                        _ScoreEventTile(event: event),
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          _CreditPanel(
            title: 'Prochaine échéance',
            child: _NextInstallment(
              installment: data.installments
                  .where(
                    (item) => item.status != 'paid' && item.status != 'waived',
                  )
                  .firstOrNull,
              onPayments: onPayments,
            ),
          ),
        ] else ...[
          _CreditNotice(
            icon: Icons.health_and_safety_outlined,
            color: AppColors.teal,
            title: 'Les soins d’abord, le paiement à votre rythme',
            message:
                'Votre capacité financière détermine automatiquement un échéancier réaliste. Aucun crédit n’est accordé sans vérification des références et des justificatifs.',
          ),
        ],
      ],
    );
  }
}

class _NoCreditHero extends StatelessWidget {
  final HealthCreditApplication? application;
  final VoidCallback onApply;

  const _NoCreditHero({required this.application, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final pending =
        application != null &&
        !const {'rejected', 'cancelled'}.contains(application!.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.health_and_safety_rounded,
          color: Color(0xFF8DE6DF),
          size: 42,
        ),
        const SizedBox(height: 18),
        Text(
          pending ? 'Votre demande est en cours' : 'Soignez-vous maintenant',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          pending
              ? '${application!.validatedReferences}/3 références minimum validées. Échéancier estimé : ${application!.recommendedInstallments} mois.'
              : 'Demandez un financement adapté à votre reste à vivre et remboursez en plusieurs échéances.',
          style: const TextStyle(color: Color(0xFFD9E6FF), height: 1.5),
        ),
        if (!pending) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('health-credit-apply'),
            onPressed: onApply,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _creditBlue,
            ),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Faire une demande'),
          ),
        ],
      ],
    );
  }
}

class _ActiveCreditHero extends StatelessWidget {
  final HealthCredit credit;
  final VoidCallback onPayments;

  const _ActiveCreditHero({required this.credit, required this.onPayments});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 82,
            height: 82,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: .3),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${credit.score}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'SCORE',
                  style: TextStyle(
                    color: Color(0xFFBFD0FF),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Score Santé Financier',
                  style: TextStyle(
                    color: Color(0xFFBFD0FF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Risque ${credit.risk.label}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      Text(
        'Solde restant  ${_money(credit.balance)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 10),
      LinearProgressIndicator(
        value: credit.progress,
        minHeight: 8,
        borderRadius: BorderRadius.circular(10),
        backgroundColor: Colors.white.withValues(alpha: .16),
        valueColor: const AlwaysStoppedAnimation(Color(0xFF6DE5DD)),
      ),
      const SizedBox(height: 8),
      Text(
        '${(credit.progress * 100).round()} % remboursé sur ${_money(credit.principal)}',
        style: const TextStyle(color: Color(0xFFD9E6FF), fontSize: 12),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: onPayments,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: _creditBlue,
        ),
        icon: const Icon(Icons.payments_outlined),
        label: const Text('Gérer mes paiements'),
      ),
    ],
  );
}

class _CreditApplicationSection extends StatelessWidget {
  final List<HealthCreditApplication> applications;
  final HealthCredit? credit;
  final VoidCallback onApply;

  const _CreditApplicationSection({
    required this.applications,
    required this.credit,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final openApplication = applications
        .where((item) => !const {'rejected', 'cancelled'}.contains(item.status))
        .firstOrNull;
    final canApply = credit == null && openApplication == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CreditPageTitle(
          icon: Icons.request_quote_outlined,
          title: 'Demande de crédit',
          subtitle:
              'Une analyse transparente de vos revenus, charges, antécédents et références.',
        ),
        const SizedBox(height: 18),
        if (canApply)
          _CreditPanel(
            title: 'Préparer mon dossier',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Requirement(
                  icon: Icons.account_balance_wallet_outlined,
                  text: 'Revenus et dépenses mensuels',
                ),
                const _Requirement(
                  icon: Icons.description_outlined,
                  text: 'Au moins un justificatif de revenus',
                ),
                const _Requirement(
                  icon: Icons.groups_outlined,
                  text: '3 à 5 garants ou références communautaires',
                ),
                const SizedBox(height: 15),
                FilledButton.icon(
                  onPressed: onApply,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Commencer ma demande'),
                ),
              ],
            ),
          )
        else if (openApplication != null)
          _ApplicationStatusCard(application: openApplication)
        else if (credit != null)
          const _CreditNotice(
            icon: Icons.verified_outlined,
            color: AppColors.success,
            title: 'Crédit approuvé',
            message:
                'Votre dossier a été approuvé. Retrouvez les échéances et paiements dans l’onglet Paiements.',
          ),
        if (applications.isNotEmpty) ...[
          const SizedBox(height: 20),
          _CreditPanel(
            title: 'Historique des demandes',
            child: Column(
              children: [
                for (final item in applications)
                  _ApplicationHistoryTile(item: item),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CreditRepaymentSection extends StatelessWidget {
  final HealthCreditDashboardData data;
  final HealthCreditRepository repository;
  final Future<void> Function() onChanged;

  const _CreditRepaymentSection({
    required this.data,
    required this.repository,
    required this.onChanged,
  });

  Future<void> _pay(BuildContext context, HealthCredit credit) async {
    final submitted = await showDialog<bool>(
      context: context,
      builder: (_) => _PaymentDialog(credit: credit, repository: repository),
    );
    if (submitted == true) await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final credit = data.credit;
    if (credit == null) {
      return const _CreditEmpty(
        icon: Icons.calendar_month_outlined,
        title: 'Aucun échéancier',
        message: 'Votre calendrier apparaîtra dès qu’un crédit sera approuvé.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CreditPageTitle(
          icon: Icons.calendar_month_outlined,
          title: 'Remboursements',
          subtitle:
              '${credit.installmentCount} échéances adaptées à votre capacité financière.',
        ),
        const SizedBox(height: 18),
        _CreditPanel(
          title: 'Solde et paiement',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _money(credit.balance),
                style: const TextStyle(
                  color: _creditNavy,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                'Solde restant',
                style: TextStyle(color: AppColors.muted),
              ),
              if (credit.balance > 0 && credit.status != 'defaulted') ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _pay(context, credit),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Paiement partiel ou total'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        _CreditPanel(
          title: 'Calendrier des échéances',
          child: Column(
            children: [
              for (final item in data.installments)
                _InstallmentTile(item: item),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _CreditPanel(
          title: 'Historique des paiements',
          child: data.payments.isEmpty
              ? const _EmptyLine('Aucun paiement déclaré.')
              : Column(
                  children: [
                    for (final item in data.payments)
                      _PaymentTile(payment: item),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CreditSolidaritySection extends StatelessWidget {
  final HealthCreditDashboardData data;
  final HealthCreditRepository repository;
  final VoidCallback onAssessment;
  final Future<void> Function() onChanged;

  const _CreditSolidaritySection({
    required this.data,
    required this.repository,
    required this.onAssessment,
    required this.onChanged,
  });

  Future<void> _request(
    BuildContext context,
    HealthSocialAssessment assessment,
  ) async {
    final submitted = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _SolidarityDialog(assessment: assessment, repository: repository),
    );
    if (submitted == true) await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final assessment = data.assessment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _CreditPageTitle(
          icon: Icons.volunteer_activism_outlined,
          title: 'Soutien aux personnes vulnérables',
          subtitle:
              'Une évaluation sociale confidentielle ouvre l’accès aux soins à faible coût et au Financement Solidaire.',
        ),
        const SizedBox(height: 18),
        if (assessment == null)
          _CreditPanel(
            title: 'Évaluer ma situation',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Répondez à quelques questions sur votre foyer. Le résultat sert uniquement à vous orienter vers les aides adaptées.',
                  style: TextStyle(color: AppColors.muted, height: 1.5),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onAssessment,
                  icon: const Icon(Icons.assignment_ind_outlined),
                  label: const Text('Faire l’évaluation sociale'),
                ),
              ],
            ),
          )
        else ...[
          _VulnerabilityCard(assessment: assessment, onRedo: onAssessment),
          if (assessment.vulnerable) ...[
            const SizedBox(height: 18),
            _CreditPanel(
              title: 'Centres partenaires à faible coût',
              subtitle: 'Contactez le centre avant votre déplacement.',
              child: data.partnerCenters.isEmpty
                  ? const _EmptyLine('Aucun centre disponible pour le moment.')
                  : Column(
                      children: [
                        for (final center in data.partnerCenters)
                          _PartnerCenterTile(center: center),
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            _CreditPanel(
              title: 'Financement Solidaire',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Demandez la couverture de tout ou partie des frais médicaux. Une équipe assurera le suivi jusqu’à la prise en charge.',
                    style: TextStyle(color: AppColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => _request(context, assessment),
                    icon: const Icon(Icons.favorite_outline_rounded),
                    label: const Text('Déposer une demande solidaire'),
                  ),
                ],
              ),
            ),
          ],
        ],
        if (data.solidarityRequests.isNotEmpty) ...[
          const SizedBox(height: 18),
          _CreditPanel(
            title: 'Suivi de l’accompagnement',
            child: Column(
              children: [
                for (final request in data.solidarityRequests)
                  _SolidarityRequestTile(request: request),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class HealthCreditApplicationScreen extends StatefulWidget {
  final String patientName;
  final HealthCreditRepository repository;

  const HealthCreditApplicationScreen({
    super.key,
    required this.patientName,
    required this.repository,
  });

  @override
  State<HealthCreditApplicationScreen> createState() =>
      _HealthCreditApplicationScreenState();
}

class _HealthCreditApplicationScreenState
    extends State<HealthCreditApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  final _income = TextEditingController();
  final _expenses = TextEditingController();
  final _employer = TextEditingController();
  final _references = <_ReferenceControllers>[];
  final _documents = <HealthCreditDocumentDraft>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 3; i++) {
      _references.add(_ReferenceControllers());
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    _income.dispose();
    _expenses.dispose();
    _employer.dispose();
    for (final item in _references) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDocuments() async {
    final files = await ImagePicker().pickMultiImage(
      imageQuality: 82,
      limit: 3,
    );
    if (files.isEmpty) return;
    final next = <HealthCreditDocumentDraft>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      final extension = file.name.split('.').last.toLowerCase();
      final mime = extension == 'png'
          ? 'image/png'
          : extension == 'webp'
          ? 'image/webp'
          : 'image/jpeg';
      next.add(
        HealthCreditDocumentDraft(
          fileName: file.name,
          mimeType: mime,
          bytes: bytes,
        ),
      );
    }
    setState(() {
      _documents
        ..clear()
        ..addAll(next);
    });
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    if (_documents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ajoutez au moins un justificatif de revenus.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.submitApplication(
        HealthCreditApplicationDraft(
          patientName: widget.patientName,
          requestedAmount: _number(_amount.text),
          medicalReason: _reason.text.trim(),
          monthlyIncome: _number(_income.text),
          monthlyExpenses: _number(_expenses.text),
          employer: _employer.text.trim(),
          references: _references.map((item) => item.toDraft()).toList(),
          documents: _documents,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demande transmise pour vérification.')),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La demande n’a pas pu être envoyée. Vérifiez les informations et réessayez.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nouvelle demande')),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 42),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CreditPageTitle(
                    icon: Icons.health_and_safety_outlined,
                    title: 'Votre besoin médical',
                    subtitle:
                        'Les données financières sont chiffrées et utilisées uniquement pour évaluer une mensualité soutenable.',
                  ),
                  const SizedBox(height: 20),
                  _CreditPanel(
                    title: 'Financement demandé',
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _amount,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Montant demandé (HTG)',
                            prefixIcon: Icon(Icons.payments_outlined),
                          ),
                          validator: _positiveValidator,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _reason,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: 2000,
                          decoration: const InputDecoration(
                            labelText: 'Motif médical',
                            alignLabelWithHint: true,
                          ),
                          validator: (value) => (value?.trim().length ?? 0) < 10
                              ? 'Décrivez le besoin médical (10 caractères minimum).'
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _CreditPanel(
                    title: 'Capacité financière mensuelle',
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _income,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Revenus mensuels (HTG)',
                            prefixIcon: Icon(Icons.trending_up_rounded),
                          ),
                          validator: _nonNegativeValidator,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _expenses,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Dépenses mensuelles (HTG)',
                            prefixIcon: Icon(Icons.trending_down_rounded),
                          ),
                          validator: _nonNegativeValidator,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _employer,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Employeur (optionnel)',
                            prefixIcon: Icon(Icons.business_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _CreditPanel(
                    title: 'Justificatifs de revenus',
                    subtitle:
                        'Photo de fiche de paie, attestation ou relevé (3 images maximum).',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _pickDocuments,
                          icon: const Icon(Icons.upload_file_outlined),
                          label: Text(
                            _documents.isEmpty
                                ? 'Ajouter des justificatifs'
                                : '${_documents.length} justificatif(s) sélectionné(s)',
                          ),
                        ),
                        if (_documents.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          for (final item in _documents)
                            Text(
                              '• ${item.fileName}',
                              style: const TextStyle(color: AppColors.muted),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _CreditPanel(
                    title: 'Références (${_references.length}/5)',
                    subtitle:
                        'Ajoutez obligatoirement 3 à 5 garants ou références communautaires.',
                    child: Column(
                      children: [
                        for (var i = 0; i < _references.length; i++) ...[
                          _ReferenceFields(
                            index: i,
                            controllers: _references[i],
                            canRemove: _references.length > 3,
                            onRemove: () => setState(
                              () => _references.removeAt(i).dispose(),
                            ),
                          ),
                          if (i < _references.length - 1)
                            const Divider(height: 30),
                        ],
                        if (_references.length < 5) ...[
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: () => setState(
                              () => _references.add(_ReferenceControllers()),
                            ),
                            icon: const Icon(Icons.person_add_alt_outlined),
                            label: const Text('Ajouter une référence'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    key: const ValueKey('submit-health-credit-application'),
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(
                      _saving ? 'Envoi en cours…' : 'Soumettre ma demande',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class HealthSocialAssessmentScreen extends StatefulWidget {
  final HealthCreditRepository repository;
  const HealthSocialAssessmentScreen({super.key, required this.repository});

  @override
  State<HealthSocialAssessmentScreen> createState() =>
      _HealthSocialAssessmentScreenState();
}

class _HealthSocialAssessmentScreenState
    extends State<HealthSocialAssessmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _income = TextEditingController();
  final _householdSize = TextEditingController(text: '1');
  final _notes = TextEditingController();
  String _housing = 'stable';
  String _stability = 'stable';
  bool _food = false;
  bool _healthExpense = false;
  bool _dependency = false;
  bool _singleParent = false;
  bool _saving = false;

  @override
  void dispose() {
    _income.dispose();
    _householdSize.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _saving = true);
    try {
      await widget.repository.submitSocialAssessment(
        householdIncome: _number(_income.text),
        householdSize: int.parse(_householdSize.text),
        housingStatus: _housing,
        incomeStability: _stability,
        foodInsecurity: _food,
        catastrophicHealthExpense: _healthExpense,
        disabilityOrDependency: _dependency,
        singleParent: _singleParent,
        notes: _notes.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('L’évaluation n’a pas pu être enregistrée.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Évaluation sociale')),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _CreditPanel(
                title: 'Situation du foyer',
                subtitle:
                    'Ces réponses permettent d’identifier les aides les plus adaptées.',
                child: Column(
                  children: [
                    TextFormField(
                      controller: _income,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Revenus mensuels du foyer (HTG)',
                      ),
                      validator: _nonNegativeValidator,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _householdSize,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de personnes dans le foyer',
                      ),
                      validator: (value) {
                        final number = int.tryParse(value ?? '');
                        return number == null || number < 1 || number > 30
                            ? 'Entrez un nombre entre 1 et 30.'
                            : null;
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _housing,
                      decoration: const InputDecoration(
                        labelText: 'Situation de logement',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'stable',
                          child: Text('Logement stable'),
                        ),
                        DropdownMenuItem(
                          value: 'precarious',
                          child: Text('Logement précaire'),
                        ),
                        DropdownMenuItem(
                          value: 'homeless',
                          child: Text('Sans logement'),
                        ),
                      ],
                      onChanged: (value) => setState(() => _housing = value!),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _stability,
                      decoration: const InputDecoration(
                        labelText: 'Stabilité des revenus',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'stable',
                          child: Text('Stables'),
                        ),
                        DropdownMenuItem(
                          value: 'irregular',
                          child: Text('Irréguliers'),
                        ),
                        DropdownMenuItem(
                          value: 'none',
                          child: Text('Aucun revenu'),
                        ),
                      ],
                      onChanged: (value) => setState(() => _stability = value!),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _food,
                      onChanged: (value) => setState(() => _food = value!),
                      title: const Text(
                        'Difficultés à couvrir les besoins alimentaires',
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _healthExpense,
                      onChanged: (value) =>
                          setState(() => _healthExpense = value!),
                      title: const Text(
                        'Les frais médicaux menacent l’équilibre du foyer',
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _dependency,
                      onChanged: (value) =>
                          setState(() => _dependency = value!),
                      title: const Text(
                        'Handicap ou personne dépendante dans le foyer',
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _singleParent,
                      onChanged: (value) =>
                          setState(() => _singleParent = value!),
                      title: const Text('Foyer monoparental'),
                    ),
                    TextFormField(
                      controller: _notes,
                      maxLines: 3,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        labelText: 'Précisions utiles (optionnel)',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: Text(
                          _saving ? 'Évaluation…' : 'Obtenir mon orientation',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ReferenceControllers {
  final name = TextEditingController();
  final phone = TextEditingController();
  final relationship = TextEditingController();
  String type = 'community';

  HealthCreditReferenceDraft toDraft() => HealthCreditReferenceDraft(
    fullName: name.text.trim(),
    phone: phone.text.trim(),
    relationship: relationship.text.trim(),
    type: type,
  );
  void dispose() {
    name.dispose();
    phone.dispose();
    relationship.dispose();
  }
}

class _ReferenceFields extends StatefulWidget {
  final int index;
  final _ReferenceControllers controllers;
  final bool canRemove;
  final VoidCallback onRemove;
  const _ReferenceFields({
    required this.index,
    required this.controllers,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  State<_ReferenceFields> createState() => _ReferenceFieldsState();
}

class _ReferenceFieldsState extends State<_ReferenceFields> {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Référence ${widget.index + 1}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: _creditNavy,
              ),
            ),
          ),
          if (widget.canRemove)
            IconButton(
              onPressed: widget.onRemove,
              tooltip: 'Retirer',
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      TextFormField(
        controller: widget.controllers.name,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Nom complet'),
        validator: (value) =>
            (value?.trim().length ?? 0) < 3 ? 'Nom requis.' : null,
      ),
      const SizedBox(height: 10),
      TextFormField(
        controller: widget.controllers.phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Téléphone'),
        validator: (value) =>
            (value?.trim().length ?? 0) < 8 ? 'Téléphone valide requis.' : null,
      ),
      const SizedBox(height: 10),
      TextFormField(
        controller: widget.controllers.relationship,
        decoration: const InputDecoration(labelText: 'Lien avec vous'),
        validator: (value) =>
            (value?.trim().length ?? 0) < 2 ? 'Précisez le lien.' : null,
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: widget.controllers.type,
        decoration: const InputDecoration(labelText: 'Type de référence'),
        items: const [
          DropdownMenuItem(
            value: 'community',
            child: Text('Référence communautaire'),
          ),
          DropdownMenuItem(value: 'guarantor', child: Text('Garant')),
        ],
        onChanged: (value) => setState(() => widget.controllers.type = value!),
      ),
    ],
  );
}

class _PaymentDialog extends StatefulWidget {
  final HealthCredit credit;
  final HealthCreditRepository repository;
  const _PaymentDialog({required this.credit, required this.repository});
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _key = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  String _method = 'moncash';
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_key.currentState?.validate() != true) return;
    setState(() => _saving = true);
    try {
      await widget.repository.submitPayment(
        creditId: widget.credit.id,
        amount: _number(_amount.text),
        method: _method,
        reference: _reference.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Le paiement n’a pas pu être déclaré.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Déclarer un paiement'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Solde : ${_money(widget.credit.balance)}',
              style: const TextStyle(
                color: _creditNavy,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Montant (HTG)',
                suffixIcon: TextButton(
                  onPressed: () =>
                      _amount.text = widget.credit.balance.toStringAsFixed(2),
                  child: const Text('TOTAL'),
                ),
              ),
              validator: (value) {
                final amount = _number(value ?? '');
                return amount <= 0 || amount > widget.credit.balance
                    ? 'Entrez un montant jusqu’au solde restant.'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Mode de paiement'),
              items: const [
                DropdownMenuItem(value: 'moncash', child: Text('MonCash')),
                DropdownMenuItem(value: 'card', child: Text('Carte')),
                DropdownMenuItem(
                  value: 'bank_transfer',
                  child: Text('Virement bancaire'),
                ),
                DropdownMenuItem(
                  value: 'cash_partner',
                  child: Text('Espèces chez un partenaire'),
                ),
              ],
              onChanged: (value) => setState(() => _method = value!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reference,
              decoration: const InputDecoration(
                labelText: 'Référence de transaction (optionnel)',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Le paiement modifiera votre solde et votre score après confirmation par i-ENTIER.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: _saving ? null : _submit,
        child: Text(_saving ? 'Envoi…' : 'Déclarer'),
      ),
    ],
  );
}

class _SolidarityDialog extends StatefulWidget {
  final HealthSocialAssessment assessment;
  final HealthCreditRepository repository;
  const _SolidarityDialog({required this.assessment, required this.repository});
  @override
  State<_SolidarityDialog> createState() => _SolidarityDialogState();
}

class _SolidarityDialogState extends State<_SolidarityDialog> {
  final _key = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _need = TextEditingController();
  bool _saving = false;
  @override
  void dispose() {
    _amount.dispose();
    _need.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_key.currentState?.validate() != true) return;
    setState(() => _saving = true);
    try {
      await widget.repository.submitSolidarityRequest(
        assessmentId: widget.assessment.id,
        amount: _number(_amount.text),
        medicalNeed: _need.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La demande solidaire n’a pas pu être envoyée.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Financement Solidaire'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Montant nécessaire (HTG)',
              ),
              validator: _positiveValidator,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _need,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Soins à financer',
                alignLabelWithHint: true,
              ),
              validator: (value) => (value?.trim().length ?? 0) < 10
                  ? 'Décrivez les soins nécessaires.'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: _saving ? null : _submit,
        child: Text(_saving ? 'Envoi…' : 'Déposer'),
      ),
    ],
  );
}

class _CreditPanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _CreditPanel({required this.title, this.subtitle, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _creditNavy,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(
            subtitle!,
            style: const TextStyle(color: AppColors.muted, height: 1.4),
          ),
        ],
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

class _CreditPageTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _CreditPageTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: _creditBlue),
      ),
      const SizedBox(width: 13),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _creditNavy,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    ],
  );
}

class _CreditNotice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  const _CreditNotice({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withValues(alpha: .22)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                message,
                style: const TextStyle(color: AppColors.muted, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CreditError extends StatelessWidget {
  final Future<void> Function() onRetry;
  const _CreditError({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 42, color: _creditBlue),
          const SizedBox(height: 12),
          const Text(
            'Impossible de charger Crédit Santé.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    ),
  );
}

class _CreditEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _CreditEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 70),
    child: Column(
      children: [
        Icon(icon, size: 52, color: AppColors.border),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: _creditNavy,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _EmptyLine extends StatelessWidget {
  final String text;
  const _EmptyLine(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: const TextStyle(color: AppColors.muted)),
  );
}

class _Requirement extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Requirement({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Icon(icon, color: AppColors.teal, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ScoreEventTile extends StatelessWidget {
  final HealthScoreEvent event;
  const _ScoreEventTile({required this.event});
  @override
  Widget build(BuildContext context) {
    final positive = event.variation >= 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor:
            (positive ? AppColors.success : Theme.of(context).colorScheme.error)
                .withValues(alpha: .1),
        child: Icon(
          positive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          color: positive
              ? AppColors.success
              : Theme.of(context).colorScheme.error,
        ),
      ),
      title: Text(
        event.reason,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(_date(event.createdAt)),
      trailing: Text(
        '${event.variation > 0 ? '+' : ''}${event.variation}  •  ${event.score}',
        style: TextStyle(
          color: positive
              ? AppColors.success
              : Theme.of(context).colorScheme.error,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _NextInstallment extends StatelessWidget {
  final HealthCreditInstallment? installment;
  final VoidCallback onPayments;
  const _NextInstallment({required this.installment, required this.onPayments});
  @override
  Widget build(BuildContext context) => installment == null
      ? const _EmptyLine('Toutes les échéances sont réglées.')
      : Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${installment!.number}',
                style: const TextStyle(
                  color: _creditBlue,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _money(installment!.remaining),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: _creditNavy,
                    ),
                  ),
                  Text(
                    'Échéance le ${_date(installment!.dueDate)}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onPayments, child: const Text('Voir')),
          ],
        );
}

class _ApplicationStatusCard extends StatelessWidget {
  final HealthCreditApplication application;
  const _ApplicationStatusCard({required this.application});
  @override
  Widget build(BuildContext context) => _CreditPanel(
    title: _applicationStatus(application.status),
    subtitle: 'Soumise le ${_date(application.createdAt)}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: application.validatedReferences / 3,
          minHeight: 8,
          borderRadius: BorderRadius.circular(10),
        ),
        const SizedBox(height: 9),
        Text(
          '${application.validatedReferences} référence(s) validée(s) sur 3 minimum',
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 18,
          runSpacing: 10,
          children: [
            Text('Montant : ${_money(application.requestedAmount)}'),
            Text('${application.recommendedInstallments} échéances estimées'),
            Text('Mensualité : ${_money(application.estimatedInstallment)}'),
          ],
        ),
        if (application.decisionReason.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            application.decisionReason,
            style: const TextStyle(color: Color(0xFFD92D20)),
          ),
        ],
      ],
    ),
  );
}

class _ApplicationHistoryTile extends StatelessWidget {
  final HealthCreditApplication item;
  const _ApplicationHistoryTile({required this.item});
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.description_outlined, color: _creditBlue),
    title: Text(
      _money(item.requestedAmount),
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    subtitle: Text(
      '${_applicationStatus(item.status)} • ${_date(item.createdAt)}',
    ),
    trailing: Text(
      '${item.preliminaryScore}/100',
      style: const TextStyle(
        color: AppColors.muted,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _InstallmentTile extends StatelessWidget {
  final HealthCreditInstallment item;
  const _InstallmentTile({required this.item});
  @override
  Widget build(BuildContext context) {
    final late = item.status == 'late';
    final paid = item.status == 'paid';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor:
            (paid
                    ? AppColors.success
                    : late
                    ? const Color(0xFFD92D20)
                    : _creditBlue)
                .withValues(alpha: .1),
        child: Icon(
          paid
              ? Icons.check_rounded
              : late
              ? Icons.warning_amber_rounded
              : Icons.calendar_today_outlined,
          color: paid
              ? AppColors.success
              : late
              ? const Color(0xFFD92D20)
              : _creditBlue,
        ),
      ),
      title: Text(
        'Échéance ${item.number} • ${_money(item.due)}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${_date(item.dueDate)}${item.paid > 0 ? ' • ${_money(item.paid)} payé' : ''}',
      ),
      trailing: _MiniStatus(
        text: _installmentStatus(item.status),
        danger: late,
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final HealthCreditPayment payment;
  const _PaymentTile({required this.payment});
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.receipt_long_outlined, color: _creditBlue),
    title: Text(
      _money(payment.amount),
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    subtitle: Text(
      '${_paymentMethod(payment.method)} • ${_date(payment.createdAt)}${payment.rejectionReason.isEmpty ? '' : '\n${payment.rejectionReason}'}',
    ),
    isThreeLine: payment.rejectionReason.isNotEmpty,
    trailing: _MiniStatus(
      text: _paymentStatus(payment.status),
      danger: payment.status == 'rejected',
    ),
  );
}

class _VulnerabilityCard extends StatelessWidget {
  final HealthSocialAssessment assessment;
  final VoidCallback onRedo;
  const _VulnerabilityCard({required this.assessment, required this.onRedo});
  @override
  Widget build(BuildContext context) {
    final color = assessment.vulnerable
        ? const Color(0xFFD97706)
        : AppColors.success;
    return _CreditNotice(
      icon: assessment.vulnerable
          ? Icons.support_agent_outlined
          : Icons.verified_user_outlined,
      color: color,
      title: assessment.vulnerable
          ? 'Vulnérabilité reconnue • ${assessment.score}/100'
          : 'Niveau de vulnérabilité faible • ${assessment.score}/100',
      message: assessment.vulnerable
          ? 'Vous êtes éligible à une orientation vers nos centres partenaires, au Financement Solidaire et à un accompagnement social et médical.'
          : 'Le Crédit Santé classique reste accessible selon l’évaluation financière. Vous pouvez refaire l’évaluation si votre situation change.',
    );
  }
}

class _PartnerCenterTile extends StatelessWidget {
  final HealthPartnerCenter center;
  const _PartnerCenterTile({required this.center});
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const CircleAvatar(
      backgroundColor: _creditMint,
      child: Icon(Icons.local_hospital_outlined, color: AppColors.success),
    ),
    title: Text(
      center.name,
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    subtitle: Text(
      '${center.address}, ${center.commune}\n${center.services}${center.phone.isEmpty ? '' : '\n${center.phone}'}',
    ),
    isThreeLine: true,
  );
}

class _SolidarityRequestTile extends StatelessWidget {
  final HealthSolidarityRequest request;
  const _SolidarityRequestTile({required this.request});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _creditMint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _money(request.requestedAmount),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _creditNavy,
                ),
              ),
            ),
            _MiniStatus(text: _solidarityStatus(request.status)),
          ],
        ),
        const SizedBox(height: 7),
        Text(request.medicalNeed, maxLines: 2, overflow: TextOverflow.ellipsis),
        if (request.fundedAmount > 0)
          Text(
            'Financé : ${_money(request.fundedAmount)}',
            style: const TextStyle(
              color: AppColors.success,
              fontWeight: FontWeight.w800,
            ),
          ),
        if (request.socialWorker.isNotEmpty ||
            request.medicalCoordinator.isNotEmpty) ...[
          const Divider(),
          Text(
            'Accompagnement : ${[request.socialWorker, request.medicalCoordinator].where((v) => v.isNotEmpty).join(' • ')}',
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
        if (request.followUpNote.isNotEmpty)
          Text(
            request.followUpNote,
            style: const TextStyle(color: AppColors.muted),
          ),
      ],
    ),
  );
}

class _MiniStatus extends StatelessWidget {
  final String text;
  final bool danger;
  const _MiniStatus({required this.text, this.danger = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: (danger ? const Color(0xFFD92D20) : _creditBlue).withValues(
        alpha: .08,
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: danger ? const Color(0xFFD92D20) : _creditBlue,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

double _number(String value) =>
    double.tryParse(value.trim().replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
String? _positiveValidator(String? value) =>
    _number(value ?? '') <= 0 ? 'Entrez un montant supérieur à zéro.' : null;
String? _nonNegativeValidator(String? value) =>
    value == null || value.trim().isEmpty || _number(value) < 0
    ? 'Entrez un montant valide.'
    : null;
String _money(double amount) {
  final fixed = amount.toStringAsFixed(
    amount == amount.roundToDouble() ? 0 : 2,
  );
  final parts = fixed.split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ' ',
  );
  return '${parts.length == 1 ? grouped : '$grouped.${parts.last}'} HTG';
}

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
String _applicationStatus(String value) => switch (value) {
  'pending_references' => 'Validation des références',
  'under_review' => 'Analyse du dossier',
  'approved' => 'Approuvée',
  'rejected' => 'Non approuvée',
  'cancelled' => 'Annulée',
  _ => value,
};
String _installmentStatus(String value) => switch (value) {
  'upcoming' => 'À venir',
  'due' => 'Aujourd’hui',
  'partial' => 'Partiel',
  'paid' => 'Payée',
  'late' => 'En retard',
  'waived' => 'Dispensée',
  _ => value,
};
String _paymentStatus(String value) => switch (value) {
  'pending' => 'À confirmer',
  'confirmed' => 'Confirmé',
  'rejected' => 'Rejeté',
  'cancelled' => 'Annulé',
  _ => value,
};
String _paymentMethod(String value) => switch (value) {
  'moncash' => 'MonCash',
  'card' => 'Carte',
  'bank_transfer' => 'Virement',
  'cash_partner' => 'Espèces partenaire',
  _ => value,
};
String _solidarityStatus(String value) => switch (value) {
  'pending' => 'En étude',
  'approved' => 'Approuvé',
  'partially_funded' => 'Partiellement financé',
  'funded' => 'Financé',
  'in_care' => 'Soins en cours',
  'completed' => 'Pris en charge',
  'rejected' => 'Non retenu',
  _ => value,
};
