import { useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import type {
  CreateLeagueInput,
  JoinLeagueInput,
  LeagueActionOutcome,
  LeagueInvitePreview,
  LeagueInvitePreviewOutcome,
} from '../services/leagueService';
import type { CommercialEntitlement } from '../services/subscriptionService';
import { colors, radius } from '../theme';
import type { LeagueMode } from '../types';

type SetupMode = 'create' | 'join';

type Props = {
  commercial: CommercialEntitlement;
  onClose: () => void;
  onCreate: (input: CreateLeagueInput) => Promise<LeagueActionOutcome>;
  onJoin: (input: JoinLeagueInput) => Promise<LeagueActionOutcome>;
  onPreviewInvite: (inviteCode: string) => Promise<LeagueInvitePreviewOutcome>;
  onOpenPremium: () => void;
  onSuccess: (leagueId: string) => void;
};

export function LeagueSetupScreen({
  commercial,
  onClose,
  onCreate,
  onJoin,
  onPreviewInvite,
  onOpenPremium,
  onSuccess,
}: Props) {
  const [setupMode, setSetupMode] = useState<SetupMode>('create');
  const [leagueName, setLeagueName] = useState('');
  const [teamName, setTeamName] = useState('');
  const [inviteCode, setInviteCode] = useState('');
  const [leagueMode, setLeagueMode] = useState<LeagueMode>('classic');
  const [teamLimit, setTeamLimit] = useState(6);
  const [startingCredits, setStartingCredits] = useState('500');
  const [rosterSize, setRosterSize] = useState('25');
  const [feedback, setFeedback] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [previewing, setPreviewing] = useState(false);
  const [invitePreview, setInvitePreview] =
    useState<LeagueInvitePreview | null>(null);
  const [previewedCode, setPreviewedCode] = useState('');

  const switchMode = (next: SetupMode) => {
    setSetupMode(next);
    setFeedback('');
    setInvitePreview(null);
    setPreviewedCode('');
  };

  const checkInvite = async (): Promise<LeagueInvitePreview | null> => {
    const normalizedCode = inviteCode
      .replace(/[^a-z0-9]/gi, '')
      .toUpperCase();

    if (normalizedCode.length !== 10) {
      setFeedback('Inserisci il codice invito ricevuto dal presidente.');
      setInvitePreview(null);
      setPreviewedCode('');
      return null;
    }

    setPreviewing(true);
    setFeedback('');
    const outcome = await onPreviewInvite(normalizedCode);
    setPreviewing(false);

    if (outcome.error || !outcome.preview) {
      setInvitePreview(null);
      setPreviewedCode('');
      setFeedback(outcome.error ?? 'Non riesco a verificare questo invito.');
      return null;
    }

    setInvitePreview(outcome.preview);
    setPreviewedCode(normalizedCode);
    if (!outcome.preview.canJoin) {
      setFeedback(
        outcome.preview.blockReason ?? 'Questa lega non accetta nuovi ingressi.',
      );
    }
    return outcome.preview;
  };

  const submit = async () => {
    const normalizedTeamName = teamName.trim();
    if (normalizedTeamName.length < 2) {
      setFeedback('Dai un nome alla tua squadra. Anche brutto, ma un nome.');
      return;
    }

    if (setupMode === 'create' && leagueName.trim().length < 3) {
      setFeedback('Il nome della lega deve avere almeno 3 caratteri.');
      return;
    }

    if (
      setupMode === 'create' &&
      !commercial.isPremium &&
      commercial.ownedLeagueCount >= 1
    ) {
      setFeedback(
        'Hai già creato la lega inclusa nel piano Free. Premium sblocca nuove leghe.',
      );
      return;
    }

    const normalizedInviteCode = inviteCode
      .replace(/[^a-z0-9]/gi, '')
      .toUpperCase();

    if (setupMode === 'join' && normalizedInviteCode.length !== 10) {
      setFeedback('Inserisci il codice invito ricevuto dal presidente.');
      return;
    }

    if (setupMode === 'join') {
      const currentPreview =
        invitePreview && previewedCode === normalizedInviteCode
          ? invitePreview
          : await checkInvite();

      if (!currentPreview) {
        return;
      }

      if (!currentPreview.canJoin) {
        setFeedback(
          currentPreview.blockReason ??
            'Questa lega non accetta nuovi ingressi.',
        );
        return;
      }
    }

    const credits = Number.parseInt(startingCredits, 10);
    const roster = Number.parseInt(rosterSize, 10);
    if (
      setupMode === 'create' &&
      (!Number.isFinite(credits) ||
        credits < 100 ||
        !Number.isFinite(roster) ||
        roster < 11 ||
        roster > 50)
    ) {
      setFeedback('Controlla crediti iniziali e numero di calciatori.');
      return;
    }

    setSubmitting(true);
    setFeedback('');

    const outcome =
      setupMode === 'create'
        ? await onCreate({
            name: leagueName,
            teamName: normalizedTeamName,
            mode: leagueMode,
            teamLimit,
            startingCredits: credits,
            rosterSize: roster,
          })
        : await onJoin({
            inviteCode: normalizedInviteCode,
            teamName: normalizedTeamName,
          });

    setSubmitting(false);

    if (outcome.error) {
      setFeedback(outcome.error);
      return;
    }

    if (outcome.league) {
      onSuccess(outcome.league.id);
    }
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
          <Pressable onPress={onClose} style={styles.closeButton}>
            <Text style={styles.closeText}>‹</Text>
          </Pressable>
          <View>
            <Text style={styles.eyebrow}>NUOVO SPOGLIATOIO</Text>
            <Text style={styles.title}>La lega parte da qui</Text>
          </View>
        </View>

        <View style={styles.modeSwitch}>
          <Pressable
            onPress={() => switchMode('create')}
            style={[
              styles.modeButton,
              setupMode === 'create' && styles.modeButtonActive,
            ]}
          >
            <Text
              style={[
                styles.modeText,
                setupMode === 'create' && styles.modeTextActive,
              ]}
            >
              CREA LEGA
            </Text>
          </Pressable>
          <Pressable
            onPress={() => switchMode('join')}
            style={[
              styles.modeButton,
              setupMode === 'join' && styles.modeButtonActive,
            ]}
          >
            <Text
              style={[
                styles.modeText,
                setupMode === 'join' && styles.modeTextActive,
              ]}
            >
              ENTRA CON CODICE
            </Text>
          </Pressable>
        </View>

        <View style={styles.formCard}>
          {setupMode === 'create' ? (
            <>
              <FieldLabel text="NOME DELLA LEGA" />
              <TextInput
                autoCapitalize="sentences"
                maxLength={50}
                onChangeText={(value) => {
                  setLeagueName(value);
                  setFeedback('');
                }}
                placeholder="Es. Quelli del lunedì"
                placeholderTextColor={colors.muted}
                style={styles.input}
                value={leagueName}
              />
            </>
          ) : (
            <>
              <FieldLabel text="CODICE INVITO" />
              <TextInput
                autoCapitalize="characters"
                autoCorrect={false}
                maxLength={10}
                onChangeText={(value) => {
                  setInviteCode(
                    value.replace(/[^a-z0-9]/gi, '').toUpperCase(),
                  );
                  setInvitePreview(null);
                  setPreviewedCode('');
                  setFeedback('');
                }}
                placeholder="ES. A1B2C3D4"
                placeholderTextColor={colors.muted}
                style={[styles.input, styles.codeInput]}
                value={inviteCode}
              />
              <Pressable
                disabled={previewing}
                onPress={() => void checkInvite()}
                style={[
                  styles.previewButton,
                  previewing && styles.previewButtonDisabled,
                ]}
              >
                {previewing ? (
                  <ActivityIndicator color={colors.lime} size="small" />
                ) : (
                  <Text style={styles.previewButtonText}>CONTROLLA CODICE</Text>
                )}
              </Pressable>

              {invitePreview ? (
                <InvitePreviewCard preview={invitePreview} />
              ) : null}
            </>
          )}

          <FieldLabel text="NOME DELLA TUA SQUADRA" />
          <TextInput
            autoCapitalize="words"
            maxLength={40}
            onChangeText={(value) => {
              setTeamName(value);
              setFeedback('');
            }}
            placeholder="Es. Panchinari FC"
            placeholderTextColor={colors.muted}
            style={styles.input}
            value={teamName}
          />

          {setupMode === 'create' && (
            <>
              <FieldLabel text="SISTEMA DI RUOLI" />
              <View style={styles.choiceRow}>
                <Choice
                  active={leagueMode === 'classic'}
                  label="CLASSICO"
                  onPress={() => setLeagueMode('classic')}
                />
                <Choice
                  active={leagueMode === 'mantra'}
                  label="MANTRA"
                  onPress={() => setLeagueMode('mantra')}
                />
              </View>

              <FieldLabel text="PARTECIPANTI" />
              <View style={styles.planNotice}>
                <View style={styles.planCopy}>
                  <Text style={styles.planNoticeTitle}>
                    {commercial.isPremium ? 'PIANO PREMIUM' : 'PIANO FREE'}
                  </Text>
                  <Text style={styles.planNoticeBody}>
                    {commercial.isPremium
                      ? 'Fino a 20 partecipanti per lega.'
                      : 'Una lega, massimo 6 partecipanti.'}
                  </Text>
                </View>
                {!commercial.isPremium ? (
                  <Pressable onPress={onOpenPremium} style={styles.planButton}>
                    <Text style={styles.planButtonText}>PREMIUM</Text>
                  </Pressable>
                ) : null}
              </View>
              <View style={styles.choiceRow}>
                {(commercial.isPremium
                  ? [6, 8, 10, 12, 14, 16, 18, 20]
                  : [6]
                ).map((value) => (
                  <Choice
                    active={teamLimit === value}
                    compact
                    key={value}
                    label={String(value)}
                    onPress={() => setTeamLimit(value)}
                  />
                ))}
              </View>

              <View style={styles.doubleField}>
                <View style={styles.halfField}>
                  <FieldLabel text="CREDITI" />
                  <TextInput
                    keyboardType="number-pad"
                    maxLength={6}
                    onChangeText={(value) => {
                      setStartingCredits(value.replace(/\D/g, ''));
                      setFeedback('');
                    }}
                    style={styles.input}
                    value={startingCredits}
                  />
                </View>
                <View style={styles.halfField}>
                  <FieldLabel text="ROSA" />
                  <TextInput
                    keyboardType="number-pad"
                    maxLength={2}
                    onChangeText={(value) => {
                      setRosterSize(value.replace(/\D/g, ''));
                      setFeedback('');
                    }}
                    style={styles.input}
                    value={rosterSize}
                  />
                </View>
              </View>
            </>
          )}

          {feedback ? <Text style={styles.feedback}>{feedback}</Text> : null}

          <Pressable
            disabled={submitting}
            onPress={() => void submit()}
            style={[
              styles.submitButton,
              submitting && styles.submitButtonDisabled,
            ]}
          >
            <Text style={styles.submitText}>
              {submitting
                ? 'Controllo distinta…'
                : setupMode === 'create'
                  ? 'Crea lega e squadra'
                  : 'Entra nello spogliatoio'}
            </Text>
          </Pressable>
        </View>

        <Text style={styles.footer}>
          Il codice invito della lega potrà essere condiviso con gli altri
          partecipanti.
        </Text>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

function InvitePreviewCard({
  preview,
}: {
  preview: LeagueInvitePreview;
}) {
  return (
    <View style={styles.previewCard}>
      <View style={styles.previewTopRow}>
        <Text style={styles.previewEyebrow}>LEGA TROVATA</Text>
        <View
          style={[
            styles.previewBadge,
            !preview.canJoin && styles.previewBadgeBlocked,
          ]}
        >
          <Text
            style={[
              styles.previewBadgeText,
              !preview.canJoin && styles.previewBadgeTextBlocked,
            ]}
          >
            {preview.canJoin ? 'POSTI APERTI' : 'NON DISPONIBILE'}
          </Text>
        </View>
      </View>
      <Text style={styles.previewName}>{preview.leagueName}</Text>
      <View style={styles.previewStats}>
        <PreviewStat
          label="SQUADRE"
          value={`${preview.teamCount}/${preview.teamLimit}`}
        />
        <PreviewStat
          label="RUOLI"
          value={preview.mode === 'mantra' ? 'MANTRA' : 'CLASSICO'}
        />
        <PreviewStat label="ROSA" value={String(preview.rosterSize)} />
      </View>
      <Text style={styles.previewFooter}>
        {preview.startingCredits} crediti iniziali · {preview.availableSpots}{' '}
        {preview.availableSpots === 1 ? 'posto libero' : 'posti liberi'}
      </Text>
    </View>
  );
}

function PreviewStat({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.previewStat}>
      <Text style={styles.previewStatValue}>{value}</Text>
      <Text style={styles.previewStatLabel}>{label}</Text>
    </View>
  );
}

function FieldLabel({ text }: { text: string }) {
  return <Text style={styles.fieldLabel}>{text}</Text>;
}

function Choice({
  active,
  compact,
  label,
  onPress,
}: {
  active: boolean;
  compact?: boolean;
  label: string;
  onPress: () => void;
}) {
  return (
    <Pressable
      onPress={onPress}
      style={[
        styles.choice,
        compact && styles.choiceCompact,
        active && styles.choiceActive,
      ]}
    >
      <Text style={[styles.choiceText, active && styles.choiceTextActive]}>
        {label}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    padding: 20,
    paddingBottom: 40,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    marginBottom: 22,
  },
  closeButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  closeText: {
    color: colors.navy,
    fontSize: 32,
    lineHeight: 34,
  },
  eyebrow: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  title: {
    color: colors.navy,
    fontSize: 25,
    fontWeight: '900',
    marginTop: 4,
  },
  modeSwitch: {
    flexDirection: 'row',
    padding: 5,
    borderRadius: radius.md,
    backgroundColor: colors.canvasMuted,
  },
  modeButton: {
    flex: 1,
    height: 44,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  modeButtonActive: {
    backgroundColor: colors.navy,
  },
  modeText: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '900',
  },
  modeTextActive: {
    color: colors.lime,
  },
  formCard: {
    marginTop: 16,
    padding: 20,
    borderRadius: radius.xl,
    backgroundColor: colors.white,
  },
  fieldLabel: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.45,
    marginTop: 17,
    marginBottom: 8,
  },
  input: {
    height: 54,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: radius.sm,
    paddingHorizontal: 15,
    color: colors.navy,
    fontSize: 15,
    fontWeight: '700',
    backgroundColor: colors.canvas,
  },
  codeInput: {
    letterSpacing: 2,
    fontWeight: '900',
  },
  choiceRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 9,
  },
  planNotice: {
    minHeight: 64,
    borderRadius: radius.md,
    backgroundColor: '#EAF1E3',
    padding: 13,
    marginBottom: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  planCopy: {
    flex: 1,
  },
  planNoticeTitle: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  planNoticeBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 17,
    marginTop: 4,
  },
  planButton: {
    height: 34,
    borderRadius: 17,
    backgroundColor: colors.navy,
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  planButtonText: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
  },
  choice: {
    flex: 1,
    height: 45,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvas,
  },
  choiceCompact: {
    minWidth: 0,
    flexBasis: '20%',
  },
  choiceActive: {
    borderColor: colors.navy,
    backgroundColor: colors.navy,
  },
  choiceText: {
    color: colors.muted,
    fontSize: 11,
    fontWeight: '900',
  },
  choiceTextActive: {
    color: colors.lime,
  },
  doubleField: {
    flexDirection: 'row',
    gap: 12,
  },
  halfField: {
    flex: 1,
  },
  previewButton: {
    height: 44,
    marginTop: 10,
    borderRadius: radius.sm,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  previewButtonDisabled: {
    opacity: 0.65,
  },
  previewButtonText: {
    color: colors.lime,
    fontSize: 11,
    fontWeight: '900',
    letterSpacing: 0.35,
  },
  previewCard: {
    marginTop: 12,
    padding: 16,
    borderRadius: radius.md,
    backgroundColor: colors.navy,
  },
  previewTopRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  previewEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.55,
  },
  previewBadge: {
    paddingHorizontal: 9,
    paddingVertical: 6,
    borderRadius: 999,
    backgroundColor: colors.lime,
  },
  previewBadgeBlocked: {
    backgroundColor: colors.navyLine,
  },
  previewBadgeText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  previewBadgeTextBlocked: {
    color: colors.mutedLight,
  },
  previewName: {
    color: colors.white,
    fontSize: 22,
    fontWeight: '900',
    marginTop: 14,
  },
  previewStats: {
    flexDirection: 'row',
    marginTop: 16,
    paddingTop: 14,
    borderTopWidth: 1,
    borderTopColor: colors.navyLine,
  },
  previewStat: {
    flex: 1,
  },
  previewStatValue: {
    color: colors.lime,
    fontSize: 16,
    fontWeight: '900',
  },
  previewStatLabel: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.45,
    marginTop: 3,
  },
  previewFooter: {
    color: colors.mutedLight,
    fontSize: 10,
    lineHeight: 15,
    marginTop: 14,
  },
  feedback: {
    color: colors.danger,
    fontSize: 12,
    fontWeight: '700',
    lineHeight: 18,
    marginTop: 17,
  },
  submitButton: {
    height: 58,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 22,
  },
  submitButtonDisabled: {
    opacity: 0.55,
  },
  submitText: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  footer: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    textAlign: 'center',
    paddingHorizontal: 24,
    marginTop: 18,
  },
});
