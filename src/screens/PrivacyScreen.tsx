import { useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import * as FileSystem from 'expo-file-system/legacy';
import * as Sharing from 'expo-sharing';
import { LegalDocumentModal } from '../components/LegalDocumentModal';
import { usePrivacyRights } from '../hooks/usePrivacyRights';
import {
  PRIVACY_POLICY_VERSION,
  MINIMUM_AGE_VERSION,
  TERMS_VERSION,
  type LegalDocumentKind,
} from '../legalDocuments';
import type { PrivacyPreferences } from '../services/privacyService';
import type {
  PrivacyRightType,
  PrivacyRightsRequest,
} from '../services/privacyRightsService';
import { colors, radius } from '../theme';

const privacyRightOptions: Array<{
  type: PrivacyRightType;
  label: string;
}> = [
  { type: 'access', label: 'Accesso' },
  { type: 'rectification', label: 'Rettifica' },
  { type: 'portability', label: 'Portabilità' },
  { type: 'restriction', label: 'Limitazione' },
  { type: 'objection', label: 'Opposizione' },
  { type: 'erasure', label: 'Cancellazione' },
];

type Props = {
  email: string;
  isDemo: boolean;
  preferences: PrivacyPreferences | null;
  userId: string;
  onBack: () => void;
  onDeleteAccount: () => void;
  onExportData: () => Promise<{
    data?: Record<string, unknown>;
    error?: string;
  }>;
};

export function PrivacyScreen({
  email,
  isDemo,
  preferences,
  userId,
  onBack,
  onDeleteAccount,
  onExportData,
}: Props) {
  const [openDocument, setOpenDocument] =
    useState<LegalDocumentKind | null>(null);
  const [busy, setBusy] = useState<'export' | null>(null);
  const [feedback, setFeedback] = useState('');
  const [isError, setIsError] = useState(false);
  const [requestType, setRequestType] =
    useState<PrivacyRightType>('access');
  const [requestDetails, setRequestDetails] = useState('');
  const rights = usePrivacyRights(isDemo, userId);

  const exportData = async () => {
    if (isDemo) {
      setFeedback('L’esportazione è disponibile per gli account registrati.');
      setIsError(true);
      return;
    }

    setBusy('export');
    setFeedback('');
    const outcome = await onExportData();

    if (outcome.error || !outcome.data) {
      setBusy(null);
      setFeedback(outcome.error ?? 'Non è stato possibile preparare i dati.');
      setIsError(true);
      return;
    }

    try {
      if (!FileSystem.cacheDirectory || !(await Sharing.isAvailableAsync())) {
        throw new Error('Condivisione file non disponibile.');
      }

      const date = new Date().toISOString().slice(0, 10);
      const fileUri = `${FileSystem.cacheDirectory}leghevo-dati-${date}.json`;
      await FileSystem.writeAsStringAsync(
        fileUri,
        JSON.stringify(outcome.data, null, 2),
        { encoding: FileSystem.EncodingType.UTF8 },
      );
      await Sharing.shareAsync(fileUri, {
        dialogTitle: 'Condividi la tua copia dati LEGHEVO',
        mimeType: 'application/json',
        UTI: 'public.json',
      });
      setFeedback(
        outcome.data.exportCertificate
          ? 'Copia dati certificata e preparata in formato JSON.'
          : 'Copia dati preparata in formato JSON.',
      );
      setIsError(false);
    } catch {
      setFeedback(
        'I dati sono pronti, ma questo dispositivo non consente di condividere il file.',
      );
      setIsError(true);
    } finally {
      setBusy(null);
    }
  };

  const submitRightsRequest = async () => {
    const details = requestDetails.trim();
    if (
      ['rectification', 'restriction', 'objection', 'erasure'].includes(
        requestType,
      ) &&
      details.length < 10
    ) {
      setFeedback('Descrivi la richiesta con almeno 10 caratteri.');
      setIsError(true);
      return;
    }

    const outcome = await rights.submit(requestType, details);
    if (!('error' in outcome)) {
      setRequestDetails('');
    }
  };

  return (
    <View style={styles.root}>
      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
      >
        <View style={styles.header}>
          <Pressable onPress={onBack} style={styles.backButton}>
            <Text style={styles.backText}>‹</Text>
          </Pressable>
          <View style={styles.headerCopy}>
            <Text style={styles.eyebrow}>DATI E CONSENSI</Text>
            <Text style={styles.title}>Privacy</Text>
          </View>
        </View>

        <View style={styles.statusCard}>
          <View style={styles.statusPill}>
            <Text style={styles.statusPillText}>
              {isDemo
                ? 'ANTEPRIMA'
                : preferences?.protected
                  ? 'ACCETTAZIONE PROTETTA'
                  : 'DOCUMENTI REGISTRATI'}
            </Text>
          </View>
          <Text style={styles.statusTitle}>{email || 'Profilo demo'}</Text>
          <StatusRow
            date={preferences?.privacyAcknowledgedAt}
            label={`Informativa ${preferences?.privacyPolicyVersion ?? PRIVACY_POLICY_VERSION}`}
          />
          <StatusRow
            date={preferences?.termsAcceptedAt}
            label={`Termini ${preferences?.termsVersion ?? TERMS_VERSION}`}
          />
          <StatusRow
            date={preferences?.minimumAgeConfirmedAt}
            label={`Requisito età ${preferences?.minimumAgeVersion ?? MINIMUM_AGE_VERSION}`}
          />
          {preferences?.protected ? (
            <Text style={styles.certifiedRevision}>
              REVISIONE CERTIFICATA v{preferences.revision} ·{' '}
              {preferences.certifiedActionCount} OPERAZIONI REGISTRATE
            </Text>
          ) : null}
        </View>

        <Text style={styles.sectionTitle}>Documenti</Text>
        <View style={styles.card}>
          <DocumentRow
            label="Informativa privacy"
            onPress={() => setOpenDocument('privacy')}
            version={PRIVACY_POLICY_VERSION}
          />
          <DocumentRow
            label="Termini di utilizzo"
            onPress={() => setOpenDocument('terms')}
            version={TERMS_VERSION}
          />
          <View style={styles.publishedNote}>
            <Text style={styles.publishedNoteText}>
              Versioni pubblicate per il rilascio italiano del 29 luglio 2026.
            </Text>
          </View>
        </View>

        <Text style={styles.sectionTitle}>Comunicazioni</Text>
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Solo messaggi di servizio</Text>
          <Text style={styles.cardBody}>
            LEGHEVO usa email e notifiche tecniche per account, sicurezza,
            assistenza e attività di gioco. Newsletter e messaggi promozionali
            diretti non sono attivi.
          </Text>
        </View>

        <Text style={styles.sectionTitle}>I tuoi diritti</Text>
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Porta con te i tuoi dati</Text>
          <Text style={styles.cardBody}>
            Prepara una copia strutturata in formato JSON con profilo, consensi,
            leghe, squadre, formazioni e notifiche.
          </Text>
          {preferences?.exportProtected ? (
            <View style={styles.protectionStrip}>
              <Text style={styles.protectionTitle}>ESPORTAZIONE PROTETTA</Text>
              <Text style={styles.protectionBody}>
                {preferences.exportRevision > 0
                  ? `REVISIONE CERTIFICATA v${preferences.exportRevision} · ${preferences.certifiedExportCount} COPIE REGISTRATE`
                  : 'IMPRONTA SHA-256 E BLOCCO DEI DOPPI INVII ATTIVI'}
              </Text>
              {preferences.lastExportedAt ? (
                <Text style={styles.protectionBody}>
                  Ultima copia: {formatDate(preferences.lastExportedAt)}
                </Text>
              ) : null}
            </View>
          ) : null}
          <Pressable
            disabled={busy !== null}
            onPress={() => void exportData()}
            style={[styles.secondaryButton, busy && styles.disabledButton]}
          >
            {busy === 'export' ? (
              <ActivityIndicator color={colors.navy} />
            ) : (
              <Text style={styles.secondaryButtonText}>
                ESPORTA I MIEI DATI
              </Text>
            )}
          </Pressable>

          <View style={styles.divider} />

          <Text style={styles.cardTitle}>Cancellazione</Text>
          <Text style={styles.cardBody}>
            L’eliminazione definitiva e l’anonimizzazione dei risultati storici
            si trovano in Account e sicurezza.
          </Text>
          <Pressable onPress={onDeleteAccount} style={styles.linkButton}>
            <Text style={styles.linkText}>GESTISCI O ELIMINA L’ACCOUNT</Text>
          </Pressable>
        </View>

        <Text style={styles.sectionTitle}>Centro diritti privacy</Text>
        <View style={styles.card}>
          <View style={styles.rightsHeader}>
            <View style={styles.rightsHeaderCopy}>
              <Text style={styles.cardTitle}>Richiesta tracciata</Text>
              <Text style={styles.cardBody}>
                Scegli il diritto da esercitare. La richiesta conserva stato,
                cronologia e termine indicativo di gestione.
              </Text>
            </View>
            <View style={styles.openCountPill}>
              <Text style={styles.openCountValue}>
                {rights.center?.openCount ?? 0}
              </Text>
              <Text style={styles.openCountLabel}>APERTE</Text>
            </View>
          </View>

          <View style={styles.protectionStrip}>
            <Text style={styles.protectionTitle}>GESTIONE PROTETTA</Text>
            <Text style={styles.protectionBody}>
              Revisioni e blocco dei doppi invii attivi
            </Text>
          </View>

          <View style={styles.rightsOptions}>
            {privacyRightOptions.map((option) => (
              <Pressable
                key={option.type}
                disabled={rights.actionLoading}
                onPress={() => setRequestType(option.type)}
                style={[
                  styles.rightOption,
                  requestType === option.type && styles.rightOptionActive,
                ]}
              >
                <Text
                  style={[
                    styles.rightOptionText,
                    requestType === option.type &&
                      styles.rightOptionTextActive,
                  ]}
                >
                  {option.label.toUpperCase()}
                </Text>
              </Pressable>
            ))}
          </View>

          <TextInput
            editable={!isDemo && !rights.actionLoading}
            maxLength={2000}
            multiline
            onChangeText={setRequestDetails}
            placeholder={requestPlaceholder(requestType)}
            placeholderTextColor={colors.muted}
            style={styles.requestInput}
            textAlignVertical="top"
            value={requestDetails}
          />
          <Text style={styles.characterCount}>
            {requestDetails.length}/2000
          </Text>

          <Pressable
            disabled={isDemo || rights.actionLoading}
            onPress={() => void submitRightsRequest()}
            style={[
              styles.primaryButton,
              (isDemo || rights.actionLoading) && styles.disabledButton,
            ]}
          >
            {rights.actionLoading ? (
              <ActivityIndicator color={colors.navy} />
            ) : (
              <Text style={styles.primaryButtonText}>INVIA RICHIESTA</Text>
            )}
          </Pressable>

          <View style={styles.slaNote}>
            <Text style={styles.slaNoteText}>
              Termine indicativo: 30 giorni dalla ricezione. Eventuali
              proroghe o risposte definitive saranno registrate nella
              cronologia.
            </Text>
          </View>
        </View>

        <Text style={styles.sectionTitle}>Le tue richieste</Text>
        {rights.loading ? (
          <View style={styles.loadingCard}>
            <ActivityIndicator color={colors.navy} />
          </View>
        ) : rights.error ? (
          <View style={[styles.feedback, styles.feedbackError]}>
            <Text style={[styles.feedbackText, styles.feedbackErrorText]}>
              {rights.error}
            </Text>
          </View>
        ) : rights.center?.requests.length ? (
          rights.center.requests.map((request) => (
            <PrivacyRequestCard
              key={request.id}
              actionLoading={rights.actionLoading}
              onCancel={() =>
                void rights.cancel(request.id, request.revision)
              }
              request={request}
            />
          ))
        ) : (
          <View style={styles.emptyCard}>
            <Text style={styles.emptyTitle}>Nessuna richiesta</Text>
            <Text style={styles.emptyBody}>
              Le richieste inviate compariranno qui con scadenza, stato e
              cronologia.
            </Text>
          </View>
        )}

        {rights.notice || rights.actionError ? (
          <View
            style={[
              styles.feedback,
              rights.actionError && styles.feedbackError,
            ]}
          >
            <Text
              style={[
                styles.feedbackText,
                rights.actionError && styles.feedbackErrorText,
              ]}
            >
              {rights.actionError || rights.notice}
            </Text>
          </View>
        ) : null}

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
      </ScrollView>

      <LegalDocumentModal
        kind={openDocument}
        onClose={() => setOpenDocument(null)}
      />
    </View>
  );
}

function StatusRow({ date, label }: { date?: string | null; label: string }) {
  return (
    <View style={styles.statusRow}>
      <View style={styles.statusDot} />
      <View style={styles.statusRowCopy}>
        <Text style={styles.statusLabel}>{label}</Text>
        <Text style={styles.statusDate}>
          {date ? `Registrato il ${formatDate(date)}` : 'Da completare'}
        </Text>
      </View>
    </View>
  );
}

function DocumentRow({
  label,
  onPress,
  version,
}: {
  label: string;
  onPress: () => void;
  version: string;
}) {
  return (
    <Pressable onPress={onPress} style={styles.documentRow}>
      <View style={styles.documentCopy}>
        <Text style={styles.documentLabel}>{label}</Text>
        <Text style={styles.documentVersion}>Versione {version}</Text>
      </View>
      <Text style={styles.documentArrow}>›</Text>
    </Pressable>
  );
}

function PrivacyRequestCard({
  actionLoading,
  onCancel,
  request,
}: {
  actionLoading: boolean;
  onCancel: () => void;
  request: PrivacyRightsRequest;
}) {
  const latestEvent = request.events.at(-1);
  return (
    <View style={styles.requestCard}>
      <View style={styles.requestCardHeader}>
        <View style={styles.requestCardCopy}>
          <Text style={styles.requestType}>
            {requestTypeLabel(request.requestType)}
          </Text>
          <Text style={styles.requestDate}>
            Inviata il {formatDate(request.submittedAt)}
          </Text>
        </View>
        <View
          style={[
            styles.requestStatus,
            request.status === 'fulfilled' && styles.requestStatusDone,
            request.status === 'rejected' && styles.requestStatusError,
            request.status === 'cancelled' && styles.requestStatusMuted,
          ]}
        >
          <Text style={styles.requestStatusText}>
            {requestStatusLabel(request.status)}
          </Text>
        </View>
      </View>

      {request.details ? (
        <Text style={styles.requestDetails}>{request.details}</Text>
      ) : null}

      <View style={styles.requestMeta}>
        <Text style={styles.requestMetaLabel}>TERMINE INDICATIVO</Text>
        <Text style={styles.requestMetaValue}>{formatDate(request.dueAt)}</Text>
      </View>

      <View style={styles.requestMeta}>
        <Text style={styles.requestMetaLabel}>REVISIONE CERTIFICATA</Text>
        <Text style={styles.requestMetaValue}>v{request.revision}</Text>
      </View>

      {request.responseNote ? (
        <View style={styles.responseNote}>
          <Text style={styles.responseNoteLabel}>RISPOSTA</Text>
          <Text style={styles.responseNoteText}>{request.responseNote}</Text>
        </View>
      ) : null}

      {latestEvent ? (
        <Text style={styles.timelineText}>
          Ultimo aggiornamento: {requestStatusLabel(latestEvent.status)} ·{' '}
          {formatDate(latestEvent.occurredAt)}
        </Text>
      ) : null}

      {request.canCancel ? (
        <Pressable
          disabled={actionLoading}
          onPress={onCancel}
          style={[
            styles.cancelRequestButton,
            actionLoading && styles.disabledButton,
          ]}
        >
          <Text style={styles.cancelRequestText}>ANNULLA RICHIESTA</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

function requestPlaceholder(type: PrivacyRightType) {
  if (type === 'access') {
    return 'Dettagli facoltativi sui dati a cui vuoi accedere';
  }
  if (type === 'portability') {
    return 'Dettagli facoltativi sul formato o sull’ambito richiesto';
  }
  if (type === 'rectification') {
    return 'Indica quali dati ritieni inesatti e come correggerli';
  }
  if (type === 'restriction') {
    return 'Descrivi il trattamento che vuoi limitare e il motivo';
  }
  if (type === 'objection') {
    return 'Descrivi il trattamento a cui ti opponi e il motivo';
  }
  return 'Descrivi quali dati o trattamenti vuoi cancellare';
}

function requestTypeLabel(type: PrivacyRightType) {
  return (
    privacyRightOptions.find((option) => option.type === type)?.label ??
    'Richiesta privacy'
  );
}

function requestStatusLabel(status: PrivacyRightsRequest['status']) {
  if (status === 'submitted') {
    return 'Ricevuta';
  }
  if (status === 'in_review') {
    return 'In lavorazione';
  }
  if (status === 'fulfilled') {
    return 'Completata';
  }
  if (status === 'rejected') {
    return 'Respinta';
  }
  return 'Annullata';
}

function formatDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return new Intl.DateTimeFormat('it-IT', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date);
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
  statusCard: {
    borderRadius: radius.xl,
    padding: 20,
    backgroundColor: colors.navy,
  },
  statusPill: {
    alignSelf: 'flex-start',
    height: 26,
    borderRadius: 13,
    paddingHorizontal: 11,
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  statusPillText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  statusTitle: {
    color: colors.warmWhite,
    fontSize: 16,
    fontWeight: '900',
    marginTop: 17,
    marginBottom: 6,
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 12,
  },
  statusDot: {
    width: 9,
    height: 9,
    borderRadius: 5,
    backgroundColor: colors.lime,
    marginRight: 10,
  },
  statusRowCopy: {
    flex: 1,
  },
  statusLabel: {
    color: colors.warmWhite,
    fontSize: 11,
    fontWeight: '800',
  },
  statusDate: {
    color: colors.mutedLight,
    fontSize: 9,
    marginTop: 3,
  },
  certifiedRevision: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.45,
    marginTop: 16,
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
  documentRow: {
    minHeight: 58,
    flexDirection: 'row',
    alignItems: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#DDE2DC',
  },
  documentCopy: {
    flex: 1,
  },
  documentLabel: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '800',
  },
  documentVersion: {
    color: colors.muted,
    fontSize: 9,
    marginTop: 3,
  },
  documentArrow: {
    color: colors.muted,
    fontSize: 25,
  },
  publishedNote: {
    borderRadius: radius.sm,
    padding: 12,
    marginTop: 14,
    backgroundColor: colors.limeSoft,
  },
  publishedNoteText: {
    color: colors.navy,
    fontSize: 10,
    lineHeight: 15,
    fontWeight: '700',
  },
  cardTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  cardBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 5,
  },
  rightsHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  rightsHeaderCopy: {
    flex: 1,
    paddingRight: 12,
  },
  openCountPill: {
    minWidth: 54,
    borderRadius: radius.md,
    alignItems: 'center',
    paddingHorizontal: 10,
    paddingVertical: 8,
    backgroundColor: colors.navy,
  },
  openCountValue: {
    color: colors.lime,
    fontSize: 17,
    fontWeight: '900',
  },
  openCountLabel: {
    color: colors.warmWhite,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 2,
  },
  protectionStrip: {
    borderRadius: radius.md,
    paddingHorizontal: 12,
    paddingVertical: 10,
    marginTop: 14,
    backgroundColor: colors.limeSoft,
  },
  protectionTitle: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  protectionBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 16,
    marginTop: 2,
  },
  rightsOptions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 7,
    marginTop: 16,
  },
  rightOption: {
    minHeight: 34,
    borderRadius: 17,
    borderWidth: 1,
    borderColor: '#D7DDD7',
    justifyContent: 'center',
    paddingHorizontal: 12,
    backgroundColor: colors.canvas,
  },
  rightOptionActive: {
    borderColor: colors.navy,
    backgroundColor: colors.navy,
  },
  rightOptionText: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  rightOptionTextActive: {
    color: colors.lime,
  },
  requestInput: {
    minHeight: 110,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: '#D7DDD7',
    color: colors.navy,
    fontSize: 12,
    lineHeight: 18,
    padding: 13,
    marginTop: 14,
    backgroundColor: colors.canvas,
  },
  characterCount: {
    color: colors.muted,
    fontSize: 8,
    textAlign: 'right',
    marginTop: 5,
  },
  slaNote: {
    borderRadius: radius.sm,
    padding: 11,
    marginTop: 13,
    backgroundColor: colors.limeSoft,
  },
  slaNoteText: {
    color: colors.navy,
    fontSize: 9,
    lineHeight: 14,
    fontWeight: '700',
  },
  loadingCard: {
    minHeight: 100,
    borderRadius: radius.lg,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  emptyCard: {
    borderRadius: radius.lg,
    padding: 20,
    backgroundColor: colors.white,
  },
  emptyTitle: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  emptyBody: {
    color: colors.muted,
    fontSize: 10,
    lineHeight: 15,
    marginTop: 5,
  },
  requestCard: {
    borderRadius: radius.lg,
    padding: 18,
    marginBottom: 10,
    backgroundColor: colors.white,
  },
  requestCardHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  requestCardCopy: {
    flex: 1,
    paddingRight: 10,
  },
  requestType: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  requestDate: {
    color: colors.muted,
    fontSize: 8,
    marginTop: 3,
  },
  requestStatus: {
    borderRadius: 12,
    paddingHorizontal: 9,
    paddingVertical: 6,
    backgroundColor: colors.limeSoft,
  },
  requestStatusDone: {
    backgroundColor: colors.lime,
  },
  requestStatusError: {
    backgroundColor: '#FFE5E2',
  },
  requestStatusMuted: {
    backgroundColor: '#E7E9E7',
  },
  requestStatusText: {
    color: colors.navy,
    fontSize: 7,
    fontWeight: '900',
  },
  requestDetails: {
    color: colors.navy,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 14,
  },
  requestMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: '#DDE2DC',
    marginTop: 14,
    paddingTop: 12,
  },
  requestMetaLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  requestMetaValue: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '800',
  },
  responseNote: {
    borderRadius: radius.sm,
    padding: 11,
    marginTop: 12,
    backgroundColor: colors.limeSoft,
  },
  responseNoteLabel: {
    color: colors.navy,
    fontSize: 7,
    fontWeight: '900',
  },
  responseNoteText: {
    color: colors.navy,
    fontSize: 10,
    lineHeight: 15,
    marginTop: 4,
  },
  timelineText: {
    color: colors.muted,
    fontSize: 8,
    lineHeight: 13,
    marginTop: 11,
  },
  cancelRequestButton: {
    minHeight: 40,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.navy,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 13,
  },
  cancelRequestText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  primaryButton: {
    height: 50,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 16,
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  secondaryButton: {
    height: 50,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.navy,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 15,
  },
  secondaryButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  disabledButton: {
    opacity: 0.5,
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: '#DDE2DC',
    marginVertical: 20,
  },
  linkButton: {
    minHeight: 42,
    justifyContent: 'center',
    marginTop: 5,
  },
  linkText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
    textDecorationLine: 'underline',
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
    fontSize: 11,
    lineHeight: 16,
    fontWeight: '700',
  },
  feedbackErrorText: {
    color: colors.danger,
  },
});
