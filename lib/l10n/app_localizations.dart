import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('zh'),
    Locale('zh', 'TW'),
  ];

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @devicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devicesTitle;

  /// No description provided for @noDeviceFound.
  ///
  /// In en, this message translates to:
  /// **'No devices found'**
  String get noDeviceFound;

  /// No description provided for @authorizeSpotifyButton.
  ///
  /// In en, this message translates to:
  /// **'Authorize Spotify'**
  String get authorizeSpotifyButton;

  /// No description provided for @logoutSpotifyButton.
  ///
  /// In en, this message translates to:
  /// **'Logout from Spotify'**
  String get logoutSpotifyButton;

  /// Status text showing the logged in Spotify username
  ///
  /// In en, this message translates to:
  /// **'Spotify: {username}'**
  String loggedInAs(String username);

  /// No description provided for @nowPlayingTab.
  ///
  /// In en, this message translates to:
  /// **'NowPlaying'**
  String get nowPlayingTab;

  /// No description provided for @libraryTab.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryTab;

  /// No description provided for @roamTab.
  ///
  /// In en, this message translates to:
  /// **'Roam'**
  String get roamTab;

  /// No description provided for @loginSuccess.
  ///
  /// In en, this message translates to:
  /// **'Logged in with Spotify'**
  String get loginSuccess;

  /// No description provided for @recordsTab.
  ///
  /// In en, this message translates to:
  /// **'RECORDS'**
  String get recordsTab;

  /// No description provided for @queueTab.
  ///
  /// In en, this message translates to:
  /// **'QUEUE'**
  String get queueTab;

  /// No description provided for @lyricsTab.
  ///
  /// In en, this message translates to:
  /// **'LYRICS'**
  String get lyricsTab;

  /// No description provided for @devicesPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devicesPageTitle;

  /// No description provided for @noDevicesFound.
  ///
  /// In en, this message translates to:
  /// **'No devices found'**
  String get noDevicesFound;

  /// No description provided for @sonosDeviceRestriction.
  ///
  /// In en, this message translates to:
  /// **'Please control this device using Spotify or Sonos app'**
  String get sonosDeviceRestriction;

  /// No description provided for @deviceRestricted.
  ///
  /// In en, this message translates to:
  /// **'This device is not available'**
  String get deviceRestricted;

  /// No description provided for @privateSession.
  ///
  /// In en, this message translates to:
  /// **'Private Session'**
  String get privateSession;

  /// No description provided for @currentDevice.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get currentDevice;

  /// No description provided for @editNote.
  ///
  /// In en, this message translates to:
  /// **'Edit Note'**
  String get editNote;

  /// No description provided for @deleteNote.
  ///
  /// In en, this message translates to:
  /// **'Delete Note'**
  String get deleteNote;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get confirmDelete;

  /// No description provided for @deleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this note? This action cannot be undone.'**
  String get deleteConfirmMessage;

  /// No description provided for @noNotes.
  ///
  /// In en, this message translates to:
  /// **'No notes added yet.'**
  String get noNotes;

  /// Text showing when a record was created
  ///
  /// In en, this message translates to:
  /// **'Records at {time}'**
  String recordsAt(String time);

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// Error message when playback fails
  ///
  /// In en, this message translates to:
  /// **'Playback failed: {error}'**
  String playbackFailed(String error);

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search songs, albums, artists...'**
  String get searchHint;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @playToGenerateInsights.
  ///
  /// In en, this message translates to:
  /// **'Play some music to generate insights!'**
  String get playToGenerateInsights;

  /// No description provided for @generateInsights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get generateInsights;

  /// No description provided for @generating.
  ///
  /// In en, this message translates to:
  /// **'Generating...'**
  String get generating;

  /// No description provided for @collapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get collapse;

  /// No description provided for @expand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get expand;

  /// No description provided for @noInsightsGenerated.
  ///
  /// In en, this message translates to:
  /// **'Could not generate insights from the provided history.'**
  String get noInsightsGenerated;

  /// No description provided for @insightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get insightsTitle;

  /// No description provided for @inspirationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Inspirations'**
  String get inspirationsTitle;

  /// No description provided for @unknownArtist.
  ///
  /// In en, this message translates to:
  /// **'Unknown Artist'**
  String get unknownArtist;

  /// No description provided for @unknownTrack.
  ///
  /// In en, this message translates to:
  /// **'Unknown Track'**
  String get unknownTrack;

  /// Error message when insights generation fails
  ///
  /// In en, this message translates to:
  /// **'Failed to generate insights: {error}'**
  String failedToGenerateInsights(String error);

  /// Message shown when something is copied to clipboard
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String copiedToClipboard(String type);

  /// No description provided for @musicPersonality.
  ///
  /// In en, this message translates to:
  /// **'Music Personality'**
  String get musicPersonality;

  /// No description provided for @insightsContent.
  ///
  /// In en, this message translates to:
  /// **'Insights Content'**
  String get insightsContent;

  /// No description provided for @recommendedSong.
  ///
  /// In en, this message translates to:
  /// **'Recommended Song'**
  String get recommendedSong;

  /// No description provided for @addNote.
  ///
  /// In en, this message translates to:
  /// **'Add Note'**
  String get addNote;

  /// No description provided for @noteHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your note here'**
  String get noteHint;

  /// No description provided for @saveNote.
  ///
  /// In en, this message translates to:
  /// **'Save Note'**
  String get saveNote;

  /// No description provided for @noteSaved.
  ///
  /// In en, this message translates to:
  /// **'Note saved'**
  String get noteSaved;

  /// Error message when saving note fails
  ///
  /// In en, this message translates to:
  /// **'Error saving note: {error}'**
  String errorSavingNote(String error);

  /// No description provided for @notesTitle.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesTitle;

  /// No description provided for @areYouSureDeleteNote.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this note?'**
  String get areYouSureDeleteNote;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @noteDeleted.
  ///
  /// In en, this message translates to:
  /// **'Note deleted'**
  String get noteDeleted;

  /// No description provided for @errorDeletingNote.
  ///
  /// In en, this message translates to:
  /// **'Error deleting note: {error}'**
  String errorDeletingNote(String error);

  /// No description provided for @noteUpdated.
  ///
  /// In en, this message translates to:
  /// **'Note updated successfully'**
  String get noteUpdated;

  /// No description provided for @errorUpdatingNote.
  ///
  /// In en, this message translates to:
  /// **'Error updating note: {error}'**
  String errorUpdatingNote(String error);

  /// No description provided for @lyricsFetching.
  ///
  /// In en, this message translates to:
  /// **'Fetching lyrics...'**
  String get lyricsFetching;

  /// No description provided for @lyricsFound.
  ///
  /// In en, this message translates to:
  /// **'Lyrics found.'**
  String get lyricsFound;

  /// No description provided for @lyricsNotFoundForTrack.
  ///
  /// In en, this message translates to:
  /// **'No lyrics found for this track.'**
  String get lyricsNotFoundForTrack;

  /// No description provided for @lyricsFetchError.
  ///
  /// In en, this message translates to:
  /// **'Error fetching lyrics: {error}'**
  String lyricsFetchError(String error);

  /// No description provided for @lyricsTranslating.
  ///
  /// In en, this message translates to:
  /// **'Translating lyrics...'**
  String get lyricsTranslating;

  /// No description provided for @lyricsTranslationSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Translation successful.'**
  String get lyricsTranslationSuccessful;

  /// No description provided for @lyricsTranslationError.
  ///
  /// In en, this message translates to:
  /// **'Error translating lyrics: {error}'**
  String lyricsTranslationError(String error);

  /// No description provided for @lyricsTitle.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get lyricsTitle;

  /// No description provided for @lyricsCopyModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy Lyrics Mode'**
  String get lyricsCopyModeTooltip;

  /// No description provided for @lyricsTranslateTooltip.
  ///
  /// In en, this message translates to:
  /// **'Translate Lyrics'**
  String get lyricsTranslateTooltip;

  /// No description provided for @lyricsToggleAutoScrollTooltip.
  ///
  /// In en, this message translates to:
  /// **'Toggle Auto-Scroll'**
  String get lyricsToggleAutoScrollTooltip;

  /// No description provided for @lyricsNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'No lyrics available.'**
  String get lyricsNotAvailable;

  /// No description provided for @lyricsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading lyrics...'**
  String get lyricsLoading;

  /// No description provided for @lyricsFailedToLoad.
  ///
  /// In en, this message translates to:
  /// **'Failed to load lyrics.'**
  String get lyricsFailedToLoad;

  /// No description provided for @lyricsCopyModeSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Copy Lyrics Mode: Single repeat active, auto-scroll disabled.'**
  String get lyricsCopyModeSnackbar;

  /// No description provided for @couldNotGetCurrentTrackId.
  ///
  /// In en, this message translates to:
  /// **'Could not get current track ID.'**
  String get couldNotGetCurrentTrackId;

  /// No description provided for @translationFailed.
  ///
  /// In en, this message translates to:
  /// **'Translation failed: {error}'**
  String translationFailed(Object error);

  /// No description provided for @centerCurrentLine.
  ///
  /// In en, this message translates to:
  /// **'Center Current Line'**
  String get centerCurrentLine;

  /// No description provided for @translateLyrics.
  ///
  /// In en, this message translates to:
  /// **'Translate Lyrics'**
  String get translateLyrics;

  /// No description provided for @exitCopyModeResumeScroll.
  ///
  /// In en, this message translates to:
  /// **'Exit Copy Mode & Resume Scroll'**
  String get exitCopyModeResumeScroll;

  /// No description provided for @enterCopyLyricsMode.
  ///
  /// In en, this message translates to:
  /// **'Enter Copy Lyrics Mode (Single Repeat)'**
  String get enterCopyLyricsMode;

  /// No description provided for @translationTitle.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get translationTitle;

  /// No description provided for @originalTitle.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get originalTitle;

  /// No description provided for @translatedByAttribution.
  ///
  /// In en, this message translates to:
  /// **'Translated by Gemini 2.5 Flash'**
  String get translatedByAttribution;

  /// No description provided for @spiritLabel.
  ///
  /// In en, this message translates to:
  /// **'Spirit: {style}'**
  String spiritLabel(String style);

  /// No description provided for @copyToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy to Clipboard'**
  String get copyToClipboard;

  /// No description provided for @retranslateButton.
  ///
  /// In en, this message translates to:
  /// **'Retranslate'**
  String get retranslateButton;

  /// No description provided for @retranslating.
  ///
  /// In en, this message translates to:
  /// **'Retranslating...'**
  String get retranslating;

  /// No description provided for @translationStyleFaithful.
  ///
  /// In en, this message translates to:
  /// **'Faithful'**
  String get translationStyleFaithful;

  /// No description provided for @translationStyleMelodramaticPoet.
  ///
  /// In en, this message translates to:
  /// **'Melodramatic Poet'**
  String get translationStyleMelodramaticPoet;

  /// No description provided for @translationStyleMachineClassic.
  ///
  /// In en, this message translates to:
  /// **'Machine Classic'**
  String get translationStyleMachineClassic;

  /// No description provided for @translationStyleTooltipFaithful.
  ///
  /// In en, this message translates to:
  /// **'Current: Faithful Translation - Tap to change'**
  String get translationStyleTooltipFaithful;

  /// No description provided for @translationStyleTooltipMelodramatic.
  ///
  /// In en, this message translates to:
  /// **'Current: Melodramatic Poet Translation - Tap to change'**
  String get translationStyleTooltipMelodramatic;

  /// No description provided for @translationStyleTooltipMachine.
  ///
  /// In en, this message translates to:
  /// **'Current: Machine Translation - Tap to change'**
  String get translationStyleTooltipMachine;

  /// No description provided for @toggleTranslationStyle.
  ///
  /// In en, this message translates to:
  /// **'Toggle Translation Style'**
  String get toggleTranslationStyle;

  /// No description provided for @showTranslation.
  ///
  /// In en, this message translates to:
  /// **'Show Translation'**
  String get showTranslation;

  /// No description provided for @showOriginal.
  ///
  /// In en, this message translates to:
  /// **'Show Original'**
  String get showOriginal;

  /// No description provided for @closeTranslation.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeTranslation;

  /// No description provided for @trackSaved.
  ///
  /// In en, this message translates to:
  /// **'Track saved to playlist'**
  String get trackSaved;

  /// No description provided for @errorSavingTrack.
  ///
  /// In en, this message translates to:
  /// **'Error saving track: {error}'**
  String errorSavingTrack(String error);

  /// No description provided for @unknownAlbum.
  ///
  /// In en, this message translates to:
  /// **'Unknown Album'**
  String get unknownAlbum;

  /// No description provided for @playlist.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get playlist;

  /// No description provided for @unknownContext.
  ///
  /// In en, this message translates to:
  /// **'Unknown Context'**
  String get unknownContext;

  /// No description provided for @noTrackOrEmptyNote.
  ///
  /// In en, this message translates to:
  /// **'Cannot get track info or note is empty'**
  String get noTrackOrEmptyNote;

  /// No description provided for @logoutSuccess.
  ///
  /// In en, this message translates to:
  /// **'Logged out from Spotify'**
  String get logoutSuccess;

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed'**
  String get operationFailed;

  /// No description provided for @invalidCredentialsError.
  ///
  /// In en, this message translates to:
  /// **'Invalid Spotify API credentials. Please check your Client ID and Secret.'**
  String get invalidCredentialsError;

  /// No description provided for @authenticationError.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed: Invalid credentials or insufficient permissions.'**
  String get authenticationError;

  /// No description provided for @tooManyRequestsError.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Please try again later.'**
  String get tooManyRequestsError;

  /// Error message for login or logout failure
  ///
  /// In en, this message translates to:
  /// **'Login/Logout failed: {error}'**
  String loginLogoutFailed(Object error);

  /// No description provided for @helpAction.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get helpAction;

  /// No description provided for @setupTitle.
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get setupTitle;

  /// No description provided for @googleAiApiKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Google AI API key'**
  String get googleAiApiKeyTitle;

  /// No description provided for @googleAiApiKeySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your Google AI Studio API key for Gemini translation'**
  String get googleAiApiKeySubtitle;

  /// No description provided for @spotifyApiTitle.
  ///
  /// In en, this message translates to:
  /// **'Spotify API'**
  String get spotifyApiTitle;

  /// No description provided for @spotifyApiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set Spotify Client ID and Secret'**
  String get spotifyApiSubtitle;

  /// No description provided for @tutorialTitle.
  ///
  /// In en, this message translates to:
  /// **'Tutorial'**
  String get tutorialTitle;

  /// No description provided for @tutorialSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See tutorial for setting up'**
  String get tutorialSubtitle;

  /// No description provided for @generalTitle.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get generalTitle;

  /// No description provided for @translationLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Gemini\'s Language'**
  String get translationLanguageTitle;

  /// No description provided for @translationLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the target language for translations and insights'**
  String get translationLanguageSubtitle;

  /// No description provided for @translationStyleTitle.
  ///
  /// In en, this message translates to:
  /// **'Translation Style'**
  String get translationStyleTitle;

  /// No description provided for @translationStyleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set Gemini\'s Spirit'**
  String get translationStyleSubtitle;

  /// No description provided for @copyLyricsAsSingleLineTitle.
  ///
  /// In en, this message translates to:
  /// **'Copy lyrics as single line'**
  String get copyLyricsAsSingleLineTitle;

  /// No description provided for @copyLyricsAsSingleLineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Replaces line breaks with spaces when copying'**
  String get copyLyricsAsSingleLineSubtitle;

  /// No description provided for @deepTranslationTitle.
  ///
  /// In en, this message translates to:
  /// **'Deep Translation'**
  String get deepTranslationTitle;

  /// No description provided for @deepTranslationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enable Gemini\'s thinking mode for better translations'**
  String get deepTranslationSubtitle;

  /// No description provided for @dataManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Data Management'**
  String get dataManagementTitle;

  /// No description provided for @exportDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Data'**
  String get exportDataTitle;

  /// No description provided for @exportDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Export all data as JSON file'**
  String get exportDataSubtitle;

  /// No description provided for @importDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Data'**
  String get importDataTitle;

  /// No description provided for @importDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Import data from exported JSON file'**
  String get importDataSubtitle;

  /// No description provided for @clearCacheTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear All Cache'**
  String get clearCacheTitle;

  /// No description provided for @clearCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clear lyrics and translation cache'**
  String get clearCacheSubtitle;

  /// No description provided for @geminiApiKeyDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Gemini API key'**
  String get geminiApiKeyDialogTitle;

  /// No description provided for @geminiApiKeyDialogHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your Gemini API key'**
  String get geminiApiKeyDialogHint;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @apiKeySaved.
  ///
  /// In en, this message translates to:
  /// **'Gemini API key saved'**
  String get apiKeySaved;

  /// No description provided for @okButton.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get okButton;

  /// No description provided for @spotifyCredentialsDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Spotify API'**
  String get spotifyCredentialsDialogTitle;

  /// No description provided for @clientIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Client ID'**
  String get clientIdLabel;

  /// No description provided for @clientSecretLabel.
  ///
  /// In en, this message translates to:
  /// **'Client Secret'**
  String get clientSecretLabel;

  /// No description provided for @emptyCredentialsError.
  ///
  /// In en, this message translates to:
  /// **'Both Client ID and Secret are required.'**
  String get emptyCredentialsError;

  /// No description provided for @invalidClientIdError.
  ///
  /// In en, this message translates to:
  /// **'Client ID must be a 32-character hex string.'**
  String get invalidClientIdError;

  /// No description provided for @invalidClientSecretError.
  ///
  /// In en, this message translates to:
  /// **'Client Secret must be a 32-character hex string.'**
  String get invalidClientSecretError;

  /// No description provided for @credentialsSaved.
  ///
  /// In en, this message translates to:
  /// **'Spotify credentials saved'**
  String get credentialsSaved;

  /// No description provided for @credentialsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save credentials'**
  String get credentialsSaveFailed;

  /// No description provided for @languageDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get languageDialogTitle;

  /// No description provided for @languageSaved.
  ///
  /// In en, this message translates to:
  /// **'Language setting saved'**
  String get languageSaved;

  /// No description provided for @translationStyleDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Translation Style'**
  String get translationStyleDialogTitle;

  /// No description provided for @translationStyleSaved.
  ///
  /// In en, this message translates to:
  /// **'Translation style saved'**
  String get translationStyleSaved;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed or cancelled.'**
  String get exportFailed;

  /// No description provided for @importDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Import'**
  String get importDialogTitle;

  /// No description provided for @importDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Importing data will replace existing tracks and translations with the same identifiers, and add all records from the file. This cannot be undone. Are you sure you want to continue?\n\nEnsure the JSON file is valid and was previously exported from Spotoolfy.'**
  String get importDialogMessage;

  /// No description provided for @importButton.
  ///
  /// In en, this message translates to:
  /// **'Import Data'**
  String get importButton;

  /// No description provided for @importSuccess.
  ///
  /// In en, this message translates to:
  /// **'Data imported successfully!'**
  String get importSuccess;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to import data.'**
  String get importFailed;

  /// No description provided for @exportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Data exported successfully!'**
  String get exportSuccess;

  /// No description provided for @clearCacheDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Clear Cache'**
  String get clearCacheDialogTitle;

  /// No description provided for @clearCacheDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear the lyrics and translation cache? This cannot be undone.'**
  String get clearCacheDialogMessage;

  /// No description provided for @clearCacheButton.
  ///
  /// In en, this message translates to:
  /// **'Clear Cache'**
  String get clearCacheButton;

  /// No description provided for @clearingCache.
  ///
  /// In en, this message translates to:
  /// **'Clearing cache...'**
  String get clearingCache;

  /// No description provided for @cacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared successfully!'**
  String get cacheCleared;

  /// No description provided for @cacheClearFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to clear cache'**
  String get cacheClearFailed;

  /// Error message when changing language fails
  ///
  /// In en, this message translates to:
  /// **'Failed to change language: {error}'**
  String failedToChangeLanguage(String error);

  /// Error message when changing translation style fails
  ///
  /// In en, this message translates to:
  /// **'Failed to change translation style: {error}'**
  String failedToChangeStyle(String error);

  /// No description provided for @noteContent.
  ///
  /// In en, this message translates to:
  /// **'Note Content'**
  String get noteContent;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveChanges;

  /// No description provided for @noLyricsToTranslate.
  ///
  /// In en, this message translates to:
  /// **'No lyrics to translate.'**
  String get noLyricsToTranslate;

  /// No description provided for @failedToSaveTranslation.
  ///
  /// In en, this message translates to:
  /// **'Failed to save fetched translation: {error}'**
  String failedToSaveTranslation(Object error);

  /// No description provided for @failedToGetTranslation.
  ///
  /// In en, this message translates to:
  /// **'Failed to get translation.'**
  String get failedToGetTranslation;

  /// No description provided for @copyLyricsModeHint.
  ///
  /// In en, this message translates to:
  /// **'Copy Lyrics Mode: Single repeat active, auto-scroll disabled.'**
  String get copyLyricsModeHint;

  /// No description provided for @exitCopyMode.
  ///
  /// In en, this message translates to:
  /// **'Exit Copy Mode & Resume Scroll'**
  String get exitCopyMode;

  /// No description provided for @enterCopyMode.
  ///
  /// In en, this message translates to:
  /// **'Enter Copy Lyrics Mode (Single Repeat)'**
  String get enterCopyMode;

  /// No description provided for @selectLyrics.
  ///
  /// In en, this message translates to:
  /// **'Select Lyrics'**
  String get selectLyrics;

  /// No description provided for @selectLyricsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Select lyrics fragments for analysis or sharing'**
  String get selectLyricsTooltip;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get deselectAll;

  /// No description provided for @noLyricsSelected.
  ///
  /// In en, this message translates to:
  /// **'Please select some lyrics first'**
  String get noLyricsSelected;

  /// No description provided for @askGemini.
  ///
  /// In en, this message translates to:
  /// **'Ask Gemini'**
  String get askGemini;

  /// No description provided for @sharePoster.
  ///
  /// In en, this message translates to:
  /// **'Share Poster'**
  String get sharePoster;

  /// No description provided for @copySelected.
  ///
  /// In en, this message translates to:
  /// **'Copy Selected'**
  String get copySelected;

  /// No description provided for @geminiAnalysisResult.
  ///
  /// In en, this message translates to:
  /// **'Gemini Analysis Result'**
  String get geminiAnalysisResult;

  /// No description provided for @lyricsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get lyricsTheme;

  /// No description provided for @lyricsEmotion.
  ///
  /// In en, this message translates to:
  /// **'Emotion'**
  String get lyricsEmotion;

  /// No description provided for @lyricsMetaphor.
  ///
  /// In en, this message translates to:
  /// **'Metaphor and Symbolism'**
  String get lyricsMetaphor;

  /// No description provided for @lyricsInterpretation.
  ///
  /// In en, this message translates to:
  /// **'In-depth Interpretation'**
  String get lyricsInterpretation;

  /// No description provided for @lyricsReference.
  ///
  /// In en, this message translates to:
  /// **'References and Allusions'**
  String get lyricsReference;

  /// No description provided for @lyricsKeywordsExplanation.
  ///
  /// In en, this message translates to:
  /// **'Keywords Explanation'**
  String get lyricsKeywordsExplanation;

  /// No description provided for @copyAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Copy Analysis'**
  String get copyAnalysis;

  /// No description provided for @analysisResultCopied.
  ///
  /// In en, this message translates to:
  /// **'Analysis result copied to clipboard'**
  String get analysisResultCopied;

  /// No description provided for @selectedLyricsCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied {count} lines of lyrics'**
  String selectedLyricsCopied(int count);

  /// No description provided for @posterGenerationFailed.
  ///
  /// In en, this message translates to:
  /// **'Poster generation failed: {error}'**
  String posterGenerationFailed(Object error);

  /// No description provided for @analysisFailed.
  ///
  /// In en, this message translates to:
  /// **'Analysis failed: {error}'**
  String analysisFailed(String error);

  /// No description provided for @noLyricsToSelect.
  ///
  /// In en, this message translates to:
  /// **'No lyrics available to select'**
  String get noLyricsToSelect;

  /// No description provided for @posterLyricsLimitExceeded.
  ///
  /// In en, this message translates to:
  /// **'Maximum 10 lines of lyrics can be selected for poster generation'**
  String get posterLyricsLimitExceeded;

  /// No description provided for @multiSelectMode.
  ///
  /// In en, this message translates to:
  /// **'Multi-select Mode'**
  String get multiSelectMode;

  /// No description provided for @tapToSelectLyrics.
  ///
  /// In en, this message translates to:
  /// **'Tap lyric line to select'**
  String get tapToSelectLyrics;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Spotoolfy'**
  String get appTitle;

  /// No description provided for @nowPlayingLabel.
  ///
  /// In en, this message translates to:
  /// **'NowPlaying'**
  String get nowPlayingLabel;

  /// No description provided for @libraryLabel.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryLabel;

  /// No description provided for @roamLabel.
  ///
  /// In en, this message translates to:
  /// **'Roam'**
  String get roamLabel;

  /// No description provided for @tutorialButtonText.
  ///
  /// In en, this message translates to:
  /// **'Tutorial'**
  String get tutorialButtonText;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageSimplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'简体中文 (Simplified Chinese)'**
  String get languageSimplifiedChinese;

  /// No description provided for @languageTraditionalChinese.
  ///
  /// In en, this message translates to:
  /// **'繁體中文 (Traditional Chinese)'**
  String get languageTraditionalChinese;

  /// No description provided for @languageJapanese.
  ///
  /// In en, this message translates to:
  /// **'日本語 (Japanese)'**
  String get languageJapanese;

  /// No description provided for @collapseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get collapseTooltip;

  /// No description provided for @expandTooltip.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get expandTooltip;

  /// No description provided for @incompleteRecordError.
  ///
  /// In en, this message translates to:
  /// **'Cannot proceed: Incomplete record information'**
  String get incompleteRecordError;

  /// No description provided for @optionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get optionsTitle;

  /// Button text to play from a specific timestamp
  ///
  /// In en, this message translates to:
  /// **'Play from {timestamp}'**
  String playFromTimestamp(String timestamp);

  /// No description provided for @editNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Note'**
  String get editNoteTitle;

  /// No description provided for @ratedStatus.
  ///
  /// In en, this message translates to:
  /// **'Rated'**
  String get ratedStatus;

  /// No description provided for @noItemsFound.
  ///
  /// In en, this message translates to:
  /// **'No items found'**
  String get noItemsFound;

  /// No description provided for @cannotCreateSpotifyLink.
  ///
  /// In en, this message translates to:
  /// **'Cannot create Spotify link'**
  String get cannotCreateSpotifyLink;

  /// No description provided for @cannotOpenSpotify.
  ///
  /// In en, this message translates to:
  /// **'Cannot open Spotify'**
  String get cannotOpenSpotify;

  /// Error message when failing to open Spotify
  ///
  /// In en, this message translates to:
  /// **'Failed to open Spotify: {error}'**
  String failedToOpenSpotify(String error);

  /// No description provided for @playlistsTab.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get playlistsTab;

  /// No description provided for @albumsTab.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get albumsTab;

  /// No description provided for @tryAgainButton.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get tryAgainButton;

  /// No description provided for @playTrackToSeeThoughts.
  ///
  /// In en, this message translates to:
  /// **'Play a track to see thoughts.'**
  String get playTrackToSeeThoughts;

  /// No description provided for @copyButtonText.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyButtonText;

  /// No description provided for @posterButtonLabel.
  ///
  /// In en, this message translates to:
  /// **'Poster'**
  String get posterButtonLabel;

  /// No description provided for @noteButtonLabel.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get noteButtonLabel;

  /// No description provided for @lyricsAnalysisTitle.
  ///
  /// In en, this message translates to:
  /// **'Lyrics Analysis'**
  String get lyricsAnalysisTitle;

  /// No description provided for @regenerateAnalysisTooltip.
  ///
  /// In en, this message translates to:
  /// **'Regenerate Analysis'**
  String get regenerateAnalysisTooltip;

  /// No description provided for @copyAllAnalysisTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy All Analysis'**
  String get copyAllAnalysisTooltip;

  /// No description provided for @geminiGrounding.
  ///
  /// In en, this message translates to:
  /// **'Gemini\'s grounding...'**
  String get geminiGrounding;

  /// No description provided for @retryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButton;

  /// No description provided for @noAnalysisResults.
  ///
  /// In en, this message translates to:
  /// **'No analysis results'**
  String get noAnalysisResults;

  /// No description provided for @noDeepAnalysisContent.
  ///
  /// In en, this message translates to:
  /// **'No deep analysis content for this lyric fragment'**
  String get noDeepAnalysisContent;

  /// No description provided for @simpleContentExplanation.
  ///
  /// In en, this message translates to:
  /// **'This may be because the lyrics are relatively simple, or have no obvious metaphors, references, or literary devices'**
  String get simpleContentExplanation;

  /// No description provided for @reanalyzeButton.
  ///
  /// In en, this message translates to:
  /// **'Re-analyze'**
  String get reanalyzeButton;

  /// No description provided for @onlyFoundDimensionsInfo.
  ///
  /// In en, this message translates to:
  /// **'Only displays analysis dimensions found in these lyrics'**
  String get onlyFoundDimensionsInfo;

  /// No description provided for @songInfoRegeneratedMessage.
  ///
  /// In en, this message translates to:
  /// **'Song information regenerated'**
  String get songInfoRegeneratedMessage;

  /// No description provided for @songInformationTitle.
  ///
  /// In en, this message translates to:
  /// **'Song Information'**
  String get songInformationTitle;

  /// No description provided for @regenerateTooltip.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get regenerateTooltip;

  /// No description provided for @noSongInfoAvailable.
  ///
  /// In en, this message translates to:
  /// **'No song information available'**
  String get noSongInfoAvailable;

  /// No description provided for @generatedByGemini.
  ///
  /// In en, this message translates to:
  /// **'Generated by Gemini 2.5 Flash'**
  String get generatedByGemini;

  /// No description provided for @poweredByGoogleSearch.
  ///
  /// In en, this message translates to:
  /// **'Powered by Google Search Grounding'**
  String get poweredByGoogleSearch;

  /// No description provided for @creationTimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Creation Time'**
  String get creationTimeTitle;

  /// No description provided for @creationLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Creation Location'**
  String get creationLocationTitle;

  /// No description provided for @lyricistTitle.
  ///
  /// In en, this message translates to:
  /// **'Lyricist'**
  String get lyricistTitle;

  /// No description provided for @composerTitle.
  ///
  /// In en, this message translates to:
  /// **'Composer'**
  String get composerTitle;

  /// No description provided for @producerTitle.
  ///
  /// In en, this message translates to:
  /// **'Producer'**
  String get producerTitle;

  /// No description provided for @songAnalysisTitle.
  ///
  /// In en, this message translates to:
  /// **'Song Analysis'**
  String get songAnalysisTitle;

  /// No description provided for @selectArtistTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Artist'**
  String get selectArtistTitle;

  /// No description provided for @backToLibraryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Back to library'**
  String get backToLibraryTooltip;

  /// No description provided for @appWatermark.
  ///
  /// In en, this message translates to:
  /// **'Spotoolfy'**
  String get appWatermark;

  /// No description provided for @loadingAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing lyrics with AI...'**
  String get loadingAnalyzing;

  /// No description provided for @loadingDecoding.
  ///
  /// In en, this message translates to:
  /// **'Decoding musical mysteries...'**
  String get loadingDecoding;

  /// No description provided for @loadingSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching for insights...'**
  String get loadingSearching;

  /// No description provided for @loadingThinking.
  ///
  /// In en, this message translates to:
  /// **'Gemini is thinking...'**
  String get loadingThinking;

  /// No description provided for @loadingGenerating.
  ///
  /// In en, this message translates to:
  /// **'Generating analysis...'**
  String get loadingGenerating;

  /// Loading message mentioning artist
  ///
  /// In en, this message translates to:
  /// **'Having a chat with {artist}...'**
  String loadingChatting(String artist);

  /// No description provided for @loadingDiscovering.
  ///
  /// In en, this message translates to:
  /// **'Discovering hidden meanings...'**
  String get loadingDiscovering;

  /// No description provided for @loadingExploring.
  ///
  /// In en, this message translates to:
  /// **'Exploring lyrical depths...'**
  String get loadingExploring;

  /// No description provided for @loadingUnraveling.
  ///
  /// In en, this message translates to:
  /// **'Unraveling poetic layers...'**
  String get loadingUnraveling;

  /// No description provided for @loadingConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting emotional threads...'**
  String get loadingConnecting;

  /// No description provided for @currentQueueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Current queue is empty'**
  String get currentQueueEmpty;

  /// No description provided for @queueUpNext.
  ///
  /// In en, this message translates to:
  /// **'Up Next'**
  String get queueUpNext;

  /// No description provided for @noQueueItems.
  ///
  /// In en, this message translates to:
  /// **'No upcoming tracks'**
  String get noQueueItems;

  /// Position indicator in queue
  ///
  /// In en, this message translates to:
  /// **'Track {position} of {total}'**
  String queuePositionInfo(int position, int total);

  /// Error message when failing to switch device
  ///
  /// In en, this message translates to:
  /// **'Failed to switch device: {error}'**
  String failedToSwitchDevice(String error);

  /// Message when device is restricted
  ///
  /// In en, this message translates to:
  /// **'Device \'{device}\' is restricted and cannot be controlled via API.'**
  String deviceRestrictedMessage(String device);

  /// No description provided for @insufficientPermissionsReauth.
  ///
  /// In en, this message translates to:
  /// **'Insufficient permissions, reauthorizing...'**
  String get insufficientPermissionsReauth;

  /// No description provided for @reauthFailedManualLogin.
  ///
  /// In en, this message translates to:
  /// **'Reauthorization failed, please login manually'**
  String get reauthFailedManualLogin;

  /// Error message for bad request
  ///
  /// In en, this message translates to:
  /// **'Bad request ({code}), please try again later or contact developer.'**
  String badRequestError(String code);

  /// No description provided for @searchLyrics.
  ///
  /// In en, this message translates to:
  /// **'Search Lyrics'**
  String get searchLyrics;

  /// No description provided for @noCurrentTrackPlaying.
  ///
  /// In en, this message translates to:
  /// **'No track currently playing'**
  String get noCurrentTrackPlaying;

  /// No description provided for @cannotGetTrackInfo.
  ///
  /// In en, this message translates to:
  /// **'Cannot get current track information'**
  String get cannotGetTrackInfo;

  /// No description provided for @lyricsSearchAppliedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Lyrics successfully searched and applied'**
  String get lyricsSearchAppliedSuccess;

  /// No description provided for @thoughts.
  ///
  /// In en, this message translates to:
  /// **'THOUGHTS'**
  String get thoughts;

  /// No description provided for @noTrack.
  ///
  /// In en, this message translates to:
  /// **'NO TRACK'**
  String get noTrack;

  /// No description provided for @noIdeasYet.
  ///
  /// In en, this message translates to:
  /// **'No ideas for this song yet.\nCome share the first idea!'**
  String get noIdeasYet;

  /// No description provided for @relatedThoughts.
  ///
  /// In en, this message translates to:
  /// **'Related Thoughts'**
  String get relatedThoughts;

  /// No description provided for @yourLibrary.
  ///
  /// In en, this message translates to:
  /// **'YOUR LIBRARY'**
  String get yourLibrary;

  /// No description provided for @errorLoadingLibrary.
  ///
  /// In en, this message translates to:
  /// **'Error loading library'**
  String get errorLoadingLibrary;

  /// No description provided for @searchResults.
  ///
  /// In en, this message translates to:
  /// **'SEARCH RESULTS'**
  String get searchResults;

  /// No description provided for @noResultsFound.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResultsFound;

  /// No description provided for @tryDifferentKeywords.
  ///
  /// In en, this message translates to:
  /// **'Try different keywords or check your spelling'**
  String get tryDifferentKeywords;

  /// No description provided for @infoLabel.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get infoLabel;

  /// No description provided for @playlistType.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get playlistType;

  /// No description provided for @albumType.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get albumType;

  /// No description provided for @songType.
  ///
  /// In en, this message translates to:
  /// **'Song'**
  String get songType;

  /// No description provided for @artistType.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get artistType;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
