import 'package:flutter/material.dart';

import '../core/theme/munja_colors.dart';

class PremiumProduct {
  final String title;
  final String subtitle;
  final IconData icon;
  final int batteryPercent;
  final bool connected;
  final bool active;

  const PremiumProduct({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.batteryPercent = 0,
    this.connected = false,
    this.active = false,
  });
}

class PremiumProductCarousel extends StatefulWidget {
  final List<PremiumProduct> products;
  final VoidCallback onOpenProducts;
  final VoidCallback? onAddProduct;

  const PremiumProductCarousel({
    super.key,
    required this.products,
    required this.onOpenProducts,
    this.onAddProduct,
  });

  @override
  State<PremiumProductCarousel> createState() => _PremiumProductCarouselState();
}

class _PremiumProductCarouselState extends State<PremiumProductCarousel> {
  final PageController _pageController = PageController(viewportFraction: 0.86);
  int currentIndex = 0;

  List<PremiumProduct> get _items {
    if (widget.products.isNotEmpty) return widget.products;

    return const [
      PremiumProduct(
        title: 'Software mode',
        subtitle: 'No hardware connected',
        icon: Icons.bluetooth_disabled_rounded,
        connected: false,
        active: true,
      ),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return Column(
      children: [
        SizedBox(
          height: 138,
          child: PageView.builder(
            controller: _pageController,
            itemCount: items.length,
            onPageChanged: (index) {
              setState(() => currentIndex = index);
            },
            itemBuilder: (context, index) {
              final product = items[index];

              return AnimatedPadding(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(
                  left: index == 0 ? 0 : 6,
                  right: 10,
                  top: currentIndex == index ? 0 : 8,
                  bottom: currentIndex == index ? 0 : 8,
                ),
                child: _ProductCard(
                  product: product,
                  onTap: widget.onOpenProducts,
                  onAddProduct: widget.onAddProduct,
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 10),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(items.length, (index) {
            final active = index == currentIndex;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 20 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: active
                    ? MunjaColors.mint
                    : Colors.white.withOpacity(0.22),
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  final PremiumProduct product;
  final VoidCallback onTap;
  final VoidCallback? onAddProduct;

  const _ProductCard({
    required this.product,
    required this.onTap,
    required this.onAddProduct,
  });

  @override
  Widget build(BuildContext context) {
    final color = product.connected ? MunjaColors.mint : MunjaColors.warning;

    return GestureDetector(
      onTap: product.connected ? onTap : onAddProduct ?? onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: MunjaColors.panel,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: color.withOpacity(product.connected ? 0.34 : 0.22),
          ),
          boxShadow: [
            BoxShadow(
              color: product.connected
                  ? MunjaColors.mint.withOpacity(0.14)
                  : Colors.black.withOpacity(0.22),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: color.withOpacity(0.13),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: color.withOpacity(0.28)),
              ),
              child: Icon(product.icon, color: color, size: 30),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          product.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      if (product.active) ...[
                        const SizedBox(width: 7),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: MunjaColors.mint,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: MunjaColors.mint.withOpacity(0.7),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 6),

                  Text(
                    product.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      _StatusPill(
                        icon: product.connected
                            ? Icons.bluetooth_connected_rounded
                            : Icons.bluetooth_disabled_rounded,
                        label: product.connected ? 'Connected' : 'Software',
                        color: color,
                      ),
                      const SizedBox(width: 8),
                      if (product.connected)
                        _StatusPill(
                          icon: Icons.battery_5_bar_rounded,
                          label: '${product.batteryPercent.clamp(0, 100)}%',
                          color: product.batteryPercent > 20
                              ? MunjaColors.mint
                              : Colors.orange,
                        )
                      else
                        _StatusPill(
                          icon: Icons.add_rounded,
                          label: 'Add',
                          color: Colors.white54,
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.38),
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
