import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;

class CcsPartner {
  final String id;
  final String name;
  final String logoUrl;
  final String bio;
  final String phone;
  final String website;
  final String instagram;
  final String telegram;
  final List<String> photoUrls;
  final bool active;
  final int createdAtMillis;

  const CcsPartner({
    required this.id,
    required this.name,
    required this.logoUrl,
    this.bio = '',
    this.phone = '',
    this.website = '',
    this.instagram = '',
    this.telegram = '',
    this.photoUrls = const <String>[],
    this.active = true,
    this.createdAtMillis = 0,
  });

  factory CcsPartner.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final createdAt = data['createdAt'];
    final gallery = data['photoUrls'];
    return CcsPartner(
      id: snapshot.id,
      name: stringFromFirebase(data['name'], '').trim(),
      logoUrl: stringFromFirebase(data['logoUrl'], '').trim(),
      bio: stringFromFirebase(data['bio'], '').trim(),
      phone: stringFromFirebase(data['phone'], '').trim(),
      website: stringFromFirebase(data['website'], '').trim(),
      instagram: stringFromFirebase(data['instagram'], '').trim(),
      telegram: stringFromFirebase(data['telegram'], '').trim(),
      photoUrls: gallery is Iterable
          ? gallery
                .map((value) => value?.toString().trim() ?? '')
                .where((value) => value.isNotEmpty)
                .take(4)
                .toList(growable: false)
          : const <String>[],
      active: data['active'] != false,
      createdAtMillis: createdAt is Timestamp
          ? createdAt.millisecondsSinceEpoch
          : (data['createdAtMillis'] as num?)?.toInt() ?? 0,
    );
  }
}
