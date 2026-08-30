import 'package:flutter/material.dart';
import 'package:waflo_app/theme/colors.dart';
import 'package:waflo_app/widgets/answer_section.dart';
import 'package:waflo_app/widgets/side_bar.dart';
import 'package:waflo_app/widgets/sources_section.dart';
import 'dart:convert';
import 'package:waflo_app/widgets/chat_input_bar.dart';
import 'package:waflo_app/widgets/image_gallery.dart';
import 'package:waflo_app/services/chat_web_service.dart';

class ChatPage extends StatelessWidget {
  final String question;
  const ChatPage({super.key, required this.question});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          sidebar(),
          SizedBox(width: 100),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          question,
                          style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color : Colors.white),
                        ),
                        SizedBox(height : 24),
                        SourcesSection(),
                        StreamBuilder<List<String>>(
                          stream: ChatWebService().imagesStream,
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                              return ImageGallery(imageUrls: snapshot.data!);
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                        StreamBuilder<String>(
                          stream: ChatWebService().generatedImageStream,
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 20.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: Image.memory(
                                    base64Decode(snapshot.data!),
                                    width: double.infinity,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                        AnswerSection(),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: ChatInputBar(replacePage: true),
                ),
              ],
            ),
          ),
          Placeholder(
            strokeWidth: 0,
            color: AppColors.background,
          ),


        ],
      ),
    );
  }
}
