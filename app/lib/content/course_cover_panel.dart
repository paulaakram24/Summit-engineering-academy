import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_controller.dart';
import 'content_repository.dart';
import 'course_cover_actions.dart';
import 'course_covers.dart';
import 'course_image_selector.dart';

class CourseCoverPanel extends StatefulWidget {
  const CourseCoverPanel({
    super.key,
    required this.course,
    required this.auth,
    required this.onClose,
    this.actions,
    this.selector,
  });
  final Course course;
  final AuthController auth;
  final VoidCallback onClose;
  final CourseCoverActions? actions;
  final CourseImageSelector? selector;

  @override
  State<CourseCoverPanel> createState() => _CourseCoverPanelState();
}

class _CourseCoverPanelState extends State<CourseCoverPanel> {
  late Course _course;
  late CourseCoverActions _actions;
  late CourseImageSelector _selector;
  Uint8List? _preview, _selected;
  bool _busy = false, _refreshRequired = false, _invalidated = false;
  bool _confirming = false;
  int _epoch = 0;
  String? _message;
  bool get _allowed =>
      !_invalidated &&
      widget.auth.stage == AuthStage.ready &&
      widget.auth.access?.role == 'admin' &&
      !_course.isDeleted;
  bool _current(int epoch) => mounted && _allowed && epoch == _epoch;

  @override
  void initState() {
    super.initState();
    _course = widget.course;
    _selector = widget.selector ?? SystemCourseImageSelector();
    widget.auth.addListener(_authChanged);
    _initialize();
  }

  void _clearImages() {
    for (final bytes in [_preview, _selected]) {
      if (bytes != null) MemoryImage(bytes).evict();
    }
    _preview = null;
    _selected = null;
  }

  @override
  void didUpdateWidget(CourseCoverPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.course != widget.course ||
        oldWidget.auth != widget.auth ||
        oldWidget.actions != widget.actions ||
        oldWidget.selector != widget.selector) {
      ++_epoch;
      oldWidget.auth.removeListener(_authChanged);
      widget.auth.addListener(_authChanged);
      _clearImages();
      _course = widget.course;
      _selector = widget.selector ?? SystemCourseImageSelector();
      _busy = _confirming = _refreshRequired = _invalidated = false;
      _message = null;
      _initialize();
    }
  }

  void _authChanged() {
    if (widget.auth.stage != AuthStage.ready ||
        widget.auth.access?.role != 'admin') {
      ++_epoch;
      _invalidated = true;
      _clearImages();
      _message = null;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    ++_epoch;
    widget.auth.removeListener(_authChanged);
    _clearImages();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (!_allowed) return;
    final epoch = ++_epoch;
    setState(() => _busy = true);
    try {
      _actions =
          widget.actions ??
          SupabaseCourseCoverActions(Supabase.instance.client);
      final lost = await _selector.discardLostSelection();
      if (!_current(epoch)) return;
      final bytes = await _actions.download(_course);
      if (!_current(epoch)) return;
      setState(() {
        _preview = bytes;
        if (lost) _message = 'An interrupted selection was discarded. Choose the image again for this course.';
      });
    } catch (_) {
      if (_current(epoch)) {
        setState(() {
          _refreshRequired = true;
          _message = const CourseCoverFailure().message;
        });
      }
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _select() async {
    if (_busy || !_allowed || _refreshRequired) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final raw = await CourseImageSelection.run(
        widget.auth,
        (returned) => _selector.select(onPickerReturned: returned),
      );
      if (!_current(epoch) || raw == null) return;
      final png = await sanitizeCoverImage(raw);
      if (!_current(epoch)) return;
      setState(() {
        if (_selected != null) MemoryImage(_selected!).evict();
        _selected = png;
      });
    } catch (_) {
      if (_current(epoch)) {
        setState(() => _message = const CourseCoverFailure().message);
      }
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _change({bool remove = false, bool cleanup = false}) async {
    if (_busy || !_allowed || _refreshRequired) return;
    if (!cleanup && (remove ? _course.coverPath == null : _selected == null)) {
      return;
    }
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _message = null;
    });
    var attempted = false;
    setState(() => _confirming = true);
    try {
      final title = cleanup
          ? 'Clean retired covers?'
          : remove
          ? 'Remove course cover?'
          : _course.coverPath == null
          ? 'Attach selected cover?'
          : 'Replace course cover?';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AnimatedBuilder(
          animation: widget.auth,
          builder: (context, _) => AlertDialog(
            title: Text(_allowed ? title : 'Access changed'),
            content: Text(
              !_allowed
                  ? 'Close this dialog and verify administrator access again.'
                  : cleanup
                  ? 'Process up to 20 retired images in one pass. The current cover is protected. Further cleanup may need another explicit pass.'
                  : remove
                  ? 'Detach the current cover. Its image will remain pending retired cleanup.'
                  : 'Save this selected image as the course cover. Any previous cover will be retired for later cleanup.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _allowed && _current(epoch)
                    ? () => Navigator.pop(context, true)
                    : null,
                child: Text(
                  cleanup
                      ? 'Confirm cleanup'
                      : remove
                      ? 'Confirm removal'
                      : 'Confirm cover',
                ),
              ),
            ],
          ),
        ),
      );
      if (!_current(epoch) || confirmed != true) return;
      setState(() => _confirming = false);
      attempted = true;
      if (cleanup) {
        final result = await _actions.cleanup(_course.id);
        if (!_current(epoch)) return;
        setState(
          () => _message =
              'Cleanup: ${result.cleaned} cleaned, ${result.failed} failed, ${result.attempted} attempted. '
              '${result.mayHaveMore ? 'More cleanup may remain. Run another pass explicitly.' : 'This pass is complete.'}',
        );
      } else {
        final result = remove
            ? await _actions.remove(_course)
            : await _actions.replace(_course, _selected!);
        if (!_current(epoch)) return;
        if (result.id != _course.id || result.isDeleted) {
          throw const CourseCoverFailure();
        }
        _clearImages();
        _course = result;
        final bytes = await _actions.download(_course);
        if (!_current(epoch)) return;
        setState(() {
          _preview = bytes;
          _message =
              'Cover saved. Retired images can be cleaned in a separate pass.';
        });
      }
    } catch (_) {
      if (_current(epoch)) {
        setState(() {
          if (!cleanup) _clearImages();
          _refreshRequired = attempted && !cleanup;
          _message = cleanup
              ? 'Cleanup could not finish. Some retired images may remain. Check your connection and access, then retry one pass.'
              : const CourseCoverFailure().message;
        });
      }
    } finally {
      if (_current(epoch)) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return const Center(
        child: Text(
          'Administrator access is required for a nondeleted course.',
        ),
      );
    }
    final enabled = !_busy && !_refreshRequired;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Cover: ${_course.title}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'PNG, JPEG or WebP; up to 5 MiB. Saved as a private PNG up to 3 MiB.',
          ),
          if (_busy && !_confirming) const LinearProgressIndicator(),
          if (_preview != null)
            Image.memory(
              _preview!,
              height: 180,
              fit: BoxFit.contain,
              semanticLabel: 'Current private course cover',
              errorBuilder: (_, _, _) => const Text('Preview unavailable.'),
            ),
          if (_preview == null && !_busy)
            const Text('No cover preview available.'),
          if (_selected != null) ...[
            const Text('Selected image — not yet saved'),
            Image.memory(
              _selected!,
              height: 180,
              fit: BoxFit.contain,
              semanticLabel: 'Selected course cover',
              errorBuilder: (_, _, _) => const Text('Preview unavailable.'),
            ),
            FilledButton(
              onPressed: enabled ? () => _change() : null,
              child: const Text('Use selected cover'),
            ),
            TextButton(
              onPressed: enabled
                  ? () => setState(() {
                      MemoryImage(_selected!).evict();
                      _selected = null;
                    })
                  : null,
              child: const Text('Discard selection'),
            ),
          ],
          OutlinedButton(
            onPressed: enabled ? _select : null,
            child: const Text('Choose image'),
          ),
          if (_course.coverPath != null)
            OutlinedButton(
              onPressed: enabled ? () => _change(remove: true) : null,
              child: const Text('Remove cover'),
            ),
          OutlinedButton(
            onPressed: enabled ? () => _change(cleanup: true) : null,
            child: const Text('Clean retired covers (up to 20)'),
          ),
          if (_message != null)
            Semantics(liveRegion: true, child: Text(_message!)),
          if (_refreshRequired)
            const Text(
              'Return to courses and refresh before retrying. The last change may already have completed.',
            ),
          TextButton(
            onPressed: _busy ? null : widget.onClose,
            child: const Text('Back to courses'),
          ),
        ],
      ),
    );
  }
}
