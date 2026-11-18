import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/campus_service.dart';
import '../theme.dart';

/// Which bottom tab is selected. Detail screens change it to jump tabs.
final ValueNotifier<int> currentTab = ValueNotifier<int>(0);

// =============================================================================
// Header + bottom bar (every screen except Login / Register)
// =============================================================================

/// White header: CUT logo (main tabs) or a back arrow (detail screens),
/// navy title, logout on the right, and the red + gold CUT shield line underneath.
PreferredSizeWidget ccAppBar(BuildContext context, {String? title, bool showLogout = true}) {
  final canPop = Navigator.of(context).canPop();
  return AppBar(
    toolbarHeight: 60,
    backgroundColor: CC.white,
    foregroundColor: CC.navy,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
    systemOverlayStyle: const SystemUiOverlayStyle(
      statusBarColor: CC.white,
      statusBarIconBrightness: Brightness.dark, // Android
      statusBarBrightness: Brightness.light, // iOS
    ),
    iconTheme: const IconThemeData(color: CC.navy),
    titleTextStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: CC.navy),
    automaticallyImplyLeading: canPop,
    leadingWidth: canPop ? null : 110.0,
    leading: canPop
        ? null
        : const Padding(
            padding: EdgeInsets.only(left: 14),
            child: Align(alignment: Alignment.centerLeft, child: CutLogo(height: 36)),
          ),
    title: title == null ? null : Text(title),
    bottom: const CCShieldLine(),
    actions: [if (showLogout) const CCLogoutButton()],
  );
}

/// Thin red + gold line taken from the CUT shield.
class CCShieldLine extends StatelessWidget implements PreferredSizeWidget {
  const CCShieldLine({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(4);

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 4,
        child: Row(children: [
          Expanded(flex: 65, child: ColoredBox(color: CC.cutRed)),
          Expanded(flex: 35, child: ColoredBox(color: CC.cutGold)),
        ]),
      );
}

/// Logout icon in the header.
class CCLogoutButton extends StatelessWidget {
  const CCLogoutButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Logout',
        icon: const Icon(Icons.logout_rounded, color: CC.navy),
        onPressed: () async {
          await CampusService.instance.logout(); // AuthGate returns to Login
          if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
        },
      );
}

/// Home / Coupons / Events / Profile: white bar, navy icons, navy pill on the open tab.
class CCBottomNav extends StatelessWidget {
  const CCBottomNav({super.key, this.popToShell = false});

  /// true on pushed detail screens: tapping a tab closes the detail screen first.
  final bool popToShell;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: currentTab,
      builder: (context, index, _) => DecoratedBox(
        decoration: const BoxDecoration(
          color: CC.white,
          border: Border(top: BorderSide(color: CC.border)),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: CC.white,
            surfaceTintColor: Colors.transparent,
            indicatorColor: CC.navy,
            elevation: 0,
            iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                  color: states.contains(WidgetState.selected) ? CC.white : CC.navy,
                )),
            labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                  fontSize: 12,
                  color: CC.navy,
                  fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
                )),
          ),
          child: NavigationBar(
            height: 66,
            selectedIndex: index,
            onDestinationSelected: (i) {
              if (popToShell) Navigator.of(context).popUntil((r) => r.isFirst);
              currentTab.value = i;
            },
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
              NavigationDestination(
                  icon: Icon(Icons.local_activity_outlined),
                  selectedIcon: Icon(Icons.local_activity_rounded),
                  label: 'Coupons'),
              NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month_rounded),
                  label: 'Events'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Login / Register widgets (unchanged look)
// =============================================================================

/// Grey rounded input with leading icon (Login / Registration screens).
class CCField extends StatelessWidget {
  const CCField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.validator,
    this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon), suffixIcon: suffix),
        ),
      );
}

/// Password field with the eye toggle from the design.
class CCPasswordField extends StatefulWidget {
  const CCPasswordField({super.key, required this.controller, required this.hint, this.validator});
  final TextEditingController controller;
  final String hint;
  final String? Function(String?)? validator;

  @override
  State<CCPasswordField> createState() => _CCPasswordFieldState();
}

class _CCPasswordFieldState extends State<CCPasswordField> {
  bool _hidden = true;
  @override
  Widget build(BuildContext context) => CCField(
        controller: widget.controller,
        hint: widget.hint,
        icon: Icons.lock,
        obscure: _hidden,
        validator: widget.validator,
        suffix: IconButton(
          icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off, color: CC.black),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      );
}

/// CUT logo. Put your exported logo at assets/images/cut_logo.png
class CutLogo extends StatelessWidget {
  const CutLogo({super.key, this.height = 70});
  final double height;
  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/cut_logo.png',
        height: height,
        errorBuilder: (_, __, ___) => Text('CUT',
            style: TextStyle(fontSize: height * 0.5, fontWeight: FontWeight.w900, color: CC.navy)),
      );
}

void showMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? CC.points : CC.navy,
  ));
}

// =============================================================================
// Building blocks for the white CUT screens
// =============================================================================

/// White card with a fine grey border and a faint shadow.
class CCCard extends StatelessWidget {
  const CCCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap, this.radius = 12});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: CC.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: CC.border),
          boxShadow: CC.cardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      );
}

/// Very light box (the Figma grey boxes, lightened): balance, info rows, activity.
class CCTile extends StatelessWidget {
  const CCTile({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.margin = EdgeInsets.zero});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: CC.tileBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: CC.border),
        ),
        child: child,
      );
}

/// Figma list card: image on the left, details on the right (Events list + Coupons list).
class CCListCard extends StatelessWidget {
  const CCListCard({super.key, required this.image, required this.children, this.onTap, this.imageSize = 100});
  final Widget image;
  final List<Widget> children;
  final VoidCallback? onTap;
  final double imageSize;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: CCCard(
          padding: const EdgeInsets.all(10),
          onTap: onTap,
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: imageSize, height: imageSize, child: image),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
          ]),
        ),
      );
}

/// Rounded square with an icon (tiles, activity rows).
class CCIconBox extends StatelessWidget {
  const CCIconBox(this.icon, {super.key, this.color = CC.navy, this.background = CC.blueSoft, this.size = 40});
  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(size * 0.3)),
        alignment: Alignment.center,
        child: Icon(icon, color: color, size: size * 0.5),
      );
}

/// Small label: "Going", "+100 pts", "Food".
class CCPill extends StatelessWidget {
  const CCPill(this.text, {super.key, this.background = CC.tileBg, this.color = CC.navy, this.icon});
  final String text;
  final Color background;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(4)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}

/// The gold coin from the Figma screens.
class CCCoin extends StatelessWidget {
  const CCCoin({super.key, this.size = 50});
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/coin.png',
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => Icon(Icons.monetization_on, size: size, color: const Color(0xFFFDC117)),
      );
}

/// Network image. With no photo it shows the CUT logo (events) or a navy icon (coupons).
class CCImage extends StatelessWidget {
  const CCImage(this.url, {super.key, this.icon = Icons.event, this.fit = BoxFit.cover, this.showLogo = false});
  final String? url;
  final IconData icon;
  final BoxFit fit;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: CC.tileBg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(10),
      child: showLogo ? const CutLogo(height: 44) : Icon(icon, size: 40, color: CC.navy),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return Image.network(url!, fit: fit, errorBuilder: (_, __, ___) => placeholder);
  }
}

/// Figma filter tabs "All | Career | Other" and "All | Food | Retail".
class CCFilterChips extends StatelessWidget {
  const CCFilterChips({super.key, required this.options, required this.selected, required this.onSelected});
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          for (final o in options)
            GestureDetector(
              onTap: () => onSelected(o),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: o == selected ? CC.navy : CC.tileBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: o == selected ? CC.navy : CC.border),
                ),
                child: Text(o,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: o == selected ? CC.white : CC.navy,
                    )),
              ),
            ),
        ],
      );
}

/// Title row with an optional link on the right ("See all").
class CCSectionHeader extends StatelessWidget {
  const CCSectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Row(children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: CC.navy)),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text('$action ›', style: const TextStyle(color: CC.navy, fontWeight: FontWeight.w700)),
            ),
        ]),
      );
}

/// Friendly empty / nothing-found message.
class CCEmptyState extends StatelessWidget {
  const CCEmptyState({super.key, required this.icon, required this.title, this.message});
  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CCIconBox(icon, size: 64),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: CC.navy)),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: CC.muted)),
          ],
        ]),
      );
}

class CCLoading extends StatelessWidget {
  const CCLoading({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator(color: CC.navy));
}

class CCErrorView extends StatelessWidget {
  const CCErrorView(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CCEmptyState(icon: Icons.wifi_off_rounded, title: 'Something went wrong', message: message),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, color: CC.navy),
              label: const Text('Try again', style: TextStyle(color: CC.navy)),
            ),
        ]),
      );
}

/// "Today", "Tomorrow", "In 5 days", "Ended".
String daysUntilLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(date.year, date.month, date.day).difference(today).inDays;
  if (d < 0) return 'Ended';
  if (d == 0) return 'Today';
  if (d == 1) return 'Tomorrow';
  return 'In $d days';
}
