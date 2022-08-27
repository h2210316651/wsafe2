import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:fluttercontactpicker/fluttercontactpicker.dart';
import 'package:google_fonts/google_fonts.dart';
import "main.dart";
import "dart:convert";

class EmergencyContacts extends StatefulWidget {
  EmergencyContacts({Key? key}) : super(key: key);

  @override
  State<EmergencyContacts> createState() => _EmergencyContactsState();
}

class _Contact {
  String name;
  String phone;
  _Contact(this.name, this.phone);
}

class _EmergencyContactsState extends State<EmergencyContacts> {
  List contactsG = [];
  bool ready = false;

  // List<Widget> generateContacts() {
  //   List<Widget> widgets = [];

  //   for (int i = 0; i < _contacts.length; i++) {
  //     widgets.add(const Divider());
  //   }
  //   return widgets;
  // }

  getEmergencyContacts() async {
    // await setData();
    var contacts = await getFGDATA("contacts");
    print(contacts.runtimeType);
    if (contacts.toString().isEmpty) {
    } else {
      List cG = contacts as List;
      setState(() {
        contactsG = cG;
      });
    }
    setState(() {
      ready = true;
    });
  }

  @override
  void initState() {
    // TODO: implement initState
    getEmergencyContacts();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;
    return Scaffold(
        body: SingleChildScrollView(
      child: Container(
        width: width,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
                width: width,
                child: Row(
                  children: [
                    IconButton(
                        alignment: Alignment.centerLeft,
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.arrow_back)),
                    Container(
                      width: width * 0.7,
                      child: Text("Emergency Contacts",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                              textStyle: TextStyle(
                                  color: Colors.grey[800],
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold))),
                    ),
                  ],
                )),
            const Divider(
              thickness: 2,
            ),
            Container(
                width: width,
                padding: const EdgeInsets.all(8),
                child: ready
                    ? Column(
                        children: [
                          Row(
                            children: [
                              MaterialButton(
                                  onPressed: () async {
                                    final PhoneContact contact =
                                        await FlutterContactPicker
                                            .pickPhoneContact();
                                    print(contact.phoneNumber);
                                    bool found = false;
                                    for (var i = 0; i < contactsG.length; i++) {
                                      if (contactsG[i]['phone'] ==
                                          contact.phoneNumber!.number) {
                                        found = true;
                                      }
                                    }
                                    if (!found) {
                                      contactsG.add({
                                        "name": contact.fullName,
                                        "phone": contact.phoneNumber!.number
                                      });
                                    }
                                    await setFGDATA('contacts', contactsG);
                                    setState(() {
                                      contactsG = contactsG;
                                    });
                                  },
                                  child: const Text(
                                    "Add Contact",
                                  )),
                            ],
                          ),
                          const Divider(),
                          Column(
                              children: List.generate(contactsG.length, (i) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "${contactsG[i]['name']} : ${contactsG[i]['phone']}",
                                  style: GoogleFonts.montserrat(
                                      textStyle: TextStyle(
                                    color: Colors.grey[800],
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  )),
                                ),
                                IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () async {
                                      setState(() {
                                        contactsG.removeAt(i);
                                      });
                                      await setFGDATA('contacts', contactsG);
                                    }),
                              ],
                            );
                          }))
                        ],
                      )
                    : const Center(child: CircularProgressIndicator()))
          ],
        ),
      ),
    ));
  }
}
