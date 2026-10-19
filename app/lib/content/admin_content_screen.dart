import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import 'content_repository.dart';
import 'course_cover_actions.dart';
import 'course_cover_panel.dart';
import 'course_image_selector.dart';
import 'material_repository.dart';
import 'admin_materials_panel.dart';

bool _canManage(AuthController auth) =>
    auth.stage == AuthStage.ready && auth.access?.role == 'admin';

class AdminContentScreen extends StatefulWidget {
  const AdminContentScreen({
    super.key,
    required this.repository,
    required this.authController,
    this.coverActions,
    this.imageSelector,
    this.materialRepository,
  });
  final ContentRepository repository;
  final AuthController authController;
  final CourseCoverActions? coverActions;
  final CourseImageSelector? imageSelector;
  final MaterialRepository? materialRepository;
  @override
  State<AdminContentScreen> createState() => _AdminContentScreenState();
}

class _AdminContentScreenState extends State<AdminContentScreen> {
  Key _workspaceKey = UniqueKey();
  void _authChanged() {
    // A closure followed by reopening before the next frame must still discard state.
    if (!_canManage(widget.authController)) _workspaceKey = UniqueKey();
  }

  @override
  void initState() {
    super.initState();
    widget.authController.addListener(_authChanged);
  }

  @override
  void didUpdateWidget(AdminContentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authController != widget.authController) {
      oldWidget.authController.removeListener(_authChanged);
      widget.authController.addListener(_authChanged);
    }
    if (oldWidget.authController != widget.authController ||
        oldWidget.repository != widget.repository ||
        oldWidget.coverActions != widget.coverActions ||
        oldWidget.imageSelector != widget.imageSelector) {
      _workspaceKey = UniqueKey();
    }
    if (oldWidget.materialRepository != widget.materialRepository) {
      _workspaceKey = UniqueKey();
    }
  }

  @override
  void dispose() {
    widget.authController.removeListener(_authChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.authController,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Course administration')),
      body: !_canManage(widget.authController)
          ? const Center(child: Text('Administrator access is required.'))
          : _AdminWorkspace(
              key: _workspaceKey,
              repository: widget.repository,
              auth: widget.authController,
              coverActions: widget.coverActions,
              imageSelector: widget.imageSelector,
              materialRepository: widget.materialRepository,
            ),
    ),
  );
}

class _AdminWorkspace extends StatefulWidget {
  const _AdminWorkspace({
    super.key,
    required this.repository,
    required this.auth,
    this.coverActions,
    this.imageSelector,
    this.materialRepository,
  });
  final ContentRepository repository;
  final AuthController auth;
  final CourseCoverActions? coverActions;
  final CourseImageSelector? imageSelector;
  final MaterialRepository? materialRepository;
  @override
  State<_AdminWorkspace> createState() => _AdminWorkspaceState();
}

class _AdminWorkspaceState extends State<_AdminWorkspace> {
  List<Course> _courses = [];
  List<CourseSession> _sessions = [];
  Course? _course;
  Course? _coverCourse;
  CourseSession? _materialSession;
  bool _includeDeleted = false, _busy = false, _hasNext = false;
  bool _confirming = false;
  int _offset = 0, _epoch = 0;
  String? _error;
  bool _editing = false;
  Course? _editingCourse;
  CourseSession? _editingSession;

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_authChanged);
    _load();
  }

  void _authChanged() {
    if (!_canManage(widget.auth)) {
      ++_epoch;
      _courses = [];
      _sessions = [];
      _course = null;
      _coverCourse = null;
      _materialSession = null;
      _editingCourse = null;
      _editingSession = null;
      _editing = false;
      _error = null;
    }
  }

  @override
  void dispose() {
    ++_epoch;
    widget.auth.removeListener(_authChanged);
    super.dispose();
  }

  bool _current(int epoch) =>
      mounted && _canManage(widget.auth) && _epoch == epoch;
  Future<void> _load() async {
    if (!_canManage(widget.auth)) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
      _hasNext = false;
    });
    try {
      final course = _course;
      if (course == null) {
        final rows = await widget.repository.listCourses(
          offset: _offset,
          includeDeleted: _includeDeleted,
        );
        if (!_current(epoch)) return;
        setState(() {
          _courses = rows;
          _hasNext = rows.length == contentPageSize;
        });
      } else {
        final rows = await widget.repository.listSessions(
          course.id,
          offset: _offset,
          includeDeleted: _includeDeleted,
        );
        if (!_current(epoch)) return;
        setState(() {
          _sessions = rows;
          _hasNext = rows.length == contentPageSize;
        });
      }
    } catch (_) {
      if (_current(epoch)) {
        setState(() {
          _error = 'Unable to load content. Check your connection and access, then retry.';
        });
      }
    } finally {
      if (_current(epoch)) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _navigate(Course? course) {
    setState(() {
      _course = course;
      _offset = 0;
      _courses = [];
      _sessions = [];
      _hasNext = false;
      _includeDeleted = false;
    });
    _load();
  }

  void _edit({Course? course, CourseSession? session}) {
    setState(() {
      _editing = true;
      _editingCourse = course;
      _editingSession = session;
    });
  }

  Future<void> _save(
    CourseDraft? courseDraft,
    SessionDraft? sessionDraft,
  ) async {
    if (_busy || !_canManage(widget.auth)) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (courseDraft != null) {
        await widget.repository.saveCourse(courseDraft, id: _editingCourse?.id);
      } else {
        await widget.repository.saveSession(
          _course!.id,
          sessionDraft!,
          id: _editingSession?.id,
        );
      }
      if (!_current(epoch)) return;
      setState(() {
        _editing = false;
        _editingCourse = null;
        _editingSession = null;
        _busy = false;
      });
      await _load();
    } catch (error) {
      if (_current(epoch)) {
        setState(() {
          _busy = false;
          _error = error is ContentFailure ? error.message : 'Unable to save content. Check your connection and access, then retry.';
        });
      }
    }
  }

  Future<void> _changeDeleted({Course? course, CourseSession? session}) async {
    if (_busy || !_canManage(widget.auth)) return;
    final deleted = !(course?.isDeleted ?? session!.isDeleted);
    final kind = course == null ? 'session' : 'course';
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _confirming = true;
      _error = null;
    });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AnimatedBuilder(
          animation: widget.auth,
          builder: (context, _) => AlertDialog(
            title: Text(
              !_canManage(widget.auth)
                  ? 'Access changed'
                  : '${deleted ? 'Delete' : 'Restore'} this $kind?',
            ),
            content: Text(
              !_canManage(widget.auth)
                  ? 'Close this dialog and verify administrator access again.'
                  : deleted
                  ? 'This is a recoverable deletion. The $kind will be hidden from students.${course != null ? ' Its sessions will also be hidden.' : ''}'
                  : 'The $kind will return to draft. Publish it explicitly when it is ready.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _canManage(widget.auth)
                    ? () => Navigator.pop(context, true)
                    : null,
                child: Text(deleted ? 'Confirm delete' : 'Confirm restore'),
              ),
            ],
          ),
        ),
      );
      if (!_current(epoch)) return;
      if (confirmed != true) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
        return;
      }
      setState(() => _confirming = false);
      if (course != null) {
        await widget.repository.setCourseDeleted(course.id, deleted);
      } else {
        await widget.repository.setSessionDeleted(
          _course!.id,
          session!.id,
          deleted,
        );
      }
      if (!_current(epoch)) return;
      setState(() {
        _offset = 0;
        _courses = [];
        _sessions = [];
        _busy = false;
      });
      await _load();
    } catch (_) {
      if (_current(epoch)) {
        setState(() {
          _busy = false;
          _error = 'Unable to change content visibility. Check your connection and access, then refresh before retrying.';
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_materialSession != null &&
        _course != null &&
        widget.materialRepository != null) {
      return AdminMaterialsPanel(
        key: ValueKey(_materialSession!.id),
        course: _course!,
        session: _materialSession!,
        auth: widget.auth,
        repository: widget.materialRepository!,
        onClose: () {
          setState(() => _materialSession = null);
          _load();
        },
      );
    }
    if (_coverCourse != null) {
      return CourseCoverPanel(
        key: ValueKey(_coverCourse!.id),
        course: _coverCourse!,
        auth: widget.auth,
        actions: widget.coverActions,
        selector: widget.imageSelector,
        onClose: () {
          setState(() => _coverCourse = null);
          _load();
        },
      );
    }
    if (_editing) {
      return _ContentEditor(
        auth: widget.auth,
        course: _editingCourse,
        session: _editingSession,
        forSession: _course != null,
        busy: _busy,
        error: _error,
        onSave: _save,
        onCancel: () => setState(() {
          _editing = false;
          _error = null;
          _editingCourse = null;
          _editingSession = null;
        }),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_course != null)
                OutlinedButton(
                  onPressed: _busy ? null : () => _navigate(null),
                  child: const Text('Back to courses'),
                ),
              Text(
                _course == null ? 'Courses' : 'Sessions: ${_course!.title}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              FilledButton(
                onPressed: _busy ? null : () => _edit(),
                child: Text(_course == null ? 'New course' : 'New session'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _load,
                child: const Text('Refresh'),
              ),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('Include deleted'),
          subtitle: const Text('Read-only; can be restored.'),
          value: _includeDeleted,
          onChanged: _busy
              ? null
              : (value) {
                  setState(() {
                    _includeDeleted = value;
                    _offset = 0;
                    _courses = [];
                    _sessions = [];
                  });
                  _load();
                },
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Semantics(liveRegion: true, child: Text(_error!)),
          ),
        if (_busy && !_confirming) const LinearProgressIndicator(),
        Expanded(child: _list()),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: _busy || _offset == 0
                      ? null
                      : () {
                          setState(() {
                            _offset -= contentPageSize;
                            _courses = [];
                            _sessions = [];
                          });
                          _load();
                        },
                  child: const Text('Previous'),
                ),
                Text('Page ${_offset ~/ contentPageSize + 1}'),
                TextButton(
                  onPressed: _busy || !_hasNext
                      ? null
                      : () {
                          setState(() {
                            _offset += contentPageSize;
                            _courses = [];
                            _sessions = [];
                          });
                          _load();
                        },
                  child: const Text('Next'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _list() {
    final count = _course == null ? _courses.length : _sessions.length;
    if (count == 0 && !_busy) {
      return const Center(child: Text('No content on this page.'));
    }
    return ListView.builder(
      itemCount: count,
      itemBuilder: (context, index) {
        if (_course == null) {
          final course = _courses[index];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${course.instructor} • ${course.category} • ${course.level}',
                  ),
                  Text(
                    '${formatPricePiasters(course.pricePiasters)} EGP • ${course.status.name}${course.isDeleted ? ' • Deleted' : ''}',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _busy || course.isDeleted
                            ? null
                            : () => setState(() => _coverCourse = course),
                        child: const Text('Course cover'),
                      ),
                      TextButton(
                        onPressed: _busy || course.isDeleted
                            ? null
                            : () => _edit(course: course),
                        child: const Text('Edit course'),
                      ),
                      TextButton(
                        onPressed: _busy || course.isDeleted
                            ? null
                            : () => _navigate(course),
                        child: const Text('Sessions'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _changeDeleted(course: course),
                        child: Text(
                          course.isDeleted ? 'Restore course' : 'Delete course',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
        final session = _sessions[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${session.sessionNumber}. ${session.title}'),
                Text(
                  '${formatPricePiasters(session.pricePiasters)} EGP • ${session.status.name}${session.isFreePreview ? ' • Free preview' : ''}${session.isDeleted ? ' • Deleted' : ''}',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy || session.isDeleted
                          ? null
                          : () => _edit(session: session),
                      child: const Text('Edit session'),
                    ),
                    if (widget.materialRepository != null)
                      TextButton(
                        onPressed:
                            _busy || session.isDeleted || _course!.isDeleted
                            ? null
                            : () => setState(() => _materialSession = session),
                        child: const Text('Materials'),
                      ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _changeDeleted(session: session),
                      child: Text(
                        session.isDeleted
                            ? 'Restore session'
                            : 'Delete session',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ContentEditor extends StatefulWidget {
  const _ContentEditor({
    required this.auth,
    required this.forSession,
    required this.busy,
    required this.error,
    required this.onSave,
    required this.onCancel,
    this.course,
    this.session,
  });
  final AuthController auth;
  final Course? course;
  final CourseSession? session;
  final bool forSession, busy;
  final String? error;
  final Future<void> Function(CourseDraft?, SessionDraft?) onSave;
  final VoidCallback onCancel;
  @override
  State<_ContentEditor> createState() => _ContentEditorState();
}

class _ContentEditorState extends State<_ContentEditor> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  late ContentStatus _status;
  late bool _preview;
  TextEditingController _field(String name) => _fields[name]!;
  @override
  void initState() {
    super.initState();
    final course = widget.course;
    final session = widget.session;
    final values = {
      'Title': course?.title ?? session?.title ?? '',
      'Description': course?.description ?? session?.description ?? '',
      'Instructor': course?.instructor ?? '',
      'Category': course?.category ?? '',
      'Level': course?.level ?? '',
      'Price (EGP)': formatPricePiasters(
        course?.pricePiasters ?? session?.pricePiasters ?? 0,
      ),
      'Position': '${course?.position ?? session?.position ?? 0}',
      'Session number': '${session?.sessionNumber ?? 1}',
    };
    for (final entry in values.entries) {
      _fields[entry.key] = TextEditingController(text: entry.value);
    }
    _status = course?.status ?? session?.status ?? ContentStatus.draft;
    _preview = session?.isFreePreview ?? false;
    widget.auth.addListener(_authChanged);
  }

  void _authChanged() {
    if (!_canManage(widget.auth)) {
      for (final controller in _fields.values) {
        controller.clear();
      }
      _status = ContentStatus.draft;
      _preview = false;
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_authChanged);
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _text(String label, int max, {bool required = true, int lines = 1}) =>
      TextFormField(
        controller: _field(label),
        enabled: !widget.busy,
        decoration: InputDecoration(labelText: label),
        maxLines: lines,
        validator: (value) =>
            validateContentText(value, label, max, required: required),
      );
  Widget _integer(String label, {bool positive = false}) => TextFormField(
    controller: _field(label),
    enabled: !widget.busy,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    validator: (value) => validateContentInteger(value, positive: positive),
  );
  void _submit() {
    if (widget.busy ||
        !_canManage(widget.auth) ||
        !_form.currentState!.validate()) {
      return;
    }
    final title = _field('Title').text;
    final description = _field('Description').text;
    final price = parsePricePiasters(_field('Price (EGP)').text)!;
    final position = int.parse(_field('Position').text.trim());
    if (widget.forSession) {
      widget.onSave(
        null,
        SessionDraft(
          title: title,
          description: description,
          sessionNumber: int.parse(_field('Session number').text.trim()),
          pricePiasters: price,
          position: position,
          status: _status,
          isFreePreview: _preview,
        ),
      );
    } else {
      widget.onSave(
        CourseDraft(
          title: title,
          description: description,
          instructor: _field('Instructor').text,
          category: _field('Category').text,
          level: _field('Level').text,
          pricePiasters: price,
          position: position,
          status: _status,
        ),
        null,
      );
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.course != null || widget.session != null ? 'Edit' : 'New'} ${widget.forSession ? 'session' : 'course'}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              _text('Title', 160),
              if (!widget.forSession && widget.course == null)
                const Text(
                  'Save course metadata first, then open Course cover from the course list.',
                ),
              _text('Description', 10000, required: false, lines: 4),
              if (!widget.forSession) ...[
                _text('Instructor', 160),
                _text('Category', 120),
                _text('Level', 120),
              ],
              if (widget.forSession) _integer('Session number', positive: true),
              TextFormField(
                controller: _field('Price (EGP)'),
                enabled: !widget.busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Price (EGP)',
                  helperMaxLines: 3,
                  helperText:
                      'Up to 2 decimal places; maximum 21474836.47 EGP.',
                ),
                validator: (value) => parsePricePiasters(value ?? '') == null
                    ? 'Enter a valid EGP price with at most 2 decimal places.'
                    : null,
              ),
              _integer('Position'),
              const SizedBox(height: 16),
              DropdownButtonFormField<ContentStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: ContentStatus.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.name),
                      ),
                    )
                    .toList(),
                onChanged: widget.busy
                    ? null
                    : (value) => setState(() {
                        _status = value!;
                      }),
              ),
              if (widget.forSession)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Free preview'),
                  value: _preview,
                  onChanged: widget.busy
                      ? null
                      : (value) => setState(() {
                          _preview = value;
                        }),
                ),
              if (widget.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(widget.error!),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: widget.busy ? null : _submit,
                child: Text(widget.busy ? 'Saving…' : 'Save'),
              ),
              TextButton(
                onPressed: widget.busy ? null : widget.onCancel,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
