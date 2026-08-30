import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FriendService {
  FriendService._();

  static final FriendService instance = FriendService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _requestsCollection =>
      _db.collection('friendRequests');

  User? get currentFirebaseUser => _auth.currentUser;

  String? get currentUid => _auth.currentUser?.uid;

  Future<String> sendFriendRequest({
    required String toUid,
  }) async {
    final fromUid = currentUid;

    if (fromUid == null) {
      throw StateError(
        'A signed-in Firebase user is required to send a friend request.',
      );
    }

    final targetUid = toUid.trim();

    if (targetUid.isEmpty) {
      throw ArgumentError(
        'The target rider UID cannot be empty.',
      );
    }

    if (fromUid == targetUid) {
      throw StateError(
        'You cannot send a friend request to yourself.',
      );
    }

    final existingOutgoing = await _requestsCollection
        .where(
          'fromUid',
          isEqualTo: fromUid,
        )
        .where(
          'toUid',
          isEqualTo: targetUid,
        )
        .where(
          'status',
          isEqualTo: 'pending',
        )
        .limit(1)
        .get();

    if (existingOutgoing.docs.isNotEmpty) {
      return existingOutgoing.docs.first.id;
    }

    final existingIncoming = await _requestsCollection
        .where(
          'fromUid',
          isEqualTo: targetUid,
        )
        .where(
          'toUid',
          isEqualTo: fromUid,
        )
        .where(
          'status',
          isEqualTo: 'pending',
        )
        .limit(1)
        .get();

    if (existingIncoming.docs.isNotEmpty) {
      throw StateError(
        'This rider has already sent you a friend request.',
      );
    }

    final requestRef = _requestsCollection.doc();

    await requestRef.set(
      <String, dynamic>{
        'id': requestRef.id,
        'fromUid': fromUid,
        'toUid': targetUid,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    return requestRef.id;
  }

  Future<bool> hasPendingOutgoingRequest({
    required String toUid,
  }) async {
    final fromUid = currentUid;

    if (fromUid == null) {
      return false;
    }

    final targetUid = toUid.trim();

    if (targetUid.isEmpty) {
      return false;
    }

    final query = await _requestsCollection
        .where(
          'fromUid',
          isEqualTo: fromUid,
        )
        .where(
          'toUid',
          isEqualTo: targetUid,
        )
        .where(
          'status',
          isEqualTo: 'pending',
        )
        .limit(1)
        .get();

    return query.docs.isNotEmpty;
  }

  Future<bool> hasPendingIncomingRequest({
    required String fromUid,
  }) async {
    final toUid = currentUid;

    if (toUid == null) {
      return false;
    }

    final senderUid = fromUid.trim();

    if (senderUid.isEmpty) {
      return false;
    }

    final query = await _requestsCollection
        .where(
          'fromUid',
          isEqualTo: senderUid,
        )
        .where(
          'toUid',
          isEqualTo: toUid,
        )
        .where(
          'status',
          isEqualTo: 'pending',
        )
        .limit(1)
        .get();

    return query.docs.isNotEmpty;
  }

  Future<List<FriendRequestRecord>> getIncomingRequests() async {
    final uid = currentUid;

    if (uid == null) {
      return const <FriendRequestRecord>[];
    }

    final query = await _requestsCollection
        .where(
          'toUid',
          isEqualTo: uid,
        )
        .where(
          'status',
          isEqualTo: 'pending',
        )
        .orderBy(
          'createdAt',
          descending: true,
        )
        .get();

    return query.docs
        .map(FriendRequestRecord.fromFirestore)
        .toList();
  }

  Future<List<FriendRequestRecord>> getOutgoingRequests() async {
    final uid = currentUid;

    if (uid == null) {
      return const <FriendRequestRecord>[];
    }

    final query = await _requestsCollection
        .where(
          'fromUid',
          isEqualTo: uid,
        )
        .where(
          'status',
          isEqualTo: 'pending',
        )
        .orderBy(
          'createdAt',
          descending: true,
        )
        .get();

    return query.docs
        .map(FriendRequestRecord.fromFirestore)
        .toList();
  }

  Future<void> cancelFriendRequest({
    required String requestId,
  }) async {
    final uid = currentUid;

    if (uid == null) {
      throw StateError(
        'A signed-in Firebase user is required to cancel a friend request.',
      );
    }

    final id = requestId.trim();

    if (id.isEmpty) {
      throw ArgumentError(
        'Friend request ID cannot be empty.',
      );
    }

    final ref = _requestsCollection.doc(id);
    final snapshot = await ref.get();

    if (!snapshot.exists) {
      return;
    }

    final data = snapshot.data() ?? <String, dynamic>{};
    final fromUid = data['fromUid'];

    if (fromUid != uid) {
      throw StateError(
        'You can only cancel friend requests that you sent.',
      );
    }

    await ref.update(
      <String, dynamic>{
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> declineFriendRequest({
    required String requestId,
  }) async {
    final uid = currentUid;

    if (uid == null) {
      throw StateError(
        'A signed-in Firebase user is required to decline a friend request.',
      );
    }

    final id = requestId.trim();

    if (id.isEmpty) {
      throw ArgumentError(
        'Friend request ID cannot be empty.',
      );
    }

    final ref = _requestsCollection.doc(id);
    final snapshot = await ref.get();

    if (!snapshot.exists) {
      return;
    }

    final data = snapshot.data() ?? <String, dynamic>{};
    final toUid = data['toUid'];

    if (toUid != uid) {
      throw StateError(
        'You can only decline friend requests sent to you.',
      );
    }

    await ref.update(
      <String, dynamic>{
        'status': 'declined',
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> acceptFriendRequest({
    required String requestId,
  }) async {
    final uid = currentUid;

    if (uid == null) {
      throw StateError(
        'A signed-in Firebase user is required to accept a friend request.',
      );
    }

    final id = requestId.trim();

    if (id.isEmpty) {
      throw ArgumentError(
        'Friend request ID cannot be empty.',
      );
    }

    final requestRef = _requestsCollection.doc(id);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(requestRef);

      if (!snapshot.exists) {
        throw StateError(
          'Friend request no longer exists.',
        );
      }

      final data = snapshot.data() ?? <String, dynamic>{};

      final fromUid = _stringValue(data['fromUid']);
      final toUid = _stringValue(data['toUid']);
      final status = _stringValue(
        data['status'],
        fallback: 'pending',
      );

      if (toUid != uid) {
        throw StateError(
          'You can only accept friend requests sent to you.',
        );
      }

      if (fromUid.isEmpty) {
        throw StateError(
          'Friend request is missing the sender UID.',
        );
      }

      if (status != 'pending') {
        throw StateError(
          'This friend request is no longer pending.',
        );
      }

      final userFriendRef = _db
          .collection('socialRiders')
          .doc(toUid)
          .collection('friends')
          .doc(fromUid);

      final senderFriendRef = _db
          .collection('socialRiders')
          .doc(fromUid)
          .collection('friends')
          .doc(toUid);

      transaction.set(
        userFriendRef,
        <String, dynamic>{
          'uid': fromUid,
          'since': FieldValue.serverTimestamp(),
        },
      );

      transaction.set(
        senderFriendRef,
        <String, dynamic>{
          'uid': toUid,
          'since': FieldValue.serverTimestamp(),
        },
      );

      transaction.update(
        requestRef,
        <String, dynamic>{
          'status': 'accepted',
          'updatedAt': FieldValue.serverTimestamp(),
          'acceptedAt': FieldValue.serverTimestamp(),
        },
      );
    });
  }

  Future<bool> areFriends({
    required String otherUid,
  }) async {
    final uid = currentUid;

    if (uid == null) {
      return false;
    }

    final targetUid = otherUid.trim();

    if (targetUid.isEmpty) {
      return false;
    }

    final snapshot = await _db
        .collection('socialRiders')
        .doc(uid)
        .collection('friends')
        .doc(targetUid)
        .get();

    return snapshot.exists;
  }

  Future<List<String>> getFriendUids() async {
    final uid = currentUid;

    if (uid == null) {
      return const <String>[];
    }

    final query = await _db
        .collection('socialRiders')
        .doc(uid)
        .collection('friends')
        .orderBy(
          'since',
          descending: true,
        )
        .get();

    return query.docs
        .map((doc) => _stringValue(doc.data()['uid']))
        .where((uid) => uid.isNotEmpty)
        .toList();
  }

  static String _stringValue(
    Object? value, {
    String fallback = '',
  }) {
    if (value is String) {
      final trimmed = value.trim();

      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    return fallback;
  }
}

class FriendRequestRecord {
  const FriendRequestRecord({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.acceptedAt,
  });

  final String id;
  final String fromUid;
  final String toUid;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? acceptedAt;

  bool get isPending => status == 'pending';

  factory FriendRequestRecord.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();

    return FriendRequestRecord(
      id: FriendService._stringValue(
        data['id'],
        fallback: snapshot.id,
      ),
      fromUid: FriendService._stringValue(
        data['fromUid'],
      ),
      toUid: FriendService._stringValue(
        data['toUid'],
      ),
      status: FriendService._stringValue(
        data['status'],
        fallback: 'pending',
      ),
      createdAt: _dateTimeValue(data['createdAt']),
      updatedAt: _dateTimeValue(data['updatedAt']),
      acceptedAt: _dateTimeValue(data['acceptedAt']),
    );
  }

  static DateTime? _dateTimeValue(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }
}
