import 'package:flutter/material.dart';

import '../core/theme/munja_colors.dart';
import '../models/firestore_bike.dart';
import '../widgets/munja_subpage_header.dart';

class BikeInfoScreen extends StatelessWidget {
  const BikeInfoScreen({
    super.key,
    required this.bike,
    this.onEdit,
  });

  final FirestoreBike bike;

  /// Optional edit action supplied by Garage.
  ///
  /// In the next step Garage can pass its existing bike editor callback here,
  /// so Bike Info remains a clean read-only overview.
  final VoidCallback? onEdit;

  String get _bikeTypeLabel {
    final value = bike.type.name.trim();

    if (value.isEmpty) {
      return 'Bike';
    }

    if (value.toLowerCase() == 'mtb') {
      return 'MTB';
    }

    if (value.toLowerCase() == 'ebike') {
      return 'E-bike';
    }

    return value[0].toUpperCase() +
        value.substring(1).toLowerCase();
  }

  String _displayValue(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? '—' : normalized;
  }

  String get _bikeDescription {
    final values = <String>[
      _bikeTypeLabel,
      if (bike.brand.trim().isNotEmpty) bike.brand.trim(),
      if (bike.model.trim().isNotEmpty) bike.model.trim(),
    ];

    return values.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: Column(
        children: [
          MunjaSubpageHeader(
            title: 'Bike info',
            trailing: onEdit == null
                ? null
                : IconButton(
                    tooltip: 'Rediger cykel',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                    icon: const Icon(
                      Icons.edit_rounded,
                      color: MunjaColors.mint,
                      size: 22,
                    ),
                  ),
          ),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                20,
                0,
                20,
                180,
              ),
              children: [
                _BikeInfoHero(
                  bike: bike,
                  typeLabel: _bikeTypeLabel,
                  description: _bikeDescription,
                ),
                const SizedBox(height: 24),
                const _SectionHeader(
                  title: 'Bike details',
                  subtitle:
                      'De vigtigste oplysninger om din aktive cykel.',
                ),
                const SizedBox(height: 12),
                _DetailsCard(
                  children: [
                    _InfoRow(
                      icon: Icons.badge_outlined,
                      label: 'Navn',
                      value: _displayValue(
                        bike.displayName,
                      ),
                    ),
                    _InfoRow(
                      icon: Icons.category_outlined,
                      label: 'Cykeltype',
                      value: _bikeTypeLabel,
                    ),
                    _InfoRow(
                      icon: Icons.business_outlined,
                      label: 'Mærke',
                      value: _displayValue(
                        bike.brand,
                      ),
                    ),
                    _InfoRow(
                      icon: Icons.pedal_bike_rounded,
                      label: 'Model',
                      value: _displayValue(
                        bike.model,
                      ),
                    ),
                    _InfoRow(
                      icon: Icons.palette_outlined,
                      label: 'Farve',
                      value: _displayValue(
                        bike.color,
                      ),
                    ),
                    _InfoRow(
                      icon: Icons.straighten_rounded,
                      label: 'Stelstørrelse',
                      value: _displayValue(
                        bike.frameSize,
                      ),
                    ),
                    _InfoRow(
                      icon: Icons.circle_outlined,
                      label: 'Hjulstørrelse',
                      value: _displayValue(
                        bike.wheelSize,
                      ),
                    ),
                    _InfoRow(
                      icon: Icons.qr_code_rounded,
                      label: 'Serienummer',
                      value: _displayValue(
                        bike.serialNumber,
                      ),
                      showDivider: false,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const _SectionHeader(
                  title: 'Digital Twin',
                  subtitle:
                      '3D-model, firmware og digital status for cyklen.',
                ),
                const SizedBox(height: 12),
                _DigitalTwinStatusCard(
                  digitalTwinEnabled:
                      bike.digitalTwinEnabled,
                  hasModel:
                      bike.hasDigitalTwinModel,
                  firmwareVersion:
                      _displayValue(
                    bike.firmwareVersion,
                  ),
                ),
                const SizedBox(height: 24),
                const _SectionHeader(
                  title: 'Notes',
                  subtitle:
                      'Ekstra information gemt på cyklen.',
                ),
                const SizedBox(height: 12),
                _NotesCard(
                  notes: bike.notes.trim(),
                ),
                const SizedBox(height: 24),
                if (onEdit != null)
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(
                        Icons.edit_rounded,
                      ),
                      label: const Text(
                        'Edit bike',
                        style: TextStyle(
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
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

class _BikeInfoHero extends StatelessWidget {
  const _BikeInfoHero({
    required this.bike,
    required this.typeLabel,
    required this.description,
  });

  final FirestoreBike bike;
  final String typeLabel;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(
          alpha: 0.76,
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: MunjaColors.mint.withValues(
            alpha: 0.17,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withValues(
              alpha: 0.07,
            ),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: MunjaColors.mint
                  .withValues(alpha: 0.10),
              borderRadius:
                  BorderRadius.circular(22),
              border: Border.all(
                color: MunjaColors.mint
                    .withValues(alpha: 0.17),
              ),
            ),
            child: Icon(
              _bikeIconFromTypeName(
                bike.type.name,
              ),
              color: MunjaColors.mint,
              size: 35,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  bike.displayName,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MunjaColors.text,
                    fontSize: 22,
                    fontWeight:
                        FontWeight.w900,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  maxLines: 2,
                  overflow:
                      TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white
                        .withValues(alpha: 0.45),
                    fontSize: 11,
                    height: 1.35,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _StatusPill(
                      icon:
                          Icons.check_circle_rounded,
                      label: bike.active
                          ? 'ACTIVE BIKE'
                          : 'BIKE',
                      active: bike.active,
                    ),
                    _StatusPill(
                      icon: Icons.view_in_ar_rounded,
                      label: bike.digitalTwinEnabled
                          ? 'DIGITAL TWIN'
                          : 'NO TWIN',
                      active:
                          bike.digitalTwinEnabled,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: MunjaColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withValues(
              alpha: 0.43,
            ),
            fontSize: 11,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(
          alpha: 0.62,
        ),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: 0.065,
          ),
        ),
      ),
      child: Column(
        children: children,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(
            vertical: 13,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: MunjaColors.mint
                      .withValues(alpha: 0.08),
                  borderRadius:
                      BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: MunjaColors.mint,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white
                        .withValues(alpha: 0.45),
                    fontSize: 11,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  value,
                  maxLines: 2,
                  overflow:
                      TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: MunjaColors.text,
                    fontSize: 12,
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.white.withValues(
              alpha: 0.045,
            ),
          ),
      ],
    );
  }
}

class _DigitalTwinStatusCard
    extends StatelessWidget {
  const _DigitalTwinStatusCard({
    required this.digitalTwinEnabled,
    required this.hasModel,
    required this.firmwareVersion,
  });

  final bool digitalTwinEnabled;
  final bool hasModel;
  final String firmwareVersion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(
          alpha: 0.62,
        ),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(
          color: MunjaColors.mint.withValues(
            alpha: 0.12,
          ),
        ),
      ),
      child: Column(
        children: [
          _TwinStatusRow(
            icon: Icons.view_in_ar_rounded,
            title: 'Digital Twin',
            value: digitalTwinEnabled
                ? 'Enabled'
                : 'Disabled',
            active: digitalTwinEnabled,
          ),
          const SizedBox(height: 10),
          _TwinStatusRow(
            icon: Icons.view_in_ar_rounded,
            title: '3D model',
            value: hasModel
                ? 'Model ready'
                : 'No model',
            active: hasModel,
          ),
          const SizedBox(height: 10),
          _TwinStatusRow(
            icon: Icons.system_update_rounded,
            title: 'Firmware',
            value: firmwareVersion,
            active: firmwareVersion != '—',
          ),
        ],
      ),
    );
  }
}

class _TwinStatusRow extends StatelessWidget {
  const _TwinStatusRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.active,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color:
            Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withValues(
                  alpha: 0.12,
                )
              : Colors.white.withValues(
                  alpha: 0.05,
                ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: active
                  ? MunjaColors.mint
                      .withValues(alpha: 0.10)
                  : Colors.white
                      .withValues(alpha: 0.035),
              borderRadius:
                  BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: active
                  ? MunjaColors.mint
                  : Colors.white54,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: MunjaColors.text,
                fontSize: 12,
                fontWeight:
                    FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active
                  ? MunjaColors.mint
                  : Colors.white54,
              fontSize: 11,
              fontWeight:
                  FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({
    required this.notes,
  });

  final String notes;

  @override
  Widget build(BuildContext context) {
    final hasNotes =
        notes.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(
          alpha: 0.60,
        ),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: 0.06,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            hasNotes
                ? Icons.notes_rounded
                : Icons
                    .sticky_note_2_outlined,
            color: hasNotes
                ? MunjaColors.mint
                : Colors.white38,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hasNotes
                  ? notes
                  : 'Ingen noter er gemt på cyklen endnu.',
              style: TextStyle(
                color: hasNotes
                    ? MunjaColors.textSoft
                    : Colors.white
                        .withValues(alpha: 0.35),
                fontSize: 11,
                height: 1.45,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint
                .withValues(alpha: 0.10)
            : Colors.white
                .withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? MunjaColors.mint
                  .withValues(alpha: 0.20)
              : Colors.white
                  .withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: active
                ? MunjaColors.mint
                : Colors.white54,
            size: 13,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: active
                  ? MunjaColors.mint
                  : Colors.white54,
              fontSize: 8,
              fontWeight:
                  FontWeight.w900,
              letterSpacing: 0.45,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _bikeIconFromTypeName(
  String typeName,
) {
  final normalized =
      typeName.toLowerCase();

  if (normalized.contains('road')) {
    return Icons.speed_rounded;
  }

  if (normalized.contains('city')) {
    return Icons.location_city_rounded;
  }

  if (normalized.contains('ebike') ||
      normalized.contains('electric')) {
    return Icons.electric_bike_rounded;
  }

  if (normalized.contains('kids') ||
      normalized.contains('child')) {
    return Icons.pedal_bike_rounded;
  }

  return Icons.directions_bike_rounded;
}
