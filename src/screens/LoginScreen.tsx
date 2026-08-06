import { useState } from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import type { AuthOutcome, RegistrationChoices } from '../hooks/useAuth';
import { LegalDocumentModal } from '../components/LegalDocumentModal';
import { Logo } from '../components/Logo';
import type { LegalDocumentKind } from '../legalDocuments';
import { colors, radius } from '../theme';

type AuthMode = 'welcome' | 'signin' | 'signup' | 'forgot';

type Props = {
  backendConfigured: boolean;
  onDemoLogin: () => void;
  onResetPassword: (email: string) => Promise<AuthOutcome>;
  onSignIn: (email: string, password: string) => Promise<AuthOutcome>;
  onSignUp: (
    email: string,
    password: string,
    displayName: string,
    choices: RegistrationChoices,
  ) => Promise<AuthOutcome>;
};

export function LoginScreen({
  backendConfigured,
  onDemoLogin,
  onResetPassword,
  onSignIn,
  onSignUp,
}: Props) {
  const [mode, setMode] = useState<AuthMode>('welcome');
  const [displayName, setDisplayName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [feedback, setFeedback] = useState('');
  const [isError, setIsError] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [minimumAgeConfirmed, setMinimumAgeConfirmed] = useState(false);
  const [privacyAcknowledged, setPrivacyAcknowledged] = useState(false);
  const [termsAccepted, setTermsAccepted] = useState(false);
  const [openDocument, setOpenDocument] =
    useState<LegalDocumentKind | null>(null);

  const changeMode = (nextMode: AuthMode) => {
    setMode(nextMode);
    setFeedback('');
    setIsError(false);
  };

  const submit = async () => {
    if (!email.includes('@')) {
      setFeedback('Inserisci un indirizzo email valido.');
      setIsError(true);
      return;
    }
    if (mode !== 'forgot' && password.length < 6) {
      setFeedback('La password deve avere almeno 6 caratteri.');
      setIsError(true);
      return;
    }
    if (mode === 'signup' && displayName.trim().length < 2) {
      setFeedback('Dicci almeno come chiamarti nello spogliatoio.');
      setIsError(true);
      return;
    }
    if (
      mode === 'signup' &&
      (!minimumAgeConfirmed || !privacyAcknowledged || !termsAccepted)
    ) {
      setFeedback(
        'Per registrarti devi confermare il requisito di età, leggere l’informativa e accettare i Termini.',
      );
      setIsError(true);
      return;
    }

    setSubmitting(true);
    setFeedback('');
    const outcome =
      mode === 'signup'
          ? await onSignUp(email, password, displayName, {
            minimumAgeConfirmed,
            privacyAcknowledged,
            termsAccepted,
          })
        : mode === 'forgot'
          ? await onResetPassword(email)
          : await onSignIn(email, password);
    setSubmitting(false);

    if (outcome.error) {
      setFeedback(outcome.error);
      setIsError(true);
    } else if (outcome.notice) {
      setFeedback(outcome.notice);
      setIsError(false);
    }
  };

  return (
    <SafeAreaView style={styles.safeArea}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        style={styles.keyboardView}
      >
        <ScrollView
          contentContainerStyle={styles.container}
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
        >
          <View style={styles.pill}>
            <Text style={styles.pillText}>
              {backendConfigured ? 'SPOGLIATOIO ONLINE' : 'PROTOTIPO DEMO'}
            </Text>
          </View>

          <Logo size={mode === 'welcome' ? 112 : 72} />

          {mode === 'welcome' ? (
            <>
              <View style={styles.copy}>
                <Text style={styles.title}>La panchina è pronta.</Text>
                <Text style={styles.subtitle}>Tu prova almeno a esserlo.</Text>
              </View>

              <View style={styles.actions}>
                {backendConfigured ? (
                  <>
                    <Pressable
                      onPress={() => changeMode('signup')}
                      style={styles.primaryButton}
                    >
                      <Text style={styles.primaryButtonText}>
                        Registrati con email
                      </Text>
                    </Pressable>
                    <Pressable
                      onPress={() => changeMode('signin')}
                      style={styles.authButton}
                    >
                      <Text style={styles.authButtonText}>
                        Accedi con email
                      </Text>
                    </Pressable>
                  </>
                ) : (
                  <Pressable onPress={onDemoLogin} style={styles.primaryButton}>
                    <Text style={styles.primaryButtonText}>Entra nella demo</Text>
                  </Pressable>
                )}

                <Pressable onPress={onDemoLogin} style={styles.demoButton}>
                  <Text style={styles.demoButtonText}>
                    {backendConfigured
                      ? 'Oppure prova senza account'
                      : 'Nessun account richiesto'}
                  </Text>
                </Pressable>
              </View>
            </>
          ) : (
            <View style={styles.form}>
              <Text style={styles.formTitle}>
                {mode === 'signup'
                  ? 'Crea il tuo profilo'
                  : mode === 'forgot'
                    ? 'Recupera l’account'
                    : 'Bentornato, mister'}
              </Text>
              <Text style={styles.formSubtitle}>
                {mode === 'signup'
                  ? 'Due minuti e sei ufficialmente giudicabile.'
                  : mode === 'forgot'
                    ? 'Ti mandiamo il link. Tu prova a ricordare almeno l’email.'
                  : 'Le scuse della scorsa giornata sono ancora agli atti.'}
              </Text>

              {mode === 'signup' && (
                <TextInput
                  autoCapitalize="words"
                  onChangeText={setDisplayName}
                  placeholder="Nome visualizzato"
                  placeholderTextColor={colors.muted}
                  style={styles.input}
                  value={displayName}
                />
              )}
              <TextInput
                autoCapitalize="none"
                autoComplete="email"
                keyboardType="email-address"
                onChangeText={setEmail}
                placeholder="Email"
                placeholderTextColor={colors.muted}
                style={styles.input}
                value={email}
              />
              {mode !== 'forgot' && (
                <TextInput
                  autoCapitalize="none"
                  autoComplete={
                    mode === 'signup' ? 'new-password' : 'current-password'
                  }
                  onChangeText={setPassword}
                  onSubmitEditing={() => void submit()}
                  placeholder="Password"
                  placeholderTextColor={colors.muted}
                  secureTextEntry
                  style={styles.input}
                  value={password}
                />
              )}

              {mode === 'signup' && (
                <View style={styles.consents}>
                  <RegistrationConsentRow
                    checked={minimumAgeConfirmed}
                    detail="Almeno 18 anni, oppure 14–17 anni con autorizzazione di un genitore o tutore."
                    label="Confermo il requisito di età *"
                    onChange={() =>
                      setMinimumAgeConfirmed((value) => !value)
                    }
                  />
                  <RegistrationConsentRow
                    checked={privacyAcknowledged}
                    label="Ho letto l’Informativa privacy *"
                    onChange={() =>
                      setPrivacyAcknowledged((value) => !value)
                    }
                    onOpen={() => setOpenDocument('privacy')}
                  />
                  <RegistrationConsentRow
                    checked={termsAccepted}
                    label="Accetto i Termini di utilizzo *"
                    onChange={() => setTermsAccepted((value) => !value)}
                    onOpen={() => setOpenDocument('terms')}
                  />
                </View>
              )}

              {mode === 'signin' && (
                <Pressable onPress={() => changeMode('forgot')}>
                  <Text style={styles.forgotText}>Password dimenticata?</Text>
                </Pressable>
              )}

              {feedback ? (
                <Text style={[styles.feedback, isError && styles.feedbackError]}>
                  {feedback}
                </Text>
              ) : null}

              <Pressable
                disabled={submitting}
                onPress={() => void submit()}
                style={[
                  styles.primaryButton,
                  submitting && styles.buttonDisabled,
                ]}
              >
                <Text style={styles.primaryButtonText}>
                  {submitting
                    ? 'Controllo formazione…'
                    : mode === 'signup'
                      ? 'Crea account'
                      : mode === 'forgot'
                        ? 'Invia link di recupero'
                      : 'Entra'}
                </Text>
              </Pressable>

              {mode !== 'forgot' && (
                <Pressable
                  onPress={() =>
                    changeMode(mode === 'signup' ? 'signin' : 'signup')
                  }
                >
                  <Text style={styles.switchText}>
                    {mode === 'signup'
                      ? 'Hai già un account? Accedi'
                      : 'Prima convocazione? Registrati'}
                  </Text>
                </Pressable>
              )}
              {mode === 'forgot' && (
                <Pressable onPress={() => changeMode('signin')}>
                  <Text style={styles.switchText}>Torna all’accesso</Text>
                </Pressable>
              )}
              <Pressable onPress={() => changeMode('welcome')}>
                <Text style={styles.backText}>‹ Torna indietro</Text>
              </Pressable>
            </View>
          )}
        </ScrollView>
      </KeyboardAvoidingView>

      <LegalDocumentModal
        kind={openDocument}
        onClose={() => setOpenDocument(null)}
      />
    </SafeAreaView>
  );
}

type RegistrationConsentRowProps = {
  checked: boolean;
  detail?: string;
  label: string;
  onChange: () => void;
  onOpen?: () => void;
};

function RegistrationConsentRow({
  checked,
  detail,
  label,
  onChange,
  onOpen,
}: RegistrationConsentRowProps) {
  return (
    <View style={styles.consentRow}>
      <Pressable onPress={onChange} style={styles.consentMain}>
        <View style={[styles.checkbox, checked && styles.checkboxChecked]}>
          <Text style={styles.checkmark}>{checked ? '✓' : ''}</Text>
        </View>
        <View style={styles.consentCopy}>
          <Text style={styles.consentLabel}>{label}</Text>
          {detail ? <Text style={styles.consentDetail}>{detail}</Text> : null}
        </View>
      </Pressable>
      {onOpen ? (
        <Pressable onPress={onOpen}>
          <Text style={styles.readText}>LEGGI</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.navy,
  },
  keyboardView: {
    flex: 1,
  },
  container: {
    flexGrow: 1,
    alignItems: 'center',
    paddingHorizontal: 24,
    paddingTop: 22,
    paddingBottom: 20,
  },
  pill: {
    paddingHorizontal: 20,
    height: 32,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navySoft,
    marginBottom: 28,
  },
  pillText: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  copy: {
    alignItems: 'center',
    marginTop: 34,
  },
  title: {
    color: colors.warmWhite,
    fontSize: 22,
    fontWeight: '900',
  },
  subtitle: {
    color: colors.mutedLight,
    fontSize: 15,
    marginTop: 8,
  },
  actions: {
    width: '100%',
    gap: 12,
    marginTop: 'auto',
  },
  authButton: {
    height: 56,
    borderRadius: radius.md,
    backgroundColor: colors.warmWhite,
    alignItems: 'center',
    justifyContent: 'center',
  },
  authButtonText: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '800',
  },
  primaryButton: {
    width: '100%',
    height: 56,
    borderRadius: radius.md,
    backgroundColor: colors.lime,
    alignItems: 'center',
    justifyContent: 'center',
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  demoButton: {
    height: 44,
    alignItems: 'center',
    justifyContent: 'center',
  },
  demoButtonText: {
    color: colors.mutedLight,
    fontSize: 13,
    fontWeight: '700',
  },
  form: {
    width: '100%',
    marginTop: 28,
  },
  formTitle: {
    color: colors.warmWhite,
    fontSize: 25,
    fontWeight: '900',
  },
  formSubtitle: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 7,
    marginBottom: 18,
  },
  input: {
    height: 54,
    borderRadius: radius.md,
    backgroundColor: colors.warmWhite,
    color: colors.navy,
    fontSize: 15,
    marginBottom: 11,
    paddingHorizontal: 16,
  },
  consents: {
    gap: 8,
    marginTop: 2,
    marginBottom: 13,
  },
  consentRow: {
    minHeight: 49,
    borderRadius: radius.sm,
    paddingHorizontal: 11,
    paddingVertical: 9,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.navySoft,
  },
  consentMain: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  checkbox: {
    width: 21,
    height: 21,
    borderRadius: 6,
    borderWidth: 1.5,
    borderColor: colors.mutedLight,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 9,
  },
  checkboxChecked: {
    borderColor: colors.lime,
    backgroundColor: colors.lime,
  },
  checkmark: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  consentCopy: {
    flex: 1,
  },
  consentLabel: {
    color: colors.warmWhite,
    fontSize: 10,
    lineHeight: 14,
    fontWeight: '700',
  },
  consentDetail: {
    color: colors.mutedLight,
    fontSize: 8,
    lineHeight: 12,
    marginTop: 2,
  },
  readText: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
    marginLeft: 8,
  },
  feedback: {
    color: colors.lime,
    fontSize: 12,
    lineHeight: 17,
    marginBottom: 12,
  },
  feedbackError: {
    color: '#FF8D86',
  },
  forgotText: {
    color: colors.lime,
    fontSize: 11,
    fontWeight: '800',
    textAlign: 'right',
    marginTop: -2,
    marginBottom: 14,
  },
  buttonDisabled: {
    opacity: 0.55,
  },
  switchText: {
    color: colors.warmWhite,
    fontSize: 13,
    fontWeight: '800',
    textAlign: 'center',
    marginTop: 18,
  },
  backText: {
    color: colors.mutedLight,
    fontSize: 13,
    textAlign: 'center',
    marginTop: 20,
  },
});
