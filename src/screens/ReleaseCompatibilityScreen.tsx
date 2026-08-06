import { Pressable, SafeAreaView, StyleSheet, Text, View } from 'react-native';
import { Logo } from '../components/Logo';
import type { ReleaseCompatibility } from '../services/releaseCompatibilityService';
import { colors, radius } from '../theme';

type Props = {
  compatibility: ReleaseCompatibility;
  loading: boolean;
  onRetry: () => void | Promise<void>;
};

export function ReleaseCompatibilityScreen({
  compatibility,
  loading,
  onRetry,
}: Props) {
  const unavailable = compatibility.status === 'unavailable';
  const rolloutHeld = compatibility.status === 'held';
  const rolloutPaused = compatibility.status === 'paused';
  const range = compatibility.minSupportedVersion && compatibility.maxSupportedVersion
    ? `${compatibility.minSupportedVersion} – ${compatibility.maxSupportedVersion}`
    : compatibility.activeVersion ?? 'versione certificata';

  return (
    <SafeAreaView style={styles.safeArea}>
      <View style={styles.container}>
        <Logo size={78} />
        <Text style={styles.eyebrow}>BARRIERA DI RILASCIO</Text>
        <Text style={styles.title}>
          {unavailable
            ? 'Controllo non disponibile'
            : rolloutHeld
              ? 'Ingresso programmato'
              : rolloutPaused
                ? 'Distribuzione in pausa'
                : 'Aggiornamento richiesto'}
        </Text>
        <Text style={styles.subtitle}>
          {unavailable
            ? 'Non riusciamo a verificare il contratto di rilascio. Per sicurezza l’app resta in panchina finché il controllo non torna disponibile.'
            : rolloutHeld
              ? 'Questa installazione non è ancora nel gruppo abilitato. Il rollout procede per scaglioni controllati, senza salti di formazione.'
              : rolloutPaused
                ? 'Il kill switch operativo ha fermato questa release. L’app resta in panchina finché la Direzione non riapre il rollout.'
                : 'La panchina è pronta, ma questa versione non può scendere in campo con lo schema attualmente certificato.'}
        </Text>

        <View style={styles.card}>
          <Text style={styles.cardLabel}>VERSIONE INSTALLATA</Text>
          <Text style={styles.cardValue}>{compatibility.applicationVersion}</Text>
          <Text style={styles.cardLabel}>
            {unavailable ? 'CONTRATTO SERVER' : 'VERSIONI AMMESSE'}
          </Text>
          <Text style={styles.cardValue}>
            {unavailable ? 'Verifica temporaneamente non disponibile' : range}
          </Text>
          {compatibility.rolloutProtected ? (
            <Text style={styles.notice}>
              Rollout {compatibility.rolloutStage ?? 'controllato'} · {compatibility.rolloutExposurePercentage ?? 0}% abilitato
              {compatibility.rolloutBucket === null ? '' : ` · gruppo ${compatibility.rolloutBucket}`}
            </Text>
          ) : null}
          {compatibility.disasterRecoveryStatus ? (
            <Text style={styles.notice}>
              Recovery {compatibility.disasterRecoveryStatus} · checkpoint {compatibility.disasterRecoveryCheckpointGeneration ?? 0} · drill {compatibility.disasterRecoveryDrillGeneration ?? 0}
            </Text>
          ) : null}
          {compatibility.physicalBackupStatus ? (
            <Text style={styles.notice}>
              Backup fisico {compatibility.physicalBackupStatus} · artefatto {compatibility.physicalBackupGeneration ?? 0} · restore esterno {compatibility.physicalBackupRehearsalGeneration ?? 0}
            </Text>
          ) : null}
          {compatibility.serviceReturnStatus ? (
            <Text style={styles.notice}>
              Ritorno in servizio {compatibility.serviceReturnStatus} · modalità {compatibility.serviceReturnMode ?? 'recovery'} · generazione {compatibility.serviceReturnGeneration ?? 0} · {compatibility.serviceReturnCheckCount ?? 0}/8 controlli
            </Text>
          ) : null}
          {compatibility.productionReadinessStatus ? (
            <Text style={styles.notice}>
              Go-live {compatibility.productionReadinessStatus} · generazione {compatibility.productionReadinessGeneration ?? 0} · {compatibility.productionReadinessCheckCount ?? 0}/10 controlli
            </Text>
          ) : null}
          {compatibility.deliveryAuditStatus ? (
            <Text style={styles.notice}>
              Audit consegne {compatibility.deliveryAuditStatus} · generazione {compatibility.deliveryAuditGeneration ?? 0} · sequenza {compatibility.deliveryAuditSequence ?? 0}
            </Text>
          ) : null}
          {compatibility.consumerDeliveryStatus ? (
            <Text style={styles.notice}>
              Ack applicativi {compatibility.consumerDeliveryStatus} · {compatibility.consumerReceiptCount ?? 0}/{compatibility.consumerExpectedReceiptCount ?? 0} ricevute
            </Text>
          ) : null}
          {compatibility.outboxStatus ? (
            <Text style={styles.notice}>
              Outbox {compatibility.outboxStatus} · {compatibility.outboxPendingCount ?? 0} in attesa · {compatibility.outboxDeadLetterCount ?? 0} in dead-letter
            </Text>
          ) : null}
          {compatibility.rollbackActive ? (
            <Text style={styles.notice}>
              È attivo un rollback controllato. Installa la versione indicata
              dalla Direzione LEGHEVO.
            </Text>
          ) : null}
        </View>

        <Pressable
          disabled={loading}
          onPress={() => void onRetry()}
          style={[styles.button, loading && styles.buttonDisabled]}
        >
          <Text style={styles.buttonText}>
            {loading ? 'CONTROLLO…' : 'RIPROVA IL CONTROLLO'}
          </Text>
        </Pressable>
        <Text style={styles.footer}>
          Codice: {compatibility.reasonCode}
        </Text>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: { flex: 1, backgroundColor: colors.navy },
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
    letterSpacing: 0.7,
    marginTop: 28,
  },
  title: {
    color: colors.warmWhite,
    fontSize: 28,
    fontWeight: '900',
    marginTop: 8,
    textAlign: 'center',
  },
  subtitle: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 20,
    marginTop: 9,
    textAlign: 'center',
  },
  card: {
    width: '100%',
    borderRadius: radius.lg,
    backgroundColor: colors.navySoft,
    borderWidth: 1,
    borderColor: colors.navyLine,
    marginTop: 24,
    padding: 20,
  },
  cardLabel: {
    color: colors.mutedLight,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.5,
    marginTop: 7,
  },
  cardValue: {
    color: colors.warmWhite,
    fontSize: 18,
    fontWeight: '900',
    marginTop: 4,
    marginBottom: 9,
  },
  notice: {
    color: colors.limeSoft,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 8,
  },
  button: {
    width: '100%',
    height: 54,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 18,
  },
  buttonDisabled: { opacity: 0.5 },
  buttonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  footer: {
    color: colors.mutedLight,
    fontSize: 10,
    marginTop: 16,
  },
});
