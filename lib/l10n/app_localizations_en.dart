// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingsTitle => 'Settings';

  @override
  String get devicesTitle => 'Devices';

  @override
  String get noDeviceFound => 'No devices found';

  @override
  String get authorizeSpotifyButton => 'Authorize Spotify';

  @override
  String get logoutSpotifyButton => 'Logout from Spotify';

  @override
  String loggedInAs(String username) {
    return 'Spotify: $username';
  }

  @override
  String get nowPlayingTab => 'NowPlaying';

  @override
  String get libraryTab => 'Library';

  @override
  String get roamTab => 'Roam';

  @override
  String get loginSuccess => 'Logged in with Spotify';

  @override
  String get recordsTab => 'RECORDS';

  @override
  String get queueTab => 'QUEUE';

  @override
  String get lyricsTab => 'LYRICS';

  @override
  String get devicesPageTitle => 'Devices';

  @override
  String get noDevicesFound => 'No devices found';

  @override
  String get sonosDeviceRestriction =>
      'Please control this device using Spotify or Sonos app';

  @override
  String get deviceRestricted => 'This device is not available';

  @override
  String get privateSession => 'Private Session';

  @override
  String get currentDevice => 'Current';

  @override
  String get editNote => 'Edit Note';

  @override
  String get deleteNote => 'Delete Note';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirmDelete => 'Confirm Delete';

  @override
  String get deleteConfirmMessage =>
      'Are you sure you want to delete this note? This action cannot be undone.';

  @override
  String get noNotes => 'No notes added yet.';

  @override
  String recordsAt(String time) {
    return 'Records at $time';
  }

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String playbackFailed(String error) {
    return 'Playback failed: $error';
  }

  @override
  String get searchHint => 'Search songs, albums, artists...';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get playToGenerateInsights => 'Play some music to generate insights!';

  @override
  String get generateInsights => 'Insights';

  @override
  String get generating => 'Generating...';

  @override
  String get collapse => 'Collapse';

  @override
  String get expand => 'Expand';

  @override
  String get noInsightsGenerated =>
      'Could not generate insights from the provided history.';

  @override
  String get insightsTitle => 'Insights';

  @override
  String get inspirationsTitle => 'Inspirations';

  @override
  String get unknownArtist => 'Unknown Artist';

  @override
  String get unknownTrack => 'Unknown Track';

  @override
  String failedToGenerateInsights(String error) {
    return 'Failed to generate insights: $error';
  }

  @override
  String copiedToClipboard(String type) {
    return 'Copied to clipboard';
  }

  @override
  String get musicPersonality => 'Music Personality';

  @override
  String get insightsContent => 'Insights Content';

  @override
  String get recommendedSong => 'Recommended Song';

  @override
  String get addNote => 'Add Note';

  @override
  String get noteHint => 'Enter your note here';

  @override
  String get saveNote => 'Save Note';

  @override
  String get noteSaved => 'Note saved';

  @override
  String errorSavingNote(String error) {
    return 'Error saving note: $error';
  }

  @override
  String get notesTitle => 'Notes';

  @override
  String get areYouSureDeleteNote =>
      'Are you sure you want to delete this note?';

  @override
  String get delete => 'Delete';

  @override
  String get noteDeleted => 'Note deleted';

  @override
  String errorDeletingNote(String error) {
    return 'Error deleting note: $error';
  }

  @override
  String get noteUpdated => 'Note updated successfully';

  @override
  String errorUpdatingNote(String error) {
    return 'Error updating note: $error';
  }

  @override
  String get lyricsFetching => 'Fetching lyrics...';

  @override
  String get lyricsFound => 'Lyrics found.';

  @override
  String get lyricsNotFoundForTrack => 'No lyrics found for this track.';

  @override
  String lyricsFetchError(String error) {
    return 'Error fetching lyrics: $error';
  }

  @override
  String get lyricsTranslating => 'Translating lyrics...';

  @override
  String get lyricsTranslationSuccessful => 'Translation successful.';

  @override
  String lyricsTranslationError(String error) {
    return 'Error translating lyrics: $error';
  }

  @override
  String get lyricsTitle => 'Lyrics';

  @override
  String get lyricsCopyModeTooltip => 'Copy Lyrics Mode';

  @override
  String get lyricsTranslateTooltip => 'Translate Lyrics';

  @override
  String get lyricsToggleAutoScrollTooltip => 'Toggle Auto-Scroll';

  @override
  String get lyricsNotAvailable => 'No lyrics available.';

  @override
  String get lyricsLoading => 'Loading lyrics...';

  @override
  String get lyricsFailedToLoad => 'Failed to load lyrics.';

  @override
  String get lyricsCopyModeSnackbar =>
      'Copy Lyrics Mode: Single repeat active, auto-scroll disabled.';

  @override
  String get couldNotGetCurrentTrackId => 'Could not get current track ID.';

  @override
  String translationFailed(Object error) {
    return 'Translation failed: $error';
  }

  @override
  String get centerCurrentLine => 'Center Current Line';

  @override
  String get translateLyrics => 'Translate Lyrics';

  @override
  String get exitCopyModeResumeScroll => 'Exit Copy Mode & Resume Scroll';

  @override
  String get enterCopyLyricsMode => 'Enter Copy Lyrics Mode (Single Repeat)';

  @override
  String get translationTitle => 'Translation';

  @override
  String get originalTitle => 'Original';

  @override
  String get translatedByAttribution => 'Translated by Gemini 2.5 Flash';

  @override
  String spiritLabel(String style) {
    return 'Spirit: $style';
  }

  @override
  String get copyToClipboard => 'Copy to Clipboard';

  @override
  String get retranslateButton => 'Retranslate';

  @override
  String get retranslating => 'Retranslating...';

  @override
  String get translationStyleFaithful => 'Faithful';

  @override
  String get translationStyleMelodramaticPoet => 'Melodramatic Poet';

  @override
  String get translationStyleMachineClassic => 'Machine Classic';

  @override
  String get translationStyleTooltipFaithful =>
      'Current: Faithful Translation - Tap to change';

  @override
  String get translationStyleTooltipMelodramatic =>
      'Current: Melodramatic Poet Translation - Tap to change';

  @override
  String get translationStyleTooltipMachine =>
      'Current: Machine Translation - Tap to change';

  @override
  String get toggleTranslationStyle => 'Toggle Translation Style';

  @override
  String get showTranslation => 'Show Translation';

  @override
  String get showOriginal => 'Show Original';

  @override
  String get closeTranslation => 'Close';

  @override
  String get trackSaved => 'Track saved to playlist';

  @override
  String errorSavingTrack(String error) {
    return 'Error saving track: $error';
  }

  @override
  String get unknownAlbum => 'Unknown Album';

  @override
  String get playlist => 'Playlist';

  @override
  String get unknownContext => 'Unknown Context';

  @override
  String get noTrackOrEmptyNote => 'Cannot get track info or note is empty';

  @override
  String get logoutSuccess => 'Logged out from Spotify';

  @override
  String get operationFailed => 'Operation failed';

  @override
  String get invalidCredentialsError =>
      'Invalid Spotify API credentials. Please check your Client ID and Secret.';

  @override
  String get authenticationError =>
      'Authentication failed: Invalid credentials or insufficient permissions.';

  @override
  String get tooManyRequestsError =>
      'Too many requests. Please try again later.';

  @override
  String loginLogoutFailed(Object error) {
    return 'Login/Logout failed: $error';
  }

  @override
  String get helpAction => 'Help';

  @override
  String get setupTitle => 'Setup';

  @override
  String get googleAiApiKeyTitle => 'Google AI API key';

  @override
  String get googleAiApiKeySubtitle =>
      'Set up your Google AI Studio API key for Gemini translation';

  @override
  String get spotifyApiTitle => 'Spotify API';

  @override
  String get spotifyApiSubtitle => 'Set Spotify Client ID and Secret';

  @override
  String get tutorialTitle => 'Tutorial';

  @override
  String get tutorialSubtitle => 'See tutorial for setting up';

  @override
  String get generalTitle => 'General';

  @override
  String get translationLanguageTitle => 'Gemini\'s Language';

  @override
  String get translationLanguageSubtitle =>
      'Choose the target language for translations and insights';

  @override
  String get translationStyleTitle => 'Translation Style';

  @override
  String get translationStyleSubtitle => 'Set Gemini\'s Spirit';

  @override
  String get copyLyricsAsSingleLineTitle => 'Copy lyrics as single line';

  @override
  String get copyLyricsAsSingleLineSubtitle =>
      'Replaces line breaks with spaces when copying';

  @override
  String get deepTranslationTitle => 'Deep Translation';

  @override
  String get deepTranslationSubtitle =>
      'Enable Gemini\'s thinking mode for better translations';

  @override
  String get dataManagementTitle => 'Data Management';

  @override
  String get exportDataTitle => 'Export Data';

  @override
  String get exportDataSubtitle => 'Export all data as JSON file';

  @override
  String get importDataTitle => 'Import Data';

  @override
  String get importDataSubtitle => 'Import data from exported JSON file';

  @override
  String get clearCacheTitle => 'Clear All Cache';

  @override
  String get clearCacheSubtitle => 'Clear lyrics and translation cache';

  @override
  String get geminiApiKeyDialogTitle => 'Gemini API key';

  @override
  String get geminiApiKeyDialogHint => 'Enter your Gemini API key';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get apiKeySaved => 'Gemini API key saved';

  @override
  String get okButton => 'OK';

  @override
  String get spotifyCredentialsDialogTitle => 'Spotify API';

  @override
  String get clientIdLabel => 'Client ID';

  @override
  String get clientSecretLabel => 'Client Secret';

  @override
  String get emptyCredentialsError => 'Both Client ID and Secret are required.';

  @override
  String get invalidClientIdError =>
      'Client ID must be a 32-character hex string.';

  @override
  String get invalidClientSecretError =>
      'Client Secret must be a 32-character hex string.';

  @override
  String get credentialsSaved => 'Spotify credentials saved';

  @override
  String get credentialsSaveFailed => 'Failed to save credentials';

  @override
  String get languageDialogTitle => 'Select Language';

  @override
  String get languageSaved => 'Language setting saved';

  @override
  String get translationStyleDialogTitle => 'Select Translation Style';

  @override
  String get translationStyleSaved => 'Translation style saved';

  @override
  String get exportFailed => 'Export failed or cancelled.';

  @override
  String get importDialogTitle => 'Confirm Import';

  @override
  String get importDialogMessage =>
      'Importing data will replace existing tracks and translations with the same identifiers, and add all records from the file. This cannot be undone. Are you sure you want to continue?\n\nEnsure the JSON file is valid and was previously exported from Spotoolfy.';

  @override
  String get importButton => 'Import Data';

  @override
  String get importSuccess => 'Data imported successfully!';

  @override
  String get importFailed => 'Failed to import data.';

  @override
  String get exportSuccess => 'Data exported successfully!';

  @override
  String get clearCacheDialogTitle => 'Confirm Clear Cache';

  @override
  String get clearCacheDialogMessage =>
      'Are you sure you want to clear the lyrics and translation cache? This cannot be undone.';

  @override
  String get clearCacheButton => 'Clear Cache';

  @override
  String get clearingCache => 'Clearing cache...';

  @override
  String get cacheCleared => 'Cache cleared successfully!';

  @override
  String get cacheClearFailed => 'Failed to clear cache';

  @override
  String failedToChangeLanguage(String error) {
    return 'Failed to change language: $error';
  }

  @override
  String failedToChangeStyle(String error) {
    return 'Failed to change translation style: $error';
  }

  @override
  String get noteContent => 'Note Content';

  @override
  String get saveChanges => 'Save';

  @override
  String get noLyricsToTranslate => 'No lyrics to translate.';

  @override
  String failedToSaveTranslation(Object error) {
    return 'Failed to save fetched translation: $error';
  }

  @override
  String get failedToGetTranslation => 'Failed to get translation.';

  @override
  String get copyLyricsModeHint =>
      'Copy Lyrics Mode: Single repeat active, auto-scroll disabled.';

  @override
  String get exitCopyMode => 'Exit Copy Mode & Resume Scroll';

  @override
  String get enterCopyMode => 'Enter Copy Lyrics Mode (Single Repeat)';

  @override
  String get selectLyrics => 'Select Lyrics';

  @override
  String get selectLyricsTooltip =>
      'Select lyrics fragments for analysis or sharing';

  @override
  String get selectAll => 'Select All';

  @override
  String get deselectAll => 'Deselect All';

  @override
  String get noLyricsSelected => 'Please select some lyrics first';

  @override
  String get askGemini => 'Ask Gemini';

  @override
  String get sharePoster => 'Share Poster';

  @override
  String get copySelected => 'Copy Selected';

  @override
  String get geminiAnalysisResult => 'Gemini Analysis Result';

  @override
  String get lyricsTheme => 'Theme';

  @override
  String get lyricsEmotion => 'Emotion';

  @override
  String get lyricsMetaphor => 'Metaphor and Symbolism';

  @override
  String get lyricsInterpretation => 'In-depth Interpretation';

  @override
  String get lyricsReference => 'References and Allusions';

  @override
  String get lyricsKeywordsExplanation => 'Keywords Explanation';

  @override
  String get copyAnalysis => 'Copy Analysis';

  @override
  String get analysisResultCopied => 'Analysis result copied to clipboard';

  @override
  String selectedLyricsCopied(int count) {
    return 'Copied $count lines of lyrics';
  }

  @override
  String posterGenerationFailed(Object error) {
    return 'Poster generation failed: $error';
  }

  @override
  String analysisFailed(String error) {
    return 'Analysis failed: $error';
  }

  @override
  String get noLyricsToSelect => 'No lyrics to select';

  @override
  String get posterLyricsLimitExceeded =>
      'Maximum 10 lines of lyrics can be selected for poster generation';

  @override
  String get multiSelectMode => 'Multi-select Mode';
}
