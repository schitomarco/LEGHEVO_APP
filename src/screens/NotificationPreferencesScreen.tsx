import {
  ActivityIndicator,
  Linking,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import type { PushPermissionState } from '../services/pushNotificationService';
import { colors, radius } from '../theme';
import type { PushNotificationPreferences } from '../types';

type CategoryKey =
  | 'auctionTradeEnabled'
  | 'lineupEnabled'
  | 'resultsEnabled'
  | 'leagueEnabled'
  | 'systemEnabled';

type Props = {
  preferences: PushNotificationPreferences;
  permission: PushPermissionState;
  loading: boolean;
  busy: boolean;
  error: string;
  isDemo: boolean;
  onBack: () => void;
  onDisable: () => void | Promise<void>;
  onEnable: () => void | Promise<void>;
  onRefresh: () => void | Promise<void>;
  onUpdate: (key: CategoryKey, enabled: boolean) => void | Promise<void>;
};

const categories: Array<{
  key: CategoryKey;
  title: string;
  body: string;
  symbol: string;
}> = [
  {
    key: 'lineupEnabled',
    title: 'Formazione',
    body: 'Scadenze, recuperi automatici e distinta mancante.',
    symbol: '11',
  },
  {
    key: 'auctionTradeEnabled',
    title: 'Asta e mercato',
    body: 'Rilanci superati, acquisti, svincoli e scambi.',
    symbol: '↔',
  },
  {
    key: 'resultsEnabled',
    title: 'Risultati',
    body: 'Live, ufficializzazioni, correzioni e voti d’ufficio.',
    symbol: 'V',
  },
  {
    key: 'leagueEnabled',
    title: 'Attività della lega',
    body: 'Calendario, competizioni, inviti e decisioni del Presidente.',
    symbol: 'L',
  },
  {
    key: 'systemEnabled',
    title: 'Servizio LEGHEVO',
    body: 'Sicurezza, account e comunicazioni tecniche indispensabili.',
    symbol: '!',
  },
];

export function NotificationPreferencesScreen({
  preferences,
  permission,
  loading,
  busy,
  error,
  isDemo,
  onBack,
  onDisable,
  onEnable,
  onRefresh,
  onUpdate,
}: Props) {
  const enabled = preferences.pushEnabled;

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
          <Text style={styles.eyebrow}>AVVISI SOTTO CONTROLLO</Text>
          <Text style={styles.title}>Preferenze</Text>
        </View>
        <Pressable
          accessibilityLabel="Aggiorna preferenze"
          disabled={loading || busy}
          onPress={() => void onRefresh()}
          style={styles.reloadButton}
        >
          <Text style={styles.reloadText}>↻</Text>
        </Pressable>
      </View>

      {loading ? (
        <View style={styles.stateCard}>
          <ActivityIndicator color={colors.navy} />
          <Text style={styles.stateBody}>Controllo i dispositivi…</Text>
        </View>
      ) : (
        <>
          <View style={[styles.masterCard, enabled && styles.masterCardEnabled]}>
            <View style={styles.masterTop}>
              <View
                style={[
                  styles.masterSymbol,
                  enabled && styles.masterSymbolEnabled,
                ]}
              >
                <Text
                  style={[
                    styles.masterSymbolText,
                    enabled && styles.masterSymbolTextEnabled,
                  ]}
                >
                  {enabled ? '✓' : '○'}
                </Text>
              </View>
              <View style={styles.masterCopy}>
                <Text style={styles.masterEyebrow}>NOTIFICHE PUSH</Text>
                <Text style={styles.masterTitle}>
                  {enabled ? 'Avvisi attivi' : 'Avvisi disattivati'}
                </Text>
              </View>
              {enabled ? (
                <View style={styles.activePill}>
                  <Text style={styles.activePillText}>ATTIVE</Text>
                </View>
              ) : null}
            </View>
            <Text style={styles.masterBody}>
              {enabled
                ? `${preferences.activeDeviceCount} ${
                    preferences.activeDeviceCount === 1
                      ? 'dispositivo collegato'
                      : 'dispositivi collegati'
                  }. Toccare un avviso apre direttamente l’azione corretta.`
                : 'Abilita gli avvisi soltanto se vuoi riceverli anche quando LEGHEVO è chiusa.'}
            </Text>
            <Pressable
              disabled={busy}
              onPress={() =>
                void (enabled ? onDisable() : onEnable())
              }
              style={[
                styles.masterButton,
                enabled && styles.masterButtonDisable,
                busy && styles.disabled,
              ]}
            >
              <Text
                style={[
                  styles.masterButtonText,
                  enabled && styles.masterButtonDisableText,
                ]}
              >
                {busy
                  ? 'AGGIORNAMENTO…'
                  : enabled
                    ? 'DISATTIVA PUSH'
                    : 'ABILITA PUSH'}
              </Text>
            </Pressable>
          </View>

          {preferences.protected ? (
            <View style={styles.protectionCard}>
              <View style={styles.protectionTop}>
                <Text style={styles.protectionLabel}>GESTIONE PROTETTA</Text>
                <Text style={styles.protectionRevision}>
                  REVISIONE v{preferences.revision}
                </Text>
              </View>
              <Text style={styles.protectionBody}>
                Preferenze e dispositivi sono sincronizzati con controllo
                anti-doppio tocco e registro certificato. Operazioni registrate:{' '}
                {preferences.certifiedActionCount}.
              </Text>
            </View>
          ) : null}

          {permission === 'denied' ? (
            <Pressable
              onPress={() => void Linking.openSettings()}
              style={styles.permissionCard}
            >
              <View>
                <Text style={styles.permissionTitle}>
                  Permesso bloccato dal telefono
                </Text>
                <Text style={styles.permissionBody}>
                  Apri le impostazioni di sistema per riabilitare LEGHEVO.
                </Text>
              </View>
              <Text style={styles.permissionArrow}>→</Text>
            </Pressable>
          ) : null}

          {isDemo ? (
            <View style={styles.demoCard}>
              <Text style={styles.demoTitle}>Modalità demo</Text>
              <Text style={styles.demoBody}>
                Puoi provare le categorie, ma nessun dispositivo viene
                registrato.
              </Text>
            </View>
          ) : null}

          {error ? (
            <View style={styles.errorCard}>
              <Text style={styles.errorTitle}>Avvisi non aggiornati</Text>
              <Text style={styles.errorBody}>{error}</Text>
            </View>
          ) : null}

          <Text style={styles.sectionTitle}>Cosa vuoi ricevere</Text>
          <View style={styles.categories}>
            {categories.map((category) => (
              <PreferenceRow
                key={category.key}
                body={category.body}
                disabled={busy}
                enabled={preferences[category.key]}
                onToggle={(next) => void onUpdate(category.key, next)}
                symbol={category.symbol}
                title={category.title}
              />
            ))}
          </View>

          <View style={styles.infoCard}>
            <Text style={styles.infoTitle}>Sempre anche nell’app</Text>
            <Text style={styles.infoBody}>
              Disattivare le push non cancella il Centro notifiche: gli
              aggiornamenti restano consultabili quando apri LEGHEVO.
            </Text>
          </View>
        </>
      )}
    </ScrollView>
  );
}

function PreferenceRow({
  symbol,
  title,
  body,
  enabled,
  disabled,
  onToggle,
}: {
  symbol: string;
  title: string;
  body: string;
  enabled: boolean;
  disabled: boolean;
  onToggle: (enabled: boolean) => void;
}) {
  return (
    <Pressable
      accessibilityRole="switch"
      accessibilityState={{ checked: enabled, disabled }}
      disabled={disabled}
      onPress={() => onToggle(!enabled)}
      style={styles.categoryRow}
    >
      <View style={[styles.categorySymbol, enabled && styles.categorySymbolOn]}>
        <Text
          style={[
            styles.categorySymbolText,
            enabled && styles.categorySymbolTextOn,
          ]}
        >
          {symbol}
        </Text>
      </View>
      <View style={styles.categoryCopy}>
        <Text style={styles.categoryTitle}>{title}</Text>
        <Text style={styles.categoryBody}>{body}</Text>
      </View>
      <View style={[styles.switchTrack, enabled && styles.switchTrackOn]}>
        <View style={[styles.switchThumb, enabled && styles.switchThumbOn]} />
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
    paddingBottom: 44,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 22,
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
    letterSpacing: 0.55,
  },
  title: {
    color: colors.navy,
    fontSize: 28,
    fontWeight: '900',
    marginTop: 3,
  },
  reloadButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  reloadText: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '800',
  },
  stateCard: {
    minHeight: 150,
    borderRadius: radius.lg,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
    backgroundColor: colors.white,
  },
  stateBody: {
    color: colors.muted,
    fontSize: 13,
  },
  masterCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.white,
  },
  masterCardEnabled: {
    backgroundColor: colors.navy,
  },
  masterTop: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  masterSymbol: {
    width: 46,
    height: 46,
    borderRadius: 23,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvas,
  },
  masterSymbolEnabled: {
    backgroundColor: colors.lime,
  },
  masterSymbolText: {
    color: colors.muted,
    fontSize: 20,
    fontWeight: '900',
  },
  masterSymbolTextEnabled: {
    color: colors.navy,
  },
  masterCopy: {
    flex: 1,
    marginLeft: 13,
  },
  masterEyebrow: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  masterTitle: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
    marginTop: 3,
  },
  activePill: {
    borderRadius: 12,
    paddingHorizontal: 10,
    paddingVertical: 6,
    backgroundColor: colors.lime,
  },
  activePillText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  masterBody: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 16,
  },
  masterButton: {
    height: 48,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
    marginTop: 18,
  },
  masterButtonDisable: {
    borderWidth: 1,
    borderColor: '#324054',
    backgroundColor: 'transparent',
  },
  masterButtonText: {
    color: colors.lime,
    fontSize: 12,
    fontWeight: '900',
  },
  masterButtonDisableText: {
    color: colors.warmWhite,
  },
  disabled: {
    opacity: 0.55,
  },
  protectionCard: {
    borderRadius: radius.lg,
    padding: 17,
    marginTop: 12,
    backgroundColor: colors.limeSoft,
    borderWidth: 1,
    borderColor: '#D8F1A5',
  },
  protectionTop: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  protectionLabel: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  protectionRevision: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  protectionBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 7,
  },
  permissionCard: {
    borderRadius: radius.lg,
    padding: 17,
    marginTop: 12,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#FFF4DD',
  },
  permissionTitle: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  permissionBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 16,
    marginTop: 3,
  },
  permissionArrow: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '900',
    marginLeft: 'auto',
  },
  demoCard: {
    borderRadius: radius.lg,
    padding: 17,
    marginTop: 12,
    backgroundColor: colors.limeSoft,
  },
  demoTitle: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  demoBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 4,
  },
  errorCard: {
    borderRadius: radius.lg,
    padding: 17,
    marginTop: 12,
    backgroundColor: '#FFF0EC',
  },
  errorTitle: {
    color: '#8B2E20',
    fontSize: 14,
    fontWeight: '900',
  },
  errorBody: {
    color: '#8B2E20',
    fontSize: 12,
    lineHeight: 18,
    marginTop: 4,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 19,
    fontWeight: '900',
    marginTop: 24,
    marginBottom: 10,
  },
  categories: {
    borderRadius: radius.lg,
    paddingHorizontal: 16,
    backgroundColor: colors.white,
  },
  categoryRow: {
    minHeight: 84,
    flexDirection: 'row',
    alignItems: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#DFE4DC',
  },
  categorySymbol: {
    width: 38,
    height: 38,
    borderRadius: 19,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvas,
  },
  categorySymbolOn: {
    backgroundColor: colors.limeSoft,
  },
  categorySymbolText: {
    color: colors.muted,
    fontSize: 12,
    fontWeight: '900',
  },
  categorySymbolTextOn: {
    color: colors.navy,
  },
  categoryCopy: {
    flex: 1,
    marginHorizontal: 12,
  },
  categoryTitle: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  categoryBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 16,
    marginTop: 3,
  },
  switchTrack: {
    width: 42,
    height: 24,
    borderRadius: 12,
    padding: 3,
    backgroundColor: '#D8DDD6',
  },
  switchTrackOn: {
    backgroundColor: colors.navy,
  },
  switchThumb: {
    width: 18,
    height: 18,
    borderRadius: 9,
    backgroundColor: colors.white,
  },
  switchThumbOn: {
    alignSelf: 'flex-end',
    backgroundColor: colors.lime,
  },
  infoCard: {
    borderRadius: radius.lg,
    padding: 18,
    marginTop: 16,
    backgroundColor: colors.white,
  },
  infoTitle: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  infoBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 5,
  },
});
