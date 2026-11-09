/// The Website card of the Website tab: the last upload, Upload now and the
/// characters to upload, each with its page on the website once uploaded.
library;

import 'package:flutter/material.dart';
import 'package:memories_core/memories_core.dart' hide UploadState;

import '../../l10n/app_localizations.dart';
import '../platform/clipboard.dart';
import '../settings/settings_controller.dart';
import '../theme/ak_widgets.dart';
import '../upload/upload_controller.dart';
import 'character_detail.dart';
import 'messages.dart';

class WebsiteCard extends StatelessWidget {
  const WebsiteCard({
    super.key,
    required this.upload,
    required this.settings,
    this.clock = DateTime.now,
    this.copyText = copyToClipboard,
  });

  final UploadController upload;
  final SettingsController settings;
  final DateTime Function() clock;
  final CopyText copyText;

  Future<void> _copy(BuildContext context, RemoteCharacter c) async {
    await copyText(c.url);
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
                      onPressed: upload.canUploadNow ? upload.uploadNow : null,
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
                  const SizedBox(height: 12),
                  _selection(context),
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

  /// The most that the list of characters grows before it scrolls.
  static const double _listMaxHeight = 360;

  Widget _selection(BuildContext context) {
    final l = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final local = upload.localCharacters;
    final selected = local.where((c) => c.selected).length;
    final others = upload.remoteOnlyCharacters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.selectionTitle, style: textTheme.titleSmall),
        if (local.isEmpty)
          Text(l.noCharacters)
        else ...[
          if (selected == 0) Text(l.selectionHint),
          Text(l.selectionNote, style: textTheme.bodySmall),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: selected == local.length ? null : upload.selectAll,
                child: Text(l.selectAllLabel),
              ),
              TextButton(
                onPressed: selected == 0 ? null : upload.selectNone,
                child: Text(l.selectNoneLabel),
              ),
            ],
          ),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _listMaxHeight),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in local) _localRow(context, c),
              for (final c in others) _remoteOnlyRow(context, c),
            ],
          ),
        ),
      ],
    );
  }

  Widget _localRow(BuildContext context, LocalCharacter c) {
    final l = AppLocalizations.of(context);
    final remote = c.remote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: c.selected,
          onChanged: (v) =>
              upload.setCharacterSelected(c.summary.path, v ?? false),
          title: Text(c.summary.name),
          subtitle: characterDetail(c.summary, l),
        ),
        if (remote != null)
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: _page(context, remote, c.summary.name),
          ),
      ],
    );
  }

  Widget _remoteOnlyRow(BuildContext context, RemoteCharacter c) {
    final name = upload.describe(c.path).name;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: Theme.of(context).textTheme.titleSmall),
          _page(context, c, name),
        ],
      ),
    );
  }

  /// The link of an uploaded character, with Copy link and Remove from
  /// website.
  Widget _page(BuildContext context, RemoteCharacter c, String name) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(c.url, style: Theme.of(context).textTheme.bodySmall),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _copy(context, c),
              child: Text(
                l.copyLinkLabel,
                semanticsLabel: l.copyLinkSemantics(name),
              ),
            ),
            TextButton(
              onPressed: upload.busy ? null : () => _remove(context, c),
              child: Text(
                l.removeFromWebsiteLabel,
                semanticsLabel: l.removeFromWebsiteSemantics(name),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
