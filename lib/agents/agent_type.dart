import 'package:flutter/material.dart';

/// The five agent identities exposed by the Agent Hub.
///
/// Each maps to a fully working executor (browser / files / research / coding
/// / writing). The home screen shows one avatar character per agent; selecting
/// a character routes its tasks to the matching executor in
/// [AgentWorkspacePage].
enum AgentType {
  /// STROBI — Browser Agent (opens a real browser via browser-use).
  researcher,

  /// BUBBLES — File Editing & Manipulation Agent (in-app file workspace).
  fileEditing,

  /// COSMO — Research & Analysis Agent (web search + LLM analysis).
  research,

  /// NIXA — Coding & Development Agent (in-app coding workspace).
  coding,

  /// SUNNY — Writing & Communication Agent (LLM writing, no search).
  writing,
}

class AgentIdentity {
  final AgentType type;
  final String name;
  final String role;
  final String description;
  final String riveAsset;
  final Color accent;
  final IconData icon;

  const AgentIdentity({
    required this.type,
    required this.name,
    required this.role,
    required this.description,
    required this.riveAsset,
    required this.accent,
    required this.icon,
  });
}

const Map<AgentType, AgentIdentity> agentIdentities = {
  AgentType.researcher: AgentIdentity(
    type: AgentType.researcher,
    name: 'STROBI',
    role: 'Browser Agent',
    description:
        'Opens a real browser, navigates websites, extracts information and '
        'compares options to complete research and shopping workflows.',
    riveAsset: 'assets/rive/5845-11463-curious-phone-girl.riv',
    accent: Color(0xFF5B7FE5),
    icon: Icons.travel_explore,
  ),
  AgentType.fileEditing: AgentIdentity(
    type: AgentType.fileEditing,
    name: 'BUBBLES',
    role: 'File Editing & Manipulation Agent',
    description:
        'Inspects, creates, edits and deletes files in a project workspace. '
        'Makes small, targeted changes and asks before any destructive step.',
    riveAsset: 'assets/rive/16499-31053-bubble-gum-boy.riv',
    accent: Color(0xFFE85D9C),
    icon: Icons.edit_note,
  ),
  AgentType.research: AgentIdentity(
    type: AgentType.research,
    name: 'COSMO',
    role: 'Research & Analysis Agent',
    description:
        'Searches the live web, weighs sources and delivers a researched, '
        'analysed answer — stats, comparisons and takeaways included.',
    riveAsset: 'assets/rive/8115-15583-no-back.riv',
    accent: Color(0xFF2FD6A8),
    icon: Icons.manage_search,
  ),
  AgentType.coding: AgentIdentity(
    type: AgentType.coding,
    name: 'NIXA',
    role: 'Coding & Development Agent',
    description:
        'Writes, edits and refactors code in the project workspace — list the '
        'files, read any source, create new ones and ask it to implement things.',
    riveAsset: 'assets/rive/17942-33773-character-test.riv',
    accent: Color(0xFF8B5CF6),
    icon: Icons.code,
  ),
  AgentType.writing: AgentIdentity(
    type: AgentType.writing,
    name: 'SUNNY',
    role: 'Writing & Communication Agent',
    description:
        'Drafts emails, essays, captions, scripts and brand copy with a '
        'natural writer\u2019s voice. Tell it what to write and for whom.',
    riveAsset: 'assets/rive/8115-15583-no-back.riv',
    accent: Color(0xFFFFB020),
    icon: Icons.edit,
  ),
};

AgentIdentity agentIdentityOf(AgentType type) => agentIdentities[type]!;

List<AgentIdentity> get allAgents => agentIdentities.values.toList();

/// Maps the selected avatar character (the roster shown in the home character
/// dropdown) to its agent identity. Unknown ids fall back to STROBI.
AgentIdentity agentIdentityForCharacter(String characterId) {
  final type = switch (characterId) {
    'bubbles' => AgentType.fileEditing,
    'cosmo' => AgentType.research,
    'nixa' => AgentType.coding,
    'sunny' => AgentType.writing,
    _ => AgentType.researcher,
  };
  return agentIdentities[type]!;
}

/// Maps an agent back to the avatar character id rendered for it.
String characterIdOf(AgentType type) => switch (type) {
      AgentType.researcher => 'strobi',
      AgentType.fileEditing => 'bubbles',
      AgentType.research => 'cosmo',
      AgentType.coding => 'nixa',
      AgentType.writing => 'sunny',
    };