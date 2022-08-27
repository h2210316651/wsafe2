import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:audio_manager/audio_manager.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shake/shake.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wsafe2/audio_utils.dart';
import 'package:wsafe2/emergencyContacts.dart';
import 'package:wsafe2/geolocationutils.dart';
import 'package:wsafe2/smsutils.dart';
import 'firebase_options.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swiping_card_deck/swiping_card_deck.dart';
import 'package:wsafe2/quotes.dart';
import 'package:fluttertoast/fluttertoast.dart';

class EMContact {
  late String name;
  late String phone;
  EMContact(this.name, this.phone);
}

setFGDATA(String key, dynamic value) async {
  print("setting sata ${jsonEncode(value)}");
  await FlutterForegroundTask.saveData(key: key, value: jsonEncode(value));
}

getFGDATA(String key) async {
  var contacts = await FlutterForegroundTask.getData(key: key);
  var dec;
  if (contacts == null) {
    dec = [];
    return dec;
  }
  dec = jsonDecode(contacts);
  print(dec);
  return dec;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  //full screen
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  //initialize firebase APP
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

void startCallback() {
  // The setTaskHandler function must be called to handle the task in the background.
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  Future panicWarningMessage() async {
    AudioManager.instance.setVolume(1.0);
    await AudioManager.instance
        .start(
            "assets/panic_warning.mp3",
            // "network format resource"
            // "local resource (file://${file.path})"
            "Panic Alert",
            desc: "panic mode will be enabled in less than a minute",
            // cover: "network cover image resource"
            cover: "assets/back.png")
        .then((err) {
      print(err);
    });
    AudioManager.instance.stop();
    return true;
  }

  SendPort? _sendPort;
  int _eventCount = 0;
  late Timer t;
  int checkCount = 0;
  List contacts = [];
  stopTimer() {
    try {
      t.cancel();
    } catch (e) {
      print("Stop timer error : $e");
    }
  }

  getEventSharedPrefs() async {
    Map prefs = {};
    var contacts = await getFGDATA("contacts");
    contacts ??= [];

    var panicMode = await FlutterForegroundTask.getData(key: "panicMode");
    panicMode ??= false;

    var lastSOS = await FlutterForegroundTask.getData(key: "lastSOS");
    try {
      lastSOS ??= jsonDecode(lastSOS);
    } catch (e) {
      lastSOS ??= {};
    }

    var sosResponse = await FlutterForegroundTask.getData(key: "sosResponse");
    sosResponse ??= false;

    var panicResponse =
        await FlutterForegroundTask.getData(key: "panicResponse");
    panicResponse ??= false;

    var listeningPanic =
        await FlutterForegroundTask.getData(key: "listeningPanic");
    listeningPanic ??= false;

    var listeningSOS = await FlutterForegroundTask.getData(key: "listeningSOS");
    listeningSOS ??= false;
    for (var contact in contacts) {
      // contact["phone"].toString().toString().replaceAll(RegExp(r"\D"), "");
      contact["phone"] =
          contact["phone"].toString().replaceAll(RegExp('[^0-9]'), '');
      if (contact["phone"].toString().length > 10) {
        //trim the phone number to last 10 digits
        contact["phone"] = contact["phone"].toString().substring(
            contact["phone"].toString().length - 10,
            contact["phone"].toString().length);
      }
    }
    prefs["contacts"] = contacts;
    prefs["panicMode"] = panicMode;
    prefs["lastSOS"] = lastSOS;
    prefs["sosResponse"] = sosResponse;
    prefs["panicResponse"] = panicResponse;
    prefs["listeningPanic"] = listeningPanic;
    prefs["listeningSOS"] = listeningSOS;
    return prefs;
  }

  eventMainLoop() async {
    // meta data for he event
    // Shared preferences for storing the event data
    //"panicMode" -> bool -> true if panic mode is enabled by user
    //"contacts" -> List<String> -> list of contacts in emergency contact list
    //"lastSOS" -> Map<String, dynamic> -> last SOS sent to the user
    //"sosResponse" ->bool -> if true sound alarm on sos messge
    //"panicResponse" -> bool -> if true sound alarm on panic message
    //"listeningPanic" -> bool -> if true listen for panic message
    //"listeningSOS" -> bool -> if true listen for SOS message
    Map prefs = await getEventSharedPrefs();
    late Timer smsTimer;
    // print("prefs : $prefs");
    if (prefs["panicMode"] == true) {
      if (!prefs["listeningPanic"]) {
        await FlutterForegroundTask.saveData(
            key: "listeningPanic", value: true);
        Timer cancelTimer =
            Timer.periodic(const Duration(seconds: 1), (timer) async {
          var panicMode = await FlutterForegroundTask.getData(key: "panicMode");
          if (panicMode == false) {
            print("Panic cancelled by user");
            timer.cancel();

            await FlutterForegroundTask.saveData(
                key: "listeningPanic", value: false);
            eventMainLoop();
            return;
          }
        });
        await Future.delayed(const Duration(minutes: 1));
        print("1 minutes passed");

        cancelTimer.cancel();
        bool panicMode = await FlutterForegroundTask.getData(key: "panicMode");

        if (panicMode) {
          await sendSOSSMS();
          int timerStart = DateTime.now().millisecondsSinceEpoch;
          Timer.periodic(const Duration(seconds: 15), (timer) async {
            if (DateTime.now()
                    .subtract(const Duration(minutes: 5))
                    .millisecondsSinceEpoch >
                timerStart) {
              timer.cancel();
              await FlutterForegroundTask.saveData(
                  key: "listeningPanic", value: false);
              await FlutterForegroundTask.saveData(
                  key: "panicMode", value: false);
              if (AudioManager.instance.isPlaying) {
                AudioManager.instance.stop();
              }
              eventMainLoop();
            }
            Map p = await getEventSharedPrefs();
            print("prefs : $p");
            if (p["panicResponse"] && p["panicMode"]) {
              if (AudioManager.instance.isPlaying) {
                AudioManager.instance.stop();
              }
              AudioManager.instance.setVolume(1.0);
              AudioManager.instance
                  .start(
                      "assets/siren.mp3",
                      // "network format resource"
                      // "local resource (file://${file.path})"
                      "Panic Alert",
                      desc: "panic mode enabled",
                      // cover: "network cover image resource"
                      cover: "assets/back.png")
                  .then((err) {
                print(err);
              });
            }
            print("panic details ${p["panicMode"]}");
            if (p["panicMode"]) {
              List messages = await readSMS();
              if (messages.isEmpty) {
                print("No messages");
              } else {
                print("Messages : $messages");

                for (SmsMessage message in messages) {
                  String senderId = message.sender
                      .toString()
                      .replaceAll(RegExp('[^0-9]'), '');
                  if (senderId.length > 10) {
                    senderId = senderId.substring(
                        senderId.length - 10, senderId.length);
                  }
                  print("senderId : $senderId");
                  List contacts = [];
                  List c = prefs["contacts"];
                  c.forEach((a) {
                    contacts.add(a["phone"]);
                  });
                  print("contacts : $contacts");
                  print("contacts contains? : ${contacts.contains(senderId)}");
                  if (contacts.contains(senderId)) {
                    try {
                      String msg = message.body
                          .toString()
                          .replaceAll(RegExp(r"<<hash>>"), "");

                      msg = msg.replaceAll(RegExp(r"<</hash>>"), "");

                      String decrypted = decryptMyData(msg);
                      Map decodeMsg = jsonDecode(decrypted);
                      if (decodeMsg["panicAck"] == true) {
                        print("Panic Acknowledged");
                        await FlutterForegroundTask.saveData(
                            key: "panicMode", value: false);
                        await FlutterForegroundTask.saveData(
                            key: "listeningPanic", value: false);
                        if (AudioManager.instance.isPlaying) {
                          AudioManager.instance.stop();
                        }
                        eventMainLoop();
                        timer.cancel();
                      }
                    } catch (e) {
                      print("Error in replacing hash : $e");
                    }
                  }
                }
              }
            } else {
              print("panic  mode disabled");
              timer.cancel();
            }
          });
        } else {
          try {
            cancelTimer.cancel();
            await FlutterForegroundTask.saveData(
                key: "panicMode", value: false);
            await FlutterForegroundTask.saveData(
                key: "listeningPanic", value: false);
            eventMainLoop();
            return;
          } catch (e) {
            print("cancel timer error : $e");
          }
        }
        await Future.delayed(const Duration(minutes: 5));
        print("5 minutes passed");
        await FlutterForegroundTask.saveData(key: "panicMode", value: false);
        await FlutterForegroundTask.saveData(
            key: "listeningPanic", value: false);

        eventMainLoop();
        return;
      } else {
        await Future.delayed(const Duration(seconds: 5));

        eventMainLoop();
        return;
      }
    } else {
      print("Sos mode");
      if (!prefs["listeningSOS"]) {
        // return;
        await FlutterForegroundTask.saveData(key: "listeningSOS", value: true);
        await Future.delayed(const Duration(seconds: 5));

        await FlutterForegroundTask.saveData(key: "listeningSOS", value: false);
        eventMainLoop();
        return;
      } else {
        await Future.delayed(const Duration(seconds: 5));

        eventMainLoop();
        return;
      }
    }
  }

  sosAlarm() async {
    AudioManager.instance.setVolume(1.0);
    await AudioManager.instance
        .start(
            "assets/siren.mp3",
            // "network format resource"
            // "local resource (file://${file.path})"
            "Panic Alert",
            desc: "panic mode enabled",
            // cover: "network cover image resource"
            cover: "assets/back.png")
        .then((err) {
      print(err);
    });

    Timer alarmTimer =
        Timer.periodic(const Duration(seconds: 30), (timer) async {
      AudioManager.instance.setVolume(1.0);
      await AudioManager.instance
          .start(
              "assets/siren.mp3",
              // "network format resource"
              // "local resource (file://${file.path})"
              "Panic Alert",
              desc: "panic mode enabled",
              // cover: "network cover image resource"
              cover: "assets/back.png")
          .then((err) {
        print(err);
      });
    });
    await Future.delayed(const Duration(minutes: 5), () {
      alarmTimer.cancel();
      eventMainLoop();
    });
  }

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    _sendPort = sendPort;

    //background shake counter
    int count = 0;
    List a = [
      0,
      0,
      0,
      0,
      0,
    ];

    final ec = await getFGDATA('contacts');
    // print("FGDATA $ec");
    if (ec.isEmpty) {
      Fluttertoast.showToast(
          msg: "Cannot start panic service without emergency contacts");
      _sendPort?.send("onNotificationPressed");
      await FlutterForegroundTask.stopService();
    } else {
      eventMainLoop();
    }
    ShakeDetector detector = ShakeDetector.autoStart(onPhoneShake: () async {
      // Do stuff on phone shake
      count += 1;
      int ts = DateTime.now().millisecondsSinceEpoch;
      a[0] = a[1];
      a[1] = a[2];
      a[2] = a[3];
      a[3] = a[4];
      a[4] = ts;

      print("shit differnce $a ${a[4] - a[0]}");
      if (a[4] - a[0] < 4000) {
        await FlutterForegroundTask.saveData(key: "panicMode", value: true);
        panicWarningMessage();
        await Future.delayed(const Duration(seconds: 10));
      }
    });
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    await FlutterForegroundTask.saveData(key: "count", value: _eventCount);

    FlutterForegroundTask.updateService(
        notificationTitle: 'MyTaskHandler',
        notificationText: 'eventCount: $_eventCount');

    // Send data to the main isolate.
    sendPort?.send(_eventCount);

    _eventCount++;
    // var customData =
    //     await FlutterForegroundTask.getData<String>(key: 'contacts');
    // print('customData: $customData');

    // var customData2 = await FlutterForegroundTask.getData<int>(key: "count");
    // print('customData: $customData2');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    // You can use the clearAllData function to clear all the stored data.
    // await FlutterForegroundTask.clearAllData();
    await FlutterForegroundTask.saveData(key: 'panicMode', value: false);
    await FlutterForegroundTask.saveData(key: "listeningPanic", value: false);

    await FlutterForegroundTask.saveData(key: 'listeningSOS', value: false);
    if (AudioManager.instance.isPlaying) {
      AudioManager.instance.stop();
    }
  }

  @override
  void onButtonPressed(String id) {
    // Called when the notification button on the Android platform is pressed.
    print('onButtonPressed >> $id');
  }

  @override
  void onNotificationPressed() {
    // Called when the notification itself on the Android platform is pressed.
    //
    // "android.permission.SYSTEM_ALERT_WINDOW" permission must be granted for
    // this function to be called.

    // Note that the app will only route to "/resume-route" when it is exited so
    // it will usually be necessary to send a message through the send port to
    // signal it to restore state when the app is already started.
    FlutterForegroundTask.launchApp("/resume-route");
    _sendPort?.send('onNotificationPressed');
  }
}

GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int indexG = 0;
  FirebaseDatabase database = FirebaseDatabase.instance;
  Map stories = {};
  @override
  void initState() {
    // TODO: implement initState
    DatabaseReference ref = FirebaseDatabase.instance.ref("/");
    ref
        .child("stories")
        .orderByChild("verified")
        .startAt(true)
        .endAt(true)
        .once()
        .then((event) {
      if (event.snapshot.value != null) {
        setState(() {
          stories = event.snapshot.value as Map;
        });
        print(stories);
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: Scaffold(
          bottomNavigationBar: CurvedNavigationBar(
            backgroundColor: Colors.white,
            color: const Color.fromARGB(255, 245, 245, 245),
            items: const <Widget>[
              Icon(Icons.sos, size: 30),
              Icon(Icons.home, size: 30),
              Icon(Icons.settings, size: 30),
            ],
            onTap: (index) {
              //Handle button tap
              setState(() {
                indexG = index;
              });
            },
          ),
          body: Container(color: Colors.white, child: determinePage(indexG))),
    );
  }
}

determinePage(int index) {
  switch (index) {
    case 1:
      return CardsPage();
      break;
    case 0:
      return SosPage();
      break;
    case 2:
      return SettingsPage();
      break;
  }
}

class SettingsPage extends StatefulWidget {
  SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List contacts = [];
  bool ready = false;
  Map settings = {
    "panicAlarm": false,
    "sosAlarm": false,
    "phonePermission": false,
    "locationPermission": false,
    "locationbackgroundPermission": false,
    "smsPermission": false,
    "ignorebatteryPermission": false,
  };

  setContacts() async {
    var c = await getFGDATA('contacts') as List;
    setState(() {
      contacts = c;
    });
  }

  checkPermissions() async {
    bool hasphonePermission = await Permission.phone.isGranted;
    if (hasphonePermission) {
      settings["phonePermission"] = true;
    }
    bool haslocationPermission = await Permission.location.isGranted;
    if (haslocationPermission) {
      settings["locationPermission"] = true;
    }
    bool haslocationbackgroundPermission =
        await Permission.locationAlways.isGranted;
    if (haslocationbackgroundPermission) {
      settings["locationbackgroundPermission"] = true;
    }
    bool hassmsPermission = await Permission.sms.isGranted;
    if (hassmsPermission) {
      settings["smsPermission"] = true;
    }
    bool hasignorebatteryPermission =
        await Permission.ignoreBatteryOptimizations.isGranted;
    if (hasignorebatteryPermission) {
      settings["ignorebatteryPermission"] = true;
    }

    setState(() {
      settings = settings;
    });
  }

  late Timer t;
  bool isServiceRunning = false;

  @override
  void initState() {
    // TODO: implement initState
    checkPermissions();
    setContacts();
    t = Timer.periodic(const Duration(seconds: 1), (timer) async {
      setContacts();
      checkPermissions();
      var sospref = await FlutterForegroundTask.getData(key: "sosResponse");
      sospref ??= true;
      var panicpref = await FlutterForegroundTask.getData(key: "panicResponse");
      panicpref ??= true;
      await FlutterForegroundTask.saveData(key: "sosResponse", value: sospref);
      await FlutterForegroundTask.saveData(
          key: "panicResponse", value: panicpref);
      bool isR = await FlutterForegroundTask.isRunningService;
      setState(() {
        settings["panicAlarm"] = panicpref;
        settings["sosAlarm"] = sospref;
        isServiceRunning = isR;
        ready = true;
      });
    });
    super.initState();
  }

  @override
  void dispose() {
    // TODO: implement dispose
    t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;
    return !isServiceRunning
        ? ready
            ? SingleChildScrollView(
                child: Container(
                  width: width,
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Container(
                        width: width,
                        child: Text("Settings",
                            textAlign: TextAlign.start,
                            style: GoogleFonts.poppins(
                                textStyle: TextStyle(
                                    color: Colors.grey[800],
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold))),
                      ),
                      Container(
                        width: width * 0.9,
                        child: Divider(
                          color: Colors.grey[500],
                          thickness: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            width: width,
                            child: Text(
                              "Emergency Contacts",
                              textAlign: TextAlign.start,
                              style: GoogleFonts.montserrat(
                                  textStyle: TextStyle(
                                color: Colors.grey[800],
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              )),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(left: 8, right: 8),
                            width: width,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Column(
                                    children:
                                        List.generate(contacts.length, (index) {
                                  return Column(
                                    children: [
                                      Container(
                                        height: 50,
                                        child: Center(
                                          child: Text(
                                            "${contacts[index]["name"]} : ${contacts[index]["phone"]} ",
                                            textAlign: TextAlign.start,
                                            style: GoogleFonts.montserrat(
                                                textStyle: TextStyle(
                                              color: Colors.grey[800],
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                            )),
                                          ),
                                        ),
                                      ),
                                      const Divider()
                                    ],
                                  );
                                })),
                                MaterialButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (context) =>
                                                  EmergencyContacts()));
                                    },
                                    color: Colors.orange[400],
                                    child: Text(
                                      "Edit",
                                      style: GoogleFonts.montserrat(
                                          textStyle: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      )),
                                    )),
                              ],
                            ),
                          ),
                          Divider(),
                          Container(
                            padding: const EdgeInsets.all(16),
                            width: width,
                            child: Text(
                              "Panic Alarm",
                              textAlign: TextAlign.start,
                              style: GoogleFonts.montserrat(
                                  textStyle: TextStyle(
                                color: Colors.grey[800],
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              )),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.only(left: 16),
                            width: width,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Sound alarm when in panic mode?",
                                  style: GoogleFonts.montserrat(
                                    textStyle: TextStyle(
                                      color: Colors.grey[800],
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Switch(
                                    value: settings["panicAlarm"],
                                    activeColor: Colors.orange[400],
                                    onChanged: (changed) async {
                                      await FlutterForegroundTask.saveData(
                                          key: "panicResponse", value: changed);
                                      setState(() {
                                        settings["panicAlarm"] = changed;
                                      });
                                    })
                              ],
                            ),
                          ),
                          Divider(),
                          Container(
                            padding: const EdgeInsets.all(16),
                            width: width,
                            child: Text(
                              "External SOS Alarm",
                              textAlign: TextAlign.start,
                              style: GoogleFonts.montserrat(
                                  textStyle: TextStyle(
                                color: Colors.grey[800],
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              )),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.only(left: 16),
                            width: width,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Sound alarm on sos from friends?",
                                  style: GoogleFonts.montserrat(
                                    textStyle: TextStyle(
                                      color: Colors.grey[800],
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Switch(
                                    value: settings["sosAlarm"],
                                    activeColor: Colors.orange[400],
                                    onChanged: (changed) async {
                                      await FlutterForegroundTask.saveData(
                                          key: "sosResponse", value: changed);
                                      setState(() {
                                        settings["sosAlarm"] = changed;
                                      });
                                    })
                              ],
                            ),
                          ),
                          Divider(),
                          Container(
                            padding: const EdgeInsets.all(16),
                            width: width,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Permissions",
                                  textAlign: TextAlign.start,
                                  style: GoogleFonts.montserrat(
                                      textStyle: TextStyle(
                                    color: Colors.grey[800],
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  )),
                                ),
                                SizedBox(
                                  height: 16,
                                ),
                                Text(
                                  "Tap on the permission to grant ",
                                  textAlign: TextAlign.start,
                                  style: GoogleFonts.montserrat(
                                      fontStyle: FontStyle.italic,
                                      textStyle: TextStyle(
                                        color: Colors.grey[800],
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      )),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(16),
                            width: width,
                            height: 250,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                InkWell(
                                  onTap: () async {
                                    print("tapped");
                                    try {
                                      if (!settings[
                                          "locationbackgroundPermission"]) {
                                        await openAppSettings();
                                      }
                                    } catch (e) {
                                      print(e);
                                    }
                                  },
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Location",
                                        style: GoogleFonts.montserrat(
                                            textStyle: TextStyle(
                                          color: Colors.grey[800],
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        )),
                                      ),
                                      settings["locationbackgroundPermission"]
                                          ? Text(
                                              "Location granted in background")
                                          : settings["locationPermission"]
                                              ? Text(
                                                  "Location granted while using the app")
                                              : Text("Location not granted"),
                                    ],
                                  ),
                                ),
                                Divider(),
                                InkWell(
                                  onTap: () async {
                                    print("tapped");
                                    try {
                                      if (!settings["phonePermission"]) {
                                        PermissionStatus pp =
                                            await Permission.phone.request();
                                        if (pp.isGranted) {
                                          setState(() {
                                            settings["phonePermission"] = true;
                                          });
                                        }
                                      }
                                    } catch (e) {
                                      print(e);
                                    }
                                  },
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Phone",
                                        style: GoogleFonts.montserrat(
                                            textStyle: TextStyle(
                                          color: Colors.grey[800],
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        )),
                                      ),
                                      settings["phonePermission"]
                                          ? Text("Phone permission granted")
                                          : Text(
                                              "Phone permission not granted"),
                                    ],
                                  ),
                                ),
                                Divider(),
                                InkWell(
                                  onTap: () async {
                                    print("tapped");
                                    try {
                                      if (!settings["smsPermission"]) {
                                        PermissionStatus pp =
                                            await Permission.sms.request();
                                        if (pp.isGranted) {
                                          setState(() {
                                            settings["smsPermission"] = true;
                                          });
                                        }
                                      }
                                    } catch (e) {
                                      print(e);
                                    }
                                  },
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "SMS",
                                        style: GoogleFonts.montserrat(
                                            textStyle: TextStyle(
                                          color: Colors.grey[800],
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        )),
                                      ),
                                      settings["smsPermission"]
                                          ? Text("SMS permission granted")
                                          : Text("SMS permission not granted"),
                                    ],
                                  ),
                                ),
                                Divider(),
                                InkWell(
                                  onTap: () async {
                                    print("tapped");
                                    try {
                                      if (!settings[
                                          "ignorebatteryPermission"]) {
                                        PermissionStatus pp = await Permission
                                            .ignoreBatteryOptimizations
                                            .request();
                                        if (pp.isGranted) {
                                          setState(() {
                                            settings[
                                                    "ignorebatteryPermission"] =
                                                true;
                                          });
                                        }
                                      }
                                    } catch (e) {
                                      print(e);
                                    }
                                  },
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Battery",
                                        style: GoogleFonts.montserrat(
                                            textStyle: TextStyle(
                                          color: Colors.grey[800],
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        )),
                                      ),
                                      settings["smsPermission"]
                                          ? Text(
                                              "Battery optimisations ignored")
                                          : Text(
                                              "Battery optimisations not ignored"),
                                    ],
                                  ),
                                ),
                                Divider(
                                  thickness: 2,
                                ),
                                Container(
                                  margin: EdgeInsets.only(top: 16),
                                  width: width,
                                  child: Text(
                                    "Guide >",
                                    textAlign: TextAlign.start,
                                    style: GoogleFonts.montserrat(
                                        textStyle: TextStyle(
                                      color: Colors.grey[800],
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    )),
                                  ),
                                )
                              ],
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              )
            : const Center(
                child: CircularProgressIndicator(),
              )
        : const Center(
            child: Text(
                "Can not change setttings while Panic service is running"));
  }
}

class SosPage extends StatefulWidget {
  SosPage({Key? key}) : super(key: key);

  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  ReceivePort? _receivePort;

  Future<void> _initForegroundTask() async {
    await FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'notification_channel_id',
        channelName: 'Foreground Notification',
        channelDescription:
            'This notification appears when the foreground service is running.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
          backgroundColor: Colors.orange,
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000000,
        autoRunOnBoot: true,
        allowWifiLock: true,
      ),
      printDevLog: true,
    );
  }

  Future<bool> _startForegroundTask() async {
    // "android.permission.SYSTEM_ALERT_WINDOW" permission must be granted for
    // onNotificationPressed function to be called.
    //
    // When the notification is pressed while permission is denied,
    // the onNotificationPressed function is not called and the app opens.
    //
    // If you do not use the onNotificationPressed or launchApp function,
    // you do not need to write this code.
    if (!await FlutterForegroundTask.canDrawOverlays) {
      final isGranted =
          await FlutterForegroundTask.openSystemAlertWindowSettings();
      if (!isGranted) {
        print('SYSTEM_ALERT_WINDOW permission denied!');
        return false;
      }
    }

    // You can save data using the saveData function.
    // await FlutterForegroundTask.saveData(key: 'customData', value: 'hello');

    bool reqResult;
    if (await FlutterForegroundTask.isRunningService) {
      reqResult = await FlutterForegroundTask.restartService();
    } else {
      reqResult = await FlutterForegroundTask.startService(
        notificationTitle: 'Foreground Service is running',
        notificationText: 'Tap to return to the app',
        callback: startCallback,
      );
    }

    ReceivePort? receivePort;
    if (reqResult) {
      receivePort = await FlutterForegroundTask.receivePort;
    }

    return _registerReceivePort(receivePort);
  }

  Future<bool> _stopForegroundTask() async {
    return await FlutterForegroundTask.stopService();
  }

  bool _registerReceivePort(ReceivePort? receivePort) {
    _closeReceivePort();

    if (receivePort != null) {
      _receivePort = receivePort;
      _receivePort?.listen((message) {
        if (message is int) {
          print('eventCount: $message');
        } else if (message is String) {
          if (message == 'onNotificationPressed') {
            Navigator.of(context).push(
                MaterialPageRoute(builder: ((context) => EmergencyContacts())));
          }
        } else if (message is DateTime) {
          print('timestamp: ${message.toString()}');
        }
      });

      return true;
    }

    return false;
  }

  void _closeReceivePort() {
    _receivePort?.close();
    _receivePort = null;
  }

  T? _ambiguate<T>(T? value) => value;

  bool isLocationGrabbed = false;
  late Position currentLocation;

  setLocation() async {
    Position cl = await determinePosition().catchError((e) {
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
    setState(() {
      isLocationGrabbed = true;
      currentLocation = cl;
    });
  }

  bool isListeningForPanic = false;
  bool isPanicModeEnabled = false;
  late Timer panicListener;
  updatePanicListener() async {
    bool ir = await FlutterForegroundTask.isRunningService;
    if (ir) {
      setState(() {
        isListeningForPanic = true;
      });

      var pe = await FlutterForegroundTask.getData(key: "panicMode");
      pe ??= false;
      setState(() {
        isPanicModeEnabled = pe;
      });
    } else {
      setState(() {
        isListeningForPanic = false;
      });
    }
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _initForegroundTask();
    _ambiguate(WidgetsBinding.instance)?.addPostFrameCallback((_) async {
      // You can get the previous ReceivePort without restarting the service.
      if (await FlutterForegroundTask.isRunningService) {
        final newReceivePort = await FlutterForegroundTask.receivePort;
        _registerReceivePort(newReceivePort);
      }
    });
    setLocation();
    panicListener = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      updatePanicListener();
    });
  }

  @override
  void dispose() {
    _closeReceivePort();
    panicListener.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;
    return SingleChildScrollView(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              !isListeningForPanic
                  ? MaterialButton(
                      color: Colors.green[400],
                      onPressed: () async {
                        await _startForegroundTask();
                        Timer.periodic(const Duration(seconds: 10), (timer) {
                          //generate a random 5 letter string
                          final randomString = Random()
                              .nextInt(1000000)
                              .toString()
                              .padLeft(5, '0');
                          FlutterForegroundTask.saveData(
                              key: 'customData', value: randomString);
                        });
                      },
                      child: const Text(
                        "Start listening for panic",
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  : MaterialButton(
                      color: Colors.red[400],
                      onPressed: () async {
                        // await _stopForegroundTask();
                        await FlutterForegroundTask.saveData(
                            key: 'panicMode', value: false);
                        await FlutterForegroundTask.saveData(
                            key: "listeningPanic", value: false);

                        await FlutterForegroundTask.saveData(
                            key: 'listeningSOS', value: false);
                        // exit(0);
                        await FlutterForegroundTask.stopService();
                        // MyTaskHandler().stopForegroundService();
                      },
                      child: const Text(
                        "Stop listening for panic",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
            ],
          ),
          isListeningForPanic
              ? Container(
                  margin: const EdgeInsets.all(16),
                  width: width,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.grey[50]),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        height: 60,
                        child: Center(
                          child: Text(
                            "Listening for panic",
                            style: GoogleFonts.poppins(
                                textStyle: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            )),
                          ),
                        ),
                      ),
                      const Divider(),
                      isPanicModeEnabled
                          ? Container(
                              child: Container(
                                height: 80,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    Text(
                                      "Panic mode is Enabled",
                                      style: GoogleFonts.poppins(
                                          textStyle: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black)),
                                    ),
                                    MaterialButton(
                                        color: Colors.orange[400],
                                        onPressed: () async {
                                          await FlutterForegroundTask.saveData(
                                              key: 'panicMode', value: false);
                                          if (AudioManager.instance.isPlaying) {
                                            AudioManager.instance.stop();
                                          }
                                          setState(() {
                                            isPanicModeEnabled = false;
                                          });
                                        },
                                        child: Text(
                                          "Disable panic mode",
                                          style: GoogleFonts.poppins(
                                              textStyle: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white)),
                                        )),
                                  ],
                                ),
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.all(16),
                              child: const Center(
                                  child: Text(
                                      "Panic mode is not enabled.\n\nShake you phone until you hear a sound to enable panic mode")),
                            )
                    ],
                  ))
              : Container(),
          isLocationGrabbed
              ? Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.grey[50],
                  ),
                  margin: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Container(
                        margin: EdgeInsets.only(bottom: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text(
                              "Nearby Safe Places",
                              style: GoogleFonts.poppins(
                                  textStyle: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              )),
                            ),
                            IconButton(
                                onPressed: () async {
                                  print("Nearby Safe Places Requested");
                                  await setLocation();
                                },
                                icon: const Icon(Icons.refresh)),
                          ],
                        ),
                      ),
                      const Divider(
                        thickness: 2,
                      ),
                      const SizedBox(
                        height: 20,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Text(
                            "Hospitals",
                            style: GoogleFonts.poppins(
                                textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            )),
                          ),
                          MaterialButton(
                              color: Colors.orange[400],
                              onPressed: () =>
                                  MapsLauncher.launchQuery("Hospitals near me"),
                              child: Text(
                                "Open in maps",
                                style: GoogleFonts.poppins(
                                    textStyle: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                              ))
                        ],
                      ),
                      const Divider(),
                      Container(
                        height: height * 0.6,
                        margin: const EdgeInsets.all(8),
                        child: WebView(
                          initialUrl:
                              "https://www.google.com/maps/search/hospitals+near+me/@${currentLocation.latitude},${currentLocation.longitude}",
                          javascriptMode: JavascriptMode.unrestricted,
                        ),
                      ),

                      ///Pharmacies
                      ///
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Text(
                            "Pharmacies",
                            style: GoogleFonts.poppins(
                                textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            )),
                          ),
                          MaterialButton(
                              color: Colors.orange[400],
                              onPressed: () => MapsLauncher.launchQuery(
                                  "Pharmacies near me"),
                              child: Text(
                                "Open in maps",
                                style: GoogleFonts.poppins(
                                    textStyle: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                              ))
                        ],
                      ),
                      const Divider(),
                      Container(
                        height: height * 0.6,
                        margin: const EdgeInsets.all(8),
                        child: WebView(
                          initialUrl:
                              "https://www.google.com/maps/search/pharmacies+near+me/@${currentLocation.latitude},${currentLocation.longitude}",
                          javascriptMode: JavascriptMode.unrestricted,
                        ),
                      ),

                      ///Police

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Text(
                            "Police Stations",
                            style: GoogleFonts.poppins(
                                textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            )),
                          ),
                          MaterialButton(
                              color: Colors.orange[400],
                              onPressed: () => MapsLauncher.launchQuery(
                                  "Police station near me"),
                              child: Text(
                                "Open in maps",
                                style: GoogleFonts.poppins(
                                    textStyle: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                              ))
                        ],
                      ),
                      const Divider(),
                      Container(
                        height: height * 0.6,
                        margin: const EdgeInsets.all(8),
                        child: WebView(
                          initialUrl:
                              "https://www.google.com/maps/search/police+station+near+me/@${currentLocation.latitude},${currentLocation.longitude}",
                          javascriptMode: JavascriptMode.unrestricted,
                        ),
                      ),
                    ],
                  ))
              : Container()
        ],
      ),
    );
  }
}

class CardsPage extends StatefulWidget {
  CardsPage({Key? key}) : super(key: key);
  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  List<Card> cards = generateCards();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;
    return Center(
      child: SwipingCardDeck(
        cardDeck: cards,
        onDeckEmpty: () {
          debugPrint("Card deck empty");
          setState(() {
            cards = generateCards();
          });
        },
        onLeftSwipe: (Card card) => debugPrint("Swiped left!"),
        onRightSwipe: (Card card) => debugPrint("Swiped right!"),
        swipeThreshold: MediaQuery.of(context).size.width / 4,
        minimumVelocity: 1000,
        cardWidth: 200,
        rotationFactor: 0.8 / 3.14,
        swipeAnimationDuration: const Duration(milliseconds: 200),
      ),
    );
  }
}
