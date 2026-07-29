import 'dart:io';

import 'package:flutter/material.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/bike_profile.dart';
import '../widgets/munja_3d_bike_viewer.dart';

class BikeDetailScreen extends StatelessWidget {
  final BikeProfile bike;
  final bool active;
  final VoidCallback? onSetActive;

  const BikeDetailScreen({
    super.key,
    required this.bike,
    this.active = false,
    this.onSetActive,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 360),
          children: [
            _TopBar(
              title: bike.name,
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            Munja3DBikeViewer(
              height: 420,
              modelPath: bike.modelPath,
              brakeLightMounted: bike.hasRearLight,
              showControls: true,
            ),
            const SizedBox(height: 18),
            _BikeHeroInfo(bike: bike, active: active, onSetActive: onSetActive),
            const SizedBox(height: 16),
            _SectionCard(
              title: AppText.t('bikeComponents'),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoChip(
                    icon: Icons.category_rounded,
                    label: _bikeTypeLabel(bike.type),
                  ),
                  _InfoChip(
                    icon: Icons.circle_outlined,
                    label: _wheelSizeLabel(bike.wheelSize),
                  ),
                  _InfoChip(
                    icon: Icons.linear_scale_rounded,
                    label: _handlebarLabel(bike.handlebarType),
                  ),
                  _InfoChip(
                    icon: Icons.settings_rounded,
                    label: _gearTypeLabel(bike.gearType),
                  ),
                  _InfoChip(
                    icon: Icons.radio_button_checked_rounded,
                    label: _brakeTypeLabel(bike.brakeType),
                  ),
                  _InfoChip(
                    icon: Icons.palette_rounded,
                    label: _colorLabel(bike.frameColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: AppText.t('bikeAccessories'),
              child: Column(
                children: [
                  _AccessoryLine(
                    label: AppText.t('mudguards'),
                    enabled: bike.hasMudguards,
                  ),
                  _AccessoryLine(
                    label: AppText.t('kickstand'),
                    enabled: bike.hasKickstand,
                  ),
                  _AccessoryLine(
                    label: AppText.t('bottleCage'),
                    enabled: bike.hasBottleCage,
                  ),
                  _AccessoryLine(
                    label: AppText.t('rearLight'),
                    enabled: bike.hasRearLight,
                  ),
                  _AccessoryLine(
                    label: AppText.t('frontLight'),
                    enabled: bike.hasFrontLight,
                  ),
                  _AccessoryLine(
                    label: AppText.t('rearRack'),
                    enabled: bike.hasRearRack,
                  ),
                  _AccessoryLine(
                    label: AppText.t('bell'),
                    enabled: bike.hasBell,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ProductsCard(bike: bike),
            const SizedBox(height: 16),
            _PhotoSection(photoPaths: bike.photoPaths),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _TopBar({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded, color: MunjaColors.text),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MunjaColors.text,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _BikeHeroInfo extends StatelessWidget {
  final BikeProfile bike;
  final bool active;
  final VoidCallback? onSetActive;

  const _BikeHeroInfo({
    required this.bike,
    required this.active,
    this.onSetActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.68),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withOpacity(0.32)
              : Colors.white.withOpacity(0.07),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.directions_bike_rounded,
              color: MunjaColors.mint,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bike.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MunjaColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_bikeTypeLabel(bike.type)} · ${_wheelSizeLabel(bike.wheelSize)} · ${_colorLabel(bike.frameColor)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.46),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (active)
            _ActivePill()
          else
            TextButton(
              onPressed: onSetActive,
              child: Text(
                AppText.t('activate'),
                style: const TextStyle(
                  color: MunjaColors.mint,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivePill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: MunjaColors.mint.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MunjaColors.mint.withOpacity(0.32)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: MunjaColors.mint,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            AppText.t('active').toUpperCase(),
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

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
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: MunjaColors.mint, size: 16),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessoryLine extends StatelessWidget {
  final String label;
  final bool enabled;

  const _AccessoryLine({required this.label, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: enabled ? MunjaColors.mint : Colors.white24,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? MunjaColors.text : Colors.white38,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductsCard extends StatelessWidget {
  final BikeProfile bike;

  const _ProductsCard({required this.bike});

  @override
  Widget build(BuildContext context) {
    final hasProducts = bike.hasRearLight || bike.hasFrontLight || bike.hasBell;

    return _SectionCard(
      title: AppText.t('products'),
      child: hasProducts
          ? Column(
              children: [
                if (bike.hasRearLight)
                  _ProductLine(
                    icon: Icons.light_mode_rounded,
                    title: AppText.t('rearLight'),
                    subtitle: AppText.t('mounted'),
                  ),
                if (bike.hasFrontLight)
                  _ProductLine(
                    icon: Icons.flashlight_on_rounded,
                    title: AppText.t('frontLight'),
                    subtitle: AppText.t('mounted'),
                  ),
                if (bike.hasBell)
                  _ProductLine(
                    icon: Icons.notifications_rounded,
                    title: AppText.t('bell'),
                    subtitle: AppText.t('mounted'),
                  ),
              ],
            )
          : Text(
              AppText.t('noProductsMounted'),
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

class _ProductLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ProductLine({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Icon(icon, color: MunjaColors.mint, size: 21),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: MunjaColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.44),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        ],
      ),
    );
  }
}

class _PhotoSection extends StatelessWidget {
  final List<String> photoPaths;

  const _PhotoSection({required this.photoPaths});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: AppText.t('bikePhotos'),
      child: photoPaths.isEmpty
          ? Text(
              AppText.t('noBikePhotosYet'),
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            )
          : GridView.builder(
              itemCount: photoPaths.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemBuilder: (context, index) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.file(File(photoPaths[index]), fit: BoxFit.cover),
                );
              },
            ),
    );
  }
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

String _colorLabel(BikeFrameColor color) {
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
