import 'dart:core';

import 'package:flutter/material.dart';

import 'package:flutter_socket_io/socket_io_manager.dart';
import 'package:flutter_socket_io/flutter_socket_io.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:http/http.dart' as http;

import 'calling_page.dart';

class HomePage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return _HomePage();
  }
}

class _HomePage extends State<HomePage> {
  SocketIO socketIO;

  MediaStream _localStream;
  final _localRenderer = new RTCVideoRenderer();

  bool _videoOn = true;
  bool _micOn = true;
  bool _isLoading = false;
  TextEditingController textController;

  @override
  void initState() {
    super.initState();

    textController = TextEditingController();

    socketIO = SocketIOManager().createSocketIO(
      'https://singis.herokuapp.com/',
      '/',
    );
    socketIO.init();
    socketIO.connect();

    initRenderers();
  }

  @override
  void dispose() {
    super.dispose();
    _hangUp();
  }

  initRenderers() async {
    _localRenderer.objectFit = RTCVideoViewObjectFit.RTCVideoViewObjectFitCover;
    await _localRenderer.initialize();
    await _openMedia();
  }

  _hangUp() async {
    try {
      await _localStream?.dispose();
      _localRenderer.srcObject = null;
      _localRenderer?.dispose();
    } catch (e) {
      print(e.toString());
    }
  }

  _openMedia() async {
    final Map<String, dynamic> mediaConstraints = {
      "audio": true,
      "video": {
        "mandatory": {
          "minWidth":
              "640", // Provide your own width, height and frame rate here
          "minHeight": '480',
          "minFrameRate": '30',
        },
        "facingMode": "user", // or environment
        "optional": [],
      }
    };
    _localStream = await navigator.getUserMedia(mediaConstraints);
    _localRenderer.srcObject = _localStream;
  }

  void killVideo() {
    if (_localStream != null) {
      if (_videoOn) {
        _localStream.getVideoTracks()[0].enabled = false;
        _videoOn = !_videoOn;
      } else {
        _localStream.getVideoTracks()[0].enabled = true;
        _videoOn = !_videoOn;
      }
      setState(() {});
    }
  }

  openDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: new Text("Add roomId"),
          content: TextField(
            maxLines: 1,
            maxLength: 4,
            maxLengthEnforced: true,
            controller: textController,
            decoration: InputDecoration.collapsed(hintText: "Room-ID"),
          ),
          actions: <Widget>[
            // usually buttons at the bottom of the dialog
            new FlatButton(
              child: new Text("Join"),
              onPressed: () {
                Navigator.of(context).pop();

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => CallingPage(
                      socketIO,
                      micOn: _micOn,
                      videoOn: _videoOn,
                      createRoom: false,
                      roomId: textController.text,
                    ),
                  ),
                );
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
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        body: Stack(
          children: [
            Column(
              children: <Widget>[
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        child: RTCVideoView(_localRenderer),
                      ),
                      Positioned(
                        bottom: 5,
                        left: 5,
                        child: FloatingActionButton(
                          backgroundColor:
                              _videoOn ? Colors.tealAccent : Colors.red,
                          heroTag: "0",
                          onPressed: killVideo,
                          tooltip: 'Video',
                          child: _videoOn
                              ? Icon(
                                  Icons.videocam,
                                  color: Colors.black,
                                )
                              : Icon(
                                  Icons.videocam_off,
                                  color: Colors.black,
                                ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: _videoOn
                            ? Container()
                            : Text(
                                "Video is off!",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                      ),
                      Positioned(
                        bottom: 5,
                        right: 5,
                        child: FloatingActionButton(
                          backgroundColor:
                              _micOn ? Colors.tealAccent : Colors.red,
                          heroTag: "1",
                          onPressed: () {
                            setState(() {
                              _micOn = !_micOn;
                            });
                          },
                          tooltip: 'Audio',
                          child: _micOn
                              ? Icon(
                                  Icons.mic,
                                  color: Colors.black,
                                )
                              : Icon(
                                  Icons.mic_off,
                                  color: Colors.black,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Text(
                          "Hello",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ButtonTheme(
                              minWidth:
                                  MediaQuery.of(context).size.width * 0.35,
                              height: 40,
                              child: RaisedButton(
                                color: Colors.cyan,
                                onPressed: openDialog,
                                child: Text(
                                  "Join a Room",
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                            ButtonTheme(
                              minWidth:
                                  MediaQuery.of(context).size.width * 0.35,
                              height: 40,
                              child: RaisedButton(
                                color: Colors.lightBlueAccent,
                                onPressed: () async {
                                  setState(() {
                                    _isLoading = true;
                                  });

                                  final response = await http.get(
                                      "https://singis.herokuapp.com/create_room");

                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => CallingPage(
                                        socketIO,
                                        micOn: _micOn,
                                        videoOn: _videoOn,
                                        createRoom: true,
                                        roomId: response.body,
                                      ),
                                    ),
                                  );

                                  setState(() {
                                    _isLoading = false;
                                  });
                                },
                                child: Text(
                                  "Create a Room",
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
            _isLoading
                ? Container(
                    color: Colors.grey.withOpacity(0.3),
                    height: double.infinity,
                    width: double.infinity,
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                : Container()
          ],
        ),
      ),
    );
  }
}
