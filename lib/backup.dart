// eventMainLoop() async {
//   //check if panic mode is activated
//   var panicMode = await FlutterForegroundTask.getData(key: "panicMode");
//   panicMode ??= false;
//   if (panicMode) {
//     print("Entering panic mode");
//     //alert the user that panic mode is activated
//     panicWarningMessage();

//     print("reached Here");

//     Timer t = Timer.periodic(const Duration(seconds: 1), (timer) async {
//       //check if panic mode is activated
//       var panicMode = await FlutterForegroundTask.getData(key: "panicMode");
//       panicMode ??= false;
//       if (!panicMode) {
//         print("Exiting panic mode");
//         //alert the user that panic mode is activated
//         timer.cancel();
//         eventMainLoop();
//       }
//     });

//     await Future.delayed(const Duration(minutes: 1), () async {
//       t.cancel();
//       try {
//         var panicMode = await FlutterForegroundTask.getData(key: "panicMode");
//         panicMode ??= false;
//         if (panicMode) {
//           await sendSOSSMS();
//           late Timer smsTimer;
//           smsTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
//             //read messages
//             List<SmsMessage> sms = await readSMS();
//             print(sms.isNotEmpty ? sms[0].body : "No messages");
//             if (sms.isNotEmpty) {
//               List contacts = await getFGDATA("contacts");
//               for (int i = 0; i < sms.length; i++) {
//                 // if(sms[i].sender)
//                 String ss =
//                     sms[i].sender.toString().replaceAll(RegExp(r"\D"), "");

//                 for (int j = 0; j < contacts.length; j++) {
//                   String cc = contacts[j]["phone"]
//                       .toString()
//                       .replaceAll(RegExp(r"\D"), "");
//                   int diff = ss.compareTo(cc);
//                   print("difference is $diff");
//                   if (diff < 4 && diff > -4) {
//                     print("Sms is from contacts selected");
//                     //remove '<<hash>>' from the message
//                     String msg = sms[i]
//                         .body
//                         .toString()
//                         .replaceAll(RegExp(r"<<hash>>"), "");
//                     msg = msg.replaceAll(RegExp(r"<</hash>>"), "");
//                     print(msg);
//                     try {
//                       Map map = json.decode(msg);
//                       print(map["panicAck"]);
//                       if (map["panicAck"] == true) {
//                         await FlutterForegroundTask.saveData(
//                             key: "panicMode", value: false);
//                         print("Exiting panic mode");
//                         smsTimer.cancel();
//                         eventMainLoop();
//                       }
//                     } catch (e) {
//                       print("Error reading SOS message hash : $e");
//                       smsTimer.cancel();
//                       eventMainLoop();
//                     }
//                   }
//                 }
//                 print(sms[i].sender);
//               }
//             }
//           });

//           //wait for five minutes then exit
//           await Future.delayed(const Duration(minutes: 5), () async {
//             await FlutterForegroundTask.saveData(
//                 key: "panicMode", value: false);
//             print("Exiting panic mode");
//             smsTimer.cancel();

//             eventMainLoop();
//           });
//         } else {
//           eventMainLoop();
//         }
//       } catch (e) {
//         print("Error sending SOS message : $e");
//         eventMainLoop();
//       }
//     });
//     print("reached Here");

//     //send SOS message to all contacts

//   } else {
//     //
//     //
//     print("Entering sos mode");
//     Map sosDetails = {};

//     List<SmsMessage> sms = await readSMS();
//     print(sms.isNotEmpty ? sms[0].body : "No messages");
//     if (sms.isNotEmpty) {
//       bool found = false;
//       for (int i = 0; i < sms.length; i++) {
//         // if(sms[i].sender)
//         if (found) {
//           break;
//         }

//         // print("Sms is from contacts selected");

//         String msg = sms[i].body.toString().replaceAll(RegExp(r"<<hash>>"), "");
//         msg = msg.replaceAll(RegExp(r"<</hash>>"), "");
//         if (sms[i].date!.millisecondsSinceEpoch >
//             DateTime.now()
//                 .subtract(const Duration(minutes: 5))
//                 .millisecondsSinceEpoch) {
//           try {
//             String msgdecrypted = decryptMyData(msg);

//             Map map = json.decode(msgdecrypted);
//             if (map["lat"] != null && map["lng"] != null) {
//               found = true;
//               map["timestamp"] = sms[i].date!.millisecondsSinceEpoch;
//               await FlutterForegroundTask.saveData(
//                   key: "lastSOS", value: json.encode(map));
//               print(map);

//               sosDetails = map;
//             }
//           } catch (e) {
//             print("Error reading SOS message hash : $e");
//           }
//         }
//       }

//       if (found) {
//         int count = 0;
//         Timer.periodic(const Duration(seconds: 30), (timer) {
//           if (count >= 9) {
//             timer.cancel();

//             eventMainLoop();
//           }
//           sosAlarm();
//         });
//       }
//     } else {
//       await Future.delayed(const Duration(seconds: 10), () {
//         eventMainLoop();
//       });
//     }
//   }
//   //
//   //
// }
