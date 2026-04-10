import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TvFocusManager
// ─────────────────────────────────────────────────────────────────────────────

/// Manages D-Pad focus traversal for a grid or list of focusable items.
///
/// ### Typical usage
/// ```dart
/// // 1. Create once in State.initState
/// final _focus = TvFocusManager(columnCount: 3);
///
/// // 2. In build, resize to match the current item count
/// _focus.resize(_items.length);
///
/// // 3. Wrap the grid with a Focus that routes key events here
/// Focus(
///   onKeyEvent: (_, e) => _focus.handleKey(_items.length, e),
///   child: GridView.builder(
///     itemCount: _items.length,
///     itemBuilder: (_, i) => MyTile(focusNode: _focus.nodeAt(i)),
///   ),
/// )
///
/// // 4. Each tile calls _focus.onItemFocused(index) when it receives focus
/// //    so the manager knows which item is active.
///
/// // 5. Dispose in State.dispose
/// _focus.dispose();
/// ```
class TvFocusManager {
  TvFocusManager({int columnCount = 1}) : _columnCount = columnCount.clamp(1, 100);

  // ── Configuration ──────────────────────────────────────────────────────────

  int _columnCount;

  /// Number of columns in the grid. Update when layout changes.
  int get columnCount => _columnCount;
  set columnCount(int v) => _columnCount = v.clamp(1, 100);

  // ── Internal state ─────────────────────────────────────────────────────────

  final List<FocusNode> _nodes = [];
  int _focusedIndex = 0;

  /// Index of the most recently focused item.
  int get focusedIndex => _focusedIndex;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the [FocusNode] for [index], creating it if necessary.
  FocusNode nodeAt(int index) {
    while (_nodes.length <= index) {
      _nodes.add(FocusNode(debugLabel: 'TvItem#${_nodes.length}'));
    }
    return _nodes[index];
  }

  /// Shrinks the internal node list to [count], disposing surplus nodes.
  /// Call this in [build] before iterating items so stale nodes are cleaned up.
  void resize(int count) {
    if (count < 0) return;
    while (_nodes.length > count) {
      _nodes.removeLast().dispose();
    }
    if (_focusedIndex >= count && count > 0) {
      _focusedIndex = count - 1;
    }
  }

  /// Call from a tile's [FocusNode] listener so the manager tracks the active index.
  void onItemFocused(int index) => _focusedIndex = index;

  /// Moves focus to the first item, if any.
  void focusFirst() {
    if (_nodes.isNotEmpty) {
      _focusedIndex = 0;
      _nodes[0].requestFocus();
    }
  }

  /// Routes a [KeyEvent] from a parent [Focus.onKeyEvent] handler.
  ///
  /// Moves focus along the grid using arrow-key D-Pad semantics and returns
  /// [KeyEventResult.handled] when the event was consumed.
  KeyEventResult handleKey(int itemCount, KeyEvent event) {
    if (event is! KeyDownEvent || itemCount == 0) return KeyEventResult.ignored;

    // Detect which node currently has primary focus (more robust than tracking
    // _focusedIndex manually, since touch/mouse taps can change focus too).
    final currentIndex = _nodes.indexWhere((n) => n.hasPrimaryFocus);
    if (currentIndex != -1) _focusedIndex = currentIndex;

    int next = _focusedIndex;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        // Only move left if not already in the first column.
        if (next % _columnCount > 0) {
          next--;
        } else {
          return KeyEventResult.ignored; // propagate to allow horizontal scroll
        }

      case LogicalKeyboardKey.arrowRight:
        // Only move right if not already in the last column AND next item exists.
        if (next % _columnCount < _columnCount - 1 && next + 1 < itemCount) {
          next++;
        } else {
          return KeyEventResult.ignored;
        }

      case LogicalKeyboardKey.arrowUp:
        if (next - _columnCount >= 0) {
          next -= _columnCount;
        } else {
          return KeyEventResult.ignored;
        }

      case LogicalKeyboardKey.arrowDown:
        if (next + _columnCount < itemCount) {
          next += _columnCount;
        } else {
          return KeyEventResult.ignored;
        }

      default:
        return KeyEventResult.ignored;
    }

    _focusedIndex = next;
    nodeAt(next).requestFocus();
    return KeyEventResult.handled;
  }

  /// Releases all [FocusNode]s. Call from [State.dispose].
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    _nodes.clear();
  }
}
