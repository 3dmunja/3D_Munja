import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:interactive_3d/interactive_3d.dart';

class FrameNativeTestScreen extends StatefulWidget {
  const FrameNativeTestScreen({super.key});

  @override
  State<FrameNativeTestScreen> createState() =>
      _FrameNativeTestScreenState();
}

class _FrameNativeTestScreenState
    extends State<FrameNativeTestScreen> {
  static const String _modelPath =
      'assets/models/kids_mtb_master.glb';

  // Same safe area principle as the rest of Munja:
  // the navigation wheel must always remain visible and must not
  // cover controls near the bottom of a subpage.
  static const double bottomWheelSafePadding = 360;

  static const List<_FrameVariant> _frames = <_FrameVariant>[
    _FrameVariant(
      id: 'frame_1',
      label: 'Frame 1',
      entityName: 'Frame 1',
    ),
    _FrameVariant(
      id: 'frame_2',
      label: 'Frame 2',
      entityName: 'FRAME 2',
    ),
    _FrameVariant(
      id: 'frame_3',
      label: 'Frame 3',
      entityName: 'FRAME 3',
    ),
    _FrameVariant(
      id: 'frame_4',
      label: 'Frame 4',
      entityName: 'frame 4',
    ),
  ];

  final Interactive3dController _controller =
      Interactive3dController();

  late final Map<String, ModelPartGroup> _frameGroups;

  String _selectedFrameId = 'frame_1';

  bool _switchingFrame = false;
  bool _frameControlReady = false;
  bool _startupVisibilityApplied = false;

  String? _statusMessage;

  final Set<String> _confirmedFrameEntities = <String>{};

  _FrameVariant get _selectedFrame {
    return _frames.firstWhere(
      (frame) => frame.id == _selectedFrameId,
      orElse: () => _frames.first,
    );
  }

  @override
  void initState() {
    super.initState();

    _frameGroups = <String, ModelPartGroup>{
      for (final frame in _frames)
        frame.id: ModelPartGroup(
          title: frame.label,
          names: <String>[
            frame.entityName,
          ],
        ),
    };

    // interactive_3d does not expose a dedicated "model loaded"
    // callback in this flow. Give the native renderer a short moment
    // to attach before applying the initial exclusive visibility.
    Future<void>.delayed(
      const Duration(milliseconds: 1800),
      () async {
        if (!mounted || _startupVisibilityApplied) {
          return;
        }

        _startupVisibilityApplied = true;

        await _applyFrame(
          _selectedFrameId,
          startup: true,
        );
      },
    );
  }

  void _handleSelectionChanged(
    List<EntityData> selectedEntities,
  ) {
    final selectedNames = selectedEntities
        .map((entity) => entity.name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);

    for (final frame in _frames) {
      if (selectedNames.contains(frame.entityName)) {
        _confirmedFrameEntities.add(
          frame.entityName,
        );
      }
    }

    debugPrint(
      'MUNJA NATIVE 3D SELECTION: $selectedNames',
    );

    debugPrint(
      'MUNJA NATIVE FRAME ENTITIES CONFIRMED: '
      '${_confirmedFrameEntities.toList()}',
    );

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> _selectFrame(
    String frameId,
  ) async {
    if (_switchingFrame ||
        frameId == _selectedFrameId) {
      return;
    }

    HapticFeedback.selectionClick();

    await _applyFrame(frameId);
  }

  Future<void> _applyFrame(
    String frameId, {
    bool startup = false,
  }) async {
    final selected = _frames.firstWhere(
      (frame) => frame.id == frameId,
      orElse: () => _frames.first,
    );

    if (mounted) {
      setState(() {
        _switchingFrame = true;
        _statusMessage = startup
            ? 'Initialiserer ${selected.label}...'
            : 'Skifter til ${selected.label}...';
      });
    }

    try {
      // This is the actual interactive_3d 2.1.0 visibility API.
      //
      // Each Munja frame is represented as its own PartGroup.
      // We explicitly update all four groups every time so only
      // the selected frame remains visible.
      for (final frame in _frames) {
        final group = _frameGroups[frame.id];

        if (group == null) {
          continue;
        }

        await _controller.updatePartGroupConfig(
          group: group,
          isVisible: frame.id == selected.id,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedFrameId = selected.id;
        _frameControlReady = true;
        _statusMessage =
            '${selected.label} er aktiv';
      });

      debugPrint(
        'MUNJA NATIVE FRAME ACTIVE: '
        '${selected.id} -> ${selected.entityName}',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'MUNJA NATIVE FRAME SWITCH ERROR: $error',
      );
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        _frameControlReady = false;
        _statusMessage =
            'Kunne ikke skifte frame. Se terminal-loggen.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _switchingFrame = false;
        });
      }
    }
  }

  Future<void> _showAllFrames() async {
    if (_switchingFrame) {
      return;
    }

    HapticFeedback.lightImpact();

    setState(() {
      _switchingFrame = true;
      _statusMessage = 'Viser alle frames...';
    });

    try {
      for (final frame in _frames) {
        final group = _frameGroups[frame.id];

        if (group == null) {
          continue;
        }

        await _controller.updatePartGroupConfig(
          group: group,
          isVisible: true,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _frameControlReady = true;
        _statusMessage =
            'Alle fire frames er synlige';
      });

      debugPrint(
        'MUNJA NATIVE FRAME TEST: ALL FRAMES VISIBLE',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'MUNJA NATIVE SHOW ALL ERROR: $error',
      );
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage =
            'Kunne ikke vise alle frames.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _switchingFrame = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF041610);
    const panel = Color(0xFF0B211A);
    const mint = Color(0xFF6FFFC2);
    const muted = Color(0xFF8FA79D);

    final selectedFrame = _selectedFrame;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Native Frame Test',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            16,
            8,
            16,
            bottomWheelSafePadding,
          ),
          children: <Widget>[
            SizedBox(
              height: 430,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius:
                      BorderRadius.circular(24),
                  border: Border.all(
                    color:
                        mint.withValues(alpha: 0.16),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Interactive3d(
                      controller: _controller,
                      modelPath: _modelPath,
                      solidBackgroundColor:
                          const <double>[
                        0.043,
                        0.129,
                        0.102,
                        1.0,
                      ],
                      defaultZoom: 0.85,
                      onSelectionChanged:
                          _handleSelectionChanged,
                    ),
                    Positioned(
                      left: 12,
                      top: 12,
                      child: IgnorePointer(
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black
                                .withValues(alpha: 0.56),
                            borderRadius:
                                BorderRadius.circular(999),
                            border: Border.all(
                              color: mint.withValues(
                                alpha: 0.18,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize:
                                MainAxisSize.min,
                            children: <Widget>[
                              Container(
                                width: 7,
                                height: 7,
                                decoration:
                                    const BoxDecoration(
                                  color: mint,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                selectedFrame.label,
                                style:
                                    const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight:
                                      FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_switchingFrame)
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child:
                                CircularProgressIndicator(
                              color: mint,
                              strokeWidth: 2.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: panel,
                borderRadius:
                    BorderRadius.circular(22),
                border: Border.all(
                  color:
                      mint.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.view_in_ar_rounded,
                        color: mint,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'FRAME SELECTOR',
                          style: TextStyle(
                            color: mint,
                            fontSize: 10,
                            fontWeight:
                                FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: (_frameControlReady
                                  ? mint
                                  : Colors.orangeAccent)
                              .withValues(alpha: 0.10),
                          borderRadius:
                              BorderRadius.circular(999),
                        ),
                        child: Text(
                          _frameControlReady
                              ? 'NATIVE'
                              : 'TEST',
                          style: TextStyle(
                            color: _frameControlReady
                                ? mint
                                : Colors.orangeAccent,
                            fontSize: 8,
                            fontWeight:
                                FontWeight.w900,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusMessage ??
                        'Vælg én frame. De tre andre bliver skjult.',
                    style: const TextStyle(
                      color: muted,
                      height: 1.35,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GridView.builder(
                    shrinkWrap: true,
                    physics:
                        const NeverScrollableScrollPhysics(),
                    itemCount: _frames.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 9,
                      mainAxisSpacing: 9,
                      childAspectRatio: 2.25,
                    ),
                    itemBuilder: (context, index) {
                      final frame = _frames[index];

                      return _FrameButton(
                        frame: frame,
                        selected:
                            frame.id ==
                                _selectedFrameId,
                        disabled: _switchingFrame,
                        onTap: () =>
                            _selectFrame(frame.id),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _switchingFrame
                          ? null
                          : _showAllFrames,
                      icon: const Icon(
                        Icons.layers_rounded,
                        size: 17,
                      ),
                      label: const Text(
                        'Vis alle frames',
                      ),
                      style:
                          OutlinedButton.styleFrom(
                        foregroundColor:
                            Colors.white,
                        side: BorderSide(
                          color: Colors.white
                              .withValues(alpha: 0.12),
                        ),
                        padding:
                            const EdgeInsets.symmetric(
                          vertical: 13,
                        ),
                      ),
                    ),
                  ),
                  if (_confirmedFrameEntities
                      .isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      'Bekræftet i GLB: '
                      '${_confirmedFrameEntities.join(', ')}',
                      style: TextStyle(
                        color: Colors.white
                            .withValues(alpha: 0.28),
                        fontSize: 8,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrameVariant {
  const _FrameVariant({
    required this.id,
    required this.label,
    required this.entityName,
  });

  final String id;
  final String label;
  final String entityName;
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
    const mint = Color(0xFF6FFFC2);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(17),
        child: AnimatedContainer(
          duration:
              const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: selected
                ? mint.withValues(alpha: 0.13)
                : Colors.black
                    .withValues(alpha: 0.15),
            borderRadius:
                BorderRadius.circular(17),
            border: Border.all(
              color: selected
                  ? mint
                  : Colors.white
                      .withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(
                  milliseconds: 180,
                ),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: selected
                      ? mint.withValues(
                          alpha: 0.15,
                        )
                      : Colors.white
                          .withValues(alpha: 0.04),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? mint
                        : Colors.white
                            .withValues(
                              alpha: 0.10,
                            ),
                  ),
                ),
                child: Icon(
                  selected
                      ? Icons.check_rounded
                      : Icons
                          .directions_bike_rounded,
                  color: selected
                      ? mint
                      : Colors.white54,
                  size: 16,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      frame.label,
                      style: TextStyle(
                        color: selected
                            ? mint
                            : Colors.white,
                        fontSize: 11,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      frame.entityName,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white
                            .withValues(alpha: 0.32),
                        fontSize: 7,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
