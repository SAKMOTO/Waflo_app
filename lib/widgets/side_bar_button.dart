import 'package:flutter/material.dart';

class SideBarButton extends StatelessWidget {
  final bool isCollapsed;
  final IconData icon;
  final String  text;
  const SideBarButton({super.key,
  required this.isCollapsed,
  required this.icon,
  required this.text
  });

  @override
  Widget build(BuildContext context) {
    return Row(
          mainAxisAlignment : isCollapsed ?  MainAxisAlignment.center: MainAxisAlignment.start,
           children: [
             Container(
                margin : EdgeInsets.symmetric(vertical : 15, horizontal : 15),
                child: Icon(icon, color: Colors.white, size: 25),
              ),
              isCollapsed ? const SizedBox():
              Text(text,style :TextStyle(color : Colors.white,fontWeight : FontWeight.bold,fontSize : 13))
           ],
         );
  }
}