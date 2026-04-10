import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TvTextField
// ─────────────────────────────────────────────────────────────────────────────

/// TextField adaptado para navegación D-Pad en Android TV.
///
/// **Modo proxy** (por defecto): el widget es un contenedor focusable que se
/// ilumina visualmente cuando el D-Pad llega a él, pero NO abre el teclado.
/// Pulsar Enter/OK (o tap) activa el **modo edición**: aparece el TextField
/// real, se invoca el IME y el usuario puede escribir.
///
/// Al cerrar el teclado (Back, submit o pérdida de foco) el widget regresa
/// automáticamente al modo proxy y reclama el foco D-Pad.
class TvTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final bool enabled;
  final TextInputType? keyboardType;
  final Widget? prefixIcon;

  const TvTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.enabled = true,
    this.keyboardType,
    this.prefixIcon,
  });

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  final _proxyFocus = FocusNode(debugLabel: 'TvTextField.proxy');
  final _editFocus  = FocusNode(debugLabel: 'TvTextField.edit');
  bool _hasFocus  = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _proxyFocus.addListener(_onProxyFocus);
    _editFocus.addListener(_onEditFocus);
    widget.controller.addListener(_onControllerChange);
  }

  @override
  void didUpdateWidget(TvTextField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
    }
  }

  @override
  void dispose() {
    _proxyFocus.removeListener(_onProxyFocus);
    _editFocus.removeListener(_onEditFocus);
    widget.controller.removeListener(_onControllerChange);
    _proxyFocus.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  void _onProxyFocus() {
    if (!mounted) return;
    setState(() => _hasFocus = _proxyFocus.hasFocus);
  }

  void _onEditFocus() {
    if (!mounted) return;
    // El teclado se cerró o el foco se movió → volver a modo proxy.
    if (!_editFocus.hasFocus && _isEditing) {
      setState(() => _isEditing = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _proxyFocus.requestFocus();
      });
    }
  }

  void _onControllerChange() {
    // Refleja cambios externos (p.ej. limpiar desde el padre) en proxy.
    if (mounted && !_isEditing) setState(() {});
  }

  void _startEditing() {
    if (!widget.enabled) return;
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _editFocus.requestFocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _isEditing
        ? AppColors.accent
        : _hasFocus
            ? AppColors.focusBorder
            : AppColors.border;
    final borderWidth = (_isEditing || _hasFocus) ? 2.0 : 1.0;

    // ── Modo edición: TextField real ──────────────────────────────────────
    if (_isEditing) {
      return TextField(
        controller: widget.controller,
        focusNode: _editFocus,
        enabled: widget.enabled,
        autofocus: false,
        keyboardType: widget.keyboardType,
        style: AppTextStyles.bodyLarge,
        onSubmitted: (_) => _editFocus.unfocus(),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: AppTextStyles.bodyMedium,
          prefixIcon: widget.prefixIcon,
          suffixIcon: widget.controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear,
                      color: AppColors.textSecondary, size: 18),
                  onPressed: () {
                    widget.controller.clear();
                    _editFocus.requestFocus();
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.surfaceVariant,
          contentPadding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md, horizontal: AppSpacing.base),
          border: OutlineInputBorder(
            borderRadius: AppRadius.buttonRadius,
            borderSide: BorderSide(color: borderColor, width: borderWidth),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.buttonRadius,
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.buttonRadius,
            borderSide: const BorderSide(color: AppColors.accent, width: 2),
          ),
        ),
      );
    }

    // ── Modo proxy: contenedor focusable, sin teclado ─────────────────────
    final hasText = widget.controller.text.isNotEmpty;

    return Focus(
      focusNode: _proxyFocus,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          _startEditing();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _startEditing,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md, horizontal: AppSpacing.base),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: AppRadius.buttonRadius,
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: _hasFocus
                ? [
                    BoxShadow(
                      color: AppColors.focusGlow,
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ]
                : [],
          ),
          child: Row(
            children: [
              if (widget.prefixIcon != null) ...[
                widget.prefixIcon!,
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  hasText ? widget.controller.text : widget.hintText,
                  style: hasText
                      ? AppTextStyles.bodyLarge
                      : AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textDisabled),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (hasText)
                GestureDetector(
                  onTap: () {
                    widget.controller.clear();
                    setState(() {});
                  },
                  child: const Padding(
                    padding: EdgeInsets.only(left: AppSpacing.sm),
                    child: Icon(Icons.clear,
                        color: AppColors.textSecondary, size: 18),
                  ),
                )
              else if (_hasFocus)
                const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.sm),
                  child: Icon(Icons.keyboard,
                      size: 14, color: AppColors.accent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
