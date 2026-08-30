import 'package:flutter/material.dart';
import 'package:waflo_app/theme/colors.dart';

class SearchBarButton extends StatefulWidget {

  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  const SearchBarButton({super.key, required this.icon, required this.text, this.onTap});

  @override
  State<SearchBarButton> createState() => _SearchBarButtonState();
}

class _SearchBarButtonState extends State<SearchBarButton> {
  bool isHovered = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter : (event) {
          setState(() {
            isHovered = true;
          });
        },
        onExit : (event) {
          setState(() {
            isHovered = false;
          });
        },
        child: Container(
          padding : EdgeInsets.symmetric(vertical : 10, horizontal : 10),
          decoration : BoxDecoration(
            borderRadius : BorderRadius.circular(6.0),
            color : isHovered ? AppColors.proButton : Colors.transparent,
          ),
          child : Row (
            children: [ 
              Icon(widget.icon, color : AppColors.iconGrey,size : 20,),
              const SizedBox(width :8),
              Text(widget.text,style : TextStyle(color : AppColors.textGrey))
            ],)
        ),
      ),
    );
  }
}