import 'dart:convert';

import 'package:background_sms/background_sms.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:geolocator/geolocator.dart';
import 'package:wsafe2/geolocationutils.dart';
import 'package:wsafe2/main.dart';

final key = enc.Key.fromUtf8('123qwe456rty678u123qwe456rty678u'); //32 chars
final iv = enc.IV.fromUtf8('123qwe456rty678u'); //16chars

String encryptMyData(String text) {
  final e = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  final encrypted_data = e.encrypt(text, iv: iv);
  return encrypted_data.base64;
}

String decryptMyData(String text) {
  final e = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  final decrypted_data = e.decrypt(enc.Encrypted.fromBase64(text), iv: iv);
  return decrypted_data;
}

Future sendSMSBack(String message, List<String> recipents) async {
  int count = 0;
  recipents.forEach((recipient) async {
    try {
      List<String> a = message.split("<</hash>>");
      SmsStatus result = await BackgroundSms.sendMessage(
          phoneNumber: recipient, message: a[0] + "<</hash>>");
      SmsStatus result2 = await BackgroundSms.sendMessage(
          phoneNumber: recipient, message: a[1]);
      if (result == SmsStatus.sent) {
        count++;
        //print("shit Sent");
      } else {
        //print("Failed");
      }
    } catch (e) {
      //print("shit sms error $e");
    }

    // await telephony.sendSms(to: recipient, message: message);
  });
  //print(count);

  return count.toString();
}

Future readSMS() async {
  SmsQuery query = SmsQuery();
  List<SmsMessage> a = [];
  List<SmsMessage> sms = await query.querySms(kinds: [SmsQueryKind.inbox]);
  int timeNowMin = DateTime.now()
      .subtract(const Duration(minutes: 5))
      .millisecondsSinceEpoch;
  int timeNowMax = DateTime.now().millisecondsSinceEpoch;

  for (int i = 0; i < sms.length; i++) {
    // check if sms was received in last five minutes
    if (sms[i].date!.millisecondsSinceEpoch > timeNowMin &&
        sms[i].date!.millisecondsSinceEpoch < timeNowMax) {
      //check if sms is app encoded
      // print(sms[i].body);
      if (sms[i].body.toString().contains("<<hash>>") &&
          sms[i].body.toString().contains("<</hash>>") &&
          sms[i].body.toString().length > 17) {
        a.add(sms[i]);
      }
    } else {
      break;
    }
  }
  // print(a);
  return a;
}

Future sendSOSSMS() async {
  Position location;
  location = await determinePosition().catchError((e) {
    //print("Shit Location error $e");
    return Position(
        longitude: 0,
        latitude: 0,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0);
  });

  String mapsUri =
      "https://maps.google.com/?q=${location.latitude},${location.longitude}";

  Map appSmsHash = {
    "lat": location.latitude,
    "lng": location.longitude,
    "uri": mapsUri,
  };
  //print(appSmsHash);
  String jsonData = json.encode(appSmsHash);
  String hash = encryptMyData(jsonData);
  String smsMessage =
      "<<hash>>$hash<</hash>>  SOS! I am in danger. My location is ${location.latitude},${location.longitude} \n\nPlease help me.\n\n$mapsUri";
  List contacts = await getFGDATA("contacts");
  List<String> recipents = [];
  for (int i = 0; i < contacts.length; i++) {
    recipents.add(contacts[i]["phone"]);
  }
  List<String> cL = recipents;
  //print(cL);
  String smsResp = await sendSMSBack(smsMessage, cL);
  //print(smsResp);

  return true;
}
