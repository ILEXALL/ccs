import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart'
    show
        appOutline,
        appPrimaryText,
        appSecondaryText,
        appSubtleText,
        appSurfaceOverlay,
        blue,
        panelGlass;

class AddSpotSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const AddSpotSection({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CcsText(
            trText(title),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          ...children.expand(
            (child) => [
              child,
              if (child != children.last) const SizedBox(height: 10),
            ],
          ),
        ],
      ),
    );
  }
}

class CcsTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final TextInputType keyboardType;
  final bool readOnly;
  final bool autoGrow;

  const CcsTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.readOnly = false,
    this.autoGrow = false,
  });

  @override
  Widget build(BuildContext context) {
    final multiline = autoGrow || maxLines > 1;

    return TextField(
      controller: controller,
      minLines: multiline ? 2 : 1,
      maxLines: autoGrow ? null : maxLines,
      keyboardType: multiline ? TextInputType.multiline : keyboardType,
      textInputAction: multiline
          ? TextInputAction.newline
          : TextInputAction.done,
      readOnly: readOnly,
      style: TextStyle(color: appPrimaryText, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        isDense: true,
        labelText: trText(label),
        hintText: trText(hint),
        prefixIcon: Icon(icon, color: blue),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 42,
          minHeight: 42,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        labelStyle: TextStyle(color: appSecondaryText),
        hintStyle: TextStyle(color: appSubtleText),
        filled: true,
        fillColor: appSurfaceOverlay,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: appOutline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: blue, width: 1.4),
        ),
      ),
    );
  }
}
