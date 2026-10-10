import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'video_call_repository.dart';
import 'video_room_page.dart';

const _ink = Color(0xFF142C49);
const _blue = Color(0xFF1976D2);
const _canvas = Color(0xFFF4F7FB);

/// Owns one call session for the signed-in account, including invitations while
/// another page is open. Place below the application's Navigator.
class VideoCallHost extends StatefulWidget {
  final SupabaseClient? client;
  final String userId;
  final VideoCallRole role;
  final VideoCallRepository? repository;
  final Widget child;
  const VideoCallHost({
    super.key,
    this.client,
    required this.userId,
    required this.role,
    required this.child,
    this.repository,
  }) : assert(client != null || repository != null);

  static void open(BuildContext context) =>
      context.findAncestorStateOfType<_VideoCallHostState>()?._openPage();

  @override
  State<VideoCallHost> createState() => _VideoCallHostState();
}

class _VideoCallHostState extends State<VideoCallHost>
    with WidgetsBindingObserver {
  late final VideoCallController _controller;
  final _presented = <String>{};
  bool _invitationOpen = false;
  Route<void>? _roomRoute;
  Route<void>? _pageRoute;
  Route<String>? _invitationRoute;
  String? _activeId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = VideoCallController(
      userId: widget.userId,
      repository:
          widget.repository ??
          SupabaseVideoCallRepository(
            client: widget.client!,
            userId: widget.userId,
            role: widget.role,
          ),
    )..addListener(_changed);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_controller.refresh());
  }

  void _changed() {
    if (!mounted || _invitationOpen || _activeId != null) return;
    for (final call in _controller.calls) {
      if (call.isIncoming(widget.userId) && !_presented.contains(call.id)) {
        _presented.add(call.id);
        _invitationOpen = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_invite(call));
        });
        // A Realtime event may arrive while the UI is completely idle.
        WidgetsBinding.instance.scheduleFrame();
        break;
      }
    }
  }

  Future<void> _invite(VideoCall call) async {
    unawaited(SystemSound.play(SystemSoundType.alert));
    final route = DialogRoute<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _IncomingCallDialog(controller: _controller, call: call),
    );
    _invitationRoute = route;
    final result = await Navigator.of(context).push(route);
    _invitationRoute = null;
    _invitationOpen = false;
    if (!mounted) return;
    if (result == 'accepted') {
      await _openCall(_controller.find(call.id) ?? call);
    }
  }

  Future<void> _openPage() async {
    if (_pageRoute != null) return;
    final route = MaterialPageRoute<void>(
      builder: (_) =>
          VideoCallsPage(controller: _controller, onOpenCall: _openCall),
    );
    _pageRoute = route;
    try {
      await Navigator.of(context).push(route);
    } finally {
      _pageRoute = null;
    }
  }

  Future<void> _openCall(VideoCall call) async {
    if (!mounted || _activeId != null || !call.isActive) return;
    _activeId = call.id;
    final route = MaterialPageRoute<void>(
      builder: (_) => VideoRoomPage(controller: _controller, initialCall: call),
    );
    _roomRoute = route;
    try {
      await Navigator.of(context).push(route);
    } finally {
      _roomRoute = null;
      _activeId = null;
      if (mounted) unawaited(_controller.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    // Remove just our routes after logout; never pop an unrelated page.
    final routes = <Route<dynamic>?>[_roomRoute, _invitationRoute, _pageRoute];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final route in routes) {
        if (route?.navigator != null) route!.navigator!.removeRoute(route);
      }
    });
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class VideoCallsPage extends StatefulWidget {
  final VideoCallController controller;
  final Future<void> Function(VideoCall) onOpenCall;
  const VideoCallsPage({
    super.key,
    required this.controller,
    required this.onOpenCall,
  });
  @override
  State<VideoCallsPage> createState() => _VideoCallsPageState();
}

class _VideoCallsPageState extends State<VideoCallsPage> {
  List<VideoAppointment> _appointments = [];
  bool _loading = true;
  String? _loadError, _busyId;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _clock = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_load()),
    );
  }

  Future<void> _load() async {
    try {
      final appointments = await widget.controller.repository.appointments();
      if (mounted) {
        setState(() {
          _appointments = appointments;
          _loadError = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Impossible de charger les rendez-vous.';
        });
      }
    }
  }

  Future<void> _start(VideoAppointment appointment) async {
    if (_busyId != null) return;
    setState(() => _busyId = appointment.id);
    try {
      final call = await widget.controller.act(
        'start',
        appointmentId: appointment.id,
      );
      if (!mounted) return;
      // A simultaneous call from the other person must still be accepted.
      if (call.isIncoming(widget.controller.userId)) return;
      await widget.onOpenCall(call);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(videoCallError(error))));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _canvas,
    appBar: AppBar(
      title: const Text('Appels vidéo'),
      actions: [
        IconButton(
          tooltip: 'Actualiser',
          onPressed: () {
            unawaited(_load());
            unawaited(widget.controller.refresh());
          },
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final history = controller.calls;
        return RefreshIndicator(
          onRefresh: () async {
            await _load();
            await controller.refresh();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_ink, Color(0xFF245787)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(
                                Icons.videocam_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 18),
                            const Expanded(
                              child: Text(
                                'Mes consultations vidéo',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (controller.error != null || _loadError != null)
                        _EmptyCard(
                          icon: Icons.cloud_off_rounded,
                          text: _loadError ?? controller.error!,
                        ),
                      if (!controller.loading &&
                          controller.error == null &&
                          !controller.configured)
                        const _EmptyCard(
                          icon: Icons.videocam_off_outlined,
                          text: 'Appels vidéo indisponibles',
                        ),
                      const _SectionTitle('Rendez-vous vidéo'),
                      if (_loading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(28),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (_appointments.isEmpty && _loadError == null)
                        const _EmptyCard(
                          icon: Icons.event_available_outlined,
                          text: 'Aucun rendez-vous vidéo confirmé',
                        )
                      else
                        for (final appointment in _appointments)
                          _AppointmentCard(
                            appointment: appointment,
                            busy: _busyId == appointment.id,
                            onCall:
                                controller.configured &&
                                    _busyId == null &&
                                    appointment.canCallAt(DateTime.now())
                                ? () => _start(appointment)
                                : null,
                          ),
                      const SizedBox(height: 28),
                      const _SectionTitle('Historique'),
                      if (controller.loading)
                        const Center(child: CircularProgressIndicator())
                      else if (history.isEmpty)
                        const _EmptyCard(
                          icon: Icons.history_rounded,
                          text: 'Aucun appel',
                        )
                      else
                        for (final call in history)
                          Card(
                            elevation: 0,
                            color: Colors.white,
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 8,
                              ),
                              leading: Icon(
                                call.callerId == controller.userId
                                    ? Icons.call_made_rounded
                                    : Icons.call_received_rounded,
                                color:
                                    call.status == 'missed' ||
                                        call.status == 'declined'
                                    ? Colors.redAccent
                                    : _blue,
                              ),
                              title: Text(
                                call.otherName(controller.userId),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${_date(context, call.createdAt)} · ${call.label}',
                              ),
                              trailing:
                                  call.isActive &&
                                      call.expiresAt.isAfter(DateTime.now()) &&
                                      !call.isIncoming(controller.userId)
                                  ? IconButton(
                                      tooltip: 'Rejoindre',
                                      onPressed: () => widget.onOpenCall(call),
                                      icon: const Icon(
                                        Icons.videocam_rounded,
                                        color: _blue,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

String _date(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final l = MaterialLocalizations.of(context);
  return '${l.formatShortDate(local)} · ${l.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: true)}';
}

class _AppointmentCard extends StatelessWidget {
  final VideoAppointment appointment;
  final bool busy;
  final VoidCallback? onCall;
  const _AppointmentCard({
    required this.appointment,
    required this.busy,
    this.onCall,
  });
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _blue.withValues(alpha: .10),
                child: const Icon(Icons.person_outline_rounded, color: _blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  appointment.name,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (appointment.service.isNotEmpty) ...[
            Text(appointment.service),
            const SizedBox(height: 6),
          ],
          Text(
            _date(context, appointment.scheduledAt),
            style: const TextStyle(color: Color(0xFF65758A)),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onCall,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.videocam_rounded),
              label: const Text('Appeler'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      text,
      style: const TextStyle(
        color: _ink,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyCard({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF65758A)),
        const SizedBox(width: 14),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _IncomingCallDialog extends StatefulWidget {
  final VideoCallController controller;
  final VideoCall call;
  const _IncomingCallDialog({required this.controller, required this.call});
  @override
  State<_IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<_IncomingCallDialog> {
  bool _busy = false, _closing = false;
  String? _error;
  Timer? _expiry;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _expiry = Timer.periodic(const Duration(seconds: 1), (_) => _changed());
  }

  void _changed() {
    if (!mounted || _busy || _closing) return;
    final call = widget.controller.find(widget.call.id) ?? widget.call;
    if (!call.isIncoming(widget.controller.userId)) {
      _closing = true;
      Navigator.of(context).pop();
    }
  }

  Future<void> _respond(String action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final call = await widget.controller.act(action, callId: widget.call.id);
      if (mounted) {
        _closing = true;
        Navigator.of(
          context,
        ).pop(call.status == 'accepted' ? 'accepted' : null);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = videoCallError(error);
        });
      }
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      icon: const Icon(Icons.videocam_rounded, size: 38, color: _blue),
      title: Text(widget.call.otherName(widget.controller.userId)),
      content: Text(
        _error ?? 'Appel vidéo entrant',
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _respond('decline'),
          child: const Text('Refuser'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _respond('accept'),
          child: const Text('Accepter'),
        ),
      ],
    ),
  );
}
