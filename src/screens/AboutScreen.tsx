import { Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import {
  LEGAL_DOCUMENT_DATE,
  PRIVACY_POLICY_VERSION,
  TERMS_VERSION,
} from '../legalDocuments';
import {
  LEGHEVO_ACTIVE_SERVICES,
  LEGHEVO_LEGAL_PROFILE,
} from '../legalProfile';
import { APP_RELEASE_VERSION } from '../release';
import { colors, radius } from '../theme';

type Props = {
  onBack: () => void;
  onPrivacy: () => void;
};

export function AboutScreen({ onBack, onPrivacy }: Props) {
  const openEmail = () =>
    void Linking.openURL(`mailto:${LEGHEVO_LEGAL_PROFILE.supportEmail}`);
  const openPhone = () =>
    void Linking.openURL(
      `tel:${LEGHEVO_LEGAL_PROFILE.phone.replace(/\s/g, '')}`,
    );

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.header}>
        <Pressable onPress={onBack} style={styles.backButton}>
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>TRASPARENZA</Text>
          <Text style={styles.title}>Informazioni</Text>
        </View>
      </View>

      <View style={styles.heroCard}>
        <Text style={styles.heroEyebrow}>LEGHEVO</Text>
        <Text style={styles.heroTitle}>Il fantasy football di lega.</Text>
        <Text style={styles.heroBody}>
          App per iOS e Android ideata e sviluppata da Marco Schito.
        </Text>
        <Text style={styles.version}>Versione {APP_RELEASE_VERSION}</Text>
      </View>

      <Text style={styles.sectionTitle}>Titolare e sviluppatore</Text>
      <View style={styles.card}>
        <InfoRow label="Nome" value={LEGHEVO_LEGAL_PROFILE.controllerName} />
        <InfoRow label="Codice fiscale" value={LEGHEVO_LEGAL_PROFILE.taxCode} />
        <InfoRow label="Sede" value={LEGHEVO_LEGAL_PROFILE.address} />
        <InfoRow label="Sviluppo" value={LEGHEVO_LEGAL_PROFILE.developerName} />
        <InfoRow
          label="Ambito"
          value={`Disponibile in ${LEGHEVO_LEGAL_PROFILE.launchMarket} · età minima ${LEGHEVO_LEGAL_PROFILE.minimumAge} anni`}
        />
      </View>

      <Text style={styles.sectionTitle}>Contatti</Text>
      <View style={styles.card}>
        <ActionRow
          label="Email e privacy"
          value={LEGHEVO_LEGAL_PROFILE.privacyEmail}
          onPress={openEmail}
        />
        <InfoRow label="PEC" value={LEGHEVO_LEGAL_PROFILE.certifiedEmail} />
        <ActionRow
          label="Telefono"
          value={LEGHEVO_LEGAL_PROFILE.phone}
          onPress={openPhone}
        />
        <InfoRow
          label="DPO"
          value="Non nominato"
        />
      </View>

      <Text style={styles.sectionTitle}>Servizi tecnici</Text>
      <View style={styles.card}>
        {LEGHEVO_ACTIVE_SERVICES.map((service) => (
          <InfoRow
            key={service.name}
            label={service.name}
            value={service.purpose}
          />
        ))}
        <InfoRow
          label="Email tecniche"
          value="Supabase Auth; nessun provider dedicato configurato"
        />
        <InfoRow
          label="Analytics pubblicitari"
          value="Non attivi"
        />
      </View>

      <Text style={styles.sectionTitle}>Documenti</Text>
      <View style={styles.card}>
        <InfoRow
          label="Informativa privacy"
          value={`Versione ${PRIVACY_POLICY_VERSION}`}
        />
        <InfoRow
          label="Termini di utilizzo"
          value={`Versione ${TERMS_VERSION}`}
        />
        <InfoRow label="Pubblicati" value={LEGAL_DOCUMENT_DATE} />
        <Pressable onPress={onPrivacy} style={styles.documentButton}>
          <Text style={styles.documentButtonText}>
            APRI PRIVACY E CENTRO DIRITTI
          </Text>
        </Pressable>
      </View>
    </ScrollView>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.infoRow}>
      <Text style={styles.infoLabel}>{label}</Text>
      <Text style={styles.infoValue}>{value}</Text>
    </View>
  );
}

function ActionRow({
  label,
  value,
  onPress,
}: {
  label: string;
  value: string;
  onPress: () => void;
}) {
  return (
    <Pressable onPress={onPress} style={styles.infoRow}>
      <Text style={styles.infoLabel}>{label}</Text>
      <View style={styles.actionValue}>
        <Text style={[styles.infoValue, styles.link]}>{value}</Text>
        <Text style={styles.arrow}>›</Text>
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    padding: 20,
    paddingBottom: 38,
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
  heroCard: {
    borderRadius: radius.xl,
    backgroundColor: colors.navy,
    padding: 22,
    marginTop: 22,
  },
  heroEyebrow: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.6,
  },
  heroTitle: {
    color: colors.warmWhite,
    fontSize: 22,
    fontWeight: '900',
    marginTop: 13,
  },
  heroBody: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 20,
    marginTop: 7,
  },
  version: {
    alignSelf: 'flex-start',
    borderRadius: 12,
    backgroundColor: colors.navySoft,
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    paddingHorizontal: 10,
    paddingVertical: 6,
    marginTop: 16,
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
    paddingHorizontal: 16,
  },
  infoRow: {
    minHeight: 66,
    justifyContent: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#DFE4DC',
    paddingVertical: 11,
  },
  infoLabel: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    textTransform: 'uppercase',
    letterSpacing: 0.35,
  },
  infoValue: {
    color: colors.navy,
    fontSize: 13,
    lineHeight: 19,
    fontWeight: '700',
    marginTop: 4,
  },
  actionValue: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  link: {
    flex: 1,
    textDecorationLine: 'underline',
  },
  arrow: {
    color: colors.muted,
    fontSize: 23,
    marginLeft: 8,
  },
  documentButton: {
    minHeight: 50,
    alignItems: 'center',
    justifyContent: 'center',
    marginVertical: 14,
    borderRadius: radius.md,
    backgroundColor: colors.lime,
  },
  documentButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
});
