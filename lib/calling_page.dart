import 'dart:convert';
import 'dart:core';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/webrtc.dart';

import 'package:flutter_socket_io/flutter_socket_io.dart';
import 'package:share/share.dart';
import 'package:http/http.dart' as http;

class CallingPage extends StatefulWidget {
  final SocketIO socketIO;
  final bool micOn;
  final bool videoOn;
  final bool createRoom;
  final String roomId;

  CallingPage(this.socketIO,
      {this.micOn, this.videoOn, this.createRoom, this.roomId});

  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<CallingPage> {
  MediaStream _localStream;
  RTCPeerConnection _peerConnection;
  final _localRenderer = new RTCVideoRenderer();
  final _remoteRenderer = new RTCVideoRenderer();

  var calleeCandidates = [];
  var answerSdp;

  @override
  initState() {
    super.initState();
    initRenderers();
    widget.createRoom ? _makeCall() : _joinRoom();
  }

  @override
  void dispose() {
    super.dispose();
    _hangUp();
    _localRenderer?.dispose();
    _remoteRenderer?.dispose();
  }

  initRenderers() async {
    _localRenderer.objectFit = RTCVideoViewObjectFit.RTCVideoViewObjectFitCover;
    _remoteRenderer.objectFit =
        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover;
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
    widget.socketIO.sendMessage("add_caller_candidates",
        json.encode({"roomId": widget.roomId, "candidate": candidate.toMap()}));
  }

  _onCandidate121(RTCIceCandidate candidate) {
    if (candidate.candidate.isEmpty) {
      print("Got final candidate!");
      return;
    }
    print('onCandidate: ' + candidate.candidate);
    widget.socketIO.sendMessage("add_callee_candidates",
        json.encode({"roomId": widget.roomId, "candidate": candidate.toMap()}));
  }

  _onRenegotiationNeeded() {
    print('RenegotiationNeeded');
  }

  _subscribeCreateRoomEvents() async {
    widget.socketIO.subscribe("recieve_answer_sdp", (answer) async {
      print("recieve_answer_sdp");
      Map<String, dynamic> answerSdp = json.decode(answer);
      await _peerConnection.setRemoteDescription(
          new RTCSessionDescription(answerSdp["sdp"], answerSdp["type"]));
      print("remote description set");
    });

    widget.socketIO.subscribe("recieve_callee_candidates", (candidate) async {
      Map<String, dynamic> candi = json.decode(candidate);
      calleeCandidates.add(candidate);
      print("recieve_callee_candidate");
      print(calleeCandidates.length);
      await _peerConnection.addCandidate(RTCIceCandidate(
          candi["candidate"], candi["sdpMid"], candi["sdpMLineIndex"]));
    });
  }

  _makeCall() async {
    await _openMedia();
    await _subscribeCreateRoomEvents();

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
        "roomId": widget.roomId
      });

      widget.socketIO.sendMessage("create_room", roomWithOffer);

      //change for loopback.
      //setting remote description
//      description.type = "answer";
//      _peerConnection.setRemoteDescription(description);

      _localStream.getAudioTracks()[0].setMicrophoneMute(false);
    } catch (e) {
      print(e.toString());
    }
    if (!mounted) return;
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

    widget.socketIO
        .sendMessage('join_room', json.encode({"roomId": widget.roomId}));

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

    _peerConnection.addStream(_localStream);

    final response = await http.post(
        "https://singis.herokuapp.com/get_room_details",
        body: json.encode({"roomId": widget.roomId}),
        headers: {"Content-Type": "application/json"});
    final responseData = json.decode(response.body);

    final offer = responseData["offerSdp"];
    await _peerConnection.setRemoteDescription(
        new RTCSessionDescription(offer["sdp"], offer["type"]));

    final answer = await _peerConnection.createAnswer(answer_sdp_constraints);
    await _peerConnection.setLocalDescription(answer);

    final roomWithAnswer = json.encode({
      "answer": {
        "type": answer.type,
        "sdp": answer.sdp,
      },
      "roomId": widget.roomId
    });

    widget.socketIO.sendMessage('add_answer_sdp', roomWithAnswer);

    responseData["callerCandidates"].forEach((candidate) async {
      calleeCandidates.add(candidate);
      print("recieve_caller_candidate");
      print(calleeCandidates.length);
      if (candidate["candidate"] != null) {
        await _peerConnection.addCandidate(new RTCIceCandidate(
            candidate["candidate"],
            candidate["sdpMid"],
            candidate["sdpMLineIndex"]));
      }
    });
  }

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
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: AppBar(
        title: Text('Room ID - ${widget.roomId}'),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.share),
            onPressed: () {
              Share.share("${widget.roomId}");
            },
          ),
        ],
      ),
      backgroundColor: Colors.grey,
      body: Container(
        child: Column(
          children: [
            Expanded(
              child: Card(
                child: RTCVideoView(_localRenderer),
              ),
            ),
            Expanded(
              child: Card(
                child: RTCVideoView(_remoteRenderer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
