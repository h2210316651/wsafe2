import 'package:firebase_database/firebase_database.dart';

Future insertData(DatabaseReference ref, Map data, String deviceId) async {
  try {
    await ref.child(deviceId).set({
      "name": "John Doe",
      "story": "I am a story",
      "verified": false,
    });
    return true;
  } catch (e) {
    return false;
  }
}
