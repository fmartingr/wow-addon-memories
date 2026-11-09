/// The registration part of the Website tab: the address, the registration, the
/// Upload switch and the screenshots.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../settings/settings_controller.dart';
import '../theme/ak_widgets.dart';
import '../upload/notice.dart';
import '../upload/upload_controller.dart';
import 'messages.dart';

class WebsiteSection extends StatefulWidget {
  const WebsiteSection({
    super.key,
    required this.upload,
    required this.settings,
  });

  final UploadController upload;
  final SettingsController settings;

  @override
  State<WebsiteSection> createState() => _WebsiteSectionState();
}

class _WebsiteSectionState extends State<WebsiteSection> {
  late final TextEditingController _address = TextEditingController(
    text: widget.settings.settings.site,
  );
  final TextEditingController _invite = TextEditingController();
  Notice? _addressError;

  UploadController get _upload => widget.upload;

  @override
  void dispose() {
    _address.dispose();
    _invite.dispose();
    super.dispose();
  }

  /// Saves the address of the field. Returns false and shows why when the app
  /// does not accept it.
  bool _apply() {
    final error = _upload.changeSite(_address.text);
    setState(() => _addressError = error);
    if (error != null) return false;
    _address.text = widget.settings.settings.site;
    return true;
  }

  Future<void> _check() async {
    if (_apply()) await _upload.checkSite();
  }

  Future<void> _register() async {
    if (!_apply()) return;
    // The field is hidden on a website with open registration, so its text
    // may be left from another website.
    final open = _upload.siteInfo?.registration == 'open';
    if (await _upload.register(open ? null : _invite.text)) _invite.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final errorStyle = TextStyle(color: theme.colorScheme.error);
    return ListenableBuilder(
      // The controller passes on each change of the settings.
      listenable: _upload,
      builder: (context, _) {
        final registered = _upload.registered;
        final info = _upload.siteInfo;
        final open = info?.registration == 'open';
        final fingerprint = _upload.fingerprint;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AkPanelTitle(l.registrationTitle),
              TextField(
                controller: _address,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l.websiteAddressLabel,
                  errorText: _addressError == null
                      ? null
                      : noticeText(l, _addressError!),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _check(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: _upload.checking ? null : _check,
                  child: Text(l.checkSiteLabel),
                ),
              ),
              if (info != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(siteFoundText(l, info)),
                ),
              if (_upload.siteError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    noticeText(l, _upload.siteError!),
                    style: errorStyle,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                registered
                    ? l.registeredText(siteLabel(widget.settings.settings.site))
                    : l.notRegisteredText(
                        siteLabel(widget.settings.settings.site),
                      ),
              ),
              if (!registered) ...[
                if (!open) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _invite,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: l.inviteCodeLabel,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _register(),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _upload.registering ? null : _register,
                    child: Text(l.registerLabel),
                  ),
                ),
                if (_upload.registerError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      noticeText(l, _upload.registerError!),
                      style: errorStyle,
                    ),
                  ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.uploadSwitchTitle),
                subtitle: Text(l.uploadSwitchSubtitle),
                value: widget.settings.settings.upload,
                onChanged: registered
                    ? (v) => widget.settings.update(
                        widget.settings.settings.copyWith(upload: v),
                      )
                    : null,
              ),
              if (registered) ...[
                Text(screenshotsText(l, _upload.screenshots)),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: _upload.canRequestScreenshots
                        ? _upload.requestScreenshots
                        : null,
                    child: Text(l.requestScreenshotsLabel),
                  ),
                ),
              ],
              if (fingerprint != null) ...[
                const SizedBox(height: 16),
                Text(l.fingerprintText(fingerprint)),
                const SizedBox(height: 4),
                Text(l.lostKeyText, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        );
      },
    );
  }
}
