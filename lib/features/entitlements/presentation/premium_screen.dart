import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/widgets/page_content.dart';
import '../data/local_mock_entitlement_repository.dart';
import '../data/local_premium_verification_service.dart';
import '../domain/entitlement.dart';
import '../domain/purchase_gateway.dart';

class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _action(Future<PurchaseOutcome> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await operation();
      if (mounted) setState(() => _message = result.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy(
    LocalMockEntitlementRepository repository,
    PremiumPlan plan,
  ) async {
    if (_busy) return;
    final result = await showDialog<PurchaseOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MockCheckoutDialog(repository: repository, plan: plan),
    );
    if (mounted && result != null) setState(() => _message = result.message);
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(entitlementRepositoryProvider);
    final mock = repository is LocalMockEntitlementRepository
        ? repository
        : null;
    final entitlement =
        ref.watch(entitlementProvider).asData?.value ?? repository.current;
    final pro = entitlement.isProAt(DateTime.now());
    final canTest = mock?.enabled ?? false;
    final theme = Theme.of(context);
    return PageContent(
      children: [
        Text('Make room for more.', style: theme.textTheme.headlineLarge),
        const SizedBox(height: 12),
        Text(
          pro
              ? 'Local test Pro is active'
              : 'You’re on Free. No account needed.',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 20),
        const InfoPanel(
          title: 'Local test mode · no charges',
          body:
              'Google Play Billing is not connected. Prices below are planned prices. '
              'Test purchases stay on this device and never renew automatically. '
              'You can keep editing on Free without signing up.',
          icon: Icons.science_outlined,
        ),
        if (mock?.initializationWarning case final String warning) ...[
          const SizedBox(height: 12),
          Text(warning),
        ],
        if (_message != null) ...[
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(_message!)),
        ],
        if (pro) ...[
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your test subscription',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Access ends ${_date(entitlement.expiresAt!)}. No automatic renewal.',
                  ),
                  if (mock?.isCancelled ?? false)
                    const Text(
                      'Cancelled locally. Access remains until expiry.',
                    ),
                  const SizedBox(height: 12),
                  if (mock != null && !mock.isCancelled)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _action(mock.cancelSubscription),
                      child: const Text('Cancel test subscription'),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        for (final plan in PremiumPlan.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      plan.interval == PlanInterval.year
                          ? 'Yearly Pro'
                          : 'Monthly Pro',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      plan.priceLabel,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      plan.interval == PlanInterval.year
                          ? '₹169 less than 12 monthly payments at the planned price'
                          : 'Planned monthly price',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: canTest && !pro && !_busy
                          ? () => _buy(mock!, plan)
                          : null,
                      child: Text(
                        'Buy ${plan.interval == PlanInterval.year ? 'yearly' : 'monthly'} Pro · test only',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No charges. Local simulated email verification follows.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (!canTest)
          const Text(
            'Test purchases are disabled in this build. Free editing remains available.',
          ),
        const SizedBox(height: 12),
        Text('Included with Pro', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        for (final benefit in const [
          'No ads',
          'All templates and Premium filters, effects and transitions',
          'On-device background removal',
          'Higher-quality export',
          'More fonts and stickers',
          'Future: 4K export and Premium on-device tools',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('• $benefit'),
          ),
        if (canTest) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : () => _action(mock!.restoreLastPurchase),
            child: const Text('Restore local test purchase'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _action(mock!.reset),
            child: const Text('Reset local test Pro to Free'),
          ),
          const Text(
            'Restore works only on this device. Reset permanently removes the local test receipt.',
          ),
        ],
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(
            semanticsLabel: 'Updating test subscription',
          ),
        ],
      ],
    );
  }

  static String _date(DateTime date) {
    final local = date.toLocal();
    return '${local.day}/${local.month}/${local.year} at '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _MockCheckoutDialog extends StatefulWidget {
  const _MockCheckoutDialog({required this.repository, required this.plan});
  final LocalMockEntitlementRepository repository;
  final PremiumPlan plan;
  @override
  State<_MockCheckoutDialog> createState() => _MockCheckoutDialogState();
}

class _MockCheckoutDialogState extends State<_MockCheckoutDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _verification = LocalPremiumVerificationService();
  LocalVerificationChallenge? _challenge;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _verification.cancel();
    super.dispose();
  }

  void _generate() {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _challenge = _verification.begin(_email.text);
      _error = null;
      _code.clear();
    });
  }

  Future<void> _activate() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = _verification.verify(_code.text);
      final result = await widget.repository.purchase(widget.plan, account);
      if (!mounted) return;
      if (result.status == PurchaseStatus.completed) {
        Navigator.of(context).pop(result);
        return;
      } else {
        setState(() {
          _error = result.message;
          _challenge = null;
        });
      }
    } on LocalVerificationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final challenge = _challenge;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Try Pro on this device'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${widget.plan.priceLabel} planned · no charges',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This is simulated verification. No email is sent and email ownership '
                    'is not verified. Your address and test receipt stay locally on this device.',
                  ),
                  const SizedBox(height: 20),
                  if (challenge == null)
                    TextFormField(
                      controller: _email,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email for local test',
                        hintText: 'you@example.com',
                      ),
                      validator: (value) =>
                          LocalPremiumVerificationService.isValidEmail(
                            value ?? '',
                          )
                          ? null
                          : 'Enter a valid email address.',
                      onFieldSubmitted: (_) => _generate(),
                    )
                  else ...[
                    Text('Test address: ${challenge.email}'),
                    const SizedBox(height: 12),
                    SelectableText(
                      'Local test code: ${challenge.displayCode}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter this displayed code below. It expires in 5 minutes.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _code,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: const InputDecoration(
                        labelText: '6-digit local test code',
                      ),
                      validator: (value) =>
                          RegExp(r'^\d{6}$').hasMatch(value ?? '')
                          ? null
                          : 'Enter the 6-digit test code.',
                      onFieldSubmitted: (_) => _activate(),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _challenge = null;
                              _error = null;
                              _verification.cancel();
                            }),
                      child: const Text('Change email or generate a new code'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(
                      semanticsLabel: 'Activating local test Pro',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Keep Free'),
          ),
          FilledButton(
            onPressed: _busy
                ? null
                : (challenge == null ? _generate : _activate),
            child: Text(
              challenge == null
                  ? 'Generate test code'
                  : 'Activate test Pro · no charges',
            ),
          ),
        ],
      ),
    );
  }
}
