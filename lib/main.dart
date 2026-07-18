import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const IEntierApp());
}

class IEntierApp extends StatelessWidget {
  const IEntierApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'I-ENTIER',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: Colors.white,
      ),
      fontFamily: 'Arial',
    ),
    home: const AuthGate(),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _LoadingScreen();
      }
      return snapshot.hasData
          ? PatientProfileGate(user: snapshot.data!)
          : const SignInScreen();
    },
  );
}

class PatientProfileGate extends StatelessWidget {
  final User user;
  const PatientProfileGate({super.key, required this.user});

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('patients')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingScreen();
          }
          final profile = snapshot.data?.data() ?? const <String, dynamic>{};
          if (snapshot.hasError || profile['profileComplete'] != true) {
            return PatientProfileScreen(
              user: user,
              isOnboarding: true,
              initialProfile: profile,
              storageError: snapshot.hasError,
            );
          }
          return HomeScreen(user: user, profile: profile);
        },
      );
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
  );
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _isSigningIn = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isSigningIn = true;
      _error = null;
    });
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) return;
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
    } on FirebaseAuthException catch (error) {
      _error = _friendlyAuthError(error.code);
    } catch (_) {
      _error = 'La connexion Google n’a pas abouti. Réessayez.';
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  String _friendlyAuthError(String code) => switch (code) {
    'popup-closed-by-user' => 'La fenêtre de connexion a été fermée.',
    'account-exists-with-different-credential' =>
      'Ce compte utilise une autre méthode de connexion.',
    'network-request-failed' => 'Vérifiez votre connexion Internet.',
    _ => 'Connexion impossible pour le moment. Réessayez.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5F5FF),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Icon(
                      Icons.all_inclusive_rounded,
                      color: Color(0xFF13B7C4),
                      size: 50,
                    ),
                  ),
                ),
                const SizedBox(height: 27),
                const Text(
                  'Bienvenue sur I-ENTIER',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Connectez-vous pour retrouver vos services de santé et votre dossier personnel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.45,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 34),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F0),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFB3261E)),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _isSigningIn ? null : _signInWithGoogle,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    icon: _isSigningIn
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const _GoogleMark(),
                    label: Text(
                      _isSigningIn
                          ? 'Connexion en cours...'
                          : 'Continuer avec Google',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'En continuant, vous acceptez les conditions d’utilisation et la politique de confidentialité.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => const Text(
    'G',
    style: TextStyle(
      color: Color(0xFF4285F4),
      fontSize: 22,
      fontWeight: FontWeight.w800,
    ),
  );
}

class PatientProfileScreen extends StatefulWidget {
  final User user;
  final bool isOnboarding;
  final bool storageError;
  final Map<String, dynamic> initialProfile;
  const PatientProfileScreen({
    super.key,
    required this.user,
    this.isOnboarding = false,
    this.storageError = false,
    this.initialProfile = const <String, dynamic>{},
  });

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _conditionsController;
  late final TextEditingController _allergiesController;
  String? _sex;
  DateTime? _birthDate;
  bool _saving = false;
  final Set<String> _selectedConditions = <String>{};
  static const _conditionOptions = [
    'Diabète',
    'Hypertension',
    'Asthme',
    'Cardiopathie',
  ];

  @override
  void initState() {
    super.initState();
    final data = widget.initialProfile;
    _nameController = TextEditingController(
      text: _profileText(data, ['fullName', 'nomComplet', 'name']).isEmpty
          ? (widget.user.displayName ?? '')
          : _profileText(data, ['fullName', 'nomComplet', 'name']),
    );
    _sex = _profileText(data, ['sex', 'sexe']);
    _birthDate = _profileDate(data['birthDate'] ?? data['dateNaissance']);
    final conditions = _profileStrings(
      data['medicalConditions'] ?? data['maladies'],
    );
    _selectedConditions.addAll(conditions.where(_conditionOptions.contains));
    _conditionsController = TextEditingController(
      text: conditions
          .where((condition) => !_conditionOptions.contains(condition))
          .join(', '),
    );
    _allergiesController = TextEditingController(
      text: _profileStrings(data['allergies']).join(', '),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _conditionsController.dispose();
    _allergiesController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(DateTime.now().year - 25),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Date de naissance',
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() ||
        _birthDate == null ||
        _sex == null) {
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    final customConditions = _conditionsController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    final allergies = _allergiesController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    try {
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.user.uid)
          .set({
            'fullName': _nameController.text.trim(),
            'sex': _sex,
            'birthDate': Timestamp.fromDate(_birthDate!),
            'medicalConditions': {
              ..._selectedConditions,
              ...customConditions,
            }.toList(),
            'allergies': allergies,
            'photoUrl': widget.user.photoURL,
            'profileComplete': true,
            'updatedAt': FieldValue.serverTimestamp(),
            if (widget.initialProfile.isEmpty)
              'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (mounted && !widget.isOnboarding) Navigator.of(context).pop();
    } on FirebaseException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d’enregistrer le profil. Vérifiez les règles Firestore.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final age = _birthDate == null ? null : _ageFrom(_birthDate!);
    return Scaffold(
      appBar: widget.isOnboarding
          ? null
          : AppBar(title: const Text('Profil'), centerTitle: false),
      body: SafeArea(
        top: widget.isOnboarding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 42),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: _GoogleAvatar(user: widget.user, radius: 45)),
                    const SizedBox(height: 20),
                    Text(
                      widget.isOnboarding
                          ? 'Parlons de vous'
                          : 'Profil patient',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      widget.isOnboarding
                          ? 'Ces informations nous aident à vous proposer des services adaptés.'
                          : 'Gardez vos informations de santé à jour.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        height: 1.4,
                        color: AppColors.muted,
                      ),
                    ),
                    if (widget.storageError) ...[
                      const SizedBox(height: 16),
                      const _DirectoryFeedback(
                        icon: Icons.lock_outline,
                        title: 'Accès au profil requis',
                        message:
                            'Autorisez les utilisateurs connectés à lire et écrire leur document patients/{uid}.',
                      ),
                    ],
                    const SizedBox(height: 28),
                    _profileLabel('Nom complet'),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: _profileDecoration('Votre nom complet'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Votre nom est requis.'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    _profileLabel('Sexe'),
                    DropdownButtonFormField<String>(
                      initialValue: _sex?.isEmpty ?? true ? null : _sex,
                      decoration: _profileDecoration('Sélectionnez votre sexe'),
                      items: const [
                        DropdownMenuItem(value: 'Femme', child: Text('Femme')),
                        DropdownMenuItem(value: 'Homme', child: Text('Homme')),
                        DropdownMenuItem(value: 'Autre', child: Text('Autre')),
                        DropdownMenuItem(
                          value: 'Préfère ne pas répondre',
                          child: Text('Préfère ne pas répondre'),
                        ),
                      ],
                      onChanged: (value) => setState(() => _sex = value),
                      validator: (value) =>
                          value == null ? 'Sélectionnez une option.' : null,
                    ),
                    const SizedBox(height: 18),
                    _profileLabel('Date de naissance'),
                    InkWell(
                      onTap: _pickBirthDate,
                      borderRadius: BorderRadius.circular(14),
                      child: InputDecorator(
                        decoration: _profileDecoration(
                          'Sélectionnez votre date de naissance',
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_month_outlined,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _birthDate == null
                                    ? 'Sélectionnez votre date de naissance'
                                    : '${_birthDate!.day.toString().padLeft(2, '0')}/${_birthDate!.month.toString().padLeft(2, '0')}/${_birthDate!.year}',
                              ),
                            ),
                            if (age != null)
                              Text(
                                '$age ans',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (_birthDate == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'La date de naissance est requise.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFFB3261E),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    _profileLabel('Maladies ou antécédents'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _conditionOptions
                          .map(
                            (condition) => FilterChip(
                              label: Text(condition),
                              selected: _selectedConditions.contains(condition),
                              onSelected: (selected) => setState(
                                () => selected
                                    ? _selectedConditions.add(condition)
                                    : _selectedConditions.remove(condition),
                              ),
                              selectedColor: const Color(0xFFE7F0FF),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _conditionsController,
                      maxLines: 2,
                      decoration: _profileDecoration(
                        'Autres maladies, séparées par des virgules (facultatif)',
                      ),
                    ),
                    const SizedBox(height: 18),
                    _profileLabel('Allergies'),
                    TextFormField(
                      controller: _allergiesController,
                      maxLines: 2,
                      decoration: _profileDecoration(
                        'Allergies, séparées par des virgules (facultatif)',
                      ),
                    ),
                    const SizedBox(height: 30),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 21,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              widget.isOnboarding
                                  ? 'Continuer'
                                  : 'Enregistrer les modifications',
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _profileLabel(String value) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(
    value,
    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy),
  ),
);

InputDecoration _profileDecoration(String hint) => InputDecoration(
  hintText: hint,
  filled: true,
  fillColor: const Color(0xFFF8FAFD),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AppColors.border),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AppColors.border),
  ),
);

String _profileText(Map<String, dynamic> data, List<String> keys) =>
    _field(data, keys);

List<String> _profileStrings(dynamic value) {
  if (value is Iterable) return value.map((entry) => entry.toString()).toList();
  if (value is String) {
    return value
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }
  return const [];
}

DateTime? _profileDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

int _ageFrom(DateTime birthDate) {
  final today = DateTime.now();
  var age = today.year - birthDate.year;
  if (today.month < birthDate.month ||
      (today.month == birthDate.month && today.day < birthDate.day)) {
    age--;
  }
  return age;
}

class AppColors {
  static const primary = Color(0xFF1769F5);
  static const navy = Color(0xFF102B5C);
  static const muted = Color(0xFF74809A);
  static const border = Color(0xFFE9EDF5);
}

class HomeScreen extends StatefulWidget {
  final User user;
  final Map<String, dynamic> profile;
  const HomeScreen({super.key, required this.user, required this.profile});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;
  bool _assistantOpen = false;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 32 : 20,
                    18,
                    wide ? 32 : 20,
                    104,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(
                        user: widget.user,
                        profile: widget.profile,
                        onProfileTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PatientProfileScreen(
                              user: widget.user,
                              initialProfile: widget.profile,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _TopTabs(
                        selectedIndex: _selectedTab,
                        onChanged: (index) =>
                            setState(() => _selectedTab = index),
                      ),
                      const SizedBox(height: 24),
                      if (_selectedTab == 0) ...[
                        const _SearchField(),
                        const SizedBox(height: 22),
                        _Hero(wide: wide),
                        const SizedBox(height: 28),
                        const _SectionHeading(
                          title: 'Services',
                          action: 'Voir tout',
                        ),
                        const SizedBox(height: 14),
                        _ServiceGrid(wide: wide),
                        const SizedBox(height: 28),
                        _AssistantCard(
                          open: _assistantOpen,
                          onToggle: () =>
                              setState(() => _assistantOpen = !_assistantOpen),
                        ),
                      ] else if (_selectedTab == 1)
                        const _PersonnelPage()
                      else
                        const _InstitutionsPage(),
                    ],
                  ),
                ),
                if (_selectedTab == 0)
                  Positioned(
                    right: wide ? 32 : 20,
                    bottom: 88,
                    child: _EmergencyButton(),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 76,
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        indicatorColor: const Color(0xFFE8F0FF),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.medical_information_outlined),
            selectedIcon: Icon(Icons.medical_information),
            label: 'Personnel',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_hospital_outlined),
            selectedIcon: Icon(Icons.local_hospital),
            label: 'Institutions',
          ),
        ],
      ),
    );
  }
}

class _TopTabs extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  const _TopTabs({required this.selectedIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: 3,
      separatorBuilder: (context, index) => const SizedBox(width: 9),
      itemBuilder: (context, index) {
        const labels = ['Accueil', 'Personnel', 'Institutions'];
        final selected = index == selectedIndex;
        return ChoiceChip(
          label: Text(labels[index]),
          selected: selected,
          onSelected: (_) => onChanged(index),
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.navy,
            fontWeight: FontWeight.w700,
          ),
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        );
      },
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String? action;
  const _SectionHeading({required this.title, this.action});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: () {},
          child: Text(
            action!,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
    ],
  );
}

class _PersonnelPage extends StatelessWidget {
  const _PersonnelPage();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Personnel médical',
        style: TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Trouvez un professionnel près de chez vous.',
        style: TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 20),
      const _SearchField(hint: 'Médecin, spécialité ou établissement...'),
      const SizedBox(height: 16),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: const [
            _FilterChip('Tous'),
            SizedBox(width: 8),
            _FilterChip('Médecins'),
            SizedBox(width: 8),
            _FilterChip('Infirmiers'),
            SizedBox(width: 8),
            _FilterChip('Disponibles'),
          ],
        ),
      ),
      const SizedBox(height: 22),
      const _SectionHeading(title: 'Professionnels recommandés'),
      const SizedBox(height: 6),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('personnelMedical')
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _DirectoryFeedback(
              icon: Icons.lock_outline,
              title: 'Personnel indisponible',
              message:
                  'Vérifiez les règles Firestore de la collection personnelMedical.',
            );
          }
          if (!snapshot.hasData) return const _DirectoryLoading();
          final records = snapshot.data!.docs
              .map((doc) => _Professional.fromFirestore(doc))
              .toList();
          if (records.isEmpty) {
            return const _DirectoryFeedback(
              icon: Icons.person_search_outlined,
              title: 'Aucun professionnel pour le moment',
              message:
                  'Ajoutez des documents dans personnelMedical depuis Firebase.',
            );
          }
          return Column(
            children: [
              for (final record in records) ...[
                _ProfessionalCard(
                  name: record.name,
                  role: record.role,
                  distance: record.distance,
                  color: record.color,
                  initials: record.initials,
                  available: record.available,
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    ],
  );
}

class _InstitutionsPage extends StatelessWidget {
  const _InstitutionsPage();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Institutions',
        style: TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Des soins de qualité, partout où vous êtes.',
        style: TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 20),
      const _SearchField(hint: 'Rechercher un hôpital, une clinique...'),
      const SizedBox(height: 22),
      const _SectionHeading(title: 'À proximité'),
      const SizedBox(height: 6),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('institution')
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _DirectoryFeedback(
              icon: Icons.lock_outline,
              title: 'Institutions indisponibles',
              message:
                  'Vérifiez les règles Firestore de la collection institution.',
            );
          }
          if (!snapshot.hasData) return const _DirectoryLoading();
          final records = snapshot.data!.docs
              .map((doc) => _Institution.fromFirestore(doc))
              .toList();
          if (records.isEmpty) {
            return const _DirectoryFeedback(
              icon: Icons.location_city_outlined,
              title: 'Aucune institution pour le moment',
              message:
                  'Ajoutez des documents dans institution depuis Firebase.',
            );
          }
          return Column(
            children: [
              for (final record in records) ...[
                _InstitutionCard(
                  name: record.name,
                  type: record.type,
                  distance: record.distance,
                  icon: record.icon,
                  color: record.color,
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    ],
  );
}

class _FilterChip extends StatelessWidget {
  final String label;
  const _FilterChip(this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F7FC),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: AppColors.navy,
      ),
    ),
  );
}

class _ProfessionalCard extends StatelessWidget {
  final String name, role, distance, initials;
  final Color color;
  final bool available;
  const _ProfessionalCard({
    required this.name,
    required this.role,
    required this.distance,
    required this.color,
    required this.initials,
    required this.available,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 29,
          backgroundColor: color,
          child: Text(
            initials,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 3),
              Text(role, style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.verified,
                    size: 15,
                    color: available
                        ? const Color(0xFF23A67A)
                        : AppColors.muted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    available ? 'Disponible' : 'Indisponible',
                    style: TextStyle(
                      fontSize: 12,
                      color: available
                          ? const Color(0xFF23A67A)
                          : AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.location_on_outlined,
                    size: 15,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    distance,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DirectoryLoading extends StatelessWidget {
  const _DirectoryLoading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 36),
    child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
  );
}

class _DirectoryFeedback extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _DirectoryFeedback({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F9FD),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 34),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, height: 1.35),
        ),
      ],
    ),
  );
}

class _Professional {
  final String name;
  final String role;
  final String distance;
  final String initials;
  final Color color;
  final bool available;

  const _Professional({
    required this.name,
    required this.role,
    required this.distance,
    required this.initials,
    required this.color,
    required this.available,
  });

  factory _Professional.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final firstName = _field(data, ['prenom', 'firstName', 'first_name']);
    final lastName = _field(data, ['nom', 'lastName', 'last_name']);
    final fullName = _field(data, [
      'nomComplet',
      'fullName',
      'displayName',
      'name',
    ]);
    final name = fullName.isNotEmpty
        ? fullName
        : [firstName, lastName].where((value) => value.isNotEmpty).join(' ');
    final resolvedName = name.isEmpty ? 'Professionnel de santé' : name;
    return _Professional(
      name: resolvedName,
      role:
          _field(data, [
            'specialite',
            'specialty',
            'role',
            'profession',
          ]).isEmpty
          ? 'Professionnel de santé'
          : _field(data, ['specialite', 'specialty', 'role', 'profession']),
      distance:
          _field(data, [
            'distance',
            'distanceLabel',
            'adresse',
            'address',
          ]).isEmpty
          ? 'À proximité'
          : _field(data, ['distance', 'distanceLabel', 'adresse', 'address']),
      initials: _initials(resolvedName),
      color: const Color(0xFFE7F1FF),
      available: _boolean(data, [
        'disponible',
        'available',
        'isAvailable',
      ], fallback: true),
    );
  }
}

class _Institution {
  final String name;
  final String type;
  final String distance;
  final IconData icon;
  final Color color;

  const _Institution({
    required this.name,
    required this.type,
    required this.distance,
    required this.icon,
    required this.color,
  });

  factory _Institution.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final category = _field(data, [
      'type',
      'categorie',
      'category',
    ]).toLowerCase();
    final name = _field(data, ['nom', 'name', 'nomInstitution', 'displayName']);
    final schedule = _field(data, ['horaires', 'openingHours', 'schedule']);
    final type = category.isEmpty ? 'Institution de santé' : category;
    final isPharmacy = category.contains('pharm');
    final isHospital =
        category.contains('hôpital') ||
        category.contains('hopital') ||
        category.contains('hospital');
    return _Institution(
      name: name.isEmpty ? 'Institution de santé' : name,
      type: schedule.isEmpty ? type : '$type · $schedule',
      distance:
          _field(data, [
            'distance',
            'distanceLabel',
            'adresse',
            'address',
          ]).isEmpty
          ? 'À proximité'
          : _field(data, ['distance', 'distanceLabel', 'adresse', 'address']),
      icon: isPharmacy
          ? Icons.medication_rounded
          : isHospital
          ? Icons.local_hospital_rounded
          : Icons.health_and_safety_rounded,
      color: isPharmacy
          ? const Color(0xFFFFF1E9)
          : isHospital
          ? const Color(0xFFE8F1FF)
          : const Color(0xFFE8F8F4),
    );
  }
}

String _field(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return '';
}

bool _boolean(
  Map<String, dynamic> data,
  List<String> keys, {
  required bool fallback,
}) {
  for (final key in keys) {
    final value = data[key];
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == 'true' || value.toLowerCase() == 'oui';
    }
  }
  return fallback;
}

String _initials(String value) => value
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .take(2)
    .map((part) => part[0].toUpperCase())
    .join();

class _InstitutionCard extends StatelessWidget {
  final String name, type, distance;
  final IconData icon;
  final Color color;
  const _InstitutionCard({
    required this.name,
    required this.type,
    required this.distance,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Icon(icon, color: AppColors.primary, size: 30),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                type,
                style: const TextStyle(color: AppColors.muted, height: 1.3),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    distance,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  final User user;
  final Map<String, dynamic> profile;
  final VoidCallback onProfileTap;
  const _Header({
    required this.user,
    required this.profile,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final profileName = _profileText(profile, ['fullName', 'name']);
    final greetingName = profileName.isEmpty
        ? (user.displayName ?? 'à vous')
        : profileName;
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFFE5F5FF),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.all_inclusive_rounded,
            color: Color(0xFF13B7C4),
            size: 35,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'I-ENTIER',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 23,
                  color: AppColors.navy,
                  letterSpacing: .4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Salut $greetingName',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ],
          ),
        ),
        const _RoundIcon(icon: Icons.notifications_none, badge: '3'),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          label: 'Ouvrir le profil',
          child: InkWell(
            onTap: onProfileTap,
            customBorder: const CircleBorder(),
            child: _GoogleAvatar(user: user, radius: 23),
          ),
        ),
      ],
    );
  }
}

class _GoogleAvatar extends StatelessWidget {
  final User user;
  final double radius;
  const _GoogleAvatar({required this.user, required this.radius});

  @override
  Widget build(BuildContext context) {
    final photoUrl = user.photoURL;
    final initials = (user.displayName ?? user.email ?? 'P')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE3EEFF),
      foregroundImage: photoUrl == null || photoUrl.isEmpty
          ? null
          : NetworkImage(photoUrl),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * .72,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final String? badge;
  const _RoundIcon({required this.icon, this.badge});
  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: AppColors.navy),
      ),
      if (badge != null)
        Positioned(
          right: -2,
          top: -3,
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: const BoxDecoration(
              color: Color(0xFFFF352C),
              shape: BoxShape.circle,
            ),
            child: Text(
              badge!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
    ],
  );
}

class _SearchField extends StatelessWidget {
  final String hint;
  const _SearchField({
    this.hint = 'Rechercher un service, un professionnel...',
  });
  @override
  Widget build(BuildContext context) => Container(
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        Icon(Icons.search, color: AppColors.muted, size: 28),
        SizedBox(width: 16),
        Expanded(
          child: Text(
            hint,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.muted, fontSize: 15),
          ),
        ),
        Icon(Icons.tune, color: AppColors.muted),
      ],
    ),
  );
}

class _Hero extends StatelessWidget {
  final bool wide;
  const _Hero({required this.wide});
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 270),
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFEAF7FF), Color(0xFFD9EFFF)],
      ),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -20,
          top: -30,
          child: Container(
            width: wide ? 360 : 220,
            height: wide ? 360 : 220,
            decoration: const BoxDecoration(
              color: Color(0x66FFFFFF),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              flex: wide ? 5 : 7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Votre santé,\nnotre priorité.',
                    style: TextStyle(
                      fontSize: 32,
                      height: 1.12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Accédez à des services de santé fiables, proches de chez vous.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: Color(0xFF52698C),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 19,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    child: const Text('Trouver un service'),
                  ),
                ],
              ),
            ),
            if (wide) const Expanded(flex: 4, child: _CareIllustration()),
          ],
        ),
        if (!wide)
          const Positioned(
            right: 12,
            bottom: 16,
            child: _CareIllustration(compact: true),
          ),
      ],
    ),
  );
}

class _CareIllustration extends StatelessWidget {
  final bool compact;
  const _CareIllustration({this.compact = false});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: compact ? 76 : 210,
    height: compact ? 76 : 210,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFF9DD7FF),
            shape: BoxShape.circle,
          ),
        ),
        Icon(
          Icons.family_restroom,
          size: compact ? 54 : 142,
          color: AppColors.navy,
        ),
        Positioned(
          right: 0,
          bottom: 10,
          child: CircleAvatar(
            radius: compact ? 15 : 30,
            backgroundColor: const Color(0xFF3B9BFF),
            child: Icon(
              Icons.add,
              color: Colors.white,
              size: compact ? 20 : 38,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ServiceGrid extends StatelessWidget {
  final bool wide;
  const _ServiceGrid({required this.wide});
  @override
  Widget build(BuildContext context) {
    final services = [
      (
        'Pharmacie',
        'Commandez vos médicaments en ligne',
        Icons.medication_rounded,
        const Color(0xFFE7F8F4),
        const Color(0xFF11A98B),
      ),
      (
        'Don de sang',
        'Trouvez un centre et sauvez des vies',
        Icons.bloodtype_rounded,
        const Color(0xFFFFEFF1),
        const Color(0xFFF04B62),
      ),
      (
        'Suivi de cycle',
        'Suivez votre cycle et recevez des conseils',
        Icons.calendar_month_rounded,
        const Color(0xFFF1EEFF),
        const Color(0xFF8552C8),
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final count = c.maxWidth > 620 ? 3 : 1;
        return GridView.count(
          crossAxisCount: count,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: count == 1 ? 2.65 : 0.70,
          children: services
              .map(
                (s) => _ServiceCard(
                  title: s.$1,
                  description: s.$2,
                  icon: s.$3,
                  background: s.$4,
                  accent: s.$5,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final String title, description;
  final IconData icon;
  final Color background, accent;
  const _ServiceCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.background,
    required this.accent,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(26),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(19),
          ),
          child: Icon(icon, color: accent, size: 34),
        ),
        const Spacer(),
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: Color(0xFF172033),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          description,
          style: const TextStyle(height: 1.35, color: Color(0xFF59667C)),
        ),
        const SizedBox(height: 16),
        Text(
          'Accéder  →',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: accent,
          ),
        ),
      ],
    ),
  );
}

class _AssistantCard extends StatelessWidget {
  final bool open;
  final VoidCallback onToggle;
  const _AssistantCard({required this.open, required this.onToggle});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    width: double.infinity,
    height: open ? 350 : 190,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFF6F9FF), Color(0xFFEAF1FF)],
      ),
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 27,
              backgroundColor: Color(0xFFBED5FF),
              child: Icon(Icons.smart_toy_outlined, color: AppColors.navy),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'I-ENTIER AI',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                      color: AppColors.navy,
                    ),
                  ),
                  Text(
                    'Votre assistant santé intelligent',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onToggle,
              icon: Icon(open ? Icons.expand_less : Icons.more_horiz),
            ),
          ],
        ),
        const Spacer(),
        Center(
          child: Column(
            children: const [
              Text(
                'Kijan mwen ka ede w 👋',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Je suis là pour vous aider',
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (open)
          TextField(
            decoration: InputDecoration(
              hintText: 'Écrivez votre message...',
              suffixIcon: const Icon(Icons.send, color: AppColors.primary),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
          ),
      ],
    ),
  );
}

class _EmergencyButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
    onPressed: () {},
    backgroundColor: const Color(0xFFFF3029),
    foregroundColor: Colors.white,
    elevation: 7,
    icon: const Icon(Icons.emergency),
    label: const Text(
      'Urgences',
      style: TextStyle(fontWeight: FontWeight.bold),
    ),
  );
}
