import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/features/spots/data/spot_ownership.dart'
    show SpotOwnerAssignment, findSpotOwnerAssignment, transferSpotOwnership;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

Future<CarSpot?> showSpotOwnershipTransfer(
  BuildContext context,
  CarSpot spot,
) => showDialog<CarSpot>(
  context: context,
  barrierDismissible: false,
  builder: (_) => SpotOwnershipTransferDialog(spot: spot),
);

class SpotOwnershipTransferDialog extends StatefulWidget {
  final CarSpot spot;
  const SpotOwnershipTransferDialog({super.key, required this.spot});
  @override
  State<SpotOwnershipTransferDialog> createState() =>
      _SpotOwnershipTransferDialogState();
}

class _SpotOwnershipTransferDialogState
    extends State<SpotOwnershipTransferDialog> {
  final controller = TextEditingController();
  SpotOwnerAssignment? recipient;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> search() async {
    setState(() {
      busy = true;
      error = null;
      recipient = null;
    });
    try {
      final result = await findSpotOwnerAssignment(controller.text);
      if (!mounted) return;
      setState(() {
        recipient = result;
        if (result == null) error = 'User not found.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not find the user. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> transfer() async {
    if (recipient == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final updated = await transferSpotOwnership(widget.spot, recipient!);
      if (mounted) Navigator.pop(context, updated);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Transfer failed. Check that the user is active, ownership has not changed, and the spot is not under review.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      scrollable: true,
      title: CcsText(
        communityText(
          en: 'Transfer ownership',
          ru: 'Передать владение',
          lv: 'Nodot īpašumtiesības',
        ),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CcsText(widget.spot.name),
            const SizedBox(height: 8),
            CcsText('${trText('Owner')}: @${widget.spot.addedBy}'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: communityText(
                  en: 'Nickname or user ID',
                  ru: 'Никнейм или ID пользователя',
                  lv: 'Segvārds vai lietotāja ID',
                ),
              ),
              onChanged: (_) => setState(() {
                recipient = null;
                error = null;
              }),
              onSubmitted: (_) {
                if (!busy && controller.text.trim().isNotEmpty) search();
              },
            ),
            TextButton(
              onPressed: busy ? null : search,
              child: CcsText(trText('Search')),
            ),
            if (recipient != null)
              CcsText(
                communityText(
                  en: 'Transfer this spot to @${recipient!.username}? They will receive ownership and editing rights.',
                  ru: 'Передать точку @${recipient!.username}? Пользователь получит права владельца и редактирования.',
                  lv: 'Nodot vietu @${recipient!.username}? Lietotājs saņems īpašumtiesības un rediģēšanas tiesības.',
                ),
              ),
            if (error != null)
              CcsText(error!, style: const TextStyle(color: Colors.redAccent)),
            if (busy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: CcsText(trText('Cancel')),
        ),
        FilledButton(
          onPressed: busy || recipient == null ? null : transfer,
          child: CcsText(
            communityText(
              en: 'Confirm transfer',
              ru: 'Подтвердить передачу',
              lv: 'Apstiprināt nodošanu',
            ),
          ),
        ),
      ],
    ),
  );
}
