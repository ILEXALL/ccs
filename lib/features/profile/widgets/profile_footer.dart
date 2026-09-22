import 'package:flutter/material.dart' hide Text;

class ProfileActionFooter extends StatelessWidget {
  final Widget? action;
  final List<Widget> links;
  const ProfileActionFooter({super.key, this.action, required this.links});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Divider(height: 1, color: Colors.white10),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final socials = Wrap(spacing: 8, runSpacing: 8, children: links);
          if (action == null)
            return Align(alignment: Alignment.centerRight, child: socials);
          if (links.isEmpty) return action!;
          final linksWidth = links.length * 44 + (links.length - 1) * 8;
          final actionWidth = 145 * MediaQuery.textScalerOf(context).scale(1);
          if (constraints.maxWidth < actionWidth + linksWidth + 12) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                action!,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: socials),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: action!),
              const SizedBox(width: 12),
              socials,
            ],
          );
        },
      ),
    ],
  );
}
