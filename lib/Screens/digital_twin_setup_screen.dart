import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/bike_profile.dart';
import '../services/bike_garage_service.dart';
import '../services/bike_model_resolver.dart';

class DigitalTwinSetupScreen extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onClose;
  final ValueChanged<BikeProfile>? onSaved;

  const DigitalTwinSetupScreen({
    super.key,
    this.embedded = false,
    this.onClose,
    this.onSaved,
  });

  @override
  State<DigitalTwinSetupScreen> createState() => _DigitalTwinSetupScreenState();
}

class _DigitalTwinSetupScreenState extends State<DigitalTwinSetupScreen> {
  final BikeGarageService _bikeGarageService = const BikeGarageService();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _nameController = TextEditingController(
    text: 'Kids MTB',
  );

  BikeType _selectedType = BikeType.kidsMtb;
  BikeFrameColor _selectedColor = BikeFrameColor.blue;
  BikeWheelSize _selectedWheelSize = BikeWheelSize.inch24;
  BikeHandlebarType _selectedHandlebar = BikeHandlebarType.flat;
  BikeBrakeType _selectedBrakeType = BikeBrakeType.rim;
  BikeGearType _selectedGearType = BikeGearType.externalDerailleur;

  bool _hasMudguards = true;
  bool _hasKickstand = true;
  bool _hasBottleCage = true;
  bool _hasRearLight = true;
  bool _hasFrontLight = false;
  bool _hasRearRack = false;
  bool _hasBell = false;

  bool _saving = false;

  final List<XFile> _photos = [];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_photos.length >= 4) return;

    final photo = await _imagePicker.pickImage(
      source: source,
      imageQuality: 78,
      maxWidth: 1600,
    );

    if (photo == null || !mounted) return;

    setState(() {
      _photos.add(photo);
    });
  }

  void _removePhoto(int index) {
    setState(() {
      _photos.removeAt(index);
    });
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
      return;
    }

    Navigator.of(context).pop();
  }

  Future<void> _saveBike() async {
    if (_saving) return;

    setState(() {
      _saving = true;
    });

    try {
      final now = DateTime.now();

      final profile = BikeProfile(
        id: 'bike_${now.millisecondsSinceEpoch}',
        name: _nameController.text.trim().isEmpty
            ? AppText.t('kidsMtb')
            : _nameController.text.trim(),
        type: _selectedType,
        frameColor: _selectedColor,
        handlebarType: _selectedHandlebar,
        brakeType: _selectedBrakeType,
        gearType: _selectedGearType,
        wheelSize: _selectedWheelSize,
        hasMudguards: _hasMudguards,
        hasKickstand: _hasKickstand,
        hasBottleCage: _hasBottleCage,
        hasRearLight: _hasRearLight,
        hasFrontLight: _hasFrontLight,
        hasRearRack: _hasRearRack,
        hasBell: _hasBell,
        photoPaths: _photos.map((photo) => photo.path).toList(),
        modelPath: BikeModelResolver.resolveModelPath(
          type: _selectedType,
          wheelSize: _selectedWheelSize,
        ),
        createdAt: now,
        updatedAt: now,
      );

      await _bikeGarageService.addBike(profile, makeActive: true);

      if (!mounted) return;

      if (widget.onSaved != null) {
        widget.onSaved!(profile);
        return;
      }

      Navigator.of(context).pop(profile);
    } catch (e) {
      debugPrint('DIGITAL TWIN SETUP SAVE ERROR: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppText.t('couldNotSaveBike')),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      padding: EdgeInsets.fromLTRB(20, widget.embedded ? 8 : 18, 20, 360),
      children: [
        _TopBar(onClose: _close),
        const SizedBox(height: 24),
        _HeroHeader(photosCount: _photos.length),
        const SizedBox(height: 22),
        _SectionCard(
          title: AppText.t('bikePhotos'),
          subtitle: AppText.t('bikePhotosSubtitle'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PhotoGrid(
                photos: _photos,
                onRemove: _removePhoto,
                onAddFromCamera: () => _pickPhoto(ImageSource.camera),
                onAddFromGallery: () => _pickPhoto(ImageSource.gallery),
              ),
              const SizedBox(height: 14),
              Text(
                AppText.t('bikePhotosHint'),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.42),
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: AppText.t('bikeIdentity'),
          subtitle: AppText.t('bikeIdentitySubtitle'),
          child: Column(
            children: [
              _MunjaTextField(
                controller: _nameController,
                label: AppText.t('bikeName'),
              ),
              const SizedBox(height: 14),
              _DropdownField<BikeType>(
                label: AppText.t('bikeType'),
                value: _selectedType,
                items: BikeType.values,
                labelBuilder: _bikeTypeLabel,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedType = value);
                },
              ),
              const SizedBox(height: 14),
              _DropdownField<BikeFrameColor>(
                label: AppText.t('frameColor'),
                value: _selectedColor,
                items: BikeFrameColor.values,
                labelBuilder: _frameColorLabel,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedColor = value);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: AppText.t('bikeComponents'),
          subtitle: AppText.t('bikeComponentsSubtitle'),
          child: Column(
            children: [
              _DropdownField<BikeWheelSize>(
                label: AppText.t('wheelSize'),
                value: _selectedWheelSize,
                items: BikeWheelSize.values,
                labelBuilder: _wheelSizeLabel,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedWheelSize = value);
                },
              ),
              const SizedBox(height: 14),
              _DropdownField<BikeHandlebarType>(
                label: AppText.t('handlebar'),
                value: _selectedHandlebar,
                items: BikeHandlebarType.values,
                labelBuilder: _handlebarLabel,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedHandlebar = value);
                },
              ),
              const SizedBox(height: 14),
              _DropdownField<BikeBrakeType>(
                label: AppText.t('brakeType'),
                value: _selectedBrakeType,
                items: BikeBrakeType.values,
                labelBuilder: _brakeTypeLabel,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedBrakeType = value);
                },
              ),
              const SizedBox(height: 14),
              _DropdownField<BikeGearType>(
                label: AppText.t('gearType'),
                value: _selectedGearType,
                items: BikeGearType.values,
                labelBuilder: _gearTypeLabel,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedGearType = value);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: AppText.t('bikeAccessories'),
          subtitle: AppText.t('bikeAccessoriesSubtitle'),
          child: Column(
            children: [
              _SwitchLine(
                label: AppText.t('mudguards'),
                value: _hasMudguards,
                onChanged: (value) => setState(() => _hasMudguards = value),
              ),
              _SwitchLine(
                label: AppText.t('kickstand'),
                value: _hasKickstand,
                onChanged: (value) => setState(() => _hasKickstand = value),
              ),
              _SwitchLine(
                label: AppText.t('bottleCage'),
                value: _hasBottleCage,
                onChanged: (value) => setState(() => _hasBottleCage = value),
              ),
              _SwitchLine(
                label: AppText.t('rearLight'),
                value: _hasRearLight,
                onChanged: (value) => setState(() => _hasRearLight = value),
              ),
              _SwitchLine(
                label: AppText.t('frontLight'),
                value: _hasFrontLight,
                onChanged: (value) => setState(() => _hasFrontLight = value),
              ),
              _SwitchLine(
                label: AppText.t('rearRack'),
                value: _hasRearRack,
                onChanged: (value) => setState(() => _hasRearRack = value),
              ),
              _SwitchLine(
                label: AppText.t('bell'),
                value: _hasBell,
                onChanged: (value) => setState(() => _hasBell = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _CreateButton(saving: _saving, onPressed: _saveBike),
      ],
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: SafeArea(bottom: false, child: content),
    );
  }

  String _bikeTypeLabel(BikeType type) {
    switch (type) {
      case BikeType.road:
        return AppText.t('road');
      case BikeType.gravel:
        return AppText.t('gravel');
      case BikeType.mtb:
        return AppText.t('mtb');
      case BikeType.city:
        return AppText.t('city');
      case BikeType.ebike:
        return AppText.t('ebike');
      case BikeType.kidsMtb:
        return AppText.t('kidsMtb');
    }
  }

  String _frameColorLabel(BikeFrameColor color) {
    switch (color) {
      case BikeFrameColor.black:
        return AppText.t('black');
      case BikeFrameColor.blue:
        return AppText.t('blue');
      case BikeFrameColor.green:
        return AppText.t('green');
      case BikeFrameColor.red:
        return AppText.t('red');
      case BikeFrameColor.white:
        return AppText.t('white');
      case BikeFrameColor.grey:
        return AppText.t('grey');
      case BikeFrameColor.silver:
        return AppText.t('silver');
      case BikeFrameColor.custom:
        return AppText.t('custom');
    }
  }

  String _handlebarLabel(BikeHandlebarType type) {
    switch (type) {
      case BikeHandlebarType.drop:
        return AppText.t('dropHandlebar');
      case BikeHandlebarType.flat:
        return AppText.t('flatHandlebar');
      case BikeHandlebarType.rise:
        return AppText.t('riseHandlebar');
      case BikeHandlebarType.unknown:
        return AppText.t('unknown');
    }
  }

  String _brakeTypeLabel(BikeBrakeType type) {
    switch (type) {
      case BikeBrakeType.disc:
        return AppText.t('discBrake');
      case BikeBrakeType.rim:
        return AppText.t('rimBrake');
      case BikeBrakeType.coaster:
        return AppText.t('coasterBrake');
      case BikeBrakeType.unknown:
        return AppText.t('unknown');
    }
  }

  String _gearTypeLabel(BikeGearType type) {
    switch (type) {
      case BikeGearType.singleSpeed:
        return AppText.t('singleSpeed');
      case BikeGearType.internalHub:
        return AppText.t('internalHub');
      case BikeGearType.externalDerailleur:
        return AppText.t('externalDerailleur');
      case BikeGearType.unknown:
        return AppText.t('unknown');
    }
  }

  String _wheelSizeLabel(BikeWheelSize size) {
    switch (size) {
      case BikeWheelSize.inch20:
        return '20"';
      case BikeWheelSize.inch24:
        return '24"';
      case BikeWheelSize.inch26:
        return '26"';
      case BikeWheelSize.inch275:
        return '27.5"';
      case BikeWheelSize.inch29:
        return '29"';
      case BikeWheelSize.c700:
        return '700C';
      case BikeWheelSize.unknown:
        return AppText.t('unknown');
    }
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onClose;

  const _TopBar({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, color: MunjaColors.text),
        ),
        const Spacer(),
        Text(
          AppText.t('digitalTwin').toUpperCase(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.52),
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const Spacer(),
        const SizedBox(width: 48),
      ],
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final int photosCount;

  const _HeroHeader({required this.photosCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.72),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: MunjaColors.mint.withOpacity(0.16)),
      ),
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withOpacity(0.12),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: MunjaColors.mint.withOpacity(0.24)),
            ),
            child: const Icon(
              Icons.directions_bike_rounded,
              color: MunjaColors.mint,
              size: 32,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            AppText.t('buildYourBike'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MunjaColors.text,
              fontSize: 25,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            AppText.t('buildYourBikeSubtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.48),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _ProgressPill(value: '$photosCount/4', label: AppText.t('photos')),
        ],
      ),
    );
  }
}

class _ProgressPill extends StatelessWidget {
  final String value;
  final String label;

  const _ProgressPill({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: MunjaColors.mint.withOpacity(0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MunjaColors.mint.withOpacity(0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.56),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.62),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: MunjaColors.text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.42),
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  final List<XFile> photos;
  final ValueChanged<int> onRemove;
  final VoidCallback onAddFromCamera;
  final VoidCallback onAddFromGallery;

  const _PhotoGrid({
    required this.photos,
    required this.onRemove,
    required this.onAddFromCamera,
    required this.onAddFromGallery,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GridView.builder(
          itemCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            if (index < photos.length) {
              return _PhotoTile(
                file: File(photos[index].path),
                onRemove: () => onRemove(index),
              );
            }

            return const _EmptyPhotoTile();
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MiniActionButton(
                icon: Icons.photo_camera_rounded,
                label: AppText.t('camera'),
                onPressed: onAddFromCamera,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniActionButton(
                icon: Icons.photo_library_rounded,
                label: AppText.t('gallery'),
                onPressed: onAddFromGallery,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final File file;
  final VoidCallback onRemove;

  const _PhotoTile({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.file(file, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.72),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 15,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyPhotoTile extends StatelessWidget {
  const _EmptyPhotoTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Icon(
        Icons.add_photo_alternate_rounded,
        color: Colors.white.withOpacity(0.28),
        size: 22,
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _MiniActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MunjaColors.mint.withOpacity(0.11),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: MunjaColors.mint.withOpacity(0.20)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: MunjaColors.mint, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 12,
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

class _MunjaTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _MunjaTextField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(
        color: MunjaColors.text,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Colors.white.withOpacity(0.46),
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: Colors.black.withOpacity(0.18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: MunjaColors.mint.withOpacity(0.50)),
        ),
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T value) labelBuilder;
  final ValueChanged<T?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      dropdownColor: MunjaColors.panel,
      iconEnabledColor: MunjaColors.mint,
      style: const TextStyle(
        color: MunjaColors.text,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Colors.white.withOpacity(0.46),
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: Colors.black.withOpacity(0.18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: MunjaColors.mint.withOpacity(0.50)),
        ),
      ),
      items: items.map((item) {
        return DropdownMenuItem<T>(
          value: item,
          child: Text(labelBuilder(item)),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}

class _SwitchLine extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchLine({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: MunjaColors.mint,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(
          color: MunjaColors.text,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  final bool saving;
  final VoidCallback onPressed;

  const _CreateButton({required this.saving, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MunjaColors.mint,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: saving ? null : onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 58,
          alignment: Alignment.center,
          child: saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.black,
                  ),
                )
              : Text(
                  AppText.t('createBike').toUpperCase(),
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
        ),
      ),
    );
  }
}
