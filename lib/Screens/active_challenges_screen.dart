import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/localization/app_text.dart';
import '../services/challenge_service.dart';


String _t(String key) => AppText.t(key);

class ActiveChallengesScreen extends StatefulWidget {
  const ActiveChallengesScreen({super.key});

  @override
  State<ActiveChallengesScreen> createState() =>
      _ActiveChallengesScreenState();
}

enum _ChallengeTab {
  active,
  history,
}

class _ActiveChallengesScreenState extends State<ActiveChallengesScreen> {
  static const Color _background = Color(0xFF00100A);
  static const Color _card = Color(0xFF061A12);
  static const Color _cardDark = Color(0xFF03140D);
  static const Color _mint = Color(0xFF45F0B2);
  static const Color _text = Color(0xFFF5F7F6);
  static const Color _muted = Color(0xFF91A49C);
  static const Color _border = Color(0xFF123A2C);
  static const Color _danger = Color(0xFFFF6577);
  static const Color _gold = Color(0xFFFFCB6B);

  final ChallengeService _challengeService = ChallengeService.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _loading = true;
  String? _error;

  _ChallengeTab _tab = _ChallengeTab.active;

  List<MunjaChallenge> _active = <MunjaChallenge>[];
  List<MunjaChallenge> _history = <MunjaChallenge>[];

  final Map<String, _RiderProfile> _profiles =
      <String, _RiderProfile>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      var active = await _challengeService.getActiveChallenges();

      // Move expired challenges into history automatically.
      for (final challenge in active) {
        if (challenge.endsAt != null &&
            !DateTime.now().isBefore(challenge.endsAt!)) {
          try {
            await _challengeService.completeExpiredChallenge(
              challengeId: challenge.id,
            );
          } catch (error) {
            debugPrint(
              'ACTIVE CHALLENGE EXPIRE ERROR '
              '${challenge.id}: $error',
            );
          }
        }
      }

      active = await _challengeService.getActiveChallenges();
      final history =
          await _challengeService.getCompletedChallenges();

      final riderUids = <String>{};

      for (final challenge in <MunjaChallenge>[
        ...active,
        ...history,
      ]) {
        riderUids
          ..add(challenge.creatorUid)
          ..add(challenge.opponentUid);
      }

      final loadedProfiles = <String, _RiderProfile>{};

      await Future.wait(
        riderUids.map((uid) async {
          try {
            final snapshot =
                await _db.collection('socialRiders').doc(uid).get();

            loadedProfiles[uid] = _RiderProfile.fromFirestore(
              uid: uid,
              data: snapshot.data(),
            );
          } catch (_) {
            loadedProfiles[uid] = _RiderProfile.fallback(uid);
          }
        }),
      );

      if (!mounted) return;

      setState(() {
        _active = active;
        _history = history;
        _profiles
          ..clear()
          ..addAll(loadedProfiles);
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('CHALLENGES LOAD ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String get _currentUid => _challengeService.currentUid ?? '';

  int get _wins => _history
      .where((challenge) => challenge.winnerUid == _currentUid)
      .length;

  int get _draws => _history
      .where((challenge) => challenge.winnerUid == null)
      .length;

  int get _losses =>
      (_history.length - _wins - _draws).clamp(0, 99999);

  double get _winRate {
    final decided = _wins + _losses;
    if (decided <= 0) return 0;
    return (_wins / decided) * 100;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: RefreshIndicator(
          color: _mint,
          backgroundColor: _card,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _buildHeader(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: _buildHero(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _buildTabs(),
                ),
              ),
              if (_tab == _ChallengeTab.history && !_loading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: _buildHistoryStats(),
                  ),
                ),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: _mint),
                  ),
                )
              else if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: _buildError(),
                  ),
                )
              else if (_visibleChallenges.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: _buildEmpty(),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final challenge = _visibleChallenges[index];

                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          index == 0 ? 20 : 12,
                          20,
                          0,
                        ),
                        child: _tab == _ChallengeTab.active
                            ? _buildActiveCard(challenge)
                            : _buildHistoryCard(challenge),
                      );
                    },
                    childCount: _visibleChallenges.length,
                  ),
                ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 330),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<MunjaChallenge> get _visibleChallenges =>
      _tab == _ChallengeTab.active ? _active : _history;

  Widget _buildHeader() {
    return Row(
      children: <Widget>[
        InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          borderRadius: BorderRadius.circular(30),
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: _text,
              size: 27,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('challengesTitle'),
                style: TextStyle(
                  color: _text,
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              SizedBox(height: 3),
              Text(
                _t('challengeTagline'),
                style: TextStyle(
                  color: _muted,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: _loading ? null : _load,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _card,
              shape: BoxShape.circle,
              border: Border.all(color: _border),
            ),
            child: const Icon(
              Icons.refresh_rounded,
              color: _mint,
              size: 21,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF071F16),
            Color(0xFF03140D),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: _mint.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: _mint.withValues(alpha: 0.055),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: _mint.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(19),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: _mint,
              size: 29,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MUNJA COMPETE',
                  style: TextStyle(
                    color: _mint,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.45,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _active.isEmpty
                      ? _t('readyNextRace')
                      : '${_active.length} ${_t('activeCaps').toLowerCase()} ${_t('challengesTitle').toLowerCase()}',
                  style: const TextStyle(
                    color: _text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _history.isEmpty
                      ? _t('completedAppearHistory')
                      : '${_history.length} ${_t('completed').toLowerCase()} · $_wins ${_t('wins').toLowerCase()}',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          _tabButton(
            tab: _ChallengeTab.active,
            label: _t('activeCaps'),
            count: _active.length,
            icon: Icons.bolt_rounded,
          ),
          const SizedBox(width: 5),
          _tabButton(
            tab: _ChallengeTab.history,
            label: _t('historyCaps'),
            count: _history.length,
            icon: Icons.history_rounded,
          ),
        ],
      ),
    );
  }

  Widget _tabButton({
    required _ChallengeTab tab,
    required String label,
    required int count,
    required IconData icon,
  }) {
    final selected = _tab == tab;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (_tab == tab) return;
            setState(() => _tab = tab);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: selected
                  ? _mint.withValues(alpha: 0.11)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? _mint.withValues(alpha: 0.22)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: selected ? _mint : _muted,
                ),
                const SizedBox(width: 6),
                Text(
                  '$label  $count',
                  style: TextStyle(
                    color: selected ? _text : _muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryStats() {
    return Row(
      children: [
        Expanded(
          child: _statTile(
            _t('wins'),
            '$_wins',
            _mint,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statTile(
            _t('losses'),
            '$_losses',
            _danger,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statTile(
            _t('draws'),
            '$_draws',
            _gold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statTile(
            _t('winRate'),
            '${_winRate.toStringAsFixed(0)}%',
            Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _statTile(
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              color: _muted,
              fontSize: 6.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveCard(MunjaChallenge challenge) {
    final myUid = _currentUid;
    final otherUid = challenge.otherUidFor(myUid);

    final me = _profileFor(myUid);
    final other = _profileFor(otherUid);

    final myProgress = challenge.progressFor(myUid);
    final otherProgress = challenge.progressFor(otherUid);

    final target = challenge.targetDistanceKm;
    final myRatio = _ratio(myProgress, target);
    final otherRatio = _ratio(otherProgress, target);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(27),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _mint.withValues(alpha: 0.04),
            blurRadius: 25,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusBadge(
                label: _t('activeCaps'),
                icon: Icons.bolt_rounded,
                color: _mint,
              ),
              const Spacer(),
              Icon(
                Icons.timer_outlined,
                color: _muted.withValues(alpha: 0.85),
                size: 16,
              ),
              const SizedBox(width: 5),
              Text(
                _daysLeftText(challenge),
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          Text(
            '${_distanceText(target)} KM RACE',
            style: const TextStyle(
              color: _text,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.35,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'First rider to ${_distanceText(target)} km wins.',
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          _versusHeader(me, other),
          const SizedBox(height: 20),
          _progressRow(
            name: _t('youCaps'),
            value: myProgress,
            target: target,
            ratio: myRatio,
            color: _mint,
          ),
          const SizedBox(height: 14),
          _progressRow(
            name: other.displayName,
            value: otherProgress,
            target: target,
            ratio: otherRatio,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: _background.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _border.withValues(alpha: 0.8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  myProgress >= otherProgress
                      ? Icons.trending_up_rounded
                      : Icons.flag_rounded,
                  color: _mint,
                  size: 18,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _leaderText(
                      myProgress: myProgress,
                      otherProgress: otherProgress,
                      otherName: other.displayName,
                    ),
                    style: const TextStyle(
                      color: _text,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(MunjaChallenge challenge) {
    final myUid = _currentUid;
    final otherUid = challenge.otherUidFor(myUid);
    final other = _profileFor(otherUid);

    final myProgress = challenge.progressFor(myUid);
    final otherProgress = challenge.progressFor(otherUid);

    final isDraw = challenge.winnerUid == null;
    final won = challenge.winnerUid == myUid;

    final color = isDraw
        ? _gold
        : won
            ? _mint
            : _danger;

    final label = isDraw
        ? _t('draw')
        : won
            ? _t('victory')
            : _t('defeat');

    final icon = isDraw
        ? Icons.horizontal_rule_rounded
        : won
            ? Icons.emoji_events_rounded
            : Icons.close_rounded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.07),
            _card,
          ],
        ),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: color.withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusBadge(
                label: label,
                icon: icon,
                color: color,
              ),
              const Spacer(),
              Text(
                _formatDate(
                  challenge.completedAt ??
                      challenge.updatedAt ??
                      challenge.startedAt,
                ),
                style: const TextStyle(
                  color: _muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            '${_distanceText(challenge.targetDistanceKm)} KM · VS ${other.displayName.toUpperCase()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _resultValue(
                  label: _t('youCaps'),
                  value: '${myProgress.toStringAsFixed(1)} km',
                  color: won ? _mint : _text,
                ),
              ),
              Container(
                width: 1,
                height: 32,
                color: _border,
              ),
              Expanded(
                child: _resultValue(
                  label: other.displayName.toUpperCase(),
                  value: '${otherProgress.toStringAsFixed(1)} km',
                  color: !isDraw && !won ? _danger : _text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Icon(
                challenge.completionReason == 'expired'
                    ? Icons.timer_off_outlined
                    : Icons.flag_rounded,
                color: _muted,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                challenge.completionReason == 'expired'
                    ? _t('timeExpired')
                    : _t('targetReached'),
                style: const TextStyle(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultValue({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _muted,
            fontSize: 7,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
          ),
        ),
      ],
    );
  }

  Widget _versusHeader(
    _RiderProfile me,
    _RiderProfile other,
  ) {
    return Row(
      children: [
        Expanded(
          child: _riderMini(
            me,
            label: _t('youCaps'),
            alignEnd: false,
          ),
        ),
        Container(
          width: 38,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _background.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _border),
          ),
          child: Text(
            'VS',
            style: TextStyle(
              color: _mint,
              fontSize: 8,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(
          child: _riderMini(
            other,
            label: other.displayName,
            alignEnd: true,
          ),
        ),
      ],
    );
  }

  Widget _riderMini(
    _RiderProfile rider, {
    required String label,
    required bool alignEnd,
  }) {
    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!alignEnd) _avatar(rider),
        if (!alignEnd) const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment:
                alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _text,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                rider.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (alignEnd) const SizedBox(width: 8),
        if (alignEnd) _avatar(rider),
      ],
    );
  }

  Widget _avatar(_RiderProfile rider) {
    final hasPhoto =
        rider.photoUrl != null && rider.photoUrl!.trim().isNotEmpty;

    return Container(
      width: 34,
      height: 34,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _mint.withValues(alpha: 0.09),
        shape: BoxShape.circle,
        border: Border.all(
          color: _mint.withValues(alpha: 0.20),
        ),
      ),
      child: hasPhoto
          ? Image.network(
              rider.photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _avatarFallback(rider),
            )
          : _avatarFallback(rider),
    );
  }

  Widget _avatarFallback(_RiderProfile rider) {
    final initial = rider.displayName.trim().isEmpty
        ? 'M'
        : rider.displayName.trim()[0].toUpperCase();

    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: _mint,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _progressRow({
    required String name,
    required double value,
    required double target,
    required double ratio,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _text,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '${value.toStringAsFixed(1)} / ${_distanceText(target)} km',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: ratio,
            backgroundColor: _background,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _statusBadge({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.75,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final history = _tab == _ChallengeTab.history;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 34,
      ),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Icon(
            history
                ? Icons.history_rounded
                : Icons.emoji_events_outlined,
            color: _mint,
            size: 34,
          ),
          const SizedBox(height: 12),
          Text(
            history
                ? _t('noHistory')
                : 'No active challenges',
            style: const TextStyle(
              color: _text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            history
                ? _t('historyAppear')
                : 'Accepted challenges will appear here.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _danger.withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: _danger,
            size: 30,
          ),
          const SizedBox(height: 10),
          Text(
            _error ?? _t('challengeLoadFailed'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(_t('tryAgainCaps')),
          ),
        ],
      ),
    );
  }

  _RiderProfile _profileFor(String uid) {
    return _profiles[uid] ?? _RiderProfile.fallback(uid);
  }

  static double _ratio(
    double value,
    double target,
  ) {
    if (target <= 0) return 0;
    return (value / target).clamp(0.0, 1.0);
  }

  static String _distanceText(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  String _daysLeftText(MunjaChallenge challenge) {
    final end = challenge.endsAt;
    if (end == null) {
      return '${challenge.durationDays} days';
    }

    final difference = end.difference(DateTime.now());

    if (difference.isNegative) {
      return _t('ending');
    }

    final days = difference.inDays;
    if (days <= 0) {
      final hours = difference.inHours.clamp(0, 23);
      return '${hours <= 0 ? 1 : hours}h left';
    }

    return '$days ${days == 1 ? _t('homeDaysLeftSingular') : _t('homeDaysLeftPlural')}';
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '';

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  static String _leaderText({
    required double myProgress,
    required double otherProgress,
    required String otherName,
  }) {
    final difference = (myProgress - otherProgress).abs();

    if (difference < 0.01) {
      return _t('evenNow');
    }

    if (myProgress > otherProgress) {
      return 'You lead by ${difference.toStringAsFixed(1)} km.';
    }

    return '$otherName leads by ${difference.toStringAsFixed(1)} km.';
  }
}

class _RiderProfile {
  _RiderProfile({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String username;
  final String? photoUrl;

  factory _RiderProfile.fromFirestore({
    required String uid,
    required Map<String, dynamic>? data,
  }) {
    final map = data ?? <String, dynamic>{};

    final displayName = _readString(
      map['displayName'] ?? map['name'],
      fallback: 'Munja Rider',
    );

    var username = _readString(
      map['username'],
      fallback: '',
    );

    if (username.isEmpty) {
      username =
          '@${displayName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '')}';
    } else if (!username.startsWith('@')) {
      username = '@$username';
    }

    final photoUrl = _readNullableString(
      map['photoUrl'] ?? map['photoURL'],
    );

    return _RiderProfile(
      uid: uid,
      displayName: displayName,
      username: username,
      photoUrl: photoUrl,
    );
  }

  factory _RiderProfile.fallback(String uid) {
    final short = uid.length <= 6 ? uid : uid.substring(0, 6);

    return _RiderProfile(
      uid: uid,
      displayName: 'Munja Rider',
      username: '@rider_$short',
      photoUrl: null,
    );
  }

  static String _readString(
    Object? value, {
    required String fallback,
  }) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  static String? _readNullableString(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }
}
