import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

void main() => runApp(const PhotoDateApp());

class PhotoDateApp extends StatelessWidget {
  const PhotoDateApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Foto Tarih Düzenleyici',
    theme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      useMaterial3: true,
      brightness: Brightness.light,
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _channel = MethodChannel('foto_tarih_duzenleyici');
  String? _folder;
  Map<String, dynamic>? _result;
  bool _busy = false;
  bool _cancelRequested = false;
  bool _organizeByYear = false;
  bool _separateScreenshots = false;
  bool _includeSubfolders = true;
  bool _findDuplicates = false;
  bool _separateSnapchat = true;
  final Map<String, String> _quarantine = {};
  final Set<String> _selectedQuarantine = {};
  double _progress = 0;
  String _progressText = '';
  bool _snapUnix = true;
  bool _assignUnknownSnap = false;
  DateTime? _fallbackDate;
  final _exifTool = TextEditingController();

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress' && mounted) {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        setState(() {
          _progress = (args['value'] as num).toDouble();
          _progressText = '${args['current']} / ${args['total']}';
        });
      }
    });
  }

  Future<void> _selectFolder() async {
    final folder = Platform.isWindows
        ? await FilePicker.getDirectoryPath(dialogTitle: 'Medya klasörünü seç')
        : await _channel.invokeMethod<String>('pickFolder');
    if (folder != null && mounted) setState(() => _folder = folder);
  }

  Future<void> _openFile(String path) async {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', path]);
    } else {
      await _channel.invokeMethod('openFile', {'uri': path});
    }
  }

  Future<void> _run() async {
    if (_folder == null) return;
    if ((_organizeByYear || _separateScreenshots || _separateSnapchat) &&
        Platform.isWindows) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Dosyalar taşınacak'),
          content: const Text(
            'Tarih verilen dosyalar kaynak klasörden yıl klasörlerine taşınacak. Devam edilsin mi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Taşı'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _busy = true;
      _result = null;
      _progress = 0;
      _progressText = '';
      _cancelRequested = false;
    });
    try {
      if (Platform.isWindows) {
        await _runWindows();
        return;
      }
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'fixDates',
        {
          'snapUnix': _snapUnix,
          'assignUnknown': _assignUnknownSnap,
          'fallbackDate': _fallbackDate?.toIso8601String(),
        },
      );
      if (mounted) setState(() => _result = result);
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message ?? error.code)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _requestCancel() {
    if (_busy) {
      setState(() => _cancelRequested = true);
      if (!Platform.isWindows) _channel.invokeMethod('cancel');
    }
  }

  Future<void> _runWindows() async {
    final root = Directory(_folder!);
    final tool = File(_exifTool.text);
    if (!tool.existsSync()) {
      throw PlatformException(
        code: 'EXIFTOOL',
        message: 'ExifTool yolu bulunamadı.',
      );
    }
    final extensions = {
      '.jpg',
      '.jpeg',
      '.png',
      '.heic',
      '.webp',
      '.mp4',
      '.mov',
      '.m4v',
      '.3gp',
    };
    final files = <File>[];
    await for (final entity in root.list(
      recursive: _includeSubfolders,
      followLinks: false,
    )) {
      if (entity is File &&
          !entity.path.contains(
            '${Platform.pathSeparator}_Karantina${Platform.pathSeparator}',
          ) &&
          extensions.contains(
            '.${entity.path.split('.').last.toLowerCase()}',
          )) {
        files.add(entity);
      }
    }
    if (_findDuplicates) await _findAndQuarantineDuplicates(root, files);
    var written = 0, failed = 0, noDate = 0;
    final okFiles = <String>[];
    final problemFiles = <String>[];
    final compact = RegExp(
      r'(?<!\d)(20\d{2})([01]\d)([0-3]\d)[_ -]?([0-2]\d)([0-5]\d)([0-5]\d)',
    );
    final dashed = RegExp(
      r'(?<!\d)(20\d{2})-([01]\d)-([0-3]\d)[_ -]?(?:saat )?([0-2]\d)[-:.]?([0-5]\d)[-:.]?([0-5]\d)',
    );
    final millis = RegExp(r'(?<!\d)(1[5-9]\d{11}|20\d{11})(?!\d)');
    DateTime? parse(String name) {
      final isSnapchat = name.toLowerCase().startsWith('snapchat-');
      final match = compact.firstMatch(name) ?? dashed.firstMatch(name);
      if (match != null) {
        try {
          return DateTime.parse(
            '${match.group(1)}-${match.group(2)}-${match.group(3)} ${match.group(4)}:${match.group(5)}:${match.group(6)}',
          );
        } catch (_) {}
      }
      final dateOnly = RegExp(
        r'(?<!\d)(20\d{2})[-_. ]?([01]\d)[-_. ]?([0-3]\d)(?!\d)',
      ).firstMatch(name);
      if (dateOnly != null) {
        try {
          return DateTime(
            int.parse(dateOnly.group(1)!),
            int.parse(dateOnly.group(2)!),
            int.parse(dateOnly.group(3)!),
          );
        } catch (_) {}
      }
      final ms = millis.firstMatch(name);
      if (ms != null) {
        return DateTime.fromMillisecondsSinceEpoch(int.parse(ms.group(1)!));
      }
      if (_snapUnix && !isSnapchat) {
        final number = RegExp(r'(?<!\d)(\d{9,10})(?!\d)').firstMatch(name);
        if (number != null) {
          final date = DateTime.fromMillisecondsSinceEpoch(
            int.parse(number.group(1)!) * 1000,
          );
          if (date.year >= 1970 && date.year <= 2100) return date;
        }
      }
      return null;
    }

    var assigned = 0;
    final jobs = <Map<String, dynamic>>[];
    for (final file in files) {
      final parsed = parse(file.uri.pathSegments.last);
      final date =
          parsed ??
          (_assignUnknownSnap && _fallbackDate != null
              ? _fallbackDate!.add(Duration(minutes: assigned++))
              : null);
      if (date == null) {
        noDate++;
        problemFiles.add(file.path);
        final lowerName = file.uri.pathSegments.last.toLowerCase();
        final isScreenshot =
            lowerName.contains('screenshot') ||
            lowerName.contains('screen_shot') ||
            lowerName.contains('screencap') ||
            lowerName.startsWith('ss_');
        final isSnapchat = lowerName.startsWith('snapchat-');
        if ((_separateScreenshots && isScreenshot) ||
            (_separateSnapchat && isSnapchat)) {
          final folderName = isSnapchat ? 'Snapchat' : 'Screenshots';
          final folder = Directory(
            '${root.path}${Platform.pathSeparator}$folderName${Platform.pathSeparator}Tarihsiz',
          );
          await folder.create(recursive: true);
          var target = File(
            '${folder.path}${Platform.pathSeparator}${file.uri.pathSegments.last}',
          );
          var n = 1;
          while (await target.exists()) {
            target = File(
              '${folder.path}${Platform.pathSeparator}${n++}_${file.uri.pathSegments.last}',
            );
          }
          await file.rename(target.path);
        }
        continue;
      }
      jobs.add({'file': file, 'date': date});
    }
    var completed = noDate;
    Future<void> processJob(Map<String, dynamic> job) async {
      final file = job['file'] as File;
      final date = job['date'] as DateTime;
      final value =
          '${date.year.toString().padLeft(4, '0')}:${date.month.toString().padLeft(2, '0')}:${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
      final isVideo = {
        '.mp4',
        '.mov',
        '.m4v',
        '.3gp',
      }.contains('.${file.path.split('.').last.toLowerCase()}');
      final result = await Process.run(_exifTool.text, [
        '-overwrite_original',
        '-P',
        '-m',
        '-EXIF:DateTimeOriginal=$value',
        '-EXIF:CreateDate=$value',
        '-EXIF:ModifyDate=$value',
        '-XMP:DateCreated=$value',
        '-XMP:CreateDate=$value',
        '-XMP:ModifyDate=$value',
        if (isVideo) '-QuickTime:CreateDate=$value',
        if (isVideo) '-QuickTime:ModifyDate=$value',
        if (isVideo) '-Keys:CreationDate=$value',
        file.path,
      ]);
      if (result.exitCode == 0) {
        written++;
        okFiles.add(file.path);
        await file.setLastModified(date);
        final lowerName = file.uri.pathSegments.last.toLowerCase();
        final isScreenshot =
            lowerName.contains('screenshot') ||
            lowerName.contains('screen_shot') ||
            lowerName.contains('screencap') ||
            lowerName.startsWith('ss_');
        final isSnapchat = lowerName.startsWith('snapchat-');
        if (_organizeByYear ||
            (_separateScreenshots && isScreenshot) ||
            (_separateSnapchat && isSnapchat)) {
          final parts = <String>[];
          if (_separateScreenshots && isScreenshot) parts.add('Screenshots');
          if (_separateSnapchat && isSnapchat) parts.add('Snapchat');
          if (_organizeByYear) parts.add(date.year.toString());
          final folder = Directory(
            '${root.path}${Platform.pathSeparator}${parts.join(Platform.pathSeparator)}',
          );
          await folder.create(recursive: true);
          var target = File(
            '${folder.path}${Platform.pathSeparator}${file.uri.pathSegments.last}',
          );
          if (target.path.toLowerCase() != file.path.toLowerCase()) {
            var n = 1;
            while (await target.exists()) {
              target = File(
                '${folder.path}${Platform.pathSeparator}${n++}_${file.uri.pathSegments.last}',
              );
            }
            await file.rename(target.path);
          }
        }
      } else {
        failed++;
        problemFiles.add(file.path);
      }
      completed++;
      if (mounted && (completed % 10 == 0 || completed == files.length)) {
        setState(() {
          _progress = completed / files.length;
          _progressText = '$completed / ${files.length}';
        });
      }
    }

    for (var i = 0; i < jobs.length; i += 4) {
      if (_cancelRequested) break;
      final end = (i + 4 < jobs.length) ? i + 4 : jobs.length;
      await Future.wait(jobs.sublist(i, end).map(processJob));
    }
    if (mounted) {
      setState(
        () => _result = {
          'total': files.length,
          'written': written,
          'noDate': noDate,
          'assigned': assigned,
          'failed': failed,
          'okFiles': okFiles,
          'problemFiles': problemFiles,
        },
      );
    }
  }

  Future<void> _findAndQuarantineDuplicates(
    Directory root,
    List<File> files,
  ) async {
    final seen = <String, File>{};
    final quarantineDir = Directory(
      '${root.path}${Platform.pathSeparator}_Karantina',
    );
    for (final file in List<File>.from(files)) {
      final digest = (await sha256.bind(file.openRead()).first).toString();
      final original = seen[digest];
      if (original == null) {
        seen[digest] = file;
        continue;
      }
      await quarantineDir.create(recursive: true);
      var target = File(
        '${quarantineDir.path}${Platform.pathSeparator}${file.uri.pathSegments.last}',
      );
      var n = 1;
      while (await target.exists()) {
        target = File(
          '${quarantineDir.path}${Platform.pathSeparator}${n++}_${file.uri.pathSegments.last}',
        );
      }
      final moved = await file.rename(target.path);
      _quarantine[moved.path] = original.path;
      _selectedQuarantine.add(moved.path);
      files.remove(file);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Foto Tarih Düzenleyici'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildActionSection(),
            const SizedBox(height: 20),
            _buildSettingsSection(),
            const SizedBox(height: 20),
            if (_busy) _buildProgressSection(),
            if (result != null) _buildResultSection(result),
            if (_quarantine.isNotEmpty) _buildQuarantineSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Foto Tarih Düzenleyici',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(
        'Dosya adındaki tarihleri medyanın içine gömer ve organize eder.',
        style: TextStyle(color: Colors.grey[600], fontSize: 15),
      ),
    ],
  );

  Widget _buildActionSection() => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Colors.grey.shade300),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _selectFolder,
            icon: const Icon(Icons.folder_open),
            label: const Text('Medya Klasörünü Seç'),
          ),
          if (_folder != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '📍 $_folder',
                style: const TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          if (Platform.isWindows)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: TextField(
                controller: _exifTool,
                decoration: const InputDecoration(
                  labelText: 'ExifTool Yolu',
                  prefixIcon: Icon(Icons.terminal),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || _folder == null ? null : _run,
            icon: const Icon(Icons.auto_fix_high),
            label: Text(_busy ? 'İşleniyor…' : 'Tarihleri Dosyaya Yaz'),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: _cancelRequested ? null : _requestCancel,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(
                  _cancelRequested ? 'Durduruluyor…' : 'İşlemi Durdur',
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _buildSettingsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Ayarlar',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Unix zaman damgalarını çöz'),
                subtitle: const Text(
                  'Dosya adında Unix zaman damgası varsa tarihe çevirir.',
                ),
                value: _snapUnix,
                onChanged: _busy ? null : (v) => setState(() => _snapUnix = v),
              ),
              SwitchListTile(
                title: const Text('Sadece Snapchatleri ayır'),
                subtitle: const Text(
                  'Snapchat dosyalarını ayrı klasöre taşır.',
                ),
                value: _separateSnapchat,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _separateSnapchat = v),
              ),
              SwitchListTile(
                title: const Text('Ekran görüntülerini ayır'),
                subtitle: const Text(
                  'Screenshot, ScreenCap vb. dosyaları ayırır.',
                ),
                value: _separateScreenshots,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _separateScreenshots = v),
              ),
              SwitchListTile(
                title: const Text('Birebir kopyaları bul'),
                subtitle: const Text(
                  'Aynı içerikli dosyaları karantinaya taşır.',
                ),
                value: _findDuplicates,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _findDuplicates = v),
              ),
              SwitchListTile(
                title: const Text('Yıllara göre ayır'),
                subtitle: const Text(
                  'Başarılı dosyaları yıl klasörlerine taşır.',
                ),
                value: _organizeByYear,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _organizeByYear = v),
              ),
              SwitchListTile(
                title: const Text('Alt klasörleri tara'),
                subtitle: const Text('Tüm alt dizinleri işleme dahil eder.'),
                value: _includeSubfolders,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _includeSubfolders = v),
              ),
              SwitchListTile(
                title: const Text('Tarihi bulunamayanlara tarih ata'),
                subtitle: const Text('Tarih yoksa seçilen tarihe ayarlar.'),
                value: _assignUnknownSnap,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _assignUnknownSnap = v),
              ),
              if (_assignUnknownSnap)
                ListTile(
                  leading: const Icon(Icons.event),
                  title: Text(
                    _fallbackDate == null
                        ? 'Varsayılan tarih seç'
                        : 'Varsayılan tarih: ${_fallbackDate!.day}.${_fallbackDate!.month}.${_fallbackDate!.year}',
                  ),
                  onTap: _busy
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            firstDate: DateTime(1970),
                            lastDate: DateTime(2100),
                            initialDate: _fallbackDate ?? DateTime.now(),
                          );
                          if (picked != null) {
                            setState(() => _fallbackDate = picked);
                          }
                        },
                ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _buildProgressSection() => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Colors.grey.shade300),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: _progress,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 8),
          Text(
            '${(_progress * 100).toStringAsFixed(1)}%  $_progressText',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ),
  );

  Widget _buildResultSection(Map<String, dynamic> result) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Colors.grey.shade300),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'İşlem Sonucu',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statItem('Taranan', result['total']),
              _statItem('Başarılı', result['written'], Colors.green),
              _statItem('Hatalı', result['failed'], Colors.red),
            ],
          ),
          const SizedBox(height: 16),
          _fileList('Problemsiz dosyalar', result['okFiles'], Colors.green),
          _fileList('Problemli dosyalar', result['problemFiles'], Colors.red),
          const SizedBox(height: 12),
          const Text(
            'Not: JPEG/PNG/HEIC için EXIF tarihleri yazılır. MP4/MOV video QuickTime tarihleri Windows’ta desteklenir.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    ),
  );

  Widget _statItem(String label, dynamic value, [Color? color]) => Column(
    children: [
      Text(
        value.toString(),
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ],
  );

  Widget _buildQuarantineSection() => Card(
    color: Colors.amber.shade50,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Colors.amber.shade200),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Karantina: ${_quarantine.length} Kopya',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Birebir kopyalar buraya taşındı. Silmek veya geri almak için seçin.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(
                  () => _selectedQuarantine.addAll(_quarantine.keys),
                ),
                child: const Text('Tümünü seç'),
              ),
              TextButton(
                onPressed: () => setState(() => _selectedQuarantine.clear()),
                child: const Text('Seçimi kaldır'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _selectedQuarantine.isEmpty
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Onay'),
                            content: Text(
                              '${_selectedQuarantine.length} dosya kalıcı olarak silinecek.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('İptal'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('SİL'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          for (final p in List<String>.from(
                            _selectedQuarantine,
                          )) {
                            final f = File(p);
                            if (await f.exists()) await f.delete();
                            _quarantine.remove(p);
                          }
                          setState(() => _selectedQuarantine.clear());
                        }
                      },
                icon: const Icon(Icons.delete),
                label: const Text('SİL'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: ListView(
              children: _quarantine.entries
                  .map(
                    (entry) => ListTile(
                      dense: true,
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _selectedQuarantine.contains(entry.key),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selectedQuarantine.add(entry.key);
                              } else {
                                _selectedQuarantine.remove(entry.key);
                              }
                            }),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(
                              File(entry.key),
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.copy, color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                      title: Text(
                        entry.key.split(Platform.pathSeparator).last,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: const Text('Birebir kopya'),
                      trailing: IconButton(
                        icon: const Icon(Icons.restore),
                        tooltip: 'Geri al',
                        onPressed: () async {
                          final f = File(entry.key);
                          if (await f.exists()) {
                            final original = File(entry.value);
                            var target = File(
                              '${original.parent.path}${Platform.pathSeparator}${f.uri.pathSegments.last}',
                            );
                            var n = 1;
                            while (await target.exists()) {
                              target = File(
                                '${original.parent.path}${Platform.pathSeparator}${n++}_${f.uri.pathSegments.last}',
                              );
                            }
                            await f.rename(target.path);
                            setState(() => _quarantine.remove(entry.key));
                          }
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _fileList(String title, dynamic value, Color color) {
    final files = value is List
        ? value.map((e) => e.toString()).toList()
        : <String>[];
    return ExpansionTile(
      leading: Icon(Icons.photo_library, color: color),
      title: Text('$title (${files.length})'),
      children: [
        SizedBox(
          height: files.isEmpty ? 0 : 220,
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (_, i) {
              final path = files[i];
              return ListTile(
                dense: true,
                onTap: () => _openFile(path),
                leading: Platform.isWindows
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(path),
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(Icons.image),
                        ),
                      )
                    : const Icon(Icons.image_outlined),
                title: Text(
                  path.split(Platform.pathSeparator).last,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Konumu açmak için dokun',
                  style: TextStyle(color: color, fontSize: 11),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
