import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:waflo_app/widgets/chat_input_bar.dart';

class SearchSection extends StatefulWidget {
  const SearchSection({super.key});

  @override
  State<SearchSection> createState() => _SearchSectionState();
}

class _SearchSectionState extends State<SearchSection> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Where knowledge meets WAFLO',
          style: GoogleFonts.ibmPlexMono(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 25,
            letterSpacing: 0.5,
          ),
        ),

        const SizedBox(height: 5),

        ChatInputBar(replacePage: false),
      ],
    );
  }
}
