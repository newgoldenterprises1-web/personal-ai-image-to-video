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
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    home: const HomePage(),
  );
}

class Scene {
  Scene({
    required this.id,
    required this.path,
    this.duration = 5,
    this.prompt = '',
    this.status = 'ready',
    this.jobId,
    this.videoUrl,
  });

  final String id;
  final String path;
  int duration;
  String prompt;
  String status;
  String? jobId;
  String? videoUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'duration': duration,
    'prompt': prompt,
    'status': status,
    'jobId': jobId,
    'videoUrl': videoUrl,
  };

  factory Scene.fromJson(Map<String, dynamic> json) => Scene(
    id: json['id'] as String,
    path: json['path'] as String,
    duration: (json['duration'] as num?)?.toInt() ?? 5,
    prompt: json['prompt'] as String? ?? '',
    status: json['status'] as String? ?? 'ready',
    jobId: json['jobId'] as String?,
    videoUrl: json['videoUrl'] as String?,
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Duration _uploadTimeout = Duration(minutes: 2);
  static const Duration _requestTimeout = Duration(seconds: 45);
  static const Duration _renderTimeout = Duration(minutes: 30);
  static const Duration _downloadTimeout = Duration(minutes: 2);

  final picker = ImagePicker();
  final scenes = <Scene>[];

  String projectId = DateTime.now().millisecondsSinceEpoch.toString();
  String projectName = 'My YouTube Video';
  String ratio = '16:9';
  String resolution = '1080p';
  String backend = 'http://127.0.0.1:8787';
  bool busy = false;
  String? finalUrl;

  Uri _backendUri(String path) {
    final base = backend.trim().replaceFirst(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      throw const FormatException('Backend URL is empty');
    }
    return Uri.parse('$base$path');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      projectId = prefs.getString('projectId') ?? projectId;
      projectName = prefs.getString('projectName') ?? projectName;
      ratio = prefs.getString('ratio') ?? ratio;
      resolution = prefs.getString('resolution') ?? resolution;
      backend = prefs.getString('backend') ?? backend;
      if (backend == 'http://10.0.2.2:8787') backend = 'http://127.0.0.1:8787';
      final raw = prefs.getString('scenes');
      if (raw != null) {
        scenes
          ..clear()
          ..addAll(
            (jsonDecode(raw) as List)
                .map((item) => Scene.fromJson(Map<String, dynamic>.from(item as Map))),
          );
      }
      finalUrl = prefs.getString('finalUrl');
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('projectId', projectId);
    await prefs.setString('projectName', projectName);
    await prefs.setString('ratio', ratio);
    await prefs.setString('resolution', resolution);
    await prefs.setString('backend', backend);
    await prefs.setString(
      'scenes',
      jsonEncode(scenes.map((scene) => scene.toJson()).toList()),
    );
    if (finalUrl != null) await prefs.setString('finalUrl', finalUrl!);
  }

  Future<void> _addImages() async {
    final picked = await picker.pickMultiImage(imageQuality: null);
    if (picked.isEmpty) return;

    final dir = await getApplicationDocumentsDirectory();
    for (final image in picked) {
      final target = File(
        '${dir.path}/scene_${DateTime.now().microsecondsSinceEpoch}_${image.name}',
      );
      await File(image.path).copy(target.path);
      scenes.add(
        Scene(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          path: target.path,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    await _save();
    if (mounted) setState(() {});
  }

  Future<void> _editScene(Scene scene) async {
    final controller = TextEditingController(text: scene.prompt);
    var duration = scene.duration;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Scene settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Motion prompt',
                hintText: 'Slow cinematic camera push-in, natural movement...',
              ),
            ),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (context, setLocal) => Row(
                children: [
                  const Text('Duration'),
                  Expanded(
                    child: Slider(
                      value: duration.toDouble(),
                      min: 2,
                      max: 10,
                      divisions: 8,
                      label: '${duration}s',
                      onChanged: (value) => setLocal(() => duration = value.round()),
                    ),
                  ),
                  Text('${duration}s'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              scene.prompt = controller.text.trim();
              scene.duration = duration;
              Navigator.pop(context);
              _save();
              setState(() {});
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  String _prompt(Scene scene) {
    if (scene.prompt.isNotEmpty) return scene.prompt;
    return 'Animate the scene naturally with subtle cinematic camera movement, gentle depth and realistic motion. Preserve the exact identity, composition, colors and important details of the source image. No morphing, no new objects, no text, no distortion.';
  }

  Future<bool> _generate(Scene scene) async {
    if (backend.trim().isEmpty) {
      _snack('Set the backend URL first');
      return false;
    }

    if (mounted) setState(() => scene.status = 'uploading');
    await _save();

    try {
      final request = http.MultipartRequest(
        'POST',
        _backendUri('/api/projects/$projectId/scenes'),
      );
      request.files.add(await http.MultipartFile.fromPath('image', scene.path));

      final upload = await request.send().timeout(_uploadTimeout);
      final uploadBody = await upload.stream.bytesToString();
      if (upload.statusCode >= 300) throw Exception(uploadBody);

      final imagePath = (jsonDecode(uploadBody) as Map<String, dynamic>)['path'];

      final generation = await http.post(
        _backendUri('/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'projectId': projectId,
          'imagePath': imagePath,
          'prompt': _prompt(scene),
          'ratio': ratio,
          'duration': scene.duration,
        }),
      ).timeout(_requestTimeout);
      if (generation.statusCode >= 300) throw Exception(generation.body);

      scene.jobId =
          (jsonDecode(generation.body) as Map<String, dynamic>)['jobId'] as String;
      scene.status = 'generating';
      await _save();
      if (mounted) setState(() {});

      return await _poll(scene);
    } catch (error) {
      scene.status = 'failed';
      await _save();
      if (mounted) {
        setState(() {});
        _snack(error.toString());
      }
      return false;
    }
  }

  Future<bool> _poll(Scene scene) async {
    for (var i = 0; i < 240; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted || scene.jobId == null) return false;

      final response = await http.get(
        _backendUri('/api/jobs/${scene.jobId}'),
      ).timeout(_requestTimeout);
      if (response.statusCode >= 300) throw Exception(response.body);

      final job = jsonDecode(response.body) as Map<String, dynamic>;
      if (job['status'] == 'SUCCEEDED') {
        scene.status = 'ready';
        scene.videoUrl = job['videoUrl'] as String?;
        await _save();
        if (mounted) setState(() {});
        return scene.videoUrl != null;
      }
      if (job['status'] == 'FAILED') {
        throw Exception(job['error'] ?? 'Generation failed');
      }

      scene.status = 'generating';
      if (mounted) setState(() {});
    }

    throw Exception('Generation timed out');
  }

  Future<void> _generateAll() async {
    if (scenes.isEmpty) {
      _snack('Add at least one image');
      return;
    }

    setState(() => busy = true);
    var failed = 0;
    try {
      for (final scene in scenes) {
        if (scene.videoUrl == null && !await _generate(scene)) failed++;
      }
      _snack(
        failed == 0
            ? 'All scene clips generated'
            : '$failed scene(s) failed. Fix them and retry.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _render() async {
    final ready = scenes.where((scene) => scene.videoUrl != null).toList();
    if (ready.length != scenes.length) {
      _snack('Generate every scene before rendering the final video');
      return;
    }
    if (ready.isEmpty) {
      _snack('Add and generate at least one scene first');
      return;
    }

    setState(() => busy = true);
    try {
      final response = await http.post(
        _backendUri('/api/render'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'projectId': projectId,
          'scenes': ready
              .map((scene) => {'videoUrl': scene.videoUrl})
              .toList(),
          'outputName':
              '${projectName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.mp4',
          'ratio': ratio,
          'resolution': resolution,
        }),
      ).timeout(_renderTimeout);
      if (response.statusCode >= 300) throw Exception(response.body);

      finalUrl =
          (jsonDecode(response.body) as Map<String, dynamic>)['videoUrl'] as String?;
      await _save();
      if (mounted) {
        setState(() {});
        _snack('Final video rendered');
      }
    } catch (error) {
      if (mounted) _snack(error.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _shareFinal() async {
    if (finalUrl == null) {
      _snack('Render the final video first');
      return;
    }

    final response = await http.get(Uri.parse(finalUrl!)).timeout(_downloadTimeout);
    if (response.statusCode >= 300) {
      _snack('Could not download final video');
      return;
    }

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/${projectName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.mp4',
    );
    await file.writeAsBytes(response.bodyBytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: projectName);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _preview(String url) async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: VideoPreview(url: url),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(projectName),
      actions: [
        IconButton(onPressed: _settings, icon: const Icon(Icons.settings)),
      ],
    ),
    body: busy
        ? const _BusyView()
        : Column(
            children: [
              _topBar(),
              Expanded(
                child: scenes.isEmpty
                    ? _empty()
                    : ReorderableListView.builder(
                        itemCount: scenes.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setState(() {
                            final scene = scenes.removeAt(oldIndex);
                            scenes.insert(newIndex, scene);
                          });
                          _save();
                        },
                        itemBuilder: (context, index) =>
                            _sceneCard(scenes[index], index),
                      ),
              ),
              _bottom(),
            ],
          ),
  );

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Row(
      children: [
        FilledButton.icon(
          onPressed: _addImages,
          icon: const Icon(Icons.add_photo_alternate),
          label: const Text('Add images'),
        ),
        const Spacer(),
        Text('${scenes.length} scenes'),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: ratio,
          items: const [
            DropdownMenuItem(value: '16:9', child: Text('16:9')),
            DropdownMenuItem(value: '9:16', child: Text('9:16')),
            DropdownMenuItem(value: '1:1', child: Text('1:1')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => ratio = value);
            _save();
          },
        ),
      ],
    ),
  );

  Widget _sceneCard(Scene scene, int index) => Card(
    key: ValueKey(scene.id),
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    child: ListTile(
      leading: SizedBox(
        width: 74,
        height: 58,
        child: Image.file(
          File(scene.path),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image),
        ),
      ),
      title: Text('Scene ${index + 1} • ${scene.duration}s'),
      subtitle: Text(
        scene.status == 'generating'
            ? 'Generating AI video…'
            : scene.status == 'uploading'
                ? 'Uploading HD image…'
                : scene.status == 'failed'
                    ? 'Generation failed'
                    : scene.videoUrl != null
                        ? 'AI clip ready'
                        : 'Ready',
      ),
      trailing: Wrap(
        spacing: 2,
        children: [
          if (scene.videoUrl != null)
            IconButton(
              onPressed: () => _preview(scene.videoUrl!),
              icon: const Icon(Icons.play_circle_outline),
            ),
          IconButton(
            onPressed: () => _editScene(scene),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            onPressed: () => _generate(scene),
            icon: Icon(
              scene.videoUrl != null ? Icons.refresh : Icons.auto_awesome,
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() => scenes.remove(scene));
              _save();
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    ),
  );

  Widget _empty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.movie_creation_outlined, size: 72),
        const SizedBox(height: 12),
        const Text('Add your HD images to start'),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _addImages,
          icon: const Icon(Icons.add),
          label: const Text('Import images'),
        ),
      ],
    ),
  );

  Widget _bottom() => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: busy ? null : _generateAll,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate all'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: busy ? null : _render,
              icon: const Icon(Icons.video_settings),
              label: Text('Render $resolution'),
            ),
          ),
          if (finalUrl != null)
            IconButton(
              onPressed: _shareFinal,
              icon: const Icon(Icons.share),
            ),
        ],
      ),
    ),
  );

  Future<void> _settings() async {
    final backendController = TextEditingController(text: backend);
    final nameController = TextEditingController(text: projectName);

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Project settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Project name'),
            ),
            TextField(
              controller: backendController,
              decoration: const InputDecoration(labelText: 'Backend URL'),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Resolution'),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: resolution,
                  items: const [
                    DropdownMenuItem(value: '720p', child: Text('720p')),
                    DropdownMenuItem(value: '1080p', child: Text('1080p')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => resolution = value);
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                projectName = nameController.text.trim().isEmpty
                    ? 'My YouTube Video'
                    : nameController.text.trim();
                backend = backendController.text.trim();
              });
              _save();
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    backendController.dispose();
    nameController.dispose();
  }
}

class _BusyView extends StatelessWidget {
  const _BusyView();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Generating and rendering your video…'),
      ],
    ),
  );
}

class VideoPreview extends StatefulWidget {
  const VideoPreview({super.key, required this.url});
  final String url;

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  late final VideoPlayerController controller;

  @override
  void initState() {
    super.initState();
    controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.center,
        children: [
          VideoPlayer(controller),
          IconButton(
            onPressed: () {
              setState(() {
                controller.value.isPlaying
                    ? controller.pause()
                    : controller.play();
              });
            },
            icon: Icon(
              controller.value.isPlaying
                  ? Icons.pause_circle
                  : Icons.play_circle,
              size: 64,
            ),
          ),
        ],
      ),
    );
  }
}
