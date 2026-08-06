import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, radius } from '../theme';
import type { LeagueMode, RosterPlayer } from '../types';

type Props = {
  formation: string;
  mode: LeagueMode;
  players: RosterPlayer[];
  onRemovePlayer: (player: RosterPlayer) => void;
};

type PitchLayer = {
  key: string;
  label: string;
  count: number;
  players: Array<RosterPlayer | null>;
};

export function FormationPitch({
  formation,
  mode,
  players,
  onRemovePlayer,
}: Props) {
  const layers = buildPitchLayers(formation, mode, players);

  return (
    <View style={styles.card}>
      <View style={styles.cardHeader}>
        <View>
          <Text style={styles.cardEyebrow}>LAVAGNA TATTICA</Text>
          <Text style={styles.cardFormation}>{formation}</Text>
        </View>
        <View style={styles.cardCount}>
          <Text style={styles.cardCountValue}>{players.length}/11</Text>
          <Text style={styles.cardCountLabel}>TITOLARI</Text>
        </View>
      </View>

      <View style={styles.pitch}>
        <PitchMarkings />
        <View style={styles.layers}>
          {layers.map((layer) => (
            <View key={layer.key} style={styles.layer}>
              {layer.players.map((player, index) => (
                <View
                  key={player?.id ?? `${layer.key}-${index}`}
                  style={styles.slot}
                >
                  <Pressable
                    accessibilityHint={
                      player ? 'Tocca per togliere il calciatore' : undefined
                    }
                    accessibilityLabel={
                      player
                        ? `${player.name}, ${player.role}`
                        : `Posizione ${layer.label} libera`
                    }
                    disabled={!player}
                    onPress={() => {
                      if (player) {
                        onRemovePlayer(player);
                      }
                    }}
                    style={[
                      styles.marker,
                      !player && styles.markerEmpty,
                      layer.key === 'goalkeeper' && styles.markerGoalkeeper,
                    ]}
                  >
                    <Text
                      numberOfLines={1}
                      style={[
                        styles.markerRole,
                        !player && styles.markerRoleEmpty,
                      ]}
                    >
                      {player ? compactRole(player.role) : layer.label}
                    </Text>
                  </Pressable>
                  <View
                    style={[
                      styles.namePlate,
                      !player && styles.namePlateEmpty,
                    ]}
                  >
                    <Text
                      adjustsFontSizeToFit
                      minimumFontScale={0.72}
                      numberOfLines={1}
                      style={[
                        styles.playerName,
                        !player && styles.playerNameEmpty,
                      ]}
                    >
                      {player ? shortPlayerName(player.name) : 'LIBERO'}
                    </Text>
                  </View>
                </View>
              ))}
            </View>
          ))}
        </View>
      </View>

      <Text style={styles.hint}>
        Tocca un calciatore sul campo per toglierlo dai titolari.
      </Text>
    </View>
  );
}

function PitchMarkings() {
  return (
    <View pointerEvents="none" style={StyleSheet.absoluteFill}>
      <View style={styles.touchline} />
      <View style={styles.halfwayLine} />
      <View style={styles.centerCircle} />
      <View style={styles.centerSpot} />
      <View style={[styles.penaltyArea, styles.penaltyAreaTop]} />
      <View style={[styles.goalArea, styles.goalAreaTop]} />
      <View style={[styles.penaltyArea, styles.penaltyAreaBottom]} />
      <View style={[styles.goalArea, styles.goalAreaBottom]} />
    </View>
  );
}

function buildPitchLayers(
  formation: string,
  mode: LeagueMode,
  selectedPlayers: RosterPlayer[],
): PitchLayer[] {
  const counts = formation
    .split('-')
    .map(Number)
    .filter((value) => Number.isFinite(value) && value > 0);
  const goalkeeper =
    selectedPlayers.find((player) => isGoalkeeper(player.role)) ?? null;
  const outfield = selectedPlayers.filter((player) => player.id !== goalkeeper?.id);

  if (mode === 'classic') {
    const [defenders = 0, midfielders = 0, attackers = 0] = counts;
    const byRole = {
      D: outfield.filter((player) => player.role === 'D'),
      C: outfield.filter((player) => player.role === 'C'),
      A: outfield.filter((player) => player.role === 'A'),
    };

    return [
      makeLayer('attack', 'A', attackers, byRole.A),
      makeLayer('midfield', 'C', midfielders, byRole.C),
      makeLayer('defence', 'D', defenders, byRole.D),
      makeLayer('goalkeeper', 'P', 1, goalkeeper ? [goalkeeper] : []),
    ];
  }

  const layerDefinitions =
    counts.length === 4
      ? [
          { key: 'attack', label: 'A', count: counts[3] ?? 0 },
          { key: 'attacking-midfield', label: 'T', count: counts[2] ?? 0 },
          { key: 'midfield', label: 'C', count: counts[1] ?? 0 },
          { key: 'defence', label: 'D', count: counts[0] ?? 0 },
        ]
      : [
          { key: 'attack', label: 'A', count: counts[2] ?? 0 },
          { key: 'midfield', label: 'C', count: counts[1] ?? 0 },
          { key: 'defence', label: 'D', count: counts[0] ?? 0 },
        ];

  const remaining = [...outfield];
  const assigned = layerDefinitions.map((definition) => {
    const preferred = takePreferredPlayers(
      remaining,
      definition.count,
      definition.key,
    );
    return makeLayer(
      definition.key,
      definition.label,
      definition.count,
      preferred,
    );
  });

  return [
    ...assigned,
    makeLayer('goalkeeper', 'P', 1, goalkeeper ? [goalkeeper] : []),
  ];
}

function takePreferredPlayers(
  remaining: RosterPlayer[],
  count: number,
  layerKey: string,
) {
  const picked: RosterPlayer[] = [];
  const preferred = remaining.filter((player) =>
    fitsMantraLayer(player.role, layerKey),
  );

  for (const player of preferred) {
    if (picked.length === count) {
      break;
    }
    picked.push(player);
    remaining.splice(
      remaining.findIndex((item) => item.id === player.id),
      1,
    );
  }

  while (picked.length < count && remaining.length > 0) {
    picked.push(remaining.shift() as RosterPlayer);
  }

  return picked;
}

function fitsMantraLayer(role: string, layerKey: string) {
  const codes = role
    .split('/')
    .map((code) => code.trim().toUpperCase())
    .filter(Boolean);

  if (layerKey === 'defence') {
    return codes.some((code) => ['D', 'DC', 'DD', 'DS'].includes(code));
  }
  if (layerKey === 'midfield') {
    return codes.some((code) => ['C', 'M', 'E'].includes(code));
  }
  if (layerKey === 'attacking-midfield') {
    return codes.some((code) => ['T', 'W'].includes(code));
  }
  return codes.some((code) => ['A', 'PC'].includes(code));
}

function makeLayer(
  key: string,
  label: string,
  count: number,
  players: RosterPlayer[],
): PitchLayer {
  return {
    key,
    label,
    count,
    players: Array.from(
      { length: count },
      (_, index) => players[index] ?? null,
    ),
  };
}

function isGoalkeeper(role: string) {
  const normalized = role.trim().toUpperCase();
  return normalized === 'P' || normalized.includes('POR');
}

function compactRole(role: string) {
  const firstRole = role.split('/')[0]?.trim() || '—';
  return firstRole.length > 3 ? firstRole.slice(0, 3).toUpperCase() : firstRole;
}

function shortPlayerName(name: string) {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length < 2) {
    return name.toUpperCase();
  }
  const surname = parts.slice(1).join(' ');
  return `${parts[0]?.charAt(0)}. ${surname}`.toUpperCase();
}

const lineColor = 'rgba(255, 255, 255, 0.68)';

const styles = StyleSheet.create({
  card: {
    borderRadius: radius.xl,
    padding: 13,
    backgroundColor: colors.navy,
    marginTop: 14,
  },
  cardHeader: {
    minHeight: 58,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 5,
  },
  cardEyebrow: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  cardFormation: {
    color: colors.lime,
    fontSize: 25,
    fontWeight: '900',
    marginTop: 2,
  },
  cardCount: {
    alignItems: 'flex-end',
  },
  cardCountValue: {
    color: colors.warmWhite,
    fontSize: 16,
    fontWeight: '900',
  },
  cardCountLabel: {
    color: colors.mutedLight,
    fontSize: 7,
    fontWeight: '900',
    letterSpacing: 0.5,
    marginTop: 2,
  },
  pitch: {
    width: '100%',
    aspectRatio: 0.7,
    borderRadius: radius.lg,
    overflow: 'hidden',
    backgroundColor: '#237849',
  },
  touchline: {
    position: 'absolute',
    top: 10,
    right: 10,
    bottom: 10,
    left: 10,
    borderWidth: 1.2,
    borderColor: lineColor,
  },
  halfwayLine: {
    position: 'absolute',
    top: '50%',
    right: 10,
    left: 10,
    height: 1.2,
    backgroundColor: lineColor,
  },
  centerCircle: {
    position: 'absolute',
    top: '50%',
    left: '50%',
    width: 78,
    height: 78,
    borderRadius: 39,
    borderWidth: 1.2,
    borderColor: lineColor,
    marginTop: -39,
    marginLeft: -39,
  },
  centerSpot: {
    position: 'absolute',
    top: '50%',
    left: '50%',
    width: 4,
    height: 4,
    borderRadius: 2,
    backgroundColor: lineColor,
    marginTop: -2,
    marginLeft: -2,
  },
  penaltyArea: {
    position: 'absolute',
    left: '22%',
    width: '56%',
    height: '16%',
    borderWidth: 1.2,
    borderColor: lineColor,
  },
  penaltyAreaTop: {
    top: 10,
    borderTopWidth: 0,
  },
  penaltyAreaBottom: {
    bottom: 10,
    borderBottomWidth: 0,
  },
  goalArea: {
    position: 'absolute',
    left: '36%',
    width: '28%',
    height: '7%',
    borderWidth: 1.2,
    borderColor: lineColor,
  },
  goalAreaTop: {
    top: 10,
    borderTopWidth: 0,
  },
  goalAreaBottom: {
    bottom: 10,
    borderBottomWidth: 0,
  },
  layers: {
    flex: 1,
    justifyContent: 'space-around',
    paddingTop: 19,
    paddingBottom: 16,
  },
  layer: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-evenly',
  },
  slot: {
    width: 58,
    alignItems: 'center',
  },
  marker: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: colors.lime,
    backgroundColor: colors.navy,
  },
  markerEmpty: {
    borderColor: 'rgba(255, 255, 255, 0.55)',
    borderStyle: 'dashed',
    backgroundColor: 'rgba(7, 20, 38, 0.24)',
  },
  markerGoalkeeper: {
    borderColor: '#FFE169',
  },
  markerRole: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
  },
  markerRoleEmpty: {
    color: colors.warmWhite,
  },
  namePlate: {
    maxWidth: 58,
    minWidth: 45,
    minHeight: 17,
    borderRadius: 7,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 3,
    backgroundColor: 'rgba(7, 20, 38, 0.88)',
    marginTop: 3,
  },
  namePlateEmpty: {
    backgroundColor: 'rgba(7, 20, 38, 0.32)',
  },
  playerName: {
    width: 52,
    color: colors.warmWhite,
    fontSize: 6.5,
    fontWeight: '900',
    textAlign: 'center',
  },
  playerNameEmpty: {
    color: 'rgba(255, 255, 255, 0.58)',
  },
  hint: {
    color: colors.mutedLight,
    fontSize: 8,
    lineHeight: 13,
    textAlign: 'center',
    marginTop: 10,
  },
});
