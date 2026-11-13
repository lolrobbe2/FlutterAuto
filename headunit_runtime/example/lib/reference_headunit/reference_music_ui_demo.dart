import 'package:headunit_sdk/headunit_sdk.dart';

/// Small SDK-side example showing how an app publishes a headunit-native page.
///
/// The app does not import Flutter Material widgets for its headunit UI. The
/// shell chooses their appearance and handles focus/input consistently.
class ReferenceMusicUiDemo {
  final HeadunitUiController ui;
  bool _isPlaying = false;
  int _selectedTrack = 0;

  ReferenceMusicUiDemo(this.ui);

  Future<void> publish() => _publishPage();

  Future<void> _publishPage() {
    const List<String> tracks = <String>[
      'Midnight Drive',
      'Open Road',
      'Coastal Lights',
    ];
    final String selectedTrack = tracks[_selectedTrack];

    return ui.showPage(
      HeadunitUiPage(
        title: 'Music',
        subtitle: 'Reference application using standard headunit components',
        body: HeadunitUiColumn(
          children: <HeadunitUiComponent>[
            HeadunitUiCarousel(
              items: <HeadunitUiCarouselItem>[
                HeadunitUiCarouselItem(
                  id: 'recently-played',
                  title: 'Recently played',
                  subtitle: 'Continue listening',
                  action: HeadunitUiAction(
                    id: 'music.recent',
                    onInvoke: () => _showMessagePage('Recently played'),
                  ),
                ),
                HeadunitUiCarouselItem(
                  id: 'playlists',
                  title: 'Playlists',
                  subtitle: 'Your saved collections',
                  action: HeadunitUiAction(
                    id: 'music.playlists',
                    onInvoke: () => _showMessagePage('Your playlists'),
                  ),
                ),
                HeadunitUiCarouselItem(
                  id: 'radio',
                  title: 'Radio',
                  subtitle: 'Discover stations',
                  action: HeadunitUiAction(
                    id: 'music.radio',
                    onInvoke: () => _showMessagePage('Radio stations'),
                  ),
                ),
              ],
            ),
            HeadunitUiText(text: 'Queue', style: HeadunitUiTextStyle.title),
            HeadunitUiList(
              items: <HeadunitUiListItem>[
                for (int index = 0; index < tracks.length; index++)
                  HeadunitUiListItem(
                    id: 'track-$index',
                    title: tracks[index],
                    subtitle: index == _selectedTrack ? 'Now selected' : '3:42',
                    trailingText: index == _selectedTrack ? 'Playing' : null,
                    action: HeadunitUiAction(
                      id: 'music.track.$index',
                      onInvoke: () => _selectTrack(index),
                    ),
                  ),
              ],
            ),
            HeadunitUiMediaControls(
              title: selectedTrack,
              artist: 'FlutterAuto Radio',
              isPlaying: _isPlaying,
              progress: 0.42,
              previousAction: HeadunitUiAction(
                id: 'music.previous',
                onInvoke: () => _moveTrack(-1),
              ),
              playPauseAction: HeadunitUiAction(
                id: 'music.playPause',
                onInvoke: _togglePlayback,
              ),
              nextAction: HeadunitUiAction(
                id: 'music.next',
                onInvoke: () => _moveTrack(1),
              ),
            ),
            HeadunitUiButton(
              label: 'Show connection details',
              variant: HeadunitUiButtonVariant.secondary,
              action: HeadunitUiAction(
                id: 'music.connection',
                onInvoke: () => _showMessagePage('Connected to FlutterAuto'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePlayback() async {
    _isPlaying = !_isPlaying;
    await _publishPage();
  }

  Future<void> _moveTrack(int delta) async {
    _selectedTrack = (_selectedTrack + delta + 3) % 3;
    await _publishPage();
  }

  Future<void> _selectTrack(int index) async {
    _selectedTrack = index;
    _isPlaying = true;
    await _publishPage();
  }

  Future<void> _showMessagePage(String title) {
    return ui.showPage(
      HeadunitUiPage(
        title: title,
        body: HeadunitUiColumn(
          children: <HeadunitUiComponent>[
            HeadunitUiText(
              text: 'This page is described by the application SDK and rendered by the headunit.',
            ),
            HeadunitUiButton(
              label: 'Back to music',
              action: HeadunitUiAction(
                id: 'music.back',
                onInvoke: _publishPage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
