import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const StudioApp());

class StudioApp extends StatelessWidget {
  const StudioApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Personal AI Video Studio',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo, brightness: Brightness.dark),
    home: const HomePage(),
  );
}

class Scene {
  Scene({required this.id, required this.path, this.duration = 5, this.prompt = '', this.status = 'ready', this.jobId, this.videoUrl});
  final String id;
  final String path;
  int duration;
  String prompt;
  String status;
  String? jobId;
  String? videoUrl;
  Map<String,dynamic> toJson() => {'id':id,'path':path,'duration':duration,'prompt':prompt,'status':status,'jobId':jobId,'videoUrl':videoUrl};
  factory Scene.fromJson(Map<String,dynamic> j) => Scene(id:j['id'],path:j['path'],duration:j['duration'] ?? 5,prompt:j['prompt'] ?? '',status:j['status'] ?? 'ready',jobId:j['jobId'],videoUrl:j['videoUrl']);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState()=>_HomePageState();
}

class _HomePageState extends State<HomePage> {
  final picker=ImagePicker();
  final scenes=<Scene>[];
  String projectId=DateTime.now().millisecondsSinceEpoch.toString();
  String projectName='My YouTube Video';
  String ratio='16:9';
  String resolution='1080p';
  String backend='http://10.0.2.2:8787';
  bool busy=false;
  String? finalUrl;

  @override void initState(){super.initState(); _load();}

  Future<void> _load() async {
    final p=await SharedPreferences.getInstance();
    setState(() {
      projectId=p.getString('projectId') ?? projectId;
      projectName=p.getString('projectName') ?? projectName;
      ratio=p.getString('ratio') ?? ratio;
      resolution=p.getString('resolution') ?? resolution;
      backend=p.getString('backend') ?? backend;
      final raw=p.getString('scenes');
      if(raw!=null) scenes.addAll((jsonDecode(raw) as List).map((e)=>Scene.fromJson(e)));
      finalUrl=p.getString('finalUrl');
    });
  }

  Future<void> _save() async {
    final p=await SharedPreferences.getInstance();
    await p.setString('projectId',projectId);
    await p.setString('projectName',projectName);
    await p.setString('ratio',ratio);
    await p.setString('resolution',resolution);
    await p.setString('backend',backend);
    await p.setString('scenes',jsonEncode(scenes.map((e)=>e.toJson()).toList()));
    if(finalUrl!=null) await p.setString('finalUrl',finalUrl!);
  }

  Future<void> _addImages() async {
    final picked=await picker.pickMultiImage(imageQuality:null);
    if(picked.isEmpty)return;
    final dir=await getApplicationDocumentsDirectory();
    for(final x in picked){
      final target=File('${dir.path}/scene_${DateTime.now().microsecondsSinceEpoch}_${x.name}');
      await File(x.path).copy(target.path);
      scenes.add(Scene(id:DateTime.now().microsecondsSinceEpoch.toString(),path:target.path));
      await Future.delayed(const Duration(milliseconds:2));
    }
    await _save(); setState((){});
  }

  Future<void> _editScene(Scene s) async {
    final c=TextEditingController(text:s.prompt);
    int d=s.duration;
    await showDialog(context:context,builder:(_)=>AlertDialog(
      title:const Text('Scene settings'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:c,maxLines:4,decoration:const InputDecoration(labelText:'Motion prompt',hintText:'Slow cinematic camera push-in, natural movement...')),
        const SizedBox(height:12),
        StatefulBuilder(builder:(context,setLocal)=>Row(children:[
          const Text('Duration'), Expanded(child:Slider(value:d.toDouble(),min:4,max:8,divisions:4,label:'${d}s',onChanged:(v){setLocal(()=>d=v.round());})), Text('${d}s')
        ]))
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:(){s.prompt=c.text.trim();s.duration=d;Navigator.pop(context);_save();setState((){});},child:const Text('Save'))]
    ));
  }

  String _prompt(Scene s){
    if(s.prompt.isNotEmpty)return s.prompt;
    return 'Animate the scene naturally with subtle cinematic camera movement, gentle depth and realistic motion. Preserve the exact identity, composition, colors and important details of the source image. No morphing, no new objects, no text, no distortion.';
  }

  Future<void> _generate(Scene s) async {
    if(backend.trim().isEmpty){_snack('Set the backend URL first');return;}
    setState(()=>s.status='uploading'); await _save();
    try{
      final req=http.MultipartRequest('POST',Uri.parse('${backend.trim()}/api/projects/$projectId/scenes'));
      req.files.add(await http.MultipartFile.fromPath('image',s.path));
      final up=await req.send();
      final body=await up.stream.bytesToString();
      if(up.statusCode>=300)throw Exception(body);
      final imagePath=jsonDecode(body)['path'];
      final g=await http.post(Uri.parse('${backend.trim()}/api/generate'),headers:{'Content-Type':'application/json'},body:jsonEncode({'projectId':projectId,'imagePath':imagePath,'prompt':_prompt(s),'ratio':ratio,'duration':s.duration,'model':'gen4.5'}));
      if(g.statusCode>=300)throw Exception(g.body);
      s.jobId=jsonDecode(g.body)['jobId']; s.status='generating'; await _save(); setState((){});
      await _poll(s);
    }catch(e){s.status='failed';await _save();setState((){});_snack(e.toString());}
  }

  Future<void> _poll(Scene s) async {
    for(int i=0;i<240;i++){
      await Future.delayed(const Duration(seconds:3));
      if(!mounted || s.jobId==null)return;
      final r=await http.get(Uri.parse('${backend.trim()}/api/jobs/${s.jobId}'));
      if(r.statusCode>=300)throw Exception(r.body);
      final j=jsonDecode(r.body);
      if(j['status']=='SUCCEEDED'){s.status='ready';s.videoUrl=j['videoUrl'];await _save();if(mounted)setState((){});return;}
      if(j['status']=='FAILED'){throw Exception(j['error'] ?? 'Generation failed');}
      s.status='generating'; if(mounted)setState((){});
    }
    throw Exception('Generation timed out');
  }

  Future<void> _generateAll() async {
    if(scenes.isEmpty){_snack('Add at least one image');return;}
    setState(()=>busy=true);
    try{
      for(final s in scenes){if(s.videoUrl==null)await _generate(s);}
      _snack('All scene clips generated');
    }finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> _render() async {
    final ready=scenes.where((s)=>s.videoUrl!=null).toList();
    if(ready.isEmpty){_snack('Generate at least one scene first');return;}
    setState(()=>busy=true);
    try{
      final r=await http.post(Uri.parse('${backend.trim()}/api/render'),headers:{'Content-Type':'application/json'},body:jsonEncode({'projectId':projectId,'scenes':ready.map((s)=>{'videoPath':s.videoUrl!.replaceFirst(RegExp('^.*?/media/'), '')}).toList(),'outputName':'${projectName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'),'_')}.mp4','ratio':ratio,'resolution':resolution}));
      if(r.statusCode>=300)throw Exception(r.body);
      finalUrl=jsonDecode(r.body)['videoUrl'];await _save();setState((){});
      _snack('Final video rendered');
    }catch(e){_snack(e.toString());}finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> _shareFinal() async {
    if(finalUrl==null){_snack('Render the final video first');return;}
    final response=await http.get(Uri.parse(finalUrl!));
    if(response.statusCode>=300){_snack('Could not download final video');return;}
    final dir=await getTemporaryDirectory();
    final f=File('${dir.path}/${projectName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'),'_')}.mp4');
    await f.writeAsBytes(response.bodyBytes,flush:true);
    await Share.shareXFiles([XFile(f.path)],text:projectName);
  }

  void _snack(String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s),behavior:SnackBarBehavior.floating));
  Future<void> _preview(String url) async { await showDialog(context:context,builder:(_)=>Dialog(child:Padding(padding:const EdgeInsets.all(12),child:VideoPreview(url:url)))); }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(projectName),actions:[IconButton(onPressed:_settings,icon:const Icon(Icons.settings))]),
    body:busy?const _BusyView():Column(children:[
      _topBar(),
      Expanded(child:scenes.isEmpty?_empty():ReorderableListView.builder(itemCount:scenes.length,onReorder:(a,b){setState((){if(b>a)b--;final x=scenes.removeAt(a);scenes.insert(b,x);});_save();},itemBuilder:(c,i)=>_sceneCard(scenes[i],i))),
      _bottom()
    ]),
  );

  Widget _topBar()=>Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:Row(children:[
    FilledButton.icon(onPressed:_addImages,icon:const Icon(Icons.add_photo_alternate),label:const Text('Add images')),
    const Spacer(),Text('${scenes.length} scenes'),const SizedBox(width:8),DropdownButton<String>(value:ratio,items:const[DropdownMenuItem(value:'16:9',child:Text('16:9')),DropdownMenuItem(value:'9:16',child:Text('9:16')),DropdownMenuItem(value:'1:1',child:Text('1:1'))],onChanged:(v){setState(()=>ratio=v!);_save();})
  ]));

  Widget _sceneCard(Scene s,int i)=>Card(key:ValueKey(s.id),margin:const EdgeInsets.symmetric(horizontal:12,vertical:5),child:ListTile(
    leading:SizedBox(width:74,height:58,child:Image.file(File(s.path),fit:BoxFit.cover,errorBuilder:(_,__,___)=>const Icon(Icons.broken_image))),
    title:Text('Scene ${i+1} • ${s.duration}s'),subtitle:Text(s.status== 'generating'?'Generating AI video…':s.status== 'failed'?'Generation failed':s.videoUrl!=null?'AI clip ready':'Ready'),
    trailing:Wrap(spacing:2,children:[IconButton(onPressed:()=>_editScene(s),icon:const Icon(Icons.tune)),IconButton(onPressed:()=>_generate(s),icon:Icon(s.videoUrl!=null?Icons.refresh:Icons.auto_awesome)),IconButton(onPressed:(){setState(()=>scenes.remove(s));_save();},icon:const Icon(Icons.delete_outline))])
  ));

  Widget _empty()=>Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[const Icon(Icons.movie_creation_outlined,size:72),const SizedBox(height:12),const Text('Add your HD images to start'),const SizedBox(height:8),FilledButton.icon(onPressed:_addImages,icon:const Icon(Icons.add),label:const Text('Import images'))]));

  Widget _bottom()=>SafeArea(child:Padding(padding:const EdgeInsets.all(10),child:Row(children:[Expanded(child:FilledButton.icon(onPressed:busy?null:_generateAll,icon:const Icon(Icons.auto_awesome),label:const Text('Generate all'))),const SizedBox(width:8),Expanded(child:FilledButton.icon(onPressed:busy?null:_render,icon:const Icon(Icons.video_settings),label:const Text('Render 1080p'))),if(finalUrl!=null)IconButton(onPressed:_shareFinal,icon:const Icon(Icons.share))])));

  Future<void> _settings() async {
    final b=TextEditingController(text:backend), n=TextEditingController(text:projectName);
    await showDialog(context:context,builder:(_)=>AlertDialog(title:const Text('Project settings'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:n,decoration:const InputDecoration(labelText:'Project name')),TextField(controller:b,decoration:const InputDecoration(labelText:'Backend URL'),keyboardType:TextInputType.url),const SizedBox(height:8),Align(alignment:Alignment.centerLeft,child:Text('Resolution: $resolution'))
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:(){setState((){projectName=n.text.trim().isEmpty?'My YouTube Video':n.text.trim();backend=b.text.trim();});_save();Navigator.pop(context);},child:const Text('Save'))]));
  }
}

class _BusyView extends StatelessWidget{const _BusyView();@override Widget build(BuildContext c)=>const Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[CircularProgressIndicator(),SizedBox(height:16),Text('Working… AI and FFmpeg are doing their little rituals.')]);}

class VideoPreview extends StatefulWidget{final String url;const VideoPreview({super.key,required this.url});@override State<VideoPreview> createState()=>_VideoPreviewState();}
class _VideoPreviewState extends State<VideoPreview>{late VideoPlayerController c;@override void initState(){super.initState();c=VideoPlayerController.networkUrl(Uri.parse(widget.url))..initialize().then((_){setState((){});});}@override void dispose(){c.dispose();super.dispose();}@override Widget build(BuildContext context)=>c.value.isInitialized?AspectRatio(aspectRatio:c.value.aspectRatio,child:Stack(alignment:Alignment.center,children:[VideoPlayer(c),IconButton(onPressed:(){setState(()=>c.value.isPlaying?c.pause():c.play());},icon:Icon(c.value.isPlaying?Icons.pause_circle:Icons.play_circle,size:64))])):const CircularProgressIndicator();}
