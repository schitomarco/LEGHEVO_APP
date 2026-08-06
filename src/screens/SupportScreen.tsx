import { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Linking,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSupportCenter } from '../hooks/useSupportCenter';
import { LEGHEVO_LEGAL_PROFILE } from '../legalProfile';
import type {
  SupportCategory,
  SupportRequest,
  SupportRequestStatus,
} from '../services/supportService';
import { colors, radius } from '../theme';
import type { LeagueSummary } from '../types';

type Props = {
  userId: string | null;
  isDemo: boolean;
  leagues: LeagueSummary[];
  onBack: () => void;
};

const categories: Array<{ value: SupportCategory; label: string }> = [
  { value: 'account', label: 'Account' },
  { value: 'league', label: 'Lega' },
  { value: 'auction_market', label: 'Asta e mercato' },
  { value: 'lineup_results', label: 'Formazione e risultati' },
  { value: 'technical', label: 'Problema tecnico' },
  { value: 'billing', label: 'Premium e pagamenti' },
  { value: 'safety', label: 'Sicurezza' },
  { value: 'other', label: 'Altro' },
];

const faqs = [
  {
    id: 'lineup-lock',
    question: 'Quando si blocca la formazione?',
    answer:
      'Alla prima partita reale della giornata di Serie A. Dopo la scadenza LEGHEVO usa la distinta consegnata oppure, se disponibile, recupera automaticamente l’ultima formazione valida.',
  },
  {
    id: 'missing-score',
    question: 'Perché un calciatore risulta senza voto?',
    answer:
      'Il provider può non avere ancora chiuso la partita o il turno. I risultati restano provvisori finché tutti i dati necessari non sono definitivi.',
  },
  {
    id: 'substitution',
    question: 'Come funzionano le sostituzioni?',
    answer:
      'LEGHEVO segue l’ordine della panchina, la compatibilità del ruolo e il limite impostato dal Presidente. Nel Live viene sempre indicato perché un cambio è stato applicato o bloccato.',
  },
  {
    id: 'invite',
    question: 'Il codice invito non funziona',
    answer:
      'Controlla che il Presidente non abbia chiuso gli inviti o avviato la competizione. Un codice rigenerato sostituisce immediatamente quello precedente.',
  },
  {
    id: 'provider-correction',
    question: 'Un voto o un risultato è sbagliato',
    answer:
      'Il Presidente può riaprire il singolo risultato, motivare la correzione e ufficializzarlo nuovamente. Tutte le revisioni restano tracciate.',
  },
  {
    id: 'privacy',
    question: 'Come esercito un diritto privacy?',
    answer:
      'Usa Profilo → Privacy → Centro diritti. Le richieste privacy hanno un flusso dedicato e non devono essere inviate come normali ticket di assistenza.',
  },
];

export function SupportScreen({
  userId,
  isDemo,
  leagues,
  onBack,
}: Props) {
  const support = useSupportCenter(userId, isDemo);
  const [openFaqId, setOpenFaqId] = useState<string | null>(null);
  const [openRequestId, setOpenRequestId] = useState<string | null>(null);
  const [category, setCategory] = useState<SupportCategory>('technical');
  const [leagueId, setLeagueId] = useState<string | null>(null);
  const [subject, setSubject] = useState('');
  const [message, setMessage] = useState('');
  const [replyDrafts, setReplyDrafts] = useState<Record<string, string>>({});
  const [localError, setLocalError] = useState('');

  const createRequest = async () => {
    const cleanSubject = subject.trim();
    const cleanMessage = message.trim();
    if (cleanSubject.length < 5) {
      setLocalError('Scrivi un oggetto di almeno 5 caratteri.');
      return;
    }
    if (cleanMessage.length < 10) {
      setLocalError('Descrivi il problema con almeno 10 caratteri.');
      return;
    }

    setLocalError('');
    const outcome = await support.create({
      category,
      leagueId,
      subject: cleanSubject,
      message: cleanMessage,
    });
    if (!outcome.error) {
      setSubject('');
      setMessage('');
      setLeagueId(null);
      if (outcome.data?.id) {
        setOpenRequestId(outcome.data.id);
      }
    }
  };

  const sendReply = async (request: SupportRequest) => {
    const requestId = request.id;
    const reply = (replyDrafts[requestId] ?? '').trim();
    if (reply.length < 2) {
      setLocalError('Scrivi una risposta di almeno 2 caratteri.');
      return;
    }
    setLocalError('');
    const outcome = await support.reply(
      requestId,
      reply,
      request.revision,
    );
    if (!outcome.error) {
      setReplyDrafts((current) => ({ ...current, [requestId]: '' }));
    }
  };

  const confirmClose = (request: SupportRequest) => {
    Alert.alert(
      'Chiudere la richiesta?',
      'La conversazione resterà consultabile, ma non potrai aggiungere altre risposte.',
      [
        { text: 'Annulla', style: 'cancel' },
        {
          text: 'Chiudi',
          style: 'destructive',
          onPress: () =>
            void support.close(request.id, request.revision),
        },
      ],
    );
  };

  const openEmail = () => {
    const subjectLine = encodeURIComponent('Assistenza LEGHEVO');
    void Linking.openURL(
      `mailto:${LEGHEVO_LEGAL_PROFILE.supportEmail}?subject=${subjectLine}`,
    );
  };

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      keyboardShouldPersistTaps="handled"
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.header}>
        <Pressable
          accessibilityLabel="Torna al profilo"
          onPress={onBack}
          style={styles.backButton}
        >
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>AIUTO E SEGNALAZIONI</Text>
          <Text style={styles.title}>Assistenza</Text>
        </View>
        <Pressable
          accessibilityLabel="Aggiorna richieste"
          disabled={support.loading}
          onPress={() => void support.refresh()}
          style={styles.refreshButton}
        >
          <Text style={styles.refreshText}>↻</Text>
        </Pressable>
      </View>

      <View style={styles.heroCard}>
        <View style={styles.heroTop}>
          <View>
            <Text style={styles.heroEyebrow}>CENTRO ASSISTENZA</Text>
            <Text style={styles.heroTitle}>La panchina tecnica.</Text>
          </View>
          <View style={styles.openPill}>
            <Text style={styles.openValue}>
              {support.center?.openCount ?? 0}
            </Text>
            <Text style={styles.openLabel}>APERTE</Text>
          </View>
        </View>
        <Text style={styles.heroBody}>
          Consulta le risposte rapide oppure apri una pratica e seguine gli
          aggiornamenti senza uscire da LEGHEVO.
        </Text>
        {support.center?.protection.guardedActionsReady &&
        support.center.protection.revisionControlReady &&
        support.center.protection.idempotencyReady ? (
          <View style={styles.protectionPill}>
            <Text style={styles.protectionPillText}>
              GESTIONE PROTETTA · ANTI-DOPPIO TOCCO
            </Text>
          </View>
        ) : null}
        {(support.center?.waitingUserCount ?? 0) > 0 ? (
          <View style={styles.waitingBanner}>
            <Text style={styles.waitingBannerText}>
              {support.center?.waitingUserCount}{' '}
              {support.center?.waitingUserCount === 1
                ? 'richiesta aspetta'
                : 'richieste aspettano'}{' '}
              una tua risposta.
            </Text>
          </View>
        ) : null}
      </View>

      <Text style={styles.sectionTitle}>Risposte rapide</Text>
      <View style={styles.card}>
        {faqs.map((faq) => {
          const isOpen = openFaqId === faq.id;
          return (
            <Pressable
              key={faq.id}
              onPress={() => setOpenFaqId(isOpen ? null : faq.id)}
              style={styles.faqRow}
            >
              <View style={styles.faqHeader}>
                <Text style={styles.faqQuestion}>{faq.question}</Text>
                <Text style={styles.faqArrow}>{isOpen ? '−' : '+'}</Text>
              </View>
              {isOpen ? (
                <Text style={styles.faqAnswer}>{faq.answer}</Text>
              ) : null}
            </Pressable>
          );
        })}
      </View>

      <Text style={styles.sectionTitle}>Nuova richiesta</Text>
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Di cosa hai bisogno?</Text>
        <Text style={styles.cardBody}>
          Scegli la categoria e indica, se serve, la lega interessata.
        </Text>

        <View style={styles.chipWrap}>
          {categories.map((option) => (
            <Pressable
              key={option.value}
              disabled={support.actionLoading}
              onPress={() => setCategory(option.value)}
              style={[
                styles.chip,
                category === option.value && styles.chipActive,
              ]}
            >
              <Text
                style={[
                  styles.chipText,
                  category === option.value && styles.chipTextActive,
                ]}
              >
                {option.label}
              </Text>
            </Pressable>
          ))}
        </View>

        {leagues.length > 0 ? (
          <>
            <Text style={styles.inputLabel}>LEGA INTERESSATA · FACOLTATIVA</Text>
            <View style={styles.chipWrap}>
              <Pressable
                disabled={support.actionLoading}
                onPress={() => setLeagueId(null)}
                style={[
                  styles.chip,
                  leagueId === null && styles.chipActive,
                ]}
              >
                <Text
                  style={[
                    styles.chipText,
                    leagueId === null && styles.chipTextActive,
                  ]}
                >
                  Nessuna
                </Text>
              </Pressable>
              {leagues.map((league) => (
                <Pressable
                  key={league.id}
                  disabled={support.actionLoading}
                  onPress={() => setLeagueId(league.id)}
                  style={[
                    styles.chip,
                    leagueId === league.id && styles.chipActive,
                  ]}
                >
                  <Text
                    numberOfLines={1}
                    style={[
                      styles.chipText,
                      leagueId === league.id && styles.chipTextActive,
                    ]}
                  >
                    {league.name}
                  </Text>
                </Pressable>
              ))}
            </View>
          </>
        ) : null}

        <Text style={styles.inputLabel}>OGGETTO</Text>
        <TextInput
          editable={!support.actionLoading}
          maxLength={100}
          onChangeText={setSubject}
          placeholder="Es. Il risultato non si aggiorna"
          placeholderTextColor={colors.muted}
          style={styles.input}
          value={subject}
        />

        <Text style={styles.inputLabel}>MESSAGGIO</Text>
        <TextInput
          editable={!support.actionLoading}
          maxLength={3000}
          multiline
          onChangeText={setMessage}
          placeholder="Descrivi cosa è successo e in quale punto dell’app."
          placeholderTextColor={colors.muted}
          style={[styles.input, styles.messageInput]}
          textAlignVertical="top"
          value={message}
        />
        <Text style={styles.counter}>{message.length}/3000</Text>

        <Pressable
          disabled={support.actionLoading}
          onPress={() => void createRequest()}
          style={[
            styles.primaryButton,
            support.actionLoading && styles.disabledButton,
          ]}
        >
          {support.actionLoading ? (
            <ActivityIndicator color={colors.navy} />
          ) : (
            <Text style={styles.primaryButtonText}>INVIA RICHIESTA</Text>
          )}
        </Pressable>

        <Pressable onPress={openEmail} style={styles.emailButton}>
          <Text style={styles.emailButtonText}>
            O SCRIVI A {LEGHEVO_LEGAL_PROFILE.supportEmail.toUpperCase()}
          </Text>
        </Pressable>
      </View>

      {localError || support.error || support.notice ? (
        <View
          style={[
            styles.feedback,
            Boolean(localError || support.error) && styles.feedbackError,
          ]}
        >
          <Text
            style={[
              styles.feedbackText,
              Boolean(localError || support.error) &&
                styles.feedbackTextError,
            ]}
          >
            {localError || support.error || support.notice}
          </Text>
        </View>
      ) : null}

      <View style={styles.requestsHeader}>
        <Text style={styles.sectionTitle}>Le tue richieste</Text>
        <Text style={styles.requestsCount}>
          {support.center?.totalCount ?? 0} TOTALI
        </Text>
      </View>

      {support.loading && !support.center ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.navy} />
          <Text style={styles.loadingText}>Recupero le pratiche…</Text>
        </View>
      ) : (support.center?.requests.length ?? 0) === 0 ? (
        <View style={styles.emptyCard}>
          <Text style={styles.emptyTitle}>Nessuna pratica aperta</Text>
          <Text style={styles.emptyBody}>
            Quando invii una richiesta, stato e risposte compariranno qui.
          </Text>
        </View>
      ) : (
        <View style={styles.requestList}>
          {support.center?.requests.map((request) => (
            <SupportRequestCard
              key={request.id}
              actionLoading={support.actionLoading}
              expanded={openRequestId === request.id}
              onClose={() => confirmClose(request)}
              onReply={() => void sendReply(request)}
              onToggle={() =>
                setOpenRequestId(
                  openRequestId === request.id ? null : request.id,
                )
              }
              reply={replyDrafts[request.id] ?? ''}
              request={request}
              setReply={(value) =>
                setReplyDrafts((current) => ({
                  ...current,
                  [request.id]: value,
                }))
              }
            />
          ))}
        </View>
      )}
    </ScrollView>
  );
}

function SupportRequestCard({
  request,
  expanded,
  reply,
  actionLoading,
  onToggle,
  setReply,
  onReply,
  onClose,
}: {
  request: SupportRequest;
  expanded: boolean;
  reply: string;
  actionLoading: boolean;
  onToggle: () => void;
  setReply: (value: string) => void;
  onReply: () => void;
  onClose: () => void;
}) {
  return (
    <View style={styles.requestCard}>
      <Pressable onPress={onToggle} style={styles.requestHeader}>
        <View style={styles.requestHeaderCopy}>
          <View style={styles.requestMetaRow}>
            <View
              style={[
                styles.statusPill,
                request.status === 'waiting_user' && styles.statusPillWaiting,
                request.status === 'resolved' && styles.statusPillResolved,
                request.status === 'closed' && styles.statusPillClosed,
              ]}
            >
              <Text style={styles.statusPillText}>
                {statusLabel(request.status)}
              </Text>
            </View>
            <Text style={styles.requestDate}>
              {formatDate(request.updatedAt)}
            </Text>
          </View>
          <Text style={styles.requestSubject}>{request.subject}</Text>
          <Text style={styles.requestContext}>
            {categoryLabel(request.category)}
            {request.leagueName ? ` · ${request.leagueName}` : ''}
          </Text>
          {request.protected ? (
            <Text style={styles.requestRevision}>
              REVISIONE CERTIFICATA v{request.revision}
            </Text>
          ) : null}
        </View>
        <Text style={styles.requestArrow}>{expanded ? '−' : '+'}</Text>
      </Pressable>

      {expanded ? (
        <View style={styles.requestBody}>
          <View style={styles.timeline}>
            {request.messages.map((item) => (
              <View
                key={item.id}
                style={[
                  styles.messageBubble,
                  item.authorType === 'support' &&
                    styles.messageBubbleSupport,
                ]}
              >
                <View style={styles.messageTop}>
                  <Text style={styles.messageAuthor}>
                    {item.authorType === 'support' ? 'ASSISTENZA' : 'TU'}
                  </Text>
                  <Text style={styles.messageDate}>
                    {formatDateTime(item.createdAt)}
                  </Text>
                </View>
                <Text
                  style={[
                    styles.messageBody,
                    item.authorType === 'support' &&
                      styles.messageBodySupport,
                  ]}
                >
                  {item.body}
                </Text>
              </View>
            ))}
          </View>

          {request.canReply ? (
            <>
              <Text style={styles.inputLabel}>AGGIUNGI UNA RISPOSTA</Text>
              <TextInput
                editable={!actionLoading}
                maxLength={3000}
                multiline
                onChangeText={setReply}
                placeholder="Scrivi qui…"
                placeholderTextColor={colors.muted}
                style={[styles.input, styles.replyInput]}
                textAlignVertical="top"
                value={reply}
              />
              <Pressable
                disabled={actionLoading}
                onPress={onReply}
                style={[
                  styles.darkButton,
                  actionLoading && styles.disabledButton,
                ]}
              >
                <Text style={styles.darkButtonText}>INVIA RISPOSTA</Text>
              </Pressable>
            </>
          ) : (
            <View style={styles.closedNote}>
              <Text style={styles.closedNoteText}>
                Pratica conclusa. La conversazione resta disponibile.
              </Text>
            </View>
          )}

          {request.canClose ? (
            <Pressable
              disabled={actionLoading}
              onPress={onClose}
              style={styles.closeButton}
            >
              <Text style={styles.closeButtonText}>CHIUDI LA RICHIESTA</Text>
            </Pressable>
          ) : null}
        </View>
      ) : null}
    </View>
  );
}

function statusLabel(status: SupportRequestStatus) {
  switch (status) {
    case 'in_progress':
      return 'IN LAVORAZIONE';
    case 'waiting_user':
      return 'ATTENDE TE';
    case 'resolved':
      return 'RISOLTA';
    case 'closed':
      return 'CHIUSA';
    default:
      return 'INVIATA';
  }
}

function categoryLabel(category: SupportCategory) {
  return (
    categories.find((option) => option.value === category)?.label ?? 'Altro'
  );
}

function formatDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '—';
  }
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: 'short',
  }).format(date);
}

function formatDateTime(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '—';
  }
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
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
  header: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  backButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
    marginRight: 12,
  },
  backText: {
    color: colors.navy,
    fontSize: 31,
    lineHeight: 34,
  },
  headerCopy: {
    flex: 1,
  },
  eyebrow: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.6,
  },
  title: {
    color: colors.navy,
    fontSize: 29,
    fontWeight: '900',
    marginTop: 3,
  },
  refreshButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  refreshText: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
  },
  heroCard: {
    borderRadius: radius.xl,
    backgroundColor: colors.navy,
    padding: 22,
    marginTop: 22,
  },
  heroTop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
  },
  heroEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.6,
  },
  heroTitle: {
    color: colors.warmWhite,
    fontSize: 23,
    fontWeight: '900',
    marginTop: 8,
  },
  heroBody: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 20,
    marginTop: 12,
  },
  protectionPill: {
    alignSelf: 'flex-start',
    borderRadius: 999,
    backgroundColor: colors.navySoft,
    paddingHorizontal: 11,
    paddingVertical: 7,
    marginTop: 14,
  },
  protectionPillText: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  openPill: {
    minWidth: 62,
    borderRadius: 16,
    backgroundColor: colors.lime,
    paddingHorizontal: 10,
    paddingVertical: 8,
    alignItems: 'center',
  },
  openValue: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  openLabel: {
    color: colors.navy,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 1,
  },
  waitingBanner: {
    borderRadius: radius.md,
    backgroundColor: colors.navySoft,
    padding: 12,
    marginTop: 16,
  },
  waitingBannerText: {
    color: colors.lime,
    fontSize: 12,
    lineHeight: 18,
    fontWeight: '800',
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
    marginTop: 24,
    marginBottom: 9,
  },
  card: {
    borderRadius: radius.lg,
    backgroundColor: colors.white,
    padding: 16,
  },
  faqRow: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#DFE4DC',
    paddingVertical: 14,
  },
  faqHeader: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  faqQuestion: {
    flex: 1,
    color: colors.navy,
    fontSize: 14,
    fontWeight: '800',
    paddingRight: 12,
  },
  faqArrow: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
  },
  faqAnswer: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 20,
    marginTop: 10,
    paddingRight: 24,
  },
  cardTitle: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  cardBody: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 6,
  },
  chipWrap: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginTop: 15,
  },
  chip: {
    minHeight: 34,
    maxWidth: '100%',
    borderRadius: 17,
    borderWidth: 1,
    borderColor: '#D7DDD4',
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  chipActive: {
    borderColor: colors.navy,
    backgroundColor: colors.navy,
  },
  chipText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '800',
  },
  chipTextActive: {
    color: colors.lime,
  },
  inputLabel: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.45,
    marginTop: 18,
    marginBottom: 7,
  },
  input: {
    minHeight: 48,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: '#D7DDD4',
    backgroundColor: colors.canvas,
    color: colors.navy,
    fontSize: 13,
    paddingHorizontal: 13,
    paddingVertical: 11,
  },
  messageInput: {
    minHeight: 120,
  },
  replyInput: {
    minHeight: 86,
  },
  counter: {
    color: colors.muted,
    fontSize: 9,
    textAlign: 'right',
    marginTop: 5,
  },
  primaryButton: {
    minHeight: 50,
    borderRadius: radius.md,
    backgroundColor: colors.lime,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 16,
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  emailButton: {
    minHeight: 44,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 6,
  },
  emailButtonText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  disabledButton: {
    opacity: 0.55,
  },
  feedback: {
    borderRadius: radius.md,
    backgroundColor: '#EAF7D1',
    padding: 13,
    marginTop: 12,
  },
  feedbackError: {
    backgroundColor: '#FCE7E5',
  },
  feedbackText: {
    color: '#355312',
    fontSize: 12,
    lineHeight: 18,
    fontWeight: '700',
  },
  feedbackTextError: {
    color: '#8A2823',
  },
  requestsHeader: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
  },
  requestsCount: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    marginBottom: 11,
  },
  loadingCard: {
    minHeight: 100,
    borderRadius: radius.lg,
    backgroundColor: colors.white,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 9,
  },
  loadingText: {
    color: colors.muted,
    fontSize: 12,
    fontWeight: '700',
  },
  emptyCard: {
    borderRadius: radius.lg,
    backgroundColor: colors.white,
    padding: 20,
  },
  emptyTitle: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  emptyBody: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 6,
  },
  requestList: {
    gap: 10,
  },
  requestCard: {
    borderRadius: radius.lg,
    backgroundColor: colors.white,
    overflow: 'hidden',
  },
  requestHeader: {
    minHeight: 104,
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
  },
  requestHeaderCopy: {
    flex: 1,
  },
  requestMetaRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusPill: {
    borderRadius: 10,
    backgroundColor: '#E9EDE7',
    paddingHorizontal: 8,
    paddingVertical: 5,
  },
  statusPillWaiting: {
    backgroundColor: colors.lime,
  },
  statusPillResolved: {
    backgroundColor: '#DCEFD7',
  },
  statusPillClosed: {
    backgroundColor: '#E1E5E0',
  },
  statusPillText: {
    color: colors.navy,
    fontSize: 7,
    fontWeight: '900',
  },
  requestDate: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '700',
    marginLeft: 8,
  },
  requestSubject: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
    marginTop: 9,
  },
  requestContext: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '700',
    marginTop: 4,
  },
  requestRevision: {
    color: colors.success,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
    marginTop: 7,
  },
  requestArrow: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
    marginLeft: 12,
  },
  requestBody: {
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: '#DFE4DC',
    padding: 16,
  },
  timeline: {
    gap: 9,
  },
  messageBubble: {
    alignSelf: 'flex-end',
    width: '88%',
    borderRadius: radius.md,
    backgroundColor: colors.lime,
    padding: 12,
  },
  messageBubbleSupport: {
    alignSelf: 'flex-start',
    backgroundColor: colors.navy,
  },
  messageTop: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  messageAuthor: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  messageDate: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '700',
  },
  messageBody: {
    color: colors.navy,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 6,
  },
  messageBodySupport: {
    color: colors.warmWhite,
  },
  darkButton: {
    minHeight: 46,
    borderRadius: radius.md,
    backgroundColor: colors.navy,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 10,
  },
  darkButtonText: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
  },
  closeButton: {
    minHeight: 42,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 5,
  },
  closeButtonText: {
    color: '#9A332D',
    fontSize: 9,
    fontWeight: '900',
  },
  closedNote: {
    borderRadius: radius.md,
    backgroundColor: colors.canvas,
    padding: 12,
    marginTop: 14,
  },
  closedNoteText: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    textAlign: 'center',
  },
});
