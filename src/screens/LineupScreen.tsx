import { useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  LayoutAnimation,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { FormationPitch } from '../components/FormationPitch';
import { useLineup } from '../hooks/useLineup';
import { useTeamRoster } from '../hooks/useTeamRoster';
import { colors, radius } from '../theme';
import type { AppScreen, LeagueSummary, RosterPlayer } from '../types';

const classicFormations = [
  '3-4-3',
  '3-5-2',
  '4-3-3',
  '4-4-2',
  '4-5-1',
  '5-3-2',
  '5-4-1',
];

const mantraFormations = [
  '3-4-1-2',
  '3-4-2-1',
  '3-5-2',
  '4-3-1-2',
  '4-3-2-1',
  '4-4-1-1',
  '4-4-2',
];

type Props = {
  league: LeagueSummary | null;
  onNavigate: (screen: AppScreen) => void;
};

export function LineupScreen({ league, onNavigate }: Props) {
  const isDemo = Boolean(league?.isDemo);
  const roster = useTeamRoster(
    league?.team?.id ?? null,
    league?.mode ?? 'classic',
    isDemo,
  );
  const lineup = useLineup(
    league?.id ?? null,
    league?.team?.id ?? null,
    isDemo,
  );
  const formations =
    league?.mode === 'mantra' ? mantraFormations : classicFormations;
  const [formation, setFormation] = useState(
    league?.mode === 'mantra' ? '3-4-1-2' : '4-3-3',
  );
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [benchIds, setBenchIds] = useState<string[]>([]);
  const [feedback, setFeedback] = useState('');
  const [success, setSuccess] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const hydratedKey = useRef('');
  const isPreview = !lineup.loading && !lineup.context;

  useEffect(() => {
    if (roster.loading || lineup.loading) {
      return;
    }

    const rosterKey = roster.players.map((player) => player.id).join(',');
    const nextHydratedKey = [
      lineup.context?.matchday.id ?? 'preview',
      lineup.context?.submittedAt ?? 'draft',
      lineup.context?.lineupOrigin ?? 'empty',
      lineup.context?.sourceMatchdayNumber ?? 'none',
      lineup.context?.revision ?? 0,
      rosterKey,
    ].join(':');

    if (hydratedKey.current === nextHydratedKey) {
      return;
    }

    const validRosterIds = new Set(
      roster.players.map((player) => player.id),
    );
    const nextStarters = (lineup.context?.starterIds ?? []).filter((id) =>
      validRosterIds.has(id),
    );
    const starterSet = new Set(nextStarters);
    const savedBench = (lineup.context?.benchIds ?? []).filter(
      (id) => validRosterIds.has(id) && !starterSet.has(id),
    );
    const savedBenchSet = new Set(savedBench);
    const missingBench = roster.players
      .map((player) => player.id)
      .filter(
        (id) => !starterSet.has(id) && !savedBenchSet.has(id),
      );

    if (lineup.context?.formation) {
      setFormation(lineup.context.formation);
    }
    setSelectedIds(nextStarters);
    setBenchIds([...savedBench, ...missingBench]);
    hydratedKey.current = nextHydratedKey;
  }, [
    lineup.context?.benchIds,
    lineup.context?.formation,
    lineup.context?.lineupOrigin,
    lineup.context?.matchday.id,
    lineup.context?.revision,
    lineup.context?.sourceMatchdayNumber,
    lineup.context?.starterIds,
    lineup.context?.submittedAt,
    lineup.loading,
    roster.loading,
    roster.players,
  ]);

  const selectedPlayers = useMemo(
    () =>
      selectedIds
        .map((id) => roster.players.find((player) => player.id === id))
        .filter((player): player is RosterPlayer => Boolean(player)),
    [roster.players, selectedIds],
  );

  if (!league) {
    return (
      <View style={styles.centerRoot}>
        <Text style={styles.centerTitle}>Prima scegli una lega.</Text>
        <Pressable
          onPress={() => onNavigate('home')}
          style={styles.submitButton}
        >
          <Text style={styles.submitButtonText}>TORNA ALLA HOME</Text>
        </Pressable>
      </View>
    );
  }

  const changeFormation = (next: string) => {
    LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
    setFormation(next);
    if (league.mode === 'classic') {
      const nextQuota = classicQuota(next);
      const compatibleIds = (['P', 'D', 'C', 'A'] as const).flatMap((role) =>
        selectedPlayers
          .filter((player) => player.role === role)
          .slice(0, nextQuota[role])
          .map((player) => player.id),
      );
      const removed = selectedIds.length - compatibleIds.length;
      setSelectedIds(compatibleIds);
      setBenchIds((current) =>
        orderBench(
          roster.players.map((player) => player.id),
          compatibleIds,
          current,
        ),
      );
      setFeedback(
        removed > 0
          ? `Modulo ${next}: ho mantenuto i titolari compatibili. Completa gli spazi liberi.`
          : `Modulo ${next}: la lavagna si è aggiornata.`,
      );
    } else {
      const compatiblePlayers = selectedPlayers.reduce<RosterPlayer[]>(
        (kept, player) =>
          canAssignSelectedMantra([...kept, player], next)
            ? [...kept, player]
            : kept,
        [],
      );
      const compatibleIds = compatiblePlayers.map((player) => player.id);
      const removed = selectedIds.length - compatibleIds.length;
      setSelectedIds(compatibleIds);
      setBenchIds((current) =>
        orderBench(
          roster.players.map((player) => player.id),
          compatibleIds,
          current,
        ),
      );
      setFeedback(
        removed > 0
          ? `Modulo ${next}: ho rimesso in panchina i calciatori senza uno slot compatibile.`
          : `Modulo ${next}: la lavagna si è aggiornata.`,
      );
    }
    setSuccess(false);
  };

  const togglePlayer = (player: RosterPlayer) => {
    setSuccess(false);
    setFeedback('');

    if (selectedIds.includes(player.id)) {
      setSelectedIds((current) => current.filter((id) => id !== player.id));
      setBenchIds((current) => [
        player.id,
        ...current.filter((id) => id !== player.id),
      ]);
      return;
    }
    if (selectedIds.length >= 11) {
      setFeedback('Gli imbucati restano fuori: i titolari devono essere 11.');
      return;
    }

    if (league.mode === 'classic') {
      const quota = classicQuota(formation);
      const role = player.role as 'P' | 'D' | 'C' | 'A';
      const selectedInRole = selectedPlayers.filter(
        (selected) => selected.role === role,
      ).length;
      if (!quota[role] || selectedInRole >= quota[role]) {
        setFeedback(
          `Nel ${formation} hai già completato il reparto ${role}.`,
        );
        return;
      }
    } else if (
      !canAssignSelectedMantra([...selectedPlayers, player], formation)
    ) {
      setFeedback(
        `Nel ${formation} ${player.name} non trova uno slot libero compatibile.`,
      );
      return;
    }

    setSelectedIds((current) => [...current, player.id]);
    setBenchIds((current) => current.filter((id) => id !== player.id));
  };

  const autoSelect = () => {
    if (roster.players.length < 11) {
      const message = 'Servono almeno 11 calciatori in rosa.';
      setFeedback(message);
      Alert.alert('Formazione automatica non disponibile', message);
      return;
    }

    if (league.mode === 'classic') {
      const quota = classicQuota(formation);
      const next = (['P', 'D', 'C', 'A'] as const).flatMap((role) =>
        roster.players
          .filter((player) => player.role === role)
          .slice(0, quota[role])
          .map((player) => player.id),
      );
      if (next.length !== 11) {
        const message =
          'La rosa non ha abbastanza calciatori nei ruoli richiesti da questo modulo.';
        setFeedback(message);
        Alert.alert('Formazione automatica non disponibile', message);
        return;
      }
      setSelectedIds(next);
      setBenchIds((current) =>
        orderBench(
          roster.players.map((player) => player.id),
          next,
          current,
        ),
      );
      setFeedback(
        'Formazione automatica pronta. Ora puoi metterci del tuo.',
      );
    } else {
      const next = autoSelectMantra(roster.players, formation);
      if (next.length !== 11) {
        const message =
          'La rosa non ha abbastanza calciatori compatibili con questo modulo.';
        setFeedback(message);
        Alert.alert('Formazione automatica non disponibile', message);
        return;
      }
      setSelectedIds(next);
      setBenchIds((current) =>
        orderBench(
          roster.players.map((player) => player.id),
          next,
          current,
        ),
      );
      setFeedback('Formazione automatica pronta. Il coraggio resta manuale.');
    }
  };

  const moveBench = (athleteId: string, direction: -1 | 1) => {
    setBenchIds((current) => {
      const index = current.indexOf(athleteId);
      const nextIndex = index + direction;
      if (index < 0 || nextIndex < 0 || nextIndex >= current.length) {
        return current;
      }
      const next = [...current];
      [next[index], next[nextIndex]] = [next[nextIndex], next[index]];
      return next;
    });
    setSuccess(false);
    setFeedback('Ordine della panchina aggiornato.');
  };

  const submit = async () => {
    if (!lineup.context) {
      setFeedback('Prima deve essere disponibile una giornata di calendario.');
      return;
    }
    if (!lineup.context.canSubmit) {
      setFeedback('Tempo scaduto: la distinta è già bloccata.');
      return;
    }
    if (selectedIds.length !== 11) {
      setFeedback('Devi scegliere esattamente 11 titolari.');
      return;
    }

    setSubmitting(true);
    setSuccess(false);
    setFeedback('');
    const outcome = await lineup.submit({
      formation,
      starterIds: selectedIds,
      benchIds,
    });
    setSubmitting(false);

    if (outcome.error) {
      setFeedback(outcome.error);
    } else {
      setSuccess(true);
      setFeedback('Formazione consegnata. Adesso puoi dare la colpa al mister.');
    }
  };

  const loading = roster.loading || lineup.loading;

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.header}>
        <Pressable onPress={() => onNavigate('league')} style={styles.backButton}>
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>
            {isPreview
              ? 'ANTEPRIMA TATTICA'
              : lineup.context?.lineupOrigin === 'previous_preview'
                ? 'ULTIMA DISTINTA PRONTA'
                : 'DISTINTA UFFICIALE'}
          </Text>
          <Text style={styles.title}>Formazione</Text>
        </View>
        <View style={styles.selectedBadge}>
          <Text style={styles.selectedNumber}>{selectedIds.length}</Text>
          <Text style={styles.selectedLabel}>SU 11</Text>
        </View>
      </View>

      {loading ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.lime} size="large" />
          <Text style={styles.loadingText}>Disegno le righe del campo…</Text>
        </View>
      ) : roster.error || lineup.error ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>Distinta non disponibile</Text>
          <Text style={styles.errorBody}>{roster.error || lineup.error}</Text>
        </View>
      ) : (
        <>
          {lineup.context ? (
            <>
              <View style={styles.matchCard}>
                <Text style={styles.matchEyebrow}>
                  GIORNATA {lineup.context.matchday.number}
                </Text>
                <View style={styles.matchRow}>
                  <Text style={styles.matchTeam}>
                    {lineup.context.home
                      ? league.team?.name
                      : lineup.context.opponentName}
                  </Text>
                  <Text style={styles.matchVs}>VS</Text>
                  <Text style={[styles.matchTeam, styles.matchTeamAway]}>
                    {lineup.context.home
                      ? lineup.context.opponentName
                      : league.team?.name}
                  </Text>
                </View>
                <Text style={styles.lockText}>
                  CONSEGNA ENTRO{' '}
                  {formatDeadline(lineup.context.matchday.locksAt)}
                </Text>
              </View>
              {lineup.context.submissionPolicy === 'guarded_v1' ? (
                <View
                  style={[
                    styles.protectionCard,
                    !lineup.context.integrityReady &&
                      styles.protectionCardWarning,
                  ]}
                >
                  <View style={styles.protectionHeader}>
                    <Text style={styles.protectionLabel}>
                      {lineup.context.integrityReady
                        ? 'CONSEGNA PROTETTA'
                        : 'DISTINTA DA VERIFICARE'}
                    </Text>
                    <Text style={styles.protectionRevision}>
                      R{lineup.context.revision}
                    </Text>
                  </View>
                  <Text style={styles.protectionTitle}>
                    {lineup.context.directWritesBlocked
                      ? 'Salvataggio atomico e sincronizzato'
                      : 'Protezione database non completa'}
                  </Text>
                  <Text style={styles.protectionBody}>
                    Ogni modifica usa una revisione progressiva: un altro
                    dispositivo non può sovrascrivere una distinta più recente.
                  </Text>
                </View>
              ) : null}
              {lineup.context.deadlinePolicy === 'guarded_v1' ? (
                <View
                  style={[
                    styles.protectionCard,
                    (lineup.context.deadlineOutcome === 'processing' ||
                      lineup.context.deadlineOutcome === 'missing') &&
                      styles.protectionCardWarning,
                  ]}
                >
                  <View style={styles.protectionHeader}>
                    <Text style={styles.protectionLabel}>
                      {lineup.context.deadlineCertified
                        ? 'SCADENZA CERTIFICATA'
                        : lineup.context.deadlineOutcome === 'processing'
                          ? 'BLOCCO IN ELABORAZIONE'
                          : 'SCADENZA PROTETTA'}
                    </Text>
                    <Text style={styles.protectionRevision}>
                      L{lineup.context.matchdayLineupLockRevision}
                    </Text>
                  </View>
                  <Text style={styles.protectionTitle}>
                    {lineup.context.deadlineOutcome === 'manager'
                      ? 'Distinta congelata come consegnata'
                      : lineup.context.deadlineOutcome === 'carried'
                        ? 'Distinta precedente confermata automaticamente'
                        : lineup.context.deadlineOutcome === 'missing'
                          ? 'Nessuna distinta valida disponibile'
                          : lineup.context.deadlineOutcome === 'processing'
                            ? 'LEGHEVO sta certificando le formazioni'
                            : 'Blocco automatico al primo calcio d’inizio'}
                  </Text>
                  <Text style={styles.protectionBody}>
                    {lineup.context.deadlineCertified
                      ? 'Titolari, panchina e ordine delle riserve sono ormai immutabili e verificati dal database.'
                      : 'Alla scadenza ogni squadra viene classificata come consegnata, recuperata o mancante, senza modifiche tardive.'}
                  </Text>
                </View>
              ) : null}
              {lineup.context.willAutoCarry ? (
                <View style={styles.continuityCard}>
                  <Text style={styles.continuityLabel}>FORMAZIONE PROTETTA</Text>
                  <Text style={styles.continuityTitle}>
                    Distinta della giornata{' '}
                    {lineup.context.sourceMatchdayNumber} già pronta
                  </Text>
                  <Text style={styles.continuityBody}>
                    Puoi modificarla e consegnarla. Se non fai nulla, LEGHEVO
                    la confermerà automaticamente alla scadenza.
                  </Text>
                </View>
              ) : lineup.context.firstSubmissionRequired ? (
                <View
                  style={[
                    styles.continuityCard,
                    styles.continuityCardWarning,
                  ]}
                >
                  <Text
                    style={[
                      styles.continuityLabel,
                      styles.continuityLabelWarning,
                    ]}
                  >
                    PRIMA CONSEGNA NECESSARIA
                  </Text>
                  <Text style={styles.continuityTitle}>
                    Non esiste ancora una formazione precedente
                  </Text>
                  <Text style={styles.continuityBody}>
                    Consegna almeno una distinta valida. Senza una formazione,
                    questa giornata sarà calcolata con 0 fantapunti.
                  </Text>
                </View>
              ) : lineup.context.lineupOrigin === 'manager' ? (
                <View style={styles.savedCard}>
                  <Text style={styles.savedText}>
                    DISTINTA CONSEGNATA DAL MANAGER
                  </Text>
                </View>
              ) : null}
            </>
          ) : (
            <View style={styles.previewCard}>
              <View style={styles.previewBadge}>
                <Text style={styles.previewBadgeText}>ANTEPRIMA</Text>
              </View>
              <Text style={styles.previewTitle}>Prova la lavagna tattica</Text>
              <Text style={styles.previewBody}>
                Cambia modulo e disponi i calciatori già acquistati. Questa
                prova resta sul telefono e non viene consegnata finché non
                esiste una giornata di calendario.
              </Text>
            </View>
          )}

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Modulo</Text>
            <Pressable
              accessibilityHint="Seleziona automaticamente undici titolari compatibili con il modulo"
              accessibilityRole="button"
              onPress={autoSelect}
            >
              <Text style={styles.autoText}>FORMAZIONE AUTO</Text>
            </Pressable>
          </View>
          <ScrollView
            horizontal
            contentContainerStyle={styles.formationsRow}
            showsHorizontalScrollIndicator={false}
          >
            {formations.map((item) => (
              <Pressable
                key={item}
                onPress={() => changeFormation(item)}
                style={[
                  styles.formationButton,
                  formation === item && styles.formationButtonActive,
                ]}
              >
                <Text
                  style={[
                    styles.formationText,
                    formation === item && styles.formationTextActive,
                  ]}
                >
                  {item}
                </Text>
              </Pressable>
            ))}
          </ScrollView>

          <FormationPitch
            formation={formation}
            mode={league.mode}
            onRemovePlayer={togglePlayer}
            players={selectedPlayers}
          />

          <Text style={styles.sectionTitle}>Scegli i titolari</Text>
          <View style={styles.playersCard}>
            {roster.players.map((player) => {
              const selected = selectedIds.includes(player.id);
              return (
                <Pressable
                  key={player.id}
                  onPress={() => togglePlayer(player)}
                  style={[
                    styles.playerRow,
                    selected && styles.playerRowSelected,
                  ]}
                >
                  <View
                    style={[
                      styles.checkBox,
                      selected && styles.checkBoxSelected,
                    ]}
                  >
                    <Text
                      style={[
                        styles.checkText,
                        selected && styles.checkTextSelected,
                      ]}
                    >
                      {selected ? '✓' : player.role}
                    </Text>
                  </View>
                  <View style={styles.playerCopy}>
                    <Text style={styles.playerName}>{player.name}</Text>
                    <Text style={styles.playerClub}>{player.clubName}</Text>
                  </View>
                  <Text style={styles.playerPrice}>
                    {selected
                      ? 'IN CAMPO'
                      : `PANCHINA ${Math.max(
                          benchIds.indexOf(player.id) + 1,
                          1,
                        )}`}
                  </Text>
                </Pressable>
              );
            })}
          </View>

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Ordine panchina</Text>
            <Text style={styles.benchCount}>{benchIds.length} RISERVE</Text>
          </View>
          <View style={styles.playersCard}>
            {benchIds.length > 0 ? (
              benchIds.map((athleteId, index) => {
                const player = roster.players.find(
                  (item) => item.id === athleteId,
                );
                if (!player) {
                  return null;
                }

                return (
                  <View key={athleteId} style={styles.benchRow}>
                    <View style={styles.benchPosition}>
                      <Text style={styles.benchPositionText}>{index + 1}</Text>
                    </View>
                    <View style={styles.playerCopy}>
                      <Text style={styles.playerName}>{player.name}</Text>
                      <Text style={styles.playerClub}>
                        {player.role} · {player.clubName}
                      </Text>
                    </View>
                    <Pressable
                      accessibilityLabel={`Sposta ${player.name} verso l'alto`}
                      disabled={index === 0}
                      onPress={() => moveBench(athleteId, -1)}
                      style={[
                        styles.orderButton,
                        index === 0 && styles.orderButtonDisabled,
                      ]}
                    >
                      <Text style={styles.orderButtonText}>↑</Text>
                    </Pressable>
                    <Pressable
                      accessibilityLabel={`Sposta ${player.name} verso il basso`}
                      disabled={index === benchIds.length - 1}
                      onPress={() => moveBench(athleteId, 1)}
                      style={[
                        styles.orderButton,
                        index === benchIds.length - 1 &&
                          styles.orderButtonDisabled,
                      ]}
                    >
                      <Text style={styles.orderButtonText}>↓</Text>
                    </Pressable>
                  </View>
                );
              })
            ) : (
              <Text style={styles.emptyBenchText}>
                I calciatori non titolari compariranno qui.
              </Text>
            )}
          </View>

          {feedback ? (
            <View
              style={[
                styles.feedbackCard,
                success && styles.feedbackCardSuccess,
              ]}
            >
              <Text
                style={[
                  styles.feedbackText,
                  success && styles.feedbackTextSuccess,
                ]}
              >
                {feedback}
              </Text>
            </View>
          ) : null}

          <Pressable
            accessibilityState={{
              disabled:
                isPreview ||
                submitting ||
                selectedIds.length !== 11 ||
                lineup.context?.canSubmit === false,
            }}
            disabled={
              isPreview ||
              submitting ||
              selectedIds.length !== 11 ||
              lineup.context?.canSubmit === false ||
              selectedIds.length + benchIds.length !== roster.players.length
            }
            onPress={() => void submit()}
            style={[
              styles.submitButton,
              (isPreview ||
                submitting ||
                selectedIds.length !== 11 ||
                lineup.context?.canSubmit === false ||
                selectedIds.length + benchIds.length !==
                  roster.players.length) &&
                styles.submitButtonDisabled,
            ]}
          >
            <Text style={styles.submitButtonText}>
              {isPreview
                ? 'CONSEGNA DISPONIBILE CON IL CALENDARIO'
                : submitting
                ? 'CONSEGNA IN CORSO…'
                : lineup.context?.canSubmit === false
                  ? 'FORMAZIONE BLOCCATA'
                  : lineup.context?.submittedAt
                    ? 'AGGIORNA FORMAZIONE'
                    : 'CONSEGNA FORMAZIONE'}
            </Text>
          </Pressable>
        </>
      )}
    </ScrollView>
  );
}

function orderBench(
  rosterIds: string[],
  starterIds: string[],
  currentBenchIds: string[],
) {
  const starters = new Set(starterIds);
  const available = new Set(
    rosterIds.filter((id) => !starters.has(id)),
  );
  const kept = currentBenchIds.filter((id) => available.delete(id));
  return [...kept, ...rosterIds.filter((id) => available.has(id))];
}

function autoSelectMantra(
  players: RosterPlayer[],
  formation: string,
) {
  const slots = mantraSlots(formation);
  const findLineup = (
    slotIndex: number,
    usedIds: Set<string>,
  ): string[] | null => {
    if (slotIndex === slots.length) {
      return [];
    }

    const candidates = players
      .filter(
        (player) =>
          !usedIds.has(player.id) &&
          mantraRoleFits(player.role, slots[slotIndex]),
      )
      .sort(
        (left, right) =>
          mantraCompatibleSlotCount(left.role, slots) -
          mantraCompatibleSlotCount(right.role, slots),
      );

    for (const player of candidates) {
      const nextUsed = new Set(usedIds);
      nextUsed.add(player.id);
      const rest = findLineup(slotIndex + 1, nextUsed);
      if (rest) {
        return [player.id, ...rest];
      }
    }

    return null;
  };

  return findLineup(0, new Set()) ?? [];
}

function canAssignSelectedMantra(
  players: RosterPlayer[],
  formation: string,
) {
  const slots = mantraSlots(formation);
  const orderedPlayers = [...players].sort(
    (left, right) =>
      mantraCompatibleSlotCount(left.role, slots) -
      mantraCompatibleSlotCount(right.role, slots),
  );

  const placePlayer = (
    playerIndex: number,
    usedSlotIndexes: Set<number>,
  ): boolean => {
    if (playerIndex === orderedPlayers.length) {
      return true;
    }

    return slots.some((slot, slotIndex) => {
      if (
        usedSlotIndexes.has(slotIndex) ||
        !mantraRoleFits(orderedPlayers[playerIndex].role, slot)
      ) {
        return false;
      }

      const nextUsed = new Set(usedSlotIndexes);
      nextUsed.add(slotIndex);
      return placePlayer(playerIndex + 1, nextUsed);
    });
  };

  return players.length <= slots.length && placePlayer(0, new Set());
}

function mantraSlots(formation: string) {
  const counts = formation.split('-').map(Number);
  return counts.length === 4
    ? [
        'POR',
        ...Array.from({ length: counts[0] ?? 0 }, () => 'DEF'),
        ...Array.from({ length: counts[1] ?? 0 }, () => 'MID'),
        ...Array.from({ length: counts[2] ?? 0 }, () => 'TRE'),
        ...Array.from({ length: counts[3] ?? 0 }, () => 'ATT'),
      ]
    : [
        'POR',
        ...Array.from({ length: counts[0] ?? 0 }, () => 'DEF'),
        ...Array.from({ length: counts[1] ?? 0 }, () => 'MID'),
        ...Array.from({ length: counts[2] ?? 0 }, () => 'ATT'),
      ];
}

function mantraCompatibleSlotCount(role: string, slots: string[]) {
  return slots.filter((slot) => mantraRoleFits(role, slot)).length;
}

function mantraRoleFits(role: string, slot: string) {
  const roles = role.split('/').map((item) => item.trim());
  if (slot === 'POR') return roles.includes('Por');
  if (slot === 'DEF') {
    return roles.some((item) => ['Dc', 'Dd', 'Ds'].includes(item));
  }
  if (slot === 'MID') {
    return roles.some((item) => ['E', 'M', 'C'].includes(item));
  }
  if (slot === 'TRE') {
    return roles.some((item) => ['W', 'T'].includes(item));
  }
  return roles.some((item) => ['A', 'Pc'].includes(item));
}

function classicQuota(formation: string) {
  const [defenders, midfielders, attackers] = formation
    .split('-')
    .map(Number);
  return {
    P: 1,
    D: defenders ?? 0,
    C: midfielders ?? 0,
    A: attackers ?? 0,
  };
}

function formatDeadline(value: string) {
  return new Intl.DateTimeFormat('it-IT', {
    weekday: 'short',
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
    .format(new Date(value))
    .toUpperCase();
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
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 20,
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
  },
  title: {
    color: colors.navy,
    fontSize: 25,
    fontWeight: '900',
    marginTop: 4,
  },
  selectedBadge: {
    width: 50,
    height: 50,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  selectedNumber: {
    color: colors.lime,
    fontSize: 17,
    fontWeight: '900',
  },
  selectedLabel: {
    color: colors.mutedLight,
    fontSize: 7,
    fontWeight: '900',
  },
  loadingCard: {
    minHeight: 280,
    borderRadius: radius.xl,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  loadingText: {
    color: colors.mutedLight,
    fontSize: 12,
    marginTop: 12,
  },
  errorCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.navy,
  },
  errorTitle: {
    color: colors.warmWhite,
    fontSize: 18,
    fontWeight: '900',
  },
  errorBody: {
    color: colors.mutedLight,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 7,
  },
  protectionCard: {
    borderRadius: radius.lg,
    padding: 16,
    marginTop: 12,
    backgroundColor: colors.white,
    borderWidth: 1,
    borderColor: colors.lime,
  },
  protectionCardWarning: {
    borderColor: '#F0A64A',
  },
  protectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  protectionLabel: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.8,
  },
  protectionRevision: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  protectionTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
    marginTop: 8,
  },
  protectionBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 5,
  },
  previewCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.navy,
  },
  previewBadge: {
    alignSelf: 'flex-start',
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 6,
    backgroundColor: colors.lime,
  },
  previewBadgeText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.6,
  },
  previewTitle: {
    color: colors.warmWhite,
    fontSize: 18,
    fontWeight: '900',
    marginTop: 16,
  },
  previewBody: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 8,
  },
  continuityCard: {
    borderWidth: 1,
    borderColor: colors.lime,
    borderRadius: radius.lg,
    padding: 18,
    backgroundColor: colors.limeSoft,
    marginTop: 12,
  },
  continuityCardWarning: {
    borderColor: '#F1B1AC',
    backgroundColor: '#FFE9E8',
  },
  continuityLabel: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  continuityLabelWarning: {
    color: '#A3312D',
  },
  continuityTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
    lineHeight: 20,
    marginTop: 7,
  },
  continuityBody: {
    color: colors.navySoft,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 6,
  },
  savedCard: {
    alignItems: 'center',
    borderRadius: radius.md,
    paddingHorizontal: 14,
    paddingVertical: 11,
    backgroundColor: colors.canvasMuted,
    marginTop: 12,
  },
  savedText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  matchCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.navy,
  },
  matchEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
  },
  matchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 17,
  },
  matchTeam: {
    flex: 1,
    color: colors.warmWhite,
    fontSize: 13,
    fontWeight: '900',
  },
  matchTeamAway: {
    textAlign: 'right',
  },
  matchVs: {
    color: colors.lime,
    fontSize: 15,
    fontWeight: '900',
    marginHorizontal: 12,
  },
  lockText: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 19,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 19,
    fontWeight: '900',
    marginTop: 23,
    marginBottom: 11,
  },
  autoText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    marginTop: 14,
  },
  formationsRow: {
    gap: 9,
    paddingRight: 20,
  },
  formationButton: {
    minWidth: 70,
    height: 42,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 12,
    backgroundColor: colors.white,
  },
  formationButtonActive: {
    backgroundColor: colors.navy,
  },
  formationText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  formationTextActive: {
    color: colors.lime,
  },
  playersCard: {
    borderRadius: radius.lg,
    padding: 7,
    backgroundColor: colors.white,
  },
  playerRow: {
    minHeight: 62,
    borderRadius: 15,
    paddingHorizontal: 9,
    flexDirection: 'row',
    alignItems: 'center',
  },
  playerRowSelected: {
    backgroundColor: colors.limeSoft,
  },
  checkBox: {
    width: 38,
    height: 38,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  checkBoxSelected: {
    backgroundColor: colors.navy,
  },
  checkText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  checkTextSelected: {
    color: colors.lime,
  },
  playerCopy: {
    flex: 1,
    marginLeft: 11,
  },
  playerName: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  playerClub: {
    color: colors.muted,
    fontSize: 9,
    marginTop: 4,
  },
  playerPrice: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
  },
  benchCount: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    marginTop: 14,
  },
  benchRow: {
    minHeight: 62,
    borderRadius: 15,
    paddingHorizontal: 9,
    flexDirection: 'row',
    alignItems: 'center',
  },
  benchPosition: {
    width: 38,
    height: 38,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  benchPositionText: {
    color: colors.lime,
    fontSize: 12,
    fontWeight: '900',
  },
  orderButton: {
    width: 34,
    height: 34,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
    marginLeft: 6,
  },
  orderButtonDisabled: {
    opacity: 0.28,
  },
  orderButtonText: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  emptyBenchText: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    paddingHorizontal: 12,
    paddingVertical: 18,
  },
  feedbackCard: {
    borderRadius: radius.md,
    padding: 15,
    backgroundColor: '#FFE9E8',
    marginTop: 16,
  },
  feedbackCardSuccess: {
    backgroundColor: colors.limeSoft,
  },
  feedbackText: {
    color: '#A3312D',
    fontSize: 12,
    fontWeight: '700',
    lineHeight: 18,
  },
  feedbackTextSuccess: {
    color: colors.navy,
  },
  submitButton: {
    minHeight: 58,
    borderRadius: radius.lg,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 20,
    backgroundColor: colors.lime,
    marginTop: 18,
  },
  submitButtonDisabled: {
    opacity: 0.45,
  },
  submitButtonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
});
