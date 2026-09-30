class DevelopmentPhase {
  const DevelopmentPhase(
    this.number,
    this.title,
    this.description,
    this.features,
  );
  final int number;
  final String title;
  final String description;
  final List<String> features;
}

const developmentPhases = [
  DevelopmentPhase(
    1,
    'Architecture + home',
    'The foundation of your creative space.',
    [
      'Guest-first launch and offline home',
      'Clean architecture and centralized entitlements',
      'Responsive dark design and navigation',
    ],
  ),
  DevelopmentPhase(2, 'Photo editor', 'Make every image your own.', [
    'Crop, rotate and resize',
    'Brightness, contrast, saturation and exposure',
    'Filters and blur',
    'Text, stickers and shapes',
    'Social presets and HD export',
    'Background replacement',
  ]),
  DevelopmentPhase(3, 'Video editor', 'Turn moments into a story.', [
    'Timeline, trim, split and merge',
    'Crop, resize and speed control',
    'Mute, volume and music',
    'Text, filters and overlays',
    '720p and 1080p export',
    'Extensible 4K export architecture',
  ]),
  DevelopmentPhase(
    4,
    'Transitions + effects',
    'Give your edits a little movement.',
    [
      'Transitions between clips',
      'Basic effects',
      'Free and Premium effect collections',
    ],
  ),
  DevelopmentPhase(5, 'Templates', 'A starting point for every idea.', [
    'Instagram posts, Stories and Reels',
    'YouTube thumbnails and product ads',
    'Festival and business posters',
    'Editable text, images, colors and layout',
    'Limited free library and full Pro library',
  ]),
  DevelopmentPhase(
    6,
    'Background remover',
    'Keep the subject. Change the scene.',
    [
      'On-device, open-source model',
      'Premium background removal',
      'Subject cutout and background replacement',
      'No media uploads or paid AI APIs',
    ],
  ),
  DevelopmentPhase(7, 'Project save + load', 'Pick up where you left off.', [
    'Local versioned project documents',
    'Autosave and recovery',
    'Offline media references and thumbnails',
    'Storage and permission error recovery',
  ]),
  DevelopmentPhase(
    8,
    'Premium + mock entitlement',
    'One place for every Pro benefit.',
    [
      '₹39/month and ₹299/year plans',
      'Signup and verification only at purchase',
      'Clearly labelled local test entitlement',
      'Replaceable Google Play Billing gateway',
      'Higher-quality export, more fonts and stickers',
      'Future 4K and premium on-device tools',
      'Optional future Supabase account adapter',
    ],
  ),
  DevelopmentPhase(9, 'Ads architecture', 'Keep free editing accessible.', [
    'Replaceable ad provider and no-op offline adapter',
    'No ads for Premium',
    'Consent, failure handling and editor-safe placements',
  ]),
  DevelopmentPhase(
    10,
    'Production optimization',
    'Built for Android, with release checks to complete.',
    [
      'Bounded image memory and background processing',
      'Cancellation, low-storage and lifecycle recovery',
      'Accessibility checks and device test checklist',
      'Bundled licenses and release setup guide',
    ],
  ),
];
