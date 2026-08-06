import { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useLeagueMembers } from '../hooks/useLeagueMembers';
import { useLiveAuction } from '../hooks/useLiveAuction';
import { colors, radius } from '../theme';
import type { AppScreen, LeagueSummary } from '../types';

type Props = {
  currentUserId: string | null;
  league: LeagueSummary | null;
  onNavigate: (screen: AppScreen) => void;
};

export function AuctionScreen({
  currentUserId,
  league,
  onNavigate,
}: Props) {
  const auction = useLiveAuction(league, currentUserId);
  const members = useLeagueMembers(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const [message, setMessage] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [secondsLeft, setSecondsLeft] = useState(0);
  const [bidIncrement, setBidIncrement] = useState('1');
  const [bidSeconds, setBidSeconds] = useState('15');

  const isAdmin =
    Boolean(league?.isDemo) ||
    league?.currentRole === 'admin' ||
    members.members.some(
      (member) =>
        member.userId === currentUserId && member.role === 'admin',
    );
  const currentItem = auction.state.currentItem;
  const auctionStatus = auction.state.auction?.status;
  const isPaused = auctionStatus === 'paused';

  useEffect(() => {
    if (!auction.state.auction) {
      return;
    }
    setBidIncrement(String(auction.state.auction.bidIncrement));
    setBidSeconds(String(auction.state.auction.bidSeconds));
  }, [auction.state.auction?.id]);

  useEffect(() => {
    const calculate = () => {
      if (isPaused || !currentItem?.expiresAt) {
        setSecondsLeft(0);
        return;
      }
      setSecondsLeft(
        Math.max(
          0,
          Math.ceil(
            (new Date(currentItem.expiresAt).getTime() - Date.now()) / 1000,
          ),
        ),
      );
    };

    calculate();
    const timer = setInterval(calculate, 500);
    return () => clearInterval(timer);
  }, [currentItem?.expiresAt, isPaused]);

  const currentPrice =
    currentItem?.highestBid ?? currentItem?.openingPrice ?? 0;
  const minimumIncrement = auction.state.auction?.bidIncrement ?? 1;
  const bidOptions = [
    minimumIncrement,
    minimumIncrement * 2,
    minimumIncrement * 5,
  ];
  // I pulsanti indicano l'aumento reale rispetto all'offerta mostrata.
  // Anche il primo rilancio deve quindi partire dalla base d'asta visibile,
  // non da una base virtuale ridotta del rilancio minimo.
  const bidBase = currentPrice;
  const isLeading =
    Boolean(auction.state.myTeam) &&
    currentItem?.highestBidTeamId === auction.state.myTeam?.id;

  const coachMessage = useMemo(() => {
    if (message) {
      return message;
    }
    if (isLeading) {
      return `Sei in testa a ${currentPrice}. Adesso fai quello tranquillo.`;
    }
    if (currentItem?.highestBidTeamName) {
      return `${currentItem.highestBidTeamName} guida a ${currentPrice}. Qualcuno vuole reagire?`;
    }
    return 'La base è servita. Chi rompe il silenzio?';
  }, [
    currentItem?.highestBidTeamName,
    currentPrice,
    isLeading,
    message,
  ]);

  if (!league) {
    return (
      <View style={styles.centerRoot}>
        <Text style={styles.centerTitle}>Prima scegli una lega.</Text>
        <Pressable
          onPress={() => onNavigate('home')}
          style={styles.primaryButton}
        >
          <Text style={styles.primaryButtonText}>TORNA ALLA HOME</Text>
        </Pressable>
      </View>
    );
  }

  const openRoom = async () => {
    const settings = parseAuctionSettings(bidIncrement, bidSeconds);
    if ('error' in settings) {
      setMessage(settings.error);
      return;
    }
    setSubmitting(true);
    setMessage('');
    const outcome = await auction.openRoom(
      settings.bidIncrement,
      settings.bidSeconds,
    );
    setSubmitting(false);
    if (outcome.error) {
      setMessage(outcome.error);
    }
  };

  const saveConfiguration = async () => {
    const settings = parseAuctionSettings(bidIncrement, bidSeconds);
    if ('error' in settings) {
      setMessage(settings.error);
      return;
    }
    setSubmitting(true);
    setMessage('');
    const outcome = await auction.configure(
      settings.bidIncrement,
      settings.bidSeconds,
    );
    setSubmitting(false);
    setMessage(
      outcome.error ??
        'Regia aggiornata. Il martello adesso batte con il ritmo giusto.',
    );
  };

  const runControl = async (
    action: 'pause' | 'resume' | 'cancel_item' | 'complete',
  ) => {
    setSubmitting(true);
    setMessage('');
    const outcome = await auction.control(action);
    setSubmitting(false);
    if (outcome.error) {
      setMessage(outcome.error);
      return;
    }

    const messages = {
      pause: 'Asta in pausa. Respirate, ma non fate mercato sottobanco.',
      resume: 'Asta ripresa. Tornano a volare crediti.',
      cancel_item: 'Lotto annullato. Il calciatore torna tra i disponibili.',
      complete: 'Asta terminata. Le rose possono entrare in campo.',
    };
    setMessage(messages[action]);
  };

  const confirmCancelItem = () => {
    Alert.alert(
      'Annullare questo lotto?',
      'Le offerte verranno ignorate e il calciatore tornerà disponibile.',
      [
        { text: 'No, continua', style: 'cancel' },
        {
          text: 'Annulla lotto',
          style: 'destructive',
          onPress: () => void runControl('cancel_item'),
        },
      ],
    );
  };

  const confirmCompleteAuction = () => {
    Alert.alert(
      'Terminare definitivamente l’asta?',
      'La lega passerà allo stato attivo. Potrai aprire una nuova sessione in seguito, se necessario.',
      [
        { text: 'Non ancora', style: 'cancel' },
        {
          text: 'Termina asta',
          style: 'destructive',
          onPress: () => void runControl('complete'),
        },
      ],
    );
  };

  const nominate = async (athleteId: string, athleteName: string) => {
    setSubmitting(true);
    setMessage('');
    const outcome = await auction.nominate(athleteId);
    setSubmitting(false);
    setMessage(
      outcome.error ??
        `${athleteName} è sul banco. Adesso vediamo chi perde la testa.`,
    );
  };

  const placeBid = async (increase: number) => {
    const nextBid = bidBase + increase;
    const credits = auction.state.myTeam?.creditsRemaining ?? 0;

    if (secondsLeft <= 0) {
      setMessage('Tempo scaduto. Il VAR conferma.');
      return;
    }
    if (credits < nextBid) {
      setMessage('Crediti finiti. Adesso servirebbe un miracolo.');
      return;
    }

    setSubmitting(true);
    const outcome = await auction.bid(nextBid);
    setSubmitting(false);
    setMessage(
      outcome.error ?? `Sei in testa a ${nextBid}. Fingi sicurezza.`,
    );
  };

  const finalize = async () => {
    setSubmitting(true);
    const outcome = await auction.finalize();
    setSubmitting(false);
    setMessage(
      outcome.error ??
        (currentItem?.highestBid
          ? 'Affare fatto. Qualcuno controlli il bilancio.'
          : 'Invenduto. Anche il silenzio ha un prezzo.'),
    );
  };

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.header}>
        <Pressable onPress={() => onNavigate('league')} style={styles.backButton}>
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text numberOfLines={1} style={styles.eyebrow}>
            {league.name}
          </Text>
          <Text style={styles.title}>Asta live</Text>
        </View>
        <View style={styles.livePill}>
          <View
            style={[
              styles.liveDot,
              (!currentItem || isPaused) && styles.liveDotWaiting,
            ]}
          />
          <Text style={styles.liveText}>
            {auctionStatusLabel(auctionStatus, Boolean(currentItem))}
          </Text>
        </View>
      </View>

      {auction.state.integrity?.safetyEnabled ? (
        <View
          style={[
            styles.safetyCard,
            !auction.state.integrity.ok && styles.safetyCardWarning,
          ]}
        >
          <View
            style={[
              styles.safetyDot,
              !auction.state.integrity.ok && styles.safetyDotWarning,
            ]}
          />
          <View style={styles.safetyCopy}>
            <Text
              style={[
                styles.safetyTitle,
                !auction.state.integrity.ok && styles.safetyTitleWarning,
              ]}
            >
              {auction.state.integrity.ok
                ? 'ASTA PROTETTA'
                : 'CONTROLLO ASTA RICHIESTO'}
            </Text>
            <Text style={styles.safetyBody}>
              {auction.state.integrity.ok
                ? 'Rilanci e assegnazioni sono serializzati da Supabase.'
                : `Rilevate ${auction.state.integrity.issueCount} anomalie di integrità.`}
            </Text>
          </View>
        </View>
      ) : null}

      {!auction.loading && auction.state.auction && isAdmin ? (
        <View style={styles.directorCard}>
          <View style={styles.directorHeader}>
            <View>
              <Text style={styles.directorEyebrow}>REGIA DEL PRESIDENTE</Text>
              <Text style={styles.directorTitle}>
                {isPaused ? 'Asta in pausa' : 'Comandi asta'}
              </Text>
            </View>
            <View style={styles.directorStatus}>
              <Text style={styles.directorStatusText}>
                {auctionStatusLabel(auctionStatus, Boolean(currentItem))}
              </Text>
            </View>
          </View>

          {!currentItem ? (
            <>
              <AuctionSetupFields
                bidIncrement={bidIncrement}
                bidSeconds={bidSeconds}
                dark
                onBidIncrement={setBidIncrement}
                onBidSeconds={setBidSeconds}
              />
              <Pressable
                disabled={submitting}
                onPress={() => void saveConfiguration()}
                style={[
                  styles.directorSaveButton,
                  submitting && styles.buttonDisabled,
                ]}
              >
                <Text style={styles.directorSaveText}>SALVA IMPOSTAZIONI</Text>
              </Pressable>
            </>
          ) : (
            <Text style={styles.directorBody}>
              {isPaused
                ? 'Il timer è congelato. Riprendi quando lo spogliatoio è pronto.'
                : 'Puoi fermare il timer oppure annullare il lotto in caso di errore.'}
            </Text>
          )}

          <View style={styles.directorActions}>
            <Pressable
              disabled={submitting}
              onPress={() =>
                void runControl(isPaused ? 'resume' : 'pause')
              }
              style={[
                styles.directorPrimaryAction,
                submitting && styles.buttonDisabled,
              ]}
            >
              <Text style={styles.directorPrimaryActionText}>
                {isPaused ? 'RIPRENDI' : 'METTI IN PAUSA'}
              </Text>
            </Pressable>
            <Pressable
              disabled={submitting}
              onPress={
                currentItem ? confirmCancelItem : confirmCompleteAuction
              }
              style={[
                styles.directorDangerAction,
                submitting && styles.buttonDisabled,
              ]}
            >
              <Text style={styles.directorDangerActionText}>
                {currentItem ? 'ANNULLA LOTTO' : 'TERMINA ASTA'}
              </Text>
            </Pressable>
          </View>
        </View>
      ) : null}

      {auction.loading ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.lime} size="large" />
          <Text style={styles.loadingText}>Apro la porta dello spogliatoio…</Text>
        </View>
      ) : auction.error ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>Stanza irraggiungibile</Text>
          <Text style={styles.errorText}>{auction.error}</Text>
        </View>
      ) : !auction.state.auction ? (
        <View style={styles.emptyCard}>
          <View style={styles.emptyBadge}>
            <Text style={styles.emptyBadgeText}>€</Text>
          </View>
          <Text style={styles.emptyTitle}>La stanza asta è chiusa</Text>
          <Text style={styles.emptyBody}>
            Il presidente può aprirla quando tutti i manager sono pronti. O
            almeno fingono di esserlo.
          </Text>
          {isAdmin ? (
            <>
              <AuctionSetupFields
                bidIncrement={bidIncrement}
                bidSeconds={bidSeconds}
                onBidIncrement={setBidIncrement}
                onBidSeconds={setBidSeconds}
              />
              <Pressable
                disabled={submitting}
                onPress={() => void openRoom()}
                style={[
                  styles.primaryButton,
                  submitting && styles.buttonDisabled,
                ]}
              >
                <Text style={styles.primaryButtonText}>
                  {submitting ? 'APERTURA…' : 'APRI STANZA ASTA'}
                </Text>
              </Pressable>
            </>
          ) : (
            <Text style={styles.waitingText}>
              In attesa del fischio del presidente.
            </Text>
          )}
          {message ? <Text style={styles.feedback}>{message}</Text> : null}
        </View>
      ) : !currentItem ? (
        <View>
          <View style={styles.waitingCard}>
            <Text style={styles.waitingEyebrow}>STANZA APERTA</Text>
            <Text style={styles.waitingTitle}>Prossima chiamata</Text>
            <Text style={styles.waitingBody}>
              {isAdmin
                ? isPaused
                  ? 'La stanza è in pausa. Riprendila dalla regia per continuare.'
                  : 'Scegli un calciatore e mandalo sul banco.'
                : 'Il presidente sta scegliendo il prossimo nome da rovinare.'}
            </Text>
          </View>

          {isAdmin && !isPaused ? (
            <>
              <Text style={styles.sectionLabel}>CALCIATORI DISPONIBILI</Text>
              <View style={styles.candidatesCard}>
                {auction.candidates.length === 0 ? (
                  <Text style={styles.noCandidates}>
                    Nessun calciatore disponibile in questo momento.
                  </Text>
                ) : (
                  auction.candidates.slice(0, 30).map((candidate) => (
                    <View style={styles.candidateRow} key={candidate.id}>
                      <View style={styles.candidateRole}>
                        <Text style={styles.candidateRoleText}>
                          {candidate.role}
                        </Text>
                      </View>
                      <View style={styles.candidateCopy}>
                        <Text style={styles.candidateName}>
                          {candidate.name}
                        </Text>
                        <Text style={styles.candidateClub}>
                          {candidate.clubName}
                        </Text>
                      </View>
                      <Pressable
                        disabled={submitting}
                        onPress={() =>
                          void nominate(candidate.id, candidate.name)
                        }
                        style={styles.nominateButton}
                      >
                        <Text style={styles.nominateText}>NOMINA</Text>
                      </Pressable>
                    </View>
                  ))
                )}
              </View>
            </>
          ) : null}
          {message ? (
            <View style={styles.coachCard}>
              <Text style={styles.coachLabel}>SPOGLIATOIO</Text>
              <Text style={styles.coachText}>{message}</Text>
            </View>
          ) : null}
        </View>
      ) : (
        <>
          <View style={styles.playerCard}>
            <View style={styles.rolePill}>
              <Text style={styles.roleText}>{currentItem.athlete.role}</Text>
            </View>
            <View style={styles.playerRow}>
              <View style={styles.playerAvatar}>
                <Text style={styles.playerNumber}>
                  {currentItem.athlete.shirtNumber ?? '—'}
                </Text>
              </View>
              <View style={styles.playerCopy}>
                <Text numberOfLines={2} style={styles.playerName}>
                  {currentItem.athlete.name}
                </Text>
                <Text style={styles.playerMeta}>
                  {currentItem.athlete.clubName}
                </Text>
                <Text style={styles.quotation}>
                  BASE D’ASTA {currentItem.openingPrice}
                </Text>
              </View>
            </View>
            <View style={styles.playerDivider} />
            <View style={styles.bidRow}>
              <View>
                <Text style={styles.bidLabel}>OFFERTA ATTUALE</Text>
                <View style={styles.bidValueRow}>
                  <Text style={styles.bidValue}>{currentPrice}</Text>
                  <Text style={styles.bidUnit}>crediti</Text>
                </View>
              </View>
              <View style={styles.countdown}>
                <Text
                  style={[
                    styles.countdownValue,
                    !isPaused &&
                      secondsLeft <= 5 &&
                      styles.countdownDanger,
                  ]}
                >
                  {isPaused ? '—' : secondsLeft}
                </Text>
                <Text style={styles.countdownLabel}>
                  {isPaused ? 'IN PAUSA' : 'SECONDI'}
                </Text>
              </View>
            </View>
          </View>

          {isPaused ? (
            <View style={styles.expiredNotice}>
              <Text style={styles.expiredTitle}>Asta in pausa</Text>
              <Text style={styles.expiredBody}>
                Il timer ripartirà dal punto in cui è stato fermato.
              </Text>
            </View>
          ) : secondsLeft > 0 ? (
            <>
              <Text style={styles.sectionLabel}>IL TUO RILANCIO</Text>
              <View style={styles.raiseRow}>
                {bidOptions.map((amount, index) => (
                  <Pressable
                    disabled={submitting}
                    key={amount}
                    onPress={() => void placeBid(amount)}
                    style={[
                      styles.raiseButton,
                      index === bidOptions.length - 1 && styles.raisePrimary,
                      submitting && styles.raiseDisabled,
                    ]}
                  >
                    <Text
                      style={[
                        styles.raiseText,
                        index === bidOptions.length - 1 &&
                          styles.raisePrimaryText,
                      ]}
                    >
                      +{amount}
                    </Text>
                  </Pressable>
                ))}
              </View>
            </>
          ) : isAdmin ? (
            <Pressable
              disabled={submitting}
              onPress={() => void finalize()}
              style={[
                styles.assignButton,
                submitting && styles.buttonDisabled,
              ]}
            >
              <Text style={styles.assignButtonText}>
                {submitting
                  ? 'CONTROLLO VAR…'
                  : currentItem.highestBid
                    ? 'ASSEGNA CALCIATORE'
                    : 'CHIUDI COME INVENDUTO'}
              </Text>
            </Pressable>
          ) : (
            <View style={styles.expiredNotice}>
              <Text style={styles.expiredTitle}>Tempo scaduto</Text>
              <Text style={styles.expiredBody}>
                Il presidente sta confermando l’assegnazione.
              </Text>
            </View>
          )}

          <View style={styles.statsCard}>
            <AuctionStat
              label="CREDITI"
              value={String(auction.state.myTeam?.creditsRemaining ?? 0)}
            />
            <AuctionStat
              label="POSTI ROSA"
              value={`${auction.state.myTeam?.rosterCount ?? 0}/${league.rosterSize}`}
            />
            <AuctionStat
              highlighted={isLeading}
              label="POSIZIONE"
              value={isLeading ? '1°' : '—'}
            />
          </View>

          <View style={styles.coachCard}>
            <Text style={styles.coachLabel}>SPOGLIATOIO</Text>
            <Text style={styles.coachText}>{coachMessage}</Text>
          </View>
        </>
      )}
    </ScrollView>
  );
}

function AuctionSetupFields({
  bidIncrement,
  bidSeconds,
  dark = false,
  onBidIncrement,
  onBidSeconds,
}: {
  bidIncrement: string;
  bidSeconds: string;
  dark?: boolean;
  onBidIncrement: (value: string) => void;
  onBidSeconds: (value: string) => void;
}) {
  return (
    <View style={styles.setupRow}>
      <View style={styles.setupField}>
        <Text style={[styles.setupLabel, dark && styles.setupLabelDark]}>
          RILANCIO MINIMO
        </Text>
        <View
          style={[styles.setupInputShell, dark && styles.setupInputShellDark]}
        >
          <TextInput
            keyboardType="number-pad"
            maxLength={3}
            onChangeText={onBidIncrement}
            selectTextOnFocus
            style={[styles.setupInput, dark && styles.setupInputDark]}
            value={bidIncrement}
          />
          <Text style={styles.setupSuffix}>CR</Text>
        </View>
      </View>
      <View style={styles.setupField}>
        <Text style={[styles.setupLabel, dark && styles.setupLabelDark]}>
          TIMER
        </Text>
        <View
          style={[styles.setupInputShell, dark && styles.setupInputShellDark]}
        >
          <TextInput
            keyboardType="number-pad"
            maxLength={3}
            onChangeText={onBidSeconds}
            selectTextOnFocus
            style={[styles.setupInput, dark && styles.setupInputDark]}
            value={bidSeconds}
          />
          <Text style={styles.setupSuffix}>SEC</Text>
        </View>
      </View>
    </View>
  );
}

function AuctionStat({
  label,
  value,
  highlighted,
}: {
  label: string;
  value: string;
  highlighted?: boolean;
}) {
  return (
    <View style={styles.stat}>
      <Text style={styles.statLabel}>{label}</Text>
      <Text style={[styles.statValue, highlighted && styles.statHighlighted]}>
        {value}
      </Text>
    </View>
  );
}

function parseAuctionSettings(
  incrementValue: string,
  secondsValue: string,
):
  | { error: string }
  | { bidIncrement: number; bidSeconds: number } {
  const increment = Number(incrementValue.trim());
  const seconds = Number(secondsValue.trim());

  if (!Number.isInteger(increment) || increment < 1 || increment > 100) {
    return { error: 'Il rilancio minimo deve essere tra 1 e 100 crediti.' };
  }
  if (!Number.isInteger(seconds) || seconds < 5 || seconds > 120) {
    return { error: 'Il timer deve essere compreso tra 5 e 120 secondi.' };
  }

  return { bidIncrement: increment, bidSeconds: seconds };
}

function auctionStatusLabel(
  status: 'scheduled' | 'live' | 'paused' | 'completed' | undefined,
  hasCurrentItem: boolean,
) {
  if (status === 'paused') {
    return 'PAUSA';
  }
  if (status === 'completed') {
    return 'CHIUSA';
  }
  return hasCurrentItem ? 'LIVE' : 'ATTESA';
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.navy,
  },
  content: {
    padding: 20,
    paddingBottom: 36,
  },
  centerRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 25,
    backgroundColor: colors.navy,
  },
  centerTitle: {
    color: colors.warmWhite,
    fontSize: 20,
    fontWeight: '900',
  },
  header: {
    minHeight: 68,
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 20,
  },
  backButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    backgroundColor: colors.navySoft,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 12,
  },
  backText: {
    color: colors.warmWhite,
    fontSize: 32,
    lineHeight: 34,
  },
  headerCopy: {
    flex: 1,
  },
  eyebrow: {
    color: colors.mutedLight,
    fontSize: 12,
  },
  title: {
    color: colors.warmWhite,
    fontSize: 29,
    fontWeight: '900',
    marginTop: 3,
  },
  livePill: {
    height: 34,
    borderRadius: 17,
    paddingHorizontal: 14,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.navySoft,
  },
  liveDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.danger,
    marginRight: 7,
  },
  liveDotWaiting: {
    backgroundColor: colors.muted,
  },
  liveText: {
    color: colors.warmWhite,
    fontSize: 10,
    fontWeight: '900',
  },
  safetyCard: {
    minHeight: 54,
    borderWidth: 1,
    borderColor: '#31512E',
    borderRadius: radius.md,
    paddingHorizontal: 14,
    paddingVertical: 11,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#102A24',
    marginBottom: 14,
  },
  safetyCardWarning: {
    borderColor: '#5D302F',
    backgroundColor: '#2B1D24',
  },
  safetyDot: {
    width: 9,
    height: 9,
    borderRadius: 5,
    backgroundColor: colors.lime,
    marginRight: 11,
  },
  safetyDotWarning: {
    backgroundColor: colors.danger,
  },
  safetyCopy: {
    flex: 1,
  },
  safetyTitle: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.35,
  },
  safetyTitleWarning: {
    color: colors.danger,
  },
  safetyBody: {
    color: colors.mutedLight,
    fontSize: 10,
    lineHeight: 14,
    marginTop: 3,
  },
  directorCard: {
    borderWidth: 1,
    borderColor: '#24364E',
    borderRadius: radius.lg,
    padding: 17,
    backgroundColor: colors.navySoft,
    marginBottom: 18,
  },
  directorHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  directorEyebrow: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  directorTitle: {
    color: colors.warmWhite,
    fontSize: 17,
    fontWeight: '900',
    marginTop: 4,
  },
  directorStatus: {
    height: 28,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 11,
    backgroundColor: colors.navy,
  },
  directorStatusText: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
  },
  directorBody: {
    color: colors.mutedLight,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 14,
  },
  directorSaveButton: {
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 12,
  },
  directorSaveText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  directorActions: {
    flexDirection: 'row',
    gap: 9,
    marginTop: 11,
  },
  directorPrimaryAction: {
    flex: 1,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.warmWhite,
  },
  directorPrimaryActionText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  directorDangerAction: {
    flex: 1,
    height: 42,
    borderWidth: 1,
    borderColor: colors.danger,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
  },
  directorDangerActionText: {
    color: colors.danger,
    fontSize: 8,
    fontWeight: '900',
  },
  loadingCard: {
    minHeight: 300,
    borderRadius: radius.xl,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navySoft,
  },
  loadingText: {
    color: colors.mutedLight,
    fontSize: 12,
    marginTop: 12,
  },
  errorCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.navySoft,
  },
  errorTitle: {
    color: colors.warmWhite,
    fontSize: 18,
    fontWeight: '900',
  },
  errorText: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 8,
  },
  emptyCard: {
    borderRadius: radius.xl,
    padding: 24,
    backgroundColor: colors.canvas,
  },
  emptyBadge: {
    width: 54,
    height: 54,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  emptyBadgeText: {
    color: colors.lime,
    fontSize: 23,
    fontWeight: '900',
  },
  emptyTitle: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
    marginTop: 19,
  },
  emptyBody: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 8,
  },
  setupRow: {
    flexDirection: 'row',
    gap: 11,
    marginTop: 17,
  },
  setupField: {
    flex: 1,
  },
  setupLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    marginBottom: 7,
  },
  setupLabelDark: {
    color: colors.mutedLight,
  },
  setupInputShell: {
    height: 48,
    borderWidth: 1,
    borderColor: '#DFE4DC',
    borderRadius: radius.sm,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.warmWhite,
  },
  setupInputShellDark: {
    borderColor: '#31445E',
    backgroundColor: colors.navy,
  },
  setupInput: {
    flex: 1,
    height: 48,
    paddingLeft: 13,
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  setupInputDark: {
    color: colors.warmWhite,
  },
  setupSuffix: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    marginRight: 12,
  },
  primaryButton: {
    minHeight: 54,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 22,
    backgroundColor: colors.lime,
    marginTop: 22,
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  waitingText: {
    color: colors.muted,
    fontSize: 12,
    fontWeight: '700',
    marginTop: 20,
  },
  feedback: {
    color: colors.danger,
    fontSize: 12,
    fontWeight: '700',
    lineHeight: 18,
    marginTop: 15,
  },
  waitingCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.canvas,
  },
  waitingEyebrow: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
  },
  waitingTitle: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
    marginTop: 6,
  },
  waitingBody: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 8,
  },
  sectionLabel: {
    color: colors.mutedLight,
    fontSize: 11,
    fontWeight: '900',
    marginTop: 24,
    marginBottom: 12,
  },
  candidatesCard: {
    borderRadius: radius.lg,
    padding: 8,
    backgroundColor: colors.canvas,
  },
  candidateRow: {
    minHeight: 65,
    borderRadius: 16,
    paddingHorizontal: 9,
    flexDirection: 'row',
    alignItems: 'center',
  },
  candidateRole: {
    width: 40,
    height: 40,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  candidateRoleText: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
  },
  candidateCopy: {
    flex: 1,
    marginLeft: 11,
  },
  candidateName: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  candidateClub: {
    color: colors.muted,
    fontSize: 10,
    marginTop: 4,
  },
  nominateButton: {
    height: 32,
    paddingHorizontal: 12,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  nominateText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  noCandidates: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    padding: 16,
  },
  playerCard: {
    borderRadius: radius.xl,
    backgroundColor: colors.canvas,
    padding: 22,
  },
  rolePill: {
    alignSelf: 'flex-start',
    height: 28,
    borderRadius: 14,
    paddingHorizontal: 16,
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  roleText: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
  },
  playerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 15,
  },
  playerAvatar: {
    width: 96,
    height: 96,
    borderRadius: 48,
    backgroundColor: colors.limeSoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  playerNumber: {
    color: colors.navy,
    fontSize: 34,
    fontWeight: '900',
  },
  playerCopy: {
    flex: 1,
    marginLeft: 18,
  },
  playerName: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '900',
  },
  playerMeta: {
    color: colors.muted,
    fontSize: 13,
    marginTop: 6,
  },
  quotation: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '900',
    marginTop: 12,
  },
  playerDivider: {
    height: 1,
    backgroundColor: '#DFE4DC',
    marginVertical: 18,
  },
  bidRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  bidLabel: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '900',
  },
  bidValueRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    marginTop: 2,
  },
  bidValue: {
    color: colors.navy,
    fontSize: 34,
    fontWeight: '900',
  },
  bidUnit: {
    color: colors.muted,
    fontSize: 11,
    fontWeight: '700',
    marginLeft: 8,
    marginBottom: 6,
  },
  countdown: {
    alignItems: 'center',
  },
  countdownValue: {
    width: 54,
    height: 54,
    borderRadius: 27,
    textAlign: 'center',
    textAlignVertical: 'center',
    backgroundColor: colors.lime,
    color: colors.navy,
    fontSize: 22,
    fontWeight: '900',
  },
  countdownDanger: {
    backgroundColor: colors.danger,
    color: colors.white,
  },
  countdownLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '800',
    marginTop: 5,
  },
  raiseRow: {
    flexDirection: 'row',
    gap: 12,
  },
  raiseButton: {
    flex: 1,
    height: 58,
    borderRadius: radius.md,
    backgroundColor: colors.navySoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  raisePrimary: {
    backgroundColor: colors.lime,
  },
  raiseDisabled: {
    opacity: 0.55,
  },
  raiseText: {
    color: colors.warmWhite,
    fontSize: 20,
    fontWeight: '900',
  },
  raisePrimaryText: {
    color: colors.navy,
  },
  assignButton: {
    minHeight: 58,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 20,
  },
  assignButtonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  expiredNotice: {
    borderRadius: radius.lg,
    padding: 17,
    backgroundColor: colors.navySoft,
    marginTop: 20,
  },
  expiredTitle: {
    color: colors.warmWhite,
    fontSize: 14,
    fontWeight: '900',
  },
  expiredBody: {
    color: colors.mutedLight,
    fontSize: 12,
    marginTop: 5,
  },
  statsCard: {
    minHeight: 78,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.navyLine,
    backgroundColor: '#0E1B2E',
    marginTop: 20,
    paddingHorizontal: 16,
    flexDirection: 'row',
    alignItems: 'center',
  },
  stat: {
    flex: 1,
  },
  statLabel: {
    color: colors.mutedLight,
    fontSize: 9,
    fontWeight: '900',
  },
  statValue: {
    color: colors.warmWhite,
    fontSize: 18,
    fontWeight: '900',
    marginTop: 5,
  },
  statHighlighted: {
    color: colors.lime,
  },
  coachCard: {
    minHeight: 72,
    borderRadius: radius.lg,
    backgroundColor: colors.lime,
    marginTop: 20,
    padding: 17,
  },
  coachLabel: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  coachText: {
    color: colors.navy,
    fontSize: 14,
    marginTop: 7,
  },
});
