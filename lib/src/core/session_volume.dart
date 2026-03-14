// ─────────────────────────────────────────────────────────────────────────────
// SessionVolume
//
// App-wide singleton that holds current volume and mute state for the session.
// Lives in core so both app_state.dart and media_player_widget.dart can import
// it without creating a dependency from core → UI.
// ─────────────────────────────────────────────────────────────────────────────

class SessionVolume {
  SessionVolume._();
  static final SessionVolume instance = SessionVolume._();

  double volume = 1.0;
  bool muted = false;

  /// Called when a library is opened so the session reflects that library's
  /// startMuted setting.
  void initFromSettings(bool startMuted) {
    muted = startMuted;
  }
}
