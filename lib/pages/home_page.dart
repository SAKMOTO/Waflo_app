import 'package:flutter/material.dart';
import 'package:waflo_app/services/chat_web_service.dart';
import 'package:waflo_app/widgets/side_bar.dart';
import 'package:waflo_app/widgets/search_section.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String fullResponse = '';

  @override
  void initState() {
    super.initState();
    ChatWebService().connect();
  }

  void _handleNavigation(int index) {
    if (index == 1) {
      Navigator.pushReplacementNamed(context, '/commerce');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          sidebar(onNavigate: _handleNavigation),
          Expanded(
            child: Column(
              children: [
                Expanded(child: SearchSection()),
               
                Container(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Wrap(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: GestureDetector(
                          onTap: () {
                            // Handle tap event
                          },
                          child: Text(
                            '© 2026 Waflo Inc. All rights reserved.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
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

          ///side nav bar
          ///search section
          /// footer section
        ],
      ),
    );
  }
}
