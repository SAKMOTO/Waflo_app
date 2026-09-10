import 'package:flutter/material.dart';
import 'package:waflo_app/theme/colors.dart';

class SideBarButton extends StatelessWidget {
  final bool isCollapsed;
  final IconData icon;
  final String text;

  /// Optional animated icon (e.g. a Lottie) shown in place of [icon].
  final Widget? iconWidget;

  const SideBarButton({
    super.key,
    required this.isCollapsed,
    required this.icon,
    required this.text,
    this.iconWidget,
  });

  @override
  Widget build(BuildContext context) {
    // Tooltip gives the label popup on hover for every icon, collapsed or not.
    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 300),
      child: Row(
        mainAxisAlignment:
            isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
            child: iconWidget ?? Icon(icon, color: AppColors.textPrimary, size: 34),
          ),
          isCollapsed
              ? const SizedBox()
              : Flexible(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
        ],
      ),
    );
  }
}