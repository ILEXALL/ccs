import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

const int globalChatMessagePageSize = 20;

const Duration globalChatMessageSendCooldown = Duration(seconds: 30);

Future<QuerySnapshot<Map<String, dynamic>>>?
legacyLatvianGlobalMessagesSnapshotFuture;
