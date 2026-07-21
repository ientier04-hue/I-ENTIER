import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';
import 'cycle_tracking_page.dart';
import 'health_tracking_page.dart';
import 'laboratory_page.dart';
import 'mental_health_page.dart';
import 'notification_service.dart';
import 'notifications_page.dart';
import 'pharmacy_page.dart';
import 'preventive_medicine_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseNotificationService.instance.initialize();
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
      scaffoldBackgroundColor: AppColors.canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.teal,
        error: const Color(0xFFD92D20),
        surface: Colors.white,
      ),
      fontFamily: 'Arial',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
          letterSpacing: -.8,
        ),
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
          letterSpacing: -.5,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
        ),
        bodyLarge: TextStyle(color: AppColors.ink, height: 1.45),
        bodyMedium: TextStyle(color: AppColors.muted, height: 1.4),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.navy,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: AppColors.navy,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primarySoft,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
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
          ? AccountBootstrap(user: snapshot.data!)
          : const SignInScreen();
    },
  );
}

class AccountBootstrap extends StatefulWidget {
  final User user;
  const AccountBootstrap({super.key, required this.user});

  @override
  State<AccountBootstrap> createState() => _AccountBootstrapState();
}

class _AccountBootstrapState extends State<AccountBootstrap> {
  late final Future<Map<String, dynamic>> _account = _loadAccount();

  Future<Map<String, dynamic>> _loadAccount() async {
    final reference = FirebaseFirestore.instance
        .collection('user')
        .doc(widget.user.uid);
    final snapshot = await reference.get();
    final existing = snapshot.data() ?? const <String, dynamic>{};
    await reference.set({
      'displayName': _profileText(existing, ['displayName']).isEmpty
          ? (widget.user.displayName ?? '')
          : _profileText(existing, ['displayName']),
      'email': widget.user.email ?? _profileText(existing, ['email']),
      'photoUrl': widget.user.photoURL ?? _profileText(existing, ['photoUrl']),
      'provider': 'google.com',
      'updatedAt': FieldValue.serverTimestamp(),
      if (!snapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return {
      ...existing,
      'displayName':
          widget.user.displayName ?? _profileText(existing, ['displayName']),
      'email': widget.user.email ?? _profileText(existing, ['email']),
      'photoUrl': widget.user.photoURL ?? _profileText(existing, ['photoUrl']),
    };
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _account,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const _LoadingScreen();
      }
      if (snapshot.hasError) {
        return const _AccountAccessError();
      }
      return PatientProfileGate(user: widget.user, account: snapshot.data!);
    },
  );
}

class _AccountAccessError extends StatelessWidget {
  const _AccountAccessError();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: _DirectoryFeedback(
          icon: Icons.lock_outline,
          title: 'Accès au compte requis',
          message:
              'Autorisez chaque utilisateur connecté à lire et écrire son document user/{uid}.',
        ),
      ),
    ),
  );
}

class PatientProfileGate extends StatelessWidget {
  final User user;
  final Map<String, dynamic> account;
  const PatientProfileGate({
    super.key,
    required this.user,
    required this.account,
  });

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
              accountProfile: account,
              isOnboarding: true,
              initialProfile: profile,
              storageError: snapshot.hasError,
            );
          }
          return HomeScreen(
            user: user,
            account: account,
            patientProfile: profile,
          );
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
    backgroundColor: AppColors.navy,
    body: Stack(
      fit: StackFit.expand,
      children: [
        const _SignInBackdrop(),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 900;
              final horizontalPadding = desktop ? 48.0 : 20.0;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: desktop ? 32 : 20,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 1180,
                      minHeight: constraints.maxHeight - (desktop ? 64 : 40),
                    ),
                    child: desktop
                        ? Row(
                            children: [
                              const Expanded(flex: 11, child: _SignInStory()),
                              const SizedBox(width: 70),
                              Expanded(
                                flex: 9,
                                child: _SignInCard(
                                  isSigningIn: _isSigningIn,
                                  error: _error,
                                  onGoogleTap: _signInWithGoogle,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const _MobileSignInBrand(),
                              const SizedBox(height: 26),
                              _SignInCard(
                                isSigningIn: _isSigningIn,
                                error: _error,
                                onGoogleTap: _signInWithGoogle,
                              ),
                              const SizedBox(height: 20),
                              const _SignInFooter(light: true),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _SignInBackdrop extends StatelessWidget {
  const _SignInBackdrop();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF081B3A), Color(0xFF0B3263), Color(0xFF075B70)],
        stops: [0, .55, 1],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          left: -100,
          top: -130,
          child: _GlowOrb(size: 390, color: Color(0x2915BFCB)),
        ),
        Positioned(
          right: -90,
          bottom: -120,
          child: _GlowOrb(size: 430, color: Color(0x241E7BFF)),
        ),
        Positioned(
          right: 28,
          top: 34,
          child: _HealthCross(color: Color(0x12FFFFFF), size: 94),
        ),
      ],
    ),
  );
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      boxShadow: [BoxShadow(color: color, blurRadius: 90, spreadRadius: 28)],
    ),
  );
}

class _SignInStory extends StatelessWidget {
  const _SignInStory();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const _BrandLockup(light: true),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Eyebrow(label: 'VOTRE SANTÉ, SIMPLEMENT'),
            SizedBox(height: 20),
            Text(
              'Toute votre santé,\nau même endroit.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 48,
                height: 1.04,
                letterSpacing: -1.8,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 22),
            SizedBox(
              width: 510,
              child: Text(
                'Trouvez les bons professionnels, accédez aux services essentiels et gardez vos informations de santé à portée de main.',
                style: TextStyle(
                  color: Color(0xFFD5E7F6),
                  fontSize: 17,
                  height: 1.55,
                ),
              ),
            ),
            SizedBox(height: 30),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _FeaturePill(
                  icon: Icons.verified_user_outlined,
                  label: 'Données sécurisées',
                ),
                _FeaturePill(
                  icon: Icons.favorite_border_rounded,
                  label: 'Services personnalisés',
                ),
              ],
            ),
          ],
        ),
        const _SignInFooter(light: true),
      ],
    ),
  );
}

class _MobileSignInBrand extends StatelessWidget {
  const _MobileSignInBrand();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      _BrandLockup(light: true, centered: true),
      SizedBox(height: 12),
      Text(
        'Votre santé, simplement.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFFBDD7E9), fontSize: 15),
      ),
    ],
  );
}

class _SignInCard extends StatelessWidget {
  final bool isSigningIn;
  final String? error;
  final VoidCallback onGoogleTap;
  const _SignInCard({
    required this.isSigningIn,
    required this.error,
    required this.onGoogleTap,
  });

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 480),
    padding: const EdgeInsets.fromLTRB(34, 36, 34, 30),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: const Color(0x26FFFFFF)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x3800122D),
          blurRadius: 46,
          offset: Offset(0, 24),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.lock_open_rounded,
              color: AppColors.primary,
              size: 27,
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Bienvenue sur I-ENTIER',
          style: TextStyle(
            fontSize: 30,
            height: 1.12,
            letterSpacing: -.7,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Connectez-vous pour retrouver votre espace santé personnel.',
          style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 28),
        if (error != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F0),
              border: Border.all(color: const Color(0xFFFDC9C5)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFD92D20),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    error!,
                    style: const TextStyle(
                      color: Color(0xFF9E231B),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          height: 58,
          child: FilledButton.icon(
            onPressed: isSigningIn ? null : onGoogleTap,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              disabledBackgroundColor: const Color(0xFFB7C1D0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: isSigningIn
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const _GoogleMark(),
            label: Text(
              isSigningIn ? 'Connexion en cours...' : 'Continuer avec Google',
            ),
          ),
        ),
        const SizedBox(height: 22),
        const _TrustLine(),
        const SizedBox(height: 24),
        const Divider(color: AppColors.border),
        const SizedBox(height: 18),
        const Text(
          'En continuant, vous acceptez nos conditions d’utilisation et notre politique de confidentialité.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.45,
            color: AppColors.muted,
          ),
        ),
      ],
    ),
  );
}

class _BrandLockup extends StatelessWidget {
  final bool light;
  final bool centered;
  const _BrandLockup({required this.light, this.centered = false});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
    children: [
      _BrandMark(light: light),
      const SizedBox(width: 13),
      Text(
        'I-ENTIER',
        style: TextStyle(
          color: light ? Colors.white : AppColors.navy,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: .7,
        ),
      ),
    ],
  );
}

class _BrandMark extends StatelessWidget {
  final bool light;
  const _BrandMark({this.light = false});

  @override
  Widget build(BuildContext context) => Container(
    width: 50,
    height: 50,
    decoration: BoxDecoration(
      color: light ? const Color(0x1FFFFFFF) : AppColors.primarySoft,
      borderRadius: BorderRadius.circular(16),
      border: light ? Border.all(color: const Color(0x35FFFFFF)) : null,
    ),
    child: Icon(
      Icons.all_inclusive_rounded,
      color: light ? const Color(0xFF6DE5DD) : AppColors.teal,
      size: 32,
    ),
  );
}

class _Eyebrow extends StatelessWidget {
  final String label;
  const _Eyebrow({required this.label});

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: Color(0xFF6DE5DD),
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.8,
    ),
  );
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0x14FFFFFF),
      border: Border.all(color: const Color(0x26FFFFFF)),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF8DE6DF), size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _TrustLine extends StatelessWidget {
  const _TrustLine();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.shield_outlined, size: 17, color: AppColors.teal),
      SizedBox(width: 7),
      Flexible(
        child: Text(
          'Connexion sécurisée et confidentielle',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _SignInFooter extends StatelessWidget {
  final bool light;
  const _SignInFooter({required this.light});

  @override
  Widget build(BuildContext context) => Text(
    '© ${DateTime.now().year} I-ENTIER  •  Santé accessible, partout.',
    textAlign: TextAlign.center,
    style: TextStyle(
      color: light ? const Color(0xFF9AB8CE) : AppColors.muted,
      fontSize: 11.5,
    ),
  );
}

class _HealthCross extends StatelessWidget {
  final Color color;
  final double size;
  const _HealthCross({required this.color, required this.size});

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.health_and_safety_rounded, color: color, size: size);
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 26,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
    ),
    child: const Text(
      'G',
      style: TextStyle(
        color: Color(0xFF4285F4),
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class PatientProfileScreen extends StatefulWidget {
  final User user;
  final Map<String, dynamic> accountProfile;
  final bool isOnboarding;
  final bool storageError;
  final Map<String, dynamic> initialProfile;
  const PatientProfileScreen({
    super.key,
    required this.user,
    this.accountProfile = const <String, dynamic>{},
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
  late final TextEditingController _weightController;
  late final TextEditingController _heightController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emergencyNameController;
  late final TextEditingController _emergencyRelationshipController;
  late final TextEditingController _emergencyPhoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _conditionsController;
  late final TextEditingController _allergiesController;
  late final TextEditingController _medicationsController;
  late final TextEditingController _surgeriesController;
  late final TextEditingController _specialNeedsController;
  late final TextEditingController _primaryDoctorController;
  late final TextEditingController _insuranceController;
  String? _sex;
  String? _bloodType;
  String? _pregnancyStatus;
  DateTime? _birthDate;
  bool _saving = false;
  final Set<String> _selectedConditions = <String>{};
  static const _conditionOptions = [
    'Diabète',
    'Hypertension',
    'Asthme',
    'Cardiopathie',
  ];
  static const _bloodTypeOptions = [
    'A+',
    'A−',
    'B+',
    'B−',
    'AB+',
    'AB−',
    'O+',
    'O−',
    'Je ne sais pas',
  ];
  static const _pregnancyOptions = [
    'Oui',
    'Non',
    'Non applicable',
    'Préfère ne pas répondre',
  ];

  @override
  void initState() {
    super.initState();
    final data = widget.initialProfile;
    final accountName = _profileText(widget.accountProfile, [
      'displayName',
      'fullName',
      'name',
    ]);
    final legacyPatientName = _profileText(data, [
      'fullName',
      'nomComplet',
      'name',
    ]);
    _nameController = TextEditingController(
      text: accountName.isNotEmpty
          ? accountName
          : legacyPatientName.isNotEmpty
          ? legacyPatientName
          : (widget.user.displayName ?? ''),
    );
    _sex = _profileText(data, ['sex', 'sexe']);
    _birthDate = _profileDate(data['birthDate'] ?? data['dateNaissance']);
    _weightController = TextEditingController(
      text: _profileMeasurementText(data['weightKg'] ?? data['poids']),
    );
    _heightController = TextEditingController(
      text: _profileMeasurementText(data['heightCm'] ?? data['taille']),
    );
    _phoneController = TextEditingController(
      text: _profileText(data, ['phone', 'telephone']),
    );
    final emergencyValue = data['emergencyContact'];
    final emergencyContact = emergencyValue is Map
        ? emergencyValue.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    _emergencyNameController = TextEditingController(
      text: _profileText(emergencyContact, ['name', 'nom']).isNotEmpty
          ? _profileText(emergencyContact, ['name', 'nom'])
          : _profileText(data, ['emergencyContactName']),
    );
    _emergencyRelationshipController = TextEditingController(
      text: _profileText(emergencyContact, ['relationship', 'lien']).isNotEmpty
          ? _profileText(emergencyContact, ['relationship', 'lien'])
          : _profileText(data, ['emergencyContactRelationship']),
    );
    _emergencyPhoneController = TextEditingController(
      text: _profileText(emergencyContact, ['phone', 'telephone']).isNotEmpty
          ? _profileText(emergencyContact, ['phone', 'telephone'])
          : _profileText(data, ['emergencyContactPhone']),
    );
    _addressController = TextEditingController(
      text: _profileText(data, ['address', 'adresse', 'commune']),
    );
    _bloodType = _profileText(data, ['bloodType', 'groupeSanguin']);
    _pregnancyStatus = _profileText(data, [
      'pregnancyStatus',
      'statutGrossesse',
    ]);
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
    _medicationsController = TextEditingController(
      text: _profileStrings(
        data['currentMedications'] ?? data['medicaments'],
      ).join(', '),
    );
    _surgeriesController = TextEditingController(
      text: _profileStrings(
        data['previousSurgeries'] ?? data['interventions'],
      ).join(', '),
    );
    _specialNeedsController = TextEditingController(
      text: _profileText(data, ['specialNeeds', 'besoinsParticuliers']),
    );
    _primaryDoctorController = TextEditingController(
      text: _profileText(data, ['primaryDoctor', 'medecinTraitant']),
    );
    _insuranceController = TextEditingController(
      text: _profileText(data, ['insurance', 'assurance']),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _phoneController.dispose();
    _emergencyNameController.dispose();
    _emergencyRelationshipController.dispose();
    _emergencyPhoneController.dispose();
    _addressController.dispose();
    _conditionsController.dispose();
    _allergiesController.dispose();
    _medicationsController.dispose();
    _surgeriesController.dispose();
    _specialNeedsController.dispose();
    _primaryDoctorController.dispose();
    _insuranceController.dispose();
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
    final medications = _profileCommaSeparated(_medicationsController.text);
    final surgeries = _profileCommaSeparated(_surgeriesController.text);
    try {
      final accountReference = FirebaseFirestore.instance
          .collection('user')
          .doc(widget.user.uid);
      final patientReference = FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.user.uid);
      final patientData = <String, dynamic>{
        'sex': _sex,
        'birthDate': Timestamp.fromDate(_birthDate!),
        'weightKg': _profileMeasurement(_weightController.text),
        'heightCm': _profileMeasurement(_heightController.text),
        'phone': _phoneController.text.trim(),
        'emergencyContact': {
          'name': _emergencyNameController.text.trim(),
          'relationship': _emergencyRelationshipController.text.trim(),
          'phone': _emergencyPhoneController.text.trim(),
        },
        if (!widget.isOnboarding) ...{
          'address': _addressController.text.trim(),
          'bloodType': _bloodType ?? '',
          'medicalConditions': {
            ..._selectedConditions,
            ...customConditions,
          }.toList(),
          'allergies': allergies,
          'currentMedications': medications,
          'previousSurgeries': surgeries,
          'specialNeeds': _specialNeedsController.text.trim(),
          'pregnancyStatus': _pregnancyStatus ?? '',
          'primaryDoctor': _primaryDoctorController.text.trim(),
          'insurance': _insuranceController.text.trim(),
        },
        'profileComplete': true,
        'updatedAt': FieldValue.serverTimestamp(),
        if (widget.initialProfile.isEmpty)
          'createdAt': FieldValue.serverTimestamp(),
      };
      await Future.wait([
        accountReference.set({
          'displayName': _nameController.text.trim(),
          'email': widget.user.email ?? '',
          'photoUrl': widget.user.photoURL,
          'provider': 'google.com',
          'updatedAt': FieldValue.serverTimestamp(),
          if (widget.accountProfile.isEmpty)
            'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
        patientReference.set(patientData, SetOptions(merge: true)),
      ]);
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
    final bodyMassIndex = _bodyMassIndex(
      _weightController.text,
      _heightController.text,
    );
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
                          ? 'Renseignez uniquement les informations essentielles. Vous pourrez compléter votre dossier plus tard dans votre profil.'
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
                    const SizedBox(height: 18),
                    _profileLabel('Poids'),
                    TextFormField(
                      controller: _weightController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: _profileDecoration(
                        'Votre poids',
                      ).copyWith(suffixText: 'kg'),
                      onChanged: (_) => setState(() {}),
                      validator: (value) => _profileMeasurementError(
                        value,
                        label: 'Le poids',
                        minimum: 1,
                        maximum: 500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _profileLabel('Taille'),
                    TextFormField(
                      controller: _heightController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: _profileDecoration(
                        'Votre taille',
                      ).copyWith(suffixText: 'cm'),
                      onChanged: (_) => setState(() {}),
                      validator: (value) => _profileMeasurementError(
                        value,
                        label: 'La taille',
                        minimum: 30,
                        maximum: 300,
                      ),
                    ),
                    if (bodyMassIndex != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'IMC calculé : ${bodyMassIndex.toStringAsFixed(1)}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    _profileLabel('Numéro de téléphone'),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [_phoneInputFormatter],
                      decoration: _profileDecoration(
                        'Votre numéro de téléphone',
                      ),
                      validator: (value) => _phoneError(
                        value,
                        requiredMessage: 'Votre numéro est requis.',
                      ),
                    ),
                    const SizedBox(height: 28),
                    _profileSectionTitle(
                      'Contact d’urgence',
                      'Cette personne pourra être contactée en cas de besoin.',
                    ),
                    _profileLabel('Nom complet'),
                    TextFormField(
                      controller: _emergencyNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: _profileDecoration(
                        'Nom du contact d’urgence',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Le nom du contact est requis.'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    _profileLabel('Lien avec vous'),
                    TextFormField(
                      controller: _emergencyRelationshipController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _profileDecoration(
                        'Ex. parent, conjoint(e), ami(e)',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Le lien avec le contact est requis.'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    _profileLabel('Téléphone du contact'),
                    TextFormField(
                      controller: _emergencyPhoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [_phoneInputFormatter],
                      decoration: _profileDecoration(
                        'Numéro du contact d’urgence',
                      ),
                      validator: (value) => _phoneError(
                        value,
                        requiredMessage:
                            'Le numéro du contact d’urgence est requis.',
                      ),
                    ),
                    if (!widget.isOnboarding) ...[
                      const SizedBox(height: 34),
                      _profileSectionTitle(
                        'Informations complémentaires',
                        'Ces renseignements sont facultatifs et peuvent être modifiés à tout moment.',
                      ),
                      _profileLabel('Adresse ou commune'),
                      TextFormField(
                        controller: _addressController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _profileDecoration(
                          'Votre adresse ou votre commune (facultatif)',
                        ),
                      ),
                      const SizedBox(height: 18),
                      _profileLabel('Groupe sanguin'),
                      DropdownButtonFormField<String>(
                        initialValue: _bloodTypeOptions.contains(_bloodType)
                            ? _bloodType
                            : null,
                        decoration: _profileDecoration(
                          'Sélectionnez votre groupe (facultatif)',
                        ),
                        items: _bloodTypeOptions
                            .map(
                              (option) => DropdownMenuItem(
                                value: option,
                                child: Text(option),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _bloodType = value),
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
                                selected: _selectedConditions.contains(
                                  condition,
                                ),
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
                          'Allergies médicamenteuses ou alimentaires (facultatif)',
                        ),
                      ),
                      const SizedBox(height: 18),
                      _profileLabel('Médicaments actuels'),
                      TextFormField(
                        controller: _medicationsController,
                        maxLines: 2,
                        decoration: _profileDecoration(
                          'Médicaments séparés par des virgules (facultatif)',
                        ),
                      ),
                      const SizedBox(height: 18),
                      _profileLabel('Interventions chirurgicales antérieures'),
                      TextFormField(
                        controller: _surgeriesController,
                        maxLines: 2,
                        decoration: _profileDecoration(
                          'Interventions séparées par des virgules (facultatif)',
                        ),
                      ),
                      const SizedBox(height: 18),
                      _profileLabel('Handicap ou besoin particulier'),
                      TextFormField(
                        controller: _specialNeedsController,
                        maxLines: 2,
                        decoration: _profileDecoration(
                          'Besoin d’accessibilité ou accompagnement (facultatif)',
                        ),
                      ),
                      const SizedBox(height: 18),
                      _profileLabel('Grossesse'),
                      DropdownButtonFormField<String>(
                        initialValue:
                            _pregnancyOptions.contains(_pregnancyStatus)
                            ? _pregnancyStatus
                            : null,
                        decoration: _profileDecoration(
                          'Sélectionnez une option (facultatif)',
                        ),
                        items: _pregnancyOptions
                            .map(
                              (option) => DropdownMenuItem(
                                value: option,
                                child: Text(option),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _pregnancyStatus = value),
                      ),
                      const SizedBox(height: 18),
                      _profileLabel('Médecin traitant'),
                      TextFormField(
                        controller: _primaryDoctorController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _profileDecoration(
                          'Nom du médecin traitant (facultatif)',
                        ),
                      ),
                      const SizedBox(height: 18),
                      _profileLabel('Assurance ou couverture médicale'),
                      TextFormField(
                        controller: _insuranceController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _profileDecoration(
                          'Nom de l’assurance ou couverture (facultatif)',
                        ),
                      ),
                    ],
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

Widget _profileSectionTitle(String title, String description) => Padding(
  padding: const EdgeInsets.only(bottom: 20),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 5),
      Text(description, style: const TextStyle(color: AppColors.muted)),
    ],
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

List<String> _profileCommaSeparated(String value) => value
    .split(',')
    .map((entry) => entry.trim())
    .where((entry) => entry.isNotEmpty)
    .toList();

final _phoneInputFormatter = FilteringTextInputFormatter.allow(
  RegExp(r'[0-9+() -]'),
);

String? _phoneError(String? value, {required String requiredMessage}) {
  if (value == null || value.trim().isEmpty) return requiredMessage;
  final digitCount = RegExp(r'\d').allMatches(value).length;
  if (digitCount < 8 || digitCount > 15) {
    return 'Entrez un numéro de téléphone valide.';
  }
  return null;
}

DateTime? _profileDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

double? _profileMeasurement(String value) =>
    double.tryParse(value.trim().replaceAll(',', '.'));

double? _bodyMassIndex(String weightValue, String heightValue) {
  final weight = _profileMeasurement(weightValue);
  final heightCm = _profileMeasurement(heightValue);
  if (weight == null ||
      heightCm == null ||
      weight <= 0 ||
      weight > 500 ||
      heightCm < 30 ||
      heightCm > 300) {
    return null;
  }
  final heightMeters = heightCm / 100;
  return weight / (heightMeters * heightMeters);
}

String _profileMeasurementText(dynamic value) {
  if (value == null) return '';
  final measurement = value is num
      ? value.toDouble()
      : _profileMeasurement(value.toString());
  if (measurement == null) return '';
  return measurement == measurement.roundToDouble()
      ? measurement.toInt().toString()
      : measurement.toString();
}

String? _profileMeasurementError(
  String? value, {
  required String label,
  required double minimum,
  required double maximum,
}) {
  if (value == null || value.trim().isEmpty) return '$label est requis.';
  final measurement = _profileMeasurement(value);
  if (measurement == null || measurement < minimum || measurement > maximum) {
    return 'Entrez une valeur valide.';
  }
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
  static const primary = Color(0xFF176BFF);
  static const primarySoft = Color(0xFFEAF1FF);
  static const teal = Color(0xFF0AA6A6);
  static const navy = Color(0xFF102A56);
  static const ink = Color(0xFF344054);
  static const muted = Color(0xFF667085);
  static const border = Color(0xFFE4EAF2);
  static const canvas = Color(0xFFF5F8FC);
}

/// Données indépendantes du rendu. La même structure peut venir plus tard
/// d'une collection Firestore ou d'une API plutôt que de [_homeServices].
class HealthService {
  final String id;
  final String title;
  final String summary;
  final String imagePath;
  final String backgroundColor;
  final String accentColor;
  final String actionLabel;
  final String? externalUrl;
  final IconData? icon;

  const HealthService({
    required this.id,
    required this.title,
    required this.summary,
    required this.imagePath,
    required this.backgroundColor,
    required this.accentColor,
    this.actionLabel = 'Accéder',
    this.externalUrl,
    this.icon,
  });

  /// Format attendu, par exemple depuis Firebase :
  /// {title, summary, imagePath, backgroundColor, accentColor, actionLabel}
  factory HealthService.fromMap(String id, Map<String, dynamic> data) =>
      HealthService(
        id: id,
        title: data['title']?.toString() ?? '',
        summary: data['summary']?.toString() ?? '',
        imagePath:
            data['imagePath']?.toString() ?? data['imageUrl']?.toString() ?? '',
        backgroundColor: data['backgroundColor']?.toString() ?? '#FFFFFF',
        accentColor: data['accentColor']?.toString() ?? '#1769F5',
        actionLabel: data['actionLabel']?.toString() ?? 'Accéder',
        externalUrl: data['externalUrl']?.toString() ?? data['url']?.toString(),
      );

  bool get hasRemoteImage =>
      imagePath.startsWith('https://') || imagePath.startsWith('http://');

  Color get background => _colorFromHex(backgroundColor, Colors.white);
  Color get accent => _colorFromHex(accentColor, AppColors.primary);

  static Color _colorFromHex(String value, Color fallback) {
    final normalized = value.trim().replaceFirst('#', '');
    final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
    final colorValue = int.tryParse(hex, radix: 16);
    return colorValue == null ? fallback : Color(colorValue);
  }
}

const _homeServices = <HealthService>[
  HealthService(
    id: 'pharmacie',
    title: 'Pharmacie',
    summary: 'Commandez vos médicaments en ligne',
    imagePath: 'pharma.png',
    backgroundColor: '#D7F5F1',
    accentColor: '#009B88',
  ),
  HealthService(
    id: 'don-de-sang',
    title: 'Don de sang',
    summary: 'Trouvez un centre et sauvez des vies',
    imagePath: 'sang.png',
    backgroundColor: '#FFA2A8',
    accentColor: '#F01924',
    externalUrl: 'https://www.croixrouge.ht/2-check-up/',
  ),
  HealthService(
    id: 'laboratoire',
    title: 'Laboratoire',
    summary: 'Trouvez un labo pour votre examen',
    imagePath: 'laboratoire.png',
    backgroundColor: '#DDF6F4',
    accentColor: '#009B88',
  ),
  HealthService(
    id: 'suivi-cycle',
    title: 'Suivi de cycle',
    summary: 'Comprenez votre cycle et vos symptômes',
    imagePath: 'regles.png',
    backgroundColor: '#F0E8FF',
    accentColor: '#7C5CE5',
  ),
  HealthService(
    id: 'soutien-psychologique',
    title: 'Bien-être mental',
    summary: 'Écoutez-vous et trouvez du soutien',
    imagePath: 'mental_health.png',
    backgroundColor: '#F3ECFF',
    accentColor: '#7656D8',
    actionLabel: 'Prendre soin de moi',
  ),
  HealthService(
    id: 'medecine-preventive',
    title: 'Prévention',
    summary: 'Planifiez vos bilans et protégez votre santé',
    imagePath: 'preventive_medicine.png',
    backgroundColor: '#E7F3FF',
    accentColor: '#176BFF',
    actionLabel: 'Voir mon plan',
  ),
];

class HomeScreen extends StatefulWidget {
  final User user;
  final Map<String, dynamic> account;
  final Map<String, dynamic> patientProfile;
  final Stream<List<AppNotification>>? notificationStream;
  const HomeScreen({
    super.key,
    required this.user,
    required this.account,
    required this.patientProfile,
    this.notificationStream,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;
  List<AppNotification> _notifications = const [];
  StreamSubscription<List<AppNotification>>? _notificationSubscription;
  Timer? _notificationClock;

  bool get _usesFirebaseNotifications =>
      widget.notificationStream == null && Firebase.apps.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.notificationStream == null && Firebase.apps.isEmpty) {
      _notifications = defaultAppNotifications();
    }
    final notificationStream =
        widget.notificationStream ??
        (_usesFirebaseNotifications
            ? FirebaseNotificationService.instance.watchNotifications(
                widget.user.uid,
              )
            : Stream.value(defaultAppNotifications()));
    _notificationSubscription = notificationStream.listen(
      (notifications) {
        if (mounted) setState(() => _notifications = notifications);
      },
      onError: (Object _) {
        // Le reste de l’accueil reste disponible hors connexion.
      },
    );
    _notificationClock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    if (_usesFirebaseNotifications) {
      unawaited(
        FirebaseNotificationService.instance.startSync(widget.user.uid),
      );
    }
  }

  int get _unreadNotificationCount => _notifications
      .where(
        (notification) =>
            !notification.isRead && notification.isDeliveredAt(DateTime.now()),
      )
      .length;

  @override
  void dispose() {
    _notificationClock?.cancel();
    unawaited(_notificationSubscription?.cancel());
    if (_usesFirebaseNotifications) {
      unawaited(FirebaseNotificationService.instance.stopSync());
    }
    super.dispose();
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsPage(
          patientId: _usesFirebaseNotifications ? widget.user.uid : null,
          notificationStream: widget.notificationStream,
          notifications: _notifications
              .where(
                (notification) => notification.isDeliveredAt(DateTime.now()),
              )
              .toList(),
          onNotificationsChanged: (notifications) {
            if (!mounted) return;
            setState(() => _notifications = List.of(notifications));
          },
        ),
      ),
    );
  }

  Future<void> _openAiAssistant() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    Route<dynamic>? assistantRoute;
    final transitionController = AnimationController(
      vsync: navigator,
      duration: const Duration(milliseconds: 620),
      reverseDuration: const Duration(milliseconds: 420),
    );

    try {
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: const Color(0xB30A1930),
        elevation: 0,
        enableDrag: false,
        showDragHandle: false,
        transitionAnimationController: transitionController,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width,
          maxHeight: MediaQuery.sizeOf(context).height,
        ),
        builder: (sheetContext) {
          assistantRoute ??= ModalRoute.of(sheetContext);
          return _AiAssistantSheet(
            onClose: () async {
              if (transitionController.status != AnimationStatus.dismissed) {
                await transitionController.reverse();
              }
              final route = assistantRoute;
              if (route != null && route.isActive) {
                navigator.removeRoute(route);
              }
            },
          );
        },
      );
    } finally {
      transitionController.dispose();
    }
  }

  Future<void> _openService(HealthService service) async {
    final externalUrl = service.externalUrl;
    if (externalUrl != null && externalUrl.isNotEmpty) {
      final launched = await launchUrl(
        Uri.parse(externalUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d’ouvrir ${service.title}.')),
        );
      }
      return;
    }

    if (service.id == 'pharmacie') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PharmacyPage(patientId: widget.user.uid),
        ),
      );
      return;
    }
    if (service.id == 'laboratoire') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LaboratoryPage(patientId: widget.user.uid),
        ),
      );
      return;
    }
    if (service.id == 'suivi-cycle') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CycleTrackingPage(patientId: widget.user.uid),
        ),
      );
      return;
    }
    if (service.id == 'soutien-psychologique') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MentalHealthPage(
            patientId: widget.user.uid,
            patientProfile: widget.patientProfile,
          ),
        ),
      );
      return;
    }
    if (service.id == 'medecine-preventive') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PreventiveMedicinePage(
            patientId: widget.user.uid,
            patientProfile: widget.patientProfile,
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Le service « ${service.title} » arrive bientôt.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      extendBody: true,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 42 : 20,
                    wide ? 28 : 18,
                    wide ? 42 : 20,
                    104,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_selectedTab == 0) ...[
                        _Header(
                          unreadNotificationCount: _unreadNotificationCount,
                          onNotificationsTap: _openNotifications,
                          onProfileTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PatientProfileScreen(
                                user: widget.user,
                                accountProfile: widget.account,
                                initialProfile: widget.patientProfile,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_selectedTab == 0) ...[
                        const _SearchField(),
                        const SizedBox(height: 26),
                        const _SectionHeading(
                          title: 'Services',
                          action: 'Voir tout',
                        ),
                        const SizedBox(height: 14),
                        _ServiceCarousel(
                          wide: wide,
                          services: _homeServices,
                          onServiceTap: _openService,
                        ),
                        const SizedBox(height: 26),
                        AspectRatio(
                          aspectRatio: 18 / 10,
                          child: _AssistantCard(onComposeTap: _openAiAssistant),
                        ),
                      ] else if (_selectedTab == 1)
                        const _PersonnelPage()
                      else if (_selectedTab == 2)
                        const _InstitutionsPage(),
                      if (_selectedTab == 3)
                        HealthTrackingPage(patientId: widget.user.uid),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: SizedBox(
                    height: 76,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _GlassNavigationBar(
                            selectedIndex: _selectedTab,
                            onDestinationSelected: (index) =>
                                setState(() => _selectedTab = index),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const _EmergencyButton(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassNavigationBar extends StatelessWidget {
  const _GlassNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _destinations = [
    (Icons.home_outlined, Icons.home_rounded, 'Accueil'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Personnel'),
    (
      Icons.account_balance_rounded,
      Icons.account_balance_rounded,
      'Institution',
    ),
    (Icons.monitor_heart_outlined, Icons.monitor_heart_rounded, 'Suivi'),
  ];

  @override
  Widget build(BuildContext context) => _GlassSurface(
    borderRadius: 28,
    child: Row(
      children: List.generate(_destinations.length, (index) {
        final destination = _destinations[index];
        return Expanded(
          child: _GlassNavigationDestination(
            icon: destination.$1,
            selectedIcon: destination.$2,
            label: destination.$3,
            selected: selectedIndex == index,
            onTap: () => onDestinationSelected(index),
          ),
        );
      }),
    ),
  );
}

class _GlassNavigationDestination extends StatelessWidget {
  const _GlassNavigationDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: selected ? 42 : 34,
                height: 32,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0x241778D4)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  selected ? selectedIcon : icon,
                  size: 27,
                  color: selected ? AppColors.primary : AppColors.navy,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: selected ? AppColors.primary : AppColors.navy,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({required this.child, required this.borderRadius});

  final Widget child;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x2B102A56),
          blurRadius: 32,
          spreadRadius: -5,
          offset: Offset(0, 14),
        ),
        BoxShadow(
          color: Color(0x70FFFFFF),
          blurRadius: 8,
          offset: Offset(0, -2),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xD9FFFFFF), Color(0xA8EDF5FF), Color(0xB8F7FCFF)],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: const Color(0xD9FFFFFF), width: 1.4),
          ),
          child: child,
        ),
      ),
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
            fontSize: 24,
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
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
      if (Firebase.apps.isEmpty)
        const _DirectoryFeedback(
          icon: Icons.cloud_off_outlined,
          title: 'Annuaire en mode aperçu',
          message:
              'Firebase sera utilisé lorsque l’application sera initialisée.',
        )
      else
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
            return _DirectoryGrid(
              children: [
                for (final record in records)
                  _ProfessionalCard(professional: record),
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
      if (Firebase.apps.isEmpty)
        const _DirectoryFeedback(
          icon: Icons.cloud_off_outlined,
          title: 'Annuaire en mode aperçu',
          message:
              'Firebase sera utilisé lorsque l’application sera initialisée.',
        )
      else
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
            return _DirectoryGrid(
              children: [
                for (final record in records)
                  _InstitutionCard(institution: record),
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

class _DirectoryCardTapTarget extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Widget child;
  const _DirectoryCardTapTarget({
    required this.label,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    ),
  );
}

class _ProfessionalCard extends StatelessWidget {
  final _Professional professional;
  const _ProfessionalCard({required this.professional});

  @override
  Widget build(BuildContext context) => _DirectoryCardTapTarget(
    label: 'Voir le profil de ${professional.name}',
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ProfessionalDetailPage(professional: professional),
      ),
    ),
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D173B66),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: professional.color,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  professional.initials,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      professional.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _StatusBadge(available: professional.available),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const _OpenProfileIndicator(),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8FD),
              borderRadius: BorderRadius.circular(14),
            ),
            child: _InformationLine(
              icon: Icons.medical_services_outlined,
              text: professional.role,
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (professional.workplace.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InformationLine(
              icon: Icons.local_hospital_outlined,
              text: professional.workplace,
            ),
          ],
          if (professional.address.isNotEmpty) ...[
            const SizedBox(height: 10),
            _InformationLine(
              icon: Icons.location_on_outlined,
              text: professional.address,
            ),
          ],
          if (professional.distance.isNotEmpty ||
              professional.phone.isNotEmpty) ...[
            const SizedBox(height: 13),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (professional.distance.isNotEmpty)
                  _DetailPill(
                    icon: Icons.near_me_outlined,
                    label: professional.distance,
                  ),
                if (professional.phone.isNotEmpty)
                  _DetailPill(
                    icon: Icons.phone_outlined,
                    label: professional.phone,
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

class _DirectoryGrid extends StatelessWidget {
  final List<Widget> children;
  const _DirectoryGrid({required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 14.0;
      final columns = constraints.maxWidth >= 760 ? 2 : 1;
      final itemWidth =
          (constraints.maxWidth - (columns - 1) * spacing) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final child in children)
            SizedBox(width: itemWidth, child: child),
        ],
      );
    },
  );
}

class _StatusBadge extends StatelessWidget {
  final bool available;
  const _StatusBadge({required this.available});

  @override
  Widget build(BuildContext context) {
    final foreground = available
        ? const Color(0xFF13795B)
        : const Color(0xFF667085);
    final background = available
        ? const Color(0xFFE7F7F0)
        : const Color(0xFFF0F2F5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            available ? 'Disponible' : 'Indisponible',
            style: TextStyle(
              color: foreground,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InformationLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final FontWeight fontWeight;
  const _InformationLine({
    required this.icon,
    required this.text,
    this.color = AppColors.muted,
    this.fontWeight = FontWeight.w500,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 17, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontWeight: fontWeight, height: 1.3),
        ),
      ),
    ],
  );
}

class _DetailPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _DetailPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F9FC),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 1),
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 12,
            fontWeight: FontWeight.w700,
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
  final String workplace;
  final String biography;
  final String experience;
  final String qualification;
  final String schedule;
  final String services;
  final String address;
  final String distance;
  final String phone;
  final String email;
  final String initials;
  final Color color;
  final bool available;

  const _Professional({
    required this.name,
    required this.role,
    required this.workplace,
    required this.biography,
    required this.experience,
    required this.qualification,
    required this.schedule,
    required this.services,
    required this.address,
    required this.distance,
    required this.phone,
    required this.email,
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
    final role = _field(data, [
      'specialite',
      'spécialité',
      'specialty',
      'role',
      'profession',
      'titre',
      'title',
    ]);
    return _Professional(
      name: resolvedName,
      role: role.isEmpty ? 'Professionnel de santé' : role,
      workplace: _field(data, [
        'etablissement',
        'établissement',
        'institution',
        'clinique',
        'clinic',
        'hospital',
        'workplace',
      ]),
      biography: _field(data, [
        'biographie',
        'biography',
        'bio',
        'description',
        'aPropos',
        'about',
      ]),
      experience: _field(data, [
        'experience',
        'expérience',
        'anneesExperience',
        'annéesExpérience',
        'yearsExperience',
      ]),
      qualification: _field(data, [
        'qualification',
        'qualifications',
        'diplome',
        'diplôme',
        'degree',
        'formation',
      ]),
      schedule: _field(data, [
        'horaires',
        'horaire',
        'disponibilites',
        'disponibilités',
        'schedule',
        'availability',
      ]),
      services: _field(data, [
        'services',
        'prestations',
        'expertises',
        'expertise',
      ]),
      address: _field(data, ['adresse', 'address', 'localisation', 'location']),
      distance: _field(data, ['distance', 'distanceLabel', 'distance_label']),
      phone: _field(data, [
        'telephone',
        'téléphone',
        'phone',
        'phoneNumber',
        'contact',
      ]),
      email: _field(data, ['email', 'e-mail', 'courriel', 'mail']),
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
  final String description;
  final String services;
  final String address;
  final String distance;
  final String schedule;
  final String phone;
  final String email;
  final IconData icon;
  final Color color;

  const _Institution({
    required this.name,
    required this.type,
    required this.description,
    required this.services,
    required this.address,
    required this.distance,
    required this.schedule,
    required this.phone,
    required this.email,
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
      'catégorie',
      'category',
    ]);
    final normalizedCategory = category.toLowerCase();
    final name = _field(data, ['nom', 'name', 'nomInstitution', 'displayName']);
    final schedule = _field(data, [
      'horaires',
      'horaire',
      'openingHours',
      'opening_hours',
      'schedule',
    ]);
    final type = category.isEmpty ? 'Institution de santé' : category;
    final isPharmacy = normalizedCategory.contains('pharm');
    final isHospital =
        normalizedCategory.contains('hôpital') ||
        normalizedCategory.contains('hopital') ||
        normalizedCategory.contains('hospital');
    return _Institution(
      name: name.isEmpty ? 'Institution de santé' : name,
      type: type,
      description: _field(data, [
        'description',
        'aPropos',
        'about',
        'presentation',
        'présentation',
      ]),
      services: _field(data, [
        'services',
        'specialites',
        'spécialités',
        'prestations',
        'departements',
        'départements',
      ]),
      address: _field(data, ['adresse', 'address', 'localisation', 'location']),
      distance: _field(data, ['distance', 'distanceLabel', 'distance_label']),
      schedule: schedule,
      phone: _field(data, [
        'telephone',
        'téléphone',
        'phone',
        'phoneNumber',
        'contact',
      ]),
      email: _field(data, ['email', 'e-mail', 'courriel', 'mail']),
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
    if (value is Map) {
      for (final nestedKey in const [
        'label',
        'formatted',
        'fullAddress',
        'name',
        'value',
      ]) {
        final nestedValue = value[nestedKey];
        if (nestedValue != null && nestedValue.toString().trim().isNotEmpty) {
          return nestedValue.toString().trim();
        }
      }
      continue;
    }
    if (value is Iterable) {
      final result = value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .join(', ');
      if (result.isNotEmpty) return result;
      continue;
    }
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
  final _Institution institution;
  const _InstitutionCard({required this.institution});

  @override
  Widget build(BuildContext context) => _DirectoryCardTapTarget(
    label: 'Voir les détails de ${institution.name}',
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _InstitutionDetailPage(institution: institution),
      ),
    ),
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D173B66),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: institution.color,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  institution.icon,
                  color: AppColors.primary,
                  size: 29,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      institution.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: institution.color,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        institution.type,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const _OpenProfileIndicator(),
            ],
          ),
          if (institution.address.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F8FD),
                borderRadius: BorderRadius.circular(14),
              ),
              child: _InformationLine(
                icon: Icons.location_on_outlined,
                text: institution.address,
                color: AppColors.navy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (institution.schedule.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InformationLine(
              icon: Icons.schedule_outlined,
              text: institution.schedule,
            ),
          ],
          if (institution.distance.isNotEmpty ||
              institution.phone.isNotEmpty) ...[
            const SizedBox(height: 13),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (institution.distance.isNotEmpty)
                  _DetailPill(
                    icon: Icons.near_me_outlined,
                    label: institution.distance,
                  ),
                if (institution.phone.isNotEmpty)
                  _DetailPill(
                    icon: Icons.phone_outlined,
                    label: institution.phone,
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

class _OpenProfileIndicator extends StatelessWidget {
  const _OpenProfileIndicator();

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    decoration: const BoxDecoration(
      color: Color(0xFFF1F5FB),
      shape: BoxShape.circle,
    ),
    child: const Icon(
      Icons.arrow_forward_ios_rounded,
      size: 14,
      color: AppColors.primary,
    ),
  );
}

class _ProfessionalDetailPage extends StatelessWidget {
  final _Professional professional;
  const _ProfessionalDetailPage({required this.professional});

  @override
  Widget build(BuildContext context) => _DirectoryDetailScaffold(
    pageTitle: 'Profil du personnel',
    children: [
      _DirectoryDetailHero(
        color: professional.color,
        leading: Text(
          professional.initials,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: AppColors.primary,
          ),
        ),
        title: professional.name,
        subtitle: professional.role,
        status: _StatusBadge(available: professional.available),
      ),
      if (professional.biography.isNotEmpty) ...[
        const SizedBox(height: 18),
        _DetailSection(
          title: 'À propos',
          children: [
            _DetailEntry(
              icon: Icons.person_outline_rounded,
              label: 'Présentation',
              value: professional.biography,
            ),
          ],
        ),
      ],
      const SizedBox(height: 18),
      _DetailSection(
        title: 'Informations professionnelles',
        children: [
          _DetailEntry(
            icon: Icons.medical_services_outlined,
            label: 'Spécialité',
            value: professional.role,
          ),
          if (professional.workplace.isNotEmpty)
            _DetailEntry(
              icon: Icons.local_hospital_outlined,
              label: 'Établissement',
              value: professional.workplace,
            ),
          if (professional.experience.isNotEmpty)
            _DetailEntry(
              icon: Icons.workspace_premium_outlined,
              label: 'Expérience',
              value: professional.experience,
            ),
          if (professional.qualification.isNotEmpty)
            _DetailEntry(
              icon: Icons.school_outlined,
              label: 'Formation et qualifications',
              value: professional.qualification,
            ),
          if (professional.schedule.isNotEmpty)
            _DetailEntry(
              icon: Icons.schedule_outlined,
              label: 'Horaires',
              value: professional.schedule,
            ),
          if (professional.services.isNotEmpty)
            _DetailEntry(
              icon: Icons.health_and_safety_outlined,
              label: 'Services et expertises',
              value: professional.services,
            ),
        ],
      ),
      if (professional.address.isNotEmpty ||
          professional.distance.isNotEmpty ||
          professional.phone.isNotEmpty ||
          professional.email.isNotEmpty) ...[
        const SizedBox(height: 18),
        _DetailSection(
          title: 'Coordonnées',
          children: [
            if (professional.address.isNotEmpty)
              _DetailEntry(
                icon: Icons.location_on_outlined,
                label: 'Adresse',
                value: professional.address,
              ),
            if (professional.distance.isNotEmpty)
              _DetailEntry(
                icon: Icons.near_me_outlined,
                label: 'Distance',
                value: professional.distance,
              ),
            if (professional.phone.isNotEmpty)
              _DetailEntry(
                icon: Icons.phone_outlined,
                label: 'Téléphone',
                value: professional.phone,
                copyValue: professional.phone,
              ),
            if (professional.email.isNotEmpty)
              _DetailEntry(
                icon: Icons.email_outlined,
                label: 'E-mail',
                value: professional.email,
                copyValue: professional.email,
              ),
          ],
        ),
      ],
    ],
  );
}

class _InstitutionDetailPage extends StatelessWidget {
  final _Institution institution;
  const _InstitutionDetailPage({required this.institution});

  @override
  Widget build(BuildContext context) => _DirectoryDetailScaffold(
    pageTitle: 'Détails de l’institution',
    children: [
      _DirectoryDetailHero(
        color: institution.color,
        leading: Icon(institution.icon, size: 38, color: AppColors.primary),
        title: institution.name,
        subtitle: institution.type,
      ),
      if (institution.description.isNotEmpty) ...[
        const SizedBox(height: 18),
        _DetailSection(
          title: 'À propos',
          children: [
            _DetailEntry(
              icon: Icons.info_outline_rounded,
              label: 'Présentation',
              value: institution.description,
            ),
          ],
        ),
      ],
      const SizedBox(height: 18),
      _DetailSection(
        title: 'Informations',
        children: [
          _DetailEntry(
            icon: Icons.category_outlined,
            label: 'Type d’institution',
            value: institution.type,
          ),
          if (institution.services.isNotEmpty)
            _DetailEntry(
              icon: Icons.medical_services_outlined,
              label: 'Services et spécialités',
              value: institution.services,
            ),
          if (institution.schedule.isNotEmpty)
            _DetailEntry(
              icon: Icons.schedule_outlined,
              label: 'Horaires',
              value: institution.schedule,
            ),
        ],
      ),
      if (institution.address.isNotEmpty ||
          institution.distance.isNotEmpty ||
          institution.phone.isNotEmpty ||
          institution.email.isNotEmpty) ...[
        const SizedBox(height: 18),
        _DetailSection(
          title: 'Localisation et contact',
          children: [
            if (institution.address.isNotEmpty)
              _DetailEntry(
                icon: Icons.location_on_outlined,
                label: 'Adresse',
                value: institution.address,
              ),
            if (institution.distance.isNotEmpty)
              _DetailEntry(
                icon: Icons.near_me_outlined,
                label: 'Distance',
                value: institution.distance,
              ),
            if (institution.phone.isNotEmpty)
              _DetailEntry(
                icon: Icons.phone_outlined,
                label: 'Téléphone',
                value: institution.phone,
                copyValue: institution.phone,
              ),
            if (institution.email.isNotEmpty)
              _DetailEntry(
                icon: Icons.email_outlined,
                label: 'E-mail',
                value: institution.email,
                copyValue: institution.email,
              ),
          ],
        ),
      ],
    ],
  );
}

class _DirectoryDetailScaffold extends StatelessWidget {
  final String pageTitle;
  final List<Widget> children;
  const _DirectoryDetailScaffold({
    required this.pageTitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppBar(title: Text(pageTitle)),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    ),
  );
}

class _DirectoryDetailHero extends StatelessWidget {
  final Color color;
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? status;
  const _DirectoryDetailHero({
    required this.color,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.status,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Colors.white, Color(0xFFF3F7FD)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: AppColors.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x10173B66),
          blurRadius: 28,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(23),
          ),
          child: leading,
        ),
        const SizedBox(width: 17),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 23,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (status != null) ...[const SizedBox(height: 11), status!],
            ],
          ),
        ),
      ],
    ),
  );
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _DetailSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const Divider(height: 1, color: AppColors.border),
          children[index],
        ],
      ],
    ),
  );
}

class _DetailEntry extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? copyValue;
  const _DetailEntry({
    required this.icon,
    required this.label,
    required this.value,
    this.copyValue,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5FB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              SelectableText(
                value,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 14.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (copyValue != null) ...[
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Copier',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: copyValue!));
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('$label copié')));
            },
            icon: const Icon(Icons.copy_rounded, size: 19),
            color: AppColors.primary,
          ),
        ],
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  final int unreadNotificationCount;
  final VoidCallback onNotificationsTap;
  final VoidCallback onProfileTap;
  const _Header({
    required this.unreadNotificationCount,
    required this.onNotificationsTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('home-header'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFEDF8F5),
      child: Row(
        children: [
          const SizedBox(width: 44, height: 44, child: _BrandMark()),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'I-ENTIER',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                    height: 1.1,
                    color: AppColors.navy,
                    letterSpacing: .4,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Votre espace santé',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _RoundIcon(
            icon: Icons.notifications_none_rounded,
            badge: unreadNotificationCount == 0
                ? null
                : unreadNotificationCount.toString(),
            tooltip: 'Notifications',
            onTap: onNotificationsTap,
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Ouvrir le profil LL',
            child: Material(
              color: const Color(0xFFE8E2F8),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onProfileTap,
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 42,
                  height: 42,
                  child: Center(
                    child: Text(
                      'LL',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
  final String? tooltip;
  final VoidCallback? onTap;
  const _RoundIcon({required this.icon, this.badge, this.tooltip, this.onTap});
  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: const Color(0xFFDDEFF3),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(icon, color: AppColors.navy, size: 21),
            ),
          ),
        ),
      ),
      if (badge != null)
        Positioned(
          right: -2,
          top: -3,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF6750A4),
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
    key: const ValueKey('home-search-bar'),
    height: 56,
    padding: const EdgeInsets.fromLTRB(16, 6, 7, 6),
    decoration: BoxDecoration(
      color: const Color(0xFFF0EDFA),
      borderRadius: BorderRadius.circular(28),
    ),
    child: Row(
      children: [
        const Icon(Icons.search_rounded, color: AppColors.navy, size: 23),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            hint,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'Filtrer',
          child: Material(
            color: const Color(0xFFDDECF7),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: () {},
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.tune_rounded,
                  color: AppColors.navy,
                  size: 21,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ServiceCarousel extends StatelessWidget {
  final bool wide;
  final List<HealthService> services;
  final ValueChanged<HealthService> onServiceTap;
  const _ServiceCarousel({
    required this.wide,
    required this.services,
    required this.onServiceTap,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 12.0;
      // Au moins 2,5 cartes restent visibles, sans déformer leur ratio 266 x 365.
      final cardWidth = (constraints.maxWidth - (gap * 2)) / 2.5;
      final cardHeight = cardWidth * (365 / 266);
      return SizedBox(
        height: cardHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          clipBehavior: Clip.none,
          padding: const EdgeInsets.only(right: 4),
          itemCount: services.length,
          separatorBuilder: (context, index) => const SizedBox(width: gap),
          itemBuilder: (context, index) => SizedBox(
            width: cardWidth,
            child: _ServiceCard(
              service: services[index],
              onTap: () => onServiceTap(services[index]),
            ),
          ),
        ),
      );
    },
  );
}

class _ServiceCard extends StatelessWidget {
  final HealthService service;
  final VoidCallback onTap;
  const _ServiceCard({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth <= 180;
      final imageSize = constraints.maxWidth * .64;
      final radius = BorderRadius.circular(compact ? 17 : 25);
      return Material(
        color: service.background,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 10 : 18,
              compact ? 9 : 16,
              compact ? 10 : 18,
              compact ? 10 : 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(
                    child: _ServiceImage(service: service, size: imageSize),
                  ),
                ),
                Text(
                  service.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 14 : 19,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF172033),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  service.summary,
                  maxLines: compact ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 10.5 : 14,
                    height: 1.2,
                    color: const Color(0xFF283648),
                  ),
                ),
                SizedBox(height: compact ? 7 : 13),
                Text(
                  '${service.actionLabel}  →',
                  style: TextStyle(
                    fontSize: compact ? 12 : 16,
                    fontWeight: FontWeight.bold,
                    color: service.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ServiceImage extends StatelessWidget {
  final HealthService service;
  final double size;
  const _ServiceImage({required this.service, required this.size});

  @override
  Widget build(BuildContext context) {
    if (service.imagePath.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .72),
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Color(0x187656D8),
              blurRadius: 20,
              offset: Offset(0, 9),
            ),
          ],
        ),
        child: Icon(
          service.icon ?? Icons.health_and_safety_outlined,
          size: size * .56,
          color: service.accent,
        ),
      );
    }
    if (service.hasRemoteImage) {
      return Image.network(
        service.imagePath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.image_not_supported_outlined,
          size: 64,
          color: AppColors.muted,
        ),
      );
    }
    return Image.asset(
      service.imagePath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) => const Icon(
        Icons.image_not_supported_outlined,
        size: 64,
        color: AppColors.muted,
      ),
    );
  }
}

class _AssistantCard extends StatelessWidget {
  final VoidCallback onComposeTap;

  const _AssistantCard({required this.onComposeTap});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF173C75), Color(0xFF2265B3)],
      ),
      borderRadius: BorderRadius.circular(28),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33215FA9),
          blurRadius: 26,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Hero(
                  tag: 'i-entier-ai-avatar',
                  child: const CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(0xFFCDEAFF),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFF1559A5),
                    ),
                  ),
                ),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4EE29A),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF173C75),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'I-ENTIER AI',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Assistant santé • En ligne',
                    style: TextStyle(color: Color(0xFFCFE3FF), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFCFE3FF),
              size: 22,
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Bonjour 👋 Comment puis-je vous aider aujourd’hui ?',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const Spacer(),
        Semantics(
          button: true,
          label: 'Ouvrir I-ENTIER AI',
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onComposeTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Écrivez votre message...',
                        style: TextStyle(
                          color: Color(0xFF75849C),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_upward_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _AiAssistantSheet extends StatefulWidget {
  final VoidCallback onClose;

  const _AiAssistantSheet({required this.onClose});

  @override
  State<_AiAssistantSheet> createState() => _AiAssistantSheetState();
}

class _AiAssistantSheetState extends State<_AiAssistantSheet>
    with TickerProviderStateMixin {
  static const _suggestions = <({IconData icon, String label})>[
    (icon: Icons.health_and_safety_outlined, label: 'Comprendre mes symptômes'),
    (icon: Icons.medication_outlined, label: 'Question sur un médicament'),
    (icon: Icons.calendar_month_outlined, label: 'Préparer mon rendez-vous'),
  ];

  final _messageController = TextEditingController();
  final _focusNode = FocusNode();
  late final AnimationController _entranceController;
  late final AnimationController _magicController;
  Timer? _focusTimer;
  String? _submittedMessage;
  bool _isClosing = false;
  bool _isDragging = false;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    )..forward();
    _magicController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();

    _focusTimer = Timer(const Duration(milliseconds: 430), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _close() {
    if (_isClosing) return;
    _isClosing = true;
    _focusTimer?.cancel();
    _focusNode.unfocus();
    widget.onClose();
  }

  void _startDrag(DragStartDetails details) {
    if (_isClosing) return;
    setState(() => _isDragging = true);
  }

  void _updateDrag(DragUpdateDetails details) {
    if (!_isDragging || _isClosing) return;
    setState(() {
      _dragOffset = math.max(0, _dragOffset + details.delta.dy);
    });
  }

  void _endDrag(DragEndDetails details) {
    if (!_isDragging || _isClosing) return;
    final shouldClose =
        _dragOffset >= 72 || (details.primaryVelocity ?? 0) >= 650;
    if (shouldClose) {
      setState(() => _isDragging = false);
      _close();
      return;
    }
    setState(() {
      _isDragging = false;
      _dragOffset = 0;
    });
  }

  void _cancelDrag() {
    if (!_isDragging || _isClosing) return;
    setState(() {
      _isDragging = false;
      _dragOffset = 0;
    });
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    _messageController.dispose();
    _focusNode.dispose();
    _entranceController.dispose();
    _magicController.dispose();
    super.dispose();
  }

  void _useSuggestion(String suggestion) {
    _messageController
      ..text = suggestion
      ..selection = TextSelection.collapsed(offset: suggestion.length);
    _focusNode.requestFocus();
  }

  void _submitMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    setState(() {
      _submittedMessage = message;
      _messageController.clear();
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600;
    final contentAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(.18, 1, curve: Curves.easeOutCubic),
    );

    return AnimatedContainer(
      duration: _isDragging ? Duration.zero : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, _dragOffset, 0),
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF07172E),
                  Color(0xFF0D2A55),
                  Color(0xFF114D82),
                ],
                stops: [0, .52, 1],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _MagicBackdropPainter(_magicController),
                    ),
                  ),
                ),
                AnimatedPadding(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 16 : 32,
                      10,
                      compact ? 16 : 32,
                      10,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: Column(
                          children: [
                            GestureDetector(
                              key: const ValueKey('ai-sheet-drag-handle'),
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragStart: _startDrag,
                              onVerticalDragUpdate: _updateDrag,
                              onVerticalDragEnd: _endDrag,
                              onVerticalDragCancel: _cancelDrag,
                              child: SizedBox(
                                width: 88,
                                height: 22,
                                child: Center(
                                  child: Container(
                                    width: 46,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: .42,
                                      ),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            _AiSheetHeader(onClose: _close),
                            Expanded(
                              child: FadeTransition(
                                opacity: contentAnimation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, .08),
                                    end: Offset.zero,
                                  ).animate(contentAnimation),
                                  child: _submittedMessage == null
                                      ? _AiWelcome(
                                          compact: compact,
                                          magicAnimation: _magicController,
                                          suggestions: _suggestions,
                                          onSuggestionTap: _useSuggestion,
                                        )
                                      : _AiConversationPreview(
                                          message: _submittedMessage!,
                                        ),
                                ),
                              ),
                            ),
                            _AiComposer(
                              controller: _messageController,
                              focusNode: _focusNode,
                              onSubmitted: _submitMessage,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "L'IA peut faire des erreurs. En cas d'urgence, contactez un professionnel.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFAFC9E7),
                                fontSize: 10.5,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AiSheetHeader extends StatelessWidget {
  final VoidCallback onClose;

  const _AiSheetHeader({required this.onClose});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Hero(
        tag: 'i-entier-ai-avatar',
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE1F3FF), Color(0xFF8ED7FF)],
            ),
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Color(0x6646B8FF),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFF125AA3),
          ),
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'I-ENTIER AI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: .2,
              ),
            ),
            Row(
              children: [
                _OnlineDot(),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Assistant santé • En ligne',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Color(0xFFC6DDF5), fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Fermer',
        onPressed: onClose,
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: .1),
          minimumSize: const Size(44, 44),
        ),
        icon: const Icon(Icons.close_rounded),
      ),
    ],
  );
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot();

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: const BoxDecoration(
      color: Color(0xFF55E6A5),
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: Color(0x9955E6A5), blurRadius: 7)],
    ),
  );
}

class _AiWelcome extends StatelessWidget {
  final bool compact;
  final Animation<double> magicAnimation;
  final List<({IconData icon, String label})> suggestions;
  final ValueChanged<String> onSuggestionTap;

  const _AiWelcome({
    required this.compact,
    required this.magicAnimation,
    required this.suggestions,
    required this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: EdgeInsets.symmetric(vertical: compact ? 18 : 34),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight - 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _AiMagicOrb(animation: magicAnimation, compact: compact),
            SizedBox(height: compact ? 18 : 26),
            Text(
              'Bonjour, je suis là pour vous',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 24 : 32,
                height: 1.08,
                fontWeight: FontWeight.w800,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              'Posez une question sur votre santé ou choisissez une suggestion.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFC4D9EF),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            SizedBox(height: compact ? 20 : 28),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 9,
              runSpacing: 9,
              children: suggestions
                  .map(
                    (suggestion) => _AiSuggestionChip(
                      icon: suggestion.icon,
                      label: suggestion.label,
                      onTap: () => onSuggestionTap(suggestion.label),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AiMagicOrb extends StatelessWidget {
  final Animation<double> animation;
  final bool compact;

  const _AiMagicOrb({required this.animation, required this.compact});

  @override
  Widget build(BuildContext context) {
    final size = compact ? 96.0 : 126.0;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final phase = animation.value * math.pi * 2;
        final scale = 1 + math.sin(phase) * .035;
        return Transform.scale(
          scale: scale,
          child: Transform.rotate(
            angle: math.sin(phase * .5) * .035,
            child: child,
          ),
        );
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(-.28, -.35),
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFB8E8FF),
              Color(0xFF62B9FF),
              Color(0xFF2569C5),
            ],
            stops: [0, .28, .65, 1],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: .72)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x8859C8FF),
              blurRadius: 50,
              spreadRadius: 10,
            ),
            BoxShadow(
              color: Color(0x664D7DFF),
              blurRadius: 90,
              spreadRadius: 24,
            ),
          ],
        ),
        child: Icon(
          Icons.auto_awesome_rounded,
          size: compact ? 42 : 54,
          color: const Color(0xFF0D4D91),
        ),
      ),
    );
  }
}

class _AiSuggestionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AiSuggestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .09),
    borderRadius: BorderRadius.circular(99),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: .14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF91D8FF), size: 18),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AiConversationPreview extends StatelessWidget {
  final String message;

  const _AiConversationPreview({required this.message});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF2B78D0),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, height: 1.35),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 620),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: Border.all(color: Colors.white.withValues(alpha: .12)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFF8FD7FF),
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "L'interface est prête. Le moteur de réponse IA sera connecté prochainement.",
                    style: TextStyle(color: Colors.white, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _AiComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmitted;

  const _AiComposer({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(1.2),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF8BE0FF), Color(0xFF497CFF), Color(0xFFB290FF)],
      ),
      borderRadius: BorderRadius.circular(23),
      boxShadow: const [
        BoxShadow(color: Color(0x553E9CFF), blurRadius: 28, spreadRadius: 2),
      ],
    ),
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 5, 6, 5),
      decoration: BoxDecoration(
        color: const Color(0xF2142B47),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              keyboardAppearance: Brightness.dark,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              cursorColor: const Color(0xFF8EDCFF),
              decoration: const InputDecoration(
                hintText: 'Demandez quelque chose...',
                hintStyle: TextStyle(color: Color(0xFF91A9C3)),
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 13),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, child) {
              final enabled = value.text.trim().isNotEmpty;
              return Semantics(
                button: true,
                enabled: enabled,
                label: 'Envoyer le message',
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: enabled
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF68CAFF), Color(0xFF246CDE)],
                          )
                        : null,
                    color: enabled ? null : Colors.white.withValues(alpha: .08),
                    shape: BoxShape.circle,
                    boxShadow: enabled
                        ? const [
                            BoxShadow(color: Color(0x665BC5FF), blurRadius: 18),
                          ]
                        : null,
                  ),
                  child: IconButton(
                    tooltip: 'Envoyer',
                    onPressed: enabled ? onSubmitted : null,
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.arrow_upward_rounded,
                      color: enabled ? Colors.white : const Color(0xFF6F89A5),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _MagicBackdropPainter extends CustomPainter {
  final Animation<double> animation;

  _MagicBackdropPainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final phase = animation.value * math.pi * 2;
    final glowPaint = Paint()
      ..color = const Color(0x284CBFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70);
    canvas.drawCircle(
      Offset(
        size.width * .16 + math.sin(phase) * 24,
        size.height * .32 + math.cos(phase) * 18,
      ),
      math.min(size.width, size.height) * .24,
      glowPaint,
    );

    glowPaint.color = const Color(0x223B72FF);
    canvas.drawCircle(
      Offset(
        size.width * .84 + math.cos(phase * .8) * 30,
        size.height * .67 + math.sin(phase * .8) * 22,
      ),
      math.min(size.width, size.height) * .29,
      glowPaint,
    );

    for (var index = 0; index < 22; index++) {
      final x = ((index * 47) % 101) / 100 * size.width;
      final baseY = ((index * 71) % 97) / 100 * size.height;
      final y = baseY + math.sin(phase + index * .9) * 7;
      final pulse = .35 + (math.sin(phase * 1.7 + index) + 1) * .27;
      final radius = index % 5 == 0 ? 2.1 : 1.25;
      final starPaint = Paint()
        ..color = Colors.white.withValues(alpha: pulse.clamp(0, 1));
      canvas.drawCircle(Offset(x, y), radius, starPaint);
      if (index % 5 == 0) {
        canvas.drawLine(
          Offset(x - 4, y),
          Offset(x + 4, y),
          starPaint..strokeWidth = .7,
        );
        canvas.drawLine(Offset(x, y - 4), Offset(x, y + 4), starPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MagicBackdropPainter oldDelegate) =>
      oldDelegate.animation != animation;
}

class _EmergencyButton extends StatefulWidget {
  const _EmergencyButton();

  @override
  State<_EmergencyButton> createState() => _EmergencyButtonState();
}

class _EmergencyButtonState extends State<_EmergencyButton> {
  static const _phoneChannel = MethodChannel('i_entier/phone');

  Future<void> _openEmergencySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Services d’urgence',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _EmergencyServiceIcon(
                  icon: Icons.local_hospital,
                  color: const Color(0xFFFF3029),
                ),
                title: const Text(
                  'CAN',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Composer le 116'),
                trailing: const Icon(Icons.phone_forwarded),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _dialNumber('116');
                },
              ),
              const Divider(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _EmergencyServiceIcon(
                  icon: Icons.airplanemode_active,
                  color: AppColors.primary,
                ),
                title: const Text(
                  'Air Ambulance',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Numéro bientôt disponible'),
                trailing: const Icon(Icons.chevron_right),
                enabled: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _dialNumber(String number) async {
    try {
      await _phoneChannel.invokeMethod<void>('dial', {'number': number});
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'ouvrir le téléphone.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    child: Semantics(
      button: true,
      label: 'Urgences',
      child: Tooltip(
        message: 'Urgences',
        child: _GlassSurface(
          borderRadius: 38,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('emergency-bottom-button'),
              onTap: _openEmergencySheet,
              customBorder: const CircleBorder(),
              child: const Icon(
                Icons.emergency_rounded,
                size: 37,
                color: Color(0xFFFF3029),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _EmergencyServiceIcon extends StatelessWidget {
  const _EmergencyServiceIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(icon, color: color),
  );
}
