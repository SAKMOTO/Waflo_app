import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:waflo_app/pages/chat_page.dart';
import 'package:waflo_app/pages/commerce_page.dart';
import 'package:waflo_app/theme/colors.dart';
import 'package:waflo_app/widgets/search_bar_button.dart';
import 'package:waflo_app/services/chat_web_service.dart';

class ChatInputBar extends StatefulWidget {
  final bool replacePage;
  const ChatInputBar({super.key, this.replacePage = false});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final queryController = TextEditingController();
  String? selectedFileName;
  String? selectedFileBase64;

  Future<void> pickFile() async {
    FilePickerResult? result = await FilePicker.pickFiles();
    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      List<int> fileBytes = await file.readAsBytes();
      setState(() {
        selectedFileName = result.files.single.name;
        selectedFileBase64 = base64Encode(fileBytes);
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
    queryController.dispose();
  }

  void _submit() {
    if (queryController.text.trim().isEmpty && selectedFileName == null) return;
    
    final queryText = queryController.text.trim();
    final isCommerceQuery = queryText.toLowerCase().contains('find') || 
                            queryText.toLowerCase().contains('buy') ||
                            queryText.toLowerCase().contains('shop');
    
    if (isCommerceQuery) {
      if (widget.replacePage) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => CommercePage(initialQuery: queryText),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CommercePage(initialQuery: queryText),
          ),
        );
      }
      return;
    }

    // Only send generic chat event if it's not a commerce query
    ChatWebService().chat(
      queryText,
      fileName: selectedFileName,
      fileBase64: selectedFileBase64,
    );
    
    if (widget.replacePage) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ChatPage(question: queryText),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatPage(question: queryText),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 700,
      decoration: BoxDecoration(
        color: AppColors.searchBar,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: AppColors.searchBarBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: queryController,
              style: TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'search anything ...',
                hintStyle: TextStyle(color: Colors.white, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.all(0),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (selectedFileName != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  Icon(Icons.attach_file, color: Colors.grey, size: 16),
                  SizedBox(width: 4),
                  Text(selectedFileName!, style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.grey, size: 16),
                    onPressed: () {
                      setState(() {
                        selectedFileName = null;
                        selectedFileBase64 = null;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  )
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.auto_awesome, size: 20),
                  onPressed: () {},
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
                SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.add_circle_outline, size: 20),
                  onPressed: pickFile,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
                Spacer(),
                GestureDetector(
                  onTap: _submit,
                  child: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.submitButton,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Icon(
                      Icons.arrow_forward,
                      color: AppColors.background,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
