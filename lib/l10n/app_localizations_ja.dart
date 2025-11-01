// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get settingsTitle => '設定';

  @override
  String get devicesTitle => 'デバイス';

  @override
  String get noDeviceFound => '利用可能なデバイスが見つからない';

  @override
  String get authorizeSpotifyButton => 'Spotifyを承認';

  @override
  String get logoutSpotifyButton => 'Spotifyからログアウト';

  @override
  String loggedInAs(String username) {
    return 'Spotify: $username';
  }

  @override
  String get nowPlayingTab => '再生中';

  @override
  String get libraryTab => 'ライブラリ';

  @override
  String get roamTab => '探索';

  @override
  String get loginSuccess => 'Spotifyでログインした';

  @override
  String get recordsTab => '記録';

  @override
  String get queueTab => 'キュー';

  @override
  String get lyricsTab => '歌詞';

  @override
  String get devicesPageTitle => 'デバイス';

  @override
  String get noDevicesFound => 'デバイスが見つからない';

  @override
  String get sonosDeviceRestriction => 'SpotifyまたはSonosアプリでこのデバイスを操作する';

  @override
  String get deviceRestricted => 'このデバイスは利用できない';

  @override
  String get privateSession => 'プライベートセッション';

  @override
  String get currentDevice => '再生中';

  @override
  String get editNote => 'メモを編集';

  @override
  String get deleteNote => 'メモを削除';

  @override
  String get cancel => 'キャンセル';

  @override
  String get confirmDelete => '削除の確認';

  @override
  String get deleteConfirmMessage => 'このメモを削除してもいい？この操作は元に戻せない。';

  @override
  String get noNotes => '追加されたメモはまだない。';

  @override
  String recordsAt(String time) {
    return '$time に記録';
  }

  @override
  String get today => '今日';

  @override
  String get yesterday => '昨日';

  @override
  String playbackFailed(String error) {
    return '再生に失敗した: $error';
  }

  @override
  String get searchHint => '曲、アルバム、アーティストを検索...';

  @override
  String get clearSearch => '検索をクリア';

  @override
  String get playToGenerateInsights => 'インサイトを生成するには音楽を再生して！';

  @override
  String get generateInsights => '洞察発見';

  @override
  String get generating => '生成中...';

  @override
  String get collapse => '折りたたむ';

  @override
  String get expand => '展開する';

  @override
  String get noInsightsGenerated => '提供された履歴からインサイトを生成できなかった。';

  @override
  String get insightsTitle => 'インサイト';

  @override
  String get inspirationsTitle => 'インスピレーション';

  @override
  String get unknownArtist => '不明なアーティスト';

  @override
  String get unknownTrack => '不明な曲';

  @override
  String failedToGenerateInsights(String error) {
    return 'インサイトの生成に失敗した: $error';
  }

  @override
  String copiedToClipboard(String type) {
    return 'クリップボードにコピーされた';
  }

  @override
  String get musicPersonality => '音楽の個性';

  @override
  String get insightsContent => 'インサイト内容';

  @override
  String get recommendedSong => 'おすすめの曲';

  @override
  String get addNote => 'メモを追加';

  @override
  String get noteHint => 'ここにメモを入力して';

  @override
  String get saveNote => 'メモを保存';

  @override
  String get noteSaved => 'メモが正常に保存された';

  @override
  String errorSavingNote(String error) {
    return 'メモの保存中にエラーが発生した: $error';
  }

  @override
  String get notesTitle => 'ノート';

  @override
  String get areYouSureDeleteNote => 'このメモを削除してもいい？';

  @override
  String get delete => '削除';

  @override
  String get noteDeleted => 'メモが削除された';

  @override
  String errorDeletingNote(String error) {
    return 'メモの削除中にエラーが発生した: $error';
  }

  @override
  String get noteUpdated => 'メモが正常に更新された';

  @override
  String errorUpdatingNote(String error) {
    return 'メモの更新中にエラーが発生した: $error';
  }

  @override
  String get lyricsFetching => '歌詞を取得中...';

  @override
  String get lyricsFound => '歌詞が見つかった。';

  @override
  String get lyricsNotFoundForTrack => 'この曲の歌詞は見つからない。';

  @override
  String lyricsFetchError(String error) {
    return '歌詞の取得中にエラーが発生した: $error';
  }

  @override
  String get lyricsTranslating => '歌詞を翻訳中...';

  @override
  String get lyricsTranslationSuccessful => '翻訳に成功した。';

  @override
  String lyricsTranslationError(String error) {
    return '歌詞の翻訳中にエラーが発生した: $error';
  }

  @override
  String get lyricsTitle => '歌詞';

  @override
  String get lyricsCopyModeTooltip => '歌詞コピーモード';

  @override
  String get lyricsTranslateTooltip => '歌詞を翻訳';

  @override
  String get lyricsToggleAutoScrollTooltip => '自動スクロールを切り替え';

  @override
  String get lyricsNotAvailable => '利用可能な歌詞はない。';

  @override
  String get lyricsLoading => '歌詞を読み込み中...';

  @override
  String get lyricsFailedToLoad => '歌詞の読み込みに失敗した。';

  @override
  String get lyricsCopyModeSnackbar => '歌詞コピー モード：単曲リピート有効、自動スクロール無効。';

  @override
  String get couldNotGetCurrentTrackId => '現在の曲のIDを取得できなかった。';

  @override
  String translationFailed(Object error) {
    return '翻訳に失敗した: $error';
  }

  @override
  String get centerCurrentLine => '現在の行を中央揃え';

  @override
  String get translateLyrics => '歌詞を翻訳';

  @override
  String get exitCopyModeResumeScroll => 'コピー モード終了＆スクロール再開';

  @override
  String get enterCopyLyricsMode => '歌詞コピー モードに入る（単曲リピート）';

  @override
  String get translationTitle => '翻訳';

  @override
  String get originalTitle => '原文';

  @override
  String get translatedByAttribution => 'Gemini 2.5 Flashによって翻訳された';

  @override
  String spiritLabel(String style) {
    return 'スピリット: $style';
  }

  @override
  String get copyToClipboard => 'クリップボードにコピー';

  @override
  String get retranslateButton => '再翻訳';

  @override
  String get retranslating => '再翻訳中...';

  @override
  String get translationStyleFaithful => '忠実';

  @override
  String get translationStyleMelodramaticPoet => 'メロドラマ詩人';

  @override
  String get translationStyleMachineClassic => '機械翻訳クラシック';

  @override
  String get translationStyleTooltipFaithful => '現在: 忠実な - タップして変更';

  @override
  String get translationStyleTooltipMelodramatic => '現在: メロドラマ詩人 - タップして変更';

  @override
  String get translationStyleTooltipMachine => '現在: 機械翻訳クラシック - タップして変更';

  @override
  String get toggleTranslationStyle => '翻訳スタイルを切り替え';

  @override
  String get showTranslation => '翻訳を表示';

  @override
  String get showOriginal => '原文を表示';

  @override
  String get closeTranslation => '閉じる';

  @override
  String get trackSaved => '曲がプレイリストに保存された';

  @override
  String errorSavingTrack(String error) {
    return '曲の保存中にエラーが発生した: $error';
  }

  @override
  String get unknownAlbum => '不明なアルバム';

  @override
  String get playlist => 'プレイリスト';

  @override
  String get unknownContext => '不明なコンテキスト';

  @override
  String get noTrackOrEmptyNote => '曲の情報が取得できないか、メモが空だ';

  @override
  String get logoutSuccess => 'Spotifyからログアウトした';

  @override
  String get operationFailed => '操作に失敗した';

  @override
  String get invalidCredentialsError =>
      '無効なSpotify API認証情報だ。クライアントIDとシークレットを確認して。';

  @override
  String get authenticationError => '認証に失敗した：無効な認証情報または権限が不足している。';

  @override
  String get tooManyRequestsError => 'リクエストが多すぎる。後でもう一度試して。';

  @override
  String loginLogoutFailed(Object error) {
    return 'ログイン/ログアウトに失敗した: $error';
  }

  @override
  String get helpAction => 'ヘルプ';

  @override
  String get setupTitle => '設定';

  @override
  String get googleAiApiKeyTitle => 'Google AI APIキー';

  @override
  String get googleAiApiKeySubtitle =>
      'Gemini翻訳のためにGoogle AI Studio APIキーを設定する';

  @override
  String get spotifyApiTitle => 'Spotify API';

  @override
  String get spotifyApiSubtitle => 'SpotifyクライアントIDとSecretを設定する';

  @override
  String get tutorialTitle => 'チュートリアル';

  @override
  String get tutorialSubtitle => '設定のチュートリアルを見る';

  @override
  String get generalTitle => '一般';

  @override
  String get translationLanguageTitle => 'Gemini言語';

  @override
  String get translationLanguageSubtitle => '翻訳とインサイトのターゲット言語を選択する';

  @override
  String get translationStyleTitle => '翻訳スタイル';

  @override
  String get translationStyleSubtitle => 'Gemini のスピリットを設定する';

  @override
  String get autoTranslateLyricsTitle => '歌詞を自動翻訳';

  @override
  String get autoTranslateLyricsSubtitle => '翻訳がないときは自動で翻訳を実行します';

  @override
  String get copyLyricsAsSingleLineTitle => '歌詞を１行でコピー';

  @override
  String get copyLyricsAsSingleLineSubtitle => 'コピー時に改行をスペースに置き換える';

  @override
  String get deepTranslationTitle => '思考→翻訳';

  @override
  String get deepTranslationSubtitle => 'Gemini の思考モードを有効にして翻訳品質を向上させる';

  @override
  String get dataManagementTitle => 'データ管理';

  @override
  String get exportDataTitle => 'データのエクスポート';

  @override
  String get exportDataSubtitle => 'すべてのデータをJSONファイルとしてエクスポートする';

  @override
  String get importDataTitle => 'データのインポート';

  @override
  String get importDataSubtitle => 'エクスポートされたJSONファイルからデータをインポートする';

  @override
  String get clearCacheTitle => 'すべてのキャッシュをクリア';

  @override
  String get clearCacheSubtitle => '歌詞と翻訳のキャッシュをクリアする';

  @override
  String get geminiApiKeyDialogTitle => 'Gemini APIキー';

  @override
  String get geminiApiKeyDialogHint => 'Gemini APIキーを入力して';

  @override
  String get cancelButton => 'キャンセル';

  @override
  String get apiKeySaved => 'Gemini APIキーが保存された';

  @override
  String get okButton => 'OK';

  @override
  String get spotifyCredentialsDialogTitle => 'Spotify API';

  @override
  String get clientIdLabel => 'クライアントID';

  @override
  String get clientSecretLabel => 'クライアントSecret';

  @override
  String get emptyCredentialsError => 'クライアントIDと Secret の両方が必要だ。';

  @override
  String get invalidClientIdError => 'クライアントIDは32文字の16進文字列である必要がある。';

  @override
  String get invalidClientSecretError => 'クライアントSecretは32文字の16進文字列である必要がある。';

  @override
  String get credentialsSaved => 'Spotify 資格情報が保存された';

  @override
  String get credentialsSaveFailed => '資格情報の保存に失敗した';

  @override
  String get languageDialogTitle => '言語を選択';

  @override
  String get languageSaved => '言語設定が保存された';

  @override
  String get translationStyleDialogTitle => '翻訳スタイルを選択';

  @override
  String get translationStyleSaved => '翻訳スタイルが保存された';

  @override
  String get exportFailed => 'エクスポートに失敗したかキャンセルされた。';

  @override
  String get importDialogTitle => 'インポートの確認';

  @override
  String get importDialogMessage =>
      'データをインポートすると、同じ識別子を持つ既存のトラックと翻訳が置き換えられ、ファイル内のすべてのレコードが追加される。この操作は元に戻せない。続行する？\n\nJSONファイルが有効であり、以前にSpotoolfyからエクスポートされたものであることを確認して。';

  @override
  String get importButton => 'データのインポート';

  @override
  String get importSuccess => 'データが正常にインポートされた！';

  @override
  String get importFailed => 'データのインポートに失敗した。';

  @override
  String get exportSuccess => 'データが正常にエクスポートされた！';

  @override
  String get clearCacheDialogTitle => 'キャッシュクリアの確認';

  @override
  String get clearCacheDialogMessage => '歌詞と翻訳のキャッシュをクリアしてもいい？この操作は元に戻せない。';

  @override
  String get clearCacheButton => 'キャッシュをクリア';

  @override
  String get clearingCache => 'キャッシュをクリアしている...';

  @override
  String get cacheCleared => 'キャッシュが正常にクリアされた！';

  @override
  String get cacheClearFailed => 'キャッシュのクリアに失敗した';

  @override
  String failedToChangeLanguage(String error) {
    return '言語の変更に失敗した: $error';
  }

  @override
  String failedToChangeStyle(String error) {
    return '翻訳スタイルの変更に失敗した: $error';
  }

  @override
  String get noteContent => 'ノート内容';

  @override
  String get saveChanges => '保存';

  @override
  String get noLyricsToTranslate => '翻訳する歌詞がない。';

  @override
  String failedToSaveTranslation(Object error) {
    return '取得した翻訳の保存に失敗した: $error';
  }

  @override
  String get failedToGetTranslation => '翻訳の取得に失敗した。';

  @override
  String get copyLyricsModeHint => '歌詞コピー モード：単曲リピート有効、自動スクロール無効。';

  @override
  String get exitCopyMode => 'コピー モード終了＆スクロール再開';

  @override
  String get enterCopyMode => '歌詞コピー モードに入る（単曲リピート）';

  @override
  String get selectLyrics => '歌詞を選択';

  @override
  String get selectLyricsTooltip => '分析または共有する歌詞部分を選択';

  @override
  String get selectAll => '全て選択';

  @override
  String get deselectAll => '全て選択解除';

  @override
  String get noLyricsSelected => 'まず歌詞を選択してください';

  @override
  String get askGemini => 'Geminiに質問';

  @override
  String get sharePoster => 'ポスターを共有';

  @override
  String get copySelected => '選択をコピー';

  @override
  String get geminiAnalysisResult => 'Gemini分析結果';

  @override
  String get lyricsTheme => 'テーマ';

  @override
  String get lyricsEmotion => '感情';

  @override
  String get lyricsMetaphor => '隠喩と象徴';

  @override
  String get lyricsInterpretation => '深い解釈';

  @override
  String get lyricsReference => '引用と典故';

  @override
  String get lyricsKeywordsExplanation => 'キーワード解説';

  @override
  String get copyAnalysis => '分析をコピー';

  @override
  String get analysisResultCopied => '分析結果がクリップボードにコピーされました';

  @override
  String selectedLyricsCopied(int count) {
    return '$count行の歌詞をコピーしました';
  }

  @override
  String posterGenerationFailed(Object error) {
    return 'ポスター生成に失敗しました: $error';
  }

  @override
  String analysisFailed(String error) {
    return '分析に失敗しました: $error';
  }

  @override
  String get noLyricsToSelect => '選択できる歌詞がない';

  @override
  String get posterLyricsLimitExceeded => 'ポスター生成には最大10行まで選択できます';

  @override
  String get multiSelectMode => '複数選択モード';

  @override
  String get tapToSelectLyrics => '歌詞行をタップして選択';

  @override
  String get appTitle => 'Spotoolfy';

  @override
  String get nowPlayingLabel => '再生中';

  @override
  String get libraryLabel => 'ライブラリ';

  @override
  String get roamLabel => '探索';

  @override
  String get tutorialButtonText => 'チュートリアル';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageSimplifiedChinese => '简体中文 (Simplified Chinese)';

  @override
  String get languageTraditionalChinese => '繁體中文 (Traditional Chinese)';

  @override
  String get languageJapanese => '日本語 (Japanese)';

  @override
  String get collapseTooltip => '折りたたむ';

  @override
  String get expandTooltip => '展開する';

  @override
  String get incompleteRecordError => '続行できない：記録情報が不完全';

  @override
  String get optionsTitle => 'オプション';

  @override
  String playFromTimestamp(String timestamp) {
    return '$timestamp から再生';
  }

  @override
  String get editNoteTitle => 'メモを編集';

  @override
  String get ratedStatus => '評価済み';

  @override
  String get noItemsFound => '項目が見つからない';

  @override
  String get cannotCreateSpotifyLink => 'Spotify リンクを作成できない';

  @override
  String get cannotOpenSpotify => 'Spotify を開けない';

  @override
  String failedToOpenSpotify(String error) {
    return 'Spotify を開くのに失敗した: $error';
  }

  @override
  String get playlistsTab => 'プレイリスト';

  @override
  String get albumsTab => 'アルバム';

  @override
  String get tryAgainButton => '再試行';

  @override
  String get playTrackToSeeThoughts => 'トラックを再生して思考を見る。';

  @override
  String get copyButtonText => 'コピー';

  @override
  String get posterButtonLabel => 'ポスター';

  @override
  String get noteButtonLabel => 'メモ';

  @override
  String get lyricsAnalysisTitle => '歌詞分析';

  @override
  String get regenerateAnalysisTooltip => '分析を再生成';

  @override
  String get copyAllAnalysisTooltip => 'すべての分析をコピー';

  @override
  String get geminiGrounding => 'Gemini が考えている...';

  @override
  String get retryButton => '再試行';

  @override
  String get noAnalysisResults => '分析結果がない';

  @override
  String get noDeepAnalysisContent => 'この歌詞部分には深い分析内容がない';

  @override
  String get simpleContentExplanation =>
      'これは歌詞の内容が比較的単純であるか、明らかな隠喩、引用、その他の文学的手法がないためかもしれない';

  @override
  String get reanalyzeButton => '再分析';

  @override
  String get onlyFoundDimensionsInfo => 'これらの歌詞で見つかった分析次元のみ表示';

  @override
  String get songInfoRegeneratedMessage => '楽曲情報が再生成された';

  @override
  String get songInformationTitle => 'INFORMATION';

  @override
  String get regenerateTooltip => '再生成';

  @override
  String get noSongInfoAvailable => '利用可能な楽曲情報がない';

  @override
  String get generateAIContent => 'AI楽曲解析と背景情報を生成';

  @override
  String get generatingAIContent => '生成中...';

  @override
  String get deleteAIContent => 'AI解析コンテンツを削除';

  @override
  String get generatedByGemini => 'Gemini 2.5 Flash によって生成';

  @override
  String get poweredByGoogleSearch => 'Google 検索グラウンディングによる';

  @override
  String get creationTimeTitle => '作成時間';

  @override
  String get creationLocationTitle => '作成場所';

  @override
  String get lyricistTitle => '作詞';

  @override
  String get composerTitle => '作曲';

  @override
  String get producerTitle => 'プロデューサー';

  @override
  String get songAnalysisTitle => '楽曲分析';

  @override
  String get selectArtistTitle => 'アーティストを選択';

  @override
  String get backToLibraryTooltip => 'ライブラリに戻る';

  @override
  String get appWatermark => 'Spotoolfy';

  @override
  String get loadingAnalyzing => 'AI で歌詞を分析している...';

  @override
  String get loadingDecoding => '音楽の謎を解読している...';

  @override
  String get loadingSearching => '洞察を検索している...';

  @override
  String get loadingThinking => 'Gemini が考えている...';

  @override
  String get loadingGenerating => '分析を生成している...';

  @override
  String loadingChatting(String artist) {
    return '$artist とチャットしている...';
  }

  @override
  String get loadingDiscovering => '隠された意味を発見している...';

  @override
  String get loadingExploring => '歌詞の深さを探っている...';

  @override
  String get loadingUnraveling => '詩的な層を解きほぐしている...';

  @override
  String get loadingConnecting => '感情の糸をつなげている...';

  @override
  String get currentQueueEmpty => '現在のキューは空';

  @override
  String get queueUpNext => '次に再生';

  @override
  String get noQueueItems => 'upcoming tracks がない';

  @override
  String queuePositionInfo(int position, int total) {
    return '$total 曲中 $position 番目';
  }

  @override
  String failedToSwitchDevice(String error) {
    return 'デバイス切り替えに失敗した: $error';
  }

  @override
  String deviceRestrictedMessage(String device) {
    return 'デバイス \'$device\' は制限されており、API経由で制御できない。';
  }

  @override
  String get insufficientPermissionsReauth => '権限が不足しています、再認証中...';

  @override
  String get reauthFailedManualLogin => '再認証に失敗しました、手動でログインしてください';

  @override
  String badRequestError(String code) {
    return 'リクエストエラー ($code)、後でもう一度試すか開発者に連絡してください。';
  }

  @override
  String get searchLyrics => '歌詞を検索';

  @override
  String get noCurrentTrackPlaying => '現在再生中の曲がない';

  @override
  String get cannotGetTrackInfo => '現在の曲情報を取得できない';

  @override
  String get lyricsSearchAppliedSuccess => '歌詞が正常に検索され適用された';

  @override
  String get thoughts => '思考';

  @override
  String get noTrack => 'トラックなし';

  @override
  String get noIdeasYet => 'この曲についてのアイデアはまだありません。\n最初のアイデアをシェアしてください！';

  @override
  String get relatedThoughts => '関連思考';

  @override
  String get yourLibrary => 'あなたのライブラリ';

  @override
  String get errorLoadingLibrary => 'ライブラリの読み込みエラー';

  @override
  String get searchResults => '検索結果';

  @override
  String get noResultsFound => '結果が見つかりません';

  @override
  String get tryDifferentKeywords => '別のキーワードを試すか、スペルを確認してください';

  @override
  String get infoLabel => '情報';

  @override
  String get playlistType => 'プレイリスト';

  @override
  String get albumType => 'アルバム';

  @override
  String get songType => '曲';

  @override
  String get artistType => 'アーティスト';

  @override
  String get daysAgo => '日前';

  @override
  String get hoursAgo => '時間前';

  @override
  String get minsAgo => '分前';

  @override
  String get secsAgo => '秒前';

  @override
  String failedToPlayAlbum(String error) {
    return 'アルバムの再生に失敗した: $error';
  }

  @override
  String get rateAtLeastOneSongForPoster => 'ポスターを生成する前に少なくとも1曲を評価して';

  @override
  String failedToSharePoster(String error) {
    return '評価ポスターの共有に失敗した: $error';
  }

  @override
  String get cannotPlayMissingTrackLink => '再生できない: トラックリンクがない';

  @override
  String failedToPlaySong(String error) {
    return '曲の再生に失敗した: $error';
  }

  @override
  String failedToSaveRating(String error) {
    return '評価の保存に失敗した: $error';
  }

  @override
  String get albumDetails => 'アルバム詳細';

  @override
  String get titleCopied => 'タイトルがコピーされた';

  @override
  String get playAlbum => '再生';

  @override
  String get rateAtLeastOneSongFirst => 'ポスターを共有する前にいくつかの曲を評価して';

  @override
  String get shareAlbumRatingPoster => 'アルバム評価ポスターを共有';

  @override
  String get hideQuickRating => 'クイック評価を隠す';

  @override
  String get showQuickRating => 'クイック評価を表示';

  @override
  String get currently => '現在';

  @override
  String get savingChanges => '保存中…';

  @override
  String get saveAllChanges => 'すべての変更を保存';

  @override
  String get generatingTooltip => '生成中…';

  @override
  String get generateAlbumInsights => 'アルバムインサイトを生成';

  @override
  String get collapseInsights => 'インサイトを折りたたむ';

  @override
  String get expandInsights => 'インサイトを展開';

  @override
  String get noSongsRatedYet => 'まだ評価された曲がない';

  @override
  String basedOnRatedSongs(int rated, int total) {
    return '$rated/$total 曲に基づく';
  }

  @override
  String failedToGenerateAlbumInsights(String error) {
    return 'インサイトの生成に失敗した: $error';
  }

  @override
  String failedToLoadCache(String error) {
    return 'キャッシュの読み込みに失敗した: $error';
  }

  @override
  String get generatingAlbumInsights => 'アルバムインサイトを生成している…';

  @override
  String get noInsightsAvailableTapToGenerate =>
      '利用可能なインサイトがない。上のボタンをタップして生成して。';

  @override
  String get insightsEmptyRetryGenerate => 'インサイトが空だ、再生成してみて。';

  @override
  String insightsGeneratedDaysAgo(int days) {
    return '$days 日前にインサイトが生成された';
  }

  @override
  String insightsGeneratedHoursAgo(int hours) {
    return '$hours 時間前にインサイトが生成された';
  }

  @override
  String insightsGeneratedMinutesAgo(int minutes) {
    return '$minutes 分前にインサイトが生成された';
  }

  @override
  String get insightsJustGenerated => 'インサイトがたった今生成された';

  @override
  String get refreshAlbum => 'アルバムを更新';

  @override
  String get failedToLoadAlbum => 'アルバムの読み込みに失敗した';

  @override
  String get unknownError => '不明なエラー';

  @override
  String get unratedStatus => '未評価';

  @override
  String get justNow => 'たった今';

  @override
  String minutesAgoShort(int minutes) {
    return '$minutes分前';
  }

  @override
  String hoursAgoShort(int hours) {
    return '$hours時間前';
  }

  @override
  String daysAgoShort(int days) {
    return '$days日前';
  }

  @override
  String totalTracksCount(int count) {
    return '全$count曲';
  }

  @override
  String failedToPlayPlaylist(String error) {
    return 'プレイリストの再生に失敗した: $error';
  }

  @override
  String get playPlaylist => 'プレイリストを再生';

  @override
  String get playlistDetails => 'プレイリスト詳細';

  @override
  String get refreshPlaylist => 'プレイリストを更新';

  @override
  String createdBy(String owner) {
    return '$owner が作成';
  }

  @override
  String playlistTrackCount(int count) {
    return '全 $count 曲';
  }

  @override
  String get failedToLoadPlaylist => 'プレイリストの読み込みに失敗した';

  @override
  String get playlistTracksLabel => 'プレイリスト曲';

  @override
  String get deviceOperationNotSupported =>
      'このデバイスはこの操作をサポートしていないか制限されている。他のデバイスで音楽を再生してみるか、アカウントタイプを確認して。';

  @override
  String shareAlbumMessage(
      String albumName, String artist, String score, int rated, int total) {
    return 'Spotoolfy で《$albumName》（$artist）に $score を付けた、$rated/$total 曲を評価した。';
  }

  @override
  String get noRating => '評価なし';

  @override
  String get retry => '再試行';

  @override
  String get unknownTrackName => '不明な曲';

  @override
  String get albumInsightReadyStatus => 'アルバムインサイトが準備できた';

  @override
  String get clickToGenerateAlbumInsights => '右のボタンをクリックしてこのアルバムのインサイトを生成';

  @override
  String get failedToGenerateAlbumInsightsStatus => 'アルバムインサイトの生成に失敗した';

  @override
  String get providerQQMusic => 'QQ音楽';

  @override
  String get providerLRCLIB => 'LRCLIB';

  @override
  String get providerNetease => '網易雲音楽';

  @override
  String get playingFrom => '再生元';

  @override
  String get playFromAlbum => 'アルバムから再生';

  @override
  String get playFromPlaylist => 'プレイリストから再生';

  @override
  String get sharingStatus => '共有中...';

  @override
  String get shareButton => '共有';
}
