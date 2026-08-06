import { useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { LegalDocumentModal } from '../components/LegalDocumentModal';
import type { AuthOutcome } from '../hooks/useAuth';
import {
  PRIVACY_POLICY_VERSION,
  TERMS_VERSION,
  type LegalDocumentKind,
} from '../legalDocuments';
import { colors, radius } from '../theme';

type Props = {
  error: string;
  onAccept: () => Promise<AuthOutcome>;
  onLogout: () => void | Promise<void>;
};

export function PrivacyOnboardingScreen({
  error,
  onAccept,
  onLogout,
}: Props) {
  const [privacyRead, setPrivacyRead] = useState(false);
  const [termsAccepted, setTermsAccepted] = useState(false);
  const [minimumAgeConfirmed, setMinimumAgeConfirmed] = useState(false);
  const [openDocument, setOpenDocument] =
    useState<LegalDocumentKind | null>(null);
  const [feedback, setFeedback] = useState(error);
  const [submitting, setSubmitting] = useState(false);

  const submit = async () => {
    if (!minimumAgeConfirmed || !privacyRead || !termsAccepted) {
      setFeedback(
        'Per continuare devi confermare il requisito di età, leggere l’informativa e accettare i Termini.',
      );
      return;
    }

    setSubmitting(true);
    setFeedback('');
    const outcome = await onAccept();
    setSubmitting(false);
    if (outcome.error) {
      setFeedback(outcome.error);
    }
  };

  return (
    <SafeAreaView style={styles.safeArea}>
      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
      >
        <View style={styles.pill}>
          <Text style={styles.pillText}>ACCETTAZIONE PROTETTA</Text>
        </View>

        <Text style={styles.title}>Prima del fischio d’inizio.</Text>
        <Text style={styles.subtitle}>
          Abbiamo pubblicato i documenti definitivi di LEGHEVO. La presa
          visione viene registrata con revisione protetta e resta sincronizzata
          sui tuoi dispositivi.
        </Text>

        <View style={styles.versionCard}>
          <Text style={styles.versionText}>
            Informativa {PRIVACY_POLICY_VERSION}
          </Text>
          <Text style={styles.versionText}>Termini {TERMS_VERSION}</Text>
        </View>

        <ConsentRow
          checked={minimumAgeConfirmed}
          label="Ho almeno 18 anni oppure almeno 14 anni e l’autorizzazione di un genitore o tutore"
          onChange={() => setMinimumAgeConfirmed((value) => !value)}
          required
        />
        <ConsentRow
          checked={privacyRead}
          label="Ho letto l’Informativa privacy"
          onChange={() => setPrivacyRead((value) => !value)}
          onOpen={() => setOpenDocument('privacy')}
          required
        />
        <ConsentRow
          checked={termsAccepted}
          label="Accetto i Termini di utilizzo"
          onChange={() => setTermsAccepted((value) => !value)}
          onOpen={() => setOpenDocument('terms')}
          required
        />
        {feedback ? (
          <View style={styles.feedback}>
            <Text style={styles.feedbackText}>{feedback}</Text>
          </View>
        ) : null}

        <Pressable
          disabled={submitting}
          onPress={() => void submit()}
          style={[
            styles.primaryButton,
            (!minimumAgeConfirmed ||
              !privacyRead ||
              !termsAccepted ||
              submitting) &&
              styles.disabledButton,
          ]}
        >
          {submitting ? (
            <ActivityIndicator color={colors.navy} />
          ) : (
            <Text style={styles.primaryButtonText}>ACCETTA E CONTINUA</Text>
          )}
        </Pressable>

        <Pressable onPress={onLogout} style={styles.logoutButton}>
          <Text style={styles.logoutText}>Esci dal profilo</Text>
        </Pressable>
      </ScrollView>

      <LegalDocumentModal
        kind={openDocument}
        onClose={() => setOpenDocument(null)}
      />
    </SafeAreaView>
  );
}

type ConsentRowProps = {
  checked: boolean;
  label: string;
  onChange: () => void;
  onOpen?: () => void;
  optionalDetail?: string;
  required?: boolean;
};

function ConsentRow({
  checked,
  label,
  onChange,
  onOpen,
  optionalDetail,
  required,
}: ConsentRowProps) {
  return (
    <View style={styles.consentCard}>
      <Pressable onPress={onChange} style={styles.consentMain}>
        <View style={[styles.checkbox, checked && styles.checkboxChecked]}>
          <Text style={styles.checkmark}>{checked ? '✓' : ''}</Text>
        </View>
        <View style={styles.consentCopy}>
          <Text style={styles.consentLabel}>
            {label} {required ? '*' : ''}
          </Text>
          {optionalDetail ? (
            <Text style={styles.optionalDetail}>{optionalDetail}</Text>
          ) : null}
        </View>
      </Pressable>
      {onOpen ? (
        <Pressable onPress={onOpen} style={styles.openButton}>
          <Text style={styles.openText}>LEGGI</Text>
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
  content: {
    paddingHorizontal: 22,
    paddingTop: 26,
    paddingBottom: 34,
  },
  pill: {
    alignSelf: 'flex-start',
    height: 29,
    borderRadius: 15,
    paddingHorizontal: 13,
    justifyContent: 'center',
    backgroundColor: colors.navySoft,
  },
  pillText: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  title: {
    color: colors.warmWhite,
    fontSize: 29,
    fontWeight: '900',
    marginTop: 24,
  },
  subtitle: {
    color: colors.mutedLight,
    fontSize: 14,
    lineHeight: 21,
    marginTop: 9,
    marginBottom: 18,
  },
  versionCard: {
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.navyLine,
    padding: 14,
    marginBottom: 13,
    gap: 5,
  },
  versionText: {
    color: colors.mutedLight,
    fontSize: 10,
    fontWeight: '800',
  },
  consentCard: {
    borderRadius: radius.md,
    padding: 15,
    marginBottom: 11,
    backgroundColor: colors.warmWhite,
  },
  consentMain: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  checkbox: {
    width: 24,
    height: 24,
    borderRadius: 7,
    borderWidth: 2,
    borderColor: colors.muted,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 11,
  },
  checkboxChecked: {
    borderColor: colors.navy,
    backgroundColor: colors.lime,
  },
  checkmark: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  consentCopy: {
    flex: 1,
  },
  consentLabel: {
    color: colors.navy,
    fontSize: 13,
    lineHeight: 18,
    fontWeight: '800',
  },
  optionalDetail: {
    color: colors.muted,
    fontSize: 10,
    lineHeight: 15,
    marginTop: 4,
  },
  openButton: {
    alignSelf: 'flex-start',
    marginTop: 11,
    marginLeft: 35,
  },
  openText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    textDecorationLine: 'underline',
  },
  feedback: {
    borderRadius: radius.md,
    padding: 13,
    marginTop: 3,
    backgroundColor: '#FFE5E2',
  },
  feedbackText: {
    color: colors.danger,
    fontSize: 11,
    lineHeight: 16,
    fontWeight: '700',
  },
  primaryButton: {
    height: 54,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 15,
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  disabledButton: {
    opacity: 0.55,
  },
  logoutButton: {
    height: 46,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 8,
  },
  logoutText: {
    color: colors.mutedLight,
    fontSize: 12,
    fontWeight: '700',
  },
});
