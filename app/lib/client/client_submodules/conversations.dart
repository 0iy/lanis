import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart';

import '../../shared/apps.dart';
import '../../shared/exceptions/client_status_exceptions.dart';
import '../../shared/types/conversations.dart';
import '../client.dart';
import '../connection_checker.dart';
import '../cryptor.dart';
import '../logger.dart';

class ConversationsParser {
  late Dio dio;
  late SPHclient client;

  ConversationsParser(Dio dioClient, this.client) {
    dio = dioClient;
  }

  Future<dynamic> getOverview(bool invisible) async {
    if (!(client.doesSupportFeature(SPHAppEnum.nachrichten))) {
      throw NotSupportedException();
    }

    logger.i("Get new conversation data. Invisible: $invisible.");
    try {
      final response =
          await dio.post("https://start.schulportal.hessen.de/nachrichten.php",
              data: {
                "a": "headers",
                "getType": invisible ? "unvisibleOnly" : "visibleOnly",
                "last": "0"
              },
              options: Options(
                headers: {
                  "Accept": "*/*",
                  "Content-Type":
                      "application/x-www-form-urlencoded; charset=UTF-8",
                  "Sec-Fetch-Dest": "empty",
                  "Sec-Fetch-Mode": "cors",
                  "Sec-Fetch-Site": "same-origin",
                  "X-Requested-With": "XMLHttpRequest",
                },
              ));

      return compute(
          computeJson, [response.toString(), client.cryptor.key.bytes]);
    } on (SocketException, DioException) {
      throw NetworkException();
    } on LanisException {
      rethrow;
    } catch (e) {
      throw UnknownException();
    }
  }

  static dynamic computeJson(List<dynamic> args) {
    final Map<String, dynamic> encryptedJSON = jsonDecode(args[0]);

    final String? decryptedConversations = Cryptor.decryptWithKeyString(
        encryptedJSON["rows"], encrypt.Key(args[1]));

    if (decryptedConversations == null) {
      throw UnsaltedOrUnknownException();
    }

    return jsonDecode(decryptedConversations);
  }

  Future<Conversation> getSingleConversation(String uniqueID) async {
    if (!(await connectionChecker.connected)) {
      throw NoConnectionException();
    }

    try {
      final encryptedUniqueID = client.cryptor.encryptString(uniqueID);

      final response =
          await dio.post("https://start.schulportal.hessen.de/nachrichten.php",
              queryParameters: {"a": "read", "msg": uniqueID},
              data: {"a": "read", "uniqid": encryptedUniqueID},
              options: Options(
                headers: {
                  "Accept": "*/*",
                  "Content-Type":
                      "application/x-www-form-urlencoded; charset=UTF-8",
                  "Sec-Fetch-Dest": "empty",
                  "Sec-Fetch-Mode": "cors",
                  "Sec-Fetch-Site": "same-origin",
                  "X-Requested-With": "XMLHttpRequest",
                },
              ));

      final Map<String, dynamic> encryptedJSON =
          jsonDecode(response.toString());

      final String? decryptedConversations =
          client.cryptor.decryptString(encryptedJSON["message"]);

      if (decryptedConversations == null) {
        throw UnsaltedOrUnknownException();
      }

      final Map<String, dynamic> decoded = jsonDecode(decryptedConversations);

      final UnparsedMessage parent = UnparsedMessage(
          date: decoded["Datum"],
          author: decoded["username"],
          own: decoded["own"],
          content: decoded["Inhalt"]
      );

      final List<UnparsedMessage> replies = [];
      for (dynamic reply in decoded["reply"]) {
        replies.add(UnparsedMessage(
            date: reply["Datum"],
            author: reply["username"],
            own: reply["own"],
            content: reply["Inhalt"]
        ));
      }

      int countStudents = decoded["statistik"]["teilnehmer"];
      int countTeachers = decoded["statistik"]["betreuer"];
      int countParents = decoded["statistik"]["eltern"];
      if (decoded["SenderArt"] == "Teilnehmer") {
        countStudents++;
      } else if (decoded["SenderArt"] == "Betreuer") {
        countTeachers++;
      } else {
        countParents++;
      }


      final List<String> knownParticipants = [decoded["username"]];
      if (decoded["empf"] is List) {
        for (String receiver in decoded["empf"]) {
          knownParticipants.add(parse(receiver).querySelector("span")!.text.substring(1));
        }
      }

      if (decoded["WeitereEmpfaenger"] != "") {
        final others  = parse(decoded["WeitereEmpfaenger"]).querySelectorAll("span");
        for (final other in others) {
          knownParticipants.add(other.text.trim());
        }
      }

      return Conversation(
          groupChat: decoded["groupOnly"] == "ja",
          onlyPrivateAnswers: decoded["privateAnswerOnly"] == "ja",
          noReply: decoded["noAnswerAllowed"] == "ja",
          parent: parent,
          countStudents: countStudents,
          countTeachers: countTeachers,
          countParents: countParents,
          knownParticipants: knownParticipants,
          replies: replies
      );
    } on (SocketException, DioException) {
      throw NetworkException();
    }
  }

  /// Replies to an already existing conversation.
  ///
  /// [headId] is the **"Uniquid"** of the head message.
  ///
  /// [groupOnly] and [privateAnswerOnly] are only checked for existence and then ignored.
  ///
  /// [sender] is the **"Sender"** of the head message, you can also use **"all"**.
  ///
  /// [message] supports Lanis-styled text.
  ///
  /// If successful, it returns `true`.
  Future<bool> replyToConversation(String headId, String sender, String groupOnly, String privateAnswerOnly, String message) async {
    final Map replyData = {
      "to": sender,
      "groupOnly": groupOnly,
      "privateAnswerOnly": privateAnswerOnly,
      "message": message,
      "replyToMsg": headId,
    };

    String encrypted = client.cryptor.encryptString(json.encode(replyData));

    final response = await dio.post("https://start.schulportal.hessen.de/nachrichten.php",
        data: {
          "a": "reply",
          "c": encrypted,
        },
        options: Options(
          headers: {
            "Accept": "*/*",
            "Content-Type":
            "application/x-www-form-urlencoded; charset=UTF-8",
            "Sec-Fetch-Dest": "empty",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Site": "same-origin",
            "X-Requested-With": "XMLHttpRequest",
          },
        )
    );

    return json.decode(response.data)["back"]; // "back" should be bool, id is Uniquid
  }

  /// Creates a new conversation.
  ///
  /// [receivers] are Strings of Ids which you can get with `Unimplemented`.
  /// Possible receivers are _(from the point of a student)_:
  ///   - Students from the same _Lerngruppe_.
  ///   - All teachers
  ///
  /// [type] is one of the following types:
  ///   - `noAnswerAllowed`
  ///     - **Hinweis**: No answers.
  ///   - `privateAnswerOnly`
  ///     - **Mitteilung**: Answers only to sender.
  ///   - `groupOnly`
  ///     - **Gruppenchat**: Answers to everyone.
  ///   - `openChat`
  ///     - **Offener Chat**: Private messages among themselves possible.
  ///
  ///  [text] also supports Lanis-styled text.
  ///
  ///  If successful, it returns true.
  Future<CreationResponse> createConversation(List<String> receivers, String? type, String subject, String text) async {
    final List<Map<String, String>> createData = [
      {
        "name": "subject",
        "value": subject
      },
      {
        "name": "text",
        "value": text
      },
    ];

    if (type != null) {
      createData.add({
        "name": "Art",
        "value": type
      });
    }

    for (final String receiver in receivers) {
      createData.add({
        "name": "to[]",
        "value": receiver
      });
    }

    String encrypted = client.cryptor.encryptString(json.encode(createData));

    final response = await dio.post("https://start.schulportal.hessen.de/nachrichten.php",
        data: {
          "a": "newmessage",
          "c": encrypted,
        },
        options: Options(
          headers: {
            "Accept": "*/*",
            "Content-Type":
            "application/x-www-form-urlencoded; charset=UTF-8",
            "Sec-Fetch-Dest": "empty",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Site": "same-origin",
            "X-Requested-With": "XMLHttpRequest",
          },
        )
    );

    final Map decoded = json.decode(response.data);

    return CreationResponse(success: decoded["back"], id: decoded["id"]); // "back" should be bool, id is Uniquid
  }

  Future<bool> canChooseType() async {
    final html = await dio.get("https://start.schulportal.hessen.de/nachrichten.php",
        options: Options(
          headers: {
            "Accept": "*/*",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "none",
          },
        )
    );

    final document = parse(html.data);

    return document.querySelector("#MsgOptions") != null;
  }

  /// Searches for teacher using at least 2 chars.
  ///
  /// Returns false if no one was found or a error happened.
  /// On success, returns list of `SearchEntry`.
  Future<dynamic> searchTeacher(String name) async {
    if (name.length < 2) {
      return false;
    }

    final response = await dio.get("https://start.schulportal.hessen.de/nachrichten.php",
        queryParameters: {
          "a": "searchRecipt",
          "q": name
        },
        options: Options(
          headers: {
            "Accept": "*/*",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "none",
          },
        )
    );

    final data = json.decode(response.data);

    if (data["items"] != null && data["items"].isNotEmpty) {
      final List<ReceiverEntry> teacherEntries = [];

      for (final teacher in data["items"]) {
        teacherEntries.add(ReceiverEntry(
            teacher["id"]!,
            teacher["text"]!
        ));
      }

      return teacherEntries;
    }

    return false;
  }
}
