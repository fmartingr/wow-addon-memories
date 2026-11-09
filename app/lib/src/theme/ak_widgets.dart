/// The components of the website look that Material has no widget for: the header with the crest, the tabs of the
/// frame, the tags and the panel title. Each one matches a class of web/base.css or web/style.css.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

// The literals of `.tab` and `.tab[aria-selected]` in web/style.css.
const Color _tabTop = Color(0xFF1B1F1F);
const Color _tabBottom = Color(0xFF101516);
const Color _tabOnTop = Color(0xFF3A2D16);
const Color _tabOnBottom = Color(0xFF1A1409);
const Color _rule = Color(0xFF423B2D);

/// The title bar of the window: the crest and the name of the app, as `.frame-head`.
class AkHeader extends StatelessWidget {
  const AkHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Tokens.goldDim, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black, spreadRadius: 2),
                BoxShadow(color: Color(0x33D5A64F), blurRadius: 14),
              ],
              image: const DecorationImage(
                image: AssetImage('assets/crest.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tab of [AkTabBar].
class AkTab {
  const AkTab({required this.label, this.icon});

  final String label;
  final IconData? icon;
}

/// The tabs at the top of the window, as `.tabs` of the website: raised tabs with a gold edge, the selected one lit.
/// Left and Right move the selection while a tab has the focus; Tab moves between the tabs and the content.
class AkTabBar extends StatelessWidget {
  const AkTabBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<AkTab> tabs;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Tokens.edge, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              onSelected((selected + 1) % tabs.length),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              onSelected((selected - 1 + tabs.length) % tabs.length),
        },
        child: LayoutBuilder(
          // On a narrow window the tabs drop their icons and share the width.
          builder: (context, box) {
            final narrow = box.maxWidth < 560;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _TabButton(
                        key: ValueKey('tab-${tabs[i].label}'),
                        tab: tabs[i],
                        selected: i == selected,
                        compact: narrow,
                        onTap: () => onSelected(i),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.tab,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final AkTab tab;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = selected ? Tokens.goldLight : Tokens.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(top: selected ? 0 : 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: selected
                ? const [_tabOnTop, _tabOnBottom]
                : const [_tabTop, _tabBottom],
          ),
          border: Border(
            top: BorderSide(color: selected ? Tokens.goldDim : Tokens.edgeSoft),
            left: BorderSide(
              color: selected ? Tokens.goldDim : Tokens.edgeSoft,
            ),
            right: BorderSide(
              color: selected ? Tokens.goldDim : Tokens.edgeSoft,
            ),
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 20),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tab.icon != null && !compact) ...[
                      Icon(tab.icon, size: 18, color: colour),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        tab.label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colour,
                          fontSize: 13,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The kinds of [AkTag], with the colours of `.tag` in web/style.css.
enum AkTagKind {
  plain(Tokens.muted, Tokens.edge),
  alliance(Color(0xFF7FB4FF), Color(0xFF3D5F96)),
  horde(Color(0xFFFF7A6B), Color(0xFF8F3A31)),
  hardcore(Color(0xFFFF5A43), Color(0xFF8F2A1E)),
  selfFound(Color(0xFF1EFF00), Color(0xFF2B7A1E));

  const AkTagKind(this.ink, this.edge);

  final Color ink;
  final Color edge;
}

/// A small label with a border, as `.tag`.
class AkTag extends StatelessWidget {
  const AkTag(this.label, {super.key, this.kind = AkTagKind.plain});

  final String label;
  final AkTagKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: kind.edge),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: kind.ink, fontSize: 11, letterSpacing: 0.9),
      ),
    );
  }
}

/// The title of a panel, as `.panel-title`: gold capitals with a line under them.
class AkPanelTitle extends StatelessWidget {
  const AkPanelTitle(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.only(bottom: 8),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _rule)),
        ),
        child: Text(label, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}
