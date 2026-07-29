import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'supabase_config.dart';

const _crowdfundingGreen = Color(0xFF087A5B);
const _crowdfundingGreenDark = Color(0xFF075D47);
const _crowdfundingSoft = Color(0xFFE9F8F3);
const _crowdfundingGold = Color(0xFFF2A900);
const _crowdfundingIconAsset = 'assets/services/crowdfunding_3d.png';

enum CrowdfundingCategory {
  all,
  emergency,
  surgery,
  treatment,
  medication,
  maternity,
  rehabilitation,
  other,
}

extension CrowdfundingCategoryDetails on CrowdfundingCategory {
  String get storageValue => switch (this) {
    CrowdfundingCategory.all => '',
    CrowdfundingCategory.emergency => 'emergency',
    CrowdfundingCategory.surgery => 'surgery',
    CrowdfundingCategory.treatment => 'treatment',
    CrowdfundingCategory.medication => 'medication',
    CrowdfundingCategory.maternity => 'maternity',
    CrowdfundingCategory.rehabilitation => 'rehabilitation',
    CrowdfundingCategory.other => 'other',
  };

  String get label => switch (this) {
    CrowdfundingCategory.all => 'Toutes',
    CrowdfundingCategory.emergency => 'Urgence',
    CrowdfundingCategory.surgery => 'Chirurgie',
    CrowdfundingCategory.treatment => 'Traitement',
    CrowdfundingCategory.medication => 'Médicaments',
    CrowdfundingCategory.maternity => 'Maternité',
    CrowdfundingCategory.rehabilitation => 'Réadaptation',
    CrowdfundingCategory.other => 'Autre',
  };

  IconData get icon => switch (this) {
    CrowdfundingCategory.all => Icons.grid_view_rounded,
    CrowdfundingCategory.emergency => Icons.emergency_outlined,
    CrowdfundingCategory.surgery => Icons.medical_services_outlined,
    CrowdfundingCategory.treatment => Icons.healing_outlined,
    CrowdfundingCategory.medication => Icons.medication_outlined,
    CrowdfundingCategory.maternity => Icons.pregnant_woman_rounded,
    CrowdfundingCategory.rehabilitation => Icons.accessibility_new_rounded,
    CrowdfundingCategory.other => Icons.favorite_outline_rounded,
  };

  static CrowdfundingCategory fromStorage(Object? value) =>
      CrowdfundingCategory.values.firstWhere(
        (category) => category.storageValue == value?.toString(),
        orElse: () => CrowdfundingCategory.other,
      );
}

enum CrowdfundingPaymentMethod { moncash, card, bankTransfer }

extension CrowdfundingPaymentMethodDetails on CrowdfundingPaymentMethod {
  String get storageValue => switch (this) {
    CrowdfundingPaymentMethod.moncash => 'moncash',
    CrowdfundingPaymentMethod.card => 'card',
    CrowdfundingPaymentMethod.bankTransfer => 'bank_transfer',
  };

  String get label => switch (this) {
    CrowdfundingPaymentMethod.moncash => 'MonCash',
    CrowdfundingPaymentMethod.card => 'Carte',
    CrowdfundingPaymentMethod.bankTransfer => 'Virement',
  };

  IconData get icon => switch (this) {
    CrowdfundingPaymentMethod.moncash => Icons.phone_android_rounded,
    CrowdfundingPaymentMethod.card => Icons.credit_card_rounded,
    CrowdfundingPaymentMethod.bankTransfer => Icons.account_balance_outlined,
  };
}

class CrowdfundingCampaign {
  final String id;
  final String creatorId;
  final String beneficiaryName;
  final String title;
  final String story;
  final CrowdfundingCategory category;
  final String medicalFacility;
  final String location;
  final double targetAmount;
  final double raisedAmount;
  final int contributorCount;
  final String currency;
  final DateTime deadline;
  final String coverImageUrl;
  final String status;
  final String verificationStatus;
  final String rejectionReason;
  final bool featured;
  final DateTime? createdAt;

  const CrowdfundingCampaign({
    required this.id,
    required this.creatorId,
    required this.beneficiaryName,
    required this.title,
    required this.story,
    required this.category,
    required this.medicalFacility,
    required this.location,
    required this.targetAmount,
    required this.raisedAmount,
    required this.contributorCount,
    required this.currency,
    required this.deadline,
    required this.status,
    required this.verificationStatus,
    this.coverImageUrl = '',
    this.rejectionReason = '',
    this.featured = false,
    this.createdAt,
  });

  factory CrowdfundingCampaign.fromRow(Map<String, dynamic> row) {
    String text(String key) => row[key]?.toString().trim() ?? '';
    double amount(String key) => row[key] is num
        ? (row[key] as num).toDouble()
        : double.tryParse(text(key)) ?? 0;
    DateTime date(String key) =>
        DateTime.tryParse(text(key))?.toLocal() ?? DateTime.now();

    return CrowdfundingCampaign(
      id: text('campaign_id'),
      creatorId: text('creator_id'),
      beneficiaryName: text('beneficiary_name'),
      title: text('title'),
      story: text('story'),
      category: CrowdfundingCategoryDetails.fromStorage(row['category']),
      medicalFacility: text('medical_facility'),
      location: text('location'),
      targetAmount: amount('target_amount'),
      raisedAmount: amount('raised_amount'),
      contributorCount: row['contributor_count'] is num
          ? (row['contributor_count'] as num).toInt()
          : int.tryParse(text('contributor_count')) ?? 0,
      currency: text('currency').isEmpty ? 'HTG' : text('currency'),
      deadline: date('deadline'),
      coverImageUrl: text('cover_image_url'),
      status: text('status'),
      verificationStatus: text('verification_status'),
      rejectionReason: text('rejection_reason'),
      featured: row['featured'] == true,
      createdAt: DateTime.tryParse(text('created_at'))?.toLocal(),
    );
  }

  double get progress => targetAmount <= 0
      ? 0
      : (raisedAmount / targetAmount).clamp(0, 1).toDouble();

  int daysRemaining(DateTime now) {
    final remaining = deadline.difference(now).inDays;
    return remaining < 0 ? 0 : remaining;
  }

  bool get acceptsContributions =>
      status == 'active' &&
      verificationStatus == 'approved' &&
      deadline.isAfter(DateTime.now());

  bool isOwnedBy(String userId) => creatorId == userId;
}

class CrowdfundingCampaignDraft {
  final String beneficiaryName;
  final String relationshipToPatient;
  final String title;
  final String story;
  final CrowdfundingCategory category;
  final String medicalFacility;
  final String location;
  final String contactPhone;
  final double targetAmount;
  final String currency;
  final DateTime deadline;
  final bool consentToPublish;

  const CrowdfundingCampaignDraft({
    required this.beneficiaryName,
    required this.relationshipToPatient,
    required this.title,
    required this.story,
    required this.category,
    required this.medicalFacility,
    required this.location,
    required this.contactPhone,
    required this.targetAmount,
    required this.currency,
    required this.deadline,
    required this.consentToPublish,
  });
}

class CrowdfundingContributionReceipt {
  final String id;
  final double amount;
  final String currency;
  final CrowdfundingPaymentMethod paymentMethod;

  const CrowdfundingContributionReceipt({
    required this.id,
    required this.amount,
    required this.currency,
    required this.paymentMethod,
  });
}

abstract class CrowdfundingRepository {
  Stream<List<CrowdfundingCampaign>> watchCampaigns();

  Future<String> submitCampaign(CrowdfundingCampaignDraft draft);

  Future<CrowdfundingContributionReceipt> startContribution({
    required CrowdfundingCampaign campaign,
    required double amount,
    required CrowdfundingPaymentMethod paymentMethod,
    required String publicName,
    required bool anonymous,
    required String message,
  });
}

class SupabaseCrowdfundingRepository implements CrowdfundingRepository {
  final SupabaseClient client;

  SupabaseCrowdfundingRepository({SupabaseClient? client})
    : client = client ?? SupabaseConfig.client;

  @override
  Stream<List<CrowdfundingCampaign>> watchCampaigns() => client
      .schema('ientier')
      .from('crowdfunding_campaigns')
      .stream(primaryKey: ['campaign_id'])
      .order('created_at', ascending: false)
      .limit(250)
      .asyncMap((rows) async {
        final privateRows = List<Map<String, dynamic>>.from(
          await client
              .schema('ientier')
              .from('crowdfunding_campaign_contacts')
              .select('campaign_id,creator_id'),
        );
        final owners = {
          for (final row in privateRows)
            row['campaign_id']?.toString() ?? '':
                row['creator_id']?.toString() ?? '',
        };
        final campaigns = rows
            .map(
              (row) => CrowdfundingCampaign.fromRow({
                ...row,
                'creator_id': owners[row['campaign_id']?.toString()] ?? '',
              }),
            )
            .toList(growable: false);
        campaigns.sort((a, b) {
          if (a.featured != b.featured) return a.featured ? -1 : 1;
          if (a.status == 'active' && b.status != 'active') return -1;
          if (a.status != 'active' && b.status == 'active') return 1;
          return (b.createdAt ?? DateTime(1970)).compareTo(
            a.createdAt ?? DateTime(1970),
          );
        });
        return campaigns;
      });

  @override
  Future<String> submitCampaign(CrowdfundingCampaignDraft draft) async {
    final response = await client
        .schema('ientier')
        .rpc(
          'submit_crowdfunding_campaign',
          params: {
            'p_beneficiary_name': draft.beneficiaryName,
            'p_relationship_to_patient': draft.relationshipToPatient,
            'p_title': draft.title,
            'p_story': draft.story,
            'p_category': draft.category.storageValue,
            'p_medical_facility': draft.medicalFacility,
            'p_location': draft.location,
            'p_contact_phone': draft.contactPhone,
            'p_target_amount': draft.targetAmount,
            'p_currency': draft.currency,
            'p_deadline': draft.deadline.toUtc().toIso8601String(),
            'p_cover_image_url': null,
            'p_consent_to_publish': draft.consentToPublish,
          },
        );
    return response.toString();
  }

  @override
  Future<CrowdfundingContributionReceipt> startContribution({
    required CrowdfundingCampaign campaign,
    required double amount,
    required CrowdfundingPaymentMethod paymentMethod,
    required String publicName,
    required bool anonymous,
    required String message,
  }) async {
    final response = await client
        .schema('ientier')
        .rpc(
          'start_crowdfunding_contribution',
          params: {
            'p_campaign_id': campaign.id,
            'p_amount': amount,
            'p_payment_method': paymentMethod.storageValue,
            'p_public_name': publicName,
            'p_anonymous': anonymous,
            'p_message': message,
          },
        );
    return CrowdfundingContributionReceipt(
      id: response.toString(),
      amount: amount,
      currency: campaign.currency,
      paymentMethod: paymentMethod,
    );
  }
}

class CrowdfundingPage extends StatefulWidget {
  final String userId;
  final String userDisplayName;
  final Map<String, dynamic> patientProfile;
  final CrowdfundingRepository? repository;
  final DateTime? now;

  const CrowdfundingPage({
    super.key,
    required this.userId,
    required this.userDisplayName,
    this.patientProfile = const {},
    this.repository,
    this.now,
  });

  @override
  State<CrowdfundingPage> createState() => _CrowdfundingPageState();
}

class _CrowdfundingPageState extends State<CrowdfundingPage> {
  final _searchController = TextEditingController();
  CrowdfundingRepository? _repository;
  late Stream<List<CrowdfundingCampaign>> _campaigns;
  CrowdfundingCategory _category = CrowdfundingCategory.all;
  String _query = '';

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _resolveRepository();
  }

  void _resolveRepository() {
    _repository =
        widget.repository ??
        (SupabaseConfig.isInitialized
            ? SupabaseCrowdfundingRepository()
            : null);
    _campaigns =
        _repository?.watchCampaigns() ??
        Stream.value(const <CrowdfundingCampaign>[]);
  }

  @override
  void didUpdateWidget(covariant CrowdfundingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) _resolveRepository();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createCampaign() async {
    final repository = _repository;
    if (repository == null) {
      _showUnavailable();
      return;
    }
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CreateCampaignSheet(
        repository: repository,
        initialBeneficiaryName: widget.userDisplayName,
        initialPhone: widget.patientProfile['phone']?.toString() ?? '',
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Campagne envoyée. Elle sera visible après vérification.',
          ),
        ),
      );
    }
  }

  Future<void> _contribute(CrowdfundingCampaign campaign) async {
    final repository = _repository;
    if (repository == null) {
      _showUnavailable();
      return;
    }
    final receipt = await showModalBottomSheet<CrowdfundingContributionReceipt>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _ContributionSheet(
        repository: repository,
        campaign: campaign,
        publicName: widget.userDisplayName,
      ),
    );
    if (receipt == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _ContributionReceiptDialog(receipt: receipt),
    );
  }

  void _showUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Le service sera disponible dès la connexion à Supabase.',
        ),
      ),
    );
  }

  List<CrowdfundingCampaign> _filter(List<CrowdfundingCampaign> campaigns) {
    final query = _query.trim().toLowerCase();
    return campaigns
        .where((campaign) {
          final categoryMatches =
              _category == CrowdfundingCategory.all ||
              campaign.category == _category;
          final queryMatches =
              query.isEmpty ||
              '${campaign.title} ${campaign.beneficiaryName} ${campaign.location} '
                      '${campaign.medicalFacility} ${campaign.story}'
                  .toLowerCase()
                  .contains(query);
          return categoryMatches && queryMatches;
        })
        .toList(growable: false);
  }

  void _openCampaign(CrowdfundingCampaign campaign) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _CampaignDetailsPage(
          campaign: campaign,
          now: _now,
          ownedByUser: campaign.isOwnedBy(widget.userId),
          onContribute: () => _contribute(campaign),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppBar(
      title: const Text('Financement solidaire'),
      actions: [
        IconButton(
          key: const Key('crowdfunding-create'),
          tooltip: 'Créer une campagne',
          onPressed: _createCampaign,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
        const SizedBox(width: 6),
      ],
    ),
    body: StreamBuilder<List<CrowdfundingCampaign>>(
      stream: _campaigns,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _crowdfundingGreen),
          );
        }
        if (snapshot.hasError) return const _CrowdfundingError();
        final campaigns = _filter(snapshot.data ?? const []);
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _CrowdfundingHero(onCreate: _createCampaign),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          key: const Key('crowdfunding-search'),
                          controller: _searchController,
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                            hintText: 'Rechercher une campagne...',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Effacer',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _query = '');
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final category
                                  in CrowdfundingCategory.values) ...[
                                ChoiceChip(
                                  key: Key(
                                    'crowdfunding-category-${category.storageValue}',
                                  ),
                                  avatar: Icon(category.icon, size: 17),
                                  label: Text(category.label),
                                  selected: _category == category,
                                  onSelected: (_) =>
                                      setState(() => _category = category),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Campagnes solidaires',
                                style: TextStyle(
                                  color: AppColors.navy,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -.4,
                                ),
                              ),
                            ),
                            Text(
                              '${campaigns.length}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (campaigns.isEmpty)
              const SliverToBoxAdapter(child: _EmptyCampaigns())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final columns = width >= 1050
                        ? 3
                        : width >= 690
                        ? 2
                        : 1;
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        mainAxisExtent: 390,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final campaign = campaigns[index];
                        return _CampaignCard(
                          campaign: campaign,
                          now: _now,
                          ownedByUser: campaign.isOwnedBy(widget.userId),
                          onTap: () => _openCampaign(campaign),
                          onContribute: campaign.acceptsContributions
                              ? () => _contribute(campaign)
                              : null,
                        );
                      }, childCount: campaigns.length),
                    );
                  },
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _CrowdfundingHero extends StatelessWidget {
  final VoidCallback onCreate;

  const _CrowdfundingHero({required this.onCreate});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF075D47), Color(0xFF0A8F77)],
      ),
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 34),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final copy = Column(
                crossAxisAlignment: wide
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  if (!wide) ...[
                    Image.asset(
                      _crowdfundingIconAsset,
                      width: 96,
                      height: 96,
                      fit: BoxFit.contain,
                      semanticLabel:
                          'Icône 3D de financement solidaire pour la santé',
                    ),
                    const SizedBox(height: 14),
                  ],
                  const Text(
                    'SOLIDARITÉ SANTÉ',
                    style: TextStyle(
                      color: Color(0xFFA9F0D8),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Ensemble, rendons les soins possibles.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      height: 1.12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Soutenez une campagne médicale vérifiée ou demandez l’aide de la communauté.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFD7F4EA),
                      height: 1.5,
                      fontSize: 15,
                    ),
                  ),
                  if (!wide) ...[
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const Key('crowdfunding-hero-create'),
                      onPressed: onCreate,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _crowdfundingGreenDark,
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Créer une campagne'),
                    ),
                  ],
                ],
              );
              if (!wide) return copy;
              return Row(
                children: [
                  Image.asset(
                    _crowdfundingIconAsset,
                    width: 132,
                    height: 132,
                    fit: BoxFit.contain,
                    semanticLabel:
                        'Icône 3D de financement solidaire pour la santé',
                  ),
                  const SizedBox(width: 28),
                  Expanded(child: copy),
                  const SizedBox(width: 30),
                  FilledButton.icon(
                    key: const Key('crowdfunding-hero-create'),
                    onPressed: onCreate,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _crowdfundingGreenDark,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 18,
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Créer une campagne'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _CampaignCard extends StatelessWidget {
  final CrowdfundingCampaign campaign;
  final DateTime now;
  final bool ownedByUser;
  final VoidCallback onTap;
  final VoidCallback? onContribute;

  const _CampaignCard({
    required this.campaign,
    required this.now,
    required this.ownedByUser,
    required this.onTap,
    required this.onContribute,
  });

  @override
  Widget build(BuildContext context) => Card(
    key: Key('crowdfunding-campaign-${campaign.id}'),
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CampaignVisual(campaign: campaign, height: 116),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    children: [
                      _CampaignPill(
                        icon: campaign.category.icon,
                        label: campaign.category.label,
                        color: _crowdfundingGreen,
                      ),
                      if (campaign.featured)
                        const _CampaignPill(
                          icon: Icons.star_rounded,
                          label: 'À la une',
                          color: _crowdfundingGold,
                        ),
                      if (ownedByUser && campaign.status != 'active')
                        _CampaignPill(
                          icon: Icons.schedule_rounded,
                          label: _campaignStatusLabel(campaign),
                          color: AppColors.warning,
                        ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Text(
                    campaign.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 17,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Pour ${campaign.beneficiaryName} • ${campaign.location}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12.5,
                    ),
                  ),
                  const Spacer(),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: campaign.progress,
                      color: _crowdfundingGreen,
                      backgroundColor: _crowdfundingSoft,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _money(campaign.raisedAmount, campaign.currency),
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        'sur ${_money(campaign.targetAmount, campaign.currency)}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.people_outline_rounded,
                        size: 17,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${campaign.contributorCount} soutien${campaign.contributorCount > 1 ? 's' : ''}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${campaign.daysRemaining(now)} j restants',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (onContribute != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onContribute,
                        style: FilledButton.styleFrom(
                          backgroundColor: _crowdfundingGreen,
                        ),
                        child: const Text('Contribuer'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CampaignVisual extends StatelessWidget {
  final CrowdfundingCampaign campaign;
  final double height;

  const _CampaignVisual({required this.campaign, required this.height});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      height: height,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFD8F4EA), Color(0xFFF5FCF9)],
        ),
      ),
      child: Icon(campaign.category.icon, size: 52, color: _crowdfundingGreen),
    );
    if (campaign.coverImageUrl.isEmpty) return fallback;
    return Image.network(
      campaign.coverImageUrl,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class _CampaignPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CampaignPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _CampaignDetailsPage extends StatelessWidget {
  final CrowdfundingCampaign campaign;
  final DateTime now;
  final bool ownedByUser;
  final VoidCallback onContribute;

  const _CampaignDetailsPage({
    required this.campaign,
    required this.now,
    required this.ownedByUser,
    required this.onContribute,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppBar(title: const Text('Détails de la campagne')),
    bottomNavigationBar: campaign.acceptsContributions
        ? SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: FilledButton.icon(
                key: const Key('crowdfunding-detail-contribute'),
                onPressed: onContribute,
                style: FilledButton.styleFrom(
                  backgroundColor: _crowdfundingGreen,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.volunteer_activism_rounded),
                label: const Text('Contribuer à cette campagne'),
              ),
            ),
          )
        : null,
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: _CampaignVisual(campaign: campaign, height: 230),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CampaignPill(
                    icon: campaign.category.icon,
                    label: campaign.category.label,
                    color: _crowdfundingGreen,
                  ),
                  if (campaign.verificationStatus == 'approved')
                    const _CampaignPill(
                      icon: Icons.verified_rounded,
                      label: 'Vérifiée par i-ENTIER',
                      color: AppColors.primary,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                campaign.title,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 29,
                  height: 1.13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Pour ${campaign.beneficiaryName} • ${campaign.location}',
                style: const TextStyle(color: AppColors.muted, fontSize: 15),
              ),
              const SizedBox(height: 24),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          minHeight: 11,
                          value: campaign.progress,
                          color: _crowdfundingGreen,
                          backgroundColor: _crowdfundingSoft,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _money(campaign.raisedAmount, campaign.currency),
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'collectés sur ${_money(campaign.targetAmount, campaign.currency)}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _Metric(
                              value: '${campaign.contributorCount}',
                              label: 'soutiens',
                            ),
                          ),
                          Expanded(
                            child: _Metric(
                              value: '${campaign.daysRemaining(now)}',
                              label: 'jours restants',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (ownedByUser && campaign.status != 'active') ...[
                const SizedBox(height: 18),
                _OwnerCampaignNotice(campaign: campaign),
              ],
              const SizedBox(height: 26),
              const Text(
                'L’histoire',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                campaign.story,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 15,
                  height: 1.65,
                ),
              ),
              if (campaign.medicalFacility.isNotEmpty) ...[
                const SizedBox(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: _crowdfundingSoft,
                    foregroundColor: _crowdfundingGreen,
                    child: Icon(Icons.local_hospital_outlined),
                  ),
                  title: const Text('Établissement de soins'),
                  subtitle: Text(campaign.medicalFacility),
                ),
              ],
              const SizedBox(height: 18),
              const _TrustNotice(),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;

  const _Metric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
      Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
    ],
  );
}

class _OwnerCampaignNotice extends StatelessWidget {
  final CrowdfundingCampaign campaign;

  const _OwnerCampaignNotice({required this.campaign});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E8),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFF5DCA7)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: AppColors.warning),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            campaign.rejectionReason.isNotEmpty
                ? 'Cette campagne doit être corrigée : ${campaign.rejectionReason}'
                : 'Votre campagne est ${_campaignStatusLabel(campaign).toLowerCase()}. '
                      'Elle ne reçoit pas encore de contributions.',
            style: const TextStyle(color: AppColors.ink, height: 1.45),
          ),
        ),
      ],
    ),
  );
}

class _TrustNotice extends StatelessWidget {
  const _TrustNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _crowdfundingSoft,
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, color: _crowdfundingGreen),
        SizedBox(width: 11),
        Expanded(
          child: Text(
            'i-ENTIER vérifie la campagne avant publication. Une intention de '
            'contribution n’est comptabilisée qu’après confirmation du paiement.',
            style: TextStyle(color: _crowdfundingGreenDark, height: 1.45),
          ),
        ),
      ],
    ),
  );
}

class _CreateCampaignSheet extends StatefulWidget {
  final CrowdfundingRepository repository;
  final String initialBeneficiaryName;
  final String initialPhone;

  const _CreateCampaignSheet({
    required this.repository,
    required this.initialBeneficiaryName,
    required this.initialPhone,
  });

  @override
  State<_CreateCampaignSheet> createState() => _CreateCampaignSheetState();
}

class _CreateCampaignSheetState extends State<_CreateCampaignSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _beneficiaryController = TextEditingController(
    text: widget.initialBeneficiaryName,
  );
  final _relationshipController = TextEditingController(text: 'Moi-même');
  final _titleController = TextEditingController();
  final _storyController = TextEditingController();
  final _facilityController = TextEditingController();
  final _locationController = TextEditingController();
  late final _phoneController = TextEditingController(
    text: widget.initialPhone,
  );
  final _amountController = TextEditingController();
  CrowdfundingCategory _category = CrowdfundingCategory.emergency;
  String _currency = 'HTG';
  int _durationDays = 30;
  bool _consent = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _beneficiaryController.dispose();
    _relationshipController.dispose();
    _titleController.dispose();
    _storyController.dispose();
    _facilityController.dispose();
    _locationController.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    if (!_consent) {
      setState(
        () => _error = 'Votre consentement à la publication est requis.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.submitCampaign(
        CrowdfundingCampaignDraft(
          beneficiaryName: _beneficiaryController.text.trim(),
          relationshipToPatient: _relationshipController.text.trim(),
          title: _titleController.text.trim(),
          story: _storyController.text.trim(),
          category: _category,
          medicalFacility: _facilityController.text.trim(),
          location: _locationController.text.trim(),
          contactPhone: _phoneController.text.trim(),
          targetAmount: _parseAmount(_amountController.text)!,
          currency: _currency,
          deadline: DateTime.now().add(Duration(days: _durationDays)),
          consentToPublish: _consent,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'La campagne n’a pas été envoyée. Vérifiez les informations.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 20,
      right: 20,
      top: 8,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .88,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Créer une campagne',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Fermer',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const Text(
            'Les informations seront examinées avant toute publication.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  TextFormField(
                    key: const Key('campaign-beneficiary'),
                    controller: _beneficiaryController,
                    decoration: const InputDecoration(
                      labelText: 'Nom du bénéficiaire',
                    ),
                    validator: (value) => _required(value, 2),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _relationshipController,
                    decoration: const InputDecoration(
                      labelText: 'Lien avec le bénéficiaire',
                    ),
                    validator: (value) => _required(value, 2),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<CrowdfundingCategory>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Catégorie'),
                    items: CrowdfundingCategory.values
                        .where(
                          (category) => category != CrowdfundingCategory.all,
                        )
                        .map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(category.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _category = value ?? _category),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('campaign-title'),
                    controller: _titleController,
                    maxLength: 140,
                    decoration: const InputDecoration(
                      labelText: 'Titre de la campagne',
                      hintText: 'Ex. Aidez Nadia à financer son opération',
                    ),
                    validator: (value) => _required(value, 10),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('campaign-story'),
                    controller: _storyController,
                    minLines: 5,
                    maxLines: 8,
                    maxLength: 3000,
                    decoration: const InputDecoration(
                      labelText: 'Histoire et besoin médical',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => _required(value, 80),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _facilityController,
                    decoration: const InputDecoration(
                      labelText: 'Établissement de soins (facultatif)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('campaign-location'),
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'Commune / département',
                    ),
                    validator: (value) => _required(value, 2),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('campaign-phone'),
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone de contact privé',
                      helperText: 'Visible uniquement par l’administration.',
                    ),
                    validator: (value) => _required(value, 8),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          key: const Key('campaign-amount'),
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Objectif',
                          ),
                          validator: (value) {
                            final amount = _parseAmount(value);
                            return amount == null || amount < 1000
                                ? 'Minimum 1 000'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _currency,
                          decoration: const InputDecoration(
                            labelText: 'Devise',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'HTG', child: Text('HTG')),
                            DropdownMenuItem(value: 'USD', child: Text('USD')),
                          ],
                          onChanged: (value) =>
                              setState(() => _currency = value ?? 'HTG'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _durationDays,
                    decoration: const InputDecoration(
                      labelText: 'Durée de la campagne',
                    ),
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('15 jours')),
                      DropdownMenuItem(value: 30, child: Text('30 jours')),
                      DropdownMenuItem(value: 60, child: Text('60 jours')),
                      DropdownMenuItem(value: 90, child: Text('90 jours')),
                    ],
                    onChanged: (value) =>
                        setState(() => _durationDays = value ?? 30),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    key: const Key('campaign-consent'),
                    contentPadding: EdgeInsets.zero,
                    value: _consent,
                    onChanged: (value) =>
                        setState(() => _consent = value ?? false),
                    title: const Text(
                      'J’autorise la publication des informations de la campagne.',
                    ),
                    subtitle: const Text(
                      'Le téléphone reste privé. Aucun diagnostic détaillé n’est requis.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('campaign-submit'),
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: _crowdfundingGreen,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(_saving ? 'Envoi...' : 'Envoyer pour vérification'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ContributionSheet extends StatefulWidget {
  final CrowdfundingRepository repository;
  final CrowdfundingCampaign campaign;
  final String publicName;

  const _ContributionSheet({
    required this.repository,
    required this.campaign,
    required this.publicName,
  });

  @override
  State<_ContributionSheet> createState() => _ContributionSheetState();
}

class _ContributionSheetState extends State<_ContributionSheet> {
  final _amountController = TextEditingController();
  final _messageController = TextEditingController();
  CrowdfundingPaymentMethod _paymentMethod = CrowdfundingPaymentMethod.moncash;
  bool _anonymous = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = _parseAmount(_amountController.text);
    if (amount == null || amount < 50) {
      setState(() => _error = 'Entrez un montant d’au moins 50.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final receipt = await widget.repository.startContribution(
        campaign: widget.campaign,
        amount: amount,
        paymentMethod: _paymentMethod,
        publicName: widget.publicName,
        anonymous: _anonymous,
        message: _messageController.text.trim(),
      );
      if (mounted) Navigator.pop(context, receipt);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'La contribution n’a pas pu être enregistrée.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      8,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Soutenir cette campagne',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Fermer',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          Text(
            widget.campaign.title,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 22),
          TextField(
            key: const Key('contribution-amount'),
            controller: _amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Montant (${widget.campaign.currency})',
              prefixIcon: const Icon(Icons.savings_outlined),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final amount in [500, 1000, 2500, 5000])
                ActionChip(
                  label: Text(
                    _money(amount.toDouble(), widget.campaign.currency),
                  ),
                  onPressed: () => _amountController.text = '$amount',
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Mode de paiement',
            style: TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<CrowdfundingPaymentMethod>(
            segments: [
              for (final method in CrowdfundingPaymentMethod.values)
                ButtonSegment(
                  value: method,
                  icon: Icon(method.icon),
                  label: Text(method.label),
                ),
            ],
            selected: {_paymentMethod},
            onSelectionChanged: (value) =>
                setState(() => _paymentMethod = value.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _messageController,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Message de soutien (facultatif)',
              alignLabelWithHint: true,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _anonymous,
            onChanged: (value) => setState(() => _anonymous = value),
            title: const Text('Contribuer anonymement'),
          ),
          const _TrustNotice(),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('contribution-submit'),
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: _crowdfundingGreen,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                _saving ? 'Enregistrement...' : 'Enregistrer ma contribution',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ContributionReceiptDialog extends StatelessWidget {
  final CrowdfundingContributionReceipt receipt;

  const _ContributionReceiptDialog({required this.receipt});

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(
      Icons.receipt_long_outlined,
      color: _crowdfundingGreen,
      size: 38,
    ),
    title: const Text('Contribution enregistrée'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _money(receipt.amount, receipt.currency),
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 25,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Référence : ${_shortReference(receipt.id)}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        Text(
          'Votre intention est enregistrée via ${receipt.paymentMethod.label}. '
          'Le montant apparaîtra dans la campagne après confirmation du paiement.',
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.45),
        ),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        style: FilledButton.styleFrom(backgroundColor: _crowdfundingGreen),
        child: const Text('Compris'),
      ),
    ],
  );
}

class _CrowdfundingError extends StatelessWidget {
  const _CrowdfundingError();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 54, color: AppColors.muted),
          SizedBox(height: 14),
          Text(
            'Les campagnes sont momentanément indisponibles.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmptyCampaigns extends StatelessWidget {
  const _EmptyCampaigns();

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 34, 24, 60),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: _crowdfundingSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.volunteer_activism_outlined,
                size: 36,
                color: _crowdfundingGreen,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Aucune campagne trouvée',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Modifiez les filtres ou revenez bientôt pour découvrir de nouvelles campagnes vérifiées.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.45),
            ),
          ],
        ),
      ),
    ),
  );
}

String _campaignStatusLabel(CrowdfundingCampaign campaign) =>
    switch (campaign.status) {
      'active' => 'Active',
      'funded' => 'Objectif atteint',
      'paused' => 'En pause',
      'rejected' => 'À corriger',
      'closed' => 'Terminée',
      _ => 'En vérification',
    };

String? _required(String? value, int minimum) {
  if (value == null || value.trim().length < minimum) {
    return minimum <= 2
        ? 'Ce champ est requis.'
        : 'Saisissez au moins $minimum caractères.';
  }
  return null;
}

double? _parseAmount(String? raw) {
  if (raw == null) return null;
  return double.tryParse(raw.trim().replaceAll(' ', '').replaceAll(',', '.'));
}

String _money(double amount, String currency) {
  final rounded = amount.round().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < rounded.length; index++) {
    if (index > 0 && (rounded.length - index) % 3 == 0) buffer.write(' ');
    buffer.write(rounded[index]);
  }
  return '${buffer.toString()} $currency';
}

String _shortReference(String id) {
  final normalized = id.replaceAll('-', '').toUpperCase();
  return normalized.length <= 10 ? normalized : normalized.substring(0, 10);
}
