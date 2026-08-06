import { useEffect, useState } from 'react';
import {
  Alert,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import {
  leaveLeague,
  updateMyTeamName,
} from '../services/teamMembershipService';
import { colors, radius } from '../theme';
import type { AppScreen, LeagueSummary } from '../types';

type Props = {
  currentUserId: string | null;
  league: LeagueSummary | null;
  onLeagueChanged: () => void | Promise<void>;
  onLeagueLeft: () => void | Promise<void>;
  onNavigate: (screen: AppScreen) => void;
};

export function TeamMembershipScreen({
  currentUserId,
  league,
  onLeagueChanged,
  onLeagueLeft,
  onNavigate,
}: Props) {
  const [teamName, setTeamName] = useState(league?.team?.name ?? '');
  const [busy, setBusy] = useState<'name' | 'leave' | null>(null);
  const [feedback, setFeedback] = useState('');
  const [isError, setIsError] = useState(false);

  useEffect(() => {
    setTeamName(league?.team?.name ?? '');
  }, [league?.team?.name]);

  if (!league) {
    return (
      <View style={styles.emptyRoot}>
        <Text style={styles.emptyTitle}>Squadra non disponibile</Text>
        <Pressable
          onPress={() => onNavigate('home')}
          style={styles.primaryButton}
        >
          <Text style={styles.primaryButtonText}>TORNA ALLA HOME</Text>
        </Pressable>
      </View>
    );
  }

  const isOwner = Boolean(league.isDemo) || league.ownerId === currentUserId;
  const competitionStarted = Boolean(league.competitionStartedAt);
  const locked = Boolean(league.isDemo) || competitionStarted;

  const showOutcome = (outcome: { error?: string; notice?: string }) => {
    setFeedback(outcome.error ?? outcome.notice ?? '');
    setIsError(Boolean(outcome.error));
    return !outcome.error;
  };

  const saveTeamName = async () => {
    const normalizedName = teamName.trim();
    if (league.isDemo) {
      showOutcome({ error: 'La squadra demo non può essere modificata.' });
      return;
    }
    if (competitionStarted) {
      showOutcome({
        error:
          'La competizione è iniziata: il nome squadra non può più cambiare.',
      });
      return;
    }
    if (normalizedName.length < 2 || normalizedName.length > 40) {
      showOutcome({
        error: 'Il nome squadra deve contenere da 2 a 40 caratteri.',
      });
      return;
    }
    if (normalizedName === league.team?.name) {
      showOutcome({ notice: 'Il nome squadra è già aggiornato.' });
      return;
    }

    setBusy('name');
    const outcome = await updateMyTeamName(league.id, normalizedName);
    if (showOutcome(outcome)) {
      await onLeagueChanged();
    }
    setBusy(null);
  };

  const confirmLeave = () => {
    if (league.isDemo) {
      showOutcome({ error: 'Non puoi lasciare la lega dimostrativa.' });
      return;
    }
    if (isOwner) {
      showOutcome({
        error: 'Trasferisci prima la presidenza a un altro partecipante.',
      });
      return;
    }
    if (competitionStarted) {
      showOutcome({
        error: 'La competizione è iniziata: i partecipanti sono bloccati.',
      });
      return;
    }

    Alert.alert(
      `Lasciare “${league.name}”?`,
      'La tua squadra, la rosa e le attività pre-campionato saranno rimosse. Potrai rientrare soltanto con un invito ancora valido.',
      [
        { text: 'Annulla', style: 'cancel' },
        {
          text: 'Lascia la lega',
          style: 'destructive',
          onPress: () => void performLeave(),
        },
      ],
    );
  };

  const performLeave = async () => {
    setBusy('leave');
    const outcome = await leaveLeague(league.id);
    if (showOutcome(outcome)) {
      await onLeagueLeft();
    }
    setBusy(null);
  };

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      style={styles.root}
    >
      <ScrollView
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
            <Text style={styles.eyebrow}>SQUADRA E PARTECIPAZIONE</Text>
            <Text style={styles.title}>La tua identità</Text>
          </View>
        </View>

        <View style={styles.heroCard}>
          <View style={styles.statusPill}>
            <Text style={styles.statusPillText}>
              {competitionStarted ? 'IDENTITÀ BLOCCATA' : 'PRE-CAMPIONATO'}
            </Text>
          </View>
          <Text style={styles.heroTeam}>
            {league.team?.name ?? 'Squadra da completare'}
          </Text>
          <Text style={styles.heroLeague}>{league.name}</Text>
          <View style={styles.heroStats}>
            <Stat label="RUOLO" value={isOwner ? 'PRESIDENTE' : 'MANAGER'} />
            <Stat
              label="CREDITI"
              value={String(
                league.team?.creditsRemaining ?? league.startingCredits,
              )}
            />
          </View>
        </View>

        <Text style={styles.sectionTitle}>Nome squadra</Text>
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Come vuoi farti chiamare?</Text>
          <Text style={styles.cardBody}>
            Il nuovo nome comparirà subito a tutti i partecipanti. Dopo l’avvio
            del campionato non sarà più modificabile.
          </Text>
          <TextInput
            autoCapitalize="words"
            editable={!locked && busy === null}
            maxLength={40}
            onChangeText={setTeamName}
            placeholder="Nome squadra"
            placeholderTextColor={colors.muted}
            style={[styles.input, locked && styles.inputLocked]}
            value={teamName}
          />
          <Pressable
            disabled={locked || busy !== null}
            onPress={() => void saveTeamName()}
            style={[
              styles.primaryButton,
              (locked || busy !== null) && styles.disabledButton,
            ]}
          >
            <Text style={styles.primaryButtonText}>
              {busy === 'name' ? 'SALVATAGGIO…' : 'SALVA NOME SQUADRA'}
            </Text>
          </Pressable>
        </View>

        {feedback ? (
          <View style={[styles.feedback, isError && styles.feedbackError]}>
            <Text
              style={[
                styles.feedbackText,
                isError && styles.feedbackErrorText,
              ]}
            >
              {feedback}
            </Text>
          </View>
        ) : null}

        <Text style={styles.sectionTitle}>Partecipazione</Text>
        <View style={styles.dangerCard}>
          <Text style={styles.dangerTitle}>
            {isOwner ? 'Sei il Presidente' : 'Lascia la lega'}
          </Text>
          <Text style={styles.dangerBody}>
            {isOwner
              ? 'Per uscire devi prima trasferire la presidenza dalla Direzione lega. Il campionato non resterà senza guida.'
              : competitionStarted
                ? 'La competizione è iniziata. La partecipazione resta bloccata per non alterare calendario e risultati.'
                : 'Prima del campionato puoi uscire autonomamente. Rosa, offerte e attività della tua squadra saranno eliminate in modo sicuro.'}
          </Text>
          {isOwner ? (
            <Pressable
              onPress={() => onNavigate('leagueManagement')}
              style={styles.directionButton}
            >
              <Text style={styles.directionButtonText}>
                APRI DIREZIONE LEGA →
              </Text>
            </Pressable>
          ) : (
            <Pressable
              disabled={competitionStarted || busy !== null}
              onPress={confirmLeave}
              style={[
                styles.leaveButton,
                (competitionStarted || busy !== null) && styles.disabledButton,
              ]}
            >
              <Text style={styles.leaveButtonText}>
                {busy === 'leave' ? 'USCITA IN CORSO…' : 'LASCIA LA LEGA'}
              </Text>
            </Pressable>
          )}
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.stat}>
      <Text style={styles.statLabel}>{label}</Text>
      <Text style={styles.statValue}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    padding: 20,
    paddingBottom: 48,
  },
  emptyRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 28,
    backgroundColor: colors.canvas,
  },
  emptyTitle: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
    marginBottom: 18,
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
    letterSpacing: 0.55,
  },
  title: {
    color: colors.navy,
    fontSize: 27,
    fontWeight: '900',
    marginTop: 3,
  },
  heroCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.navy,
  },
  statusPill: {
    alignSelf: 'flex-start',
    borderRadius: 12,
    paddingHorizontal: 10,
    paddingVertical: 6,
    backgroundColor: colors.lime,
  },
  statusPillText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  heroTeam: {
    color: colors.warmWhite,
    fontSize: 24,
    fontWeight: '900',
    marginTop: 18,
  },
  heroLeague: {
    color: colors.mutedLight,
    fontSize: 12,
    marginTop: 5,
  },
  heroStats: {
    flexDirection: 'row',
    marginTop: 22,
    paddingTop: 18,
    borderTopWidth: 1,
    borderTopColor: colors.navyLine,
  },
  stat: {
    flex: 1,
  },
  statLabel: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
  },
  statValue: {
    color: colors.lime,
    fontSize: 15,
    fontWeight: '900',
    marginTop: 5,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
    marginTop: 24,
    marginBottom: 11,
  },
  card: {
    borderRadius: radius.lg,
    padding: 18,
    backgroundColor: colors.white,
  },
  cardTitle: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  cardBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 6,
  },
  input: {
    height: 50,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    paddingHorizontal: 15,
    color: colors.navy,
    fontSize: 14,
    fontWeight: '800',
    backgroundColor: colors.canvas,
    marginTop: 16,
  },
  inputLocked: {
    color: colors.muted,
  },
  primaryButton: {
    minHeight: 50,
    borderRadius: 25,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 20,
    backgroundColor: colors.lime,
    marginTop: 14,
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.3,
  },
  disabledButton: {
    opacity: 0.42,
  },
  feedback: {
    borderRadius: radius.md,
    padding: 14,
    backgroundColor: colors.limeSoft,
    marginTop: 14,
  },
  feedbackError: {
    backgroundColor: '#FFE9E7',
  },
  feedbackText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '800',
    lineHeight: 16,
  },
  feedbackErrorText: {
    color: '#A62D27',
  },
  dangerCard: {
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: '#FFD1CE',
    padding: 18,
    backgroundColor: colors.white,
  },
  dangerTitle: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  dangerBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 7,
  },
  leaveButton: {
    minHeight: 48,
    borderRadius: 24,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.danger,
    marginTop: 17,
  },
  leaveButtonText: {
    color: colors.white,
    fontSize: 10,
    fontWeight: '900',
  },
  directionButton: {
    minHeight: 48,
    borderRadius: 24,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
    marginTop: 17,
  },
  directionButtonText: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
  },
});
