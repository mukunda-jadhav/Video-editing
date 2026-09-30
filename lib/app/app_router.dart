import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/entitlements/presentation/premium_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/projects/presentation/projects_screen.dart';
import '../features/roadmap/presentation/roadmap_screen.dart';
import '../features/templates/presentation/templates_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'editor_host.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => HomeScreen(
                  onCreatePhoto: () => context.push('/photo'),
                  onCreateVideo: () => context.push('/video'),
                  onViewProjects: () => context.go('/projects'),
                  onViewTemplates: () => context.push('/templates'),
                  onViewPremium: () => context.go('/premium'),
                  onViewSettings: () => context.push('/settings'),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/projects',
                builder: (context, state) =>
                    const _ReturnHomeOnBack(child: ProjectsScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/premium',
                builder: (context, state) =>
                    const _ReturnHomeOnBack(child: PremiumScreen()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/photo',
        builder: (context, state) =>
            EditorHost(templateId: state.uri.queryParameters['template']),
      ),
      GoRoute(
        path: '/video',
        builder: (context, state) => EditorHost(
          video: true,
          templateId: state.uri.queryParameters['template'],
        ),
      ),
      GoRoute(
        path: '/templates',
        builder: (context, state) => const TemplatesScreen(),
      ),
      GoRoute(
        path: '/edit/:id',
        builder: (context, state) =>
            EditorHost(projectId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/upgrade',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('FrameLab Pro')),
          body: const PremiumScreen(),
        ),
      ),
      GoRoute(
        path: '/roadmap',
        builder: (context, state) => const RoadmapScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Back to home'),
        ),
      ),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});

class _AppShell extends StatelessWidget {
  const _AppShell({required this.shell});
  final StatefulNavigationShell shell;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell,
    bottomNavigationBar: NavigationBar(
      animationDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : null,
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (index) =>
          shell.goBranch(index, initialLocation: index == shell.currentIndex),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder_rounded),
          label: 'Projects',
        ),
        NavigationDestination(
          icon: Icon(Icons.auto_awesome_outlined),
          selectedIcon: Icon(Icons.auto_awesome_rounded),
          label: 'Pro',
        ),
      ],
    ),
  );
}

/// Register on the active branch's route. A PopScope around the shell is outside
/// its nested navigator and does not reliably intercept Android system back.
class _ReturnHomeOnBack extends StatelessWidget {
  const _ReturnHomeOnBack({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) context.go('/');
    },
    child: child,
  );
}
