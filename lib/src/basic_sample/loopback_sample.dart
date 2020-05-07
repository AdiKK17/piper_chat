import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'dart:core';
import 'dart:async';

import 'package:flutter_socket_io/flutter_socket_io.dart';
import 'package:flutter_socket_io/socket_io_manager.dart';
import 'package:http/http.dart' as http;


class LoopBackSample extends StatefulWidget {

  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<LoopBackSample> {
  SocketIO socketIO;

  MediaStream _localStream;
  RTCPeerConnection _peerConnection;
  final _localRenderer = new RTCVideoRenderer();
  final _remoteRenderer = new RTCVideoRenderer();
  bool _inCalling = false;

  var roomId;
  var roomText = "Hello";

  TextEditingController textController;

  var calleeCandidates = [];
  var answerSdp;

  @override
  initState() {
    super.initState();
    textController = TextEditingController();

    //Creating the socket
    socketIO = SocketIOManager().createSocketIO(
      'https://singis.herokuapp.com/',
      '/',
    );

    //Call init before doing anything with socket
    socketIO.init();

    //Connect to the socket
    socketIO.connect();

    initRenderers();
  }

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();
    socketIO.unSubscribesAll();
    socketIO.disconnect();
  }

  @override
  deactivate() {
    super.deactivate();
    if (_inCalling) {
      _hangUp();
    }
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }


  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  _onSignalingState(RTCSignalingState state) {
    print(state);
  }

  _onIceGatheringState(RTCIceGatheringState state) {
    print(state);
  }

  _onIceConnectionState(RTCIceConnectionState state) {
    print(state);
  }

  _onAddStream(MediaStream stream) {
    print('addStream: ' + stream.id);
    _remoteRenderer.srcObject = stream;
  }

  _onRemoveStream(MediaStream stream) {
    _remoteRenderer.srcObject = null;
  }

  _onCandidate(RTCIceCandidate candidate) {
    if (candidate.candidate.isEmpty) {
      print("Got final candidate!");
      return;
    }
    print('onCandidate: ' + candidate.candidate);
    socketIO.sendMessage(
        "add_caller_candidates",
        json.encode({"roomId": roomId,"candidate": candidate.toMap()})
    );
//    _peerConnection.addCandidate(candidate);
  }

  _onCandidate121(RTCIceCandidate candidate) {
    if (candidate.candidate.isEmpty) {
      print("Got final candidate!");
//      socketIO.sendMessage("get_callee_candidates", json.encode({"roomId": roomId}));
      return;
    }
    print('onCandidate: ' + candidate.candidate);
    socketIO.sendMessage(
        "add_callee_candidates",
        json.encode({"roomId": roomId,"candidate": candidate.toMap()})
    );
//    _peerConnection.addCandidate(candidate);
  }

  _onRenegotiationNeeded() {
    print('RenegotiationNeeded');
  }

  _subscribeCreateRoomEvents() async {
    socketIO.subscribe("recieve_answer_sdp", (answer) async {
      print("recieve_answer_sdp");
      Map<String,dynamic> answerSdp = json.decode(answer);
      await _peerConnection.setRemoteDescription(new RTCSessionDescription(answerSdp["sdp"],answerSdp["type"]));
      print("remote description set");
    });

    socketIO.subscribe("recieve_callee_candidates", (candidate) async {
      Map<String,dynamic> candi = json.decode(candidate);
      calleeCandidates.add(candidate);
      print("recieve_callee_candidate");
      print(calleeCandidates.length);
      await _peerConnection.addCandidate(RTCIceCandidate(candi["candidate"], candi["sdpMid"], candi["sdpMLineIndex"]));
    });
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  _makeCall() async {

    await _openMedia();

    final response = await http.get("https://singis.herokuapp.com/create_room");
    roomId = response.body;

    await _subscribeCreateRoomEvents();

    setState(() {
      roomText =
          "Current room is :-" + roomId + " - You are the Caller";
    });

//    Map<String, dynamic> configuration = {
//      "iceServers":{
//        "urls": [
//              'stun:stun1.l.google.com:19302',
//              'stun:stun2.l.google.com:19302',
//              ]
//        ,}
//    };
    Map<String, dynamic> configuration = {
      "iceServers": [
        {"url": "stun:stun.l.google.com:19302"},
      ]
    };

    final Map<String, dynamic> offer_sdp_constraints = {
      "mandatory": {
        "OfferToReceiveAudio": true,
        "OfferToReceiveVideo": true,
      },
      "optional": [],
    };

    final Map<String, dynamic> loopback_constraints = {
      "mandatory": {},
      "optional": [
        {"DtlsSrtpKeyAgreement": false},
      ],
    };

    if (_peerConnection != null) return;

    try {
      _peerConnection =
          await createPeerConnection(configuration, loopback_constraints);

      _peerConnection.onSignalingState = _onSignalingState;
      _peerConnection.onIceGatheringState = _onIceGatheringState;
      _peerConnection.onIceConnectionState = _onIceConnectionState;
      _peerConnection.onAddStream = _onAddStream;
      _peerConnection.onRemoveStream = _onRemoveStream;
      _peerConnection.onIceCandidate = _onCandidate;
      _peerConnection.onRenegotiationNeeded = _onRenegotiationNeeded;

      _peerConnection.addStream(_localStream);

      RTCSessionDescription description =
          await _peerConnection.createOffer(offer_sdp_constraints);
      print(description.sdp);
      _peerConnection.setLocalDescription(description);

      final roomWithOffer = json.encode({
        "offer": {
          "type": description.type,
          "sdp": description.sdp,
        },
        "roomId": roomId
      });

      socketIO.sendMessage(
          "create_room",
          roomWithOffer
      );

      setState(() {
        roomText =
            "Current room is :-" + roomId + " - You are the Caller";
      });

      //change for loopback.
      //setting remote description

//      description.type = "answer";
//      _peerConnection.setRemoteDescription(description);

      _localStream.getAudioTracks()[0].setMicrophoneMute(false);
    } catch (e) {
      print(e.toString());
    }
    if (!mounted) return;

    _inCalling = true;
  }


  _openMedia() async {
    final Map<String, dynamic> mediaConstraints = {
      "audio": true,
      "video": {
        "mandatory": {
          "minWidth":
              '640', // Provide your own width, height and frame rate here
          "minHeight": '480',
          "minFrameRate": '30',
        },
        "facingMode": "user",
        "optional": [],
      }
    };
    _localStream = await navigator.getUserMedia(mediaConstraints);
    _localRenderer.srcObject = _localStream;
  }

  _joinRoom() async {

    await _openMedia();

    roomId = textController.text;
    setState(() {
      roomText = "Current room is :-" + roomId + " - You are the Callee";
    });

    socketIO.sendMessage('join_room',
    json.encode({"roomId": roomId}));


    Map<String, dynamic> configuration = {
      "iceServers": [
        {"url": "stun:stun.l.google.com:19302"},
      ]
    };

    final Map<String, dynamic> loopback_constraints = {
      "mandatory": {},
      "optional": [
        {"DtlsSrtpKeyAgreement": false},
      ],
    };

    final Map<String, dynamic> answer_sdp_constraints = {
      "mandatory": {
        "OfferToReceiveAudio": true,
        "OfferToReceiveVideo": true,
      },
      "optional": [],
    };

    _peerConnection =
        await createPeerConnection(configuration, loopback_constraints);

    print("<<<<<<<<<<<<<<<<<1>>>>>>>>>>>>>>>>");
    _peerConnection.onSignalingState = _onSignalingState;
    _peerConnection.onIceGatheringState = _onIceGatheringState;
    _peerConnection.onIceConnectionState = _onIceConnectionState;
    _peerConnection.onAddStream = _onAddStream;
    _peerConnection.onRemoveStream = _onRemoveStream;
    _peerConnection.onIceCandidate = _onCandidate121;
    _peerConnection.onRenegotiationNeeded = _onRenegotiationNeeded;

    _peerConnection.addStream(_localStream);

    print("<<<<<<<<<<<<<<<<<2>>>>>>>>>>>>>>>>");
    final response = await http.post("https://singis.herokuapp.com/get_room_details",body: json.encode({"roomId": roomId}),headers: {"Content-Type" : "application/json"});
    final responseData = json.decode(response.body);

    print("<<<<<<<<<<<<<<<<<3>>>>>>>>>>>>>>>>");

    final offer = responseData["offerSdp"];
    await _peerConnection
        .setRemoteDescription(new RTCSessionDescription(offer["sdp"], offer["type"]));

    final answer = await _peerConnection.createAnswer(answer_sdp_constraints);
    await _peerConnection.setLocalDescription(answer);

    final roomWithAnswer = json.encode({
      "answer": {
        "type": answer.type,
        "sdp": answer.sdp,
      },
      "roomId": roomId
    });

    socketIO.sendMessage('add_answer_sdp', roomWithAnswer);

    responseData["callerCandidates"].forEach((candidate) async {
      calleeCandidates.add(candidate);
      print("recieve_caller_candidate");
      print(calleeCandidates.length);
      if(candidate["candidate"] != null) {
        await _peerConnection.addCandidate(new RTCIceCandidate(
            candidate["candidate"], candidate["sdpMid"],
            candidate["sdpMLineIndex"]));
      }
    });

  }

  _deleteRoom() {}

  _hangUp() async {
    try {
      await _localStream.dispose();
      await _peerConnection.close();
      _peerConnection = null;
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
    } catch (e) {
      print(e.toString());
    }
    setState(() {
      _inCalling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text('LoopBack example'),
        actions: <Widget>[IconButton(icon: Icon(Icons.description), onPressed: (){
           socketIO.sendMessage(
              "show_room",
        json.encode({"roomId": roomId})
          );
        })],
      ),
      body: new SingleChildScrollView(
        child: OrientationBuilder(
          builder: (context, orientation) {
            return new Center(
              child: new Container(
                decoration: new BoxDecoration(color: Colors.white),
                child: Column(
                  children: <Widget>[
                    Container(
                      child: Center(
                        child: Text(roomText),
                      ),
                      height: 100,
                      color: Colors.amberAccent,
                    ),
                    SizedBox(
                      height: 20,
                    ),
                    new Container(
                      margin: new EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                      width: 320.0,
                      height: 240.0,
                      child: new RTCVideoView(_localRenderer),
                      decoration: new BoxDecoration(color: Colors.black54),
                    ),
                    SizedBox(
                      height: 40,
                    ),
                    new Container(
                      margin: new EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                      width: 320.0,
                      height: 240.0,
                      child: new RTCVideoView(_remoteRenderer),
                      decoration: new BoxDecoration(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          FloatingActionButton(
            heroTag: "2",
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  // return object of type Dialog
                  return AlertDialog(
                    title: new Text("Add roomId"),
                    content: TextField(
                      maxLines: 1,
                      controller: textController,
                      decoration:
                          InputDecoration.collapsed(hintText: "Room-ID"),
                    ),
                    actions: <Widget>[
                      // usually buttons at the bottom of the dialog
                      new FlatButton(
                        child: new Text("Join"),
                        onPressed: () {
                          Navigator.of(context).pop();
                          _joinRoom();
                        },
                      ),
                      new FlatButton(
                        child: new Text("Close"),
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  );
                },
              );
            },
            tooltip: "join Room",
            child: new Icon(Icons.people),
          ),
          FloatingActionButton(
            heroTag: "3",
            onPressed: _makeCall,
            tooltip: 'Open Media and Create room',
            child: new Icon(Icons.phone),
          ),
          FloatingActionButton(
            heroTag: "4",
            onPressed: _hangUp,
            tooltip: 'Hangup',
            child: new Icon(Icons.cancel),
          ),
        ],
      ),
    );
  }
}
