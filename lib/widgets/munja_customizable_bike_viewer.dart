import 'package:flutter/material.dart';
import 'package:model_viewer_pro/model_viewer_pro.dart';

import '../core/theme/munja_colors.dart';

class MunjaCustomizableBikeViewer extends StatefulWidget {
  const MunjaCustomizableBikeViewer({
    super.key,
    this.modelPath = 'assets/models/kids_mtb_master.glb',
    this.height = 360,
    this.initialFrameId = 'frame_1',
    this.enableTouch = true,
    this.onFrameChanged,
  });

  final String modelPath;
  final double height;
  final String initialFrameId;
  final bool enableTouch;
  final ValueChanged<String>? onFrameChanged;

  @override
  State<MunjaCustomizableBikeViewer> createState() =>
      _MunjaCustomizableBikeViewerState();
}

class _MunjaCustomizableBikeViewerState
    extends State<MunjaCustomizableBikeViewer> {
  final ModelViewerProController _controller =
      ModelViewerProController();

  static const List<_FrameVariant> _frames = <_FrameVariant>[
    _FrameVariant(
      id: 'frame_1',
      label: 'Frame 1',
      meshName: 'Frame 1',
    ),
    _FrameVariant(
      id: 'frame_2',
      label: 'Frame 2',
      meshName: 'FRAME 2',
    ),
    _FrameVariant(
      id: 'frame_3',
      label: 'Frame 3',
      meshName: 'FRAME 3',
    ),
    _FrameVariant(
      id: 'frame_4',
      label: 'Frame 4',
      meshName: 'frame 4',
    ),
  ];

  late String _selectedFrameId;

  bool _loading = true;
  String? _errorMessage;
  List<String> _availableMeshes = const <String>[];

  @override
  void initState() {
    super.initState();

    _selectedFrameId = _frames.any(
      (frame) => frame.id == widget.initialFrameId,
    )
        ? widget.initialFrameId
        : _frames.first.id;
  }

  @override
  void didUpdateWidget(
    covariant MunjaCustomizableBikeViewer oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.initialFrameId != widget.initialFrameId &&
        _frames.any(
          (frame) => frame.id == widget.initialFrameId,
        )) {
      _selectedFrameId = widget.initialFrameId;

      if (!_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _applySelectedFrame();
          }
        });
      }
    }
  }

  _FrameVariant get _selectedFrame {
    return _frames.firstWhere(
      (frame) => frame.id == _selectedFrameId,
      orElse: () => _frames.first,
    );
  }

  List<String> get _frameMeshNames {
    return _frames
        .map((frame) => frame.meshName)
        .toList(growable: false);
  }

  Future<void> _handleModelLoaded(
    List<String> meshes,
  ) async {
    debugPrint(
      'MUNJA CUSTOM 3D MESHES (${meshes.length}): $meshes',
    );

    final missingFrameMeshes = _frameMeshNames
        .where((name) => !meshes.contains(name))
        .toList();

    if (!mounted) {
      return;
    }

    setState(() {
      _availableMeshes = List<String>.unmodifiable(meshes);
      _loading = false;

      if (missingFrameMeshes.isNotEmpty) {
        _errorMessage =
            'Frame meshes not found: ${missingFrameMeshes.join(', ')}';
      } else {
        _errorMessage = null;
      }
    });

    if (missingFrameMeshes.isNotEmpty) {
      debugPrint(
        'MUNJA CUSTOM 3D FRAME MESH ERROR: '
        '${missingFrameMeshes.join(', ')}',
      );
      return;
    }

    try {
      final ready = await _controller.waitForSceneReady();

      debugPrint(
        'MUNJA CUSTOM 3D SCENE READY: $ready',
      );

      if (!ready) {
        if (!mounted) {
          return;
        }

        setState(() {
          _errorMessage =
              '3D scene was loaded, but mesh control is not ready.';
        });
        return;
      }

      await _applySelectedFrame();
    } catch (error, stackTrace) {
      debugPrint(
        'MUNJA CUSTOM 3D INITIAL FRAME ERROR: $error',
      );
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            'Frame visibility could not be initialized.';
      });
    }
  }

  Future<void> _applySelectedFrame() async {
    final selectedFrame = _selectedFrame;

    try {
      await _controller.setExclusiveMesh(
        _frameMeshNames,
        selectedFrame.meshName,
      );

      debugPrint(
        'MUNJA CUSTOM 3D FRAME ACTIVE: '
        '${selectedFrame.id} -> ${selectedFrame.meshName}',
      );

      widget.onFrameChanged?.call(
        selectedFrame.id,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'MUNJA CUSTOM 3D FRAME CHANGE ERROR: $error',
      );
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            'Could not switch to ${selectedFrame.label}.';
      });
    }
  }

  Future<void> _selectFrame(
    _FrameVariant frame,
  ) async {
    if (_loading ||
        _selectedFrameId == frame.id) {
      return;
    }

    setState(() {
      _selectedFrameId = frame.id;
      _errorMessage = null;
    });

    await _applySelectedFrame();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: MunjaColors.mint.withValues(alpha: 0.14),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          SizedBox(
            height: widget.height,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ModelViewerProViewer(
                  src: widget.modelPath,
                  controller: _controller,
                  backgroundColor: Colors.transparent,
                  cameraControls: widget.enableTouch,
                  autoRotate: false,
                  exposure: 1.0,
                  shadowIntensity: 0.0,
                  shadowSoftness: 1.0,
                  cameraOrbit: '180deg 72deg 105%',
                  cameraTarget: 'auto auto auto',
                  fieldOfView: '38deg',

                  // Important:
                  // We intentionally do not use initialLoadingMeshes yet.
                  // First we want the package to report the real mesh names
                  // from the engineer's GLB. Then setExclusiveMesh() hides the
                  // three unselected frame variants immediately after load.
                  onLoad: _handleModelLoaded,
                ),
                if (_loading)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x66000000),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: MunjaColors.mint,
                        ),
                      ),
                    ),
                  ),
                if (_errorMessage != null)
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.76),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.redAccent.withValues(
                            alpha: 0.35,
                          ),
                        ),
                      ),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              14,
              13,
              14,
              15,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.15),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.view_in_ar_rounded,
                      color: MunjaColors.mint,
                      size: 17,
                    ),
                    const SizedBox(width: 7),
                    const Expanded(
                      child: Text(
                        'FRAME TEST',
                        style: TextStyle(
                          color: MunjaColors.mint,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    Text(
                      '${_availableMeshes.length} meshes',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: _frames.map((frame) {
                      final selected =
                          frame.id == _selectedFrameId;

                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _FrameButton(
                          frame: frame,
                          selected: selected,
                          disabled: _loading,
                          onTap: () => _selectFrame(frame),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameVariant {
  const _FrameVariant({
    required this.id,
    required this.label,
    required this.meshName,
  });

  final String id;
  final String label;
  final String meshName;
}

class _FrameButton extends StatelessWidget {
  const _FrameButton({
    required this.frame,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final _FrameVariant frame;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            color: selected
                ? MunjaColors.mint.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? MunjaColors.mint
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (selected) ...<Widget>[
                const Icon(
                  Icons.check_circle_rounded,
                  color: MunjaColors.mint,
                  size: 16,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                frame.label,
                style: TextStyle(
                  color: selected
                      ? MunjaColors.mint
                      : Colors.white.withValues(alpha: 0.72),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
