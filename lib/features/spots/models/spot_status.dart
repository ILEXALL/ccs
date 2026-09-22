enum SpotStatus { pending, approved, rejected, edited }

String spotStatusName(SpotStatus status) {
  switch (status) {
    case SpotStatus.pending:
      return 'pending';
    case SpotStatus.approved:
      return 'approved';
    case SpotStatus.rejected:
      return 'rejected';
    case SpotStatus.edited:
      return 'edited';
  }
}

SpotStatus spotStatusFromFirebase(Object? value) {
  switch (value) {
    case 'approved':
      return SpotStatus.approved;
    case 'rejected':
      return SpotStatus.rejected;
    case 'edited':
      return SpotStatus.edited;
    default:
      return SpotStatus.pending;
  }
}
