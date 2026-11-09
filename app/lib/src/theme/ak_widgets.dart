/// The components of the website look that Material has no widget for: the header with the crest, the tabs of the
/// frame, the tags and the panel title. Each one matches a class of web/base.css or web/style.css.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ak_theme.dart' show akRule;
import 'tokens.dart';

// The literals of `.tab` and `.tab[aria-selected]` in web/style.css.
const Color _tabTop = Color(0xFF1B1F1F);
const Color _tabBottom = Color(0xFF101516);
const Color _tabOnTop = Color(0xFF3A2D16);
const Color _tabOnBottom = Color(0xFF1A1409);

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
/// Left and Right move the selection and the focus to the next tab; Tab moves between the tabs and the content. The
/// focused tab has a gold-light ring, as `:focus-visible` of the website.
class AkTabBar extends StatefulWidget {
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
  State<AkTabBar> createState() => _AkTabBarState();
}

class _AkTabBarState extends State<AkTabBar> {
  late final List<FocusNode> _nodes = [
    for (final t in widget.tabs) FocusNode(debugLabel: 'tab ${t.label}'),
  ];

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _move(int by) {
    final i = (widget.selected + by + widget.tabs.length) % widget.tabs.length;
    widget.onSelected(i);
    _nodes[i].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Tokens.edge, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _move(1),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _move(-1),
        },
        child: LayoutBuilder(
          // On a narrow window the tabs drop their icons and share the width.
          builder: (context, box) {
            final narrow = box.maxWidth < 560;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < widget.tabs.length; i++)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _TabButton(
                        key: ValueKey('tab-${widget.tabs[i].label}'),
                        tab: widget.tabs[i],
                        node: _nodes[i],
                        selected: i == widget.selected,
                        compact: narrow,
                        onTap: () => widget.onSelected(i),
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

class _TabButton extends StatefulWidget {
  const _TabButton({
    super.key,
    required this.tab,
    required this.node,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final AkTab tab;
  final FocusNode node;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.selected;
    final colour = selected ? Tokens.goldLight : Tokens.muted;
    final edge = selected ? Tokens.goldDim : Tokens.edgeSoft;
    final side = BorderSide(
      color: _focused ? Tokens.goldLight : edge,
      width: _focused ? 2 : 1,
    );
    return Semantics(
      button: true,
      selected: selected,
      focusable: true,
      focused: _focused,
      label: widget.tab.label,
      excludeSemantics: true,
      onTap: widget.onTap,
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
          border: Border(top: side, left: side, right: side),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        ),
        child: InkWell(
          focusNode: widget.node,
          onFocusChange: (v) => setState(() => _focused = v),
          onTap: widget.onTap,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 6 : 20,
                vertical: 11,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.tab.icon != null && !widget.compact) ...[
                    Icon(widget.tab.icon, size: 18, color: colour),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      widget.tab.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colour,
                        fontSize: widget.compact ? 12 : 13,
                        letterSpacing: widget.compact ? 0.2 : 1,
                      ),
                    ),
                  ),
                ],
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
          border: Border(bottom: BorderSide(color: akRule)),
        ),
        child: Text(label, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}
