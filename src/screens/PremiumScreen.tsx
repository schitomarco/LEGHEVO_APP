import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import type { CommercialEntitlement } from '../services/subscriptionService';
import { colors, radius } from '../theme';

type Props = {
  entitlement: CommercialEntitlement;
  error: string;
  isDemo: boolean;
  onBack: () => void;
  onPurchase: () => Promise<{ error?: string }>;
  onRestore: () => Promise<{ error?: string }>;
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
        <Text style={styles.price}>{entitlement.monthlyPriceLabel}</Text>
        <Text style={styles.priceDetail}>
          Abbonamento mensile · rinnovo automatico · disdici dallo store
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
            disabled={!entitlement.purchasesEnabled || isDemo}
            onPress={() => void onPurchase()}
            style={[
              styles.purchaseButton,
              (!entitlement.purchasesEnabled || isDemo) &&
                styles.purchaseButtonDisabled,
            ]}
          >
            <Text style={styles.purchaseText}>
              {entitlement.purchasesEnabled
                ? 'ATTIVA PREMIUM'
                : 'ACQUISTI IN PREPARAZIONE'}
            </Text>
          </Pressable>
        )}
      </View>

      {!entitlement.purchasesEnabled && !entitlement.isPremium ? (
        <View style={styles.notice}>
          <Text style={styles.noticeTitle}>Nessun addebito attivo</Text>
          <Text style={styles.noticeBody}>
            La schermata è pronta per il collaudo. Collegheremo Apple e Google
            prima della versione 1.0.0.
          </Text>
        </View>
      ) : null}

      {error ? <Text style={styles.error}>{error}</Text> : null}

      <Pressable
        disabled={!entitlement.purchasesEnabled || isDemo}
        onPress={() => void onRestore()}
        style={styles.restoreButton}
      >
        <Text style={styles.restoreText}>Ripristina acquisti</Text>
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
  price: { color: colors.navy, fontSize: 28, fontWeight: '900' },
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
  legal: { color: colors.mutedLight, fontSize: 10, lineHeight: 16, textAlign: 'center' },
});
