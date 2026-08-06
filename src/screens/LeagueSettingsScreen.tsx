import { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useLeagueSettings } from '../hooks/useLeagueSettings';
import { colors, radius } from '../theme';
import type {
  AppScreen,
  LeagueSettings,
  LeagueSummary,
  StandingsTiebreaker,
} from '../types';

type Props = {
  league: LeagueSummary | null;
  onLeagueChanged: () => void;
  onNavigate: (screen: AppScreen) => void;
};

export function LeagueSettingsScreen({
  league,
  onLeagueChanged,
  onNavigate,
}: Props) {
  const rules = useLeagueSettings(league);
  const [marketOpen, setMarketOpen] = useState(true);
  const [marketMinimumPrice, setMarketMinimumPrice] = useState('1');
  const [releaseRefundPercent, setReleaseRefundPercent] = useState('50');
  const [maxSubstitutions, setMaxSubstitutions] = useState('5');
  const [defenseModifierEnabled, setDefenseModifierEnabled] = useState(false);
  const [
    defenseModifierMinDefenders,
    setDefenseModifierMinDefenders,
  ] = useState('4');
  const [goalThreshold, setGoalThreshold] = useState('66');
  const [goalStep, setGoalStep] = useState('6');
  const [goalBandsEnabled, setGoalBandsEnabled] = useState(false);
  const [goalBands, setGoalBands] = useState([
    '66',
    '72',
    '78',
    '84',
    '90',
    '96',
  ]);
  const [goalMarginEnabled, setGoalMarginEnabled] = useState(false);
  const [goalMargin, setGoalMargin] = useState('4');
  const [standingsTiebreaker, setStandingsTiebreaker] =
    useState<StandingsTiebreaker>('goal_difference');
  const [homeBonus, setHomeBonus] = useState('0');
  const [bonusGoal, setBonusGoal] = useState('3');
  const [bonusAssist, setBonusAssist] = useState('1');
  const [bonusPenaltySaved, setBonusPenaltySaved] = useState('3');
  const [malusYellowCard, setMalusYellowCard] = useState('0.5');
  const [malusRedCard, setMalusRedCard] = useState('1');
  const [malusPenaltyMissed, setMalusPenaltyMissed] = useState('3');
  const [malusGoalConceded, setMalusGoalConceded] = useState('1');
  const [rosterGoalkeepers, setRosterGoalkeepers] = useState('3');
  const [rosterDefenders, setRosterDefenders] = useState('8');
  const [rosterMidfielders, setRosterMidfielders] = useState('8');
  const [rosterAttackers, setRosterAttackers] = useState('6');
  const [changeReason, setChangeReason] = useState('');
  const [feedback, setFeedback] = useState('');
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    if (rules.loading) {
      return;
    }
    setMarketOpen(rules.settings.marketOpen);
    setMarketMinimumPrice(String(rules.settings.marketMinimumPrice));
    setReleaseRefundPercent(String(rules.settings.releaseRefundPercent));
    setMaxSubstitutions(String(rules.settings.maxSubstitutions));
    setDefenseModifierEnabled(rules.settings.defenseModifierEnabled);
    setDefenseModifierMinDefenders(
      String(rules.settings.defenseModifierMinDefenders),
    );
    setGoalThreshold(formatNumber(rules.settings.goalThreshold));
    setGoalStep(formatNumber(rules.settings.goalStep));
    setGoalBandsEnabled(rules.settings.goalBandsEnabled);
    setGoalBands(rules.settings.goalBands.map(formatNumber));
    setGoalMarginEnabled(rules.settings.goalMarginEnabled);
    setGoalMargin(formatNumber(rules.settings.goalMargin));
    setStandingsTiebreaker(rules.settings.standingsTiebreaker);
    setHomeBonus(formatNumber(rules.settings.homeBonus));
    setBonusGoal(formatNumber(rules.settings.bonusGoal));
    setBonusAssist(formatNumber(rules.settings.bonusAssist));
    setBonusPenaltySaved(formatNumber(rules.settings.bonusPenaltySaved));
    setMalusYellowCard(formatNumber(rules.settings.malusYellowCard));
    setMalusRedCard(formatNumber(rules.settings.malusRedCard));
    setMalusPenaltyMissed(formatNumber(rules.settings.malusPenaltyMissed));
    setMalusGoalConceded(formatNumber(rules.settings.malusGoalConceded));
    setRosterGoalkeepers(String(rules.settings.rosterGoalkeepers));
    setRosterDefenders(String(rules.settings.rosterDefenders));
    setRosterMidfielders(String(rules.settings.rosterMidfielders));
    setRosterAttackers(String(rules.settings.rosterAttackers));
  }, [rules.loading, rules.settings]);

  const preview = useMemo(() => {
    const threshold = parseNumber(goalThreshold) ?? 66;
    const step = parseNumber(goalStep) ?? 6;
    const custom = goalBands.map((value) => parseNumber(value));
    if (
      goalBandsEnabled &&
      custom.every((value): value is number => value !== null)
    ) {
      return custom.map((points, index) => ({
        points,
        goals: index + 1,
      }));
    }
    return Array.from({ length: 3 }, (_, index) => ({
      points: threshold + step * index,
      goals: index + 1,
    }));
  }, [goalBands, goalBandsEnabled, goalStep, goalThreshold]);

  const fantasyPreview = useMemo(() => {
    const rating = 6.5;
    const goal = parseNumber(bonusGoal) ?? 3;
    const assist = parseNumber(bonusAssist) ?? 1;
    return {
      rating,
      result: rating + goal + assist,
    };
  }, [bonusAssist, bonusGoal]);

  const rosterTotal = useMemo(
    () =>
      [rosterGoalkeepers, rosterDefenders, rosterMidfielders, rosterAttackers]
        .map((value) => Number(value.trim()))
        .filter(Number.isFinite)
        .reduce((total, value) => total + value, 0),
    [
      rosterAttackers,
      rosterDefenders,
      rosterGoalkeepers,
      rosterMidfielders,
    ],
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

  const isPresident = league.isDemo || league.currentRole === 'admin';
  if (!isPresident) {
    return (
      <View style={styles.centerRoot}>
        <View style={styles.lockBadge}>
          <Text style={styles.lockSymbol}>L</Text>
        </View>
        <Text style={styles.centerTitle}>Area riservata al Presidente</Text>
        <Text style={styles.centerBody}>
          Qui si cambiano le regole. Le proteste restano aperte a tutti.
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

  const submit = async () => {
    const normalizedReason = changeReason.trim();
    if (
      normalizedReason.length < 8 ||
      normalizedReason.length > 240
    ) {
      setFeedback('Inserisci una motivazione tra 8 e 240 caratteri.');
      setSaved(false);
      return;
    }

    const next = parseSettings({
      marketOpen,
      marketMinimumPrice,
      releaseRefundPercent,
      maxSubstitutions,
      defenseModifierEnabled:
        league.mode === 'classic' && defenseModifierEnabled,
      defenseModifierMinDefenders,
      goalThreshold,
      goalStep,
      goalBandsEnabled,
      goalBands,
      goalMarginEnabled,
      goalMargin,
      standingsTiebreaker,
      homeBonus,
      bonusGoal,
      bonusAssist,
      bonusPenaltySaved,
      malusYellowCard,
      malusRedCard,
      malusPenaltyMissed,
      malusGoalConceded,
      rosterSize: league.rosterSize,
      rosterGoalkeepers,
      rosterDefenders,
      rosterMidfielders,
      rosterAttackers,
    });
    if ('error' in next) {
      setFeedback(next.error);
      setSaved(false);
      return;
    }

    setFeedback('');
    setSaved(false);
    const outcome = await rules.save(next, normalizedReason);
    if (outcome.error) {
      setFeedback(outcome.error);
      return;
    }

    setSaved(true);
    setChangeReason('');
    setFeedback('Regole salvate. Adesso le polemiche hanno numeri precisi.');
    onLeagueChanged();
  };

  const changeGoalBand = (index: number, value: string) => {
    setGoalBands((current) =>
      current.map((item, itemIndex) =>
        itemIndex === index ? value : item,
      ),
    );
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
          <Pressable
            onPress={() => onNavigate('league')}
            style={styles.backButton}
          >
            <Text style={styles.backText}>‹</Text>
          </Pressable>
          <View style={styles.headerCopy}>
            <Text style={styles.eyebrow}>PANNELLO DEL PRESIDENTE</Text>
            <Text style={styles.title}>Regole della lega</Text>
          </View>
        </View>

        <View style={styles.heroCard}>
          <View style={styles.heroBadge}>
            <Text style={styles.heroBadgeText}>P</Text>
          </View>
          <View style={styles.heroCopy}>
            <Text style={styles.heroEyebrow}>{league.name.toUpperCase()}</Text>
            <Text style={styles.heroTitle}>Qui il VAR sei tu.</Text>
            <Text style={styles.heroBody}>
              Ogni modifica vale subito per mercato e prossimi risultati.
            </Text>
          </View>
        </View>

        {rules.loading ? (
          <View style={styles.loadingCard}>
            <ActivityIndicator color={colors.navy} />
            <Text style={styles.loadingText}>Apro il regolamento…</Text>
          </View>
        ) : rules.error ? (
          <View style={styles.errorCard}>
            <Text style={styles.errorTitle}>Regole indisponibili</Text>
            <Text style={styles.errorBody}>{rules.error}</Text>
            <Pressable
              onPress={() => void rules.refresh()}
              style={styles.retryButton}
            >
              <Text style={styles.retryText}>RIPROVA</Text>
            </Pressable>
          </View>
        ) : (
          <>
            <Text style={styles.sectionTitle}>Mercato</Text>
            <View style={styles.card}>
              <View style={styles.switchRow}>
                <View style={styles.switchCopy}>
                  <Text style={styles.fieldTitle}>Mercato svincolati</Text>
                  <Text style={styles.fieldHint}>
                    Acquisti, svincoli e scambi in un solo interruttore.
                  </Text>
                </View>
                <Switch
                  ios_backgroundColor={colors.canvasMuted}
                  onValueChange={setMarketOpen}
                  thumbColor={marketOpen ? colors.navy : colors.white}
                  trackColor={{
                    false: colors.canvasMuted,
                    true: colors.lime,
                  }}
                  value={marketOpen}
                />
              </View>

              <View style={styles.divider} />
              <View style={styles.doubleField}>
                <NumberField
                  label="PREZZO MINIMO"
                  onChange={setMarketMinimumPrice}
                  suffix="CR"
                  value={marketMinimumPrice}
                />
                <NumberField
                  label="RIMBORSO SVINCOLO"
                  onChange={setReleaseRefundPercent}
                  suffix="%"
                  value={releaseRefundPercent}
                />
              </View>
              <Text style={styles.cardFootnote}>
                Il rimborso è calcolato sul prezzo pagato all’asta o sul mercato.
              </Text>
            </View>

            <Text style={styles.sectionTitle}>Composizione rosa</Text>
            <View style={styles.card}>
              <Text style={styles.fieldTitle}>Quote massime per reparto</Text>
              <Text style={styles.fieldHint}>
                {league.mode === 'classic'
                  ? 'Configura quanti P, D, C e A deve contenere ogni rosa.'
                  : 'I ruoli Mantra vengono raggruppati in Por, difesa, centrocampo e attacco.'}
              </Text>

              <View style={styles.doubleField}>
                <NumberField
                  label={league.mode === 'classic' ? 'PORTIERI · P' : 'PORTIERI · POR'}
                  onChange={setRosterGoalkeepers}
                  suffix="MAX"
                  value={rosterGoalkeepers}
                />
                <NumberField
                  label={
                    league.mode === 'classic'
                      ? 'DIFENSORI · D'
                      : 'DIFESA · DC/DD/DS/E'
                  }
                  onChange={setRosterDefenders}
                  suffix="MAX"
                  value={rosterDefenders}
                />
              </View>
              <View style={styles.doubleField}>
                <NumberField
                  label={
                    league.mode === 'classic'
                      ? 'CENTROCAMPISTI · C'
                      : 'CENTROCAMPO · M/C/W/T'
                  }
                  onChange={setRosterMidfielders}
                  suffix="MAX"
                  value={rosterMidfielders}
                />
                <NumberField
                  label={
                    league.mode === 'classic'
                      ? 'ATTACCANTI · A'
                      : 'ATTACCO · A/PC'
                  }
                  onChange={setRosterAttackers}
                  suffix="MAX"
                  value={rosterAttackers}
                />
              </View>

              <View style={styles.preview}>
                <Text style={styles.previewLabel}>CONTROLLO COMPOSIZIONE</Text>
                <View style={styles.scorePreviewRow}>
                  <Text style={styles.scorePreviewFormula}>TOTALE ROSA</Text>
                  <Text
                    style={[
                      styles.scorePreviewValue,
                      rosterTotal !== league.rosterSize &&
                        styles.quotaTotalInvalid,
                    ]}
                  >
                    {rosterTotal}/{league.rosterSize}
                  </Text>
                </View>
              </View>
            </View>

            <Text style={styles.sectionTitle}>Formazione e cambi</Text>
            <View style={styles.card}>
              <Text style={styles.fieldTitle}>Sostituzioni automatiche</Text>
              <Text style={styles.fieldHint}>
                LEGHEVO segue l’ordine della panchina e cerca la prima riserva
                compatibile con il ruolo del titolare senza voto.
              </Text>
              <NumberField
                label="NUMERO MASSIMO DI CAMBI"
                onChange={setMaxSubstitutions}
                suffix="MAX"
                value={maxSubstitutions}
              />
              <Text style={styles.cardFootnote}>
                Il valore può essere compreso tra 0 e 11. I cambi vengono
                applicati soltanto quando la giornata reale è conclusa.
              </Text>
            </View>

            <Text style={styles.sectionTitle}>Modificatore difesa</Text>
            <View style={styles.card}>
              <View style={styles.switchRow}>
                <View style={styles.switchCopy}>
                  <Text style={styles.fieldTitle}>Modificatore difesa</Text>
                  <Text style={styles.fieldHint}>
                    {league.mode === 'classic'
                      ? 'Media del portiere e dei tre migliori difensori effettivamente a voto.'
                      : 'Il modificatore tradizionale è disponibile soltanto nelle leghe Classic.'}
                  </Text>
                </View>
                <Switch
                  disabled={league.mode !== 'classic'}
                  ios_backgroundColor={colors.canvasMuted}
                  onValueChange={setDefenseModifierEnabled}
                  thumbColor={
                    defenseModifierEnabled ? colors.navy : colors.white
                  }
                  trackColor={{
                    false: colors.canvasMuted,
                    true: colors.lime,
                  }}
                  value={
                    league.mode === 'classic' && defenseModifierEnabled
                  }
                />
              </View>

              {league.mode === 'classic' ? (
                <>
                  <NumberField
                    label="DIFENSORI MINIMI SCHIERATI"
                    onChange={setDefenseModifierMinDefenders}
                    suffix="MIN"
                    value={defenseModifierMinDefenders}
                  />
                  <Text style={styles.cardFootnote}>
                    Puoi scegliere 4 o 5. Fasce standard: media 6 = +1,
                    6,25 = +2, 6,5 = +3, 6,75 = +4, da 7 = +6.
                  </Text>
                  <View style={styles.preview}>
                    <Text style={styles.previewLabel}>
                      ORDINE DI CALCOLO
                    </Text>
                    <View style={styles.scorePreviewRow}>
                      <Text style={styles.scorePreviewFormula}>
                        VOTI BASE + MODIFICATORE + CASA
                      </Text>
                      <Text style={styles.scorePreviewValue}>FP</Text>
                    </View>
                  </View>
                </>
              ) : null}
            </View>

            <Text style={styles.sectionTitle}>Gol e fantapunti</Text>
            <View style={styles.card}>
              <View style={styles.switchRow}>
                <View style={styles.switchCopy}>
                  <Text style={styles.fieldTitle}>
                    Fasce gol personalizzate
                  </Text>
                  <Text style={styles.fieldHint}>
                    Scegli la soglia esatta di ogni gol, dal primo al sesto.
                  </Text>
                </View>
                <Switch
                  ios_backgroundColor={colors.canvasMuted}
                  onValueChange={setGoalBandsEnabled}
                  thumbColor={goalBandsEnabled ? colors.navy : colors.white}
                  trackColor={{
                    false: colors.canvasMuted,
                    true: colors.lime,
                  }}
                  value={goalBandsEnabled}
                />
              </View>

              {goalBandsEnabled ? (
                <>
                  {[0, 2, 4].map((startIndex) => (
                    <View key={startIndex} style={styles.doubleField}>
                      {[startIndex, startIndex + 1].map((index) => (
                        <NumberField
                          decimal
                          key={index}
                          label={`SOGLIA GOL ${index + 1}`}
                          onChange={(value) => changeGoalBand(index, value)}
                          suffix="PT"
                          value={goalBands[index]}
                        />
                      ))}
                    </View>
                  ))}
                  <Text style={styles.cardFootnote}>
                    Dopo il sesto gol, LEGHEVO continua usando la distanza
                    impostata tra la quinta e la sesta soglia.
                  </Text>
                </>
              ) : (
                <View style={styles.doubleField}>
                  <NumberField
                    decimal
                    label="SOGLIA DEL PRIMO GOL"
                    onChange={setGoalThreshold}
                    suffix="PT"
                    value={goalThreshold}
                  />
                  <NumberField
                    decimal
                    label="FASCIA SUCCESSIVA"
                    onChange={setGoalStep}
                    suffix="PT"
                    value={goalStep}
                  />
                </View>
              )}

              <NumberField
                decimal
                label="BONUS CASA"
                onChange={setHomeBonus}
                suffix="PT"
                value={homeBonus}
              />

              <View style={styles.preview}>
                <Text style={styles.previewLabel}>ANTEPRIMA FASCE GOL</Text>
                <View style={styles.previewRow}>
                  {preview.map((item) => (
                    <View key={`${item.points}-${item.goals}`} style={styles.previewItem}>
                      <Text style={styles.previewValue}>
                        {formatNumber(item.points)}
                      </Text>
                      <Text style={styles.previewMeta}>
                        {item.goals} GOL
                      </Text>
                    </View>
                  ))}
                </View>
              </View>

              <View style={styles.divider} />
              <View style={styles.switchRow}>
                <View style={styles.switchCopy}>
                  <Text style={styles.fieldTitle}>
                    Scarto minimo nei pareggi
                  </Text>
                  <Text style={styles.fieldHint}>
                    Se le squadre sono nella stessa fascia, assegna un gol
                    aggiuntivo a chi supera lo scarto impostato.
                  </Text>
                </View>
                <Switch
                  ios_backgroundColor={colors.canvasMuted}
                  onValueChange={setGoalMarginEnabled}
                  thumbColor={goalMarginEnabled ? colors.navy : colors.white}
                  trackColor={{
                    false: colors.canvasMuted,
                    true: colors.lime,
                  }}
                  value={goalMarginEnabled}
                />
              </View>
              {goalMarginEnabled ? (
                <>
                  <NumberField
                    decimal
                    label="SCARTO MINIMO"
                    onChange={setGoalMargin}
                    suffix="PT"
                    value={goalMargin}
                  />
                  <Text style={styles.cardFootnote}>
                    La regola vale anche sotto la soglia del primo gol ed è
                    applicata soltanto quando il risultato base è in parità.
                  </Text>
                </>
              ) : null}
            </View>

            <Text style={styles.sectionTitle}>Criteri classifica</Text>
            <View style={styles.card}>
              <Text style={styles.fieldTitle}>Ordine a pari punti</Text>
              <Text style={styles.fieldHint}>
                Scegli il primo criterio usato quando due o più squadre hanno
                gli stessi punti in campionato.
              </Text>

              <View style={styles.tiebreakerList}>
                <TiebreakerOption
                  active={standingsTiebreaker === 'goal_difference'}
                  description="Poi gol fatti e fantapunti totali."
                  label="Differenza reti"
                  onPress={() => setStandingsTiebreaker('goal_difference')}
                />
                <TiebreakerOption
                  active={standingsTiebreaker === 'fantasy_points'}
                  description="Poi differenza reti e gol fatti."
                  label="Fantapunti totali"
                  onPress={() => setStandingsTiebreaker('fantasy_points')}
                />
                <TiebreakerOption
                  active={standingsTiebreaker === 'head_to_head'}
                  description="Mini-classifica tra le squadre a pari punti."
                  label="Scontri diretti"
                  onPress={() => setStandingsTiebreaker('head_to_head')}
                />
              </View>

              {standingsTiebreaker === 'head_to_head' ? (
                <Text style={styles.cardFootnote}>
                  Gli scontri diretti vengono applicati solo quando le squadre
                  a pari punti hanno giocato lo stesso numero di confronti
                  reciproci. In caso contrario valgono differenza reti, gol
                  fatti e fantapunti.
                </Text>
              ) : null}
            </View>

            <Text style={styles.sectionTitle}>Bonus e malus</Text>
            <View style={styles.card}>
              <Text style={styles.fieldTitle}>Eventi automatici</Text>
              <Text style={styles.fieldHint}>
                Il rating resta quello del provider; LEGHEVO applica questi
                valori a ogni lega.
              </Text>

              <View style={styles.doubleField}>
                <NumberField
                  decimal
                  label="GOL"
                  onChange={setBonusGoal}
                  suffix="+PT"
                  value={bonusGoal}
                />
                <NumberField
                  decimal
                  label="ASSIST"
                  onChange={setBonusAssist}
                  suffix="+PT"
                  value={bonusAssist}
                />
              </View>
              <View style={styles.doubleField}>
                <NumberField
                  decimal
                  label="RIGORE PARATO"
                  onChange={setBonusPenaltySaved}
                  suffix="+PT"
                  value={bonusPenaltySaved}
                />
                <NumberField
                  decimal
                  label="AMMONIZIONE"
                  onChange={setMalusYellowCard}
                  suffix="−PT"
                  value={malusYellowCard}
                />
              </View>
              <View style={styles.doubleField}>
                <NumberField
                  decimal
                  label="ESPULSIONE"
                  onChange={setMalusRedCard}
                  suffix="−PT"
                  value={malusRedCard}
                />
                <NumberField
                  decimal
                  label="RIGORE SBAGLIATO"
                  onChange={setMalusPenaltyMissed}
                  suffix="−PT"
                  value={malusPenaltyMissed}
                />
              </View>
              <NumberField
                decimal
                label="GOL SUBITO DAL PORTIERE"
                onChange={setMalusGoalConceded}
                suffix="−PT"
                value={malusGoalConceded}
              />

              <View style={styles.preview}>
                <Text style={styles.previewLabel}>ESEMPIO FANTAVOTO</Text>
                <View style={styles.scorePreviewRow}>
                  <Text style={styles.scorePreviewFormula}>
                    {formatNumber(fantasyPreview.rating)} + GOL + ASSIST
                  </Text>
                  <Text style={styles.scorePreviewValue}>
                    {formatNumber(fantasyPreview.result)}
                  </Text>
                </View>
              </View>
            </View>

            <Text style={styles.sectionTitle}>Motivazione</Text>
            <View style={styles.card}>
              <Text style={styles.fieldTitle}>
                Perché stai cambiando il regolamento?
              </Text>
              <Text style={styles.fieldHint}>
                Sarà visibile a tutti i membri nella cronologia.
              </Text>
              <TextInput
                editable={!rules.saving}
                maxLength={240}
                multiline
                onChangeText={setChangeReason}
                placeholder="Es. decisione approvata dalla lega prima della prossima giornata"
                placeholderTextColor={colors.muted}
                style={styles.reasonInput}
                textAlignVertical="top"
                value={changeReason}
              />
              <Text style={styles.reasonCounter}>
                {changeReason.trim().length}/240
              </Text>
            </View>

            {feedback ? (
              <Text style={[styles.feedback, saved && styles.feedbackSuccess]}>
                {feedback}
              </Text>
            ) : null}

            <Pressable
              disabled={rules.saving}
              onPress={() => void submit()}
              style={[
                styles.saveButton,
                rules.saving && styles.buttonDisabled,
              ]}
            >
              <Text style={styles.saveButtonText}>
                {rules.saving ? 'SALVATAGGIO…' : 'SALVA REGOLAMENTO'}
              </Text>
            </Pressable>
          </>
        )}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

function NumberField({
  decimal = false,
  label,
  onChange,
  suffix,
  value,
}: {
  decimal?: boolean;
  label: string;
  onChange: (value: string) => void;
  suffix: string;
  value: string;
}) {
  return (
    <View style={styles.numberField}>
      <Text style={styles.fieldLabel}>{label}</Text>
      <View style={styles.inputShell}>
        <TextInput
          keyboardType={decimal ? 'decimal-pad' : 'number-pad'}
          maxLength={6}
          onChangeText={onChange}
          selectTextOnFocus
          style={styles.input}
          value={value}
        />
        <Text style={styles.inputSuffix}>{suffix}</Text>
      </View>
    </View>
  );
}

function TiebreakerOption({
  active,
  description,
  label,
  onPress,
}: {
  active: boolean;
  description: string;
  label: string;
  onPress: () => void;
}) {
  return (
    <Pressable
      accessibilityRole="radio"
      accessibilityState={{ checked: active }}
      onPress={onPress}
      style={[
        styles.tiebreakerOption,
        active && styles.tiebreakerOptionActive,
      ]}
    >
      <View
        style={[
          styles.tiebreakerRadio,
          active && styles.tiebreakerRadioActive,
        ]}
      >
        {active ? <View style={styles.tiebreakerRadioDot} /> : null}
      </View>
      <View style={styles.tiebreakerCopy}>
        <Text style={styles.tiebreakerLabel}>{label}</Text>
        <Text style={styles.tiebreakerDescription}>{description}</Text>
      </View>
    </Pressable>
  );
}

function parseSettings(input: {
  marketOpen: boolean;
  marketMinimumPrice: string;
  releaseRefundPercent: string;
  maxSubstitutions: string;
  defenseModifierEnabled: boolean;
  defenseModifierMinDefenders: string;
  goalThreshold: string;
  goalStep: string;
  goalBandsEnabled: boolean;
  goalBands: string[];
  goalMarginEnabled: boolean;
  goalMargin: string;
  standingsTiebreaker: StandingsTiebreaker;
  homeBonus: string;
  bonusGoal: string;
  bonusAssist: string;
  bonusPenaltySaved: string;
  malusYellowCard: string;
  malusRedCard: string;
  malusPenaltyMissed: string;
  malusGoalConceded: string;
  rosterSize: number;
  rosterGoalkeepers: string;
  rosterDefenders: string;
  rosterMidfielders: string;
  rosterAttackers: string;
}): LeagueSettings | { error: string } {
  const minimumPrice = Number(input.marketMinimumPrice.trim());
  const refund = Number(input.releaseRefundPercent.trim());
  const substitutions = Number(input.maxSubstitutions.trim());
  const modifierDefenders = Number(
    input.defenseModifierMinDefenders.trim(),
  );
  const threshold = parseNumber(input.goalThreshold);
  const step = parseNumber(input.goalStep);
  const parsedGoalBands = input.goalBands.map(parseNumber);
  const margin = parseNumber(input.goalMargin);
  const home = parseNumber(input.homeBonus);
  const goalBonus = parseNumber(input.bonusGoal);
  const assistBonus = parseNumber(input.bonusAssist);
  const penaltySavedBonus = parseNumber(input.bonusPenaltySaved);
  const yellowMalus = parseNumber(input.malusYellowCard);
  const redMalus = parseNumber(input.malusRedCard);
  const penaltyMissedMalus = parseNumber(input.malusPenaltyMissed);
  const goalConcededMalus = parseNumber(input.malusGoalConceded);
  const goalkeepers = Number(input.rosterGoalkeepers.trim());
  const defenders = Number(input.rosterDefenders.trim());
  const midfielders = Number(input.rosterMidfielders.trim());
  const attackers = Number(input.rosterAttackers.trim());

  if (!Number.isInteger(minimumPrice) || minimumPrice < 1 || minimumPrice > 1000) {
    return { error: 'Il prezzo minimo deve essere tra 1 e 1000 crediti.' };
  }
  if (!Number.isInteger(refund) || refund < 0 || refund > 100) {
    return { error: 'Il rimborso deve essere una percentuale tra 0 e 100.' };
  }
  if (
    !Number.isInteger(substitutions) ||
    substitutions < 0 ||
    substitutions > 11
  ) {
    return { error: 'Il limite dei cambi deve essere compreso tra 0 e 11.' };
  }
  if (
    !Number.isInteger(modifierDefenders) ||
    ![4, 5].includes(modifierDefenders)
  ) {
    return {
      error:
        'Il modificatore difesa deve richiedere almeno 4 oppure 5 difensori.',
    };
  }
  if (threshold === null || threshold < 50 || threshold > 100) {
    return { error: 'La soglia del primo gol deve essere tra 50 e 100.' };
  }
  if (step === null || step < 1 || step > 20) {
    return { error: 'La fascia successiva deve essere tra 1 e 20 punti.' };
  }
  const customBandsValid =
    parsedGoalBands.length === 6 &&
    parsedGoalBands.every(
      (value, index): value is number =>
        value !== null &&
        value >= 50 &&
        value <= 150 &&
        (index === 0 || value > Number(parsedGoalBands[index - 1])),
    ) &&
    Number(parsedGoalBands[0]) <= 100;
  if (input.goalBandsEnabled && !customBandsValid) {
    return {
      error:
        'Le sei fasce gol devono essere crescenti. La prima va da 50 a 100 punti.',
    };
  }
  if (margin === null || margin < 1 || margin > 20) {
    return { error: 'Lo scarto minimo deve essere tra 1 e 20 punti.' };
  }
  if (home === null || home < 0 || home > 10) {
    return { error: 'Il bonus casa deve essere tra 0 e 10 punti.' };
  }
  if (
    !Number.isInteger(goalkeepers) ||
    goalkeepers < 1 ||
    !Number.isInteger(defenders) ||
    defenders < 3 ||
    !Number.isInteger(midfielders) ||
    midfielders < 3 ||
    !Number.isInteger(attackers) ||
    attackers < 1
  ) {
    return {
      error:
        'Servono almeno 1 portiere, 3 difensori, 3 centrocampisti e 1 attaccante.',
    };
  }
  if (goalkeepers + defenders + midfielders + attackers !== input.rosterSize) {
    return {
      error: `Le quote dei reparti devono totalizzare ${input.rosterSize} calciatori.`,
    };
  }
  if (
    goalBonus === null ||
    goalBonus < 0 ||
    goalBonus > 10 ||
    assistBonus === null ||
    assistBonus < 0 ||
    assistBonus > 5 ||
    penaltySavedBonus === null ||
    penaltySavedBonus < 0 ||
    penaltySavedBonus > 10
  ) {
    return { error: 'Controlla i valori dei bonus inseriti.' };
  }
  if (
    yellowMalus === null ||
    yellowMalus < 0 ||
    yellowMalus > 5 ||
    redMalus === null ||
    redMalus < 0 ||
    redMalus > 10 ||
    penaltyMissedMalus === null ||
    penaltyMissedMalus < 0 ||
    penaltyMissedMalus > 10 ||
    goalConcededMalus === null ||
    goalConcededMalus < 0 ||
    goalConcededMalus > 5
  ) {
    return { error: 'Controlla i valori dei malus inseriti.' };
  }

  return {
    marketOpen: input.marketOpen,
    marketMinimumPrice: minimumPrice,
    releaseRefundPercent: refund,
    maxSubstitutions: substitutions,
    defenseModifierEnabled: input.defenseModifierEnabled,
    defenseModifierMinDefenders: modifierDefenders,
    goalThreshold: threshold,
    goalStep: step,
    goalBandsEnabled: input.goalBandsEnabled,
    goalBands: (
      input.goalBandsEnabled && customBandsValid
        ? parsedGoalBands
        : Array.from(
            { length: 6 },
            (_, index) => threshold + step * index,
          )
    ) as LeagueSettings['goalBands'],
    goalMarginEnabled: input.goalMarginEnabled,
    goalMargin: margin,
    standingsTiebreaker: input.standingsTiebreaker,
    homeBonus: home,
    bonusGoal: goalBonus,
    bonusAssist: assistBonus,
    bonusPenaltySaved: penaltySavedBonus,
    malusYellowCard: yellowMalus,
    malusRedCard: redMalus,
    malusPenaltyMissed: penaltyMissedMalus,
    malusGoalConceded: goalConcededMalus,
    rosterGoalkeepers: goalkeepers,
    rosterDefenders: defenders,
    rosterMidfielders: midfielders,
    rosterAttackers: attackers,
  };
}

function parseNumber(value: string) {
  const normalized = value.trim().replace(',', '.');
  if (!normalized) {
    return null;
  }
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function formatNumber(value: number) {
  return Number.isInteger(value)
    ? String(value)
    : value.toFixed(1).replace(/\.0$/, '');
}

const styles = StyleSheet.create({
  root: {
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
    padding: 28,
    backgroundColor: colors.canvas,
  },
  centerTitle: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
    textAlign: 'center',
  },
  centerBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    textAlign: 'center',
    marginTop: 8,
  },
  lockBadge: {
    width: 58,
    height: 58,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
    marginBottom: 18,
  },
  lockSymbol: {
    color: colors.lime,
    fontSize: 24,
    fontWeight: '900',
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
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  title: {
    color: colors.navy,
    fontSize: 25,
    fontWeight: '900',
    marginTop: 4,
  },
  heroCard: {
    minHeight: 136,
    borderRadius: radius.xl,
    padding: 21,
    flexDirection: 'row',
    backgroundColor: colors.navy,
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
    fontSize: 19,
    fontWeight: '900',
  },
  heroCopy: {
    flex: 1,
    marginLeft: 15,
  },
  heroEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  heroTitle: {
    color: colors.white,
    fontSize: 20,
    fontWeight: '900',
    marginTop: 5,
  },
  heroBody: {
    color: colors.mutedLight,
    fontSize: 11,
    lineHeight: 16,
    marginTop: 7,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
    marginTop: 24,
    marginBottom: 11,
  },
  card: {
    borderRadius: radius.lg,
    padding: 19,
    backgroundColor: colors.white,
  },
  switchRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  switchCopy: {
    flex: 1,
    paddingRight: 14,
  },
  fieldTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  fieldHint: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 16,
    marginTop: 5,
  },
  divider: {
    height: 1,
    backgroundColor: colors.canvasMuted,
    marginVertical: 18,
  },
  doubleField: {
    flexDirection: 'row',
    gap: 12,
  },
  numberField: {
    flex: 1,
    marginTop: 13,
  },
  fieldLabel: {
    minHeight: 24,
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.35,
    marginBottom: 7,
  },
  inputShell: {
    height: 52,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: radius.sm,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.canvas,
  },
  input: {
    flex: 1,
    height: 52,
    paddingLeft: 14,
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  inputSuffix: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    marginRight: 13,
  },
  cardFootnote: {
    color: colors.muted,
    fontSize: 10,
    lineHeight: 15,
    marginTop: 15,
  },
  reasonInput: {
    minHeight: 110,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: radius.sm,
    backgroundColor: colors.canvas,
    color: colors.navy,
    fontSize: 13,
    lineHeight: 19,
    padding: 14,
    marginTop: 14,
  },
  reasonCounter: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '800',
    textAlign: 'right',
    marginTop: 7,
  },
  tiebreakerList: {
    gap: 9,
    marginTop: 16,
  },
  tiebreakerOption: {
    minHeight: 68,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: radius.md,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 11,
    backgroundColor: colors.canvas,
  },
  tiebreakerOptionActive: {
    borderColor: colors.navy,
    backgroundColor: '#F4FFD9',
  },
  tiebreakerRadio: {
    width: 22,
    height: 22,
    borderWidth: 2,
    borderColor: colors.muted,
    borderRadius: 11,
    alignItems: 'center',
    justifyContent: 'center',
  },
  tiebreakerRadioActive: {
    borderColor: colors.navy,
  },
  tiebreakerRadioDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: colors.navy,
  },
  tiebreakerCopy: {
    flex: 1,
    marginLeft: 12,
  },
  tiebreakerLabel: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  tiebreakerDescription: {
    color: colors.muted,
    fontSize: 9,
    lineHeight: 14,
    marginTop: 3,
  },
  preview: {
    borderRadius: radius.md,
    padding: 14,
    backgroundColor: colors.navy,
    marginTop: 18,
  },
  previewLabel: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  previewRow: {
    flexDirection: 'row',
    marginTop: 12,
  },
  previewItem: {
    flex: 1,
  },
  previewValue: {
    color: colors.lime,
    fontSize: 17,
    fontWeight: '900',
  },
  previewMeta: {
    color: colors.white,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 3,
  },
  scorePreviewRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 11,
  },
  scorePreviewFormula: {
    flex: 1,
    color: colors.white,
    fontSize: 10,
    fontWeight: '900',
    paddingRight: 12,
  },
  scorePreviewValue: {
    color: colors.lime,
    fontSize: 22,
    fontWeight: '900',
  },
  quotaTotalInvalid: {
    color: colors.danger,
  },
  feedback: {
    color: colors.danger,
    fontSize: 12,
    fontWeight: '800',
    lineHeight: 18,
    marginTop: 18,
  },
  feedbackSuccess: {
    color: colors.navy,
  },
  saveButton: {
    height: 58,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 18,
  },
  primaryButton: {
    height: 50,
    borderRadius: 25,
    paddingHorizontal: 22,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 20,
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  saveButtonText: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  buttonDisabled: {
    opacity: 0.55,
  },
  loadingCard: {
    minHeight: 100,
    borderRadius: radius.lg,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
    backgroundColor: colors.white,
    marginTop: 18,
  },
  loadingText: {
    color: colors.muted,
    fontSize: 11,
    fontWeight: '800',
  },
  errorCard: {
    borderRadius: radius.lg,
    padding: 20,
    backgroundColor: colors.white,
    marginTop: 18,
  },
  errorTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  errorBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 7,
  },
  retryButton: {
    alignSelf: 'flex-start',
    borderRadius: 16,
    paddingHorizontal: 13,
    paddingVertical: 9,
    backgroundColor: colors.navy,
    marginTop: 13,
  },
  retryText: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
  },
  membersHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 12,
  },
  membersCount: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  inlineLoading: {
    minHeight: 64,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 9,
  },
  memberError: {
    color: colors.danger,
    fontSize: 11,
    lineHeight: 17,
    paddingVertical: 12,
  },
  memberList: {
    borderTopWidth: 1,
    borderTopColor: colors.canvasMuted,
  },
  memberRow: {
    minHeight: 70,
    borderBottomWidth: 1,
    borderBottomColor: colors.canvasMuted,
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
    fontSize: 10,
    fontWeight: '900',
  },
  memberCopy: {
    flex: 1,
    marginLeft: 11,
    marginRight: 8,
  },
  memberName: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  memberTeam: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '800',
    marginTop: 4,
  },
  memberActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  roleButton: {
    height: 30,
    minWidth: 55,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 9,
    backgroundColor: colors.lime,
  },
  roleButtonText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  removeButton: {
    width: 30,
    height: 30,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  removeButtonText: {
    color: colors.danger,
    fontSize: 17,
    fontWeight: '900',
    lineHeight: 19,
  },
  protectedBadge: {
    minWidth: 30,
    height: 30,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 8,
    backgroundColor: colors.navy,
  },
  protectedBadgeText: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
  },
  inviteCard: {
    minHeight: 82,
    borderRadius: radius.lg,
    paddingHorizontal: 18,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.white,
  },
  inviteLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  inviteCode: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
    letterSpacing: 1.2,
    marginTop: 5,
  },
  rotateButton: {
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 13,
    backgroundColor: colors.navy,
  },
  rotateButtonText: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
  },
});
