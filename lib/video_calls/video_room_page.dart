import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:livekit_client/livekit_client.dart';

import 'video_call_repository.dart';

class VideoRoomPage extends StatefulWidget {
  final VideoCallController controller;
  final VideoCall initialCall;
  const VideoRoomPage({
    super.key,
    required this.controller,
    required this.initialCall,
  });
  @override
  State<VideoRoomPage> createState() => _VideoRoomPageState();
}

class _VideoRoomPageState extends State<VideoRoomPage> {
  Room? _room;
  EventsListener<RoomEvent>? _events;
  Timer? _clock, _heartbeat;
  bool _connecting = false,
      _attempted = false,
      _closing = false,
      _ended = false;
  bool _toggling = false,
      _speaker = true,
      _front = true,
      _beating = false,
      _leaving = false;
  String? _error;
  DateTime _lastHeartbeat = DateTime.now();
  VideoCall get _call =>
      widget.controller.find(widget.initialCall.id) ?? widget.initialCall;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _ended) return;
      if (!_call.expiresAt.isAfter(DateTime.now())) {
        unawaited(_finish(sendEnd: false));
        unawaited(widget.controller.refresh());
      } else if (_call.status == 'accepted' &&
          DateTime.now().difference(_lastHeartbeat).inSeconds > 75) {
        _error = 'La connexion a été interrompue.';
        unawaited(_finish(sendEnd: true));
      } else {
        setState(() {});
      }
    });
    _heartbeat = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_beat()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  void _changed() {
    if (!mounted || _closing || _ended) return;
    if (!_call.isActive) {
      _error = null;
      unawaited(_finish(sendEnd: false));
      return;
    }
    if (_call.status == 'accepted' && !_attempted) {
      _lastHeartbeat = DateTime.now();
      unawaited(_connect());
    }
    setState(() {});
  }

  Future<void> _beat() async {
    if (_beating || _ended || _closing || _call.status != 'accepted') return;
    _beating = true;
    try {
      await widget.controller.act('heartbeat', callId: _call.id);
      _lastHeartbeat = DateTime.now();
    } catch (_) {
      /* The next attempt can recover before the server lease ends. */
    } finally {
      _beating = false;
    }
  }

  Future<void> _connect() async {
    if (_connecting || _closing || _ended || !mounted) return;
    setState(() {
      _connecting = true;
      _attempted = true;
      _error = null;
    });
    Room? room;
    try {
      await _releaseRoom();
      final access = await widget.controller.repository.command(
        'join',
        callId: _call.id,
      );
      if (!mounted || _closing || _ended) return;
      room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultCameraCaptureOptions: CameraCaptureOptions(
            params: VideoParametersPresets.h360_169,
            maxFrameRate: 24,
          ),
          defaultVideoPublishOptions: VideoPublishOptions(
            videoEncoding: VideoEncoding(maxBitrate: 500000, maxFramerate: 24),
          ),
        ),
      );
      _room = room;
      room.addListener(_roomChanged);
      _events = room.createListener()
        ..on<RoomDisconnectedEvent>((event) {
          if (mounted && !_closing && !_ended) {
            setState(() => _error = 'Connexion interrompue.');
          }
        });
      await room
          .connect(access['url'] as String, access['token'] as String)
          .timeout(const Duration(seconds: 30));
      if (!mounted || _closing || _ended) {
        await room.dispose();
        return;
      }
      _lastHeartbeat = DateTime.now();
      if (!kIsWeb) await AudioManager.instance.setSpeakerOutputPreferred(true);
      try {
        await room.localParticipant?.setMicrophoneEnabled(true);
      } catch (_) {
        _error = 'Microphone indisponible. Vérifiez son autorisation.';
      }
      if (!mounted || _closing || _ended) return;
      try {
        await room.localParticipant?.setCameraEnabled(true);
      } catch (_) {
        _error = 'Caméra indisponible. Vérifiez son autorisation.';
      }
      if (_closing || _ended) await room.dispose();
    } catch (error) {
      if (mounted && !_closing && !_ended) _error = videoCallError(error);
      await _releaseRoom();
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _roomChanged() {
    if (mounted && !_ended) setState(() {});
  }

  Future<void> _releaseRoom() async {
    final events = _events;
    final room = _room;
    _events = null;
    _room = null;
    room?.removeListener(_roomChanged);
    await events?.dispose();
    if (room != null) {
      try {
        await room.disconnect().timeout(const Duration(seconds: 5));
      } catch (_) {
        /* Always release capture below. */
      }
      await room.dispose();
    }
  }

  Future<void> _finish({required bool sendEnd}) async {
    if (_closing || _ended) return;
    _closing = true;
    _heartbeat?.cancel();
    _clock?.cancel();
    if (mounted) setState(() => _ended = true);
    // Release the camera/microphone before waiting for the backend.
    await _releaseRoom();
    if (sendEnd) {
      try {
        await widget.controller.act('end', callId: _call.id);
      } catch (_) {
        /* Server lease and scheduled cleanup handle offline hangup. */
      }
    }
    _closing = false;
    if (mounted) setState(() {});
  }

  Future<void> _toggle(Future<void> Function() action) async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      await action();
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Action impossible. Vérifiez les autorisations.',
        );
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await _finish(sendEnd: true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _clock?.cancel();
    _heartbeat?.cancel();
    final shouldEnd = !_ended;
    _ended = true;
    unawaited(_releaseRoom());
    if (shouldEnd) {
      unawaited(
        widget.controller
            .act('end', callId: widget.initialCall.id)
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final local = room?.localParticipant;
    final remote = room?.remoteParticipants.values.firstOrNull;
    final connected = room?.connectionState == ConnectionState.connected;
    final mic = local?.isMicrophoneEnabled() ?? false;
    final camera = local?.isCameraEnabled() ?? false;
    final elapsed = _call.acceptedAt == null
        ? Duration.zero
        : DateTime.now().difference(_call.acceptedAt!);
    final timer =
        '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    final status = _ended
        ? (_call.isActive ? 'Appel terminé' : _call.label)
        : _call.status == 'ringing'
        ? 'Appel en cours…'
        : _connecting
        ? 'Connexion…'
        : room?.connectionState == ConnectionState.reconnecting
        ? 'Reconnexion…'
        : remote == null
        ? 'En attente de votre interlocuteur…'
        : timer;
    return PopScope(
      canPop: _ended,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D192B),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Quitter l’appel',
                      onPressed: _leave,
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _call.otherName(widget.controller.userId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            status,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (remote?.connectionQuality == ConnectionQuality.poor)
                      const Tooltip(
                        message: 'Connexion faible',
                        child: Icon(
                          Icons.signal_cellular_alt_1_bar,
                          color: Colors.orangeAccent,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: _ParticipantVideo(
                              participant: _ended ? null : remote,
                              name: _call.otherName(widget.controller.userId),
                            ),
                          ),
                        ),
                        if (!_ended && local != null)
                          Positioned(
                            right: 12,
                            top: 12,
                            width: (constraints.maxWidth * .30).clamp(
                              95.0,
                              210.0,
                            ),
                            height: (constraints.maxHeight * .28).clamp(
                              95.0,
                              170.0,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: _ParticipantVideo(
                                participant: local,
                                name: 'Vous',
                                local: true,
                              ),
                            ),
                          ),
                        if (_connecting)
                          const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
              if (kIsWeb &&
                  !_ended &&
                  connected &&
                  room?.canPlaybackAudio == false)
                TextButton.icon(
                  onPressed: () => _toggle(() => room!.startAudio()),
                  icon: const Icon(
                    Icons.volume_up_rounded,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Activer le son',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              if (!_ended && !_connecting && _attempted && !connected)
                TextButton(
                  onPressed: _connect,
                  child: const Text(
                    'Réessayer',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: _ended
                    ? FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Fermer'),
                      )
                    : Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _CallControl(
                            tooltip: mic
                                ? 'Couper le micro'
                                : 'Activer le micro',
                            icon: mic
                                ? Icons.mic_rounded
                                : Icons.mic_off_rounded,
                            onPressed: connected && !_toggling
                                ? () => _toggle(() async {
                                    await local?.setMicrophoneEnabled(!mic);
                                  })
                                : null,
                          ),
                          _CallControl(
                            tooltip: camera
                                ? 'Couper la caméra'
                                : 'Activer la caméra',
                            icon: camera
                                ? Icons.videocam_rounded
                                : Icons.videocam_off_rounded,
                            onPressed: connected && !_toggling
                                ? () => _toggle(() async {
                                    await local?.setCameraEnabled(!camera);
                                  })
                                : null,
                          ),
                          if (!kIsWeb)
                            _CallControl(
                              tooltip: 'Retourner la caméra',
                              icon: Icons.cameraswitch_rounded,
                              onPressed: camera && !_toggling
                                  ? () => _toggle(() async {
                                      final track = local
                                          ?.videoTrackPublications
                                          .firstOrNull
                                          ?.track;
                                      if (track != null) {
                                        await track.setCameraPosition(
                                          _front
                                              ? CameraPosition.back
                                              : CameraPosition.front,
                                        );
                                        _front = !_front;
                                      }
                                    })
                                  : null,
                            ),
                          if (!kIsWeb)
                            _CallControl(
                              tooltip: _speaker
                                  ? 'Désactiver le haut-parleur'
                                  : 'Activer le haut-parleur',
                              icon: _speaker
                                  ? Icons.volume_up_rounded
                                  : Icons.hearing_rounded,
                              onPressed: connected && !_toggling
                                  ? () => _toggle(() async {
                                      await AudioManager.instance
                                          .setSpeakerOutputPreferred(!_speaker);
                                      _speaker = !_speaker;
                                    })
                                  : null,
                            ),
                          _CallControl(
                            tooltip: 'Raccrocher',
                            icon: Icons.call_end_rounded,
                            red: true,
                            onPressed: () => _finish(sendEnd: true),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantVideo extends StatelessWidget {
  final Participant? participant;
  final String name;
  final bool local;
  const _ParticipantVideo({
    this.participant,
    required this.name,
    this.local = false,
  });
  @override
  Widget build(BuildContext context) {
    final person = participant;
    if (person == null) return _placeholder();
    return ListenableBuilder(
      listenable: person,
      builder: (context, _) {
        final publication = person.videoTrackPublications
            .where(
              (p) =>
                  p.source == TrackSource.camera && !p.muted && p.track != null,
            )
            .firstOrNull;
        final track = publication?.track;
        return track is VideoTrack
            ? VideoTrackRenderer(
                track,
                fit: VideoViewFit.cover,
                mirrorMode: local
                    ? VideoViewMirrorMode.auto
                    : VideoViewMirrorMode.off,
              )
            : _placeholder();
      },
    );
  }

  Widget _placeholder() => ColoredBox(
    color: const Color(0xFF1B2D47),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_rounded,
            size: local ? 36 : 76,
            color: Colors.white38,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CallControl extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool red;
  final VoidCallback? onPressed;
  const _CallControl({
    required this.tooltip,
    required this.icon,
    this.red = false,
    this.onPressed,
  });
  @override
  Widget build(BuildContext context) => IconButton.filled(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: red ? const Color(0xFFE74F59) : const Color(0xFF273B57),
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0xFF1B2D47),
      disabledForegroundColor: Colors.white30,
      minimumSize: const Size(54, 54),
    ),
    icon: Icon(icon),
  );
}
