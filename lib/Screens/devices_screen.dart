import 'package:flutter/material.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppText.t('myProducts'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 28),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: MunjaColors.panel,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 30,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: Image.asset(
                        'assets/brake_light.png',
                        height: 240,
                        width: double.infinity,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) {
                          return Container(
                            height: 240,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: MunjaColors.panelSoft,
                              borderRadius: BorderRadius.circular(26),
                            ),
                            child: const Icon(
                              Icons.light_mode_rounded,
                              size: 80,
                              color: MunjaColors.mint,
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 24),

                    Text(
                      AppText.t('smartBrakeLight'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      AppText.t('smartBrakeLightDescription'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: MunjaColors.textSoft,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 24),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: MunjaColors.mint.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: MunjaColors.mint.withOpacity(0.25),
                        ),
                      ),
                      child: Text(
                        AppText.t('noDeviceConnectedYet'),
                        style: TextStyle(
                          color: MunjaColors.mint,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.bluetooth_searching_rounded),
                        label: Text(
                          AppText.t('scanForProducts'),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
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
