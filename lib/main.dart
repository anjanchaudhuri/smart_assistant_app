import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:smart_assistant_app/utils.dart';

import 'utils.dart';

import 'package:dialogflow_v2/model/audio_input_config.dart';
import 'package:dialogflow_v2/model/output_audio_config.dart';
import 'package:dialogflow_v2/model/output_audio_encoding.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// import 'package:flutter/services.dart';
import 'package:dialogflow_v2/dialogflow_v2.dart' as df;
import 'package:flutter/services.dart';

// import 'my_dialogflow_v2.dart' as df;
// import 'my_auth_google.dart';
// import 'my_language.dart';
// import 'my_message.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sound_stream/sound_stream.dart';

// import 'package:speech_recognition/speech_recognition.dart';
// import 'package:volume_watcher/volume_watcher.dart';
import 'package:xml/xml.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Assistant',
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
        primarySwatch: Colors.green,
      ),
      home: MyHomePage(title: 'Aramco Digital Assistant'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  RecorderStream _recorder = RecorderStream();
  PlayerStream _player = PlayerStream();
  List<Uint8List> _micChunks = [];
  bool _isRecording = false;
  bool _isPlaying = false;

  StreamSubscription _recorderStatus;
  StreamSubscription _playerStatus;
  StreamSubscription _microphoneStream;

  Timer _utteranceMonitor;

  @override
  void initState() {
    super.initState();
    initSoundPlugin();
  }

  @override
  void dispose() {
    _recorderStatus?.cancel();
    _playerStatus?.cancel();
    _microphoneStream?.cancel();
    super.dispose();
  }

  Future<void> initSoundPlugin() async {
    _recorderStatus = _recorder.status.listen((status) {
      if (mounted)
        setState(() {
          _isRecording = status == SoundStreamStatus.Playing;
        });
    });

    _microphoneStream = _recorder.audioStream.listen((data) {
      // if (_isPlaying) {
      //   _player.writeChunk(data);
      // } else {
      //   _micChunks.add(data);
      // }
      _micChunks.add(data);
    });

    _playerStatus = _player.status.listen((status) {
      if (mounted)
        setState(() {
          _isPlaying = status == SoundStreamStatus.Playing;
        });
    });

    await Future.wait([
      _recorder.initialize(),
      _player.initialize(),
    ]);

    // Print sound plugin states
    print('Recorder status: $_recorderStatus');
    print('Is Recording: $_isRecording');
    print('(Audio) Player status: $_playerStatus');
    print('Is (audio) playing: $_isPlaying');
  }

  final List<ChatMessage> _messages = <ChatMessage>[];
  final TextEditingController _textController = TextEditingController();
  bool _micOn = false;
  bool _speakerOn = false;

  // Future<void> _launched;

  Future<void> launchInBrowser(String url) async {
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw ('Could not launch $url');
    }
  }

  Widget _buildTextComposer() {
    return IconTheme(
      data: IconThemeData(color: Theme.of(context).accentColor),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          children: <Widget>[
            Flexible(
              child: TextField(
                controller: _textController,
                onSubmitted: handleSubmitted,
                decoration:
                    InputDecoration.collapsed(hintText: 'Send a message'),
              ),
            ),
            Container(
              // margin: EdgeInsets.symmetric(horizontal: 4.0),
              child: IconButton(
                icon: Icon(Icons.send),
                onPressed: () => handleSubmitted(_textController.text),
              ),
            ),
            Container(
              // margin: EdgeInsets.symmetric(horizontal: 4.0),
              child: IconButton(
                icon: Icon(_selectMicIcon()),
                onPressed: () => _toggleMicState(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _selectMicIcon() {
    // if (_isAvailable) {
    //   return _micOn ? Icons.mic_rounded : Icons.mic_off_rounded;
    // } else {
    //   return Icons.mic_off_outlined;
    // }
    return _micOn ? Icons.mic_rounded : Icons.mic_off_rounded;
  }

  IconData _selectSpeakerIcon() {
    return _speakerOn ? Icons.volume_up : Icons.volume_off;
  }

  void _toggleMicState() async {
    setState(() {
      // if (_isAvailable) {
      //   _micOn = (_micOn ? false : true);
      // } else {
      //   _micOn = false;
      // }
      _micOn = (_micOn ? false : true);
      _selectMicIcon();
      // Test microphone usage
    });
    print('Mic is ${_micOn ? 'on' : 'off'}');
    if (_micOn) {
      listenToUser();
      _utteranceMonitor = Timer(Duration(seconds: 5), _toggleMicState);
    } else {
      playbackUserSpeech();
    }
  }

  void _toggleSpeakerState() async {
    setState(() {
      _speakerOn = (_speakerOn ? false : true);
      _selectSpeakerIcon();
      _speakerOn ? _player.start() : _player.stop();
    });
  }

  /// Listen to user as they speak
  void listenToUser() async {
    print('In listenToUser()');
    // if (_isPlaying) {
    //   await _player.stop();
    // }
    await _recorder.start();
    // _audioStream = _recorder.audioStream.listen((data) {
    //   _micChunks.add(data);
    // });
    // _printSpeechRecognizerStatus();
    // if (_isAvailable && !_isListening) {
    //   _speechRecognition
    //       .listen(locale: 'en_US')
    //       .then((value) => print('Speech recognizer listening: $value'))
    //       .onError((error, stackTrace) {
    //     print('Speech recognizer error: ${error.runtimeType}');
    //     print('Error stacktrace: $stackTrace');
    //   });
    // }
  }

  /// Play back what the user just said
  void playbackUserSpeech() async {
    if (_utteranceMonitor.isActive) {
      _utteranceMonitor.cancel();
    }
    print('In playbackUserSpeech()');
    // await _recorder.stop();
    submitUserUtterances();
    //
    // for (Uint8List chunk in _micChunks) {
    //   _playAudio(base64.encode(chunk));
    //   // _player.writeChunk(chunk);
    // }
    //
    // // Empty out the array of sound bytes
    // _micChunks.clear();
    // _printSpeechRecognizerStatus();
    // if (_isListening) {
    //   _speechRecognition.stop().then((value) {
    //     setState(() => _isListening = value);
    //     _printSpeechRecognizerStatus();
    //     handleSubmitted(_textController.text);
    //   });
    // }
  }

  // void _printSpeechRecognizerStatus() {
  //   print('Speech recognizer is available: $_isAvailable');
  //   print('Speech recognizer listening status: $_isListening');
  // }

  Future<void> response(df.DetectIntentRequest query) async {
    _textController.clear();
    df.AuthGoogle authGoogle =
        await df.AuthGoogle(fileJson: '.secret/smart_assistant.json').build();
    df.Dialogflow dialogflow = df.Dialogflow(
        authGoogle: authGoogle,
        language: df.Language.english //DateTime.now().toIso8601String()
        );
    df.DetectIntentResponse response = await dialogflow.detectIntent(query);

    print("---- debug info $query -----");
    print(
        'Number of messages in response: ${response.getListMessage().length}');
    for (int i = 0; i < response.getListMessage().length; ++i) {
      String msgType = response.getListMessage()[i] == null
          ? null
          : response.getListMessage()[i].runtimeType.toString();
      print('$i: $msgType');
    }
    // final DateFormat format = DateFormat('E MMM d, yyyy hh:mm');
    // print(format.format(DateTime.now()));
    // print(response.toJson());

    // Display the user query text after obtaining their query text
    // from STT api call, when the user was speaking to the bot.
    if (response.outputAudioConfig != null || response.outputAudio != null) {
      // Output is an audio in response to input audio
      // So, the user input text is obtained from speech-to-text api call
      // No explicit text was typed by the user
      print(
          'Output Audio Config in response: ${response.outputAudioConfig.toJson()}');
      print('Output audio: ${response.outputAudio.length}');

      // Play audio response from Dialogflow
      await _playAudio(response.outputAudio);
    }

    print("---- end debug info -----");

    // In case the user did not explicitly type their queries
    // from the keyboard.
    if (query.queryInput.text == null) {
      ChatMessage userQuery = ChatMessage(
        text: response.queryResult.queryText,
        name: 'User',
        type: true,
        now: DateTime.now(),
      );
      setState(() {
        _messages.insert(0, userQuery);
      });
    }

    // Display bot response (rich)
    ChatMessage message = ChatMessage(
      text: _parseXml(response.getMessage()),
      aiResponse: response,
      name: 'Bot',
      type: false,
      now: DateTime.now(),
      pageState: this,
    );
    setState(() {
      _messages.insert(0, message);
    });
  }

  /// Parse XML fragment
  String _parseXml(String xml) {
    String simpleText;
    if (xml.startsWith('\<') && xml.endsWith('\>')) {
      var doc = XmlDocument.parse(xml);
      simpleText = doc.root.firstChild.text;
    } else {
      simpleText = xml;
    }
    print('Text: $simpleText');
    return simpleText;
  }

  /// Submit user query from keyboard input (text message)
  void handleSubmitted(String text) async {
    _textController.clear();
    ChatMessage message = ChatMessage(
      text: text,
      name: 'User',
      type: true,
      now: DateTime.now(),
    );
    setState(() {
      _messages.insert(0, message);
    });

    // Check current volume
    // print('Current volume is: $_currentVolume');
    // VolumeController.volumeListener.listen((event) {
    //   setState(() {
    //     _volumeListenerValue = event;
    //   });
    // });
    //
    // VolumeController.getVolume()
    //     .then((value) => setState(() => _volumeSet = value));
    //
    // print('Phone listener volume is $_volumeListenerValue');
    // print('Phone current volume is $_volumeSet');

    // Build DetectIntentRequest
    df.DetectIntentRequest request;
    if (_speakerOn) {
      //_currentVolume > 0
      request = df.DetectIntentRequest(
        queryInput: df.QueryInput(
          text: df.TextInput(text: text, languageCode: df.Language.english),
        ),
        outputAudioConfig: this.outputAudioConfig,
      );
    } else {
      request = df.DetectIntentRequest(
        queryInput: df.QueryInput(
          text: df.TextInput(text: text, languageCode: df.Language.english),
        ),
        // outputAudioConfig: this.outputAudioConfig,
      );
    }

    // Call Dialogflow
    await response(request);
  }

  /// Submit user utterances
  void submitUserUtterances() async {
    if (_micChunks.isNotEmpty) {
      // We have some utterance from the user
      print('We have ${_micChunks.length} count of utterances!');
      List<int> byteList = [];
      for (int i = 0; i < _micChunks.length; ++i) {
        byteList.addAll(_micChunks[i]);
      }
      Uint8List soundBytes = new Uint8List.fromList(byteList);
      _submitUserQuery(base64.encode(soundBytes));

      // StringBuffer audioBuffer = new StringBuffer();
      // for (var chunk in _micChunks) {
      //   audioBuffer.write(base64.encode(chunk));
      // }
      // _submitUserQuery(audioBuffer.toString());

      _micChunks.clear();
    }
  }

  /// Submit user query to Dialogflow
  void _submitUserQuery(String audioString) async {
    // var inputAudio = base64.encode(audioBytes);
    // Check current volume
    // print('Current volume is: $_currentVolume');

    _submitUserSpeech(audioString);
    // _playAudio(audioString);
  }

  /// Input audio config
  InputAudioConfig get inputAudioConfig {
    return df.InputAudioConfig(
      audioEncoding: df.AudioEncoding.linear16,
      sampleRateHertz: 16000,
      languageCode: df.Language.english,
      enableWordInfo: true,
      singleUtterance: true,
    );
  }

  /// Output audio config
  OutputAudioConfig get outputAudioConfig {
    return OutputAudioConfig(
      audioEncoding: OutputAudioEncoding.linear16,
      sampleRateHertz: 16000,
    );
  }

  /// Play audio received from Dialogflow
  Future<void> _playAudio(String audio) async {
    if (audio != null && audio.length > 0) {
      print('Playing audio response from Dialogflow...');
      _player.audioStream.add(base64.decode(audio));
      print('Finished queueing response from Dialogflow');
      // _player.writeChunk(base64.decode(audio));
    }
    // await _player.stop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
            icon: Icon(_selectSpeakerIcon()),
            onPressed: () => _toggleSpeakerState(),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // VolumeWatcher(
          //   onVolumeChangeListener: (double volume) {
          //     setState(() {
          //       _currentVolume = volume;
          //     });
          //   },
          // ),
          Flexible(
              child: ListView.builder(
            padding: EdgeInsets.all(8.0),
            reverse: true,
            itemBuilder: (_, int index) => _messages[index],
            itemCount: _messages.length,
          )),
          Divider(height: 1.0),
          Container(
            decoration: BoxDecoration(color: Theme.of(context).cardColor),
            child: _buildTextComposer(),
          ),
        ],
      ),
    );
    // throw UnimplementedError();
  }

  void _submitUserSpeech(String inputAudio) async {
    // Build DetectIntentRequest
    df.DetectIntentRequest request;
    if (_speakerOn) {
      //_currentVolume > 0
      request = df.DetectIntentRequest(
        queryInput: df.QueryInput(
          audioConfig: this.inputAudioConfig,
        ),
        inputAudio: inputAudio,
        outputAudioConfig: this.outputAudioConfig,
      );
    } else {
      request = df.DetectIntentRequest(
        queryInput: df.QueryInput(
          audioConfig: this.inputAudioConfig,
        ),
        inputAudio: inputAudio,
      );
    }

    print('_submitUserSpeech');
    // Utils.printWrapped(request.toJson().toString());

    // Call Dialogflow
    response(request);
  }
}

class ChatMessage extends StatelessWidget {
  final String text;
  final df.DetectIntentResponse aiResponse;
  final String name;
  final bool type;
  final DateTime now;
  final _MyHomePageState pageState;

  // Constructor
  ChatMessage(
      {this.text,
      this.aiResponse,
      this.name,
      this.type,
      this.now,
      this.pageState});

  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    return Container(
      margin: EdgeInsets.symmetric(
        vertical: 10.0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: this.type ? myMessage(context) : otherMessage(context),
      ),
    );
    // throw UnimplementedError();
  }

  String _format(DateTime moment) {
    String _formattedDate;
    DateFormat _formatter;
    DateTime today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    DateTime _eventDay = DateTime(moment.year, moment.month, moment.day);
    int _dateDifference = today.difference(_eventDay).inDays;

    print('Date Difference: $_dateDifference');

    if (_dateDifference == 0) {
      _formatter = DateFormat('HH:mm');
      _formattedDate = _formatter.format(moment);
    } else if (_dateDifference == 1) {
      _formatter = DateFormat('\'Yesterday\' HH:mm');
    } else {
      _formatter = DateFormat('E MMM d, yyyy HH:mm');
    }
    _formattedDate = _formatter.format(moment);
    print('Formatted $moment: $_formattedDate');
    return _formattedDate;
  }

  List<Widget> myMessage(BuildContext context) {
    return <Widget>[
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              _format(this.now),
              style: Theme.of(context).textTheme.bodyText2,
            ),
            Text(
              this.name,
              style: Theme.of(context).textTheme.subtitle1,
            ),
            Container(
              margin: EdgeInsets.only(top: 5.0),
              child: Text(text),
            ),
          ],
        ),
      ),
      Container(
        margin: EdgeInsets.only(left: 16.0),
        child: CircleAvatar(
          child: Text(this.name[0]),
        ),
      ),
    ];
  }

  List<Widget> otherMessage(BuildContext context) {
    return <Widget>[
      Container(
        margin: EdgeInsets.only(right: 16.0),
        child: CircleAvatar(
          child: Image.asset('assets/aramco.png'),
        ),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: richResponse(context),
          // <Widget>[
          //   Text(
          //     this.name,
          //     style: TextStyle(fontWeight: FontWeight.bold),
          //   ),
          //   Container(
          //     margin: EdgeInsets.only(top: 5.0),
          //     child: Text(text),
          //   ),
          // ],
        ),
      ),
    ];
  }

  List<Widget> _textResponse(BuildContext context) {
    return <Widget>[
      Text(
        this.name,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      Container(
        margin: EdgeInsets.only(top: 5.0),
        child: Text(text),
      ),
    ];
  }

  /// This method renders the rich responses from Dialogflow
  List<Widget> richResponse(BuildContext context) {
    List<Widget> _response = [];
    print('Rich response size: ${_response.length}');
    _response.addAll(_textResponse(context));
    print('Rich response size: ${_response.length}');

    // Process each message in the query result.
    for (int i = 0; i < aiResponse.getListMessage().length; ++i) {
      // Determine the rich response type
      // Render rich response based on its type
      var msg = aiResponse.getListMessage()[i];
      if (msg is df.Suggestions) {
        _response.add(renderSuggestions(context, msg));
        print(
            'Added suggestion chips. Rich response size: ${_response.length}');
      } else if (msg is df.BasicCard) {
        _response.add(renderBasicCard(context, msg));
        print('Added basic card. Rich response size: ${_response.length}');
      }
    }
    return _response;
  }

  /// This method displays the UI of a Basic Card
  Widget renderBasicCard(BuildContext context, df.BasicCard msg) {
    List<Widget> buttons = [];
    // Add basic card buttons
    for (int i = 0; i < msg.buttons.length; ++i) {
      buttons.add(ElevatedButton(
        style: ElevatedButton.styleFrom(
          primary: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30.0),
          ),
          textStyle: TextStyle(
            color: Colors.white,
          ),
        ),
        child: Text(
          msg.buttons[i].title,
        ),
        onPressed: () => launch(msg.buttons[i].openUriAction.uri),
      ));
    }

    // // Build children of the column
    // List<Widget> colChildren = [];

    // Return a container with a column containing all components
    // of the Basic Card
    return Container(
      padding: EdgeInsets.all(5.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(width: 0.25),
        color: Colors.blueGrey[50],
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            spreadRadius: 5,
            blurRadius: 7,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Text(msg.title ?? 'Basic Card Title',
          //   style: Theme.of(context).textTheme.headline5,
          // ),
          // Text(msg.subtitle ?? 'Sub Title',
          //   style: Theme.of(context).textTheme.subtitle1,
          // ),
          Text(
            msg.formattedText ?? 'Click or tap below',
            style: TextStyle(
              color: Colors.teal[800],
              fontWeight: FontWeight.normal,
              fontStyle: FontStyle.italic,
            ),
          ),
          Image.network(msg.image.imageUri),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: buttons,
          ),
        ],
      ),
    );
  }

  /// This method displays the UI for Suggestion chips
  Widget renderSuggestions(BuildContext context, df.Suggestions msg) {
    List<Widget> chips = [];

    for (int i = 0; i < msg.suggestions.length; ++i) {
      chips.add(ElevatedButton(
        style: ElevatedButton.styleFrom(
          primary: Theme.of(context).primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30.0),
          ),
          textStyle: TextStyle(
            color: Colors.white,
          ),
        ),
        child: Text(
          msg.suggestions[i].title,
        ),
        onPressed: () =>
            this.pageState.handleSubmitted(msg.suggestions[i].title),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: chips,
    );
  }
}
