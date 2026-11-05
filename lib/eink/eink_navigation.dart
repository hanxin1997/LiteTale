import 'package:flutter/material.dart';

/// Plain, opaque navigation for reflective displays. Keeping this separate from
/// the animated bars lets Home retain its existing page and Cubit instances.
class EInkNavigationDestination {
  const EInkNavigationDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.showBadge = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool showBadge;
}

class EInkNavigationBar extends StatelessWidget {
  const EInkNavigationBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<EInkNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    animationDuration: Duration.zero,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.black)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _StaticNavigationItem(
                    destination: destinations[i],
                    selected: selectedIndex == i,
                    onTap: () => onDestinationSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _StaticNavigationItem extends StatelessWidget {
  const _StaticNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final EInkNavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${destination.label}${destination.showBadge ? '，有新版本' : ''}',
    onTap: onTap,
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: selected ? Colors.black : Colors.white,
          animationDuration: Duration.zero,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        selected ? destination.selectedIcon : destination.icon,
                        color: selected ? Colors.white : Colors.black,
                      ),
                      if (destination.showBadge) ...[
                        const SizedBox(width: 3),
                        const DecoratedBox(
                          decoration: BoxDecoration(color: Colors.white),
                          child: Text(
                            '新',
                            style: TextStyle(color: Colors.black, fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected ? Colors.white : Colors.black,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
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

/// The labels update immediately, without TabBar's indicator interpolation.
/// The caller still owns the original lazily built TabBarView.
class EInkTabStrip extends StatelessWidget {
  const EInkTabStrip({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Semantics(
              selected: selectedIndex == i,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: selectedIndex == i ? Colors.black : Colors.white,
                  animationDuration: Duration.zero,
                  shape: const RoundedRectangleBorder(
                    side: BorderSide(color: Colors.black),
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                  child: InkWell(
                    onTap: () => onSelected(i),
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        labels[i],
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: selectedIndex == i ? Colors.white : Colors.black,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
