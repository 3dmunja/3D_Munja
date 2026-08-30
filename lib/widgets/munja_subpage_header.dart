import 'package:flutter/material.dart';

/// Standard header for Munja subpages.
///
/// Use on normal pushed pages such as Customize, Products, Devices and Bike info.
/// Modal sheets/dialogs should normally keep their close (X) button instead.
class MunjaSubpageHeader extends StatelessWidget {
  const MunjaSubpageHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.horizontalPadding = 34.0,
    this.topPadding = 18.0,
    this.bottomPadding = 22.0,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  final double horizontalPadding;
  final double topPadding;
  final double bottomPadding;

  static const Color _foregroundColor = Color(0xFFF5F7F6);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          topPadding,
          horizontalPadding,
          bottomPadding,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: onBack ?? () => Navigator.of(context).maybePop(),
                  child: const Center(
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: _foregroundColor,
                      size: 29,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _foregroundColor,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                  letterSpacing: -0.7,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 44,
                height: 44,
                child: Center(child: trailing),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
