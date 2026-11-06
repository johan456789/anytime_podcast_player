// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/bloc/settings/settings_bloc.dart';
import 'package:anytime/l10n/L.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Settings for the AI chat assistant: an OpenAI compatible endpoint, API key
/// and model. When no API key is configured the assistant runs in demo mode
/// using the built in mock service.
class AiChatSettingsWidget extends StatefulWidget {
  const AiChatSettingsWidget({super.key});

  @override
  State<AiChatSettingsWidget> createState() => _AiChatSettingsWidgetState();
}

class _AiChatSettingsWidgetState extends State<AiChatSettingsWidget> {
  late final TextEditingController _endpointController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;

    /// Prefill the OpenAI completions endpoint for display; an explicitly
    /// cleared field stays empty, which returns the assistant to demo mode.
    _endpointController = TextEditingController(
        text: settings.aiChatEndpoint.isEmpty
            ? 'https://api.openai.com/v1/chat/completions'
            : settings.aiChatEndpoint);
    _apiKeyController = TextEditingController(text: settings.aiChatApiKey);
    _modelController = TextEditingController(text: settings.aiChatModel);
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final l = L.of(context)!;

    return Column(
      children: [
        if (settingsBloc.currentSettings.aiChatApiKey.isEmpty || settingsBloc.currentSettings.aiChatEndpoint.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l.ai_chat_demo_mode_note,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(color: Theme.of(context).hintColor),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0.0),
          child: TextField(
            controller: _endpointController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l.ai_chat_endpoint_label,
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8.0))),
            ),
            onChanged: settingsBloc.setAiChatEndpoint,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0.0),
          child: TextField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l.ai_chat_api_key_label,
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8.0))),
              suffixIcon: IconButton(
                icon: Icon(_obscureApiKey ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
              ),
            ),
            onChanged: settingsBloc.setAiChatApiKey,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
          child: TextField(
            controller: _modelController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l.ai_chat_model_label,
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8.0))),
            ),
            onChanged: settingsBloc.setAiChatModel,
          ),
        ),
      ],
    );
  }
}
