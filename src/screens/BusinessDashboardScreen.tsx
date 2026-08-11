import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useBusinessDashboard } from '../hooks/useBusinessDashboard';
import type {
  BusinessDailyPoint,
  BusinessMonthlyPoint,
} from '../services/businessDashboardService';
import { colors, radius, shadow } from '../theme';

type Props = {
  allowed: boolean;
  onBack: () => void;
};

export function BusinessDashboardScreen({ allowed, onBack }: Props) {
  const dashboard = useBusinessDashboard(allowed);

  if (!allowed) {
    return (
      <View style={styles.centerRoot}>
        <Text style={styles.centerTitle}>Area riservata</Text>
        <Text style={styles.centerBody}>
          La Business Dashboard è accessibile soltanto al proprietario LEGHEVO.
        </Text>
        <Pressable onPress={onBack} style={styles.primaryButton}>
          <Text style={styles.primaryButtonText}>TORNA AL PROFILO</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
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
          <Text style={styles.eyebrow}>AREA PROPRIETARIO</Text>
          <Text style={styles.title}>Business Dashboard</Text>
        </View>
      </View>
      <View style={styles.refreshRow}>
        <Pressable
          accessibilityLabel="Aggiorna ricavi"
          accessibilityHint="Ricalcola i dati della Business Dashboard"
          accessibilityRole="button"
          accessibilityState={{ busy: dashboard.loading, disabled: dashboard.loading }}
          disabled={dashboard.loading}
          onPress={() => void dashboard.refresh()}
          hitSlop={8}
          style={({ pressed }) => [
            styles.refreshButton,
            pressed && !dashboard.loading && styles.refreshButtonPressed,
            dashboard.loading && styles.refreshButtonDisabled,
          ]}
        >
          {dashboard.loading ? (
            <ActivityIndicator color={colors.warmWhite} size="small" />
          ) : (
            <Text style={styles.refreshIcon}>↻</Text>
          )}
          <Text style={styles.refreshText}>
            {dashboard.loading ? 'AGGIORNAMENTO…' : 'AGGIORNA DATI'}
          </Text>
        </Pressable>
      </View>

      {dashboard.loading && !dashboard.data ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.navy} />
          <Text style={styles.loadingText}>Calcolo dei dati gestionali…</Text>
        </View>
      ) : null}

      {dashboard.error ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>Dati non disponibili</Text>
          <Text style={styles.errorBody}>{dashboard.error}</Text>
        </View>
      ) : null}

      {dashboard.data ? (
        <>
          <View style={styles.heroCard}>
            <Text style={styles.heroEyebrow}>LEGHEVO · RICAVI GESTIONALI</Text>
            <Text style={styles.heroAmount}>
              {euro(dashboard.data.seasonRevenueCents)}
            </Text>
            <Text style={styles.heroLabel}>questa stagione</Text>
            <View style={styles.heroRow}>
              <View style={styles.heroMetric}>
                <Text style={styles.heroMetricLabel}>OGGI</Text>
                <Text style={styles.heroMetricValue}>
                  {euro(dashboard.data.todayRevenueCents)}
                </Text>
              </View>
              <View style={styles.heroDivider} />
              <View style={styles.heroMetric}>
                <Text style={styles.heroMetricLabel}>QUESTO MESE</Text>
                <Text style={styles.heroMetricValue}>
                  {euro(dashboard.data.monthRevenueCents)}
                </Text>
              </View>
            </View>
          </View>

          <Text style={styles.sectionTitle}>Pubblico e conversione</Text>
          <View style={styles.metricGrid}>
            <Metric label="Utenti attivi · 30 gg" value={number(dashboard.data.activeUsers)} />
            <Metric label="Premium attivi" value={number(dashboard.data.premiumUsers)} />
            <Metric label="Conversione" value={`${decimal(dashboard.data.conversionRate)}%`} />
            <Metric label="ARPU mensile" value={euro(dashboard.data.arpuCents)} />
          </View>

          <Text style={styles.sectionTitle}>Fonti della stagione</Text>
          <View style={styles.listCard}>
            <MoneyRow label="Abbonamenti Apple" value={dashboard.data.appleRevenueCents} />
            <MoneyRow label="Abbonamenti Google" value={dashboard.data.googleRevenueCents} />
            <MoneyRow label="Pubblicità" value={dashboard.data.advertisingRevenueCents} />
            <MoneyRow label="League Pro" value={dashboard.data.leagueProRevenueCents} last />
          </View>

          <View style={styles.marginCard}>
            <MoneyRow light label="Ricavi" value={dashboard.data.totalRevenueCents} />
            <MoneyRow light label="Costi stimati" value={dashboard.data.estimatedCostsCents} />
            <View style={styles.marginDivider} />
            <Text style={styles.marginLabel}>MARGINE OPERATIVO STIMATO</Text>
            <Text style={styles.marginValue}>
              {euro(dashboard.data.operatingMarginCents)}
            </Text>
          </View>

          <Text style={styles.sectionTitle}>Premium · questo mese</Text>
          <View style={styles.metricGrid}>
            <Metric label="Nuovi Premium" value={number(dashboard.data.newPremium)} />
            <Metric label="Rinnovi" value={number(dashboard.data.renewals)} />
            <Metric label="Cancellazioni" value={number(dashboard.data.cancellations)} />
            <Metric label="Leghe attive" value={number(dashboard.data.activeLeagues)} />
          </View>

          <Text style={styles.sectionTitle}>Ricavi giornalieri · 30 giorni</Text>
          <DailyChart points={dashboard.data.daily} />

          <Text style={styles.sectionTitle}>Ricavi e leghe · 12 mesi</Text>
          <MonthlyChart points={dashboard.data.monthly} />

          <View style={styles.noticeCard}>
            <Text style={styles.noticeTitle}>DATI GESTIONALI</Text>
            <Text style={styles.noticeBody}>
              {dashboard.data.officialSourceNotice}
            </Text>
            <Text style={styles.generatedText}>
              Aggiornato {dateTime(dashboard.data.generatedAt)}
            </Text>
          </View>
        </>
      ) : null}
    </ScrollView>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.metricCard}>
      <Text style={styles.metricLabel}>{label}</Text>
      <Text adjustsFontSizeToFit numberOfLines={1} style={styles.metricValue}>
        {value}
      </Text>
    </View>
  );
}

function MoneyRow({
  label,
  value,
  last = false,
  light = false,
}: {
  label: string;
  value: number;
  last?: boolean;
  light?: boolean;
}) {
  return (
    <View style={[styles.moneyRow, last && styles.moneyRowLast]}>
      <Text style={[styles.moneyLabel, light && styles.moneyLabelLight]}>{label}</Text>
      <Text style={[styles.moneyValue, light && styles.moneyValueLight]}>{euro(value)}</Text>
    </View>
  );
}

function DailyChart({ points }: { points: BusinessDailyPoint[] }) {
  const visible = points.slice(-14);
  const maximum = Math.max(...visible.map((point) => point.revenueCents), 1);
  return (
    <View style={styles.chartCard}>
      <View style={styles.bars}>
        {visible.map((point) => (
          <View key={point.period} style={styles.barColumn}>
            <View
              accessibilityLabel={`${point.period}: ${euro(point.revenueCents)}`}
              style={[
                styles.bar,
                { height: Math.max(5, Math.round((point.revenueCents / maximum) * 104)) },
              ]}
            />
            <Text style={styles.barLabel}>{point.period.slice(8)}</Text>
          </View>
        ))}
      </View>
      <Text style={styles.chartCaption}>Ultimi 14 giorni · valori lordi stimati</Text>
    </View>
  );
}

function MonthlyChart({ points }: { points: BusinessMonthlyPoint[] }) {
  const maximum = Math.max(...points.map((point) => point.revenueCents), 1);
  return (
    <View style={styles.chartCard}>
      <View style={styles.bars}>
        {points.map((point) => (
          <View key={point.period} style={styles.barColumn}>
            <View
              accessibilityLabel={`${point.period}: ${euro(point.revenueCents)}, ${point.leaguesCreated} leghe`}
              style={[
                styles.bar,
                styles.monthBar,
                { height: Math.max(5, Math.round((point.revenueCents / maximum) * 104)) },
              ]}
            />
            <Text style={styles.barLabel}>{point.period.slice(5)}</Text>
          </View>
        ))}
      </View>
      <Text style={styles.chartCaption}>
        Il dettaglio accessibile di ogni barra include anche le nuove leghe.
      </Text>
    </View>
  );
}

function euro(cents: number) {
  return `${(cents / 100).toLocaleString('it-IT', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })} €`;
}

function number(value: number) {
  return value.toLocaleString('it-IT');
}

function decimal(value: number) {
  return value.toLocaleString('it-IT', { maximumFractionDigits: 2 });
}

function dateTime(value: string) {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime())
    ? 'ora'
    : parsed.toLocaleString('it-IT', { dateStyle: 'short', timeStyle: 'short' });
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.canvas },
  content: { padding: 20, paddingBottom: 42 },
  header: { flexDirection: 'row', alignItems: 'center' },
  headerCopy: { flex: 1, marginHorizontal: 12 },
  backButton: { width: 44, height: 44, borderRadius: 22, backgroundColor: colors.navySoft, alignItems: 'center', justifyContent: 'center' },
  backText: { color: colors.warmWhite, fontSize: 30, lineHeight: 33, fontWeight: '700' },
  refreshRow: { alignItems: 'flex-end', marginTop: 14 },
  refreshButton: { minWidth: 148, height: 42, borderRadius: 21, paddingHorizontal: 16, backgroundColor: colors.navySoft, flexDirection: 'row', gap: 8, alignItems: 'center', justifyContent: 'center' },
  refreshButtonPressed: { opacity: 0.78 },
  refreshButtonDisabled: { opacity: 0.7 },
  refreshIcon: { color: colors.lime, fontSize: 20, lineHeight: 22, fontWeight: '900' },
  refreshText: { color: colors.warmWhite, fontSize: 10, fontWeight: '900', letterSpacing: 0.5 },
  eyebrow: { color: colors.muted, fontSize: 9, fontWeight: '900', letterSpacing: 0.7 },
  title: { color: colors.navy, fontSize: 24, fontWeight: '900', marginTop: 3 },
  heroCard: { backgroundColor: colors.navy, borderRadius: radius.xl, padding: 24, marginTop: 14, ...shadow },
  heroEyebrow: { color: colors.lime, fontSize: 10, fontWeight: '900', letterSpacing: 0.7 },
  heroAmount: { color: colors.warmWhite, fontSize: 42, fontWeight: '900', marginTop: 14 },
  heroLabel: { color: colors.mutedLight, fontSize: 13, marginTop: 3 },
  heroRow: { flexDirection: 'row', marginTop: 24, alignItems: 'stretch' },
  heroMetric: { flex: 1 },
  heroDivider: { width: 1, backgroundColor: colors.navyLine, marginHorizontal: 16 },
  heroMetricLabel: { color: colors.mutedLight, fontSize: 9, fontWeight: '900' },
  heroMetricValue: { color: colors.warmWhite, fontSize: 18, fontWeight: '900', marginTop: 6 },
  sectionTitle: { color: colors.navy, fontSize: 18, fontWeight: '900', marginTop: 28, marginBottom: 12 },
  metricGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  metricCard: { width: '48%', flexGrow: 1, minHeight: 96, borderRadius: radius.lg, backgroundColor: colors.white, padding: 16 },
  metricLabel: { color: colors.muted, fontSize: 11, fontWeight: '700' },
  metricValue: { color: colors.navy, fontSize: 24, fontWeight: '900', marginTop: 10 },
  listCard: { borderRadius: radius.lg, backgroundColor: colors.white, paddingHorizontal: 18 },
  moneyRow: { minHeight: 58, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: colors.canvasMuted },
  moneyRowLast: { borderBottomWidth: 0 },
  moneyLabel: { color: colors.navy, fontSize: 14, fontWeight: '700' },
  moneyValue: { color: colors.navy, fontSize: 16, fontWeight: '900' },
  marginCard: { backgroundColor: colors.navy, borderRadius: radius.xl, padding: 20, marginTop: 16 },
  moneyLabelLight: { color: colors.mutedLight },
  moneyValueLight: { color: colors.warmWhite },
  marginDivider: { height: 1, backgroundColor: colors.navyLine, marginVertical: 18 },
  marginLabel: { color: colors.lime, fontSize: 10, fontWeight: '900', letterSpacing: 0.6 },
  marginValue: { color: colors.warmWhite, fontSize: 32, fontWeight: '900', marginTop: 8 },
  chartCard: { borderRadius: radius.lg, backgroundColor: colors.white, padding: 16 },
  bars: { height: 128, flexDirection: 'row', alignItems: 'flex-end', gap: 5 },
  barColumn: { flex: 1, alignItems: 'center', justifyContent: 'flex-end' },
  bar: { width: '72%', minWidth: 4, borderRadius: 4, backgroundColor: colors.lime },
  monthBar: { backgroundColor: colors.navySoft },
  barLabel: { color: colors.muted, fontSize: 8, marginTop: 6 },
  chartCaption: { color: colors.muted, fontSize: 11, lineHeight: 16, marginTop: 14 },
  noticeCard: { borderRadius: radius.lg, backgroundColor: colors.limeSoft, padding: 18, marginTop: 24 },
  noticeTitle: { color: colors.navy, fontSize: 10, fontWeight: '900', letterSpacing: 0.6 },
  noticeBody: { color: colors.navy, fontSize: 13, lineHeight: 19, marginTop: 7 },
  generatedText: { color: colors.muted, fontSize: 10, marginTop: 10 },
  loadingCard: { borderRadius: radius.lg, backgroundColor: colors.white, padding: 24, marginTop: 24, alignItems: 'center' },
  loadingText: { color: colors.muted, fontSize: 13, marginTop: 10 },
  errorCard: { borderRadius: radius.lg, backgroundColor: '#FFE8E6', padding: 18, marginTop: 24 },
  errorTitle: { color: colors.danger, fontSize: 14, fontWeight: '900' },
  errorBody: { color: colors.navy, fontSize: 13, lineHeight: 19, marginTop: 6 },
  centerRoot: { flex: 1, backgroundColor: colors.canvas, alignItems: 'center', justifyContent: 'center', padding: 28 },
  centerTitle: { color: colors.navy, fontSize: 27, fontWeight: '900' },
  centerBody: { color: colors.muted, fontSize: 14, lineHeight: 21, textAlign: 'center', marginTop: 10 },
  primaryButton: { height: 52, borderRadius: radius.md, backgroundColor: colors.navy, paddingHorizontal: 24, alignItems: 'center', justifyContent: 'center', marginTop: 24 },
  primaryButtonText: { color: colors.lime, fontSize: 12, fontWeight: '900' },
});
