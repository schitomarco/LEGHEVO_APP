import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  Share,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useLeagueManagement } from '../hooks/useLeagueManagement';
import { useLeagueMembers } from '../hooks/useLeagueMembers';
import { regenerateLeagueInviteCode } from '../services/leagueService';
import { colors, radius } from '../theme';
import type {
  AppScreen,
  LeagueManagementState,
  LeagueMemberSummary,
  LeaguePermissionState,
  LeagueRoleAuditEvent,
  LeagueRoleControlState,
  LeagueRoleSecurity,
  LeagueSummary,
} from '../types';

type Props = {
  currentUserId: string | null;
  league: LeagueSummary | null;
  onLeagueChanged: () => void;
  onSeasonRenewed: (leagueId: string) => void | Promise<void>;
  onNavigate: (screen: AppScreen) => void;
};

export function LeagueManagementScreen({
  currentUserId,
  league,
  onLeagueChanged,
  onSeasonRenewed,
  onNavigate,
}: Props) {
  const members = useLeagueMembers(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const management = useLeagueManagement(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const [inviteCode, setInviteCode] = useState(league?.inviteCode ?? '');
  const [busyAction, setBusyAction] = useState('');
  const [feedback, setFeedback] = useState('');
  const [success, setSuccess] = useState(false);
  const [nextSeasonInput, setNextSeasonInput] = useState('');

  useEffect(() => {
    setInviteCode(league?.inviteCode ?? '');
  }, [league?.inviteCode]);

  useEffect(() => {
    if (management.state?.nextSeason) {
      setNextSeasonInput(management.state.nextSeason);
    }
  }, [management.state?.nextSeason]);

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

  const state = management.state;
  const access = management.access;
  const canManage = Boolean(league.isDemo) ||
    (access
      ? access.permissions.canAccessDirection
      : league.currentRole === 'admin');

  if (!management.loading && access && !access.accessValid) {
    return (
      <View style={styles.centerRoot}>
        <View style={styles.lockBadge}>
          <Text style={styles.lockBadgeText}>!</Text>
        </View>
        <Text style={styles.centerTitle}>Accesso alla lega revocato</Text>
        <Text style={styles.centerBody}>
          Il tuo profilo non risulta più tra i partecipanti. La sessione è stata aggiornata automaticamente.
        </Text>
        <Pressable
          onPress={() => onNavigate('home')}
          style={styles.primaryButton}
        >
          <Text style={styles.primaryButtonText}>TORNA ALLE LEGHE</Text>
        </Pressable>
      </View>
    );
  }

  if (!management.loading && !canManage) {
    return (
      <View style={styles.centerRoot}>
        <View style={styles.lockBadge}>
          <Text style={styles.lockBadgeText}>M</Text>
        </View>
        <Text style={styles.centerTitle}>Permessi aggiornati</Text>
        <Text style={styles.centerBody}>
          Continui a partecipare come Mister, ma la Direzione Lega è riservata a Presidente e Admin.
        </Text>
        <Pressable
          onPress={() => onNavigate('league')}
          style={styles.primaryButton}
        >
          <Text style={styles.primaryButtonText}>TORNA ALLA LEGA</Text>
        </Pressable>
      </View>
    );
  }

  const isOwner =
    Boolean(league.isDemo) ||
    state?.isOwner === true ||
    league.ownerId === currentUserId;
  const startedAt =
    state?.competitionStartedAt ?? league.competitionStartedAt ?? null;
  const completedAt = state?.completedAt ?? null;
  const champion = state?.champion ?? null;

  const clearFeedback = () => {
    setFeedback('');
    setSuccess(false);
  };

  const shareInvite = async () => {
    if (state && !state.invitesOpen) {
      setFeedback('Apri prima gli inviti: questo codice ora non fa entrare nessuno.');
      setSuccess(false);
      return;
    }

    await Share.share({
      title: `Invito a ${league.name}`,
      message:
        `Ti aspetto nella lega “${league.name}” su LEGHEVO.\n` +
        `Codice invito: ${inviteCode}\n` +
        'Porta una squadra. Le scuse sono già comprese.',
    });
  };

  const toggleInvites = async (open: boolean) => {
    clearFeedback();
    setBusyAction('invites');
    const outcome = await management.setInvitesOpen(open);
    setBusyAction('');
    if (outcome.error) {
      setFeedback(outcome.error);
      return;
    }
    setSuccess(true);
    setFeedback(open ? 'Inviti riaperti.' : 'Inviti chiusi. Il codice resta memorizzato.');
    onLeagueChanged();
  };

  const rotateInvite = async () => {
    clearFeedback();
    setBusyAction('rotate');

    if (league.isDemo) {
      setInviteCode(`DEMO${String(Date.now()).slice(-6)}`);
      setBusyAction('');
      setSuccess(true);
      setFeedback('Nuovo codice demo generato.');
      return;
    }

    const outcome = await regenerateLeagueInviteCode(league.id);
    setBusyAction('');
    if (outcome.error) {
      setFeedback(outcome.error);
      return;
    }
    setInviteCode(outcome.inviteCode ?? inviteCode);
    setSuccess(true);
    setFeedback('Nuovo codice generato. Quello precedente non vale più.');
    onLeagueChanged();
  };

  const confirmRotateInvite = () => {
    Alert.alert(
      'Generare un nuovo codice?',
      'Il vecchio codice smetterà subito di funzionare.',
      [
        { text: 'ANNULLA', style: 'cancel' },
        { text: 'GENERA', onPress: () => void rotateInvite() },
      ],
    );
  };

  const changeRole = async (member: LeagueMemberSummary) => {
    const nextRole = member.role === 'admin' ? 'manager' : 'admin';
    clearFeedback();
    setBusyAction(`role:${member.userId}`);
    const outcome = await members.changeRole(
      member.userId,
      nextRole,
      state?.accessSession.revision ?? 0,
    );
    setBusyAction('');
    if (outcome.error) {
      setFeedback(outcome.error);
      return;
    }
    setSuccess(true);
    setFeedback(
      nextRole === 'admin'
        ? `${member.displayName} entra nella direzione della lega.`
        : `${member.displayName} torna partecipante.`,
    );
  };

  const removeMember = async (member: LeagueMemberSummary) => {
    clearFeedback();
    setBusyAction(`remove:${member.userId}`);
    const outcome = await members.remove(
      member.userId,
      state?.accessSession.revision ?? 0,
    );
    setBusyAction('');
    if (outcome.error) {
      setFeedback(outcome.error);
      return;
    }
    setSuccess(true);
    setFeedback(`${member.displayName} è stato rimosso dalla lega.`);
    await management.refresh(true);
    onLeagueChanged();
  };

  const confirmRemove = (member: LeagueMemberSummary) => {
    Alert.alert(
      'Rimuovere il partecipante?',
      `${member.displayName} e la sua squadra usciranno dalla lega. È possibile soltanto prima di attività ufficiali.`,
      [
        { text: 'ANNULLA', style: 'cancel' },
        {
          text: 'RIMUOVI',
          style: 'destructive',
          onPress: () => void removeMember(member),
        },
      ],
    );
  };

  const transferPresidency = async (member: LeagueMemberSummary) => {
    clearFeedback();
    setBusyAction(`transfer:${member.userId}`);
    const outcome = await management.transferPresidency(
      member.userId,
      state?.accessSession.revision ?? 0,
    );
    setBusyAction('');
    if (outcome.error) {
      setFeedback(outcome.error);
      return;
    }
    setSuccess(true);
    setFeedback(`${member.displayName} è il nuovo Presidente della lega.`);
    await members.refresh(true);
    onLeagueChanged();
  };

  const confirmTransfer = (member: LeagueMemberSummary) => {
    Alert.alert(
      'Trasferire la presidenza?',
      `${member.displayName} diventerà Presidente. Tu resterai nella direzione come amministratore.`,
      [
        { text: 'ANNULLA', style: 'cancel' },
        {
          text: 'TRASFERISCI',
          style: 'destructive',
          onPress: () => void transferPresidency(member),
        },
      ],
    );
  };

  const startCompetition = async () => {
    clearFeedback();
    setBusyAction('start');
    const outcome = await management.startCompetition();
    setBusyAction('');
    if (outcome.error) {
      setFeedback(outcome.error);
      return;
    }
    setSuccess(true);
    setFeedback('Competizione avviata. Inviti e partecipanti sono ora bloccati.');
    onLeagueChanged();
  };

  const confirmStart = () => {
    Alert.alert(
      'Fischio d’inizio?',
      'Dopo l’avvio gli inviti verranno chiusi e i partecipanti non potranno più essere rimossi.',
      [
        { text: 'NON ANCORA', style: 'cancel' },
        {
          text: 'AVVIA',
          onPress: () => void startCompetition(),
        },
      ],
    );
  };

  const completeSeason = async () => {
    clearFeedback();
    setBusyAction('complete');
    const outcome = await management.completeCompetition();
    setBusyAction('');
    if (outcome.error) {
      setFeedback(outcome.error);
      return;
    }
    setSuccess(true);
    setFeedback(
      'Stagione conclusa. Campione e classifica finale sono nell’albo della lega.',
    );
    onLeagueChanged();
  };

  const confirmComplete = () => {
    Alert.alert(
      'Proclamare il campione?',
      'La classifica finale verrà congelata. Mercato, risultati e correzioni non potranno più cambiare.',
      [
        { text: 'NON ANCORA', style: 'cancel' },
        {
          text: 'CONCLUDI',
          onPress: () => void completeSeason(),
        },
      ],
    );
  };

  const renewSeason = async () => {
    const requestedSeason = nextSeasonInput.trim();
    if (!/^[0-9]{4}$/.test(requestedSeason)) {
      setSuccess(false);
      setFeedback(
        'Inserisci la nuova stagione con quattro cifre, ad esempio 2027.',
      );
      return;
    }

    clearFeedback();
    setBusyAction('renew');
    const outcome = await management.renewCompetition(requestedSeason);
    setBusyAction('');
    if (outcome.error) {
      setFeedback(outcome.error);
      return;
    }

    if (!outcome.renewedLeagueId) {
      setFeedback('La nuova stagione è stata creata, ma non riesco ad aprirla.');
      return;
    }

    setSuccess(true);
    setFeedback(
      `Stagione ${requestedSeason} pronta. Partecipanti, squadre e regolamento sono stati copiati.`,
    );
    await onSeasonRenewed(outcome.renewedLeagueId);
  };

  const confirmRenew = () => {
    const requestedSeason = nextSeasonInput.trim();
    Alert.alert(
      `Preparare la stagione ${requestedSeason || 'successiva'}?`,
      'La stagione conclusa resterà nell’albo. Verranno copiati partecipanti, nomi squadra e regolamento; rose e calendario ripartiranno puliti, con i crediti riportati al budget iniziale.',
      [
        { text: 'NON ANCORA', style: 'cancel' },
        {
          text: 'PREPARA',
          onPress: () => void renewSeason(),
        },
      ],
    );
  };

  const openRenewedSeason = () => {
    if (state?.nextLeagueId) {
      void onSeasonRenewed(state.nextLeagueId);
    }
  };

  return (
    <ScrollView
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
      style={styles.root}
    >
      <View style={styles.header}>
        <Pressable
          onPress={() => onNavigate('league')}
          style={styles.backButton}
        >
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>PANNELLO DEL PRESIDENTE</Text>
          <Text style={styles.title}>Direzione lega</Text>
        </View>
      </View>

      <View style={styles.heroCard}>
        <View style={styles.heroTop}>
          <View style={styles.heroBadge}>
            <Text style={styles.heroBadgeText}>{startedAt ? '✓' : 'P'}</Text>
          </View>
          <View style={styles.heroCopy}>
            <Text style={styles.heroEyebrow}>{league.name.toUpperCase()}</Text>
            <Text style={styles.heroTitle}>
              {completedAt
                ? 'Stagione conclusa'
                : startedAt
                  ? 'Campionato in corso'
                  : 'Prepara lo spogliatoio'}
            </Text>
          </View>
        </View>
        <Text style={styles.heroBody}>
          {completedAt && champion
            ? `${champion.teamName} è Campione. Classifica congelata il ${formatDateTime(completedAt)}.`
            : startedAt
            ? `Avviato il ${formatDateTime(startedAt)}. Adesso parlano i risultati.`
            : 'Controlla ingressi, squadre, rose e calendario prima del via ufficiale.'}
        </Text>
      </View>

      {management.loading ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.navy} />
          <Text style={styles.loadingText}>Controllo i tesserini…</Text>
        </View>
      ) : management.error ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>Direzione non disponibile</Text>
          <Text style={styles.errorBody}>{management.error}</Text>
          <Pressable
            onPress={() => void management.refresh()}
            style={styles.smallButton}
          >
            <Text style={styles.smallButtonText}>RIPROVA</Text>
          </Pressable>
        </View>
      ) : state ? (
        <>
          <Text style={styles.sectionTitle}>Ruolo e permessi</Text>
          <PermissionCard
            permissions={state.permissions}
            revision={state.accessSession.revision}
          />
          <RoleControlCard state={state.roleControl} />
          <RoleSecurityCard security={state.roleControl.security} />

          <Text style={styles.sectionTitle}>Inviti</Text>
          <View style={styles.card}>
            <View style={styles.inviteTop}>
              <View>
                <Text style={styles.cardEyebrow}>CODICE ATTUALE</Text>
                <Text style={styles.inviteCode}>{inviteCode}</Text>
              </View>
              <View
                style={[
                  styles.statusPill,
                  !state.invitesOpen && styles.statusPillClosed,
                ]}
              >
                <Text
                  style={[
                    styles.statusPillText,
                    !state.invitesOpen && styles.statusPillTextClosed,
                  ]}
                >
                  {state.invitesOpen ? 'APERTI' : 'CHIUSI'}
                </Text>
              </View>
            </View>

            <View style={styles.divider} />
            <View style={styles.switchRow}>
              <View style={styles.switchCopy}>
                <Text style={styles.rowTitle}>Accetta nuovi ingressi</Text>
                <Text style={styles.rowBody}>
                  {isOwner
                    ? 'Chiudi gli inviti senza cambiare il codice.'
                    : 'Solo il Presidente può modificare gli ingressi.'}
                </Text>
              </View>
              <Switch
                disabled={
                  !isOwner ||
                  Boolean(startedAt) ||
                  busyAction === 'invites'
                }
                ios_backgroundColor={colors.canvasMuted}
                onValueChange={(open) => void toggleInvites(open)}
                thumbColor={state.invitesOpen ? colors.navy : colors.white}
                trackColor={{
                  false: colors.canvasMuted,
                  true: colors.lime,
                }}
                value={state.invitesOpen}
              />
            </View>

            <View style={styles.doubleButtons}>
              <Pressable
                disabled={!state.invitesOpen}
                onPress={() => void shareInvite()}
                style={[
                  styles.secondaryButton,
                  !state.invitesOpen && styles.buttonDisabled,
                ]}
              >
                <Text style={styles.secondaryButtonText}>CONDIVIDI</Text>
              </Pressable>
              <Pressable
                disabled={
                  !isOwner ||
                  Boolean(startedAt) ||
                  busyAction === 'rotate'
                }
                onPress={confirmRotateInvite}
                style={[
                  styles.secondaryButton,
                  (!isOwner || Boolean(startedAt)) && styles.buttonDisabled,
                ]}
              >
                <Text style={styles.secondaryButtonText}>
                  {busyAction === 'rotate' ? 'ATTENDI…' : 'RIGENERA'}
                </Text>
              </Pressable>
            </View>
          </View>

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Partecipanti</Text>
            <Text style={styles.sectionCount}>
              {members.members.length}/{league.teamLimit}
            </Text>
          </View>
          <View style={styles.card}>
            {members.loading ? (
              <View style={styles.inlineLoading}>
                <ActivityIndicator color={colors.navy} size="small" />
                <Text style={styles.loadingText}>Faccio l’appello…</Text>
              </View>
            ) : members.error ? (
              <Text style={styles.errorBody}>{members.error}</Text>
            ) : (
              members.members.map((member, index) => (
                <DirectionMemberRow
                  busy={busyAction.endsWith(member.userId)}
                  canEdit={isOwner}
                  canTransfer={
                    isOwner &&
                    !member.isOwner &&
                    member.userId !== currentUserId
                  }
                  current={member.userId === currentUserId}
                  key={member.userId}
                  last={index === members.members.length - 1}
                  locked={Boolean(startedAt)}
                  member={member}
                  onRemove={() => confirmRemove(member)}
                  onRole={() => void changeRole(member)}
                  onTransfer={() => confirmTransfer(member)}
                />
              ))
            )}
          </View>

          <Text style={styles.sectionTitle}>
            {startedAt ? 'Struttura competizione' : 'Controlli pre-campionato'}
          </Text>
          <View style={styles.card}>
            <ReadinessRow
              label="Spogliatoio completo"
              ready={state.checks.membersReady}
              value={`${state.memberCount}/${state.teamLimit}`}
            />
            <ReadinessRow
              label="Una squadra per utente"
              ready={state.checks.teamsReady}
              value={`${state.teamCount}/${state.teamLimit}`}
            />
            <ReadinessRow
              label="Rose complete"
              ready={state.checks.rostersReady}
              value={`${state.fullRosterCount}/${state.teamLimit}`}
            />
            <ReadinessRow
              label="Mercato e crediti"
              ready={state.checks.marketReady}
              value={state.checks.marketReady ? 'INTEGRI' : 'DA VERIFICARE'}
            />
            <ReadinessRow
              label="Trattative concluse"
              ready={state.checks.tradesSettled}
              value={state.checks.tradesSettled ? 'OK' : 'IN ATTESA'}
            />
            <ReadinessRow
              label="Asta pre-campionato"
              ready={
                state.checks.auctionIntegrityReady &&
                state.checks.auctionClosed
              }
              value={state.checks.auctionClosed ? 'CONCLUSA' : 'DA CHIUDERE'}
            />
            <ReadinessRow
              label="Calendario verificato"
              ready={
                state.checks.calendarReady &&
                state.checks.calendarIntegrityReady &&
                state.checks.calendarSnapshotStable
              }
              value={
                state.fixtureCount > 0
                  ? `${state.fixtureCount} PARTITE`
                  : 'DA FARE'
              }
            />
            <ReadinessRow
              label="Assetto iniziale congelato"
              ready={
                state.checks.precompetitionSnapshotLocked &&
                state.checks.snapshotMutationGuardReady
              }
              value={
                state.checks.precompetitionSnapshotLocked &&
                state.checks.snapshotMutationGuardReady
                  ? 'PROTETTO'
                  : 'IN ATTESA'
              }
            />
            <ReadinessRow
              label="Apertura competizione"
              ready={state.checks.competitionActivationReady}
              value={
                state.checks.competitionActivationReady
                  ? 'CERTIFICATA'
                  : 'IN ATTESA'
              }
            />
            <ReadinessRow
              label="Modello competizione"
              ready={state.checks.competitionModelClosed}
              value={
                state.checks.competitionModelClosed
                  ? 'PROTETTO'
                  : 'IN ATTESA'
              }
            />
            <ReadinessRow
              label="Distinte e panchina"
              ready={state.checks.lineupLifecycleReady}
              value={
                state.checks.lineupLifecycleReady
                  ? 'CERTIFICATE'
                  : 'DA VERIFICARE'
              }
            />
            <ReadinessRow
              label="Live e risultati"
              ready={state.checks.liveLifecycleReady}
              value={
                state.checks.liveLifecycleReady
                  ? 'COERENTI'
                  : 'DA VERIFICARE'
              }
            />
            <ReadinessRow
              label="Ciclo giornata"
              ready={state.checks.matchdayLifecycleReady}
              value={
                state.checks.matchdayLifecycleReady
                  ? 'PROTETTO'
                  : 'DA VERIFICARE'
              }
            />
            <ReadinessRow
              label="Motore giornata"
              ready={state.checks.matchdayModelClosed}
              value={
                state.checks.matchdayModelClosed
                  ? 'CERTIFICATO'
                  : 'DA CERTIFICARE'
              }
            />
            <ReadinessRow
              label="Competizioni speciali"
              last
              ready={state.checks.specialCompetitionsModelClosed}
              value={
                state.checks.specialCompetitionsModelClosed
                  ? 'CERTIFICATE'
                  : 'DA CERTIFICARE'
              }
            />
          </View>

          {feedback ? (
            <Text style={[styles.feedback, success && styles.feedbackSuccess]}>
              {feedback}
            </Text>
          ) : null}

          {state.providerSeasonBootstrapApplicable ? (
            <View
              style={
                state.providerSeasonBootstrapAffected
                  ? styles.errorCard
                  : state.providerSeasonBootstrapCertified
                    ? styles.renewalReadyCard
                    : styles.infoCard
              }
            >
              <Text
                style={
                  state.providerSeasonBootstrapAffected
                    ? styles.errorTitle
                    : styles.infoTitle
                }
              >
                BOOTSTRAP PROVIDER NUOVA STAGIONE
              </Text>
              <Text
                style={
                  state.providerSeasonBootstrapAffected
                    ? styles.errorBody
                    : styles.infoBody
                }
              >
                Catalogo calciatori: {state.providerSeasonCatalogReady ? 'pronto' : 'in attesa'}.
                {' '}Calendario Serie A: {state.providerSeasonFixturesReady ? 'copertura completa' : 'in attesa'}.
                {state.providerSeasonBootstrapCertified
                  ? ' Scope provider certificato.'
                  : ''}
                {state.providerSeasonBootstrapAffected
                  ? ` Verifica richiesta: ${state.providerSeasonBootstrapReason ?? 'anomalia provider'}.`
                  : ''}
              </Text>
            </View>
          ) : null}

          {state.providerCompetitionStartApplicable ? (
            <View
              style={
                state.providerCompetitionStartAffected
                  ? styles.errorCard
                  : state.providerCompetitionStartCertified
                    ? styles.renewalReadyCard
                    : styles.infoCard
              }
            >
              <Text
                style={
                  state.providerCompetitionStartAffected
                    ? styles.errorTitle
                    : styles.infoTitle
                }
              >
                AVVIO COMPETIZIONE CERTIFICATO
              </Text>
              <Text
                style={
                  state.providerCompetitionStartAffected
                    ? styles.errorBody
                    : styles.infoBody
                }
              >
                {state.providerCompetitionStartCertified
                  ? 'Avvio, calendario e bootstrap provider sono legati da un certificato immutabile.'
                  : state.providerCompetitionStartReady
                    ? 'La barriera provider è pronta: la Direzione può avviare la competizione.'
                    : 'Avvio in attesa della certificazione completa di calendario e provider.'}
                {state.providerCompetitionStartAffected
                  ? ` Verifica richiesta: ${state.providerCompetitionStartReason ?? 'catena di avvio non coerente'}.`
                  : ''}
              </Text>
            </View>
          ) : null}

          {completedAt && champion ? (
            <>
              <View style={styles.championCard}>
                <Text style={styles.championEyebrow}>
                  ALBO D’ORO · STAGIONE {state.season ?? '—'}
                </Text>
                <Text style={styles.championTitle}>{champion.teamName}</Text>
                <Text style={styles.championManager}>
                  {champion.managerName} · {champion.leaguePoints} PUNTI
                </Text>
                <Text style={styles.championBody}>
                  Proclamata il {formatDateTime(completedAt)}. Risultati,
                  classifica e regolamento sono congelati in uno snapshot
                  ufficiale immutabile.
                </Text>
              </View>

              {state.officialSnapshotAffected ? (
                <View style={styles.errorCard}>
                  <Text style={styles.errorTitle}>
                    SNAPSHOT UFFICIALE DA VERIFICARE
                  </Text>
                  <Text style={styles.errorBody}>
                    Una regressione provider successiva ha interessato la
                    catena certificata. Campione e classifica storica non sono
                    stati modificati: la Direzione deve verificare il motivo{' '}
                    {state.officialSnapshotReason ?? 'segnalato dal database'}.
                  </Text>
                </View>
              ) : null}

              <Text style={styles.sectionTitle}>Continuità della lega</Text>
              {state.nextLeagueId ? (
                <View style={styles.renewalReadyCard}>
                  <Text style={styles.renewalReadyEyebrow}>
                    STAGIONE {state.nextSeason ?? 'SUCCESSIVA'} PRONTA
                  </Text>
                  <Text style={styles.renewalReadyTitle}>
                    Il nuovo spogliatoio è aperto.
                  </Text>
                  <Text style={styles.renewalReadyBody}>
                    {state.renewalCopiedMemberCount || state.memberCount}{' '}
                    partecipanti e relative squadre sono stati trasferiti.
                    Rose e calendario ripartono puliti.
                    {state.seasonRolloverCertified
                      ? ' Continuità certificata con lo snapshot ufficiale.'
                      : ''}
                  </Text>
                  {state.seasonRolloverAffected ? (
                    <View style={styles.errorCard}>
                      <Text style={styles.errorTitle}>
                        CONTINUITÀ TRA STAGIONI DA VERIFICARE
                      </Text>
                      <Text style={styles.errorBody}>
                        La nuova stagione resta disponibile, ma il certificato
                        di lineage è stato marcato come interessato. La
                        Direzione deve verificare il motivo{' '}
                        {state.seasonRolloverReason ?? 'segnalato dal database'}.
                      </Text>
                    </View>
                  ) : null}
                  <Pressable
                    onPress={openRenewedSeason}
                    style={styles.openRenewalButton}
                  >
                    <Text style={styles.openRenewalButtonText}>
                      APRI LA NUOVA STAGIONE →
                    </Text>
                  </Pressable>
                </View>
              ) : isOwner ? (
                <View style={styles.renewalCard}>
                  <Text style={styles.renewalTitle}>Ripartire senza perdere nulla</Text>
                  <Text style={styles.renewalBody}>
                    Copia partecipanti, nomi squadra e regolamento in una nuova
                    lega collegata. Crediti al budget iniziale, rose e
                    calendario da ricostruire. Il rinnovo si sblocca solo dopo
                    la certificazione dello snapshot ufficiale.
                  </Text>
                  <View style={styles.seasonInputRow}>
                    <View style={styles.seasonInputCopy}>
                      <Text style={styles.seasonInputLabel}>
                        NUOVA STAGIONE
                      </Text>
                      <Text style={styles.seasonInputHint}>
                        Quella conclusa resta consultabile nell’albo.
                      </Text>
                    </View>
                    <TextInput
                      keyboardType="number-pad"
                      maxLength={4}
                      onChangeText={setNextSeasonInput}
                      placeholder="2027"
                      placeholderTextColor={colors.muted}
                      style={styles.seasonInput}
                      value={nextSeasonInput}
                    />
                  </View>
                  <Pressable
                    disabled={!state.canRenew || busyAction === 'renew'}
                    onPress={confirmRenew}
                    style={[
                      styles.renewButton,
                      (!state.canRenew || busyAction === 'renew') &&
                        styles.buttonDisabled,
                    ]}
                  >
                    <Text style={styles.renewButtonText}>
                      {busyAction === 'renew'
                        ? 'PREPARAZIONE IN CORSO…'
                        : 'PREPARA LA NUOVA STAGIONE'}
                    </Text>
                  </Pressable>
                </View>
              ) : (
                <View style={styles.adminNotice}>
                  <Text style={styles.adminNoticeTitle}>
                    Il rinnovo spetta al Presidente
                  </Text>
                  <Text style={styles.adminNoticeBody}>
                    La direzione conserva l’albo, ma solo il Presidente può
                    creare la stagione successiva.
                  </Text>
                </View>
              )}
            </>
          ) : startedAt ? (
            <>
              <View style={styles.startedCard}>
                <Text style={styles.startedEyebrow}>COMPETIZIONE ATTIVA</Text>
                <Text style={styles.startedTitle}>Il pallone è in gioco.</Text>
                <Text style={styles.startedBody}>
                  Inviti chiusi e partecipanti bloccati per proteggere il
                  campionato. Giornata iniziale{' '}
                  {state.competitionLifecycle.currentMatchdayNumber || '—'} ·
                  avvio certificato R{state.competitionLifecycle.revision || 1}
                  {state.competitionLifecycle.modelClosed
                    ? ' · calendario protetto'
                    : ''}.
                </Text>
              </View>

              <Text style={styles.sectionTitle}>Chiusura stagione</Text>
              <View style={styles.card}>
                <ReadinessRow
                  label="Risultati ufficiali"
                  last
                  ready={
                    state.fixtureCount > 0 &&
                    state.remainingFixtureCount === 0
                  }
                  value={`${state.officialFixtureCount}/${state.fixtureCount}`}
                />
              </View>

              {isOwner ? (
                <>
                  {!state.canComplete ? (
                    <Text style={styles.startHint}>
                      {state.seasonCompletionAffected
                        ? 'La stagione risulta conclusa, ma una progressione precedente non è più causalmente certificata. La Direzione deve verificare la catena provider.'
                        : state.seasonCompletionCausalStatus === 'blocked'
                          ? 'Il campione può essere proclamato soltanto quando tutte le giornate possiedono una progressione provider corrente e certificata.'
                          : 'Il campione può essere proclamato soltanto quando tutte le partite sono ufficiali.'}
                    </Text>
                  ) : null}
                  <Pressable
                    disabled={
                      !state.canComplete || busyAction === 'complete'
                    }
                    onPress={confirmComplete}
                    style={[
                      styles.completeButton,
                      (!state.canComplete || busyAction === 'complete') &&
                        styles.buttonDisabled,
                    ]}
                  >
                    <Text style={styles.completeButtonText}>
                      {busyAction === 'complete'
                        ? 'CHIUSURA IN CORSO…'
                        : 'PROCLAMA IL CAMPIONE'}
                    </Text>
                  </Pressable>
                </>
              ) : (
                <View style={styles.adminNotice}>
                  <Text style={styles.adminNoticeTitle}>
                    Ultima parola al Presidente
                  </Text>
                  <Text style={styles.adminNoticeBody}>
                    La direzione può seguire il completamento, ma solo il
                    Presidente può congelare la classifica finale.
                  </Text>
                </View>
              )}
            </>
          ) : isOwner ? (
            <>
              {!state.canStart ? (
                <Text style={styles.startHint}>
                  Completa tutti i controlli prima del fischio d’inizio.
                </Text>
              ) : null}
              <Pressable
                disabled={!state.canStart || busyAction === 'start'}
                onPress={confirmStart}
                style={[
                  styles.startButton,
                  (!state.canStart || busyAction === 'start') &&
                    styles.buttonDisabled,
                ]}
              >
                <Text style={styles.startButtonText}>
                  {busyAction === 'start'
                    ? 'AVVIO IN CORSO…'
                    : 'AVVIA COMPETIZIONE'}
                </Text>
              </Pressable>
            </>
          ) : (
            <View style={styles.adminNotice}>
              <Text style={styles.adminNoticeTitle}>Ultima parola al Presidente</Text>
              <Text style={styles.adminNoticeBody}>
                Puoi amministrare la lega, ma solo il Presidente può dare il via
                o trasferire la presidenza.
              </Text>
            </View>
          )}
        </>
      ) : null}
    </ScrollView>
  );
}

function PermissionCard({
  permissions,
  revision,
}: {
  permissions: LeaguePermissionState;
  revision: number;
}) {
  const labels =
    permissions.role === 'president'
      ? ['RUOLI', 'INVITI', 'AVVIO', 'REGOLE']
      : permissions.role === 'admin'
        ? ['ASTA', 'CALENDARIO', 'REGOLE', 'RISULTATI']
        : ['ROSA', 'FORMAZIONE', 'MERCATO', 'SCAMBI'];
  const title =
    permissions.role === 'president'
      ? 'Presidente'
      : permissions.role === 'admin'
        ? 'Admin'
        : 'Mister';
  const body =
    permissions.role === 'president'
      ? 'Hai l’ultima parola su persone, ruoli e avvio della competizione.'
      : permissions.role === 'admin'
        ? 'Gestisci le operazioni sportive. Ruoli e presidenza restano al Presidente.'
        : 'Gestisci la tua squadra. Le decisioni di lega spettano alla direzione.';

  return (
    <View style={styles.permissionCard}>
      <View style={styles.permissionTop}>
        <View style={styles.permissionBadge}>
          <Text style={styles.permissionBadgeText}>
            {permissions.role === 'president'
              ? 'P'
              : permissions.role === 'admin'
                ? 'A'
                : 'M'}
          </Text>
        </View>
        <View style={styles.permissionCopy}>
          <Text style={styles.permissionEyebrow}>IL TUO RUOLO</Text>
          <Text style={styles.permissionTitle}>{title}</Text>
        </View>
      </View>
      <Text style={styles.permissionBody}>{body}</Text>
      <View style={styles.permissionChips}>
        {labels.map((label) => (
          <View key={label} style={styles.permissionChip}>
            <Text style={styles.permissionChipText}>{label}</Text>
          </View>
        ))}
      </View>
      <Text style={styles.permissionSyncText}>
        Permessi sincronizzati · revisione {revision} · protezione multi-dispositivo attiva
      </Text>
    </View>
  );
}


function RoleControlCard({ state }: { state: LeagueRoleControlState }) {
  const integrity = state.integrity;
  return (
    <View style={styles.roleControlCard}>
      <View style={styles.roleControlHeader}>
        <View>
          <Text style={styles.permissionEyebrow}>CONTROLLO DATABASE</Text>
          <Text style={styles.roleControlTitle}>Integrità ruoli</Text>
        </View>
        <View
          style={[
            styles.roleControlStatus,
            !integrity.healthy && styles.roleControlStatusWarning,
          ]}
        >
          <Text
            style={[
              styles.roleControlStatusText,
              !integrity.healthy && styles.roleControlStatusTextWarning,
            ]}
          >
            {integrity.healthy ? 'PROTETTA' : 'DA VERIFICARE'}
          </Text>
        </View>
      </View>
      <View style={styles.roleControlStats}>
        <RoleStat label="PARTECIPANTI" value={integrity.memberCount} />
        <RoleStat label="ADMIN" value={integrity.adminCount} />
        <RoleStat label="SQUADRE" value={integrity.teamCount} />
      </View>
      <View style={styles.roleChecks}>
        <RoleCheck label="Presidente presente" ready={integrity.ownerMemberExists} />
        <RoleCheck label="Profilo Presidente attivo" ready={integrity.ownerProfileActive} />
        <RoleCheck label="Manager iscritti alla lega" ready={integrity.teamManagersAreMembers} />
        <RoleCheck label="Una squadra per Mister" ready={integrity.oneTeamPerManager} />
      </View>
      <Text style={styles.roleAuditTitle}>ULTIME MODIFICHE AI RUOLI</Text>
      {state.events.length ? (
        state.events.slice(0, 4).map((event, index) => (
          <RoleAuditRow
            event={event}
            key={event.id}
            last={index === Math.min(state.events.length, 4) - 1}
          />
        ))
      ) : (
        <Text style={styles.roleAuditEmpty}>
          Nessuna nomina o variazione di presidenza registrata.
        </Text>
      )}
    </View>
  );
}

function RoleSecurityCard({ security }: { security: LeagueRoleSecurity }) {
  const checks = [
    {
      label: 'Cambio ruoli solo tramite azione protetta',
      ready: security.directRoleMutationBlocked,
    },
    {
      label: 'Trasferimento presidenza protetto',
      ready: security.directPresidencyMutationBlocked,
    },
    {
      label: 'Rimozione partecipanti protetta',
      ready: security.directRemovalBlocked,
    },
    {
      label: 'Controllo revisione multi-dispositivo',
      ready: security.guardedActionsReady,
    },
  ];

  return (
    <View style={styles.roleSecurityCard}>
      <View style={styles.roleControlHeader}>
        <View>
          <Text style={styles.roleSecurityEyebrow}>MATRICE ACCESSI</Text>
          <Text style={styles.roleSecurityTitle}>Gerarchia operativa</Text>
        </View>
        <View
          style={[
            styles.roleControlStatus,
            !security.hardened && styles.roleControlStatusWarning,
          ]}
        >
          <Text
            style={[
              styles.roleControlStatusText,
              !security.hardened && styles.roleControlStatusTextWarning,
            ]}
          >
            {security.hardened ? 'BLINDATA' : 'DA COMPLETARE'}
          </Text>
        </View>
      </View>

      <View style={styles.roleControlStats}>
        <RoleStat label="PRESIDENTE" value={security.presidentCount} />
        <RoleStat label="ADMIN" value={security.adminCount} />
        <RoleStat label="MISTER" value={security.managerCount} />
      </View>

      <View style={styles.roleChecks}>
        {checks.map((check) => (
          <View key={check.label} style={styles.roleCheckRow}>
            <Text
              style={[
                styles.roleSecurityCheckIcon,
                !check.ready && styles.roleCheckIconWarning,
              ]}
            >
              {check.ready ? '✓' : '!'}
            </Text>
            <Text style={styles.roleSecurityCheckLabel}>{check.label}</Text>
          </View>
        ))}
      </View>

      {security.members.length ? (
        <View style={styles.roleMatrixList}>
          {security.members.map((member, index) => (
            <View
              key={member.userId}
              style={[
                styles.roleMatrixRow,
                index === security.members.length - 1 &&
                  styles.roleMatrixRowLast,
              ]}
            >
              <View style={styles.roleMatrixCopy}>
                <Text numberOfLines={1} style={styles.roleMatrixName}>
                  {member.displayName}
                </Text>
                <Text numberOfLines={1} style={styles.roleMatrixTeam}>
                  {member.teamName ?? 'Squadra da completare'}
                </Text>
              </View>
              <View style={styles.roleMatrixBadge}>
                <Text style={styles.roleMatrixBadgeText}>
                  {member.role === 'president'
                    ? 'PRESIDENTE'
                    : member.role === 'admin'
                      ? 'ADMIN'
                      : 'MISTER'}
                </Text>
              </View>
            </View>
          ))}
        </View>
      ) : (
        <Text style={styles.roleAuditEmpty}>
          La matrice dettagliata sarà disponibile dopo lo script 065.
        </Text>
      )}
    </View>
  );
}

function RoleStat({ label, value }: { label: string; value: number }) {
  return (
    <View style={styles.roleStat}>
      <Text style={styles.roleStatValue}>{value}</Text>
      <Text style={styles.roleStatLabel}>{label}</Text>
    </View>
  );
}

function RoleCheck({ label, ready }: { label: string; ready: boolean }) {
  return (
    <View style={styles.roleCheckRow}>
      <Text style={[styles.roleCheckIcon, !ready && styles.roleCheckIconWarning]}>
        {ready ? '✓' : '!'}
      </Text>
      <Text style={styles.roleCheckLabel}>{label}</Text>
    </View>
  );
}

function RoleAuditRow({
  event,
  last,
}: {
  event: LeagueRoleAuditEvent;
  last: boolean;
}) {
  const description =
    event.type === 'admin_granted'
      ? `${event.targetName} nominato Admin`
      : event.type === 'admin_revoked'
        ? `${event.targetName} torna Mister`
        : `Presidenza trasferita a ${event.targetName}`;
  return (
    <View style={[styles.roleAuditRow, last && styles.roleAuditRowLast]}>
      <View style={styles.roleAuditDot} />
      <View style={styles.roleAuditCopy}>
        <Text style={styles.roleAuditText}>{description}</Text>
        <Text style={styles.roleAuditMeta}>
          {event.actorName} · {formatDateTime(event.createdAt)}
        </Text>
      </View>
    </View>
  );
}

function DirectionMemberRow({
  busy,
  canEdit,
  canTransfer,
  current,
  last,
  locked,
  member,
  onRemove,
  onRole,
  onTransfer,
}: {
  busy: boolean;
  canEdit: boolean;
  canTransfer: boolean;
  current: boolean;
  last: boolean;
  locked: boolean;
  member: LeagueMemberSummary;
  onRemove: () => void;
  onRole: () => void;
  onTransfer: () => void;
}) {
  const initials = member.displayName
    .trim()
    .split(/\s+/)
    .map((part) => part[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
  const protectedMember = Boolean(member.isOwner) || current || locked;

  return (
    <View style={[styles.memberBlock, last && styles.memberBlockLast]}>
      <View style={styles.memberMain}>
        <View style={styles.memberAvatar}>
          <Text style={styles.memberAvatarText}>{initials || 'LV'}</Text>
        </View>
        <View style={styles.memberCopy}>
          <Text numberOfLines={1} style={styles.memberName}>
            {member.displayName}
            {current ? ' · TU' : ''}
          </Text>
          <Text numberOfLines={1} style={styles.memberTeam}>
            {member.team?.name ?? 'Squadra da completare'}
          </Text>
        </View>
        <View
          style={[
            styles.rolePill,
            member.isOwner && styles.ownerPill,
          ]}
        >
          <Text
            style={[
              styles.rolePillText,
              member.isOwner && styles.ownerPillText,
            ]}
          >
            {member.isOwner
              ? 'PRESIDENTE'
              : member.role === 'admin'
                ? 'ADMIN'
                : 'MISTER'}
          </Text>
        </View>
      </View>

      {canEdit && !protectedMember ? (
        <View style={styles.memberActions}>
          <Pressable
            disabled={busy}
            onPress={onRole}
            style={styles.memberAction}
          >
            <Text style={styles.memberActionText}>
              {member.role === 'admin' ? 'REVOCA ADMIN' : 'NOMINA ADMIN'}
            </Text>
          </Pressable>
          <Pressable
            disabled={busy}
            onPress={onRemove}
            style={styles.memberDangerAction}
          >
            <Text style={styles.memberDangerText}>RIMUOVI</Text>
          </Pressable>
        </View>
      ) : null}

      {canTransfer && !locked ? (
        <Pressable
          disabled={busy}
          onPress={onTransfer}
          style={styles.transferButton}
        >
          <Text style={styles.transferButtonText}>
            TRASFERISCI PRESIDENZA →
          </Text>
        </Pressable>
      ) : null}
    </View>
  );
}

function ReadinessRow({
  label,
  last = false,
  ready,
  value,
}: {
  label: string;
  last?: boolean;
  ready: boolean;
  value: string;
}) {
  return (
    <View style={[styles.checkRow, last && styles.checkRowLast]}>
      <View
        style={[
          styles.checkIcon,
          ready ? styles.checkIconReady : styles.checkIconWaiting,
        ]}
      >
        <Text
          style={[
            styles.checkIconText,
            !ready && styles.checkIconTextWaiting,
          ]}
        >
          {ready ? '✓' : '·'}
        </Text>
      </View>
      <Text style={styles.checkLabel}>{label}</Text>
      <Text style={[styles.checkValue, ready && styles.checkValueReady]}>
        {value}
      </Text>
    </View>
  );
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value));
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    paddingHorizontal: 20,
    paddingTop: 18,
    paddingBottom: 42,
  },
  centerRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 32,
    backgroundColor: colors.canvas,
  },
  centerTitle: {
    color: colors.navy,
    fontSize: 24,
    fontWeight: '900',
    textAlign: 'center',
  },
  centerBody: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 20,
    marginTop: 10,
    textAlign: 'center',
  },
  lockBadge: {
    width: 56,
    height: 56,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 18,
    backgroundColor: colors.navy,
  },
  lockBadgeText: {
    color: colors.lime,
    fontSize: 20,
    fontWeight: '900',
  },
  header: {
    minHeight: 50,
    flexDirection: 'row',
    alignItems: 'center',
  },
  backButton: {
    width: 38,
    height: 38,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  backText: {
    color: colors.navy,
    fontSize: 28,
    lineHeight: 30,
  },
  headerCopy: {
    marginLeft: 13,
  },
  eyebrow: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  title: {
    color: colors.navy,
    fontSize: 24,
    fontWeight: '900',
    marginTop: 2,
  },
  heroCard: {
    borderRadius: radius.xl,
    padding: 20,
    marginTop: 20,
    backgroundColor: colors.navy,
  },
  heroTop: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  heroBadge: {
    width: 46,
    height: 46,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  heroBadgeText: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
  },
  heroCopy: {
    flex: 1,
    marginLeft: 14,
  },
  heroEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  heroTitle: {
    color: colors.white,
    fontSize: 20,
    fontWeight: '900',
    marginTop: 3,
  },
  heroBody: {
    color: colors.mutedLight,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 15,
  },
  permissionCard: {
    borderRadius: radius.lg,
    padding: 17,
    backgroundColor: colors.white,
  },
  permissionTop: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  permissionBadge: {
    width: 42,
    height: 42,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  permissionBadgeText: {
    color: colors.lime,
    fontSize: 16,
    fontWeight: '900',
  },
  permissionCopy: {
    marginLeft: 12,
  },
  permissionEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  permissionTitle: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
    marginTop: 2,
  },
  permissionBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 13,
  },
  permissionChips: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 7,
    marginTop: 14,
  },
  permissionSyncText: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '700',
    marginTop: 13,
  },
  permissionChip: {
    borderRadius: 14,
    paddingHorizontal: 9,
    paddingVertical: 6,
    backgroundColor: colors.canvasMuted,
  },
  permissionChipText: {
    color: colors.navy,
    fontSize: 7,
    fontWeight: '900',
  },

  roleSecurityCard: {
    borderRadius: radius.lg,
    padding: 17,
    marginTop: 10,
    backgroundColor: colors.navy,
  },
  roleSecurityEyebrow: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  roleSecurityTitle: {
    color: colors.white,
    fontSize: 15,
    fontWeight: '900',
    marginTop: 2,
  },
  roleSecurityCheckIcon: {
    width: 20,
    color: colors.lime,
    fontSize: 11,
    fontWeight: '900',
  },
  roleSecurityCheckLabel: {
    color: colors.mutedLight,
    fontSize: 10,
    fontWeight: '700',
  },
  roleMatrixList: {
    borderRadius: 12,
    overflow: 'hidden',
    marginTop: 14,
    backgroundColor: 'rgba(255,255,255,0.08)',
  },
  roleMatrixRow: {
    minHeight: 50,
    flexDirection: 'row',
    alignItems: 'center',
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.09)',
    paddingHorizontal: 12,
  },
  roleMatrixRowLast: {
    borderBottomWidth: 0,
  },
  roleMatrixCopy: {
    flex: 1,
    paddingRight: 10,
  },
  roleMatrixName: {
    color: colors.white,
    fontSize: 10,
    fontWeight: '900',
  },
  roleMatrixTeam: {
    color: colors.mutedLight,
    fontSize: 8,
    marginTop: 3,
  },
  roleMatrixBadge: {
    borderRadius: 12,
    paddingHorizontal: 8,
    paddingVertical: 5,
    backgroundColor: colors.lime,
  },
  roleMatrixBadgeText: {
    color: colors.navy,
    fontSize: 6,
    fontWeight: '900',
  },

  roleControlCard: {
    borderRadius: radius.lg,
    padding: 17,
    marginTop: 10,
    backgroundColor: colors.white,
  },
  roleControlHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  roleControlTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
    marginTop: 2,
  },
  roleControlStatus: {
    borderRadius: 16,
    paddingHorizontal: 9,
    paddingVertical: 6,
    backgroundColor: colors.lime,
  },
  roleControlStatusWarning: {
    backgroundColor: '#FFE7E5',
  },
  roleControlStatusText: {
    color: colors.navy,
    fontSize: 7,
    fontWeight: '900',
  },
  roleControlStatusTextWarning: {
    color: colors.danger,
  },
  roleControlStats: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 15,
  },
  roleStat: {
    flex: 1,
    borderRadius: 12,
    paddingVertical: 10,
    alignItems: 'center',
    backgroundColor: colors.canvasMuted,
  },
  roleStatValue: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  roleStatLabel: {
    color: colors.muted,
    fontSize: 6,
    fontWeight: '900',
    marginTop: 3,
  },
  roleChecks: {
    marginTop: 14,
  },
  roleCheckRow: {
    minHeight: 28,
    flexDirection: 'row',
    alignItems: 'center',
  },
  roleCheckIcon: {
    width: 20,
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  roleCheckIconWarning: {
    color: colors.danger,
  },
  roleCheckLabel: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '700',
  },
  roleAuditTitle: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.5,
    marginTop: 16,
    marginBottom: 5,
  },
  roleAuditRow: {
    minHeight: 45,
    flexDirection: 'row',
    alignItems: 'center',
    borderBottomWidth: 1,
    borderBottomColor: colors.canvasMuted,
  },
  roleAuditRowLast: {
    borderBottomWidth: 0,
  },
  roleAuditDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.lime,
  },
  roleAuditCopy: {
    flex: 1,
    marginLeft: 10,
  },
  roleAuditText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  roleAuditMeta: {
    color: colors.muted,
    fontSize: 8,
    marginTop: 3,
  },
  roleAuditEmpty: {
    color: colors.muted,
    fontSize: 10,
    lineHeight: 15,
    paddingVertical: 8,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
    marginTop: 24,
    marginBottom: 10,
  },
  sectionCount: {
    color: colors.muted,
    fontSize: 11,
    fontWeight: '900',
    marginTop: 24,
  },
  card: {
    borderRadius: radius.lg,
    padding: 17,
    backgroundColor: colors.white,
  },
  cardEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  inviteTop: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  inviteCode: {
    color: colors.navy,
    fontSize: 23,
    fontWeight: '900',
    letterSpacing: 1,
    marginTop: 3,
  },
  statusPill: {
    borderRadius: 20,
    paddingHorizontal: 10,
    paddingVertical: 6,
    backgroundColor: colors.lime,
  },
  statusPillClosed: {
    backgroundColor: colors.canvasMuted,
  },
  statusPillText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  statusPillTextClosed: {
    color: colors.muted,
  },
  divider: {
    height: 1,
    marginVertical: 16,
    backgroundColor: colors.canvasMuted,
  },
  switchRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  switchCopy: {
    flex: 1,
    paddingRight: 15,
  },
  rowTitle: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  rowBody: {
    color: colors.muted,
    fontSize: 10,
    lineHeight: 15,
    marginTop: 3,
  },
  doubleButtons: {
    flexDirection: 'row',
    gap: 10,
    marginTop: 16,
  },
  secondaryButton: {
    flex: 1,
    height: 42,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.navy,
    alignItems: 'center',
    justifyContent: 'center',
  },
  secondaryButtonText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  memberBlock: {
    paddingBottom: 15,
    marginBottom: 15,
    borderBottomWidth: 1,
    borderBottomColor: colors.canvasMuted,
  },
  memberBlockLast: {
    paddingBottom: 0,
    marginBottom: 0,
    borderBottomWidth: 0,
  },
  memberMain: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  memberAvatar: {
    width: 38,
    height: 38,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  memberAvatarText: {
    color: colors.lime,
    fontSize: 11,
    fontWeight: '900',
  },
  memberCopy: {
    flex: 1,
    marginLeft: 11,
    paddingRight: 8,
  },
  memberName: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  memberTeam: {
    color: colors.muted,
    fontSize: 9,
    marginTop: 3,
  },
  rolePill: {
    borderRadius: 15,
    paddingHorizontal: 8,
    paddingVertical: 5,
    backgroundColor: colors.canvasMuted,
  },
  ownerPill: {
    backgroundColor: colors.lime,
  },
  rolePillText: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  ownerPillText: {
    color: colors.navy,
  },
  memberActions: {
    flexDirection: 'row',
    gap: 9,
    marginTop: 11,
    marginLeft: 49,
  },
  memberAction: {
    borderRadius: 10,
    paddingHorizontal: 10,
    paddingVertical: 7,
    backgroundColor: colors.canvasMuted,
  },
  memberActionText: {
    color: colors.navy,
    fontSize: 7,
    fontWeight: '900',
  },
  memberDangerAction: {
    borderRadius: 10,
    paddingHorizontal: 10,
    paddingVertical: 7,
    backgroundColor: '#FFE7E5',
  },
  memberDangerText: {
    color: colors.danger,
    fontSize: 7,
    fontWeight: '900',
  },
  transferButton: {
    alignSelf: 'flex-start',
    marginTop: 10,
    marginLeft: 49,
  },
  transferButtonText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    textDecorationLine: 'underline',
  },
  checkRow: {
    minHeight: 45,
    flexDirection: 'row',
    alignItems: 'center',
    borderBottomWidth: 1,
    borderBottomColor: colors.canvasMuted,
  },
  checkRowLast: {
    borderBottomWidth: 0,
  },
  checkIcon: {
    width: 24,
    height: 24,
    borderRadius: 9,
    alignItems: 'center',
    justifyContent: 'center',
  },
  checkIconReady: {
    backgroundColor: colors.lime,
  },
  checkIconWaiting: {
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    backgroundColor: colors.canvas,
  },
  checkIconText: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  checkIconTextWaiting: {
    color: colors.muted,
  },
  checkLabel: {
    flex: 1,
    color: colors.navy,
    fontSize: 11,
    fontWeight: '800',
    marginLeft: 10,
  },
  checkValue: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  checkValueReady: {
    color: colors.navy,
  },
  feedback: {
    color: colors.danger,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 16,
    textAlign: 'center',
  },
  feedbackSuccess: {
    color: '#4C7D00',
  },
  startHint: {
    color: colors.muted,
    fontSize: 10,
    lineHeight: 15,
    marginTop: 18,
    textAlign: 'center',
  },
  startButton: {
    height: 54,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 11,
    backgroundColor: colors.lime,
  },
  startButtonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  completeButton: {
    height: 54,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 11,
    backgroundColor: colors.navy,
  },
  completeButtonText: {
    color: colors.lime,
    fontSize: 11,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  primaryButton: {
    height: 50,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 22,
    marginTop: 22,
    backgroundColor: colors.lime,
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  smallButton: {
    alignSelf: 'flex-start',
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 8,
    marginTop: 12,
    backgroundColor: colors.navy,
  },
  smallButtonText: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
  },
  buttonDisabled: {
    opacity: 0.35,
  },
  loadingCard: {
    borderRadius: radius.lg,
    alignItems: 'center',
    padding: 24,
    marginTop: 22,
    backgroundColor: colors.white,
  },
  inlineLoading: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  loadingText: {
    color: colors.muted,
    fontSize: 11,
    marginLeft: 10,
  },
  infoCard: {
    borderRadius: radius.lg,
    padding: 18,
    marginTop: 22,
    backgroundColor: colors.canvasMuted,
  },
  infoTitle: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  infoBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 5,
  },
  errorCard: {
    borderRadius: radius.lg,
    padding: 18,
    marginTop: 22,
    backgroundColor: '#FFE7E5',
  },
  errorTitle: {
    color: colors.danger,
    fontSize: 14,
    fontWeight: '900',
  },
  errorBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 5,
  },
  startedCard: {
    borderRadius: radius.lg,
    padding: 20,
    marginTop: 20,
    backgroundColor: colors.navy,
  },
  startedEyebrow: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  startedTitle: {
    color: colors.white,
    fontSize: 18,
    fontWeight: '900',
    marginTop: 5,
  },
  startedBody: {
    color: colors.mutedLight,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 6,
  },
  championCard: {
    borderRadius: radius.xl,
    padding: 22,
    marginTop: 20,
    backgroundColor: colors.navy,
  },
  championEyebrow: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.6,
  },
  championTitle: {
    color: colors.warmWhite,
    fontSize: 26,
    fontWeight: '900',
    marginTop: 7,
  },
  championManager: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
    marginTop: 5,
  },
  championBody: {
    color: colors.mutedLight,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 15,
  },
  renewalCard: {
    borderRadius: radius.lg,
    padding: 19,
    backgroundColor: colors.white,
  },
  renewalTitle: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  renewalBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 7,
  },
  seasonInputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 18,
  },
  seasonInputCopy: {
    flex: 1,
    paddingRight: 14,
  },
  seasonInputLabel: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  seasonInputHint: {
    color: colors.muted,
    fontSize: 9,
    lineHeight: 14,
    marginTop: 3,
  },
  seasonInput: {
    width: 82,
    height: 44,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
    textAlign: 'center',
    backgroundColor: colors.canvas,
  },
  renewButton: {
    height: 50,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 17,
    backgroundColor: colors.lime,
  },
  renewButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.35,
  },
  renewalReadyCard: {
    borderRadius: radius.lg,
    padding: 20,
    backgroundColor: colors.lime,
  },
  renewalReadyEyebrow: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.55,
  },
  renewalReadyTitle: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
    marginTop: 5,
  },
  renewalReadyBody: {
    color: colors.navy,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 7,
  },
  openRenewalButton: {
    height: 44,
    borderRadius: radius.sm,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 16,
    backgroundColor: colors.navy,
  },
  openRenewalButtonText: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
  },
  adminNotice: {
    borderRadius: radius.lg,
    padding: 18,
    marginTop: 20,
    backgroundColor: colors.canvasMuted,
  },
  adminNoticeTitle: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  adminNoticeBody: {
    color: colors.muted,
    fontSize: 10,
    lineHeight: 16,
    marginTop: 5,
  },
});
