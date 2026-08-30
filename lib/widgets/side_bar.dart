import 'package:flutter/material.dart';
import 'package:waflo_app/theme/colors.dart';
import 'package:waflo_app/widgets/side_bar_button.dart';

class sidebar extends StatefulWidget {
  final Function(int)? onNavigate; // Callback for navigation
  final int selectedIndex;         // 0 = Home, 1 = Commerce
  const sidebar({super.key, this.onNavigate, this.selectedIndex = 0});

  @override
  State<sidebar> createState() => _sidebarState();
}

class _sidebarState extends State<sidebar> {
  bool isCollapse = true;
  int _selectedIndex = 0; // 0 = Home, 1 = Commerce

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.selectedIndex;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration : Duration(milliseconds: 150),
      width: isCollapse ? 80 : 130,
      color: AppColors.sideNav,
      child: Column(
        crossAxisAlignment: isCollapse ? CrossAxisAlignment.center: CrossAxisAlignment.start,
        children: [
         Row(
          mainAxisAlignment : isCollapse ?  MainAxisAlignment.center: MainAxisAlignment.start,
           children: [
             Container(
                margin : EdgeInsets.symmetric(vertical : 15, horizontal : 15),
                child: Icon(Icons.auto_awesome_mosaic, color: Colors.white, size: 25),
              ),
              isCollapse ? const SizedBox():
              Text('Home',style :TextStyle(color : Colors.white,fontWeight : FontWeight.bold,fontSize : 15))
           ],
         ),

         // Navigation buttons with selection state
         _buildNavButton(
           icon: Icons.home, 
           text: 'Home', 
           index: 0,
           isSelected: _selectedIndex == 0,
         ),
         
         _buildNavButton(
           icon: Icons.shopping_cart, 
           text: 'Shop', 
           index: 1,
           isSelected: _selectedIndex == 1,
         ),
         
         SideBarButton(isCollapsed : isCollapse , icon: Icons.add, text: 'Add'),
         
         SideBarButton(isCollapsed : isCollapse , icon: Icons.search, text: 'Search'),
         
         SideBarButton(isCollapsed : isCollapse , icon: Icons.language, text: 'Spaces'),
         
           SideBarButton(isCollapsed : isCollapse , icon: Icons.auto_awesome, text: 'Discover'),
         
           SideBarButton(isCollapsed : isCollapse , icon: Icons.cloud, text: 'Library'),
         
           SideBarButton(isCollapsed : isCollapse , icon: Icons.settings, text: 'Settings'),
         
          Spacer(),

          SizedBox(height: 30),
        GestureDetector(
          onTap : (){
            setState(() {
              isCollapse = !isCollapse;
            });


          },
            child: AnimatedContainer(
              duration : Duration(milliseconds: 150),

              margin : EdgeInsets.symmetric(vertical : 15, horizontal : 15),
              child: Icon(
                isCollapse ?Icons.keyboard_arrow_right : Icons.keyboard_arrow_left, color: Colors.white, size: 25),
            ),
          )
          
        ],
      ),
    );
  }
  
  Widget _buildNavButton({
    required IconData icon,
    required String text,
    required int index,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
        // Notify parent widget about navigation
        if (widget.onNavigate != null) {
          widget.onNavigate!(index);
        }
      },
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: isCollapse ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Icon(
              icon, 
              color: isSelected ? Colors.blue : Colors.white, 
              size: 22
            ),
            if (!isCollapse) ...[
              SizedBox(width: 12),
              Text(
                text,
                style: TextStyle(
                  color: isSelected ? Colors.blue : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
