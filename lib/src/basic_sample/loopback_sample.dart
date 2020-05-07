import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'dart:core';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

class LoopBackSample extends StatefulWidget {
  static String tag = 'loopback_sample';

  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<LoopBackSample> {
  MediaStream _localStream;

  RTCPeerConnection _peerConnection;
  final _localRenderer = new RTCVideoRenderer();
  final _remoteRenderer = new RTCVideoRenderer();
  bool _inCalling = false;

  final db = Firestore.instance;
  var roomRef;
  var roomText = "Hello";

  StreamController streamController;
  StreamController streamController1;

//  var roomId;
  TextEditingController textController;

  @override
  initState() {
    super.initState();
    textController = TextEditingController();
    streamController = new StreamController();
    streamController1 = new StreamController();
    initRenderers();
  }

  @override
  void dispose() {
    // TODO: implement dispose
      super.dispose();
      streamController.close();
      streamController1.close();
  }

  @override
  deactivate() {
    super.deactivate();
    if (_inCalling) {
      _hangUp();
    }
    _localRenderer.dispose();
    _remoteRenderer.dispose();
//    streamController.close();
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
    roomRef.collection('callerCandidates').add(candidate.toMap());
    _peerConnection.addCandidate(candidate);
  }

  _onCandidate121(RTCIceCandidate candidate) {
    if (candidate.candidate.isEmpty) {
      print("Got final candidate!");
      return;
    }
    print('onCandidate: ' + candidate.candidate);
    roomRef.collection('calleeCandidates').add(candidate.toMap());
    _peerConnection.addCandidate(candidate);
  }

  _onRenegotiationNeeded() {
    print('RenegotiationNeeded');
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  _makeCall() async {
    roomRef = db.collection("rooms").document();

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
      await _openMedia();
      _localRenderer.srcObject = _localStream;

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

      final roomWithOffer = {
        'offer': {
          "type": description.type,
          "sdp": description.sdp,
        },
      };

      await roomRef.setData(roomWithOffer);
      setState(() {
        roomText =
            "Current room is :-" + roomRef.documentID + " - You are the Caller";
      });

      //change for loopback.
      //setting remote description

      print("312312312312314343");
      streamController.addStream(roomRef.snapshots());
      streamController.stream.listen((event) async {

        final data = event.data;

        if(event.data["answer"] != null) {
          print(data["answer"]["sdp"]);
          print(data["answer"]["type"]);
          final rtcSessionDescription = new RTCSessionDescription(data["answer"]["sdp"],data["answer"]["type"]);
          await _peerConnection.setRemoteDescription(rtcSessionDescription);
        }

        print("jajajajajjajaj");
        print("jajajajajjajaj");
        print("jajajajajjajaj");

      });
      print("312312312312314343");
      
      streamController1.addStream(roomRef.collection("calleeCandidates").snapshots());
      streamController1.stream.listen((candi) {
        print("object");
        print("<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
        print("<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
        print("<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
        print(candi);

        candi.getDocuments().forEach((change) {
            print(change);
        });
      });



//      StreamBuilder<QuerySnapshot>(
//        stream: roomRef.collection('calleeCandidates').snapshots(),
//        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
//
//          snapshot.data.documentChanges.forEach((element) {
//            if(element.type.toString() ==  "added"){
//              print("heloassdasdaso");
//              print(element.document.data);
//            }
//          });
//
//          return Container();
//        },
//      );

      description.type = 'answer';
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
  }

  _joinRoom() async {

    final roomId = textController.text;
    print(roomId);

    roomRef = db.collection("rooms").document(roomId);

    await _openMedia();
    _localRenderer.srcObject = _localStream;
    setState(() {
      roomText = "Current room is :-" + roomId + " - You are the Callee";
    });

    //
    final roomSnapshot = await roomRef.get();
    //

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

    _peerConnection.onSignalingState = _onSignalingState;
    _peerConnection.onIceGatheringState = _onIceGatheringState;
    _peerConnection.onIceConnectionState = _onIceConnectionState;
    _peerConnection.onAddStream = _onAddStream;
    _peerConnection.onRemoveStream = _onRemoveStream;
    _peerConnection.onIceCandidate = _onCandidate121;
    _peerConnection.onRenegotiationNeeded = _onRenegotiationNeeded;

    final offer = roomSnapshot.data["offer"];
    await _peerConnection
        .setRemoteDescription(new RTCSessionDescription(offer["sdp"], offer["type"]));

    final answer = await _peerConnection.createAnswer(answer_sdp_constraints);
    await _peerConnection.setLocalDescription(answer);

    final roomWithAnswer = {
      "answer": {
        "type": answer.type,
        "sdp": answer.sdp,
      },
    };

    await roomRef.updateData(roomWithAnswer);

    setState(() {});

//          StreamBuilder<QuerySnapshot>(
//        stream: roomRef.collection('callerCandidates').snapshots(),
//        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
//
//          snapshot.data.documentChanges.forEach((element) {
//            if(element.type.toString() ==  "added"){
//              print("heloassdasdaso");
//              print(element.document.data);
//            }
//          });
//
//          return Container();
//        },
//      );
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
