/// The Website card of the Website tab: the last upload, Upload now and the
/// characters on the website.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:memories_core/memories_core.dart' hide UploadState;

import '../../l10n/app_localizations.dart';
import '../settings/settings_controller.dart';
import '../theme/ak_widgets.dart';
import '../upload/upload_controller.dart';
import 'messages.dart';

class WebsiteCard extends StatelessWidget {
  const WebsiteCard({
    super.key,
    required this.upload,
    required this.settings,
    this.clock = DateTime.now,
  });

  final UploadController upload;
  final SettingsController settings;
  final DateTime Function() clock;

  Future<void> _copy(BuildContext context, RemoteCharacter c) async {
    await Clipboard.setData(ClipboardData(text: c.url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).linkCopiedText)),
      );
  }

  Future<void> _remove(BuildContext context, RemoteCharacter c) async {
    final name = upload.describe(c.path).name;
    final site = settings.settings.site;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l.removeFromWebsiteLabel),
          content: Text(l.removeQuestionText(name, siteLabel(site))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.removeLabel),
            ),
          ],
        );
      },
    );
    if (yes != true) return;
    final gone = await upload.removeCharacter(c.path);
    if (!gone || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).removedText(name))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
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
                AkPanelTitle(l.websiteCardTitle(siteLabel(site))),
                if (state == UploadState.unregistered) ...[
                  Text(l.cardNotRegistered(siteLabel(site))),
                ] else ...[
                  if (state == UploadState.off) ...[
                    Text(l.cardUploadOff),
                  ] else ...[
                    Text(lastUploadText(l, upload.lastUpload, clock())),
                    if (state == UploadState.paused)
                      Text(l.uploadPausedText)
                    else if (report != null)
                      Text(syncSummaryText(l, report)),
                    const SizedBox(height: 12),
                    if (state == UploadState.uploading) ...[
                      LinearProgressIndicator(
                        value: upload.progress,
                        semanticsLabel: uploadProgressText(
                          l,
                          upload.progressCounts.done,
                          upload.progressCounts.total,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        uploadProgressText(
                          l,
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
                          ? Text(
                              l.uploadingLabel,
                              semanticsLabel: l.uploadingSemantics,
                            )
                          : Text(l.uploadNowLabel),
                    ),
                  ],
                  for (final issue in upload.issues)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        noticeText(l, issue),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  for (final c in upload.characters) _character(context, c),
                  const SizedBox(height: 12),
                  Text(l.unlistedText, style: theme.textTheme.bodySmall),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _character(BuildContext context, RemoteCharacter c) {
    final l = AppLocalizations.of(context);
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
                  l.copyLinkLabel,
                  semanticsLabel: l.copyLinkSemantics(who.name),
                ),
              ),
              TextButton(
                onPressed: upload.busy ? null : () => _remove(context, c),
                child: Text(
                  l.removeFromWebsiteLabel,
                  semanticsLabel: l.removeFromWebsiteSemantics(who.name),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
