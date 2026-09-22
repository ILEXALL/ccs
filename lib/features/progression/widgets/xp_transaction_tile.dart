import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/progression/models/xp_transaction.dart'
    show XpTransactionData;
import 'package:ccs_app/features/progression/widgets/xp_labels.dart'
    show xpTransactionIcon, xpTransactionStatusColor;

class XpTransactionTile extends StatelessWidget {
  final XpTransactionData transaction;

  const XpTransactionTile({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final statusColor = xpTransactionStatusColor(transaction.status);
    final amountColor = transaction.amount > 0 ? blue : statusColor;
    final reasonLabel = transaction.reasonLabel;
    final createdAtLabel = transaction.createdAtLabel;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: statusColor.withValues(alpha: 0.38)),
            ),
            child: Icon(
              xpTransactionIcon(transaction.objectType),
              color: statusColor,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CcsText(
                  transaction.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _XpHistoryBadge(
                      label: transaction.category,
                      color: Colors.white54,
                    ),
                    _XpHistoryBadge(
                      label: transaction.statusLabel,
                      color: statusColor,
                    ),
                    if (reasonLabel.isNotEmpty)
                      _XpHistoryBadge(
                        label: reasonLabel,
                        color: Colors.orangeAccent,
                      ),
                  ],
                ),
                if (createdAtLabel.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  CcsText(
                    createdAtLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56, maxWidth: 92),
            child: CcsText(
              transaction.amountLabel,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: amountColor,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _XpHistoryBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _XpHistoryBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: CcsText(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color == Colors.white54 ? Colors.white60 : color,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
