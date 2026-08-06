import { useState } from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  SafeAreaView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { Logo } from '../components/Logo';
import type { AuthOutcome } from '../hooks/useAuth';
import { colors, radius } from '../theme';

type Props = {
  error: string;
  onCancel: () => void | Promise<void>;
  onComplete: (password: string) => Promise<AuthOutcome>;
};

export function PasswordRecoveryScreen({
  error,
  onCancel,
  onComplete,
}: Props) {
  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [feedback, setFeedback] = useState(error);
  const [submitting, setSubmitting] = useState(false);

  const submit = async () => {
    if (password.length < 8) {
      setFeedback('La nuova password deve avere almeno 8 caratteri.');
      return;
    }
    if (password !== confirmation) {
      setFeedback('Le due password non coincidono.');
      return;
    }

    setSubmitting(true);
    const outcome = await onComplete(password);
    setSubmitting(false);
    setFeedback(outcome.error ?? outcome.notice ?? '');
  };

  return (
    <SafeAreaView style={styles.safeArea}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        style={styles.keyboardView}
      >
        <View style={styles.container}>
          <Logo size={76} />
          <Text style={styles.eyebrow}>RECUPERO ACCOUNT</Text>
          <Text style={styles.title}>Nuova password</Text>
          <Text style={styles.subtitle}>
            Questa volta segnala il cambio prima del novantesimo.
          </Text>

          <TextInput
            autoCapitalize="none"
            autoComplete="new-password"
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
            onChangeText={setConfirmation}
            onSubmitEditing={() => void submit()}
            placeholder="Ripeti la nuova password"
            placeholderTextColor={colors.muted}
            secureTextEntry
            style={styles.input}
            value={confirmation}
          />

          {feedback ? <Text style={styles.feedback}>{feedback}</Text> : null}

          <Pressable
            disabled={submitting}
            onPress={() => void submit()}
            style={[
              styles.primaryButton,
              submitting && styles.disabledButton,
            ]}
          >
            <Text style={styles.primaryButtonText}>
              {submitting ? 'AGGIORNAMENTO…' : 'SALVA NUOVA PASSWORD'}
            </Text>
          </Pressable>
          <Pressable onPress={() => void onCancel()}>
            <Text style={styles.cancelText}>Annulla e torna all’accesso</Text>
          </Pressable>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
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
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 25,
  },
  eyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.6,
    marginTop: 30,
  },
  title: {
    color: colors.warmWhite,
    fontSize: 27,
    fontWeight: '900',
    marginTop: 7,
  },
  subtitle: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 19,
    textAlign: 'center',
    marginTop: 7,
    marginBottom: 22,
  },
  input: {
    width: '100%',
    height: 54,
    borderRadius: radius.md,
    paddingHorizontal: 16,
    marginBottom: 11,
    color: colors.navy,
    fontSize: 14,
    backgroundColor: colors.warmWhite,
  },
  feedback: {
    width: '100%',
    color: '#FF9B95',
    fontSize: 12,
    lineHeight: 17,
    marginBottom: 12,
  },
  primaryButton: {
    width: '100%',
    height: 54,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  disabledButton: {
    opacity: 0.5,
  },
  cancelText: {
    color: colors.mutedLight,
    fontSize: 12,
    fontWeight: '700',
    marginTop: 20,
  },
});
