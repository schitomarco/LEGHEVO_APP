import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import type { CommercialEntitlement } from '../services/subscriptionService';
import { colors, radius } from '../theme';

type Props = {
  canAccessBusinessDashboard: boolean;
  commercial: CommercialEntitlement;
  displayName: string;
  email: string;
  isDemo: boolean;
  unreadCount: number;
  onAccount: () => void;
  onAbout: () => void;
  onBusinessDashboard: () => void;
  onNotifications: () => void;
  onPreferences: () => void;
  onPremium: () => void;
  onPrivacy: () => void;
  onSupport: () => void;
  onLogout: () => void | Promise<void>;
};

export function ProfileScreen({
  canAccessBusinessDashboard,
  commercial,
  displayName,
  email,
  isDemo,
  unreadCount,
  onAccount,
  onAbout,
  onBusinessDashboard,
  onNotifications,
  onPreferences,
  onPremium,
  onPrivacy,
  onSupport,
  onLogout,
}: Props) {
  const initials = displayName
    .split(' ')
    .map((part) => part[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
  const menuItems = [
    {
      label: 'Account e sicurezza',
      detail: '',
      onPress: onAccount,
    },
    ...(canAccessBusinessDashboard
      ? [
          {
            label: '💰 Ricavi · Business Dashboard',
            detail: 'RISERVATA',
            onPress: onBusinessDashboard,
          },
        ]
      : []),
    {
      label: 'Notifiche',
      detail: unreadCount > 0 ? String(unreadCount) : '',
      onPress: onNotifications,
    },
    { label: 'Preferenze', detail: '', onPress: onPreferences },
    { label: 'Privacy', detail: '', onPress: onPrivacy },
    { label: 'Assistenza', detail: '', onPress: onSupport },
    { label: 'Informazioni su LEGHEVO', detail: '', onPress: onAbout },
  ];

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <Text style={styles.eyebrow}>IL TUO SPOGLIATOIO</Text>
      <Text style={styles.title}>Profilo</Text>

      <View style={styles.profileCard}>
        <View style={styles.avatar}>
          <Text style={styles.avatarText}>{initials || 'LV'}</Text>
        </View>
        <View>
          <Text style={styles.name}>{displayName}</Text>
          <Text style={styles.email}>{email}</Text>
          {isDemo && <Text style={styles.demoLabel}>PROFILO DEMO</Text>}
        </View>
      </View>

      <View style={styles.premiumCard}>
        <View style={styles.premiumPill}>
          <Text style={styles.premiumPillText}>
            {commercial.isPremium ? 'PREMIUM ATTIVO' : 'LEGHEVO PREMIUM'}
          </Text>
        </View>
        <Text style={styles.premiumTitle}>
          {commercial.isPremium
            ? 'Nessuna pubblicità. Nessun limite inutile.'
            : 'Più leghe. Più partecipanti.'}
        </Text>
        <Text style={styles.premiumBody}>
          {commercial.isPremium
            ? 'Il tuo account può creare leghe fino a 20 partecipanti.'
            : `Da ${commercial.annualPriceLabel}: più leghe e niente pubblicità.`}
        </Text>
        <Pressable onPress={onPremium} style={styles.premiumButton}>
          <Text style={styles.premiumButtonText}>
            {commercial.isPremium ? 'Gestisci Premium' : 'Scopri Premium'}
          </Text>
        </Pressable>
      </View>

      <View style={styles.menu}>
        {menuItems.map((item) => (
          <Pressable
            key={item.label}
            onPress={item.onPress}
            style={styles.menuItem}
          >
            <Text style={styles.menuText}>{item.label}</Text>
            {item.detail ? (
              <View style={styles.menuBadge}>
                <Text style={styles.menuBadgeText}>{item.detail}</Text>
              </View>
            ) : null}
            <Text style={styles.menuArrow}>›</Text>
          </Pressable>
        ))}
      </View>

      <Pressable onPress={onLogout} style={styles.logoutButton}>
        <Text style={styles.logoutText}>Esci dal profilo</Text>
      </Pressable>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    padding: 20,
    paddingBottom: 36,
  },
  eyebrow: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.6,
  },
  title: {
    color: colors.navy,
    fontSize: 30,
    fontWeight: '900',
    marginTop: 5,
  },
  profileCard: {
    borderRadius: radius.lg,
    backgroundColor: colors.white,
    padding: 18,
    marginTop: 22,
    flexDirection: 'row',
    alignItems: 'center',
  },
  avatar: {
    width: 58,
    height: 58,
    borderRadius: 29,
    backgroundColor: colors.navy,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 14,
  },
  avatarText: {
    color: colors.lime,
    fontSize: 16,
    fontWeight: '900',
  },
  name: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  email: {
    color: colors.muted,
    fontSize: 13,
    marginTop: 4,
  },
  demoLabel: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    marginTop: 6,
  },
  premiumCard: {
    borderRadius: radius.xl,
    backgroundColor: colors.navy,
    padding: 22,
    marginTop: 18,
  },
  premiumPill: {
    alignSelf: 'flex-start',
    height: 27,
    borderRadius: 14,
    backgroundColor: colors.lime,
    paddingHorizontal: 12,
    justifyContent: 'center',
  },
  premiumPillText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  premiumTitle: {
    color: colors.warmWhite,
    fontSize: 22,
    fontWeight: '900',
    marginTop: 18,
  },
  premiumBody: {
    color: colors.mutedLight,
    fontSize: 14,
    lineHeight: 20,
    marginTop: 8,
  },
  premiumButton: {
    height: 48,
    borderRadius: radius.md,
    backgroundColor: colors.lime,
    marginTop: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  premiumButtonText: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  menu: {
    borderRadius: radius.lg,
    backgroundColor: colors.white,
    paddingHorizontal: 16,
    marginTop: 18,
  },
  menuItem: {
    minHeight: 56,
    flexDirection: 'row',
    alignItems: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#DFE4DC',
  },
  menuText: {
    flex: 1,
    color: colors.navy,
    fontSize: 14,
    fontWeight: '700',
  },
  menuBadge: {
    minWidth: 22,
    height: 22,
    borderRadius: 11,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginRight: 8,
  },
  menuBadgeText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  menuArrow: {
    color: colors.muted,
    fontSize: 25,
  },
  logoutButton: {
    height: 52,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: '#D8DDD6',
    marginTop: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  logoutText: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '800',
  },
});
