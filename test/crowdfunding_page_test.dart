import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/app_theme.dart';
import 'package:i_entier/crowdfunding_page.dart';

void main() {
  final now = DateTime(2026, 7, 29, 10);
  final campaigns = [
    CrowdfundingCampaign(
      id: 'campaign-surgery',
      creatorId: 'other-user',
      beneficiaryName: 'Nadia Pierre',
      title: 'Aidez Nadia à financer son opération',
      story:
          'Nadia doit subir une intervention chirurgicale indispensable. '
          'La campagne couvre les frais de l’hôpital et les médicaments.',
      category: CrowdfundingCategory.surgery,
      medicalFacility: 'Hôpital Saint-Louis',
      location: 'Port-au-Prince',
      targetAmount: 250000,
      raisedAmount: 100000,
      contributorCount: 18,
      currency: 'HTG',
      deadline: DateTime(2026, 8, 28),
      status: 'active',
      verificationStatus: 'approved',
      featured: true,
    ),
    CrowdfundingCampaign(
      id: 'campaign-medication',
      creatorId: 'patient-1',
      beneficiaryName: 'Samuel Jean',
      title: 'Un traitement continu pour Samuel',
      story:
          'Samuel a besoin de médicaments pendant plusieurs mois. '
          'Chaque contribution aide sa famille à poursuivre le traitement.',
      category: CrowdfundingCategory.medication,
      medicalFacility: 'Centre médical Espoir',
      location: 'Delmas',
      targetAmount: 80000,
      raisedAmount: 12000,
      contributorCount: 4,
      currency: 'HTG',
      deadline: DateTime(2026, 9, 10),
      status: 'active',
      verificationStatus: 'approved',
    ),
  ];

  testWidgets('affiche et filtre les campagnes médicales vérifiées', (
    tester,
  ) async {
    final repository = _FakeCrowdfundingRepository(campaigns);
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page(repository, now));
    await tester.pump();

    expect(find.text('Financement solidaire'), findsOneWidget);
    expect(find.text('Campagnes solidaires'), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/services/crowdfunding_3d.png')),
      findsOneWidget,
    );
    expect(find.text('Aidez Nadia à financer son opération'), findsOneWidget);
    expect(find.text('Un traitement continu pour Samuel'), findsOneWidget);

    await tester.tap(find.byKey(const Key('crowdfunding-category-medication')));
    await tester.pump();

    expect(find.text('Aidez Nadia à financer son opération'), findsNothing);
    expect(find.text('Un traitement continu pour Samuel'), findsOneWidget);
  });

  testWidgets('enregistre une contribution sans la compter avant paiement', (
    tester,
  ) async {
    final repository = _FakeCrowdfundingRepository([campaigns.first]);
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page(repository, now));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Contribuer'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('contribution-amount')),
      '2500',
    );
    await tester.tap(find.byKey(const Key('contribution-submit')));
    await tester.pumpAndSettle();

    expect(repository.contributions, hasLength(1));
    expect(repository.contributions.single.amount, 2500);
    expect(find.text('Contribution enregistrée'), findsOneWidget);
    expect(
      find.textContaining('après confirmation du paiement'),
      findsOneWidget,
    );
  });

  testWidgets('soumet une campagne complète pour vérification', (tester) async {
    final repository = _FakeCrowdfundingRepository(const []);
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page(repository, now));
    await tester.pump();
    await tester.tap(find.byKey(const Key('crowdfunding-create')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('campaign-title')),
      'Aidez Marie à poursuivre son traitement',
    );
    await tester.enterText(
      find.byKey(const Key('campaign-story')),
      'Marie suit un traitement médical essentiel depuis plusieurs mois. '
      'Cette collecte permettra de payer les examens, les médicaments et '
      'les déplacements nécessaires jusqu’à la fin de ses soins.',
    );
    final formScrollable = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('campaign-location')),
      350,
      scrollable: formScrollable,
    );
    await tester.enterText(
      find.byKey(const Key('campaign-location')),
      'Pétion-Ville, Ouest',
    );
    await tester.enterText(
      find.byKey(const Key('campaign-phone')),
      '+509 3700 0000',
    );
    await tester.enterText(find.byKey(const Key('campaign-amount')), '120000');
    await tester.scrollUntilVisible(
      find.byKey(const Key('campaign-consent')),
      350,
      scrollable: formScrollable,
    );
    await tester.tap(find.byKey(const Key('campaign-consent')));
    await tester.ensureVisible(find.byKey(const Key('campaign-submit')));
    await tester.tap(find.byKey(const Key('campaign-submit')));
    await tester.pumpAndSettle();

    expect(repository.drafts, hasLength(1));
    expect(repository.drafts.single.targetAmount, 120000);
    expect(
      find.text('Campagne envoyée. Elle sera visible après vérification.'),
      findsOneWidget,
    );
  });
}

Widget _page(_FakeCrowdfundingRepository repository, DateTime now) =>
    MaterialApp(
      theme: AppTheme.light,
      home: CrowdfundingPage(
        userId: 'patient-1',
        userDisplayName: 'Patient Test',
        patientProfile: const {'phone': '+509 3600 0000'},
        repository: repository,
        now: now,
      ),
    );

class _FakeCrowdfundingRepository implements CrowdfundingRepository {
  final List<CrowdfundingCampaign> campaigns;
  final List<CrowdfundingCampaignDraft> drafts = [];
  final List<_ContributionCall> contributions = [];

  _FakeCrowdfundingRepository(this.campaigns);

  @override
  Stream<List<CrowdfundingCampaign>> watchCampaigns() =>
      Stream.value(campaigns);

  @override
  Future<String> submitCampaign(CrowdfundingCampaignDraft draft) async {
    drafts.add(draft);
    return 'campaign-created';
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
    contributions.add(
      _ContributionCall(
        campaignId: campaign.id,
        amount: amount,
        paymentMethod: paymentMethod,
      ),
    );
    return CrowdfundingContributionReceipt(
      id: '01234567-89ab-cdef-0123-456789abcdef',
      amount: amount,
      currency: campaign.currency,
      paymentMethod: paymentMethod,
    );
  }
}

class _ContributionCall {
  final String campaignId;
  final double amount;
  final CrowdfundingPaymentMethod paymentMethod;

  const _ContributionCall({
    required this.campaignId,
    required this.amount,
    required this.paymentMethod,
  });
}
