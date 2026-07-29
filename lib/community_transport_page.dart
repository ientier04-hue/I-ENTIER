import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'supabase_config.dart';

const _transportBlue = Color(0xFF0C5F9C);
const _transportBlueDark = Color(0xFF083D6B);
const _transportBlueSoft = Color(0xFFE7F4FC);
const _transportGreen = Color(0xFF087A5B);
const _transportRed = Color(0xFFD92D20);

const haitianDepartments = <String>[
  'Artibonite',
  'Centre',
  'Grand’Anse',
  'Nippes',
  'Nord',
  'Nord-Est',
  'Nord-Ouest',
  'Ouest',
  'Sud',
  'Sud-Est',
];

typedef TransportUriLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchTransportUri(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

enum TransportCareLevel { seated, assisted, medicalTransfer }

extension TransportCareLevelDetails on TransportCareLevel {
  String get databaseValue => switch (this) {
    TransportCareLevel.seated => 'seated',
    TransportCareLevel.assisted => 'assisted',
    TransportCareLevel.medicalTransfer => 'medical_transfer',
  };

  String get label => switch (this) {
    TransportCareLevel.seated => 'Malade stable, assis',
    TransportCareLevel.assisted => 'Aide pour marcher ou monter',
    TransportCareLevel.medicalTransfer => 'Transfert entre établissements',
  };

  String get description => switch (this) {
    TransportCareLevel.seated =>
      'La personne peut voyager assise sans surveillance médicale continue.',
    TransportCareLevel.assisted =>
      'Mobilité réduite, fauteuil pliable ou aide humaine nécessaire.',
    TransportCareLevel.medicalTransfer =>
      'Déplacement planifié avec dossier et accord de l’établissement.',
  };

  IconData get icon => switch (this) {
    TransportCareLevel.seated => Icons.airline_seat_recline_normal_rounded,
    TransportCareLevel.assisted => Icons.accessible_forward_rounded,
    TransportCareLevel.medicalTransfer => Icons.local_hospital_outlined,
  };
}

enum TransportPaymentMethod { cash, monCash, agreeBeforeDeparture }

extension TransportPaymentMethodDetails on TransportPaymentMethod {
  String get databaseValue => switch (this) {
    TransportPaymentMethod.cash => 'cash',
    TransportPaymentMethod.monCash => 'moncash',
    TransportPaymentMethod.agreeBeforeDeparture => 'agreed_before_departure',
  };

  String get label => switch (this) {
    TransportPaymentMethod.cash => 'Espèces',
    TransportPaymentMethod.monCash => 'MonCash',
    TransportPaymentMethod.agreeBeforeDeparture => 'À convenir avant départ',
  };
}

class CommunityTransportRequestDraft {
  final String requesterId;
  final String patientName;
  final String contactPhone;
  final String pickupDepartment;
  final String pickupCommune;
  final String pickupLandmark;
  final String destinationName;
  final String destinationCommune;
  final TransportCareLevel careLevel;
  final String mobilityDetails;
  final bool departureNow;
  final DateTime? scheduledAt;
  final TransportPaymentMethod paymentMethod;
  final String notes;

  const CommunityTransportRequestDraft({
    required this.requesterId,
    required this.patientName,
    required this.contactPhone,
    required this.pickupDepartment,
    required this.pickupCommune,
    required this.pickupLandmark,
    required this.destinationName,
    required this.destinationCommune,
    required this.careLevel,
    required this.mobilityDetails,
    required this.departureNow,
    required this.scheduledAt,
    required this.paymentMethod,
    required this.notes,
  });
}

class CommunityTransportPartnerApplication {
  final String applicantId;
  final String driverName;
  final String contactPhone;
  final String department;
  final String commune;
  final String vehicleType;
  final String vehicleMakeModel;
  final String vehicleYear;
  final String plateNumber;
  final String roadCapability;
  final bool hasOwnCompanion;
  final String companionName;
  final String companionQualification;
  final bool acceptsCash;
  final bool acceptsMonCash;

  const CommunityTransportPartnerApplication({
    required this.applicantId,
    required this.driverName,
    required this.contactPhone,
    required this.department,
    required this.commune,
    required this.vehicleType,
    required this.vehicleMakeModel,
    required this.vehicleYear,
    required this.plateNumber,
    required this.roadCapability,
    required this.hasOwnCompanion,
    required this.companionName,
    required this.companionQualification,
    required this.acceptsCash,
    required this.acceptsMonCash,
  });
}

abstract class CommunityTransportRepository {
  Future<String> createRequest(CommunityTransportRequestDraft request);

  Future<String> applyAsPartner(
    CommunityTransportPartnerApplication application,
  );
}

class SupabaseCommunityTransportRepository
    implements CommunityTransportRepository {
  final SupabaseClient client;

  SupabaseCommunityTransportRepository({SupabaseClient? client})
    : client = client ?? SupabaseConfig.client;

  @override
  Future<String> createRequest(CommunityTransportRequestDraft request) async {
    final row = await client
        .schema('ientier')
        .from('community_transport_requests')
        .insert({
          'requester_id': request.requesterId,
          'patient_display_name': request.patientName.trim(),
          'contact_phone': request.contactPhone.trim(),
          'pickup_department': request.pickupDepartment,
          'pickup_commune': request.pickupCommune.trim(),
          'pickup_landmark': request.pickupLandmark.trim(),
          'destination_name': request.destinationName.trim(),
          'destination_commune': request.destinationCommune.trim(),
          'care_level': request.careLevel.databaseValue,
          'mobility_details': request.mobilityDetails.trim(),
          'departure_mode': request.departureNow ? 'now' : 'scheduled',
          'scheduled_at': request.scheduledAt?.toUtc().toIso8601String(),
          'payment_method': request.paymentMethod.databaseValue,
          'notes': request.notes.trim(),
          'health_companion_required': true,
          'status': 'requested',
        })
        .select('transport_request_id')
        .single();
    return row['transport_request_id'].toString();
  }

  @override
  Future<String> applyAsPartner(
    CommunityTransportPartnerApplication application,
  ) async {
    final row = await client
        .schema('ientier')
        .from('community_transport_partner_applications')
        .insert({
          'applicant_id': application.applicantId,
          'driver_name': application.driverName.trim(),
          'contact_phone': application.contactPhone.trim(),
          'department': application.department,
          'commune': application.commune.trim(),
          'vehicle_type': application.vehicleType,
          'vehicle_make_model': application.vehicleMakeModel.trim(),
          'vehicle_year': int.parse(application.vehicleYear),
          'plate_number': application.plateNumber.trim().toUpperCase(),
          'road_capability': application.roadCapability,
          'has_own_health_companion': application.hasOwnCompanion,
          'companion_name': application.companionName.trim(),
          'companion_qualification': application.companionQualification.trim(),
          'accepts_cash': application.acceptsCash,
          'accepts_moncash': application.acceptsMonCash,
          'verification_status': 'pending',
          'status': 'submitted',
        })
        .select('partner_application_id')
        .single();
    return row['partner_application_id'].toString();
  }
}

class CommunityTransportPage extends StatelessWidget {
  final String patientId;
  final String patientName;
  final Map<String, dynamic> patientProfile;
  final CommunityTransportRepository? repository;
  final TransportUriLauncher uriLauncher;

  const CommunityTransportPage({
    super.key,
    required this.patientId,
    required this.patientName,
    this.patientProfile = const {},
    this.repository,
    this.uriLauncher = _launchTransportUri,
  });

  CommunityTransportRepository? get _repository =>
      repository ??
      (SupabaseConfig.isInitialized
          ? SupabaseCommunityTransportRepository()
          : null);

  Future<void> _callCan(BuildContext context) async {
    final launched = await uriLauncher(Uri(scheme: 'tel', path: '116'));
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de lancer l’appel au 116.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final compactEmergencyAction =
        MediaQuery.sizeOf(context).width < 420 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          title: const Text('Mobilité Santé'),
          actions: [
            if (compactEmergencyAction)
              IconButton(
                key: const ValueKey('transport-call-116'),
                tooltip: 'Urgence : appeler le CAN au 116',
                onPressed: () => _callCan(context),
                icon: const Icon(Icons.call_rounded, color: _transportRed),
              )
            else
              TextButton.icon(
                key: const ValueKey('transport-call-116'),
                onPressed: () => _callCan(context),
                icon: const Icon(Icons.call_rounded, color: _transportRed),
                label: const Text(
                  'Urgence 116',
                  style: TextStyle(color: _transportRed),
                ),
              ),
            const SizedBox(width: 4),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                key: ValueKey('transport-tab-request'),
                icon: Icon(Icons.near_me_outlined),
                text: 'Demander',
              ),
              Tab(
                key: ValueKey('transport-tab-partner'),
                icon: Icon(Icons.directions_car_outlined),
                text: 'Devenir partenaire',
              ),
              Tab(
                key: ValueKey('transport-tab-safety'),
                icon: Icon(Icons.health_and_safety_outlined),
                text: 'Sécurité',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _RequestLanding(
              patientId: patientId,
              patientName: patientName,
              patientProfile: patientProfile,
              repository: _repository,
              onCallCan: () => _callCan(context),
            ),
            _PartnerLanding(
              patientId: patientId,
              applicantName: patientName,
              repository: _repository,
            ),
            _SafetySection(onCallCan: () => _callCan(context)),
          ],
        ),
      ),
    );
  }
}

class _RequestLanding extends StatelessWidget {
  final String patientId;
  final String patientName;
  final Map<String, dynamic> patientProfile;
  final CommunityTransportRepository? repository;
  final VoidCallback onCallCan;

  const _RequestLanding({
    required this.patientId,
    required this.patientName,
    required this.patientProfile,
    required this.repository,
    required this.onCallCan,
  });

  @override
  Widget build(BuildContext context) => _TransportScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TransportHero(),
        const SizedBox(height: 18),
        _EmergencyBoundaryCard(onCallCan: onCallCan),
        const SizedBox(height: 24),
        Text(
          'Un trajet organisé comme une course',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        const Text(
          'Un conducteur vérifié vient avec un accompagnateur santé. '
          'Le prix, le véhicule et la plaque sont confirmés avant le départ.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 16),
        const _ProcessSteps(),
        const SizedBox(height: 20),
        _PrimaryActionCard(
          icon: Icons.airport_shuttle_rounded,
          title: 'Demander un transport',
          description:
              'Pour un rendez-vous, un retour à domicile ou un transfert planifié.',
          buttonLabel: 'Décrire le trajet',
          onPressed: () {
            final service = repository;
            if (service == null) {
              _showServiceUnavailable(context);
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CommunityTransportRequestFormPage(
                  patientId: patientId,
                  patientName: patientName,
                  patientProfile: patientProfile,
                  repository: service,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        const _LocalRealityCard(),
      ],
    ),
  );
}

class _PartnerLanding extends StatelessWidget {
  final String patientId;
  final String applicantName;
  final CommunityTransportRepository? repository;

  const _PartnerLanding({
    required this.patientId,
    required this.applicantName,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) => _TransportScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_transportBlueDark, _transportBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.volunteer_activism_rounded,
                color: Colors.white,
                size: 36,
              ),
              SizedBox(height: 14),
              Text(
                'Votre véhicule peut rapprocher un malade des soins',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Aucun diplôme médical n’est exigé du conducteur. '
                'Le véhicule, l’identité et le permis doivent être vérifiés.',
                style: TextStyle(color: Color(0xFFD7EDFB), height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Conditions de base',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 14),
        const _RequirementTile(
          icon: Icons.badge_outlined,
          title: 'Conducteur identifiable',
          text: 'Pièce d’identité, permis valide et téléphone joignable.',
        ),
        const _RequirementTile(
          icon: Icons.car_repair_outlined,
          title: 'Véhicule à quatre roues',
          text:
              'Papiers à jour, ceintures, intérieur propre et état mécanique fiable.',
        ),
        const _RequirementTile(
          icon: Icons.medical_services_outlined,
          title: 'Accompagnateur santé obligatoire',
          text:
              'Vous venez avec une personne qualifiée ou i-ENTIER forme le duo avant la course.',
        ),
        const _RequirementTile(
          icon: Icons.fact_check_outlined,
          title: 'Validation avant activation',
          text:
              'Une candidature ne permet jamais de prendre une course immédiatement.',
        ),
        const SizedBox(height: 18),
        _PrimaryActionCard(
          icon: Icons.directions_car_filled_outlined,
          title: 'Proposer mon véhicule',
          description:
              'Voiture, SUV, pick-up ou minibus : la capacité est affichée au demandeur.',
          buttonLabel: 'Déposer ma candidature',
          onPressed: () {
            final service = repository;
            if (service == null) {
              _showServiceUnavailable(context);
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CommunityTransportPartnerFormPage(
                  applicantId: patientId,
                  applicantName: applicantName,
                  repository: service,
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
}

class _SafetySection extends StatelessWidget {
  final VoidCallback onCallCan;

  const _SafetySection({required this.onCallCan});

  @override
  Widget build(BuildContext context) => _TransportScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ce service a des limites claires',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Mobilité Santé organise un transport accompagné. Ce n’est pas une '
          'ambulance médicalisée et le conducteur ne réalise aucun acte de soin.',
        ),
        const SizedBox(height: 20),
        _EmergencyBoundaryCard(onCallCan: onCallCan),
        const SizedBox(height: 20),
        const _SafetyChecklist(
          title: 'Avant de monter',
          items: [
            'Vérifiez le nom du conducteur, la photo, la plaque et le véhicule.',
            'Confirmez le prix et le mode de paiement avant le départ.',
            'Confirmez l’identité et la qualification de l’accompagnateur.',
            'Partagez le trajet et le numéro du véhicule avec un proche.',
          ],
        ),
        const SizedBox(height: 16),
        const _SafetyChecklist(
          title: 'Le véhicule doit être refusé si…',
          items: [
            'la plaque ou le conducteur ne correspond pas à l’application;',
            'il n’y a pas d’accompagnateur santé confirmé;',
            'les ceintures ne fonctionnent pas ou l’habitacle est dangereux;',
            'le prix change sans accord avant le départ.',
          ],
        ),
        const SizedBox(height: 16),
        const _SafetyChecklist(
          title: 'Cas non acceptés',
          items: [
            'difficulté à respirer, perte de connaissance ou convulsions;',
            'saignement important, douleur thoracique ou signes d’AVC;',
            'accouchement imminent ou état nécessitant oxygène et surveillance;',
            'transport couché dans un véhicule non équipé et non homologué.',
          ],
        ),
      ],
    ),
  );
}

class CommunityTransportRequestFormPage extends StatefulWidget {
  final String patientId;
  final String patientName;
  final Map<String, dynamic> patientProfile;
  final CommunityTransportRepository repository;

  const CommunityTransportRequestFormPage({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.repository,
    this.patientProfile = const {},
  });

  @override
  State<CommunityTransportRequestFormPage> createState() =>
      _CommunityTransportRequestFormPageState();
}

class _CommunityTransportRequestFormPageState
    extends State<CommunityTransportRequestFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _patientName = TextEditingController(text: widget.patientName);
  late final _phone = TextEditingController(
    text: _profileText(widget.patientProfile, const [
      'phone',
      'telephone',
      'contactPhone',
    ]),
  );
  final _pickupCommune = TextEditingController();
  final _pickupLandmark = TextEditingController();
  final _destinationName = TextEditingController();
  final _destinationCommune = TextEditingController();
  final _mobilityDetails = TextEditingController();
  final _notes = TextEditingController();
  String? _department;
  TransportCareLevel _careLevel = TransportCareLevel.seated;
  TransportPaymentMethod _paymentMethod =
      TransportPaymentMethod.agreeBeforeDeparture;
  bool _departureNow = true;
  DateTime? _scheduledAt;
  bool _medicalBoundaryAccepted = false;
  bool _submitting = false;

  @override
  void dispose() {
    _patientName.dispose();
    _phone.dispose();
    _pickupCommune.dispose();
    _pickupLandmark.dispose();
    _destinationName.dispose();
    _destinationCommune.dispose();
    _mobilityDetails.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      initialDate: _scheduledAt ?? now.add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _scheduledAt ?? now.add(const Duration(hours: 2)),
      ),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (!_departureNow && _scheduledAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choisissez la date et l’heure du départ.'),
        ),
      );
      return;
    }
    if (!_medicalBoundaryAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Confirmez que la situation n’est pas une urgence vitale.',
          ),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final reference = await widget.repository.createRequest(
        CommunityTransportRequestDraft(
          requesterId: widget.patientId,
          patientName: _patientName.text,
          contactPhone: _phone.text,
          pickupDepartment: _department!,
          pickupCommune: _pickupCommune.text,
          pickupLandmark: _pickupLandmark.text,
          destinationName: _destinationName.text,
          destinationCommune: _destinationCommune.text,
          careLevel: _careLevel,
          mobilityDetails: _mobilityDetails.text,
          departureNow: _departureNow,
          scheduledAt: _departureNow ? null : _scheduledAt,
          paymentMethod: _paymentMethod,
          notes: _notes.text,
        ),
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => _RequestSubmittedPage(reference: reference),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La demande n’a pas été envoyée. Vérifiez votre connexion et réessayez.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Demander un transport')),
    body: SafeArea(
      top: false,
      child: Form(
        key: _formKey,
        child: ListView(
          key: const ValueKey('transport-request-form-scroll'),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
          children: [
            const _FormIntroCard(
              icon: Icons.supervised_user_circle_outlined,
              title: 'Un duo vient vous chercher',
              text:
                  'Chaque trajet doit avoir un conducteur et un accompagnateur santé validés.',
            ),
            const SizedBox(height: 24),
            const _FormSectionTitle(
              number: '1',
              title: 'Personne à transporter',
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey('transport-patient-name'),
              controller: _patientName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom de la personne',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (value) => _required(value, 'Le nom est requis.'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('transport-contact-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Téléphone joignable',
                hintText: '+509 37 00 00 00',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: _phoneValidator,
            ),
            const SizedBox(height: 18),
            Text(
              'Comment voyagera la personne ?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            for (final level in TransportCareLevel.values)
              _CareLevelTile(
                level: level,
                selected: _careLevel == level,
                onTap: () => setState(() => _careLevel = level),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mobilityDetails,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Mobilité ou matériel à prévoir',
                hintText:
                    'Ex. fauteuil pliable, béquilles, aide pour monter 2 marches',
                prefixIcon: Icon(Icons.accessible_outlined),
              ),
            ),
            const SizedBox(height: 26),
            const _FormSectionTitle(
              number: '2',
              title: 'Départ et destination',
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: const ValueKey('transport-pickup-department'),
              isExpanded: true,
              initialValue: _department,
              decoration: const InputDecoration(
                labelText: 'Département de départ',
                prefixIcon: Icon(Icons.map_outlined),
              ),
              items: [
                for (final department in haitianDepartments)
                  DropdownMenuItem(value: department, child: Text(department)),
              ],
              onChanged: (value) => setState(() => _department = value),
              validator: (value) =>
                  value == null ? 'Choisissez le département.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('transport-pickup-commune'),
              controller: _pickupCommune,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Commune de départ',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
              validator: (value) => _required(value, 'La commune est requise.'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('transport-pickup-landmark'),
              controller: _pickupLandmark,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Adresse et repère précis',
                hintText:
                    'Ex. après l’église, maison bleue, près du marché communal',
                prefixIcon: Icon(Icons.add_location_alt_outlined),
              ),
              validator: (value) =>
                  _required(value, 'Ajoutez un repère pour le conducteur.'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('transport-destination-name'),
              controller: _destinationName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Hôpital, clinique ou destination',
                prefixIcon: Icon(Icons.local_hospital_outlined),
              ),
              validator: (value) =>
                  _required(value, 'La destination est requise.'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('transport-destination-commune'),
              controller: _destinationCommune,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Commune de destination',
                prefixIcon: Icon(Icons.flag_outlined),
              ),
              validator: (value) =>
                  _required(value, 'La commune de destination est requise.'),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _DepartureModeButton(
                    selected: _departureNow,
                    icon: Icons.bolt_rounded,
                    label: 'Dès que possible',
                    onTap: () => setState(() => _departureNow = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DepartureModeButton(
                    selected: !_departureNow,
                    icon: Icons.schedule_rounded,
                    label: 'Planifier',
                    onTap: () => setState(() => _departureNow = false),
                  ),
                ),
              ],
            ),
            if (!_departureNow) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('transport-pick-schedule'),
                onPressed: _pickSchedule,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _scheduledAt == null
                      ? 'Choisir date et heure'
                      : _formatDateTime(_scheduledAt!),
                ),
              ),
            ],
            const SizedBox(height: 26),
            const _FormSectionTitle(number: '3', title: 'Paiement et sécurité'),
            const SizedBox(height: 14),
            DropdownButtonFormField<TransportPaymentMethod>(
              isExpanded: true,
              initialValue: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Mode de paiement préféré',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              items: [
                for (final method in TransportPaymentMethod.values)
                  DropdownMenuItem(value: method, child: Text(method.label)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _paymentMethod = value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Informations utiles (facultatif)',
                hintText:
                    'État de la route, étage, personne à appeler, heure du rendez-vous…',
                alignLabelWithHint: true,
              ),
            ),
            CheckboxListTile(
              key: const ValueKey('transport-medical-boundary'),
              value: _medicalBoundaryAccepted,
              onChanged: (value) =>
                  setState(() => _medicalBoundaryAccepted = value == true),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Je confirme qu’il ne s’agit pas d’une urgence vitale.',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'En cas de danger immédiat, j’appelle le CAN au 116.',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('transport-submit-request'),
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search_rounded),
              label: Text(
                _submitting ? 'Envoi en cours…' : 'Rechercher un duo vérifié',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Aucun prélèvement n’est effectué maintenant. Le prix doit être '
              'accepté avant l’arrivée du véhicule.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

class CommunityTransportPartnerFormPage extends StatefulWidget {
  final String applicantId;
  final String applicantName;
  final CommunityTransportRepository repository;

  const CommunityTransportPartnerFormPage({
    super.key,
    required this.applicantId,
    required this.applicantName,
    required this.repository,
  });

  @override
  State<CommunityTransportPartnerFormPage> createState() =>
      _CommunityTransportPartnerFormPageState();
}

class _CommunityTransportPartnerFormPageState
    extends State<CommunityTransportPartnerFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _driverName = TextEditingController(text: widget.applicantName);
  final _phone = TextEditingController();
  final _commune = TextEditingController();
  final _makeModel = TextEditingController();
  final _year = TextEditingController();
  final _plate = TextEditingController();
  final _companionName = TextEditingController();
  final _companionQualification = TextEditingController();
  String? _department;
  String? _vehicleType;
  String _roadCapability = 'standard';
  bool _hasOwnCompanion = false;
  bool _acceptsCash = true;
  bool _acceptsMonCash = false;
  bool _identityAndLicenseConfirmed = false;
  bool _vehiclePapersConfirmed = false;
  bool _seatBeltsConfirmed = false;
  bool _reviewAccepted = false;
  bool _submitting = false;

  @override
  void dispose() {
    _driverName.dispose();
    _phone.dispose();
    _commune.dispose();
    _makeModel.dispose();
    _year.dispose();
    _plate.dispose();
    _companionName.dispose();
    _companionQualification.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptsCash && !_acceptsMonCash) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choisissez au moins un paiement accepté.'),
        ),
      );
      return;
    }
    if (!_identityAndLicenseConfirmed ||
        !_vehiclePapersConfirmed ||
        !_seatBeltsConfirmed ||
        !_reviewAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirmez toutes les conditions de vérification.'),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final reference = await widget.repository.applyAsPartner(
        CommunityTransportPartnerApplication(
          applicantId: widget.applicantId,
          driverName: _driverName.text,
          contactPhone: _phone.text,
          department: _department!,
          commune: _commune.text,
          vehicleType: _vehicleType!,
          vehicleMakeModel: _makeModel.text,
          vehicleYear: _year.text,
          plateNumber: _plate.text,
          roadCapability: _roadCapability,
          hasOwnCompanion: _hasOwnCompanion,
          companionName: _hasOwnCompanion ? _companionName.text : '',
          companionQualification: _hasOwnCompanion
              ? _companionQualification.text
              : '',
          acceptsCash: _acceptsCash,
          acceptsMonCash: _acceptsMonCash,
        ),
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => _PartnerSubmittedPage(reference: reference),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La candidature n’a pas été envoyée. Vérifiez votre connexion.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Devenir partenaire')),
    body: SafeArea(
      top: false,
      child: Form(
        key: _formKey,
        child: ListView(
          key: const ValueKey('transport-partner-form-scroll'),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
          children: [
            const _FormIntroCard(
              icon: Icons.verified_user_outlined,
              title: 'Candidature ouverte à tous',
              text:
                  'Le conducteur n’est pas un soignant. Il assure la conduite; '
                  'l’accompagnateur santé s’occupe du malade pendant le trajet.',
            ),
            const SizedBox(height: 24),
            const _FormSectionTitle(number: '1', title: 'Conducteur'),
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey('transport-driver-name'),
              controller: _driverName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom complet',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) => _required(value, 'Le nom est requis.'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('transport-driver-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Téléphone / WhatsApp',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: _phoneValidator,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _department,
              decoration: const InputDecoration(
                labelText: 'Département principal',
                prefixIcon: Icon(Icons.map_outlined),
              ),
              items: [
                for (final department in haitianDepartments)
                  DropdownMenuItem(value: department, child: Text(department)),
              ],
              onChanged: (value) => setState(() => _department = value),
              validator: (value) =>
                  value == null ? 'Choisissez le département.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _commune,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Commune de service',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
              validator: (value) => _required(value, 'La commune est requise.'),
            ),
            const SizedBox(height: 26),
            const _FormSectionTitle(number: '2', title: 'Véhicule'),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: const ValueKey('transport-vehicle-type'),
              isExpanded: true,
              initialValue: _vehicleType,
              decoration: const InputDecoration(
                labelText: 'Type de véhicule',
                prefixIcon: Icon(Icons.directions_car_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'car', child: Text('Voiture')),
                DropdownMenuItem(value: 'suv', child: Text('SUV / 4x4')),
                DropdownMenuItem(value: 'van', child: Text('Monospace / van')),
                DropdownMenuItem(value: 'pickup', child: Text('Pick-up fermé')),
                DropdownMenuItem(value: 'minibus', child: Text('Minibus')),
              ],
              onChanged: (value) => setState(() => _vehicleType = value),
              validator: (value) =>
                  value == null ? 'Choisissez le véhicule.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('transport-vehicle-model'),
              controller: _makeModel,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Marque et modèle',
                hintText: 'Ex. Toyota RAV4',
                prefixIcon: Icon(Icons.car_repair_outlined),
              ),
              validator: (value) =>
                  _required(value, 'La marque et le modèle sont requis.'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Année'),
                    validator: _vehicleYearValidator,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _plate,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Plaque'),
                    validator: (value) =>
                        _required(value, 'La plaque est requise.'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _roadCapability,
              decoration: const InputDecoration(
                labelText: 'Routes praticables',
                prefixIcon: Icon(Icons.route_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'standard',
                  child: Text('Routes principales'),
                ),
                DropdownMenuItem(
                  value: 'high_clearance',
                  child: Text('Routes dégradées / garde au sol haute'),
                ),
                DropdownMenuItem(
                  value: 'four_wheel_drive',
                  child: Text('Zones difficiles / 4x4'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _roadCapability = value);
              },
            ),
            const SizedBox(height: 26),
            const _FormSectionTitle(number: '3', title: 'Accompagnateur santé'),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const ValueKey('transport-own-companion'),
              value: _hasOwnCompanion,
              onChanged: (value) => setState(() => _hasOwnCompanion = value),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'J’ai déjà un accompagnateur qualifié',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                _hasOwnCompanion
                    ? 'Son identité et sa qualification seront vérifiées.'
                    : 'i-ENTIER devra former le duo avant chaque course.',
              ),
            ),
            if (_hasOwnCompanion) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _companionName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nom de l’accompagnateur',
                  prefixIcon: Icon(Icons.medical_services_outlined),
                ),
                validator: (value) => _hasOwnCompanion
                    ? _required(value, 'Le nom est requis.')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _companionQualification,
                decoration: const InputDecoration(
                  labelText: 'Qualification ou formation',
                  hintText: 'Ex. infirmière, auxiliaire, secouriste formé',
                  prefixIcon: Icon(Icons.workspace_premium_outlined),
                ),
                validator: (value) => _hasOwnCompanion
                    ? _required(value, 'La qualification est requise.')
                    : null,
              ),
            ],
            const SizedBox(height: 22),
            Text(
              'Paiements acceptés',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            CheckboxListTile(
              value: _acceptsCash,
              onChanged: (value) =>
                  setState(() => _acceptsCash = value == true),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('Espèces'),
            ),
            CheckboxListTile(
              value: _acceptsMonCash,
              onChanged: (value) =>
                  setState(() => _acceptsMonCash = value == true),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('MonCash'),
            ),
            const SizedBox(height: 18),
            const _FormSectionTitle(number: '4', title: 'Déclarations'),
            const SizedBox(height: 8),
            _DeclarationCheckbox(
              value: _identityAndLicenseConfirmed,
              onChanged: (value) =>
                  setState(() => _identityAndLicenseConfirmed = value),
              title: 'J’ai une pièce d’identité et un permis valides.',
            ),
            _DeclarationCheckbox(
              value: _vehiclePapersConfirmed,
              onChanged: (value) =>
                  setState(() => _vehiclePapersConfirmed = value),
              title:
                  'Les papiers et l’état mécanique du véhicule peuvent être vérifiés.',
            ),
            _DeclarationCheckbox(
              value: _seatBeltsConfirmed,
              onChanged: (value) => setState(() => _seatBeltsConfirmed = value),
              title:
                  'Toutes les places utilisées ont une ceinture fonctionnelle.',
            ),
            _DeclarationCheckbox(
              value: _reviewAccepted,
              onChanged: (value) => setState(() => _reviewAccepted = value),
              title:
                  'J’accepte le contrôle du véhicule et de l’accompagnateur avant activation.',
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const ValueKey('transport-submit-partner'),
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(
                _submitting ? 'Envoi en cours…' : 'Envoyer ma candidature',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'La candidature reste « en vérification » jusqu’à validation. '
              'Elle ne garantit pas l’accès aux courses.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TransportHero extends StatelessWidget {
  const _TransportHero();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [_transportBlueDark, _transportBlue],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(26),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 94,
          height: 82,
          child: Image.asset(
            'assets/services/mobilite_sante_3d.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
        const SizedBox(width: 18),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Le transport santé près de chez vous',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'Un véhicule local + un accompagnateur santé, du point de départ jusqu’au lieu de soins.',
                style: TextStyle(color: Color(0xFFD7EDFB), height: 1.35),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _EmergencyBoundaryCard extends StatelessWidget {
  final VoidCallback onCallCan;

  const _EmergencyBoundaryCard({required this.onCallCan});

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('transport-emergency-boundary'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F0),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFF4C7C3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.emergency_rounded, color: _transportRed),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Danger immédiat ? N’attendez pas un conducteur.',
                style: TextStyle(
                  color: _transportRed,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Difficulté à respirer, inconscience, convulsions, saignement important, '
          'douleur thoracique, signes d’AVC ou accouchement imminent : appelez le '
          'Centre Ambulancier National.',
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onCallCan,
          style: OutlinedButton.styleFrom(
            foregroundColor: _transportRed,
            side: const BorderSide(color: _transportRed),
          ),
          icon: const Icon(Icons.call_rounded),
          label: const Text('Appeler le CAN au 116'),
        ),
      ],
    ),
  );
}

class _ProcessSteps extends StatelessWidget {
  const _ProcessSteps();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const steps = [
        (
          Icons.edit_location_alt_outlined,
          '1. Décrivez',
          'Repère, destination et mobilité.',
        ),
        (
          Icons.people_alt_outlined,
          '2. Un duo accepte',
          'Conducteur et accompagnateur vérifiés.',
        ),
        (
          Icons.verified_outlined,
          '3. Confirmez',
          'Plaque, prix et paiement avant départ.',
        ),
      ];
      final vertical = constraints.maxWidth < 650;
      final cards = [
        for (final step in steps)
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(step.$1, color: _transportBlue),
                const SizedBox(height: 10),
                Text(
                  step.$2,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.$3,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
      ];
      if (!vertical) {
        return IntrinsicHeight(
          child: Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 10),
              Expanded(child: cards[1]),
              const SizedBox(width: 10),
              Expanded(child: cards[2]),
            ],
          ),
        );
      }
      return Column(
        children: [
          for (var index = 0; index < cards.length; index++) ...[
            SizedBox(width: double.infinity, child: cards[index]),
            if (index != cards.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
    },
  );
}

class _PrimaryActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;

  const _PrimaryActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _transportBlue, size: 30),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          Text(description, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: ValueKey('transport-action-$buttonLabel'),
              onPressed: onPressed,
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    ),
  );
}

class _LocalRealityCard extends StatelessWidget {
  const _LocalRealityCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _transportBlueSoft,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pensé pour les déplacements en Haïti',
          style: TextStyle(
            color: _transportBlueDark,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 12),
        _InlineBenefit(
          icon: Icons.add_location_alt_outlined,
          text: 'Adresse complétée par un repère connu du quartier.',
        ),
        _InlineBenefit(
          icon: Icons.route_outlined,
          text: 'Type de véhicule adapté à l’état de la route.',
        ),
        _InlineBenefit(
          icon: Icons.payments_outlined,
          text: 'Espèces, MonCash ou prix convenu avant le départ.',
        ),
        _InlineBenefit(
          icon: Icons.phone_in_talk_outlined,
          text: 'Téléphone du demandeur partagé au duo après acceptation.',
        ),
      ],
    ),
  );
}

class _InlineBenefit extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InlineBenefit({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _transportBlue, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _RequirementTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _RequirementTile({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: _transportBlueSoft,
          child: Icon(icon, color: _transportBlue),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(text),
        ),
      ),
    ),
  );
}

class _SafetyChecklist extends StatelessWidget {
  final String title;
  final List<String> items;

  const _SafetyChecklist({required this.title, required this.items});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    color: _transportGreen,
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _TransportScrollView extends StatelessWidget {
  final Widget child;

  const _TransportScrollView({required this.child});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: child,
      ),
    ),
  );
}

class _FormIntroCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _FormIntroCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _transportBlueSoft,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: Colors.white,
          child: Icon(icon, color: _transportBlue),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _transportBlueDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(text),
            ],
          ),
        ),
      ],
    ),
  );
}

class _FormSectionTitle extends StatelessWidget {
  final String number;
  final String title;

  const _FormSectionTitle({required this.number, required this.title});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        radius: 15,
        backgroundColor: _transportBlue,
        child: Text(
          number,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
    ],
  );
}

class _CareLevelTile extends StatelessWidget {
  final TransportCareLevel level;
  final bool selected;
  final VoidCallback onTap;

  const _CareLevelTile({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: selected ? _transportBlueSoft : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _transportBlue : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                level.icon,
                color: selected ? _transportBlue : AppColors.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      level.label,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      level.description,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded, color: _transportBlue),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DepartureModeButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DepartureModeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? _transportBlueSoft : Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _transportBlue : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? _transportBlue : AppColors.muted,
              size: 20,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? _transportBlueDark : AppColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DeclarationCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;

  const _DeclarationCheckbox({
    required this.value,
    required this.onChanged,
    required this.title,
  });

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    value: value,
    onChanged: (newValue) => onChanged(newValue == true),
    controlAffinity: ListTileControlAffinity.leading,
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: const TextStyle(fontSize: 14)),
  );
}

class _RequestSubmittedPage extends StatelessWidget {
  final String reference;

  const _RequestSubmittedPage({required this.reference});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Demande enregistrée')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              const CircleAvatar(
                radius: 42,
                backgroundColor: Color(0xFFE7F8F1),
                child: Icon(
                  Icons.check_rounded,
                  color: _transportGreen,
                  size: 46,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Recherche du duo lancée',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Votre numéro reste privé jusqu’à l’acceptation. Vérifiez le '
                'conducteur, l’accompagnateur, la plaque et le prix avant de partir.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SelectableText(
                'Référence : ${_shortReference(reference)}',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Retour au service'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PartnerSubmittedPage extends StatelessWidget {
  final String reference;

  const _PartnerSubmittedPage({required this.reference});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Candidature envoyée')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              const CircleAvatar(
                radius: 42,
                backgroundColor: _transportBlueSoft,
                child: Icon(
                  Icons.fact_check_outlined,
                  color: _transportBlue,
                  size: 42,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Vérification en attente',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'L’identité, le permis, le véhicule et l’accompagnateur seront '
                'contrôlés. Aucune course ne sera proposée avant validation.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SelectableText(
                'Référence : ${_shortReference(reference)}',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Retour au service'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _showServiceUnavailable(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Le service de données est indisponible. Vérifiez votre connexion.',
      ),
    ),
  );
}

String? _required(String? value, String message) =>
    value == null || value.trim().isEmpty ? message : null;

String? _phoneValidator(String? value) {
  final digits = value?.replaceAll(RegExp(r'\D'), '') ?? '';
  if (digits.length < 8 || digits.length > 15) {
    return 'Entrez un numéro joignable valide.';
  }
  return null;
}

String? _vehicleYearValidator(String? value) {
  final year = int.tryParse(value ?? '');
  final latest = DateTime.now().year + 1;
  if (year == null || year < 1980 || year > latest) {
    return 'Année invalide.';
  }
  return null;
}

String _profileText(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _formatDateTime(DateTime value) {
  const months = [
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
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.day} ${months[value.month - 1]} ${value.year} à $hour:$minute';
}

String _shortReference(String value) {
  final normalized = value.replaceAll('-', '').toUpperCase();
  return normalized.length <= 8 ? normalized : normalized.substring(0, 8);
}
