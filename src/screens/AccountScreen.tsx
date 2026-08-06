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
import type { AuthOutcome } from '../hooks/useAuth';
import {
  fetchAccountCenter,
  subscribeToAccountCenter,
} from '../services/accountService';
import { colors, radius } from '../theme';

type Props = {
  displayName: string;
  email: string;
  emailVerified: boolean;
  isDemo: boolean;
  userId: string | null;
  onBack: () => void;
  onDeleteAccount: () => Promise<AuthOutcome>;
  onUpdateDisplayName: (displayName: string) => Promise<AuthOutcome>;
  onUpdatePassword: (password: string) => Promise<AuthOutcome>;
};

export function AccountScreen({
  displayName,
  email,
  emailVerified,
  isDemo,
  userId,
  onBack,
  onDeleteAccount,
  onUpdateDisplayName,
  onUpdatePassword,
}: Props) {
  const [name, setName] = useState(displayName);
  const [password, setPassword] = useState('');
  const [passwordConfirmation, setPasswordConfirmation] = useState('');
  const [deleteConfirmation, setDeleteConfirmation] = useState('');
  const [feedback, setFeedback] = useState('');
  const [accountRevision, setAccountRevision] = useState(0);
  const [accountProtected, setAccountProtected] = useState(false);
  const [securityRevision, setSecurityRevision] = useState(0);
  const [securityProtected, setSecurityProtected] = useState(false);
  const [securityEventCount, setSecurityEventCount] = useState(0);
  const [lastPasswordChangedAt, setLastPasswordChangedAt] = useState<
    string | null
  >(null);
  const [serviceHubRevision, setServiceHubRevision] = useState(0);
  const [protectedServiceCount, setProtectedServiceCount] = useState(0);
  const [totalServiceCount, setTotalServiceCount] = useState(8);
  const [serviceHubProtected, setServiceHubProtected] = useState(false);
  const [accountServicesModelClosed, setAccountServicesModelClosed] =
    useState(false);
  const [accountServicesModelVersion, setAccountServicesModelVersion] =
    useState(0);
  const [accountServicesCertifiedAt, setAccountServicesCertifiedAt] = useState<
    string | null
  >(null);
  const [lastServiceActivityAt, setLastServiceActivityAt] = useState<
    string | null
  >(null);
  const [isError, setIsError] = useState(false);
  const [busy, setBusy] = useState<
    'profile' | 'password' | 'delete' | null
  >(null);

  useEffect(() => setName(displayName), [displayName]);

  useEffect(() => {
    if (isDemo || !userId) {
      setAccountRevision(0);
      setAccountProtected(false);
      setSecurityRevision(0);
      setSecurityProtected(false);
      setSecurityEventCount(0);
      setLastPasswordChangedAt(null);
      setServiceHubRevision(0);
      setProtectedServiceCount(0);
      setTotalServiceCount(8);
      setServiceHubProtected(false);
      setAccountServicesModelClosed(false);
      setAccountServicesModelVersion(0);
      setAccountServicesCertifiedAt(null);
      setLastServiceActivityAt(null);
      return;
    }

    let active = true;
    const loadAccountCenter = () => {
      void fetchAccountCenter()
        .then((center) => {
          if (!active) {
            return;
          }
          setAccountRevision(center.revision);
          setAccountProtected(center.protected);
          setSecurityRevision(center.securityRevision);
          setSecurityProtected(center.securityProtected);
          setSecurityEventCount(center.certifiedSecurityEventCount);
          setLastPasswordChangedAt(center.lastPasswordChangedAt);
          setServiceHubRevision(center.serviceHubRevision);
          setProtectedServiceCount(center.protectedServiceCount);
          setTotalServiceCount(center.totalServiceCount);
          setServiceHubProtected(center.serviceHubProtected);
          setAccountServicesModelClosed(center.accountServicesModelClosed);
          setAccountServicesModelVersion(center.accountServicesModelVersion);
          setAccountServicesCertifiedAt(center.accountServicesCertifiedAt);
          setLastServiceActivityAt(center.serviceHubLastActivityAt);
        })
        .catch(() => {
          if (active) {
            setAccountRevision(0);
            setAccountProtected(false);
            setSecurityRevision(0);
            setSecurityProtected(false);
            setSecurityEventCount(0);
            setLastPasswordChangedAt(null);
            setServiceHubRevision(0);
            setProtectedServiceCount(0);
            setTotalServiceCount(8);
            setServiceHubProtected(false);
            setAccountServicesModelClosed(false);
            setAccountServicesModelVersion(0);
            setAccountServicesCertifiedAt(null);
            setLastServiceActivityAt(null);
          }
        });
    };

    loadAccountCenter();
    const unsubscribe = subscribeToAccountCenter(userId, loadAccountCenter);

    return () => {
      active = false;
      unsubscribe();
    };
  }, [displayName, isDemo, userId]);

  const showOutcome = (outcome: AuthOutcome) => {
    setFeedback(outcome.error ?? outcome.notice ?? '');
    setIsError(Boolean(outcome.error));
    return !outcome.error;
  };

  const updateProfile = async () => {
    if (isDemo) {
      showOutcome({ error: 'Il profilo demo non può essere modificato.' });
      return;
    }
    if (name.trim().length < 2 || name.trim().length > 40) {
      showOutcome({ error: 'Il nome deve contenere da 2 a 40 caratteri.' });
      return;
    }

    setBusy('profile');
    const outcome = await onUpdateDisplayName(name);
    showOutcome(outcome);
    setBusy(null);
  };

  const updatePassword = async () => {
    if (isDemo) {
      showOutcome({ error: 'Il profilo demo non ha una password da cambiare.' });
      return;
    }
    if (password.length < 8) {
      showOutcome({ error: 'La nuova password deve avere almeno 8 caratteri.' });
      return;
    }
    if (password !== passwordConfirmation) {
      showOutcome({ error: 'Le due password non coincidono.' });
      return;
    }

    setBusy('password');
    const outcome = await onUpdatePassword(password);
    if (showOutcome(outcome)) {
      setPassword('');
      setPasswordConfirmation('');
    }
    setBusy(null);
  };

  const confirmDeletion = () => {
    if (isDemo) {
      showOutcome({ error: 'Il profilo demo non può essere eliminato.' });
      return;
    }
    if (deleteConfirmation.trim().toUpperCase() !== 'ELIMINA') {
      showOutcome({ error: 'Scrivi ELIMINA per confermare.' });
      return;
    }

    Alert.alert(
      'Eliminare davvero l’account?',
      'L’operazione è definitiva. I risultati storici resteranno anonimi.',
      [
        { text: 'Annulla', style: 'cancel' },
        {
          text: 'Elimina account',
          style: 'destructive',
          onPress: () => void deleteAccount(),
        },
      ],
    );
  };

  const deleteAccount = async () => {
    setBusy('delete');
    const outcome = await onDeleteAccount();
    showOutcome(outcome);
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
          <Pressable onPress={onBack} style={styles.backButton}>
            <Text style={styles.backText}>‹</Text>
          </Pressable>
          <View style={styles.headerCopy}>
            <Text style={styles.eyebrow}>PROFILO E SICUREZZA</Text>
            <Text style={styles.title}>Il tuo account</Text>
          </View>
        </View>

        {isDemo ? (
          <View style={styles.demoCard}>
            <Text style={styles.demoTitle}>Sei nella modalità demo</Text>
            <Text style={styles.demoBody}>
              Puoi esplorare questa sezione, ma le modifiche richiedono un
              account registrato.
            </Text>
          </View>
        ) : null}

        {!isDemo && serviceHubProtected ? (
          <View style={styles.serviceHubCard}>
            <View style={styles.serviceHubHeader}>
              <View style={styles.serviceHubCopy}>
                <Text style={styles.serviceHubEyebrow}>CENTRO SERVIZI ACCOUNT</Text>
                <Text style={styles.serviceHubTitle}>
                  {protectedServiceCount}/{totalServiceCount} servizi protetti
                </Text>
              </View>
              <View style={styles.serviceHubBadge}>
                <Text style={styles.serviceHubBadgeText}>
                  {accountServicesModelClosed
                    ? 'MODELLO CERTIFICATO'
                    : 'CERTIFICATO'}
                </Text>
              </View>
            </View>
            <Text style={styles.serviceHubBody}>
              Privacy, assistenza, notifiche, push, credenziali e dati personali
              condividono ora una revisione di sicurezza unica.
            </Text>
            <Text style={styles.serviceHubMeta}>
              {accountServicesModelClosed
                ? `MODELLO v${accountServicesModelVersion} · CERTIFICATO${
                    accountServicesCertifiedAt
                      ? ` ${formatSecurityDate(accountServicesCertifiedAt)}`
                      : ''
                  } · `
                : ''}
              REVISIONE v{serviceHubRevision}
              {lastServiceActivityAt
                ? ` · ULTIMA ATTIVITÀ ${formatSecurityDate(lastServiceActivityAt)}`
                : ''}
            </Text>
          </View>
        ) : null}

        <Text style={styles.sectionTitle}>Dati personali</Text>
        <View style={styles.card}>
          {accountProtected ? (
            <View style={styles.protectionBadge}>
              <Text style={styles.protectionBadgeText}>
                GESTIONE PROTETTA · REVISIONE v{accountRevision}
              </Text>
            </View>
          ) : null}
          <Text style={styles.label}>EMAIL</Text>
          <View style={styles.readonlyField}>
            <Text numberOfLines={1} style={styles.readonlyText}>
              {email}
            </Text>
            <Text style={styles.verifiedText}>
              {isDemo
                ? 'DEMO'
                : emailVerified
                  ? 'VERIFICATA'
                  : 'DA CONFERMARE'}
            </Text>
          </View>

          <Text style={styles.label}>NOME VISUALIZZATO</Text>
          <TextInput
            autoCapitalize="words"
            editable={!isDemo && busy === null}
            maxLength={40}
            onChangeText={setName}
            placeholder="Nome visualizzato"
            placeholderTextColor={colors.muted}
            style={styles.input}
            value={name}
          />
          <Pressable
            disabled={busy !== null}
            onPress={() => void updateProfile()}
            style={[styles.primaryButton, busy && styles.disabledButton]}
          >
            <Text style={styles.primaryButtonText}>
              {busy === 'profile' ? 'SALVATAGGIO…' : 'SALVA PROFILO'}
            </Text>
          </Pressable>
        </View>

        <Text style={styles.sectionTitle}>Password</Text>
        <View style={styles.card}>
          {securityProtected ? (
            <View style={styles.securityBadge}>
              <Text style={styles.securityBadgeText}>
                CREDENZIALI PROTETTE · REVISIONE v{securityRevision}
              </Text>
            </View>
          ) : null}
          <Text style={styles.cardTitle}>Cambia la password</Text>
          <Text style={styles.cardBody}>
            Usa almeno 8 caratteri. “milan” da solo non vale come strategia.
          </Text>
          {securityProtected ? (
            <View style={styles.securitySummary}>
              <Text style={styles.securitySummaryLabel}>
                ULTIMO CAMBIO CERTIFICATO
              </Text>
              <Text style={styles.securitySummaryValue}>
                {lastPasswordChangedAt
                  ? formatSecurityDate(lastPasswordChangedAt)
                  : 'Nessun cambio registrato dal monitoraggio'}
              </Text>
              <Text style={styles.securitySummaryMeta}>
                {securityEventCount} EVENTI DI SICUREZZA CERTIFICATI
              </Text>
            </View>
          ) : null}
          <TextInput
            autoCapitalize="none"
            autoComplete="new-password"
            editable={!isDemo && busy === null}
            onChangeText={setPassword}
            placeholder="Nuova password"
            placeholderTextColor={colors.muted}
            secureTextEntry
            style={styles.input}
            value={password}
          />
          <TextInput
            autoCapitalize="none"
            autoComplete="new-password"
            editable={!isDemo && busy === null}
            onChangeText={setPasswordConfirmation}
            placeholder="Ripeti la nuova password"
            placeholderTextColor={colors.muted}
            secureTextEntry
            style={styles.input}
            value={passwordConfirmation}
          />
          <Pressable
            disabled={busy !== null}
            onPress={() => void updatePassword()}
            style={[styles.secondaryButton, busy && styles.disabledButton]}
          >
            <Text style={styles.secondaryButtonText}>
              {busy === 'password' ? 'AGGIORNAMENTO…' : 'CAMBIA PASSWORD'}
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

        <Text style={styles.sectionTitle}>Zona retrocessione</Text>
        <View style={styles.dangerCard}>
          <Text style={styles.dangerTitle}>Elimina account</Text>
          <Text style={styles.dangerBody}>
            Cancelleremo accesso e dati personali. Le partite già disputate
            resteranno in forma anonima per non falsare le classifiche.
          </Text>
          <TextInput
            autoCapitalize="characters"
            editable={!isDemo && busy === null}
            onChangeText={setDeleteConfirmation}
            placeholder="Scrivi ELIMINA"
            placeholderTextColor={colors.muted}
            style={styles.dangerInput}
            value={deleteConfirmation}
          />
          <Pressable
            disabled={busy !== null}
            onPress={confirmDeletion}
            style={[styles.deleteButton, busy && styles.disabledButton]}
          >
            <Text style={styles.deleteButtonText}>
              {busy === 'delete' ? 'ELIMINAZIONE…' : 'ELIMINA DEFINITIVAMENTE'}
            </Text>
          </Pressable>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

function formatSecurityDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return 'Data non disponibile';
  }
  return date.toLocaleString('it-IT', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    padding: 20,
    paddingBottom: 46,
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
  demoCard: {
    borderRadius: radius.lg,
    padding: 18,
    backgroundColor: colors.limeSoft,
  },
  demoTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  demoBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 5,
  },
  serviceHubCard: {
    borderRadius: radius.lg,
    padding: 18,
    marginTop: 18,
    backgroundColor: colors.navy,
  },
  serviceHubHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  serviceHubCopy: {
    flex: 1,
    paddingRight: 12,
  },
  serviceHubEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.55,
  },
  serviceHubTitle: {
    color: colors.white,
    fontSize: 19,
    fontWeight: '900',
    marginTop: 4,
  },
  serviceHubBadge: {
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 6,
    backgroundColor: colors.lime,
  },
  serviceHubBadgeText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  serviceHubBody: {
    color: '#DDE7EC',
    fontSize: 12,
    lineHeight: 18,
    marginTop: 12,
  },
  serviceHubMeta: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.35,
    marginTop: 12,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 19,
    fontWeight: '900',
    marginTop: 22,
    marginBottom: 10,
  },
  card: {
    borderRadius: radius.lg,
    padding: 18,
    backgroundColor: colors.white,
  },
  protectionBadge: {
    alignSelf: 'flex-start',
    borderRadius: 999,
    backgroundColor: colors.limeSoft,
    paddingHorizontal: 10,
    paddingVertical: 6,
    marginBottom: 14,
  },
  protectionBadgeText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  label: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.45,
    marginBottom: 7,
  },
  readonlyField: {
    minHeight: 48,
    borderRadius: radius.md,
    paddingHorizontal: 14,
    marginBottom: 17,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.canvasMuted,
  },
  readonlyText: {
    flex: 1,
    color: colors.navy,
    fontSize: 13,
    fontWeight: '700',
  },
  verifiedText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    marginLeft: 8,
  },
  input: {
    height: 52,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: '#DCE2DA',
    paddingHorizontal: 14,
    marginBottom: 11,
    color: colors.navy,
    fontSize: 14,
    backgroundColor: colors.warmWhite,
  },
  primaryButton: {
    height: 50,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 2,
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  securityBadge: {
    alignSelf: 'flex-start',
    borderRadius: 999,
    backgroundColor: colors.limeSoft,
    paddingHorizontal: 10,
    paddingVertical: 6,
    marginBottom: 12,
  },
  securityBadgeText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  securitySummary: {
    borderRadius: radius.md,
    backgroundColor: colors.canvas,
    padding: 12,
    marginBottom: 14,
  },
  securitySummaryLabel: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  securitySummaryValue: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '800',
    marginTop: 4,
  },
  securitySummaryMeta: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '800',
    marginTop: 5,
  },
  cardTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  cardBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 5,
    marginBottom: 14,
  },
  secondaryButton: {
    height: 50,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.navy,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 2,
  },
  secondaryButtonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  disabledButton: {
    opacity: 0.5,
  },
  feedback: {
    borderRadius: radius.md,
    padding: 14,
    marginTop: 14,
    backgroundColor: colors.limeSoft,
  },
  feedbackError: {
    backgroundColor: '#FFE5E2',
  },
  feedbackText: {
    color: colors.navy,
    fontSize: 12,
    lineHeight: 17,
    fontWeight: '700',
  },
  feedbackErrorText: {
    color: colors.danger,
  },
  dangerCard: {
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: '#F1B9B3',
    padding: 18,
    backgroundColor: '#FFF8F7',
  },
  dangerTitle: {
    color: colors.danger,
    fontSize: 16,
    fontWeight: '900',
  },
  dangerBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 6,
    marginBottom: 14,
  },
  dangerInput: {
    height: 50,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: '#F1B9B3',
    paddingHorizontal: 14,
    color: colors.navy,
    fontSize: 13,
    fontWeight: '800',
    backgroundColor: colors.white,
  },
  deleteButton: {
    height: 50,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.danger,
    marginTop: 11,
  },
  deleteButtonText: {
    color: colors.white,
    fontSize: 10,
    fontWeight: '900',
  },
});
