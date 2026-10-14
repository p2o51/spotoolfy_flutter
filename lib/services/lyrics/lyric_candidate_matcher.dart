import 'dart:math' as math;

/// 一条搜索结果：标题、全部演唱者、所在专辑（歌词源没给就是 null），顺序即歌词源给出的排位。
class LyricCandidate {
  final String title;
  final List<String> artists;
  final String? album;

  const LyricCandidate(this.title, this.artists, {this.album});
}

/// 自动匹配时，从歌词源的搜索结果里认出"就是这首歌"的那一条。认不出就返回 null，
/// 让下一个 provider 去试，而不是拿同名的别人的歌顶上。
///
/// 移植自 Yoin 的 `LyricCandidateMatcher`（2026-10），规则一致：
///
/// **标题。** 比较前先归一：全角转半角、[fold]（可注入，默认原样）、忽略大小写、
/// 标点和空白，拉丁字母去掉变音符。结尾注记——括号段（`(Live)`、`(Explicit)`）、
/// ` - 后缀`、`feat.` 子句——从外往里一层层剥。双方去掉"同一母带"注记后相同，算"原版"；
/// 双方去掉全部注记后才相同，算"注记版"。伴奏 / 纯音乐类注记取不到歌词，除非请求本身
/// 就是伴奏，否则不算匹配。
///
/// **同一母带注记**：Remaster(ed)、Mono、Stereo、Album/LP/Original Version、Original Mix、
/// Explicit 及对应日文写法，可带年份、Digital(ly)、HD、Anniversary、Version、Edition、Mix。
/// 混进别的词（`Take 1 - Remastered`）就不算；`feat.` 子句永远不算。
///
/// **专辑。** 请求的标题是原版时再看专辑：现场 / Unplugged / 演唱会 / Remix / Demo / 翻唱
/// → 最多算"注记版"；访谈、卡拉 OK、伴奏合辑 → "存疑"。
///
/// **艺人。** 请求的艺人串整体算一个名字，按 `&`、`,`、`、`、`/`、`;`、`feat.` 拆出的每一段
/// 也各算一个：归一后相同 → 匹配；书写系统完全一致却不同 → 否决；书写系统不同但双方都有
/// 拉丁词 → 一方的拉丁词全在另一方里才匹配；其余无从判断。
///
/// **挑选。** 先看艺人匹配的候选，取档位最高、排位靠前的一条。一条都没有时，只在"无从判断"
/// 的候选里看排位第一的那位艺人：他至少有 2 条同名录音并且比其余任何艺人都多，才认定是他；
/// 否则返回 null。
class LyricCandidateMatcher {
  LyricCandidateMatcher({String Function(String)? fold}) : _fold = fold ?? _identity;

  final String Function(String) _fold;

  static String _identity(String value) => value;

  /// 返回 [candidates] 里选中的下标；没有可信的匹配时返回 null。
  int? pick(List<LyricCandidate> candidates, String title, String artist) {
    if (candidates.isEmpty) return null;
    final wantedTitle = _titleOf(title);
    if (wantedTitle == null) return null;
    final wantedArtists = _artistNamesOf(artist);

    final cuts = <_Cut>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final fit = _fitOf(wantedTitle, candidate);
      if (fit == null) continue;
      final performers =
          candidate.artists.map(_nameOf).where((n) => n.key.isNotEmpty).toList();
      cuts.add(_Cut(i, fit, performers, _verdictOf(wantedArtists, performers)));
    }
    if (cuts.isEmpty) return null;

    final matched = _preferred(cuts.where((c) => c.verdict == _Verdict.match).toList());
    if (matched != null) return matched.index;
    return _dominantPerformerCut(
            cuts.where((c) => c.verdict == _Verdict.unknown).toList())
        ?.index;
  }

  // ── 标题 ─────────────────────────────────────────────────────────────────

  _Fit? _fitOf(_TitleShape wanted, LyricCandidate candidate) {
    final offered = _titleOf(candidate.title);
    if (offered == null) return null;
    final _Fit byTitle;
    if (offered.key == wanted.key || offered.masterKey == wanted.masterKey) {
      byTitle = _Fit.original;
    } else if (offered.coreKey != wanted.coreKey) {
      return null;
    } else if (offered.instrumental && !wanted.instrumental) {
      return null;
    } else {
      byTitle = _Fit.decorated;
    }
    if (!wanted.isOriginal) return byTitle;
    final byAlbum = _albumFitOf(candidate.album);
    return byAlbum.index > byTitle.index ? byAlbum : byTitle;
  }

  _TitleShape? _titleOf(String raw) {
    final text = _prepare(raw);
    final key = _keyOf(text);
    if (key.isEmpty) return null;
    var core = text;
    final notes = <_Note>[];
    while (true) {
      _NotePattern? pattern;
      RegExpMatch? found;
      for (final candidate in _trailingNotes) {
        final match = candidate.regex.firstMatch(core);
        if (match != null) {
          pattern = candidate;
          found = match;
          break;
        }
      }
      if (pattern == null || found == null) break;
      final rest = core.substring(0, found.start);
      if (_keyOf(rest).isEmpty) break;
      final noteKey = _keyOf(found.group(1) ?? '');
      notes.add(_Note(
        key: noteKey,
        segmentKey: _keyOf(found.group(0)!),
        sameMaster: pattern.versionNote && _sameMasterNote.hasMatch(noteKey),
      ));
      core = rest;
    }
    final coreKey = _keyOf(core);
    // 剥的时候从外往里，拼回去要从里往外。
    final otherNotes = notes.reversed
        .where((note) => !note.sameMaster)
        .map((note) => note.segmentKey)
        .join();
    return _TitleShape(
      key: key,
      coreKey: coreKey,
      masterKey: coreKey + otherNotes,
      instrumental: notes.any((note) => _isInstrumentalNote(note.key)),
    );
  }

  bool _isInstrumentalNote(String noteKey) =>
      _instrumentalNotes.contains(noteKey) ||
      _instrumentalWords.any(noteKey.contains);

  // ── 专辑 ─────────────────────────────────────────────────────────────────

  _Fit _albumFitOf(String? raw) {
    if (raw == null || raw.trim().isEmpty) return _Fit.original;
    final text = _prepare(raw);
    final key = _keyOf(text);
    final words = _latinWordListOf(text);
    if (words.any(_doubtfulAlbumWords.contains) ||
        _doubtfulAlbumMarks.any(key.contains)) {
      return _Fit.doubtful;
    }
    if (_isLiveAlbum(words) ||
        words.any(_alternateAlbumWords.contains) ||
        _alternateAlbumMarks.any(key.contains)) {
      return _Fit.decorated;
    }
    return _Fit.original;
  }

  /// `live` 在最后，或者后面紧跟年份 / [_liveFollowers]；`tour` 后面紧跟年份。
  bool _isLiveAlbum(List<String> words) {
    for (var i = 0; i < words.length; i++) {
      final next = i + 1 < words.length ? words[i + 1] : null;
      switch (words[i]) {
        case 'live':
          if (next == null || _liveFollowers.contains(next) || _isYear(next)) {
            return true;
          }
        case 'tour':
          if (next != null && _isYear(next)) return true;
      }
    }
    return false;
  }

  // ── 艺人 ─────────────────────────────────────────────────────────────────

  List<_Name> _artistNamesOf(String raw) {
    final whole = raw.trim();
    if (whole.isEmpty) return const [];
    final seen = <String>{};
    final names = <_Name>[];
    for (final part in [whole, ...whole.split(_artistSeparator)]) {
      final name = _nameOf(part);
      if (name.key.isEmpty || !seen.add(name.key)) continue;
      names.add(name);
    }
    return names;
  }

  _Name _nameOf(String raw) {
    final text = _prepare(raw);
    return _Name(
      key: _keyOf(text),
      scripts: _scriptsOf(text),
      latinWords: _latinWordsOf(text),
    );
  }

  _Verdict _verdictOf(List<_Name> wanted, List<_Name> performers) {
    if (wanted.isEmpty || performers.isEmpty) return _Verdict.unknown;
    var undecided = false;
    for (final name in wanted) {
      for (final performer in performers) {
        switch (_compare(name, performer)) {
          case _Verdict.match:
            return _Verdict.match;
          case _Verdict.unknown:
            undecided = true;
          case _Verdict.mismatch:
            break;
        }
      }
    }
    return undecided ? _Verdict.unknown : _Verdict.mismatch;
  }

  _Verdict _compare(_Name wanted, _Name offered) {
    if (wanted.key == offered.key) return _Verdict.match;
    if (_sameSet(wanted.scripts, offered.scripts)) return _Verdict.mismatch;
    if (wanted.latinWords.isEmpty || offered.latinWords.isEmpty) {
      return _Verdict.unknown;
    }
    if (offered.latinWords.containsAll(wanted.latinWords) ||
        wanted.latinWords.containsAll(offered.latinWords)) {
      return _Verdict.match;
    }
    return _Verdict.mismatch;
  }

  // ── 挑选 ─────────────────────────────────────────────────────────────────

  _Cut? _dominantPerformerCut(List<_Cut> unverifiable) {
    if (unverifiable.isEmpty) return null;
    final lead = unverifiable.first;
    final cutsByPerformer = <String, List<_Cut>>{};
    for (final cut in unverifiable) {
      for (final key in cut.performerKeys) {
        (cutsByPerformer[key] ??= <_Cut>[]).add(cut);
      }
    }
    String? performer;
    var most = -1;
    for (final key in lead.performerKeys) {
      final count = cutsByPerformer[key]?.length ?? 0;
      if (count > most) {
        most = count;
        performer = key;
      }
    }
    if (performer == null) return null;
    final own = cutsByPerformer[performer]!;
    if (own.length < _minDominantCuts) return null;
    final rivals = <String, int>{};
    for (final cut in unverifiable) {
      if (cut.performerKeys.contains(performer)) continue;
      for (final key in cut.performerKeys) {
        rivals[key] = (rivals[key] ?? 0) + 1;
      }
    }
    final strongestRival = rivals.values.fold<int>(0, math.max);
    return own.length > strongestRival ? _preferred(own) : null;
  }

  _Cut? _preferred(List<_Cut> cuts) {
    _Cut? best;
    for (final cut in cuts) {
      if (best == null ||
          cut.fit.index < best.fit.index ||
          (cut.fit.index == best.fit.index && cut.index < best.index)) {
        best = cut;
      }
    }
    return best;
  }

  // ── 归一 ─────────────────────────────────────────────────────────────────

  /// 全角转半角 → [fold] → 小写；保留标点，留给去注记用。
  String _prepare(String raw) => _fold(_compatibilityFold(raw)).toLowerCase();

  // ── 常量 ─────────────────────────────────────────────────────────────────

  /// 无从判断艺人时，排位第一的艺人至少要有这么多条同名录音才可信。
  static const int _minDominantCuts = 2;

  /// 结尾注记，从外往里一层层剥；第 1 组是注记内容。
  static final List<_NotePattern> _trailingNotes = [
    _NotePattern(
        RegExp(r'\s*[(\[【〔]([^()\[\]【】〔〕]*)[)\]】〕]\s*$'), true),
    _NotePattern(RegExp(r'\s+[-–—]\s+(.+)$'), true),
    _NotePattern(RegExp(r'\s+(?:feat\.?|ft\.|featuring)\s+(.+)$'), false),
  ];

  /// 同一母带注记：整段注记归一后必须完全由这些词拼成，并且至少有一个"标记词"。
  /// Yoin 用占有量词 `\d++` 防回溯爆炸；Dart 没有，用 `(?=(\d+))\N` 模拟原子组。
  static final RegExp _sameMasterNote = () {
    const marker =
        r'remaster(?:ed|ing)?|mono|stereo|explicit|(?:album|lp|original)(?:version|ver)|'
        r'originalmix|リマスター|リマスタリング|モノラル|ステレオ|アルバム(?:バージョン|ヴァージョン)';
    String filler(int group) =>
        '(?=(\\d+))\\$group(?:st|nd|rd|th)?|anniversary|digital(?:ly)?|hd|'
        'version|ver|edition|mix|版|バージョン|ヴァージョン';
    return RegExp('^(?:${filler(1)})*(?:$marker)(?:${filler(2)}|$marker)*\$');
  }();

  /// 请求艺人串里的多人分隔符。整串本身也会参与比较，拆错不至于丢掉原名。
  static final RegExp _artistSeparator = RegExp(
    r'\s*(?:[&＆,，、/／;；]|\s(?:feat\.?|ft\.|featuring)\s)\s*',
    caseSensitive: false,
  );

  static const Set<String> _instrumentalNotes = {'inst', 'instver', 'instversion'};

  static const List<String> _instrumentalWords = [
    'instrumental',
    'karaoke',
    'offvocal',
    '伴奏',
    '纯音乐',
    'カラオケ',
    'オフボーカル',
  ];

  static const Set<String> _doubtfulAlbumWords = {
    'interview',
    'interviews',
    'karaoke',
    'instrumental',
    'instrumentals',
    'inst',
  };

  static const List<String> _doubtfulAlbumMarks = [
    'offvocal', '访谈', '专访', '采访', '伴奏', '纯音乐', 'カラオケ', 'オフボーカル', 'インタビュー', '인터뷰',
  ];

  static const Set<String> _alternateAlbumWords = {
    'unplugged', 'concert', 'concerts', 'acoustic', 'remix', 'remixes', 'remixed', 'demo', 'demos',
    'outtakes', 'rehearsal', 'rehearsals', 'bootleg', 'covers', 'tribute', 'sped', 'slowed', 'nightcore',
  };

  static const List<String> _alternateAlbumMarks = [
    '演唱会', '现场', '音乐会', '翻唱', '翻自', '致敬', '混音', '加速版', '慢速版', '降速版',
    'ライブ', 'ライヴ', 'コンサート', 'リミックス', '라이브', '콘서트',
  ];

  static const Set<String> _liveFollowers = {
    'at', 'in', 'from', 'on', 'cd', 'dvd', 'album', 'version', 'ver', 'edition', 'recording',
    'recordings', 'tour', 'concert', 'session', 'sessions', 'set', 'show',
  };
}

enum _Fit { original, decorated, doubtful }

enum _Verdict { match, mismatch, unknown }

class _TitleShape {
  final String key;
  final String coreKey;
  final String masterKey;
  final bool instrumental;

  _TitleShape({
    required this.key,
    required this.coreKey,
    required this.masterKey,
    required this.instrumental,
  });

  bool get isOriginal => masterKey == coreKey;
}

class _Note {
  final String key;
  final String segmentKey;
  final bool sameMaster;

  _Note({required this.key, required this.segmentKey, required this.sameMaster});
}

class _NotePattern {
  final RegExp regex;
  final bool versionNote;

  _NotePattern(this.regex, this.versionNote);
}

class _Name {
  final String key;
  final Set<String> scripts;
  final Set<String> latinWords;

  _Name({required this.key, required this.scripts, required this.latinWords});
}

class _Cut {
  final int index;
  final _Fit fit;
  final _Verdict verdict;
  final List<String> performerKeys;

  _Cut(this.index, this.fit, List<_Name> performers, this.verdict)
      : performerKeys = performers.map((p) => p.key).toSet().toList();
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

// ── 字符工具（Dart 没有 NFKC / NFD / UnicodeScript，按需实现） ──────────────

final RegExp _letter = RegExp(r'\p{L}', unicode: true);
final RegExp _decimalDigit = RegExp(r'\p{Nd}', unicode: true);
final RegExp _latinScript = RegExp(r'\p{Script=Latin}', unicode: true);
final RegExp _ignorableScript =
    RegExp(r'[\p{Script=Common}\p{Script=Inherited}]', unicode: true);

/// 需要区分的书写系统；平假名并入片假名。其余字母归为 `Other`。
final List<MapEntry<String, RegExp>> _scripts = [
  for (final name in const [
    'Latin', 'Han', 'Katakana', 'Hangul', 'Cyrillic', 'Greek', 'Thai', 'Arabic', 'Hebrew',
    'Devanagari', 'Bopomofo', 'Armenian', 'Georgian', 'Tamil', 'Bengali', 'Lao', 'Khmer',
    'Myanmar', 'Tibetan', 'Mongolian', 'Ethiopic',
  ])
    MapEntry(name, RegExp('\\p{Script=$name}', unicode: true)),
  MapEntry('Katakana', RegExp(r'\p{Script=Hiragana}', unicode: true)),
];

/// NFKC 的子集：全角 ASCII 转半角，全角 / 不换行空格转普通空格。
String _compatibilityFold(String raw) {
  final out = StringBuffer();
  for (final rune in raw.runes) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      out.writeCharCode(rune - 0xFEE0);
    } else if (rune == 0x3000 || rune == 0x00A0) {
      out.writeCharCode(0x20);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

bool _isLetter(String char) => _letter.hasMatch(char);

bool _isLatin(String char) => _latinScript.hasMatch(char);

/// 比较键：只留字母和数字，拉丁字母去变音符。输入应已经过 prepare。
String _keyOf(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (_isLetter(char)) {
      out.write(_isLatin(char) ? _baseLatin(rune) : char);
    } else if (_decimalDigit.hasMatch(char)) {
      out.write(char);
    }
  }
  return out.toString();
}

/// 名字里出现的书写系统；通用 / 继承字符（`ー`、数字）不计。
Set<String> _scriptsOf(String text) {
  final scripts = <String>{};
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (!_isLetter(char)) continue;
    String? script;
    for (final entry in _scripts) {
      if (entry.value.hasMatch(char)) {
        script = entry.key;
        break;
      }
    }
    if (script == null) {
      if (_ignorableScript.hasMatch(char)) continue;
      script = 'Other';
    }
    scripts.add(script);
  }
  return scripts;
}

/// 连续的拉丁字母 / ASCII 数字算一个词；至少两个字符且含字母才留下。
Set<String> _latinWordsOf(String text) {
  final words = <String>{};
  for (final word in _latinRuns(text)) {
    if (word.length >= 2 && word.contains(_letter)) words.add(word);
  }
  return words;
}

/// 同 [_latinWordsOf] 的切词，但按出现顺序全部保留，给专辑名看词序用。
List<String> _latinWordListOf(String text) => _latinRuns(text);

List<String> _latinRuns(String text) {
  final words = <String>[];
  final word = StringBuffer();
  void flush() {
    if (word.isNotEmpty) words.add(word.toString());
    word.clear();
  }

  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (_isLetter(char) && _isLatin(char)) {
      word.write(_baseLatin(rune));
    } else if (rune >= 0x30 && rune <= 0x39) {
      word.write(char);
    } else {
      flush();
    }
  }
  flush();
  return words;
}

/// `19xx` / `20xx`。
bool _isYear(String word) =>
    word.length == 4 &&
    RegExp(r'^\d{4}$').hasMatch(word) &&
    (word.startsWith('19') || word.startsWith('20'));

/// 拉丁字母去掉变音符（NFD 去掉组合符号的效果）；没有规范分解的字母（ø、æ、ß、đ、ł）原样保留。
String _baseLatin(int rune) {
  if (rune < 0x80) return String.fromCharCode(rune);
  return _latinBase[rune] ?? String.fromCharCode(rune);
}

final Map<int, String> _latinBase = () {
  const table = {
    'a': 'àáâãäåāăąǎǟǡǻȁȃȧḁạảấầẩẫậắằẳẵặ',
    'c': 'çćĉċčḉ',
    'd': 'ďḋḍḏḑḓ',
    'e': 'èéêëēĕėęěȅȇȩḕḗḙḛḝẹẻẽếềểễệ',
    'g': 'ĝğġģǧǵḡ',
    'h': 'ĥȟḣḥḧḩḫẖ',
    'i': 'ìíîïĩīĭįǐȉȋḭḯỉị',
    'j': 'ĵǰ',
    'k': 'ķǩḱḳḵ',
    'l': 'ĺļľḷḹḻḽ',
    'm': 'ḿṁṃ',
    'n': 'ñńņňǹṅṇṉṋ',
    'o': 'òóôõöōŏőơǒǫǭȍȏȫȭȯȱṍṏṑṓọỏốồổỗộớờởỡợ',
    'p': 'ṕṗ',
    'r': 'ŕŗřȑȓṙṛṝṟ',
    's': 'śŝşšșṡṣṥṧṩ',
    't': 'ţťțṫṭṯṱẗ',
    'u': 'ùúûüũūŭůűųưǔǖǘǚǜȕȗṳṵṷṹṻụủứừửữự',
    'v': 'ṽṿ',
    'w': 'ŵẁẃẅẇẉẘ',
    'x': 'ẋẍ',
    'y': 'ýÿŷȳẏẙỳỵỷỹ',
    'z': 'źżžẑẓẕ',
  };
  final map = <int, String>{};
  table.forEach((base, variants) {
    for (final rune in variants.runes) {
      map[rune] = base;
    }
  });
  return map;
}();
