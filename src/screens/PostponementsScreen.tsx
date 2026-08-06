import { useState } from 'react';
import {
  ActivityIndicator,
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
import { useLeaguePostponements } from '../hooks/useLeaguePostponements';
import { colors, radius } from '../theme';
import type {
  LeagueSummary,
  PostponedFixtureIssue,
} from '../types';

type Props = {
  league: LeagueSummary | null;
  onBack: () => void;
};

export function PostponementsScreen({ league, onBack }: Props) {
  const postponements = useLeaguePostponements(league);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [score, setScore] = useState('6');
  const [reason, setReason] = useState('');
  const [feedback, setFeedback] = useState('');

  if (!league) {
    return (
      <View style={styles.centerRoot}>
        <Text style={styles.centerTitle}>Prima scegli una lega.</Text>
        <Pressable onPress={onBack} style={styles.primaryButton}>
          <Text style={styles.primaryButtonText}>TORNA ALLA LEGA</Text>
        </Pressable>
      </View>
    );
  }

  const center = postponements.center;
  const beginDecision = (issue: PostponedFixtureIssue) => {
    setEditingId(issue.providerFixtureId);
    setScore('6');
    setReason('');
    setFeedback('');
  };

  const applyDecision = async (issue: PostponedFixtureIssue) => {
    const parsedScore = Number(score.trim().replace(',', '.'));
    if (!Number.isFinite(parsedScore) || parsedScore < 0 || parsedScore > 10) {
      setFeedback('Il voto deve essere compreso tra 0 e 10.');
      return;
    }
    if (reason.trim().length < 10 || reason.trim().length > 280) {
      setFeedback('Inserisci una motivazione da 10 a 280 caratteri.');
      return;
    }

    const outcome = await postponements.applyPoliticalScore(
      issue.providerFixtureId,
      parsedScore,
      reason.trim(),
    );
    if ('error' in outcome && outcome.error) {
      setFeedback(outcome.error);
      return;
    }
    setEditingId(null);
    setFeedback('');
  };

  const confirmRevoke = (issue: PostponedFixtureIssue) => {
    if (!issue.resolution) {
      return;
    }
    Alert.alert(
      'Revocare il voto d’ufficio?',
      'LEGHEVO tornerà ad attendere il recupero e ricalcolerà i risultati non ufficiali.',
      [
        { text: 'ANNULLA', style: 'cancel' },
        {
          text: 'REVOCA',
          style: 'destructive',
          onPress: async () => {
            const outcome = await postponements.revokePoliticalScore(
              issue.providerFixtureId,
              issue.resolution?.id ?? '',
              'Decisione revocata dal Presidente.',
              issue.resolution?.revision ?? 0,
            );
            if ('error' in outcome && outcome.error) {
              setFeedback(outcome.error);
            }
          },
        },
      ],
    );
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
            accessibilityLabel="Torna alla lega"
            onPress={onBack}
            style={styles.backButton}
          >
            <Text style={styles.backText}>‹</Text>
          </Pressable>
          <View style={styles.headerCopy}>
            <Text style={styles.eyebrow}>GESTIONE EVENTI ECCEZIONALI</Text>
            <Text style={styles.title}>Rinvii e sospensioni</Text>
          </View>
          <Pressable
            accessibilityLabel="Aggiorna centro rinvii"
            accessibilityState={{
              busy: postponements.loading,
              disabled: postponements.loading,
            }}
            disabled={postponements.loading}
            onPress={() => void postponements.refresh()}
            style={[
              styles.reloadButton,
              postponements.loading && styles.reloadButtonDisabled,
            ]}
          >
            {postponements.loading ? (
              <ActivityIndicator color={colors.navy} size="small" />
            ) : (
              <Text style={styles.reloadText}>↻</Text>
            )}
          </Pressable>
        </View>

        <View style={styles.heroCard}>
          <View style={styles.heroBadge}>
            <Text style={styles.heroBadgeText}>6</Text>
          </View>
          <View style={styles.heroCopy}>
            <Text style={styles.heroEyebrow}>
              {league.name.toUpperCase()}
            </Text>
            <Text style={styles.heroTitle}>Nessun turno resta sospeso.</Text>
            <Text style={styles.heroBody}>
              Di base si attende il recupero. Il Presidente può assegnare un
              voto d’ufficio tracciato alla sola partita coinvolta.
            </Text>
          </View>
        </View>

        {postponements.loading && !center ? (
          <View style={styles.stateCard}>
            <ActivityIndicator color={colors.navy} />
            <Text style={styles.stateBody}>Controllo i campi…</Text>
          </View>
        ) : postponements.error ? (
          <View style={styles.errorCard}>
            <Text style={styles.errorTitle}>Centro rinvii indisponibile</Text>
            <Text style={styles.errorBody}>{postponements.error}</Text>
            <Pressable
              onPress={() => void postponements.refresh()}
              style={styles.retryButton}
            >
              <Text style={styles.retryText}>RIPROVA</Text>
            </Pressable>
          </View>
        ) : center ? (
          <>
            <View style={styles.summaryCard}>
              <SummaryStat label="SEGNALATE" value={center.issueCount} />
              <SummaryStat label="RISOLTE" value={center.resolvedCount} />
              <SummaryStat label="IN ATTESA" value={center.unresolvedCount} />
            </View>

            {center.protected ? (
              <View style={styles.infoCard}>
                <Text style={styles.infoLabel}>
                  GESTIONE PROTETTA · ANTI-DOPPIO TOCCO
                </Text>
                <Text style={styles.infoText}>
                  Decisioni revisionate e sincronizzate tra dispositivi. Azioni
                  certificate: {center.certifiedActionCount}.
                </Text>
              </View>
            ) : null}

            {!center.isOwner ? (
              <View style={styles.infoCard}>
                <Text style={styles.infoLabel}>TRASPARENZA DELLA LEGA</Text>
                <Text style={styles.infoText}>
                  Puoi vedere tutte le decisioni. Soltanto il Presidente può
                  applicare o revocare un voto d’ufficio.
                </Text>
              </View>
            ) : null}

            {postponements.notice ? (
              <Text style={styles.notice}>{postponements.notice}</Text>
            ) : null}
            {feedback ? <Text style={styles.feedback}>{feedback}</Text> : null}

            <Text style={styles.sectionTitle}>Partite segnalate</Text>
            {center.issues.length === 0 ? (
              <View style={styles.emptyCard}>
                <View style={styles.emptyBadge}>
                  <Text style={styles.emptyBadgeText}>✓</Text>
                </View>
                <Text style={styles.emptyTitle}>Calendario regolare</Text>
                <Text style={styles.emptyBody}>
                  Il provider non segnala partite rinviate, sospese o
                  cancellate nelle giornate della lega.
                </Text>
              </View>
            ) : (
              <View style={styles.issueList}>
                {center.issues.map((issue) => (
                  <IssueCard
                    editing={editingId === issue.providerFixtureId}
                    issue={issue}
                    key={issue.providerFixtureId}
                    loading={
                      postponements.savingId === issue.providerFixtureId
                    }
                    onApply={() => void applyDecision(issue)}
                    onBegin={() => beginDecision(issue)}
                    onCancel={() => {
                      setEditingId(null);
                      setFeedback('');
                    }}
                    onReasonChange={setReason}
                    onRevoke={() => confirmRevoke(issue)}
                    onScoreChange={setScore}
                    owner={center.isOwner}
                    reason={reason}
                    score={score}
                  />
                ))}
              </View>
            )}

            <View style={styles.ruleCard}>
              <Text style={styles.ruleLabel}>COME FUNZIONA</Text>
              <Text style={styles.ruleTitle}>Una decisione, una partita</Text>
              <Text style={styles.ruleBody}>
                Il voto scelto vale per tutti i calciatori dei due club
                coinvolti e non modifica i dati del provider. Campionato,
                Coppa, Playoff e Supercoppa usano lo stesso verdetto della
                lega. Quando arriva un risultato ufficiale, il voto provvisorio
                viene superato automaticamente.
              </Text>
            </View>
          </>
        ) : null}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

function IssueCard({
  editing,
  issue,
  loading,
  onApply,
  onBegin,
  onCancel,
  onReasonChange,
  onRevoke,
  onScoreChange,
  owner,
  reason,
  score,
}: {
  editing: boolean;
  issue: PostponedFixtureIssue;
  loading: boolean;
  onApply: () => void;
  onBegin: () => void;
  onCancel: () => void;
  onReasonChange: (value: string) => void;
  onRevoke: () => void;
  onScoreChange: (value: string) => void;
  owner: boolean;
  reason: string;
  score: string;
}) {
  const resolution = issue.resolution;
  return (
    <View style={[styles.issueCard, resolution && styles.issueCardResolved]}>
      <View style={styles.issueHeader}>
        <View style={styles.statusPill}>
          <Text style={styles.statusText}>{statusLabel(issue.status)}</Text>
        </View>
        <Text style={styles.matchdayLabel}>
          GIORNATA {issue.matchdayNumber}
        </Text>
      </View>
      <Text style={styles.fixtureTitle}>
        {issue.homeTeam} – {issue.awayTeam}
      </Text>
      <Text style={styles.fixtureDate}>{formatDate(issue.kickoffAt)}</Text>

      {resolution ? (
        <View style={styles.resolutionCard}>
          <View style={styles.resolutionScore}>
            <Text style={styles.resolutionScoreValue}>
              {formatScore(resolution.politicalScore)}
            </Text>
            <Text style={styles.resolutionScoreLabel}>VOTO</Text>
          </View>
          <View style={styles.resolutionCopy}>
            <Text style={styles.resolutionTitle}>
              Voto d’ufficio attivo
            </Text>
            <Text style={styles.resolutionReason}>{resolution.reason}</Text>
            <Text style={styles.resolutionMeta}>
              {resolution.decidedBy} · {formatDate(resolution.decidedAt)}
              {resolution.protected && resolution.revision > 0
                ? ` · REVISIONE CERTIFICATA v${resolution.revision}`
                : ''}
            </Text>
          </View>
        </View>
      ) : (
        <View style={styles.waitingRow}>
          <View style={styles.waitingDot} />
          <View style={styles.waitingCopy}>
            <Text style={styles.waitingTitle}>In attesa del recupero</Text>
            <Text style={styles.waitingBody}>
              La giornata resta non ufficiale finché manca questo risultato.
            </Text>
          </View>
        </View>
      )}

      {issue.locked ? (
        <Text style={styles.lockedText}>
          Risultati già ufficiali: per cambiare la decisione occorre prima
          riaprire la giornata.
        </Text>
      ) : editing ? (
        <View style={styles.editor}>
          <Text style={styles.editorLabel}>VOTO D’UFFICIO</Text>
          <TextInput
            keyboardType="decimal-pad"
            maxLength={4}
            onChangeText={onScoreChange}
            selectTextOnFocus
            style={styles.scoreInput}
            value={score}
          />
          <Text style={styles.editorLabel}>MOTIVAZIONE</Text>
          <TextInput
            maxLength={280}
            multiline
            onChangeText={onReasonChange}
            placeholder="Es. recupero oltre la finestra prevista dal regolamento"
            placeholderTextColor={colors.muted}
            style={styles.reasonInput}
            value={reason}
          />
          <Text style={styles.characterCount}>{reason.trim().length}/280</Text>
          <View style={styles.editorActions}>
            <Pressable
              disabled={loading}
              onPress={onCancel}
              style={styles.cancelButton}
            >
              <Text style={styles.cancelButtonText}>ANNULLA</Text>
            </Pressable>
            <Pressable
              disabled={loading}
              onPress={onApply}
              style={[
                styles.applyButton,
                loading && styles.buttonDisabled,
              ]}
            >
              <Text style={styles.applyButtonText}>
                {loading ? 'CALCOLO…' : 'APPLICA E RICALCOLA'}
              </Text>
            </Pressable>
          </View>
        </View>
      ) : owner && !resolution ? (
        <Pressable onPress={onBegin} style={styles.decisionButton}>
          <Text style={styles.decisionButtonText}>
            ASSEGNA VOTO D’UFFICIO
          </Text>
        </Pressable>
      ) : owner && resolution ? (
        <Pressable
          disabled={loading}
          onPress={onRevoke}
          style={styles.revokeButton}
        >
          <Text style={styles.revokeButtonText}>
            {loading ? 'AGGIORNO…' : 'REVOCA E ATTENDI IL RECUPERO'}
          </Text>
        </Pressable>
      ) : null}
    </View>
  );
}

function SummaryStat({ label, value }: { label: string; value: number }) {
  return (
    <View style={styles.summaryItem}>
      <Text style={styles.summaryValue}>{value}</Text>
      <Text style={styles.summaryLabel}>{label}</Text>
    </View>
  );
}

function statusLabel(status: string) {
  const labels: Record<string, string> = {
    PST: 'RINVIATA',
    SUSP: 'SOSPESA',
    INT: 'INTERROTTA',
    CANC: 'CANCELLATA',
    ABD: 'ABBANDONATA',
    TBD: 'DATA DA DEFINIRE',
  };
  return labels[status] ?? status;
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value));
}

function formatScore(value: number) {
  return Number.isInteger(value)
    ? String(value)
    : value.toFixed(1).replace('.', ',');
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
  centerRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 28,
    backgroundColor: colors.canvas,
  },
  centerTitle: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '900',
    textAlign: 'center',
  },
  primaryButton: {
    minHeight: 50,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 24,
    marginTop: 20,
    backgroundColor: colors.navy,
  },
  primaryButtonText: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.4,
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
    letterSpacing: 0.5,
  },
  title: {
    color: colors.navy,
    fontSize: 25,
    fontWeight: '900',
    marginTop: 4,
  },
  reloadButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  reloadButtonDisabled: {
    opacity: 0.65,
  },
  reloadText: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '900',
  },
  heroCard: {
    minHeight: 156,
    borderRadius: radius.xl,
    padding: 22,
    flexDirection: 'row',
    backgroundColor: colors.navy,
  },
  heroBadge: {
    width: 52,
    height: 52,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  heroBadgeText: {
    color: colors.navy,
    fontSize: 23,
    fontWeight: '900',
  },
  heroCopy: {
    flex: 1,
    marginLeft: 16,
  },
  heroEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  heroTitle: {
    color: colors.white,
    fontSize: 20,
    fontWeight: '900',
    marginTop: 5,
  },
  heroBody: {
    color: colors.mutedLight,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 7,
  },
  stateCard: {
    minHeight: 120,
    borderRadius: radius.lg,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 18,
    backgroundColor: colors.white,
  },
  stateBody: {
    color: colors.muted,
    fontSize: 12,
    marginTop: 10,
  },
  errorCard: {
    borderRadius: radius.lg,
    padding: 20,
    marginTop: 18,
    backgroundColor: '#FFF0EC',
  },
  errorTitle: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  errorBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 6,
  },
  retryButton: {
    alignSelf: 'flex-start',
    marginTop: 14,
  },
  retryText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  summaryCard: {
    minHeight: 106,
    borderRadius: radius.lg,
    flexDirection: 'row',
    marginTop: 16,
    backgroundColor: colors.white,
  },
  summaryItem: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  summaryValue: {
    color: colors.navy,
    fontSize: 27,
    fontWeight: '900',
  },
  summaryLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.35,
    marginTop: 4,
  },
  infoCard: {
    borderRadius: radius.md,
    padding: 16,
    marginTop: 12,
    backgroundColor: '#F3F7E8',
  },
  infoLabel: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  infoText: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 5,
  },
  notice: {
    color: '#2E5B23',
    fontSize: 11,
    fontWeight: '800',
    lineHeight: 17,
    marginTop: 14,
  },
  feedback: {
    color: '#A33A23',
    fontSize: 11,
    fontWeight: '800',
    lineHeight: 17,
    marginTop: 14,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
    marginTop: 24,
    marginBottom: 11,
  },
  issueList: {
    gap: 12,
  },
  issueCard: {
    borderRadius: radius.lg,
    padding: 19,
    borderWidth: 1,
    borderColor: '#E4E8E1',
    backgroundColor: colors.white,
  },
  issueCardResolved: {
    borderColor: colors.lime,
  },
  issueHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  statusPill: {
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 6,
    backgroundColor: '#FFF0D8',
  },
  statusText: {
    color: '#8A5610',
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.35,
  },
  matchdayLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.35,
  },
  fixtureTitle: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
    marginTop: 14,
  },
  fixtureDate: {
    color: colors.muted,
    fontSize: 10,
    marginTop: 5,
  },
  waitingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderTopWidth: 1,
    borderTopColor: colors.canvasMuted,
    paddingTop: 16,
    marginTop: 16,
  },
  waitingDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    marginRight: 12,
    backgroundColor: '#E2A84A',
  },
  waitingCopy: {
    flex: 1,
  },
  waitingTitle: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  waitingBody: {
    color: colors.muted,
    fontSize: 10,
    lineHeight: 15,
    marginTop: 3,
  },
  resolutionCard: {
    borderRadius: radius.md,
    padding: 15,
    flexDirection: 'row',
    marginTop: 16,
    backgroundColor: '#F5FBE6',
  },
  resolutionScore: {
    width: 52,
    height: 58,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  resolutionScoreValue: {
    color: colors.lime,
    fontSize: 21,
    fontWeight: '900',
  },
  resolutionScoreLabel: {
    color: colors.mutedLight,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 2,
  },
  resolutionCopy: {
    flex: 1,
    marginLeft: 13,
  },
  resolutionTitle: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  resolutionReason: {
    color: colors.muted,
    fontSize: 10,
    lineHeight: 15,
    marginTop: 4,
  },
  resolutionMeta: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '800',
    marginTop: 6,
  },
  lockedText: {
    color: '#8A5610',
    fontSize: 10,
    lineHeight: 15,
    marginTop: 14,
  },
  decisionButton: {
    minHeight: 48,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 16,
    backgroundColor: colors.navy,
  },
  decisionButtonText: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  revokeButton: {
    minHeight: 45,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 14,
    backgroundColor: '#FFF0EC',
  },
  revokeButtonText: {
    color: '#A33A23',
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.3,
  },
  editor: {
    borderTopWidth: 1,
    borderTopColor: colors.canvasMuted,
    paddingTop: 16,
    marginTop: 16,
  },
  editorLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.35,
    marginBottom: 7,
  },
  scoreInput: {
    width: 92,
    height: 50,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: radius.sm,
    color: colors.navy,
    fontSize: 19,
    fontWeight: '900',
    paddingHorizontal: 14,
    marginBottom: 14,
    backgroundColor: colors.canvas,
  },
  reasonInput: {
    minHeight: 98,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: radius.sm,
    color: colors.navy,
    fontSize: 12,
    lineHeight: 18,
    padding: 13,
    textAlignVertical: 'top',
    backgroundColor: colors.canvas,
  },
  characterCount: {
    color: colors.muted,
    fontSize: 8,
    textAlign: 'right',
    marginTop: 5,
  },
  editorActions: {
    flexDirection: 'row',
    gap: 10,
    marginTop: 14,
  },
  cancelButton: {
    minHeight: 46,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 16,
    backgroundColor: colors.canvasMuted,
  },
  cancelButtonText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  applyButton: {
    flex: 1,
    minHeight: 46,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 12,
    backgroundColor: colors.navy,
  },
  applyButtonText: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
  },
  buttonDisabled: {
    opacity: 0.55,
  },
  emptyCard: {
    minHeight: 180,
    borderRadius: radius.lg,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
    backgroundColor: colors.white,
  },
  emptyBadge: {
    width: 48,
    height: 48,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  emptyBadgeText: {
    color: colors.lime,
    fontSize: 20,
    fontWeight: '900',
  },
  emptyTitle: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
    marginTop: 13,
  },
  emptyBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    textAlign: 'center',
    marginTop: 6,
  },
  ruleCard: {
    borderRadius: radius.lg,
    padding: 20,
    marginTop: 20,
    backgroundColor: colors.navy,
  },
  ruleLabel: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  ruleTitle: {
    color: colors.white,
    fontSize: 17,
    fontWeight: '900',
    marginTop: 5,
  },
  ruleBody: {
    color: colors.mutedLight,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 7,
  },
});
