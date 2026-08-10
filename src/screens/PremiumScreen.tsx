import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import type {
  CommercialBillingPeriod,
  CommercialEntitlement,
} from '../services/subscriptionService';
import { colors, radius } from '../theme';

type Props = {
  entitlement: CommercialEntitlement;
  error: string;
  isDemo: boolean;
  onBack: () => void;
  onPurchase: (period: CommercialBillingPeriod) => Promise<{ error?: string }>;
  onRestore: () => Promise<{ restored: boolean; error?: string }>;
};

const features = [
  'Leghe senza limite commerciale',
  'Fino a 20 partecipanti per lega',
  'Nessuna pubblicità sul tuo account',
  'Premium disponibile su tutti i tuoi dispositivi',
];

export function PremiumScreen({
  entitlement,
  error,
  isDemo,
  onBack,
  onPurchase,
  onRestore,
}: Props) {
  const [billingPeriod, setBillingPeriod] =
    useState<CommercialBillingPeriod>('annual');
  const [busyAction, setBusyAction] = useState<'purchase' | 'restore' | null>(null);
  const [restoreMessage, setRestoreMessage] = useState('');

  const purchase = async () => {
    if (busyAction) return;
    setBusyAction('purchase');
    try {
      await onPurchase(billingPeriod);
    } finally {
      setBusyAction(null);
    }
  };

  const restore = async () => {
    if (busyAction) return;
    setRestoreMessage('');
    setBusyAction('restore');
    try {
      const outcome = await onRestore();
      if (!outcome.error) {
        setRestoreMessage(
          outcome.restored
            ? 'Acquisti ripristinati. Premium è attivo su questo account.'
            : 'Non risultano acquisti Premium da ripristinare per questo account.',
        );
      }
    } finally {
      setBusyAction(null);
    }
  };

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <Pressable onPress={onBack} style={styles.backButton}>
        <Text style={styles.backText}>‹</Text>
      </Pressable>

      <View style={styles.pill}>
        <Text style={styles.pillText}>LEGHEVO PREMIUM</Text>
      </View>
      <Text style={styles.title}>Il campionato senza limiti inutili.</Text>
      <Text style={styles.subtitle}>
        Più leghe, più partecipanti e zero interruzioni pubblicitarie.
      </Text>

      <View style={styles.priceCard}>
        <View style={styles.planRow}>
          <PlanChoice
            active={billingPeriod === 'annual'}
            badge="PIÙ CONVENIENTE"
            label="ANNUALE"
            onPress={() => setBillingPeriod('annual')}
            price={entitlement.annualPriceLabel}
          />
          <PlanChoice
            active={billingPeriod === 'monthly'}
            label="MENSILE"
            onPress={() => setBillingPeriod('monthly')}
            price={entitlement.monthlyPriceLabel}
          />
        </View>
        <Text style={styles.priceDetail}>
          Stesse funzioni Premium · rinnovo automatico · disdici dallo store
        </Text>
        {features.map((feature) => (
          <View key={feature} style={styles.featureRow}>
            <Text style={styles.check}>✓</Text>
            <Text style={styles.featureText}>{feature}</Text>
          </View>
        ))}

        {entitlement.isPremium ? (
          <View style={styles.activeCard}>
            <Text style={styles.activeTitle}>PREMIUM ATTIVO</Text>
            <Text style={styles.activeBody}>
              Questo account gioca già senza pubblicità e con i limiti Premium.
            </Text>
          </View>
        ) : (
          <Pressable
            disabled={!entitlement.purchasesEnabled || isDemo || busyAction !== null}
            onPress={() => void purchase()}
            style={[
              styles.purchaseButton,
              (!entitlement.purchasesEnabled || isDemo || busyAction !== null) &&
                styles.purchaseButtonDisabled,
            ]}
          >
            <Text style={styles.purchaseText}>
              {busyAction === 'purchase'
                ? 'ELABORAZIONE…'
                : entitlement.purchasesEnabled
                ? entitlement.purchaseMode === 'test'
                  ? 'PROVA PREMIUM NEL TEST STORE'
                  : 'ATTIVA PREMIUM'
                : 'ACQUISTI IN PREPARAZIONE'}
            </Text>
          </Pressable>
        )}
      </View>

      {!entitlement.purchasesEnabled && !entitlement.isPremium ? (
        <View style={styles.notice}>
          <Text style={styles.noticeTitle}>Acquisti non ancora attivi</Text>
          <Text style={styles.noticeBody}>
            Apple e Google verranno abilitati dopo il collaudo sandbox completo
            previsto per la versione 1.0.0.
          </Text>
        </View>
      ) : null}

      {error ? <Text style={styles.error}>{error}</Text> : null}
      {restoreMessage ? (
        <Text accessibilityLiveRegion="polite" style={styles.restoreMessage}>
          {restoreMessage}
        </Text>
      ) : null}

      <Pressable
        disabled={!entitlement.purchasesEnabled || isDemo || busyAction !== null}
        onPress={() => void restore()}
        style={styles.restoreButton}
      >
        <Text style={styles.restoreText}>
          {busyAction === 'restore' ? 'Ripristino…' : 'Ripristina acquisti'}
        </Text>
      </Pressable>

      <Text style={styles.legal}>
        Il piano Free consente una lega da massimo 6 partecipanti. Le leghe già
        create non vengono eliminate alla scadenza di Premium. Prezzo e condizioni
        definitive saranno sempre mostrati da App Store o Google Play prima
        dell’acquisto.
      </Text>
    </ScrollView>
  );
}

function PlanChoice({
  active,
  badge,
  label,
  onPress,
  price,
}: {
  active: boolean;
  badge?: string;
  label: string;
  onPress: () => void;
  price: string;
}) {
  return (
    <Pressable
      onPress={onPress}
      style={[styles.planChoice, active && styles.planChoiceActive]}
    >
      {badge ? <Text style={styles.planBadge}>{badge}</Text> : null}
      <Text style={[styles.planLabel, active && styles.planLabelActive]}>
        {label}
      </Text>
      <Text style={[styles.planPrice, active && styles.planPriceActive]}>
        {price}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.navy },
  content: { padding: 20, paddingBottom: 42 },
  backButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    backgroundColor: '#102943',
    alignItems: 'center',
    justifyContent: 'center',
  },
  backText: { color: colors.warmWhite, fontSize: 31, marginTop: -3 },
  pill: {
    alignSelf: 'flex-start',
    backgroundColor: colors.lime,
    borderRadius: 14,
    paddingHorizontal: 13,
    paddingVertical: 8,
    marginTop: 24,
  },
  pillText: { color: colors.navy, fontSize: 9, fontWeight: '900' },
  title: {
    color: colors.warmWhite,
    fontSize: 32,
    lineHeight: 37,
    fontWeight: '900',
    marginTop: 18,
  },
  subtitle: {
    color: colors.mutedLight,
    fontSize: 15,
    lineHeight: 22,
    marginTop: 10,
  },
  priceCard: {
    backgroundColor: colors.warmWhite,
    borderRadius: radius.xl,
    padding: 22,
    marginTop: 24,
  },
  planRow: { flexDirection: 'row', gap: 10 },
  planChoice: {
    flex: 1,
    minHeight: 100,
    borderWidth: 1,
    borderColor: '#D9DFD3',
    borderRadius: radius.md,
    padding: 13,
    justifyContent: 'flex-end',
  },
  planChoiceActive: { backgroundColor: colors.navy, borderColor: colors.navy },
  planBadge: { color: colors.lime, fontSize: 7, fontWeight: '900', marginBottom: 8 },
  planLabel: { color: colors.muted, fontSize: 9, fontWeight: '900' },
  planLabelActive: { color: colors.mutedLight },
  planPrice: { color: colors.navy, fontSize: 18, fontWeight: '900', marginTop: 5 },
  planPriceActive: { color: colors.warmWhite },
  priceDetail: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 5,
    marginBottom: 18,
  },
  featureRow: { flexDirection: 'row', alignItems: 'center', marginTop: 12 },
  check: { color: colors.navy, fontSize: 15, fontWeight: '900', width: 26 },
  featureText: { flex: 1, color: colors.navy, fontSize: 14, fontWeight: '700' },
  purchaseButton: {
    minHeight: 52,
    borderRadius: radius.md,
    backgroundColor: colors.lime,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 24,
  },
  purchaseButtonDisabled: { backgroundColor: '#DDE5D1' },
  purchaseText: { color: colors.navy, fontSize: 13, fontWeight: '900' },
  activeCard: {
    borderRadius: radius.md,
    backgroundColor: '#E7F7BE',
    padding: 16,
    marginTop: 22,
  },
  activeTitle: { color: colors.navy, fontSize: 11, fontWeight: '900' },
  activeBody: { color: colors.navy, fontSize: 13, lineHeight: 19, marginTop: 5 },
  notice: {
    borderRadius: radius.lg,
    backgroundColor: '#102943',
    padding: 17,
    marginTop: 16,
  },
  noticeTitle: { color: colors.lime, fontSize: 12, fontWeight: '900' },
  noticeBody: { color: colors.mutedLight, fontSize: 13, lineHeight: 19, marginTop: 6 },
  error: { color: '#FFB7B7', fontSize: 13, lineHeight: 18, marginTop: 16 },
  restoreButton: { alignItems: 'center', paddingVertical: 18 },
  restoreText: { color: colors.warmWhite, fontSize: 13, fontWeight: '800' },
  restoreMessage: {
    color: colors.lime,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 16,
    textAlign: 'center',
  },
  legal: { color: colors.mutedLight, fontSize: 10, lineHeight: 16, textAlign: 'center' },
});
