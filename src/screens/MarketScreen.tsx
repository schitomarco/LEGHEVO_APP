import { useMemo, useState } from 'react';
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
import { useTransferMarket } from '../hooks/useTransferMarket';
import { colors, radius } from '../theme';
import type {
  AppScreen,
  LeagueSummary,
  MarketPlayer,
  TradeOfferSummary,
} from '../types';

type MarketTab = 'free' | 'roster' | 'trades';

type Props = {
  league: LeagueSummary | null;
  onLeagueChanged: () => void;
  onNavigate: (screen: AppScreen) => void;
  onOpenPlayer: (playerId: string) => void;
};

export function MarketScreen({
  league,
  onLeagueChanged,
  onNavigate,
  onOpenPlayer,
}: Props) {
  const market = useTransferMarket(league);
  const [tab, setTab] = useState<MarketTab>('free');
  const [search, setSearch] = useState('');
  const [feedback, setFeedback] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [proposalOpen, setProposalOpen] = useState(false);
  const [recipientTeamId, setRecipientTeamId] = useState('');
  const [offeredPlayerId, setOfferedPlayerId] = useState('');
  const [requestedPlayerId, setRequestedPlayerId] = useState('');
  const [proposerCredits, setProposerCredits] = useState('0');
  const [recipientCredits, setRecipientCredits] = useState('0');
  const [message, setMessage] = useState('');

  const normalizedSearch = search.trim().toLowerCase();
  const freeAgents = useMemo(
    () =>
      market.dashboard.freeAgents
        .filter(
          (player) =>
            !normalizedSearch ||
            player.name.toLowerCase().includes(normalizedSearch) ||
            player.clubName.toLowerCase().includes(normalizedSearch) ||
            player.role.toLowerCase().includes(normalizedSearch),
        )
        .slice(0, 40),
    [market.dashboard.freeAgents, normalizedSearch],
  );
  const otherTeams = market.dashboard.teams.filter(
    (team) => team.id !== market.dashboard.myTeam?.id,
  );
  const recipientTeam = otherTeams.find(
    (team) => team.id === recipientTeamId,
  );
  const relevantOffers = market.dashboard.offers.filter(
    (offer) =>
      offer.proposerTeamId === market.dashboard.myTeam?.id ||
      offer.recipientTeamId === market.dashboard.myTeam?.id,
  );

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

  const execute = async (
    id: string,
    action: () => Promise<{ error?: string }>,
    successMessage: string,
  ) => {
    setBusyId(id);
    setFeedback('');
    const outcome = await action();
    setBusyId(null);
    if (outcome.error) {
      setFeedback(outcome.error);
      return false;
    }
    setFeedback(successMessage);
    onLeagueChanged();
    return true;
  };

  const buy = async (player: MarketPlayer) => {
    await execute(
      `buy-${player.id}`,
      () => market.sign(player.id),
      `${player.name} è tuo. Il procuratore pretende già una commissione.`,
    );
  };

  const confirmRelease = (player: MarketPlayer) => {
    const refund = Math.floor(
      (player.purchasePrice * market.dashboard.releaseRefundPercent) / 100,
    );
    Alert.alert(
      'Conferma svincolo',
      `Svincolando ${player.name} recuperi ${refund} crediti.`,
      [
        { text: 'ANNULLA', style: 'cancel' },
        {
          text: 'SVINCOLA',
          style: 'destructive',
          onPress: () => {
            void execute(
              `release-${player.id}`,
              () => market.release(player.id),
              `${player.name} è tornato sul mercato.`,
            );
          },
        },
      ],
    );
  };

  const sendProposal = async () => {
    const offeredCredits = parseCredits(proposerCredits);
    const requestedCredits = parseCredits(recipientCredits);
    if (!recipientTeamId) {
      setFeedback('Scegli prima la squadra destinataria.');
      return;
    }
    if (!offeredPlayerId && !requestedPlayerId) {
      setFeedback('Lo scambio deve contenere almeno un calciatore.');
      return;
    }
    if (offeredCredits === null || requestedCredits === null) {
      setFeedback('I crediti devono essere numeri interi positivi.');
      return;
    }

    const success = await execute(
      'new-trade',
      () =>
        market.propose({
          recipientTeamId,
          offeredPlayerIds: offeredPlayerId ? [offeredPlayerId] : [],
          requestedPlayerIds: requestedPlayerId ? [requestedPlayerId] : [],
          proposerCredits: offeredCredits,
          recipientCredits: requestedCredits,
          message,
        }),
      'Proposta inviata. Adesso comincia la pretattica.',
    );
    if (success) {
      setProposalOpen(false);
      setRecipientTeamId('');
      setOfferedPlayerId('');
      setRequestedPlayerId('');
      setProposerCredits('0');
      setRecipientCredits('0');
      setMessage('');
    }
  };

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.header}>
        <Pressable
          onPress={() => onNavigate('league')}
          style={styles.backButton}
        >
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>TRATTATIVE APERTE</Text>
          <Text style={styles.title}>Mercato</Text>
        </View>
        <View
          style={[
            styles.marketBadge,
            !market.dashboard.marketOpen && styles.marketBadgeClosed,
          ]}
        >
          <Text style={styles.marketBadgeText}>
            {market.dashboard.marketOpen ? 'APERTO' : 'CHIUSO'}
          </Text>
        </View>
      </View>

      <View style={styles.heroCard}>
        <View>
          <Text style={styles.heroEyebrow}>LA TUA SQUADRA</Text>
          <Text numberOfLines={1} style={styles.heroTitle}>
            {market.dashboard.myTeam?.name ?? league.team?.name ?? 'Squadra'}
          </Text>
        </View>
        <View style={styles.heroStats}>
          <HeroStat
            label="CREDITI"
            value={String(
              market.dashboard.myTeam?.creditsRemaining ??
                league.team?.creditsRemaining ??
                0,
            )}
          />
          <HeroStat
            label="ROSA"
            value={`${market.dashboard.myTeam?.players.length ?? 0}/${league.rosterSize}`}
          />
          <HeroStat
            label="SVINCOLO"
            value={`${market.dashboard.releaseRefundPercent}%`}
          />
        </View>
      </View>

      <View style={styles.tabs}>
        <Tab
          active={tab === 'free'}
          label="SVINCOLATI"
          onPress={() => setTab('free')}
        />
        <Tab
          active={tab === 'roster'}
          label="MIA ROSA"
          onPress={() => setTab('roster')}
        />
        <Tab
          active={tab === 'trades'}
          label="SCAMBI"
          notice={
            relevantOffers.filter(
              (offer) =>
                offer.status === 'pending' &&
                offer.recipientTeamId === market.dashboard.myTeam?.id,
            ).length
          }
          onPress={() => setTab('trades')}
        />
      </View>

      {feedback ? <Text style={styles.feedback}>{feedback}</Text> : null}

      {market.dashboard.integrity && !market.dashboard.integrity.ok ? (
        <View style={styles.integrityWarning}>
          <Text style={styles.integrityWarningTitle}>
            CONTROLLO MERCATO RICHIESTO
          </Text>
          <Text style={styles.integrityWarningBody}>
            Il database ha rilevato {market.dashboard.integrity.issueCount}{' '}
            {market.dashboard.integrity.issueCount === 1
              ? 'anomalia'
              : 'anomalie'}{' '}
            tra crediti, rose o trattative. Le operazioni sensibili possono essere
            bloccate finché i dati non tornano coerenti.
          </Text>
        </View>
      ) : null}

      {market.dashboard.integrity?.marketModelClosed ? (
        <View style={styles.tradeSafetyCard}>
          <Text style={styles.tradeSafetyTitle}>OPERAZIONI PROTETTE</Text>
          <Text style={styles.tradeSafetyBody}>
            Acquisti, svincoli, scambi e Asta Live passano soltanto dai comandi
            sicuri di Supabase. Crediti, rose e movimenti non possono essere
            modificati direttamente dall’app.
          </Text>
        </View>
      ) : null}

      {market.loading ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.navy} />
          <Text style={styles.loadingText}>
            Chiamo direttori sportivi e procuratori…
          </Text>
        </View>
      ) : market.error ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>Mercato indisponibile</Text>
          <Text style={styles.errorBody}>{market.error}</Text>
        </View>
      ) : tab === 'free' ? (
        <>
          {market.dashboard.integrity?.marketAuctionSafetyEnabled ? (
            <View style={styles.tradeSafetyCard}>
              <Text style={styles.tradeSafetyTitle}>
                MERCATO E ASTA COORDINATI
              </Text>
              <Text style={styles.tradeSafetyBody}>
                I calciatori presenti sul banco dell’Asta Live vengono esclusi
                automaticamente dal mercato libero fino alla chiusura del lotto.
              </Text>
            </View>
          ) : null}
          <TextInput
            onChangeText={setSearch}
            placeholder="Cerca nome, squadra o ruolo"
            placeholderTextColor={colors.muted}
            style={styles.searchInput}
            value={search}
          />
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Calciatori liberi</Text>
            <Text style={styles.sectionMeta}>
              {market.dashboard.freeAgents.length} DISPONIBILI
            </Text>
          </View>
          {freeAgents.length === 0 ? (
            <EmptyCard
              body="Nessun calciatore corrisponde alla ricerca."
              title="Panchina vuota"
            />
          ) : (
            <View style={styles.playersCard}>
              {freeAgents.map((player) => (
                <PlayerActionRow
                  actionLabel={`${market.dashboard.minimumPrice} CR`}
                  busy={busyId === `buy-${player.id}`}
                  disabled={
                    !market.dashboard.marketOpen ||
                    busyId !== null ||
                    (market.dashboard.myTeam?.players.length ?? 0) >=
                      league.rosterSize
                  }
                  key={player.id}
                  onAction={() => void buy(player)}
                  onOpen={() => onOpenPlayer(player.id)}
                  player={player}
                />
              ))}
            </View>
          )}
        </>
      ) : tab === 'roster' ? (
        <>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>La tua rosa</Text>
            <Text style={styles.sectionMeta}>
              RIMBORSO {market.dashboard.releaseRefundPercent}%
            </Text>
          </View>
          <View style={styles.playersCard}>
            {(market.dashboard.myTeam?.players ?? []).map((player) => (
              <PlayerActionRow
                actionLabel="SVINCOLA"
                busy={busyId === `release-${player.id}`}
                danger
                disabled={
                  !market.dashboard.marketOpen || busyId !== null
                }
                key={player.id}
                onAction={() => confirmRelease(player)}
                onOpen={() => onOpenPlayer(player.id)}
                player={player}
              />
            ))}
          </View>
        </>
      ) : (
        <>
          {market.dashboard.integrity?.tradeSafetyEnabled ? (
            <View style={styles.tradeSafetyCard}>
              <Text style={styles.tradeSafetyTitle}>SCAMBI PROTETTI</Text>
              <Text style={styles.tradeSafetyBody}>
                Calciatori offerti e crediti promessi vengono prenotati fino
                alla chiusura della trattativa. Le proposte incompatibili sono
                bloccate prima di modificare le rose.
              </Text>
            </View>
          ) : null}

          <Pressable
            onPress={() => setProposalOpen((current) => !current)}
            style={styles.newTradeButton}
          >
            <View>
              <Text style={styles.newTradeEyebrow}>NUOVA TRATTATIVA</Text>
              <Text style={styles.newTradeTitle}>
                Proponi uno scambio
              </Text>
            </View>
            <Text style={styles.newTradeSymbol}>
              {proposalOpen ? '×' : '+'}
            </Text>
          </Pressable>

          {proposalOpen ? (
            <View style={styles.tradeForm}>
              <Text style={styles.fieldLabel}>SQUADRA DESTINATARIA</Text>
              <ScrollView
                horizontal
                contentContainerStyle={styles.choiceRow}
                showsHorizontalScrollIndicator={false}
              >
                {otherTeams.map((team) => (
                  <Choice
                    active={team.id === recipientTeamId}
                    key={team.id}
                    label={team.name}
                    onPress={() => {
                      setRecipientTeamId(team.id);
                      setRequestedPlayerId('');
                    }}
                  />
                ))}
              </ScrollView>

              <Text style={styles.fieldLabel}>TU OFFRI</Text>
              <PlayerChoices
                players={market.dashboard.myTeam?.players ?? []}
                selectedId={offeredPlayerId}
                onSelect={setOfferedPlayerId}
              />

              <Text style={styles.fieldLabel}>TU CHIEDI</Text>
              {recipientTeam ? (
                <PlayerChoices
                  players={recipientTeam.players}
                  selectedId={requestedPlayerId}
                  onSelect={setRequestedPlayerId}
                />
              ) : (
                <Text style={styles.fieldHint}>
                  Scegli prima la squadra destinataria.
                </Text>
              )}

              <View style={styles.creditRow}>
                <CreditInput
                  label="CREDITI OFFERTI"
                  onChange={setProposerCredits}
                  value={proposerCredits}
                />
                <CreditInput
                  label="CREDITI RICHIESTI"
                  onChange={setRecipientCredits}
                  value={recipientCredits}
                />
              </View>

              <Text style={styles.fieldLabel}>MESSAGGIO FACOLTATIVO</Text>
              <TextInput
                maxLength={180}
                multiline
                onChangeText={setMessage}
                placeholder="Prova a convincerlo senza mentire troppo…"
                placeholderTextColor={colors.muted}
                style={styles.messageInput}
                value={message}
              />

              <Pressable
                disabled={busyId !== null}
                onPress={() => void sendProposal()}
                style={[
                  styles.primaryButton,
                  busyId !== null && styles.buttonDisabled,
                ]}
              >
                <Text style={styles.primaryButtonText}>
                  {busyId === 'new-trade'
                    ? 'INVIO IN CORSO…'
                    : 'INVIA PROPOSTA'}
                </Text>
              </Pressable>
            </View>
          ) : null}

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Le tue trattative</Text>
            <Text style={styles.sectionMeta}>
              {relevantOffers.length} TOTALI
            </Text>
          </View>

          {relevantOffers.length === 0 ? (
            <EmptyCard
              body="Qui compariranno le proposte inviate e ricevute."
              title="Nessuno bussa alla porta"
            />
          ) : (
            relevantOffers.map((offer) => (
              <TradeOfferCard
                busy={busyId === offer.id}
                key={offer.id}
                myTeamId={market.dashboard.myTeam?.id ?? ''}
                offer={offer}
                onAccept={() =>
                  void execute(
                    offer.id,
                    () => market.respond(offer.id, true),
                    'Scambio concluso. Le rose sono già aggiornate.',
                  )
                }
                onCancel={() =>
                  void execute(
                    offer.id,
                    () => market.cancel(offer.id),
                    'Proposta annullata.',
                  )
                }
                onDecline={() =>
                  void execute(
                    offer.id,
                    () => market.respond(offer.id, false),
                    'Proposta rifiutata. Nessun procuratore è stato ferito.',
                  )
                }
              />
            ))
          )}
        </>
      )}
    </ScrollView>
  );
}

function HeroStat({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.heroStat}>
      <Text style={styles.heroStatValue}>{value}</Text>
      <Text style={styles.heroStatLabel}>{label}</Text>
    </View>
  );
}

function Tab({
  active,
  label,
  notice = 0,
  onPress,
}: {
  active: boolean;
  label: string;
  notice?: number;
  onPress: () => void;
}) {
  return (
    <Pressable
      onPress={onPress}
      style={[styles.tab, active && styles.tabActive]}
    >
      <Text style={[styles.tabText, active && styles.tabTextActive]}>
        {label}
      </Text>
      {notice > 0 ? (
        <View style={styles.noticeBadge}>
          <Text style={styles.noticeText}>{notice}</Text>
        </View>
      ) : null}
    </Pressable>
  );
}

function PlayerActionRow({
  actionLabel,
  busy,
  danger = false,
  disabled,
  onAction,
  onOpen,
  player,
}: {
  actionLabel: string;
  busy: boolean;
  danger?: boolean;
  disabled: boolean;
  onAction: () => void;
  onOpen: () => void;
  player: MarketPlayer;
}) {
  const initials = player.name
    .split(/\s+/)
    .map((part) => part[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();

  return (
    <View style={styles.playerRow}>
      <Pressable onPress={onOpen} style={styles.playerInfo}>
        <View style={styles.playerAvatar}>
          <Text style={styles.playerAvatarText}>{initials}</Text>
        </View>
        <View style={styles.playerCopy}>
          <Text numberOfLines={1} style={styles.playerName}>
            {player.name}
          </Text>
          <Text numberOfLines={1} style={styles.playerClub}>
            {player.clubName} · {player.role}
          </Text>
        </View>
      </Pressable>
      <Pressable
        disabled={disabled}
        onPress={onAction}
        style={[
          styles.playerAction,
          danger && styles.playerActionDanger,
          disabled && styles.buttonDisabled,
        ]}
      >
        <Text
          style={[
            styles.playerActionText,
            danger && styles.playerActionDangerText,
          ]}
        >
          {busy ? '…' : actionLabel}
        </Text>
      </Pressable>
    </View>
  );
}

function Choice({
  active,
  label,
  onPress,
}: {
  active: boolean;
  label: string;
  onPress: () => void;
}) {
  return (
    <Pressable
      onPress={onPress}
      style={[styles.choice, active && styles.choiceActive]}
    >
      <Text style={[styles.choiceText, active && styles.choiceTextActive]}>
        {label}
      </Text>
    </Pressable>
  );
}

function PlayerChoices({
  players,
  selectedId,
  onSelect,
}: {
  players: MarketPlayer[];
  selectedId: string;
  onSelect: (id: string) => void;
}) {
  return (
    <ScrollView
      horizontal
      contentContainerStyle={styles.playerChoices}
      showsHorizontalScrollIndicator={false}
    >
      {players.map((player) => {
        const active = player.id === selectedId;
        return (
          <Pressable
            key={player.id}
            onPress={() => onSelect(player.id)}
            style={[
              styles.playerChoice,
              active && styles.playerChoiceActive,
            ]}
          >
            <Text
              numberOfLines={1}
              style={[
                styles.playerChoiceRole,
                active && styles.playerChoiceRoleActive,
              ]}
            >
              {player.role}
            </Text>
            <Text
              numberOfLines={1}
              style={[
                styles.playerChoiceName,
                active && styles.playerChoiceNameActive,
              ]}
            >
              {player.name}
            </Text>
          </Pressable>
        );
      })}
    </ScrollView>
  );
}

function CreditInput({
  label,
  onChange,
  value,
}: {
  label: string;
  onChange: (value: string) => void;
  value: string;
}) {
  return (
    <View style={styles.creditField}>
      <Text style={styles.fieldLabel}>{label}</Text>
      <TextInput
        keyboardType="number-pad"
        maxLength={4}
        onChangeText={onChange}
        style={styles.creditInput}
        value={value}
      />
    </View>
  );
}

function TradeOfferCard({
  busy,
  myTeamId,
  offer,
  onAccept,
  onCancel,
  onDecline,
}: {
  busy: boolean;
  myTeamId: string;
  offer: TradeOfferSummary;
  onAccept: () => void;
  onCancel: () => void;
  onDecline: () => void;
}) {
  const incoming = offer.recipientTeamId === myTeamId;
  const pending = offer.status === 'pending';
  const offered = describeSide(
    offer.offeredPlayers,
    offer.proposerCredits,
  );
  const requested = describeSide(
    offer.requestedPlayers,
    offer.recipientCredits,
  );

  return (
    <View style={styles.offerCard}>
      <View style={styles.offerHeader}>
        <View>
          <Text style={styles.offerDirection}>
            {incoming ? 'PROPOSTA RICEVUTA' : 'PROPOSTA INVIATA'}
          </Text>
          <Text style={styles.offerTeams}>
            {offer.proposerTeamName} ↔ {offer.recipientTeamName}
          </Text>
        </View>
        <View
          style={[
            styles.statusBadge,
            offer.status === 'accepted' && styles.statusAccepted,
          ]}
        >
          <Text style={styles.statusText}>{statusLabel(offer.status)}</Text>
        </View>
      </View>

      <View style={styles.exchangeRow}>
        <View style={styles.exchangeSide}>
          <Text style={styles.exchangeLabel}>OFFRE</Text>
          <Text style={styles.exchangeValue}>{offered}</Text>
        </View>
        <Text style={styles.exchangeArrow}>→</Text>
        <View style={[styles.exchangeSide, styles.exchangeSideRight]}>
          <Text style={styles.exchangeLabel}>CHIEDE</Text>
          <Text style={[styles.exchangeValue, styles.exchangeValueRight]}>
            {requested}
          </Text>
        </View>
      </View>

      {offer.message ? (
        <Text style={styles.offerMessage}>“{offer.message}”</Text>
      ) : null}

      {pending && incoming ? (
        <View style={styles.offerActions}>
          <Pressable
            disabled={busy}
            onPress={onDecline}
            style={styles.secondaryAction}
          >
            <Text style={styles.secondaryActionText}>RIFIUTA</Text>
          </Pressable>
          <Pressable
            disabled={busy}
            onPress={onAccept}
            style={styles.acceptAction}
          >
            <Text style={styles.acceptActionText}>
              {busy ? 'ATTENDI…' : 'ACCETTA'}
            </Text>
          </Pressable>
        </View>
      ) : pending && !incoming ? (
        <Pressable
          disabled={busy}
          onPress={onCancel}
          style={styles.cancelAction}
        >
          <Text style={styles.cancelActionText}>
            {busy ? 'ATTENDI…' : 'ANNULLA PROPOSTA'}
          </Text>
        </Pressable>
      ) : null}
    </View>
  );
}

function EmptyCard({ body, title }: { body: string; title: string }) {
  return (
    <View style={styles.emptyCard}>
      <Text style={styles.emptyTitle}>{title}</Text>
      <Text style={styles.emptyBody}>{body}</Text>
    </View>
  );
}

function parseCredits(value: string) {
  const parsed = Number.parseInt(value || '0', 10);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : null;
}

function describeSide(players: MarketPlayer[], credits: number) {
  const parts = players.map((player) => player.name);
  if (credits > 0) {
    parts.push(`${credits} crediti`);
  }
  return parts.join(' + ') || '—';
}

function statusLabel(status: TradeOfferSummary['status']) {
  const labels = {
    pending: 'IN ATTESA',
    accepted: 'ACCETTATA',
    declined: 'RIFIUTATA',
    canceled: 'ANNULLATA',
    expired: 'SCADUTA',
  };
  return labels[status];
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    padding: 20,
    paddingBottom: 44,
  },
  centerRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
    backgroundColor: colors.canvas,
  },
  centerTitle: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
    marginBottom: 18,
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
    letterSpacing: 0.6,
  },
  title: {
    color: colors.navy,
    fontSize: 25,
    fontWeight: '900',
    marginTop: 3,
  },
  marketBadge: {
    borderRadius: 10,
    paddingHorizontal: 10,
    paddingVertical: 7,
    backgroundColor: colors.lime,
  },
  marketBadgeClosed: {
    backgroundColor: colors.danger,
  },
  marketBadgeText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  heroCard: {
    minHeight: 155,
    borderRadius: radius.xl,
    justifyContent: 'space-between',
    padding: 22,
    backgroundColor: colors.navy,
  },
  heroEyebrow: {
    color: colors.mutedLight,
    fontSize: 9,
    fontWeight: '900',
  },
  heroTitle: {
    color: colors.warmWhite,
    fontSize: 21,
    fontWeight: '900',
    marginTop: 5,
  },
  heroStats: {
    flexDirection: 'row',
    gap: 10,
    marginTop: 22,
  },
  heroStat: {
    flex: 1,
    borderTopWidth: 1,
    borderTopColor: colors.navyLine,
    paddingTop: 10,
  },
  heroStatValue: {
    color: colors.lime,
    fontSize: 17,
    fontWeight: '900',
  },
  heroStatLabel: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 3,
  },
  tabs: {
    height: 48,
    flexDirection: 'row',
    borderRadius: radius.md,
    padding: 4,
    marginTop: 16,
    backgroundColor: colors.canvasMuted,
  },
  tab: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 5,
    borderRadius: 14,
  },
  tabActive: {
    backgroundColor: colors.navy,
  },
  tabText: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  tabTextActive: {
    color: colors.lime,
  },
  noticeBadge: {
    minWidth: 17,
    height: 17,
    borderRadius: 9,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.danger,
  },
  noticeText: {
    color: colors.white,
    fontSize: 8,
    fontWeight: '900',
  },
  feedback: {
    borderRadius: radius.sm,
    color: colors.navy,
    fontSize: 11,
    fontWeight: '800',
    lineHeight: 16,
    padding: 12,
    marginTop: 12,
    backgroundColor: '#EAFBC0',
  },
  integrityWarning: {
    borderWidth: 1,
    borderColor: colors.danger,
    borderRadius: radius.md,
    padding: 14,
    marginTop: 12,
    backgroundColor: '#FFF1F1',
  },
  integrityWarningTitle: {
    color: colors.danger,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  integrityWarningBody: {
    color: colors.navy,
    fontSize: 11,
    lineHeight: 16,
    marginTop: 5,
  },
  loadingCard: {
    minHeight: 220,
    borderRadius: radius.lg,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 18,
    backgroundColor: colors.white,
  },
  loadingText: {
    color: colors.muted,
    fontSize: 12,
    marginTop: 10,
  },
  errorCard: {
    borderRadius: radius.lg,
    padding: 22,
    marginTop: 18,
    backgroundColor: colors.navy,
  },
  errorTitle: {
    color: colors.warmWhite,
    fontSize: 17,
    fontWeight: '900',
  },
  errorBody: {
    color: colors.mutedLight,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 7,
  },
  searchInput: {
    height: 48,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: radius.md,
    color: colors.navy,
    fontSize: 12,
    paddingHorizontal: 16,
    marginTop: 18,
    backgroundColor: colors.white,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 11,
    marginTop: 22,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  sectionMeta: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  playersCard: {
    overflow: 'hidden',
    borderRadius: radius.lg,
    backgroundColor: colors.white,
  },
  playerRow: {
    minHeight: 69,
    flexDirection: 'row',
    alignItems: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.canvasMuted,
    paddingHorizontal: 12,
  },
  playerInfo: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'stretch',
  },
  playerAvatar: {
    width: 38,
    height: 38,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  playerAvatarText: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
  },
  playerCopy: {
    flex: 1,
    marginHorizontal: 10,
  },
  playerName: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  playerClub: {
    color: colors.muted,
    fontSize: 9,
    marginTop: 3,
  },
  playerAction: {
    minWidth: 54,
    borderRadius: 10,
    alignItems: 'center',
    paddingHorizontal: 9,
    paddingVertical: 9,
    backgroundColor: colors.lime,
  },
  playerActionDanger: {
    backgroundColor: '#FFE2DF',
  },
  playerActionText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  playerActionDangerText: {
    color: '#B93029',
  },
  buttonDisabled: {
    opacity: 0.45,
  },
  tradeSafetyCard: {
    borderWidth: 1,
    borderColor: '#CFEA8C',
    borderRadius: radius.md,
    padding: 14,
    marginTop: 18,
    backgroundColor: '#F4FFD9',
  },
  tradeSafetyTitle: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.6,
  },
  tradeSafetyBody: {
    color: colors.navy,
    fontSize: 11,
    lineHeight: 16,
    marginTop: 5,
  },
  newTradeButton: {
    minHeight: 86,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderRadius: radius.lg,
    paddingHorizontal: 20,
    marginTop: 18,
    backgroundColor: colors.navy,
  },
  newTradeEyebrow: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
  },
  newTradeTitle: {
    color: colors.warmWhite,
    fontSize: 17,
    fontWeight: '900',
    marginTop: 4,
  },
  newTradeSymbol: {
    color: colors.lime,
    fontSize: 28,
    fontWeight: '500',
  },
  tradeForm: {
    borderRadius: radius.lg,
    padding: 18,
    marginTop: 10,
    backgroundColor: colors.white,
  },
  fieldLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
    marginBottom: 7,
    marginTop: 12,
  },
  fieldHint: {
    color: colors.muted,
    fontSize: 10,
    fontStyle: 'italic',
    marginBottom: 8,
  },
  choiceRow: {
    gap: 7,
    paddingRight: 12,
  },
  choice: {
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    backgroundColor: colors.canvas,
  },
  choiceActive: {
    borderColor: colors.navy,
    backgroundColor: colors.navy,
  },
  choiceText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  choiceTextActive: {
    color: colors.lime,
  },
  playerChoices: {
    gap: 7,
    paddingRight: 12,
  },
  playerChoice: {
    width: 128,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: 13,
    padding: 11,
    backgroundColor: colors.canvas,
  },
  playerChoiceActive: {
    borderColor: colors.navy,
    backgroundColor: colors.navy,
  },
  playerChoiceRole: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  playerChoiceRoleActive: {
    color: colors.lime,
  },
  playerChoiceName: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
    marginTop: 4,
  },
  playerChoiceNameActive: {
    color: colors.warmWhite,
  },
  creditRow: {
    flexDirection: 'row',
    gap: 10,
  },
  creditField: {
    flex: 1,
  },
  creditInput: {
    height: 44,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: 12,
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
    paddingHorizontal: 12,
    backgroundColor: colors.canvas,
  },
  messageInput: {
    minHeight: 74,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: 12,
    color: colors.navy,
    fontSize: 11,
    lineHeight: 16,
    padding: 12,
    textAlignVertical: 'top',
    backgroundColor: colors.canvas,
  },
  primaryButton: {
    minHeight: 48,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 18,
    marginTop: 16,
    backgroundColor: colors.lime,
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  offerCard: {
    borderRadius: radius.lg,
    padding: 17,
    marginBottom: 10,
    backgroundColor: colors.white,
  },
  offerHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 8,
  },
  offerDirection: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  offerTeams: {
    maxWidth: 235,
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
    marginTop: 4,
  },
  statusBadge: {
    borderRadius: 8,
    paddingHorizontal: 8,
    paddingVertical: 6,
    backgroundColor: colors.canvasMuted,
  },
  statusAccepted: {
    backgroundColor: '#EAFBC0',
  },
  statusText: {
    color: colors.navy,
    fontSize: 7,
    fontWeight: '900',
  },
  exchangeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: radius.md,
    padding: 12,
    marginTop: 14,
    backgroundColor: colors.canvas,
  },
  exchangeSide: {
    flex: 1,
  },
  exchangeSideRight: {
    alignItems: 'flex-end',
  },
  exchangeLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  exchangeValue: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
    lineHeight: 14,
    marginTop: 3,
  },
  exchangeValueRight: {
    textAlign: 'right',
  },
  exchangeArrow: {
    color: colors.muted,
    fontSize: 16,
    marginHorizontal: 8,
  },
  offerMessage: {
    color: colors.muted,
    fontSize: 10,
    fontStyle: 'italic',
    lineHeight: 15,
    marginTop: 11,
  },
  offerActions: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 13,
  },
  secondaryAction: {
    flex: 1,
    minHeight: 41,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  secondaryActionText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  acceptAction: {
    flex: 1,
    minHeight: 41,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  acceptActionText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  cancelAction: {
    minHeight: 40,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 12,
    backgroundColor: colors.canvasMuted,
  },
  cancelActionText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  emptyCard: {
    borderRadius: radius.lg,
    padding: 22,
    backgroundColor: colors.white,
  },
  emptyTitle: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  emptyBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 7,
  },
});
