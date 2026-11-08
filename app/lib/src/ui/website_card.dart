/// The Website card of the main screen: the last upload, Upload now and the
/// characters on the website.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:memories_core/memories_core.dart' hide UploadState;

import '../settings/settings_controller.dart';
import '../upload/upload_controller.dart';
import 'messages.dart';

class WebsiteCard extends StatelessWidget {
  const WebsiteCard({
    super.key,
    required this.upload,
    required this.settings,
    required this.onOpenSettings,
    this.clock = DateTime.now,
  });

  final UploadController upload;
  final SettingsController settings;
  final VoidCallback onOpenSettings;
  final DateTime Function() clock;

  Future<void> _copy(BuildContext context, RemoteCharacter c) async {
    await Clipboard.setData(ClipboardData(text: c.url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(linkCopiedText)));
  }

  Future<void> _remove(BuildContext context, RemoteCharacter c) async {
    final name = upload.describe(c.path).name;
    final site = settings.settings.site;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(removeFromWebsiteLabel),
        content: Text(removeQuestionText(name, site)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(removeLabel),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final gone = await upload.removeCharacter(c.path);
    if (!gone || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(removedText(name))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListenableBuilder(
          // The controller passes on each change of the settings.
          listenable: upload,
          builder: (context, _) {
            final site = settings.settings.site;
            final state = upload.state;
            final report = upload.lastReport;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    '$websiteTitle: ${siteLabel(site)}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                if (state == UploadState.unregistered) ...[
                  Text(cardNotRegisteredText(site)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: onOpenSettings,
                    child: const Text(openSettingsLabel),
                  ),
                ] else ...[
                  if (state == UploadState.off) ...[
                    const Text(cardUploadOffText),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: onOpenSettings,
                      child: const Text(openSettingsLabel),
                    ),
                  ] else ...[
                    Text(lastUploadText(upload.lastUpload, clock())),
                    if (state == UploadState.paused)
                      const Text(uploadPausedText)
                    else if (report != null)
                      Text(syncSummaryText(report)),
                    const SizedBox(height: 12),
                    if (state == UploadState.uploading) ...[
                      LinearProgressIndicator(
                        value: upload.progress,
                        semanticsLabel: uploadProgressText(
                          upload.progressCounts.done,
                          upload.progressCounts.total,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        uploadProgressText(
                          upload.progressCounts.done,
                          upload.progressCounts.total,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      onPressed: upload.canUploadNow
                          ? () => upload.uploadNow(resendRemoved: true)
                          : null,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: state == UploadState.uploading
                          ? const Text(
                              uploadingLabel,
                              semanticsLabel: 'Uploading, please wait',
                            )
                          : const Text(uploadNowLabel),
                    ),
                  ],
                  for (final issue in upload.issues)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        issue,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  for (final c in upload.characters) _character(context, c),
                  const SizedBox(height: 12),
                  Text(unlistedText, style: theme.textTheme.bodySmall),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _character(BuildContext context, RemoteCharacter c) {
    final who = upload.describe(c.path);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(who.name, style: Theme.of(context).textTheme.titleSmall),
          Text(c.url, style: Theme.of(context).textTheme.bodySmall),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _copy(context, c),
                child: Text(
                  copyLinkLabel,
                  semanticsLabel: 'Copy link of ${who.name}',
                ),
              ),
              TextButton(
                onPressed: upload.busy ? null : () => _remove(context, c),
                child: Text(
                  removeFromWebsiteLabel,
                  semanticsLabel: 'Remove ${who.name} from website',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
