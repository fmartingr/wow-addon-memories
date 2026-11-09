/// What the upload tells the user, kept as codes and arguments so that a
/// change of language re-translates a notice that is on the screen.
library;

import 'package:memories_core/memories_core.dart';

/// One message of the upload. [key] gives the value equality, so the same
/// problem is not listed twice.
sealed class Notice {
  const Notice();

  Object get key;

  @override
  bool operator ==(Object other) =>
      other is Notice && other.runtimeType == runtimeType && other.key == key;

  @override
  int get hashCode => Object.hash(runtimeType, key);
}

/// A failed request of the website or of the core. A known code has its own
/// text; an unknown one shows the English [message] of the server.
final class UploadErrorNotice extends Notice {
  const UploadErrorNotice(this.code, this.message, this.site, {this.who});

  UploadErrorNotice.of(UploadException e, String site, {String? who})
    : this(e.code, e.message, site, who: who);

  final String code;
  final String message;

  /// The website address as the settings hold it.
  final String site;

  /// The character that the error is about, or null.
  final String? who;

  @override
  Object get key => (code, message, site, who);
}

/// A character that another key already owns.
final class ClaimedNotice extends Notice {
  const ClaimedNotice(this.name, this.realm);

  final String name;

  /// The realm, or null when the app does not know it.
  final String? realm;

  @override
  Object get key => (name, realm);
}

/// The website rejected the data of a character. [problems] are the first
/// problems in the English of the website, each already joined in one text.
final class RejectedNotice extends Notice {
  const RejectedNotice(this.name, this.problems, this.more);

  final String name;
  final String problems;

  /// How many problems [problems] does not list.
  final int more;

  @override
  Object get key => (name, problems, more);
}

/// A text that the core wrote in English, such as the problem of one
/// screenshot. [text] shows as it is.
final class TextNotice extends Notice {
  const TextNotice(this.text);

  final String text;

  @override
  Object get key => text;
}

/// An address that the app does not accept.
final class SiteAddressNotice extends Notice {
  const SiteAddressNotice(this.error);

  final SiteError error;

  @override
  Object get key => error;
}

/// The website answered, but not as a Memories website.
final class NotAMemoriesSiteNotice extends Notice {
  const NotAMemoriesSiteNotice();

  @override
  Object get key => 0;
}

/// An action started while an upload or another action runs.
final class BusyNotice extends Notice {
  const BusyNotice();

  @override
  Object get key => 0;
}

/// A failure that the app did not foresee.
final class GenericFailureNotice extends Notice {
  const GenericFailureNotice();

  @override
  Object get key => 0;
}
