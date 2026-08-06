import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useLeagueRulebook } from '../hooks/useLeagueRulebook';
import { colors, radius } from '../theme';
import type {
  AppScreen,
  LeagueRuleRevision,
  LeagueSettings,
  LeagueSummary,
} from '../types';

type Props = {
  league: LeagueSummary | null;
  onNavigate: (screen: AppScreen) => void;
};

export function LeagueRulebookScreen({ league, onNavigate }: Props) {
  const state = useLeagueRulebook(league);

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

  const rulebook = state.rulebook;

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
          <Text style={styles.eyebrow}>DOCUMENTO DELLA LEGA</Text>
          <Text style={styles.title}>Regolamento</Text>
        </View>
      </View>

      <View style={styles.heroCard}>
        <View style={styles.heroMark}>
          <Text style={styles.heroMarkText}>R</Text>
        </View>
        <View style={styles.heroCopy}>
          <Text style={styles.heroEyebrow}>{league.name.toUpperCase()}</Text>
          <Text style={styles.heroTitle}>Le regole sono uguali per tutti.</Text>
          <Text style={styles.heroBody}>
            E ogni modifica lascia finalmente il segno.
          </Text>
        </View>
      </View>

      {state.loading && !rulebook ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.navy} />
          <Text style={styles.loadingText}>Apro il regolamento…</Text>
        </View>
      ) : state.error && !rulebook ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>Regolamento indisponibile</Text>
          <Text style={styles.errorBody}>{state.error}</Text>
          <Pressable
            onPress={() => void state.refresh()}
            style={styles.retryButton}
          >
            <Text style={styles.retryText}>RIPROVA</Text>
          </Pressable>
        </View>
      ) : rulebook ? (
        <>
          <View style={styles.summaryCard}>
            <SummaryItem
              label="MODALITÀ"
              value={rulebook.mode === 'classic' ? 'Classic' : 'Mantra'}
            />
            <SummaryItem
              label="STAGIONE"
              value={rulebook.season ?? 'Da definire'}
            />
            <SummaryItem
              label="SQUADRE"
              value={String(rulebook.teamLimit)}
            />
            <SummaryItem
              label="CREDITI"
              value={String(rulebook.startingCredits)}
            />
          </View>

          <View style={styles.versionRow}>
            <View>
              <Text style={styles.versionLabel}>VERSIONE REGOLAMENTO</Text>
              <Text style={styles.versionValue}>
                {rulebook.currentRevision > 0
                  ? `REVISIONE ${rulebook.currentRevision}`
                  : 'VERSIONE INIZIALE'}
              </Text>
            </View>
            <Text style={styles.versionDate}>
              {formatDate(rulebook.updatedAt)}
            </Text>
          </View>

          {rulebook.isDirector ? (
            <Pressable
              onPress={() => onNavigate('leagueSettings')}
              style={styles.editButton}
            >
              <View>
                <Text style={styles.editEyebrow}>AREA PRESIDENTE</Text>
                <Text style={styles.editTitle}>Modifica il regolamento</Text>
              </View>
              <Text style={styles.editArrow}>→</Text>
            </Pressable>
          ) : null}

          <RuleSections
            mode={rulebook.mode}
            rosterSize={rulebook.rosterSize}
            settings={rulebook.settings}
          />

          <View style={styles.historyHeader}>
            <View>
              <Text style={styles.sectionEyebrow}>TRASPARENZA</Text>
              <Text style={styles.sectionTitle}>Cronologia modifiche</Text>
            </View>
            {state.loading ? (
              <ActivityIndicator color={colors.navy} size="small" />
            ) : null}
          </View>

          {rulebook.revisions.length === 0 ? (
            <View style={styles.emptyHistory}>
              <Text style={styles.emptyHistoryTitle}>
                Nessuna modifica registrata
              </Text>
              <Text style={styles.emptyHistoryBody}>
                Il regolamento attuale resta la versione iniziale. Le prossime
                variazioni mostreranno autore, data e motivazione.
              </Text>
            </View>
          ) : (
            rulebook.revisions.map((revision) => (
              <RevisionCard key={revision.id} revision={revision} />
            ))
          )}

          <Text style={styles.footnote}>
            La cronologia decorre dall’attivazione del regolamento versionato.
            Le impostazioni precedenti non vengono ricostruite artificialmente.
          </Text>
        </>
      ) : null}
    </ScrollView>
  );
}

function RuleSections({
  mode,
  rosterSize,
  settings,
}: {
  mode: LeagueSummary['mode'];
  rosterSize: number;
  settings: LeagueSettings;
}) {
  return (
    <>
      <RuleCard
        eyebrow="MERCATO"
        rows={[
          ['Stato', settings.marketOpen ? 'Aperto' : 'Chiuso'],
          ['Prezzo minimo', `${formatNumber(settings.marketMinimumPrice)} cr`],
          [
            'Rimborso svincolo',
            `${formatNumber(settings.releaseRefundPercent)}%`,
          ],
        ]}
        title="Acquisti e svincoli"
      />

      <RuleCard
        eyebrow="ROSA E FORMAZIONE"
        rows={[
          ['Dimensione rosa', `${rosterSize} calciatori`],
          ['Portieri', String(settings.rosterGoalkeepers)],
          ['Difensori', String(settings.rosterDefenders)],
          ['Centrocampisti', String(settings.rosterMidfielders)],
          ['Attaccanti', String(settings.rosterAttackers)],
          ['Sostituzioni massime', String(settings.maxSubstitutions)],
        ]}
        title="Composizione della squadra"
      />

      <RuleCard
        eyebrow="BONUS"
        rows={[
          ['Gol', signed(settings.bonusGoal)],
          ['Assist', signed(settings.bonusAssist)],
          ['Rigore parato', signed(settings.bonusPenaltySaved)],
          ['Fattore casa', signed(settings.homeBonus)],
        ]}
        title="Punti aggiuntivi"
      />

      <RuleCard
        eyebrow="MALUS"
        rows={[
          ['Ammonizione', negative(settings.malusYellowCard)],
          ['Espulsione', negative(settings.malusRedCard)],
          ['Rigore sbagliato', negative(settings.malusPenaltyMissed)],
          ['Gol subito', negative(settings.malusGoalConceded)],
        ]}
        title="Penalità"
      />

      <RuleCard
        eyebrow="RISULTATO"
        rows={[
          [
            'Fasce gol',
            settings.goalBandsEnabled
              ? settings.goalBands.map(formatNumber).join(' · ')
              : `${formatNumber(settings.goalThreshold)} + ogni ${formatNumber(
                  settings.goalStep,
                )}`,
          ],
          [
            'Scarto minimo',
            settings.goalMarginEnabled
              ? `${formatNumber(settings.goalMargin)} fantapunti`
              : 'Disattivato',
          ],
          [
            'Spareggio classifica',
            tiebreakerLabel(settings.standingsTiebreaker),
          ],
        ]}
        title="Gol e classifica"
      />

      <RuleCard
        eyebrow="MODIFICATORE"
        rows={[
          [
            'Difesa',
            mode !== 'classic'
              ? 'Non previsto in Mantra'
              : settings.defenseModifierEnabled
                ? `Attivo con almeno ${settings.defenseModifierMinDefenders} difensori`
                : 'Disattivato',
          ],
        ]}
        title="Regole speciali"
      />
    </>
  );
}

function RuleCard({
  eyebrow,
  rows,
  title,
}: {
  eyebrow: string;
  rows: [string, string][];
  title: string;
}) {
  return (
    <View style={styles.ruleCard}>
      <Text style={styles.ruleEyebrow}>{eyebrow}</Text>
      <Text style={styles.ruleTitle}>{title}</Text>
      {rows.map(([label, value], index) => (
        <View
          key={label}
          style={[styles.ruleRow, index === rows.length - 1 && styles.lastRow]}
        >
          <Text style={styles.ruleLabel}>{label}</Text>
          <Text style={styles.ruleValue}>{value}</Text>
        </View>
      ))}
    </View>
  );
}

function SummaryItem({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.summaryItem}>
      <Text style={styles.summaryLabel}>{label}</Text>
      <Text style={styles.summaryValue}>{value}</Text>
    </View>
  );
}

function RevisionCard({ revision }: { revision: LeagueRuleRevision }) {
  return (
    <View style={styles.revisionCard}>
      <View style={styles.revisionTop}>
        <View style={styles.revisionBadge}>
          <Text style={styles.revisionBadgeText}>R{revision.revision}</Text>
        </View>
        <Text style={styles.revisionDate}>
          {formatDateTime(revision.changedAt)}
        </Text>
      </View>
      <Text style={styles.revisionReason}>{revision.reason}</Text>
      <Text style={styles.revisionActor}>
        MODIFICA DI {revision.changedBy.toUpperCase()}
      </Text>
      <View style={styles.tags}>
        {revision.changedKeys.map((key) => (
          <View key={key} style={styles.tag}>
            <Text style={styles.tagText}>{changedKeyLabel(key)}</Text>
          </View>
        ))}
      </View>
    </View>
  );
}

function changedKeyLabel(key: string) {
  const labels: Record<string, string> = {
    market_open: 'Mercato',
    market_min_price: 'Prezzo minimo',
    release_refund_percent: 'Rimborso',
    max_substitutions: 'Sostituzioni',
    defense_modifier_enabled: 'Modificatore',
    defense_modifier_min_defenders: 'Difensori minimi',
    goal_threshold: 'Primo gol',
    goal_step: 'Intervallo gol',
    goal_bands_enabled: 'Fasce gol',
    goal_bands: 'Soglie gol',
    goal_margin_enabled: 'Scarto minimo',
    goal_margin: 'Soglia scarto',
    standings_tiebreaker: 'Spareggio',
    home_bonus: 'Fattore casa',
    bonus_goal: 'Bonus gol',
    bonus_assist: 'Bonus assist',
    bonus_penalty_saved: 'Rigore parato',
    malus_yellow_card: 'Ammonizione',
    malus_red_card: 'Espulsione',
    malus_penalty_missed: 'Rigore sbagliato',
    malus_goal_conceded: 'Gol subito',
    roster_quota_goalkeepers: 'Portieri',
    roster_quota_defenders: 'Difensori',
    roster_quota_midfielders: 'Centrocampisti',
    roster_quota_attackers: 'Attaccanti',
  };
  return labels[key] ?? key.replaceAll('_', ' ');
}

function tiebreakerLabel(value: LeagueSettings['standingsTiebreaker']) {
  if (value === 'fantasy_points') return 'Fantapunti totali';
  if (value === 'head_to_head') return 'Scontri diretti';
  return 'Differenza reti';
}

function signed(value: number) {
  return value > 0 ? `+${formatNumber(value)}` : formatNumber(value);
}

function negative(value: number) {
  return value > 0 ? `−${formatNumber(value)}` : '0';
}

function formatNumber(value: number) {
  return new Intl.NumberFormat('it-IT', {
    maximumFractionDigits: 2,
  }).format(value);
}

function formatDate(value: string) {
  if (!value) return 'Non disponibile';
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  }).format(new Date(value));
}

function formatDateTime(value: string) {
  if (!value) return 'Data non disponibile';
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value));
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
  centerRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 28,
    backgroundColor: colors.canvas,
  },
  centerTitle: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '900',
    textAlign: 'center',
  },
  primaryButton: {
    height: 50,
    borderRadius: radius.md,
    backgroundColor: colors.navy,
    paddingHorizontal: 24,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 20,
  },
  primaryButtonText: {
    color: colors.lime,
    fontSize: 12,
    fontWeight: '900',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  backButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    backgroundColor: colors.white,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 12,
  },
  backText: {
    color: colors.navy,
    fontSize: 30,
    lineHeight: 32,
  },
  headerCopy: {
    flex: 1,
  },
  eyebrow: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  title: {
    color: colors.navy,
    fontSize: 28,
    fontWeight: '900',
    marginTop: 3,
  },
  heroCard: {
    borderRadius: radius.xl,
    backgroundColor: colors.navy,
    padding: 20,
    marginTop: 22,
    flexDirection: 'row',
  },
  heroMark: {
    width: 52,
    height: 52,
    borderRadius: 26,
    backgroundColor: colors.lime,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 15,
  },
  heroMarkText: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
  },
  heroCopy: {
    flex: 1,
  },
  heroEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  heroTitle: {
    color: colors.warmWhite,
    fontSize: 20,
    fontWeight: '900',
    marginTop: 7,
  },
  heroBody: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 5,
  },
  loadingCard: {
    borderRadius: radius.lg,
    backgroundColor: colors.white,
    padding: 22,
    marginTop: 16,
    alignItems: 'center',
  },
  loadingText: {
    color: colors.muted,
    fontSize: 13,
    fontWeight: '700',
    marginTop: 10,
  },
  errorCard: {
    borderRadius: radius.lg,
    backgroundColor: '#FFF1EF',
    padding: 20,
    marginTop: 16,
  },
  errorTitle: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  errorBody: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 6,
  },
  retryButton: {
    alignSelf: 'flex-start',
    borderRadius: radius.md,
    backgroundColor: colors.navy,
    paddingHorizontal: 18,
    paddingVertical: 12,
    marginTop: 14,
  },
  retryText: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
  },
  summaryCard: {
    borderRadius: radius.lg,
    backgroundColor: colors.white,
    padding: 8,
    marginTop: 16,
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  summaryItem: {
    width: '50%',
    padding: 12,
  },
  summaryLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  summaryValue: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
    marginTop: 4,
  },
  versionRow: {
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: '#DDE2DA',
    padding: 15,
    marginTop: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  versionLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  versionValue: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
    marginTop: 4,
  },
  versionDate: {
    color: colors.muted,
    fontSize: 11,
    fontWeight: '700',
  },
  editButton: {
    borderRadius: radius.lg,
    backgroundColor: colors.lime,
    padding: 17,
    marginTop: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  editEyebrow: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  editTitle: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
    marginTop: 4,
  },
  editArrow: {
    color: colors.navy,
    fontSize: 23,
    fontWeight: '900',
  },
  ruleCard: {
    borderRadius: radius.lg,
    backgroundColor: colors.white,
    padding: 18,
    marginTop: 14,
  },
  ruleEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  ruleTitle: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
    marginTop: 4,
    marginBottom: 10,
  },
  ruleRow: {
    minHeight: 42,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#DFE4DC',
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 8,
  },
  lastRow: {
    borderBottomWidth: 0,
  },
  ruleLabel: {
    flex: 1,
    color: colors.muted,
    fontSize: 12,
    fontWeight: '700',
    paddingRight: 12,
  },
  ruleValue: {
    flex: 1.25,
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
    textAlign: 'right',
  },
  historyHeader: {
    marginTop: 28,
    marginBottom: 4,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  sectionEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
    marginTop: 3,
  },
  emptyHistory: {
    borderRadius: radius.lg,
    backgroundColor: colors.white,
    padding: 20,
    marginTop: 10,
  },
  emptyHistoryTitle: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  emptyHistoryBody: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 6,
  },
  revisionCard: {
    borderRadius: radius.lg,
    backgroundColor: colors.white,
    padding: 18,
    marginTop: 10,
  },
  revisionTop: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  revisionBadge: {
    borderRadius: 12,
    backgroundColor: colors.navy,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  revisionBadgeText: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
  },
  revisionDate: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '700',
  },
  revisionReason: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
    lineHeight: 21,
    marginTop: 13,
  },
  revisionActor: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.5,
    marginTop: 8,
  },
  tags: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    marginTop: 10,
    gap: 6,
  },
  tag: {
    borderRadius: 12,
    backgroundColor: colors.canvasMuted,
    paddingHorizontal: 9,
    paddingVertical: 6,
  },
  tagText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '800',
  },
  footnote: {
    color: colors.muted,
    fontSize: 10,
    lineHeight: 15,
    textAlign: 'center',
    marginTop: 16,
    paddingHorizontal: 12,
  },
});
