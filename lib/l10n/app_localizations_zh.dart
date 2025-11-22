// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get settingsTitle => '设置';

  @override
  String get devicesTitle => '设备';

  @override
  String get noDeviceFound => '没有找到可用设备';

  @override
  String get authorizeSpotifyButton => '授权 Spotify';

  @override
  String get logoutSpotifyButton => '登出 Spotify';

  @override
  String loggedInAs(String username) {
    return 'Spotify: $username';
  }

  @override
  String get nowPlayingTab => '播放中';

  @override
  String get libraryTab => '资料库';

  @override
  String get roamTab => '漫游';

  @override
  String get loginSuccess => '已使用 Spotify 登录';

  @override
  String get recordsTab => '记录';

  @override
  String get queueTab => '队列';

  @override
  String get lyricsTab => '歌词';

  @override
  String get devicesPageTitle => '设备';

  @override
  String get noDevicesFound => '没有找到可用设备';

  @override
  String get sonosDeviceRestriction => '请使用 Spotify 或 Sonos 应用控制此设备';

  @override
  String get deviceRestricted => '此设备不可用';

  @override
  String get privateSession => '私人会话';

  @override
  String get currentDevice => '当前';

  @override
  String get editNote => '编辑笔记';

  @override
  String get deleteNote => '删除笔记';

  @override
  String get cancel => '取消';

  @override
  String get confirmDelete => '确认删除';

  @override
  String get deleteConfirmMessage => '您确定要删除这条笔记吗？此操作无法撤销。';

  @override
  String get noNotes => '还没有添加任何笔记。';

  @override
  String recordsAt(String time) {
    return '记录于 $time';
  }

  @override
  String get today => '今天';

  @override
  String get yesterday => '昨天';

  @override
  String playbackFailed(String error) {
    return '播放失败: $error';
  }

  @override
  String get searchHint => '搜索歌曲、专辑、艺术家...';

  @override
  String get clearSearch => '清除搜索';

  @override
  String get playToGenerateInsights => '播放一些音乐以生成洞察。';

  @override
  String get generateInsights => '生成洞察';

  @override
  String get generating => '生成中...';

  @override
  String get collapse => '收起';

  @override
  String get expand => '展开';

  @override
  String get noInsightsGenerated => '无法从提供的历史记录生成洞察。';

  @override
  String get insightsTitle => '洞察';

  @override
  String get inspirationsTitle => '灵感';

  @override
  String get unknownArtist => '未知艺术家';

  @override
  String get unknownTrack => '未知歌曲';

  @override
  String failedToGenerateInsights(String error) {
    return '生成洞察失败: $error';
  }

  @override
  String copiedToClipboard(String type) {
    return '已复制到剪贴板';
  }

  @override
  String get musicPersonality => '音乐人格';

  @override
  String get insightsContent => '洞察内容';

  @override
  String get recommendedSong => '推荐歌曲';

  @override
  String get addNote => '添加笔记';

  @override
  String get noteHint => '在此输入你的笔记';

  @override
  String get saveNote => '保存笔记';

  @override
  String get noteSaved => '笔记保存成功';

  @override
  String errorSavingNote(String error) {
    return '保存笔记时出错: $error';
  }

  @override
  String get notesTitle => '笔记';

  @override
  String get areYouSureDeleteNote => '确定要删除这条笔记吗？';

  @override
  String get delete => '删除';

  @override
  String get noteDeleted => '笔记已删除';

  @override
  String errorDeletingNote(String error) {
    return '删除笔记时出错: $error';
  }

  @override
  String get noteUpdated => '笔记更新成功';

  @override
  String errorUpdatingNote(String error) {
    return '更新笔记时出错: $error';
  }

  @override
  String get lyricsFetching => '正在获取歌词...';

  @override
  String get lyricsFound => '已找到歌词。';

  @override
  String get lyricsNotFoundForTrack => '未找到此歌曲的歌词。';

  @override
  String lyricsFetchError(String error) {
    return '获取歌词时出错: $error';
  }

  @override
  String get lyricsTranslating => '正在翻译歌词...';

  @override
  String get lyricsTranslationSuccessful => '翻译成功。';

  @override
  String lyricsTranslationError(String error) {
    return '翻译歌词时出错: $error';
  }

  @override
  String get lyricsTitle => '歌词';

  @override
  String get lyricsCopyModeTooltip => '歌词复制模式';

  @override
  String get lyricsTranslateTooltip => '翻译歌词';

  @override
  String get lyricsToggleAutoScrollTooltip => '切换自动滚动';

  @override
  String get lyricsNotAvailable => '没有可用的歌词。';

  @override
  String get lyricsLoading => '正在加载歌词...';

  @override
  String get lyricsFailedToLoad => '加载歌词失败。';

  @override
  String get lyricsCopyModeSnackbar => '歌词复制模式：单曲重复已激活，自动滚动已禁用。';

  @override
  String get couldNotGetCurrentTrackId => '无法获取当前歌曲 ID。';

  @override
  String translationFailed(Object error) {
    return '翻译失败: $error';
  }

  @override
  String get centerCurrentLine => '居中当前行';

  @override
  String get translateLyrics => '翻译歌词';

  @override
  String get exitCopyModeResumeScroll => '退出复制模式并恢复滚动';

  @override
  String get enterCopyLyricsMode => '进入歌词复制模式（单曲重复）';

  @override
  String get translationTitle => '翻译';

  @override
  String get originalTitle => '原文';

  @override
  String get translatedByAttribution => '由 Gemini 2.5 Flash 翻译';

  @override
  String spiritLabel(String style) {
    return '灵魂: $style';
  }

  @override
  String get copyToClipboard => '复制到剪贴板';

  @override
  String get retranslateButton => '重新翻译';

  @override
  String get retranslating => '正在重新翻译...';

  @override
  String get translationStyleFaithful => '忠实';

  @override
  String get translationStyleMelodramaticPoet => '忧郁诗人';

  @override
  String get translationStyleMachineClassic => '机器经典';

  @override
  String get translationStyleTooltipFaithful => '当前：忠实 - 点击更改';

  @override
  String get translationStyleTooltipMelodramatic => '当前：忧郁诗人 - 点击更改';

  @override
  String get translationStyleTooltipMachine => '当前：机器 - 点击更改';

  @override
  String get toggleTranslationStyle => '切换翻译风格';

  @override
  String get showTranslation => '显示翻译';

  @override
  String get showOriginal => '显示原文';

  @override
  String get closeTranslation => '关闭';

  @override
  String get trackSaved => '歌曲已保存到播放列表';

  @override
  String errorSavingTrack(String error) {
    return '保存歌曲时出错: $error';
  }

  @override
  String get unknownAlbum => '未知专辑';

  @override
  String get playlist => '播放列表';

  @override
  String get unknownContext => '未知上下文';

  @override
  String get noTrackOrEmptyNote => '无法获取歌曲信息或笔记为空';

  @override
  String get logoutSuccess => '已登出 Spotify';

  @override
  String get operationFailed => '操作失败';

  @override
  String get invalidCredentialsError => '无效的 Spotify API 凭据。请检查您的客户端 ID 和密钥。';

  @override
  String get authenticationError => '身份验证失败：凭据无效或权限不足。';

  @override
  String get tooManyRequestsError => '请求过多。请稍后再试。';

  @override
  String loginLogoutFailed(Object error) {
    return '登录/注销失败: $error';
  }

  @override
  String get helpAction => '帮助';

  @override
  String get setupTitle => '设置';

  @override
  String get googleAiApiKeyTitle => 'Google AI API 密钥';

  @override
  String get googleAiApiKeySubtitle =>
      '设置您的 Google AI Studio API 密钥以进行 Gemini 翻译';

  @override
  String get spotifyApiTitle => 'Spotify API';

  @override
  String get spotifyApiSubtitle => '设置 Spotify 客户端 ID 和 Secret';

  @override
  String get tutorialTitle => '教程';

  @override
  String get tutorialSubtitle => '查看设置教程';

  @override
  String get generalTitle => '通用';

  @override
  String get translationLanguageTitle => 'Gemini 语言';

  @override
  String get translationLanguageSubtitle => '选择翻译和洞察的目标语言';

  @override
  String get translationStyleTitle => '翻译风格';

  @override
  String get translationStyleSubtitle => '设置 Gemini 的灵魂';

  @override
  String get autoTranslateLyricsTitle => '自动翻译歌词';

  @override
  String get autoTranslateLyricsSubtitle => '当歌词没有翻译时自动开始翻译';

  @override
  String get copyLyricsAsSingleLineTitle => '将歌词复制为单行';

  @override
  String get copyLyricsAsSingleLineSubtitle => '复制时将换行符替换为空格';

  @override
  String get dataManagementTitle => '数据管理';

  @override
  String get exportDataTitle => '导出数据';

  @override
  String get exportDataSubtitle => '将所有数据导出为 JSON 文件';

  @override
  String get importDataTitle => '导入数据';

  @override
  String get importDataSubtitle => '从导出的 JSON 文件导入数据';

  @override
  String get clearCacheTitle => '清除所有缓存';

  @override
  String get clearCacheSubtitle => '清除歌词和翻译缓存';

  @override
  String get geminiApiKeyDialogTitle => 'Gemini API 密钥';

  @override
  String get geminiApiKeyDialogHint => '输入您的 Gemini API 密钥';

  @override
  String get cancelButton => '取消';

  @override
  String get apiKeySaved => 'Gemini API 密钥已保存';

  @override
  String get okButton => '确定';

  @override
  String get spotifyCredentialsDialogTitle => 'Spotify API';

  @override
  String get clientIdLabel => '客户端 ID';

  @override
  String get clientSecretLabel => '客户端 Secret';

  @override
  String get emptyCredentialsError => '客户端 ID 和 Secret 均不能为空。';

  @override
  String get invalidClientIdError => '客户端 ID 必须是 32 位的十六进制字符串。';

  @override
  String get invalidClientSecretError => '客户端 Secret 必须是 32 位的十六进制字符串。';

  @override
  String get credentialsSaved => 'Spotify 凭证已保存';

  @override
  String get credentialsSaveFailed => '保存凭证失败';

  @override
  String get languageDialogTitle => '选择语言';

  @override
  String get languageSaved => '语言设置已保存';

  @override
  String get translationStyleDialogTitle => '选择翻译风格';

  @override
  String get translationStyleSaved => '翻译风格已保存';

  @override
  String get exportFailed => '导出失败或已取消。';

  @override
  String get importDialogTitle => '确认导入';

  @override
  String get importDialogMessage =>
      '导入数据将替换具有相同标识符的现有曲目和翻译，并添加文件中的所有记录。此操作无法撤销。您确定要继续吗？\n\n确保 JSON 文件有效且之前是从 Spotoolfy 导出的。';

  @override
  String get importButton => '导入数据';

  @override
  String get importSuccess => '数据导入成功！';

  @override
  String get importFailed => '导入数据失败。';

  @override
  String get exportSuccess => '数据导出成功！';

  @override
  String get clearCacheDialogTitle => '确认清除缓存';

  @override
  String get clearCacheDialogMessage => '确定要清除歌词和翻译缓存吗？此操作无法撤销。';

  @override
  String get clearCacheButton => '清除缓存';

  @override
  String get clearingCache => '正在清除缓存...';

  @override
  String get cacheCleared => '缓存清除成功。';

  @override
  String get cacheClearFailed => '清除缓存失败。';

  @override
  String failedToChangeLanguage(String error) {
    return '更改语言失败: $error';
  }

  @override
  String failedToChangeStyle(String error) {
    return '更改翻译风格失败: $error';
  }

  @override
  String get noteContent => '笔记内容';

  @override
  String get saveChanges => '保存';

  @override
  String get noLyricsToTranslate => '没有可翻译的歌词。';

  @override
  String failedToSaveTranslation(Object error) {
    return '保存获取的翻译失败: $error';
  }

  @override
  String get failedToGetTranslation => '获取翻译失败。';

  @override
  String get copyLyricsModeHint => '歌词复制模式：单曲重复已激活，自动滚动已禁用。';

  @override
  String get exitCopyMode => '退出复制模式并恢复滚动';

  @override
  String get enterCopyMode => '进入歌词复制模式（单曲重复）';

  @override
  String get selectLyrics => '选择歌词';

  @override
  String get selectLyricsTooltip => '选择歌词片段进行分析或分享';

  @override
  String get selectAll => '全选';

  @override
  String get deselectAll => '取消全选';

  @override
  String get noLyricsSelected => '请先选择一些歌词';

  @override
  String get askGemini => '问 Gemini';

  @override
  String get sharePoster => '分享海报';

  @override
  String get copySelected => '复制选中';

  @override
  String get geminiAnalysisResult => 'Gemini 分析结果';

  @override
  String get lyricsTheme => '主题';

  @override
  String get lyricsEmotion => '情感';

  @override
  String get lyricsMetaphor => '隐喻和象征';

  @override
  String get lyricsInterpretation => '深度解读';

  @override
  String get lyricsReference => '引用与典故';

  @override
  String get lyricsKeywordsExplanation => '关键词解释';

  @override
  String get copyAnalysis => '复制分析';

  @override
  String get analysisResultCopied => '分析结果已复制到剪贴板';

  @override
  String selectedLyricsCopied(int count) {
    return '已复制 $count 行歌词';
  }

  @override
  String posterGenerationFailed(Object error) {
    return '生成海报失败: $error';
  }

  @override
  String analysisFailed(String error) {
    return '分析失败: $error';
  }

  @override
  String get noLyricsToSelect => '没有可选择的歌词';

  @override
  String get posterLyricsLimitExceeded => '最多只能选择10行歌词生成海报';

  @override
  String get multiSelectMode => '多选模式';

  @override
  String get tapToSelectLyrics => '轻点歌词行以选中';

  @override
  String get appTitle => 'Spotoolfy';

  @override
  String get nowPlayingLabel => '播放中';

  @override
  String get libraryLabel => '资料库';

  @override
  String get roamLabel => '漫游';

  @override
  String get tutorialButtonText => '教程';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageSimplifiedChinese => '简体中文 (Simplified Chinese)';

  @override
  String get languageTraditionalChinese => '繁體中文 (Traditional Chinese)';

  @override
  String get languageJapanese => '日本語 (Japanese)';

  @override
  String get collapseTooltip => '收起';

  @override
  String get expandTooltip => '展开';

  @override
  String get incompleteRecordError => '无法继续：记录信息不完整';

  @override
  String get optionsTitle => '选项';

  @override
  String playFromTimestamp(String timestamp) {
    return '从 $timestamp 播放';
  }

  @override
  String get editNoteTitle => '编辑笔记';

  @override
  String get ratedStatus => '已评分';

  @override
  String get noItemsFound => '未找到项目';

  @override
  String get cannotCreateSpotifyLink => '无法创建 Spotify 链接';

  @override
  String get cannotOpenSpotify => '无法打开 Spotify';

  @override
  String failedToOpenSpotify(String error) {
    return '打开 Spotify 失败: $error';
  }

  @override
  String get playlistsTab => '播放列表';

  @override
  String get albumsTab => '专辑';

  @override
  String get tryAgainButton => '重试';

  @override
  String get playTrackToSeeThoughts => '播放歌曲以查看想法。';

  @override
  String get copyButtonText => '复制';

  @override
  String get posterButtonLabel => '海报';

  @override
  String get noteButtonLabel => '笔记';

  @override
  String get lyricsAnalysisTitle => '歌词分析';

  @override
  String get regenerateAnalysisTooltip => '重新生成分析';

  @override
  String get copyAllAnalysisTooltip => '复制所有分析';

  @override
  String get geminiGrounding => 'Gemini 正在思考...';

  @override
  String get retryButton => '重试';

  @override
  String get noAnalysisResults => '没有分析结果';

  @override
  String get noDeepAnalysisContent => '该歌词片段暂无深度分析内容';

  @override
  String get simpleContentExplanation => '这可能是因为歌词内容相对简单，或没有明显的隐喻、引用等文学手法';

  @override
  String get reanalyzeButton => '重新分析';

  @override
  String get onlyFoundDimensionsInfo => '只显示在该歌词中发现的分析维度';

  @override
  String get songInfoRegeneratedMessage => '歌曲信息已重新生成';

  @override
  String get songInformationTitle => 'INFORMATION';

  @override
  String get regenerateTooltip => '重新生成';

  @override
  String get noSongInfoAvailable => '无可用歌曲信息';

  @override
  String get generateAIContent => '点击生成歌曲背景信息和音乐解析';

  @override
  String get generatingAIContent => '正在生成中...';

  @override
  String get deleteAIContent => '点击删除AI分析内容';

  @override
  String get generatedByGemini => '由 Gemini 2.5 Flash 生成';

  @override
  String get poweredByGoogleSearch => '由 Google 搜索基础提供支持';

  @override
  String get creationTimeTitle => '创作时间';

  @override
  String get creationLocationTitle => '创作地点';

  @override
  String get lyricistTitle => '作词';

  @override
  String get composerTitle => '作曲';

  @override
  String get producerTitle => '制作人';

  @override
  String get songAnalysisTitle => '歌曲分析';

  @override
  String get selectArtistTitle => '选择艺术家';

  @override
  String get backToLibraryTooltip => '返回资料库';

  @override
  String get appWatermark => 'Spotoolfy';

  @override
  String get loadingAnalyzing => '正在用 AI 分析歌词...';

  @override
  String get loadingDecoding => '正在解码音乐奥秘...';

  @override
  String get loadingSearching => '正在搜索洞察...';

  @override
  String get loadingThinking => 'Gemini 正在思考...';

  @override
  String get loadingGenerating => '正在生成分析...';

  @override
  String loadingChatting(String artist) {
    return '正在与 $artist 对话...';
  }

  @override
  String get loadingDiscovering => '正在发现隐藏的含义...';

  @override
  String get loadingExploring => '正在探索歌词深度...';

  @override
  String get loadingUnraveling => '正在揭开诗意层次...';

  @override
  String get loadingConnecting => '正在连接情感线索...';

  @override
  String get currentQueueEmpty => '当前队列为空';

  @override
  String get queueUpNext => '即将播放';

  @override
  String get noQueueItems => '没有即将播放的曲目';

  @override
  String queuePositionInfo(int position, int total) {
    return '第 $position 首，共 $total 首';
  }

  @override
  String failedToSwitchDevice(String error) {
    return '切换设备失败: $error';
  }

  @override
  String deviceRestrictedMessage(String device) {
    return '设备 \'$device\' 受限，无法通过API控制。';
  }

  @override
  String get insufficientPermissionsReauth => '权限范围不足，正在重新获取完整授权...';

  @override
  String get reauthFailedManualLogin => '重新获取授权失败，请手动重新登录';

  @override
  String badRequestError(String code) {
    return '请求格式错误 ($code)，请稍后重试或联系开发者。';
  }

  @override
  String get searchLyrics => '搜索歌词';

  @override
  String get noCurrentTrackPlaying => '没有正在播放的歌曲';

  @override
  String get cannotGetTrackInfo => '无法获取当前歌曲信息';

  @override
  String get lyricsSearchAppliedSuccess => '歌词已成功搜索并应用';

  @override
  String get thoughts => '想法';

  @override
  String get noTrack => '无音轨';

  @override
  String get noIdeasYet => '暂无关于这首歌的想法。\n来分享第一个想法吧！';

  @override
  String get relatedThoughts => '相关想法';

  @override
  String get yourLibrary => '您的资料库';

  @override
  String get errorLoadingLibrary => '加载资料库时出错';

  @override
  String get searchResults => '搜索结果';

  @override
  String get noResultsFound => '未找到结果';

  @override
  String get tryDifferentKeywords => '请尝试不同的关键词或检查拼写';

  @override
  String get infoLabel => '信息';

  @override
  String get playlistType => '播放列表';

  @override
  String get albumType => '专辑';

  @override
  String get songType => '歌曲';

  @override
  String get artistType => '艺术家';

  @override
  String get daysAgo => '天前';

  @override
  String get hoursAgo => '小时前';

  @override
  String get minsAgo => '分钟前';

  @override
  String get secsAgo => '秒前';

  @override
  String failedToPlayAlbum(String error) {
    return '播放专辑失败：$error';
  }

  @override
  String get rateAtLeastOneSongForPoster => '至少先为一首歌曲打分才能生成海报';

  @override
  String failedToSharePoster(String error) {
    return '分享评分海报失败：$error';
  }

  @override
  String get cannotPlayMissingTrackLink => '无法播放：缺少歌曲链接';

  @override
  String failedToPlaySong(String error) {
    return '播放歌曲失败：$error';
  }

  @override
  String failedToSaveRating(String error) {
    return '保存评分失败：$error';
  }

  @override
  String get albumDetails => '专辑详情';

  @override
  String get titleCopied => '标题已复制';

  @override
  String get playAlbum => '播放';

  @override
  String get rateAtLeastOneSongFirst => '先给几首歌打分后再分享海报';

  @override
  String get shareAlbumRatingPoster => '分享专辑评分海报';

  @override
  String get hideQuickRating => '隐藏快捷评分';

  @override
  String get showQuickRating => '显示快捷评分';

  @override
  String get currently => '目前';

  @override
  String get savingChanges => '保存中…';

  @override
  String get saveAllChanges => '保存全部修改';

  @override
  String get generatingTooltip => '生成中…';

  @override
  String get generateAlbumInsights => '生成专辑洞察';

  @override
  String get collapseInsights => '收起洞察';

  @override
  String get expandInsights => '展开洞察';

  @override
  String get noSongsRatedYet => '还没有歌曲被评分';

  @override
  String basedOnRatedSongs(int rated, int total) {
    return '基于 $rated/$total 首歌曲';
  }

  @override
  String failedToGenerateAlbumInsights(String error) {
    return '生成洞察失败：$error';
  }

  @override
  String failedToLoadCache(String error) {
    return '读取缓存失败：$error';
  }

  @override
  String get generatingAlbumInsights => '正在生成专辑洞察…';

  @override
  String get noInsightsAvailableTapToGenerate => '暂无可用洞察。点击上方按钮生成一次吧。';

  @override
  String get insightsEmptyRetryGenerate => '洞察结果空空如也，试着重新生成一次。';

  @override
  String insightsGeneratedDaysAgo(int days) {
    return '洞察生成于 $days 天前';
  }

  @override
  String insightsGeneratedHoursAgo(int hours) {
    return '洞察生成于 $hours 小时前';
  }

  @override
  String insightsGeneratedMinutesAgo(int minutes) {
    return '洞察生成于 $minutes 分钟前';
  }

  @override
  String get insightsJustGenerated => '洞察刚刚生成';

  @override
  String get refreshAlbum => '刷新专辑';

  @override
  String get failedToLoadAlbum => '加载专辑失败';

  @override
  String get unknownError => '未知错误';

  @override
  String get unratedStatus => '未评分';

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgoShort(int minutes) {
    return '$minutes分钟前';
  }

  @override
  String hoursAgoShort(int hours) {
    return '$hours小时前';
  }

  @override
  String daysAgoShort(int days) {
    return '$days天前';
  }

  @override
  String totalTracksCount(int count) {
    return '共$count首曲目';
  }

  @override
  String failedToPlayPlaylist(String error) {
    return '播放播放列表失败：$error';
  }

  @override
  String get playPlaylist => '播放播放列表';

  @override
  String get playlistDetails => '播放列表详情';

  @override
  String get refreshPlaylist => '刷新播放列表';

  @override
  String createdBy(String owner) {
    return '由 $owner 创建';
  }

  @override
  String playlistTrackCount(int count) {
    return '共 $count 首曲目';
  }

  @override
  String get failedToLoadPlaylist => '加载播放列表失败';

  @override
  String get playlistTracksLabel => '歌单曲目';

  @override
  String get deviceOperationNotSupported =>
      '当前设备不支持此操作或受限。请尝试在其他设备上播放音乐，或检查您的账户类型。';

  @override
  String shareAlbumMessage(
      String albumName, String artist, String score, int rated, int total) {
    return '我在 Spotoolfy 给《$albumName》（$artist）打出了 $score 分，已评分 $rated/$total 首歌曲。';
  }

  @override
  String get noRating => '暂无评分';

  @override
  String get retry => '重试';

  @override
  String get unknownTrackName => '未知曲目';

  @override
  String get albumInsightReadyStatus => '专辑洞察已准备好';

  @override
  String get clickToGenerateAlbumInsights => '点击右侧按钮生成这张专辑的洞察';

  @override
  String get failedToGenerateAlbumInsightsStatus => '生成专辑洞察失败';

  @override
  String get providerQQMusic => 'QQ音乐';

  @override
  String get providerLRCLIB => 'LRCLIB';

  @override
  String get providerNetease => '网易云音乐';

  @override
  String get playingFrom => '播放自';

  @override
  String get playFromAlbum => '播放自专辑';

  @override
  String get playFromPlaylist => '播放自播放列表';

  @override
  String get sharingStatus => '分享中...';

  @override
  String get shareButton => '分享';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get settingsTitle => '設定';

  @override
  String get devicesTitle => '裝置';

  @override
  String get noDeviceFound => '找不到可用裝置';

  @override
  String get authorizeSpotifyButton => '授權 Spotify';

  @override
  String get logoutSpotifyButton => '登出 Spotify';

  @override
  String loggedInAs(String username) {
    return 'Spotify: $username';
  }

  @override
  String get nowPlayingTab => '播放中';

  @override
  String get libraryTab => '音樂庫';

  @override
  String get roamTab => '探索';

  @override
  String get loginSuccess => '已使用 Spotify 登入';

  @override
  String get recordsTab => '紀錄';

  @override
  String get queueTab => '佇列';

  @override
  String get lyricsTab => '歌詞';

  @override
  String get devicesPageTitle => '裝置';

  @override
  String get noDevicesFound => '沒有找到可用裝置';

  @override
  String get sonosDeviceRestriction => '請使用 Spotify 或 Sonos 應用程式控制此裝置';

  @override
  String get deviceRestricted => '此裝置不可用';

  @override
  String get privateSession => '私人模式';

  @override
  String get currentDevice => '目前';

  @override
  String get editNote => '編輯筆記';

  @override
  String get deleteNote => '刪除筆記';

  @override
  String get cancel => '取消';

  @override
  String get confirmDelete => '確認刪除';

  @override
  String get deleteConfirmMessage => '您確定要刪除這條筆記嗎？此操作無法復原。';

  @override
  String get noNotes => '尚未新增任何筆記。';

  @override
  String recordsAt(String time) {
    return '記錄於 $time';
  }

  @override
  String get today => '今天';

  @override
  String get yesterday => '昨天';

  @override
  String playbackFailed(String error) {
    return '播放失敗: $error';
  }

  @override
  String get searchHint => '搜尋歌曲、專輯、藝人...';

  @override
  String get clearSearch => '清除搜尋';

  @override
  String get playToGenerateInsights => '播放一些音樂來生成洞察！';

  @override
  String get generateInsights => '生成洞察';

  @override
  String get generating => '生成中...';

  @override
  String get collapse => '收合';

  @override
  String get expand => '展開';

  @override
  String get noInsightsGenerated => '無法從提供的歷史紀錄生成洞察。';

  @override
  String get insightsTitle => '洞察';

  @override
  String get inspirationsTitle => '靈感';

  @override
  String get unknownArtist => '未知藝人';

  @override
  String get unknownTrack => '未知歌曲';

  @override
  String failedToGenerateInsights(String error) {
    return '生成洞察失敗: $error';
  }

  @override
  String copiedToClipboard(String type) {
    return '已複製到剪貼簿';
  }

  @override
  String get musicPersonality => '音樂人格';

  @override
  String get insightsContent => '洞察內容';

  @override
  String get recommendedSong => '推薦歌曲';

  @override
  String get addNote => '新增筆記';

  @override
  String get noteHint => '在此輸入您的筆記';

  @override
  String get saveNote => '儲存筆記';

  @override
  String get noteSaved => '筆記已儲存';

  @override
  String errorSavingNote(String error) {
    return '儲存筆記時出錯: $error';
  }

  @override
  String get notesTitle => '筆記';

  @override
  String get areYouSureDeleteNote => '您確定要刪除這條筆記嗎？';

  @override
  String get delete => '刪除';

  @override
  String get noteDeleted => '筆記已刪除';

  @override
  String errorDeletingNote(String error) {
    return '刪除筆記時出錯: $error';
  }

  @override
  String get noteUpdated => '筆記更新成功';

  @override
  String errorUpdatingNote(String error) {
    return '更新筆記時出錯: $error';
  }

  @override
  String get lyricsFetching => '正在擷取歌詞...';

  @override
  String get lyricsFound => '已找到歌詞。';

  @override
  String get lyricsNotFoundForTrack => '找不到此歌曲的歌詞。';

  @override
  String lyricsFetchError(String error) {
    return '擷取歌詞時出錯: $error';
  }

  @override
  String get lyricsTranslating => '正在翻譯歌詞...';

  @override
  String get lyricsTranslationSuccessful => '翻譯成功。';

  @override
  String lyricsTranslationError(String error) {
    return '翻譯歌詞時出錯: $error';
  }

  @override
  String get lyricsTitle => '歌詞';

  @override
  String get lyricsCopyModeTooltip => '歌詞複製模式';

  @override
  String get lyricsTranslateTooltip => '翻譯歌詞';

  @override
  String get lyricsToggleAutoScrollTooltip => '切換自動捲動';

  @override
  String get lyricsNotAvailable => '無可用歌詞。';

  @override
  String get lyricsLoading => '正在載入歌詞...';

  @override
  String get lyricsFailedToLoad => '載入歌詞失敗。';

  @override
  String get lyricsCopyModeSnackbar => '歌詞複製模式：單曲循環已啟用，自動捲動已停用。';

  @override
  String get couldNotGetCurrentTrackId => '無法取得目前歌曲 ID。';

  @override
  String translationFailed(Object error) {
    return '翻譯失敗: $error';
  }

  @override
  String get centerCurrentLine => '置中目前行';

  @override
  String get translateLyrics => '翻譯歌詞';

  @override
  String get exitCopyModeResumeScroll => '退出複製模式並恢復捲動';

  @override
  String get enterCopyLyricsMode => '進入歌詞複製模式（單曲循環）';

  @override
  String get translationTitle => '翻譯';

  @override
  String get originalTitle => '原文';

  @override
  String get translatedByAttribution => '由 Gemini 2.5 Flash 翻譯';

  @override
  String spiritLabel(String style) {
    return '風格: $style';
  }

  @override
  String get copyToClipboard => '複製到剪貼簿';

  @override
  String get retranslateButton => '重新翻譯';

  @override
  String get retranslating => '重新翻譯中...';

  @override
  String get translationStyleFaithful => '忠實';

  @override
  String get translationStyleMelodramaticPoet => '抒情詩人';

  @override
  String get translationStyleMachineClassic => '機器翻譯';

  @override
  String get translationStyleTooltipFaithful => '目前：忠實翻譯 - 點選更改';

  @override
  String get translationStyleTooltipMelodramatic => '目前：抒情詩人翻譯 - 點選更改';

  @override
  String get translationStyleTooltipMachine => '目前：機器翻譯 - 點擊更改';

  @override
  String get toggleTranslationStyle => '切換翻譯風格';

  @override
  String get showTranslation => '顯示翻譯';

  @override
  String get showOriginal => '顯示原文';

  @override
  String get closeTranslation => '關閉';

  @override
  String get trackSaved => '歌曲已儲存至播放清單';

  @override
  String errorSavingTrack(String error) {
    return '儲存歌曲時出錯: $error';
  }

  @override
  String get unknownAlbum => '未知專輯';

  @override
  String get playlist => '播放清單';

  @override
  String get unknownContext => '未知上下文';

  @override
  String get noTrackOrEmptyNote => '無法取得歌曲資訊或筆記為空';

  @override
  String get logoutSuccess => '已登出 Spotify';

  @override
  String get operationFailed => '操作失敗';

  @override
  String get invalidCredentialsError => '無效的 Spotify API 憑證。請檢查您的用戶端 ID 和密鑰。';

  @override
  String get authenticationError => '身分驗證失敗：憑證無效或權限不足。';

  @override
  String get tooManyRequestsError => '請求過多。請稍後再試。';

  @override
  String loginLogoutFailed(Object error) {
    return '登入/登出失敗: $error';
  }

  @override
  String get helpAction => '說明';

  @override
  String get setupTitle => '設定';

  @override
  String get googleAiApiKeyTitle => 'Google AI API 金鑰';

  @override
  String get googleAiApiKeySubtitle =>
      '設定您的 Google AI Studio API 金鑰以進行 Gemini 翻譯';

  @override
  String get spotifyApiTitle => 'Spotify API';

  @override
  String get spotifyApiSubtitle => '設定 Spotify 用戶端 ID 和密鑰';

  @override
  String get tutorialTitle => '教學';

  @override
  String get tutorialSubtitle => '查看設定教學';

  @override
  String get generalTitle => '通用';

  @override
  String get translationLanguageTitle => 'Gemini語言';

  @override
  String get translationLanguageSubtitle => '選擇翻譯和洞察的目標語言';

  @override
  String get translationStyleTitle => '翻譯風格';

  @override
  String get translationStyleSubtitle => '設定 Gemini 的風格';

  @override
  String get autoTranslateLyricsTitle => '自動翻譯歌詞';

  @override
  String get autoTranslateLyricsSubtitle => '當歌詞沒有翻譯時自動開始翻譯';

  @override
  String get copyLyricsAsSingleLineTitle => '將歌詞複製為單行';

  @override
  String get copyLyricsAsSingleLineSubtitle => '複製時將換行符號替換為空格';

  @override
  String get dataManagementTitle => '資料管理';

  @override
  String get exportDataTitle => '匯出資料';

  @override
  String get exportDataSubtitle => '將所有資料匯出為 JSON 檔案';

  @override
  String get importDataTitle => '匯入資料';

  @override
  String get importDataSubtitle => '從匯出的 JSON 檔案匯入資料';

  @override
  String get clearCacheTitle => '清除所有快取';

  @override
  String get clearCacheSubtitle => '清除歌詞和翻譯快取';

  @override
  String get geminiApiKeyDialogTitle => 'Gemini API 金鑰';

  @override
  String get geminiApiKeyDialogHint => '輸入您的 Gemini API 金鑰';

  @override
  String get cancelButton => '取消';

  @override
  String get apiKeySaved => 'Gemini API 金鑰已儲存';

  @override
  String get okButton => '確定';

  @override
  String get spotifyCredentialsDialogTitle => 'Spotify API';

  @override
  String get clientIdLabel => '用戶端 ID';

  @override
  String get clientSecretLabel => '用戶端密鑰';

  @override
  String get emptyCredentialsError => '用戶端 ID 和密鑰皆不可為空。';

  @override
  String get invalidClientIdError => '用戶端 ID 必須是 32 位元的十六進位字串。';

  @override
  String get invalidClientSecretError => '用戶端 Secret 必須是 32 位元的十六進位字串。';

  @override
  String get credentialsSaved => 'Spotify 憑證已儲存';

  @override
  String get credentialsSaveFailed => '儲存憑證失敗';

  @override
  String get languageDialogTitle => '選擇語言';

  @override
  String get languageSaved => '語言設定已儲存';

  @override
  String get translationStyleDialogTitle => '選擇翻譯風格';

  @override
  String get translationStyleSaved => '翻譯風格已儲存';

  @override
  String get exportFailed => '匯出失敗或已取消。';

  @override
  String get importDialogTitle => '確認匯入';

  @override
  String get importDialogMessage =>
      '匯入資料將取代具有相同識別符的現有歌曲和翻譯，並新增檔案中的所有記錄。此操作無法復原。您確定要繼續嗎？\n\n確保 JSON 檔案有效且先前是從 Spotoolfy 匯出的。';

  @override
  String get importButton => '匯入資料';

  @override
  String get importSuccess => '資料匯入成功！';

  @override
  String get importFailed => '匯入失敗或已取消。';

  @override
  String get exportSuccess => '資料匯出成功！';

  @override
  String get clearCacheDialogTitle => '確認清除快取';

  @override
  String get clearCacheDialogMessage => '您確定要清除歌詞和翻譯快取嗎？此操作無法復原。';

  @override
  String get clearCacheButton => '清除快取';

  @override
  String get clearingCache => '正在清除快取...';

  @override
  String get cacheCleared => '快取清除成功！';

  @override
  String get cacheClearFailed => '清除快取失敗';

  @override
  String failedToChangeLanguage(String error) {
    return '更改語言失敗: $error';
  }

  @override
  String failedToChangeStyle(String error) {
    return '更改翻譯風格失敗: $error';
  }

  @override
  String get noteContent => '筆記內容';

  @override
  String get saveChanges => '儲存';

  @override
  String get noLyricsToTranslate => '沒有可翻譯的歌詞。';

  @override
  String failedToSaveTranslation(Object error) {
    return '儲存擷取的翻譯失敗: $error';
  }

  @override
  String get failedToGetTranslation => '擷取翻譯失敗。';

  @override
  String get copyLyricsModeHint => '歌詞複製模式：單曲循環已啟用，自動捲動已停用。';

  @override
  String get exitCopyMode => '退出複製模式並恢復捲動';

  @override
  String get enterCopyMode => '進入歌詞複製模式（單曲循環）';

  @override
  String get selectLyrics => '選擇歌詞';

  @override
  String get selectLyricsTooltip => '選擇歌詞片段進行分析或分享';

  @override
  String get selectAll => '全選';

  @override
  String get deselectAll => '取消全選';

  @override
  String get noLyricsSelected => '請先選擇一些歌詞';

  @override
  String get askGemini => '詢問 Gemini';

  @override
  String get sharePoster => '分享海報';

  @override
  String get copySelected => '複製選中';

  @override
  String get geminiAnalysisResult => 'Gemini 分析結果';

  @override
  String get lyricsTheme => '主題';

  @override
  String get lyricsEmotion => '情感';

  @override
  String get lyricsMetaphor => '隱喻與象徵';

  @override
  String get lyricsInterpretation => '深度解讀';

  @override
  String get lyricsReference => '引用與典故';

  @override
  String get lyricsKeywordsExplanation => '關鍵詞解釋';

  @override
  String get copyAnalysis => '複製分析';

  @override
  String get analysisResultCopied => '分析結果已複製到剪貼簿';

  @override
  String selectedLyricsCopied(int count) {
    return '已複製 $count 行歌詞';
  }

  @override
  String posterGenerationFailed(Object error) {
    return '生成海報失敗: $error';
  }

  @override
  String analysisFailed(String error) {
    return '分析失敗: $error';
  }

  @override
  String get noLyricsToSelect => '沒有可選擇的歌詞';

  @override
  String get posterLyricsLimitExceeded => '最多只能選擇10行歌詞生成海報';

  @override
  String get multiSelectMode => '多選模式';

  @override
  String get tapToSelectLyrics => '輕點歌詞行以選取';

  @override
  String get appTitle => 'Spotoolfy';

  @override
  String get nowPlayingLabel => '播放中';

  @override
  String get libraryLabel => '音樂庫';

  @override
  String get roamLabel => '探索';

  @override
  String get tutorialButtonText => '教學';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageSimplifiedChinese => '简体中文 (Simplified Chinese)';

  @override
  String get languageTraditionalChinese => '繁體中文 (Traditional Chinese)';

  @override
  String get languageJapanese => '日本語 (Japanese)';

  @override
  String get collapseTooltip => '收合';

  @override
  String get expandTooltip => '展開';

  @override
  String get incompleteRecordError => '無法繼續：紀錄資訊不完整';

  @override
  String get optionsTitle => '選項';

  @override
  String playFromTimestamp(String timestamp) {
    return '從 $timestamp 播放';
  }

  @override
  String get editNoteTitle => '編輯筆記';

  @override
  String get ratedStatus => '已評分';

  @override
  String get noItemsFound => '找不到項目';

  @override
  String get cannotCreateSpotifyLink => '無法建立 Spotify 連結';

  @override
  String get cannotOpenSpotify => '無法開啟 Spotify';

  @override
  String failedToOpenSpotify(String error) {
    return '開啟 Spotify 失敗: $error';
  }

  @override
  String get playlistsTab => '播放清單';

  @override
  String get albumsTab => '專輯';

  @override
  String get tryAgainButton => '重試';

  @override
  String get playTrackToSeeThoughts => '播放歌曲以查看想法。';

  @override
  String get copyButtonText => '複製';

  @override
  String get posterButtonLabel => '海報';

  @override
  String get noteButtonLabel => '筆記';

  @override
  String get lyricsAnalysisTitle => '歌詞分析';

  @override
  String get regenerateAnalysisTooltip => '重新產生分析';

  @override
  String get copyAllAnalysisTooltip => '複製所有分析';

  @override
  String get geminiGrounding => 'Gemini 正在思考...';

  @override
  String get retryButton => '重試';

  @override
  String get noAnalysisResults => '沒有分析結果';

  @override
  String get noDeepAnalysisContent => '該歌詞片段暫無深度分析內容';

  @override
  String get simpleContentExplanation => '這可能是因為歌詞內容相對簡單，或沒有明顯的隱喻、引用等文學手法';

  @override
  String get reanalyzeButton => '重新分析';

  @override
  String get onlyFoundDimensionsInfo => '只顯示在該歌詞中發現的分析維度';

  @override
  String get songInfoRegeneratedMessage => '歌曲資訊已重新產生';

  @override
  String get songInformationTitle => '歌曲資訊';

  @override
  String get regenerateTooltip => '重新產生';

  @override
  String get noSongInfoAvailable => '無可用歌曲資訊';

  @override
  String get generateAIContent => '點擊產生歌曲背景資訊和音樂解析';

  @override
  String get generatingAIContent => '正在產生中...';

  @override
  String get deleteAIContent => '點擊刪除AI分析內容';

  @override
  String get generatedByGemini => '由 Gemini 2.5 Flash 產生';

  @override
  String get poweredByGoogleSearch => '由 Google 搜尋基礎提供支援';

  @override
  String get creationTimeTitle => '創作時間';

  @override
  String get creationLocationTitle => '創作地點';

  @override
  String get lyricistTitle => '作詞';

  @override
  String get composerTitle => '作曲';

  @override
  String get producerTitle => '製作人';

  @override
  String get songAnalysisTitle => '歌曲分析';

  @override
  String get selectArtistTitle => '選擇藝術家';

  @override
  String get backToLibraryTooltip => '返回資料庫';

  @override
  String get appWatermark => 'Spotoolfy';

  @override
  String get loadingAnalyzing => '正在用 AI 分析歌詞...';

  @override
  String get loadingDecoding => '正在解碼音樂奧秘...';

  @override
  String get loadingSearching => '正在搜尋洞察...';

  @override
  String get loadingThinking => 'Gemini 正在思考...';

  @override
  String get loadingGenerating => '正在產生分析...';

  @override
  String loadingChatting(String artist) {
    return '正在與 $artist 對話...';
  }

  @override
  String get loadingDiscovering => '正在發現隱藏的含義...';

  @override
  String get loadingExploring => '正在探索歌詞深度...';

  @override
  String get loadingUnraveling => '正在揭開詩意層次...';

  @override
  String get loadingConnecting => '正在連接情感線索...';

  @override
  String get currentQueueEmpty => '目前佇列為空';

  @override
  String get queueUpNext => '即將播放';

  @override
  String get noQueueItems => '沒有即將播放的曲目';

  @override
  String queuePositionInfo(int position, int total) {
    return '第 $position 首，共 $total 首';
  }

  @override
  String failedToSwitchDevice(String error) {
    return '切換裝置失敗: $error';
  }

  @override
  String deviceRestrictedMessage(String device) {
    return '裝置 \'$device\' 受限，無法透過API控制。';
  }

  @override
  String get insufficientPermissionsReauth => '權限範圍不足，正在重新取得完整授權...';

  @override
  String get reauthFailedManualLogin => '重新取得授權失敗，請手動重新登入';

  @override
  String badRequestError(String code) {
    return '請求格式錯誤 ($code)，請稍後重試或聯繫開發者。';
  }

  @override
  String get searchLyrics => '搜尋歌詞';

  @override
  String get noCurrentTrackPlaying => '沒有正在播放的歌曲';

  @override
  String get cannotGetTrackInfo => '無法取得目前歌曲資訊';

  @override
  String get lyricsSearchAppliedSuccess => '歌詞已成功搜尋並套用';

  @override
  String get thoughts => '想法';

  @override
  String get noTrack => '無音軌';

  @override
  String get noIdeasYet => '暫無關於這首歌的想法。\n來分享第一個想法吧！';

  @override
  String get relatedThoughts => '相關想法';

  @override
  String get yourLibrary => '您的資料庫';

  @override
  String get errorLoadingLibrary => '載入資料庫時發生錯誤';

  @override
  String get searchResults => '搜尋結果';

  @override
  String get noResultsFound => '未找到結果';

  @override
  String get tryDifferentKeywords => '請嘗試不同的關鍵字或檢查拼字';

  @override
  String get infoLabel => '資訊';

  @override
  String get playlistType => '播放清單';

  @override
  String get albumType => '專輯';

  @override
  String get songType => '歌曲';

  @override
  String get artistType => '藝人';

  @override
  String get daysAgo => '天前';

  @override
  String get hoursAgo => '小時前';

  @override
  String get minsAgo => '分鐘前';

  @override
  String get secsAgo => '秒前';

  @override
  String failedToPlayAlbum(String error) {
    return '播放專輯失敗：$error';
  }

  @override
  String get rateAtLeastOneSongForPoster => '至少先為一首歌曲評分才能生成海報';

  @override
  String failedToSharePoster(String error) {
    return '分享評分海報失敗：$error';
  }

  @override
  String get cannotPlayMissingTrackLink => '無法播放：缺少歌曲連結';

  @override
  String failedToPlaySong(String error) {
    return '播放歌曲失敗：$error';
  }

  @override
  String failedToSaveRating(String error) {
    return '儲存評分失敗：$error';
  }

  @override
  String get albumDetails => '專輯詳情';

  @override
  String get titleCopied => '標題已複製';

  @override
  String get playAlbum => '播放';

  @override
  String get rateAtLeastOneSongFirst => '先給幾首歌評分後再分享海報';

  @override
  String get shareAlbumRatingPoster => '分享專輯評分海報';

  @override
  String get hideQuickRating => '隱藏快速評分';

  @override
  String get showQuickRating => '顯示快速評分';

  @override
  String get currently => '目前';

  @override
  String get savingChanges => '儲存中…';

  @override
  String get saveAllChanges => '儲存全部變更';

  @override
  String get generatingTooltip => '生成中…';

  @override
  String get generateAlbumInsights => '生成專輯洞察';

  @override
  String get collapseInsights => '收合洞察';

  @override
  String get expandInsights => '展開洞察';

  @override
  String get noSongsRatedYet => '尚未評分任何歌曲';

  @override
  String basedOnRatedSongs(int rated, int total) {
    return '基於 $rated/$total 首歌曲';
  }

  @override
  String failedToGenerateAlbumInsights(String error) {
    return '生成洞察失敗：$error';
  }

  @override
  String failedToLoadCache(String error) {
    return '讀取快取失敗：$error';
  }

  @override
  String get generatingAlbumInsights => '正在生成專輯洞察…';

  @override
  String get noInsightsAvailableTapToGenerate => '暫無可用洞察。點選上方按鈕生成一次吧。';

  @override
  String get insightsEmptyRetryGenerate => '洞察結果空空如也，試著重新生成一次。';

  @override
  String insightsGeneratedDaysAgo(int days) {
    return '洞察生成於 $days 天前';
  }

  @override
  String insightsGeneratedHoursAgo(int hours) {
    return '洞察生成於 $hours 小時前';
  }

  @override
  String insightsGeneratedMinutesAgo(int minutes) {
    return '洞察生成於 $minutes 分鐘前';
  }

  @override
  String get insightsJustGenerated => '洞察剛剛生成';

  @override
  String get refreshAlbum => '重新整理專輯';

  @override
  String get failedToLoadAlbum => '載入專輯失敗';

  @override
  String get unknownError => '未知錯誤';

  @override
  String get unratedStatus => '未評分';

  @override
  String get justNow => '剛剛';

  @override
  String minutesAgoShort(int minutes) {
    return '$minutes分鐘前';
  }

  @override
  String hoursAgoShort(int hours) {
    return '$hours小時前';
  }

  @override
  String daysAgoShort(int days) {
    return '$days天前';
  }

  @override
  String totalTracksCount(int count) {
    return '共$count首曲目';
  }

  @override
  String failedToPlayPlaylist(String error) {
    return '播放播放清單失敗：$error';
  }

  @override
  String get playPlaylist => '播放播放清單';

  @override
  String get playlistDetails => '播放清單詳情';

  @override
  String get refreshPlaylist => '重新整理播放清單';

  @override
  String createdBy(String owner) {
    return '由 $owner 建立';
  }

  @override
  String playlistTrackCount(int count) {
    return '共 $count 首曲目';
  }

  @override
  String get failedToLoadPlaylist => '載入播放清單失敗';

  @override
  String get playlistTracksLabel => '播放清單曲目';

  @override
  String get deviceOperationNotSupported =>
      '目前裝置不支援此操作或受限。請嘗試在其他裝置上播放音樂，或檢查您的帳戶類型。';

  @override
  String shareAlbumMessage(
      String albumName, String artist, String score, int rated, int total) {
    return '我在 Spotoolfy 給《$albumName》（$artist）打出了 $score 分，已評分 $rated/$total 首歌曲。';
  }

  @override
  String get noRating => '暫無評分';

  @override
  String get retry => '重試';

  @override
  String get unknownTrackName => '未知曲目';

  @override
  String get albumInsightReadyStatus => '專輯洞察已準備好';

  @override
  String get clickToGenerateAlbumInsights => '點選右側按鈕生成這張專輯的洞察';

  @override
  String get failedToGenerateAlbumInsightsStatus => '生成專輯洞察失敗';

  @override
  String get providerQQMusic => 'QQ音樂';

  @override
  String get providerLRCLIB => 'LRCLIB';

  @override
  String get providerNetease => '網易雲音樂';

  @override
  String get playingFrom => '播放自';

  @override
  String get playFromAlbum => '播放自專輯';

  @override
  String get playFromPlaylist => '播放自播放清單';

  @override
  String get sharingStatus => '分享中...';

  @override
  String get shareButton => '分享';
}
