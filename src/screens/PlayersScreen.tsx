import { useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { usePlayerDirectory } from '../hooks/usePlayerDirectory';
import { colors, radius } from '../theme';
import type {
  AppScreen,
  LeagueSummary,
  PlayerDirectoryItem,
} from '../types';

type OwnershipFilter = 'all' | 'free' | 'mine';

type Props = {
  initialPlayerId: string | null;
  league: LeagueSummary | null;
  onCloseInitialPlayer: () => void;
  onNavigate: (screen: AppScreen) => void;
};

export function PlayersScreen({
  initialPlayerId,
  league,
  onCloseInitialPlayer,
  onNavigate,
}: Props) {
  const directory = usePlayerDirectory(league);
  const [search, setSearch] = useState('');
  const [role, setRole] = useState('TUTTI');
  const [ownership, setOwnership] = useState<OwnershipFilter>('all');
  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);
  const activePlayerId = initialPlayerId ?? selectedPlayerId;
  const selected =
    directory.players.find((player) => player.id === activePlayerId) ?? null;

  const roles = useMemo(() => {
    const available = new Set<string>();
    directory.players.forEach((player) =>
      player.role.split('/').forEach((code) => available.add(code)),
    );
    const preferred = ['P', 'D', 'C', 'A'];
    return [
      'TUTTI',
      ...preferred.filter((code) => available.has(code)),
      ...[...available]
        .filter((code) => !preferred.includes(code) && code !== '—')
        .sort(),
    ];
  }, [directory.players]);

  const filteredPlayers = useMemo(() => {
    const query = search.trim().toLowerCase();
    return directory.players
      .filter((player) => {
        const matchesSearch =
          !query ||
          player.name.toLowerCase().includes(query) ||
          player.clubName.toLowerCase().includes(query) ||
          player.role.toLowerCase().includes(query);
        const matchesRole =
          role === 'TUTTI' || player.role.split('/').includes(role);
        const matchesOwnership =
          ownership === 'all' ||
          (ownership === 'free' && !player.teamId) ||
          (ownership === 'mine' && player.teamId === league?.team?.id);
        return matchesSearch && matchesRole && matchesOwnership;
      })
      .sort((first, second) => {
        const firstScore = first.averageFantasyScore ?? -1;
        const secondScore = second.averageFantasyScore ?? -1;
        return secondScore - firstScore || first.name.localeCompare(second.name);
      });
  }, [directory.players, league?.team?.id, ownership, role, search]);

  if (!league) {
    return (
      <View style={styles.centerRoot}>
        <Text style={styles.centerTitle}>Prima scegli una lega.</Text>
        <Pressable
          onPress={() => onNavigate('home')}
          style={styles.primaryButton}
        >
          <Text style={styles.primaryButtonText}>TORNA ALLA HOME</Text>
        </Pressable>
      </View>
    );
  }

  if (selected) {
    return (
      <PlayerDetail
        league={league}
        onBack={() => {
          if (initialPlayerId) {
            onCloseInitialPlayer();
            return;
          }
          setSelectedPlayerId(null);
        }}
        player={selected}
      />
    );
  }

  const freeAgents = directory.players.filter((player) => !player.teamId).length;
  const withRatings = directory.players.filter(
    (player) => player.averageRating !== null,
  ).length;

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      keyboardShouldPersistTaps="handled"
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.header}>
        <Pressable
          onPress={() => onNavigate('league')}
          style={styles.backButton}
        >
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>DATABASE DELLA LEGA</Text>
          <Text style={styles.title}>Calciatori</Text>
        </View>
        <Pressable
          accessibilityLabel="Aggiorna calciatori"
          disabled={directory.loading}
          onPress={() => void directory.refresh()}
          style={styles.reloadButton}
        >
          <Text style={styles.reloadText}>↻</Text>
        </Pressable>
      </View>

      <View style={styles.heroCard}>
        <View>
          <Text style={styles.heroEyebrow}>ARCHIVIO</Text>
          <Text style={styles.heroValue}>{directory.players.length}</Text>
          <Text style={styles.heroLabel}>CALCIATORI ATTIVI</Text>
        </View>
        <View style={styles.heroStats}>
          <HeroStat label="SVINCOLATI" value={String(freeAgents)} />
          <HeroStat label="CON VOTO" value={String(withRatings)} />
        </View>
      </View>

      <TextInput
        autoCapitalize="none"
        onChangeText={setSearch}
        placeholder="Cerca calciatore, club o ruolo"
        placeholderTextColor={colors.muted}
        style={styles.searchInput}
        value={search}
      />

      <ScrollView
        contentContainerStyle={styles.filterRow}
        horizontal
        showsHorizontalScrollIndicator={false}
      >
        {roles.map((code) => (
          <FilterChip
            active={role === code}
            key={code}
            label={code}
            onPress={() => setRole(code)}
          />
        ))}
      </ScrollView>

      <View style={styles.ownershipTabs}>
        <OwnershipTab
          active={ownership === 'all'}
          label="TUTTI"
          onPress={() => setOwnership('all')}
        />
        <OwnershipTab
          active={ownership === 'free'}
          label="LIBERI"
          onPress={() => setOwnership('free')}
        />
        <OwnershipTab
          active={ownership === 'mine'}
          label="MIA ROSA"
          onPress={() => setOwnership('mine')}
        />
      </View>

      <View style={styles.sectionHeader}>
        <Text style={styles.sectionTitle}>Risultati</Text>
        <Text style={styles.sectionMeta}>{filteredPlayers.length} TROVATI</Text>
      </View>

      {directory.loading ? (
        <View style={styles.stateCard}>
          <ActivityIndicator color={colors.navy} />
          <Text style={styles.stateBody}>Sfoglio i taccuini degli scout…</Text>
        </View>
      ) : directory.error ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>Archivio indisponibile</Text>
          <Text style={styles.errorBody}>{directory.error}</Text>
        </View>
      ) : filteredPlayers.length === 0 ? (
        <View style={styles.stateCard}>
          <Text style={styles.stateTitle}>Nessun nome sul taccuino</Text>
          <Text style={styles.stateBody}>
            Cambia ricerca o filtri. Anche gli osservatori sbagliano campo.
          </Text>
        </View>
      ) : (
        <View style={styles.playerList}>
          {filteredPlayers.slice(0, 100).map((player, index) => (
            <PlayerRow
              key={player.id}
              onPress={() => setSelectedPlayerId(player.id)}
              player={player}
              rank={index + 1}
            />
          ))}
        </View>
      )}
    </ScrollView>
  );
}

function PlayerRow({
  player,
  rank,
  onPress,
}: {
  player: PlayerDirectoryItem;
  rank: number;
  onPress: () => void;
}) {
  const trend = playerTrend(player);
  return (
    <Pressable onPress={onPress} style={styles.playerRow}>
      <Text style={styles.playerRank}>{rank}</Text>
      <View style={styles.roleBadge}>
        <Text style={styles.roleText}>{player.role}</Text>
      </View>
      <View style={styles.playerCopy}>
        <Text numberOfLines={1} style={styles.playerName}>
          {player.name}
        </Text>
        <Text numberOfLines={1} style={styles.playerMeta}>
          {player.clubName} · {player.teamName ?? 'SVINCOLATO'}
        </Text>
      </View>
      <View style={styles.scoreCopy}>
        <Text style={styles.scoreValue}>
          {formatScore(player.averageFantasyScore)}
        </Text>
        <Text
          style={[
            styles.trendText,
            trend === 'up' && styles.trendUp,
            trend === 'down' && styles.trendDown,
          ]}
        >
          {trend === 'up' ? '↑ FORMA' : trend === 'down' ? '↓ FORMA' : 'STABILE'}
        </Text>
      </View>
      <Text style={styles.playerArrow}>›</Text>
    </Pressable>
  );
}

function PlayerDetail({
  player,
  league,
  onBack,
}: {
  player: PlayerDirectoryItem;
  league: LeagueSummary;
  onBack: () => void;
}) {
  const trend = playerTrend(player);
  const ownedByMe = player.teamId === league.team?.id;

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.detailContent}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.header}>
        <Pressable onPress={onBack} style={styles.backButton}>
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>SCHEDA CALCIATORE</Text>
          <Text numberOfLines={1} style={styles.detailHeaderTitle}>
            {player.name}
          </Text>
        </View>
      </View>

      <View style={styles.playerHero}>
        <View style={styles.playerHeroTop}>
          <View style={styles.heroRoleBadge}>
            <Text style={styles.heroRoleText}>{player.role}</Text>
          </View>
          <View
            style={[
              styles.formPill,
              trend === 'down' && styles.formPillDown,
            ]}
          >
            <Text style={styles.formPillText}>
              {trend === 'up'
                ? 'FORMA IN CRESCITA'
                : trend === 'down'
                  ? 'FORMA IN CALO'
                  : 'FORMA STABILE'}
            </Text>
          </View>
        </View>
        <Text style={styles.playerHeroName}>{player.name}</Text>
        <Text style={styles.playerHeroClub}>
          {player.clubName}
          {player.shirtNumber ? ` · #${player.shirtNumber}` : ''}
        </Text>
        <View style={styles.ownershipCard}>
          <View>
            <Text style={styles.ownershipLabel}>
              {player.teamName ? 'SQUADRA FANTASY' : 'STATO'}
            </Text>
            <Text style={styles.ownershipName}>
              {ownedByMe ? 'La tua rosa' : player.teamName ?? 'Svincolato'}
            </Text>
          </View>
          <Text style={styles.ownershipPrice}>
            {player.purchasePrice !== null
              ? `${player.purchasePrice} CR`
              : 'LIBERO'}
          </Text>
        </View>
      </View>

      <Text style={styles.detailSectionTitle}>Rendimento</Text>
      <View style={styles.metricsGrid}>
        <MetricCard
          featured
          label="FANTAMEDIA"
          value={formatScore(player.averageFantasyScore)}
        />
        <MetricCard
          label="VOTO BASE"
          value={formatScore(player.averageRating)}
        />
        <MetricCard label="PRESENZE" value={String(player.appearances)} />
        <MetricCard
          label="BONUS"
          value={String(player.goals * 3 + player.assists)}
        />
      </View>

      <Text style={styles.detailSectionTitle}>Ultime prestazioni</Text>
      <View style={styles.formCard}>
        {player.lastScores.length > 0 ? (
          player.lastScores.map((score, index) => (
            <View
              key={`${player.id}-${index}`}
              style={[
                styles.formScore,
                score >= 7 && styles.formScoreHigh,
                score < 6 && styles.formScoreLow,
              ]}
            >
              <Text style={styles.formScoreValue}>{formatScore(score)}</Text>
              <Text style={styles.formScoreLabel}>G-{index + 1}</Text>
            </View>
          ))
        ) : (
          <Text style={styles.noFormText}>
            Nessun voto disponibile. Lo scout aspetta il debutto.
          </Text>
        )}
      </View>

      <Text style={styles.detailSectionTitle}>Bonus e disciplina</Text>
      <View style={styles.statsCard}>
        <DetailStat label="GOL" value={player.goals} />
        <DetailStat label="ASSIST" value={player.assists} />
        <DetailStat label="GIALLI" value={player.yellowCards} />
        <DetailStat label="ROSSI" value={player.redCards} />
      </View>

      <View style={styles.premiumInsight}>
        <View style={styles.premiumPill}>
          <Text style={styles.premiumPillText}>PREMIUM · IN ARRIVO</Text>
        </View>
        <Text style={styles.premiumTitle}>Analisi avanzata</Text>
        <Text style={styles.premiumBody}>
          Andamento stagionale, confronti ruolo per ruolo e affidabilità
          titolare diventeranno il cuore statistico di LEGHEVO Premium.
        </Text>
      </View>
    </ScrollView>
  );
}

function HeroStat({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.heroStat}>
      <Text style={styles.heroStatValue}>{value}</Text>
      <Text style={styles.heroStatLabel}>{label}</Text>
    </View>
  );
}

function FilterChip({
  active,
  label,
  onPress,
}: {
  active: boolean;
  label: string;
  onPress: () => void;
}) {
  return (
    <Pressable
      onPress={onPress}
      style={[styles.filterChip, active && styles.filterChipActive]}
    >
      <Text
        style={[styles.filterChipText, active && styles.filterChipTextActive]}
      >
        {label}
      </Text>
    </Pressable>
  );
}

function OwnershipTab({
  active,
  label,
  onPress,
}: {
  active: boolean;
  label: string;
  onPress: () => void;
}) {
  return (
    <Pressable
      onPress={onPress}
      style={[styles.ownershipTab, active && styles.ownershipTabActive]}
    >
      <Text
        style={[
          styles.ownershipTabText,
          active && styles.ownershipTabTextActive,
        ]}
      >
        {label}
      </Text>
    </Pressable>
  );
}

function MetricCard({
  label,
  value,
  featured,
}: {
  label: string;
  value: string;
  featured?: boolean;
}) {
  return (
    <View style={[styles.metricCard, featured && styles.metricCardFeatured]}>
      <Text
        style={[styles.metricValue, featured && styles.metricValueFeatured]}
      >
        {value}
      </Text>
      <Text
        style={[styles.metricLabel, featured && styles.metricLabelFeatured]}
      >
        {label}
      </Text>
    </View>
  );
}

function DetailStat({ label, value }: { label: string; value: number }) {
  return (
    <View style={styles.detailStat}>
      <Text style={styles.detailStatValue}>{value}</Text>
      <Text style={styles.detailStatLabel}>{label}</Text>
    </View>
  );
}

function playerTrend(player: PlayerDirectoryItem) {
  if (player.lastScores.length < 2) {
    return 'stable';
  }
  const current = player.lastScores[0];
  const previous = player.lastScores[1];
  if (current >= previous + 0.5) {
    return 'up';
  }
  if (current <= previous - 0.5) {
    return 'down';
  }
  return 'stable';
}

function formatScore(value: number | null) {
  if (value === null || !Number.isFinite(value)) {
    return '—';
  }
  return value.toFixed(2).replace(/0$/, '').replace('.', ',');
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    padding: 20,
    paddingBottom: 42,
  },
  detailContent: {
    padding: 20,
    paddingBottom: 46,
  },
  centerRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 25,
    backgroundColor: colors.canvas,
  },
  centerTitle: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
    marginBottom: 18,
  },
  primaryButton: {
    height: 50,
    paddingHorizontal: 22,
    borderRadius: 25,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 22,
  },
  backButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  backText: {
    color: colors.navy,
    fontSize: 32,
    lineHeight: 34,
  },
  headerCopy: {
    flex: 1,
    marginLeft: 14,
  },
  eyebrow: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.55,
  },
  title: {
    color: colors.navy,
    fontSize: 28,
    fontWeight: '900',
    marginTop: 3,
  },
  detailHeaderTitle: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
    marginTop: 3,
  },
  reloadButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  reloadText: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '800',
  },
  heroCard: {
    minHeight: 150,
    borderRadius: radius.xl,
    padding: 22,
    flexDirection: 'row',
    justifyContent: 'space-between',
    backgroundColor: colors.navy,
  },
  heroEyebrow: {
    color: colors.mutedLight,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  heroValue: {
    color: colors.lime,
    fontSize: 46,
    fontWeight: '900',
    lineHeight: 52,
    marginTop: 3,
  },
  heroLabel: {
    color: colors.warmWhite,
    fontSize: 9,
    fontWeight: '900',
  },
  heroStats: {
    minWidth: 105,
    justifyContent: 'center',
    gap: 16,
    paddingLeft: 20,
    borderLeftWidth: 1,
    borderLeftColor: colors.navyLine,
  },
  heroStat: {
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    gap: 14,
  },
  heroStatValue: {
    color: colors.warmWhite,
    fontSize: 20,
    fontWeight: '900',
  },
  heroStatLabel: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '800',
  },
  searchInput: {
    height: 54,
    borderRadius: radius.md,
    paddingHorizontal: 17,
    marginTop: 14,
    color: colors.navy,
    fontSize: 14,
    fontWeight: '700',
    backgroundColor: colors.white,
    borderWidth: 1,
    borderColor: '#E2E7DF',
  },
  filterRow: {
    gap: 8,
    paddingVertical: 12,
  },
  filterChip: {
    minWidth: 42,
    height: 36,
    paddingHorizontal: 13,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  filterChipActive: {
    backgroundColor: colors.navy,
  },
  filterChipText: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '900',
  },
  filterChipTextActive: {
    color: colors.lime,
  },
  ownershipTabs: {
    height: 46,
    borderRadius: 23,
    padding: 4,
    flexDirection: 'row',
    backgroundColor: colors.canvasMuted,
  },
  ownershipTab: {
    flex: 1,
    borderRadius: 19,
    alignItems: 'center',
    justifyContent: 'center',
  },
  ownershipTabActive: {
    backgroundColor: colors.white,
  },
  ownershipTabText: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
  },
  ownershipTabTextActive: {
    color: colors.navy,
  },
  sectionHeader: {
    minHeight: 56,
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    paddingBottom: 12,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
  },
  sectionMeta: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
  },
  playerList: {
    borderRadius: radius.lg,
    padding: 7,
    backgroundColor: colors.white,
  },
  playerRow: {
    minHeight: 76,
    borderRadius: 17,
    paddingHorizontal: 9,
    flexDirection: 'row',
    alignItems: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#E2E7DF',
  },
  playerRank: {
    width: 22,
    color: colors.muted,
    fontSize: 10,
    fontWeight: '900',
    textAlign: 'center',
  },
  roleBadge: {
    width: 39,
    height: 39,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  roleText: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
  },
  playerCopy: {
    flex: 1,
    marginLeft: 11,
  },
  playerName: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  playerMeta: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '700',
    marginTop: 4,
  },
  scoreCopy: {
    alignItems: 'flex-end',
    marginLeft: 6,
  },
  scoreValue: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  trendText: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 3,
  },
  trendUp: {
    color: '#5B8F16',
  },
  trendDown: {
    color: colors.danger,
  },
  playerArrow: {
    color: colors.muted,
    fontSize: 22,
    marginLeft: 5,
  },
  stateCard: {
    minHeight: 190,
    borderRadius: radius.xl,
    padding: 24,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  stateTitle: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  stateBody: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 19,
    textAlign: 'center',
    marginTop: 8,
  },
  errorCard: {
    minHeight: 170,
    borderRadius: radius.xl,
    padding: 24,
    justifyContent: 'center',
    backgroundColor: '#FFF0EF',
  },
  errorTitle: {
    color: colors.danger,
    fontSize: 17,
    fontWeight: '900',
  },
  errorBody: {
    color: colors.navy,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 8,
  },
  playerHero: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.navy,
  },
  playerHeroTop: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  heroRoleBadge: {
    minWidth: 44,
    height: 44,
    borderRadius: 15,
    paddingHorizontal: 10,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  heroRoleText: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  formPill: {
    height: 28,
    borderRadius: 14,
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  formPillDown: {
    backgroundColor: '#FFC9C5',
  },
  formPillText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  playerHeroName: {
    color: colors.warmWhite,
    fontSize: 28,
    fontWeight: '900',
    marginTop: 24,
  },
  playerHeroClub: {
    color: colors.mutedLight,
    fontSize: 13,
    fontWeight: '700',
    marginTop: 6,
  },
  ownershipCard: {
    minHeight: 70,
    borderRadius: radius.md,
    paddingHorizontal: 16,
    marginTop: 22,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.navySoft,
  },
  ownershipLabel: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
  },
  ownershipName: {
    color: colors.warmWhite,
    fontSize: 14,
    fontWeight: '900',
    marginTop: 4,
  },
  ownershipPrice: {
    color: colors.lime,
    fontSize: 15,
    fontWeight: '900',
  },
  detailSectionTitle: {
    color: colors.navy,
    fontSize: 19,
    fontWeight: '900',
    marginTop: 24,
    marginBottom: 12,
  },
  metricsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'space-between',
    rowGap: 10,
  },
  metricCard: {
    width: '48.5%',
    minHeight: 100,
    borderRadius: radius.lg,
    padding: 17,
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  metricCardFeatured: {
    backgroundColor: colors.lime,
  },
  metricValue: {
    color: colors.navy,
    fontSize: 27,
    fontWeight: '900',
  },
  metricValueFeatured: {
    color: colors.navy,
  },
  metricLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
    marginTop: 7,
  },
  metricLabelFeatured: {
    color: colors.navy,
  },
  formCard: {
    minHeight: 88,
    borderRadius: radius.lg,
    padding: 14,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.white,
  },
  formScore: {
    width: 49,
    height: 58,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  formScoreHigh: {
    backgroundColor: colors.limeSoft,
  },
  formScoreLow: {
    backgroundColor: '#FFE4E1',
  },
  formScoreValue: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  formScoreLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 4,
  },
  noFormText: {
    flex: 1,
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    textAlign: 'center',
  },
  statsCard: {
    minHeight: 92,
    borderRadius: radius.lg,
    padding: 16,
    flexDirection: 'row',
    backgroundColor: colors.white,
  },
  detailStat: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    borderRightWidth: StyleSheet.hairlineWidth,
    borderRightColor: '#DEE4DC',
  },
  detailStatValue: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
  },
  detailStatLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 5,
  },
  premiumInsight: {
    borderRadius: radius.xl,
    padding: 22,
    marginTop: 22,
    backgroundColor: colors.navy,
  },
  premiumPill: {
    alignSelf: 'flex-start',
    height: 27,
    borderRadius: 14,
    paddingHorizontal: 12,
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  premiumPillText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  premiumTitle: {
    color: colors.warmWhite,
    fontSize: 20,
    fontWeight: '900',
    marginTop: 17,
  },
  premiumBody: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 7,
  },
});
