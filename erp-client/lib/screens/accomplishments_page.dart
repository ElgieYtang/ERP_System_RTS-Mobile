import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../navigation/app_navigation.dart';
import '../navigation/module_navigation_scope.dart';
import '../services/accomplishment_pdf.dart';
import '../services/api_client.dart';
import '../services/api_errors.dart';
import '../services/offline_cache.dart';
import '../services/transaction_actions.dart';
import '../theme/app_theme.dart';
import '../widgets/field_ui.dart';

class AccomplishmentsPage extends StatefulWidget {
  const AccomplishmentsPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<AccomplishmentsPage> createState() => _AccomplishmentsPageState();
}

class _AccomplishmentsPageState extends State<AccomplishmentsPage> {
  bool _loading = true;
  bool _creating = false;
  bool _fromCache = false;
  String? _busyId;
  String? _error;
  String? _offlineLabel;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _projects = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final wasOffline = _fromCache;
    setState(() {
      _loading = true;
      _error = null;
      _fromCache = false;
      _offlineLabel = null;
    });
    try {
      final reports = await widget.api.getList('/accomplishments');
      final projects = await widget.api.getList('/setup/projects');
      await OfflineCache.saveList(OfflineCache.accomplishments, reports);
      await OfflineCache.saveList(OfflineCache.projects, projects);
      if (!mounted) return;
      setState(() {
        _rows = reports
            .cast<Map<String, dynamic>>()
            .where((r) => r['status'] != 'inactive')
            .toList();
        _projects = projects.cast<Map<String, dynamic>>();
        _loading = false;
      });
      if (wasOffline && mounted) fieldShowBackOnlineSnackBar(context);
    } catch (error) {
      final cached = await OfflineCache.loadList(OfflineCache.accomplishments);
      final cachedProjects = await OfflineCache.loadList(OfflineCache.projects);
      if (!mounted) return;
      if (cached.rows.isNotEmpty) {
        setState(() {
          _rows = cached.rows.where((r) => r['status'] != 'inactive').toList();
          _projects = cachedProjects.rows;
          _fromCache = true;
          _offlineLabel = OfflineCache.staleLabel(cached.savedAt);
          _error = null;
          _loading = false;
        });
      } else {
        setState(() {
          _error = friendlyApiError(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _createReport() async {
    if (_creating) return;
    if (_fromCache) {
      fieldShowOfflineBlocked(context);
      return;
    }
    if (_projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No projects available. Connect to load projects.')),
      );
      return;
    }

    String? projectId = _projects.first['id']?.toString();
    final remarksController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('New accomplishment'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: projectId,
                    items: _projects
                        .map(
                          (p) => DropdownMenuItem(
                            value: p['id']?.toString(),
                            child: Text(
                              p['name']?.toString() ?? 'Project',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setLocal(() => projectId = value),
                    decoration: const InputDecoration(labelText: 'Project'),
                  ),
                  TextField(
                    controller: remarksController,
                    decoration: const InputDecoration(labelText: 'Remarks (optional)'),
                    maxLines: 2,
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
              ],
            );
          },
        );
      },
    );

    final remarks = remarksController.text.trim();
    remarksController.dispose();

    if (created != true || projectId == null) return;

    setState(() => _creating = true);
    try {
      final payload = await widget.api.post('/accomplishments', {
        'projectId': int.tryParse(projectId!) ?? projectId,
        'remarks': remarks.isEmpty ? null : remarks,
        'status': 'pending',
      });
      final report = payload['data'] as Map<String, dynamic>?;
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      if (report != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => wrapModuleNavigationScope(
              context,
              AccomplishmentDetailPage(
                api: widget.api,
                reportId: report['dbId']?.toString() ?? report['id'].toString(),
              ),
            ),
          ),
        );
        if (mounted) await _load();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _approve(Map<String, dynamic> row) async {
    if (_fromCache) {
      fieldShowOfflineBlocked(context);
      return;
    }
    final id = fieldRowId(row);
    if (id.isEmpty || _busyId != null) return;
    if (!canApproveAccomplishment(row)) return;

    setState(() => _busyId = id);
    try {
      await widget.api.put('/accomplishments/$id', {'status': 'approved'});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report approved.')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _rows.isEmpty && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating || _fromCache ? null : _createReport,
        icon: const Icon(Icons.add),
        label: Text(_creating ? 'Creating…' : 'New'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            if (_fromCache && _offlineLabel != null)
              FieldOfflineBanner(
                label: _offlineLabel!,
                hint: OfflineCache.offlineReconnectHint,
              ),
            if (_error != null && !_fromCache) FieldErrorBanner(message: _error!, onRetry: _load),
            if (_rows.isEmpty && (_error == null || _fromCache))
              const FieldEmptyState(
                icon: Icons.photo_camera_outlined,
                title: 'No reports yet',
              ),
            ..._rows.map((row) {
              final id = fieldRowId(row);
              final imageCount = (row['images'] as List<dynamic>? ?? const []).length;
              final status = row['status']?.toString() ?? '';
              final canApprove = canApproveAccomplishment(row) && !_fromCache;
              final busy = _busyId == id;

              return Card(
                child: InkWell(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => wrapModuleNavigationScope(
                          context,
                          AccomplishmentDetailPage(
                            api: widget.api,
                            reportId: row['dbId']?.toString() ?? row['id'].toString(),
                            offline: _fromCache,
                            initialReport: row,
                            offlineLabel: _offlineLabel,
                          ),
                        ),
                      ),
                    );
                    await _load();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                row['id']?.toString() ?? 'AR',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                            ),
                            if (!canApprove) FieldStatusChip(status),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${row['projectName'] ?? '—'} · '
                          '${row['displayDate'] ?? row['date'] ?? '—'}',
                        ),
                        Text('$imageCount photo(s)'),
                        if (canApprove) ...[
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: busy ? null : () => _approve(row),
                            child: Text(busy ? 'Approving…' : 'Approve'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 72),
          ],
        ),
      ),
    );
  }
}

class AccomplishmentDetailPage extends StatefulWidget {
  const AccomplishmentDetailPage({
    super.key,
    required this.api,
    required this.reportId,
    this.offline = false,
    this.initialReport,
    this.offlineLabel,
  });

  final ApiClient api;
  final String reportId;
  final bool offline;
  final Map<String, dynamic>? initialReport;
  final String? offlineLabel;

  @override
  State<AccomplishmentDetailPage> createState() => _AccomplishmentDetailPageState();
}

class _AccomplishmentDetailPageState extends State<AccomplishmentDetailPage> {
  static const _photosPerPage = 4;

  bool _loading = true;
  bool _uploading = false;
  bool _exportingPdf = false;
  int _photoPage = 1;
  String? _error;
  String? _uploadProgress;
  Map<String, dynamic>? _report;
  final Map<String, Uint8List> _photoBytes = {};

  List<MapEntry<String, Uint8List>> get _orderedPhotos {
    final images =
        (_report?['images'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final entries = <MapEntry<String, Uint8List>>[];
    for (final image in images) {
      final id = image['id']?.toString();
      if (id != null && _photoBytes.containsKey(id)) {
        entries.add(MapEntry(id, _photoBytes[id]!));
      }
    }
    return entries;
  }

  int get _photoPageCount {
    final count = _orderedPhotos.length;
    if (count == 0) return 1;
    return (count / _photosPerPage).ceil();
  }

  List<MapEntry<String, Uint8List>> get _visiblePhotos {
    final start = (_photoPage - 1) * _photosPerPage;
    return _orderedPhotos.skip(start).take(_photosPerPage).toList();
  }

  void _clampPhotoPage() {
    final maxPage = _photoPageCount;
    if (_photoPage > maxPage) {
      _photoPage = maxPage;
    }
    if (_photoPage < 1) {
      _photoPage = 1;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _fetchReport() async {
    final ref = widget.reportId;
    try {
      return await widget.api.getOne('/accomplishments/${Uri.encodeComponent(ref)}');
    } catch (_) {
      final rows = await widget.api.getList('/accomplishments');
      for (final row in rows) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        if (map['dbId']?.toString() == ref || map['id']?.toString() == ref) {
          return map;
        }
      }
      rethrow;
    }
  }

  Future<void> _syncListCacheRow(Map<String, dynamic> report) async {
    try {
      final cached = await OfflineCache.loadList(OfflineCache.accomplishments);
      final id = report['dbId']?.toString() ?? report['id']?.toString();
      var found = false;
      final rows = cached.rows.map((row) {
        final rowId = row['dbId']?.toString() ?? row['id']?.toString();
        if (rowId == id) {
          found = true;
          return Map<String, dynamic>.from({...row, ...report});
        }
        return row;
      }).toList();
      if (!found) {
        rows.insert(0, Map<String, dynamic>.from(report));
      }
      await OfflineCache.saveList(OfflineCache.accomplishments, rows);
    } catch (_) {}
  }

  Future<void> _hydratePhotoBytes(
    Map<String, dynamic> report, {
    Map<String, Uint8List>? preserveBytes,
  }) async {
    final images =
        (report['images'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final bytes = <String, Uint8List>{};
    if (preserveBytes != null) {
      bytes.addAll(preserveBytes);
    }
    for (final image in images) {
      final id = image['id']?.toString();
      final src = image['src']?.toString();
      if (id == null || src == null) continue;
      if (bytes.containsKey(id)) continue;
      try {
        bytes[id] = await widget.api.getBytes(src);
      } catch (_) {
        // Skip broken photo.
      }
    }
    if (!mounted) return;
    setState(() {
      _report = Map<String, dynamic>.from(report);
      _photoBytes
        ..clear()
        ..addAll(bytes);
      _clampPhotoPage();
    });
  }

  Future<void> _applyReport(
    Map<String, dynamic> report, {
    Map<String, Uint8List>? preserveBytes,
  }) async {
    await OfflineCache.saveAccomplishmentDetail(widget.reportId, report);
    await _syncListCacheRow(report);
    await _hydratePhotoBytes(report, preserveBytes: preserveBytes);
  }

  Future<bool> _loadFromCacheOrInitial() async {
    final cached = await OfflineCache.loadAccomplishmentDetail(widget.reportId);
    final report = cached.data ?? widget.initialReport;
    if (report == null || !mounted) return false;
    await _hydratePhotoBytes(Map<String, dynamic>.from(report));
    if (!mounted) return false;
    setState(() {
      _loading = false;
      _error = null;
    });
    return true;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (widget.offline) {
      final loaded = await _loadFromCacheOrInitial();
      if (!mounted) return;
      if (!loaded) {
        setState(() {
          _error = 'Report details are not saved offline yet. Connect to load this report.';
          _loading = false;
        });
      }
      return;
    }

    try {
      final report = await _fetchReport();
      await _applyReport(report);
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      final loaded = await _loadFromCacheOrInitial();
      if (!mounted) return;
      if (loaded) return;
      setState(() {
        _error = friendlyApiError(error);
        _loading = false;
      });
    }
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    if (widget.offline) {
      fieldShowOfflineBlocked(context);
      return;
    }
    if (_uploading) return;
    final picker = ImagePicker();
    final files = source == ImageSource.gallery
        ? await picker.pickMultiImage(imageQuality: 75)
        : [
            if (await picker.pickImage(source: ImageSource.camera, imageQuality: 75) case final file?)
              file,
          ];

    if (files.isEmpty) return;

    setState(() {
      _uploading = true;
      _uploadProgress = 'Preparing photos…';
    });
    try {
      final payload = <({String filename, Uint8List bytes})>[];
      for (final file in files) {
        final bytes = await file.readAsBytes();
        payload.add((filename: file.name.isEmpty ? 'photo.jpg' : file.name, bytes: bytes));
      }
      final id = _report?['dbId']?.toString() ?? widget.reportId;
      setState(() => _uploadProgress = 'Uploading (retries on weak signal)…');
      final response = await widget.api.uploadPhotos(accomplishmentId: id, files: payload);
      if (!mounted) return;
      final data = response['data'];
      if (data is Map) {
        final fresh = Map<String, dynamic>.from(data);
        final preview = <String, Uint8List>{..._photoBytes};
        final images =
            (fresh['images'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
        var fileIndex = 0;
        for (final image in images) {
          final imageId = image['id']?.toString();
          if (imageId == null || preview.containsKey(imageId)) continue;
          if (fileIndex < payload.length) {
            preview[imageId] = payload[fileIndex].bytes;
            fileIndex++;
          }
        }
        await _applyReport(fresh, preserveBytes: preview);
      } else {
        await _load();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photos uploaded')),
      );
      setState(() => _photoPage = _photoPageCount);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyApiError(error)),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _pickAndUpload(source),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _exportPdf() async {
    final report = _report;
    if (report == null || _exportingPdf) return;
    if (widget.offline) {
      fieldShowOfflineBlocked(context);
      return;
    }

    setState(() => _exportingPdf = true);
    try {
      final bytes = await AccomplishmentPdf.build(
        report: report,
        photoBytes: _photoBytes,
      );
      final filename = '${report['id'] ?? 'accomplishment'}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create PDF: $error')),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _editReport() async {
    final report = _report;
    if (report == null || !canEditAccomplishment(report)) return;
    if (widget.offline) {
      fieldShowOfflineBlocked(context);
      return;
    }

    final result = await showDialog<({DateTime date, String remarks})>(
      context: context,
      builder: (_) => _EditAccomplishmentDialog(
        initialRemarks: report['remarks']?.toString() ?? '',
        initialDate: DateTime.tryParse(report['date']?.toString() ?? '') ?? DateTime.now(),
      ),
    );
    if (result == null || !mounted) return;

    final id = report['dbId']?.toString() ?? widget.reportId;
    final dateStr =
        '${result.date.year}-${result.date.month.toString().padLeft(2, '0')}-${result.date.day.toString().padLeft(2, '0')}';

    try {
      await widget.api.put('/accomplishments/$id', {
        'date': dateStr,
        'remarks': result.remarks.isEmpty ? null : result.remarks,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report updated.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
  }

  Future<void> _deletePhoto(String photoId) async {
    if (widget.offline) {
      fieldShowOfflineBlocked(context);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete photo?'),
        content: const Text('This removes the photo from the server.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    final id = _report?['dbId']?.toString() ?? widget.reportId;
    try {
      await widget.api.request('DELETE', '/accomplishments/$id/photos/$photoId');
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;

    return Scaffold(
      appBar: transactionAppBar(
        context,
        title: report?['id']?.toString() ?? 'Accomplishment',
        showBack: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : report == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: FieldErrorBanner(
                      message: _error ?? 'Report not found',
                      onRetry: _load,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (widget.offline && widget.offlineLabel != null)
                      FieldOfflineBanner(
                        label: widget.offlineLabel!,
                        hint: OfflineCache.offlineReconnectHint,
                      ),
                    if (widget.offline)
                      const Card(
                        color: AppTheme.maroonLight,
                        margin: EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.info_outline_rounded, color: AppTheme.maroon),
                          title: Text(
                            'Offline — photos and edits need a connection.',
                            style: TextStyle(fontSize: 13, height: 1.35),
                          ),
                        ),
                      ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    report['projectName']?.toString() ?? 'Project',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FieldStatusChip(report['status']?.toString()),
                              ],
                            ),
                            const SizedBox(height: 12),
                            FieldDetailMeta(
                              rows: [
                                if ((report['location']?.toString() ?? '').isNotEmpty)
                                  (label: 'Location', value: report['location'].toString()),
                                (
                                  label: 'Date',
                                  value: report['displayDate']?.toString() ??
                                      report['date']?.toString() ??
                                      '—',
                                ),
                              ],
                            ),
                            if ((report['remarks']?.toString() ?? '').isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                report['remarks'].toString(),
                                style: const TextStyle(fontSize: 14, height: 1.5),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: FieldDetailActions(
                          secondary: [
                            if (!widget.offline && canEditAccomplishment(report))
                              OutlinedButton.icon(
                                onPressed: _editReport,
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Edit report'),
                              ),
                            if (!widget.offline)
                              OutlinedButton.icon(
                                onPressed: _exportingPdf ? null : _exportPdf,
                                icon: _exportingPdf
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.picture_as_pdf_outlined),
                                label: Text(_exportingPdf ? 'Creating PDF…' : 'Print PDF'),
                              ),
                          ],
                          primary: [
                            if (!widget.offline)
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _uploading
                                          ? null
                                          : () => _pickAndUpload(ImageSource.camera),
                                      icon: const Icon(Icons.photo_camera),
                                      label: const Text('Camera'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton.tonalIcon(
                                      onPressed: _uploading
                                          ? null
                                          : () => _pickAndUpload(ImageSource.gallery),
                                      icon: const Icon(Icons.photo_library),
                                      label: const Text('Gallery'),
                                    ),
                                  ),
                                ],
                              ),
                            if (!widget.offline && _uploading) ...[
                              const SizedBox(height: 12),
                              const LinearProgressIndicator(),
                              const SizedBox(height: 6),
                              Text(
                                _uploadProgress ?? 'Uploading…',
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_orderedPhotos.isEmpty)
                      const FieldEmptyState(
                        icon: Icons.image_outlined,
                        title: 'No photos yet',
                      )
                    else ...[
                      Text(
                        '${_orderedPhotos.length} photo${_orderedPhotos.length == 1 ? '' : 's'}'
                        '${_photoPageCount > 1 ? ' · page $_photoPage of $_photoPageCount' : ''}'
                        ' (max $_photosPerPage per page)',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                      if (_photoPageCount > 1) ...[
                        const SizedBox(height: 10),
                        _PhotoPageSelector(
                          pageCount: _photoPageCount,
                          currentPage: _photoPage,
                          onPageSelected: (page) => setState(() => _photoPage = page),
                        ),
                      ],
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1,
                        ),
                        itemCount: _visiblePhotos.length,
                        itemBuilder: (context, index) {
                          final entry = _visiblePhotos[index];
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.memory(entry.value, fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: IconButton.filled(
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                    minimumSize: const Size(32, 32),
                                  ),
                                  onPressed: widget.offline ? null : () => _deletePhoto(entry.key),
                                  icon: const Icon(Icons.close, color: Colors.white, size: 16),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _EditAccomplishmentDialog extends StatefulWidget {
  const _EditAccomplishmentDialog({
    required this.initialRemarks,
    required this.initialDate,
  });

  final String initialRemarks;
  final DateTime initialDate;

  @override
  State<_EditAccomplishmentDialog> createState() => _EditAccomplishmentDialogState();
}

class _EditAccomplishmentDialogState extends State<_EditAccomplishmentDialog> {
  late final TextEditingController _remarksController;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _remarksController = TextEditingController(text: widget.initialRemarks);
    _selectedDate = widget.initialDate;
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  void _save() {
    Navigator.pop(
      context,
      (date: _selectedDate, remarks: _remarksController.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit report'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(
                '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _remarksController,
              decoration: const InputDecoration(
                labelText: 'Remarks',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _PhotoPageSelector extends StatelessWidget {
  const _PhotoPageSelector({
    required this.pageCount,
    required this.currentPage,
    required this.onPageSelected,
  });

  final int pageCount;
  final int currentPage;
  final ValueChanged<int> onPageSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: List.generate(pageCount, (index) {
        final page = index + 1;
        final active = page == currentPage;
        return FilledButton(
          onPressed: () => onPageSelected(page),
          style: FilledButton.styleFrom(
            backgroundColor: active ? AppTheme.maroon : Colors.white,
            foregroundColor: active ? Colors.white : AppTheme.maroon,
            side: const BorderSide(color: AppTheme.maroon),
            minimumSize: const Size(44, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          child: Text('$page'),
        );
      }),
    );
  }
}
