import { useCallback, useState } from 'react';
import { ActivityIndicator, SafeAreaView, StyleSheet, View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { BottomNav } from './src/components/BottomNav';
import { AboutScreen } from './src/screens/AboutScreen';
import { AccountScreen } from './src/screens/AccountScreen';
import { AuctionScreen } from './src/screens/AuctionScreen';
import { CalendarScreen } from './src/screens/CalendarScreen';
import { HomeScreen } from './src/screens/HomeScreen';
import { LeagueCupScreen } from './src/screens/LeagueCupScreen';
import { LeagueScreen } from './src/screens/LeagueScreen';
import { LeagueHistoryScreen } from './src/screens/LeagueHistoryScreen';
import { LeagueManagementScreen } from './src/screens/LeagueManagementScreen';
import { LeagueOperationsScreen } from './src/screens/LeagueOperationsScreen';
import { LeaguePlayoffsScreen } from './src/screens/LeaguePlayoffsScreen';
import { LeagueRulebookScreen } from './src/screens/LeagueRulebookScreen';
import { LeagueSettingsScreen } from './src/screens/LeagueSettingsScreen';
import { LeagueSetupScreen } from './src/screens/LeagueSetupScreen';
import { LeagueSuperCupScreen } from './src/screens/LeagueSuperCupScreen';
import { LiveScreen } from './src/screens/LiveScreen';
import { LoginScreen } from './src/screens/LoginScreen';
import { LineupScreen } from './src/screens/LineupScreen';
import { MarketScreen } from './src/screens/MarketScreen';
import { MatchupScreen } from './src/screens/MatchupScreen';
import { NotificationsScreen } from './src/screens/NotificationsScreen';
import { NotificationPreferencesScreen } from './src/screens/NotificationPreferencesScreen';
import { PasswordRecoveryScreen } from './src/screens/PasswordRecoveryScreen';
import { PremiumScreen } from './src/screens/PremiumScreen';
import { ReleaseCompatibilityScreen } from './src/screens/ReleaseCompatibilityScreen';
import { PlayersScreen } from './src/screens/PlayersScreen';
import { PostponementsScreen } from './src/screens/PostponementsScreen';
import { PrivacyOnboardingScreen } from './src/screens/PrivacyOnboardingScreen';
import { PrivacyScreen } from './src/screens/PrivacyScreen';
import { ProfileScreen } from './src/screens/ProfileScreen';
import { PublicRosterScreen } from './src/screens/PublicRosterScreen';
import { RosterScreen } from './src/screens/RosterScreen';
import { StandingsScreen } from './src/screens/StandingsScreen';
import { SupportScreen } from './src/screens/SupportScreen';
import { TeamMembershipScreen } from './src/screens/TeamMembershipScreen';
import { useAuth } from './src/hooks/useAuth';
import { useCommercialEntitlement } from './src/hooks/useCommercialEntitlement';
import { useLeagues } from './src/hooks/useLeagues';
import { useLiveMatchCenter } from './src/hooks/useLiveMatchCenter';
import { useNotifications } from './src/hooks/useNotifications';
import { usePushNotifications } from './src/hooks/usePushNotifications';
import { useReleaseCompatibility } from './src/hooks/useReleaseCompatibility';
import { colors } from './src/theme';
import type {
  AppScreen,
  MainTab,
  PublicTeamSelection,
} from './src/types';

export default function App() {
  const releaseCompatibility = useReleaseCompatibility();

  if (releaseCompatibility.loading) {
    return (
      <View style={styles.loadingRoot}>
        <StatusBar style="light" />
        <ActivityIndicator color={colors.lime} size="large" />
      </View>
    );
  }

  if (
    releaseCompatibility.enforced &&
    !releaseCompatibility.compatible
  ) {
    return (
      <View style={styles.darkRoot}>
        <StatusBar style="light" />
        <ReleaseCompatibilityScreen
          compatibility={releaseCompatibility}
          loading={releaseCompatibility.loading}
          onRetry={releaseCompatibility.refresh}
        />
      </View>
    );
  }

  return <LeghevoRuntime />;
}

function LeghevoRuntime() {
  const [screen, setScreen] = useState<AppScreen>('home');
  const [selectedLeagueId, setSelectedLeagueId] = useState<string | null>(null);
  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);
  const [selectedPublicTeam, setSelectedPublicTeam] =
    useState<PublicTeamSelection | null>(null);
  const [selectedPublicTeamReturnScreen, setSelectedPublicTeamReturnScreen] =
    useState<'league' | 'standings'>('league');
  const [selectedPlayerReturnScreen, setSelectedPlayerReturnScreen] = useState<
    'roster' | 'market' | 'publicRoster'
  >('roster');
  const auth = useAuth();
  const commercial = useCommercialEntitlement(
    auth.profile.userId,
    auth.profile.isDemo,
  );
  const leagueState = useLeagues(auth.profile.userId, auth.profile.isDemo);
  const notificationState = useNotifications(
    auth.profile.userId,
    auth.profile.isDemo,
  );
  const openPushTarget = useCallback(
    (target: {
      notificationId: string | null;
      leagueId: string | null;
      actionScreen: AppScreen | null;
    }) => {
      if (target.notificationId) {
        void notificationState.markRead(target.notificationId);
      }
      if (target.leagueId) {
        setSelectedLeagueId(target.leagueId);
      }
      setScreen(target.actionScreen ?? 'notifications');
    },
    [notificationState.markRead],
  );
  const pushState = usePushNotifications(
    auth.profile.userId,
    auth.profile.isDemo,
    openPushTarget,
  );
  const selectedLeague =
    leagueState.leagues.find((league) => league.id === selectedLeagueId) ??
    leagueState.leagues[0] ??
    null;
  const homeLeague = leagueState.leagues[0] ?? null;
  const homeMatchState = useLiveMatchCenter(
    auth.authenticated ? homeLeague : null,
  );

  const navigate = (next: AppScreen) => {
    if (next === 'players') {
      setSelectedPlayerId(null);
    }
    setScreen(next);
  };
  const navigateTab = (tab: MainTab) => {
    if (tab === 'league' && leagueState.leagues.length === 0) {
      setScreen('leagueSetup');
      return;
    }
    setScreen(tab);
  };
  const openLeague = (leagueId: string) => {
    setSelectedLeagueId(leagueId);
    setScreen('league');
  };
  const openLineup = (leagueId: string) => {
    setSelectedLeagueId(leagueId);
    setScreen('lineup');
  };
  const openLive = (leagueId: string) => {
    setSelectedLeagueId(leagueId);
    setScreen('live');
  };
  const openPlayer = (
    playerId: string,
    returnScreen: 'roster' | 'market' | 'publicRoster',
  ) => {
    setSelectedPlayerId(playerId);
    setSelectedPlayerReturnScreen(returnScreen);
    setScreen('players');
  };


  const openTeam = (
    team: PublicTeamSelection,
    isCurrent: boolean,
    returnScreen: 'league' | 'standings',
  ) => {
    if (isCurrent || team.id === selectedLeague?.team?.id) {
      setScreen('roster');
      return;
    }
    setSelectedPublicTeam(team);
    setSelectedPublicTeamReturnScreen(returnScreen);
    setScreen('publicRoster');
  };

  if (auth.loading) {
    return (
      <View style={styles.loadingRoot}>
        <StatusBar style="light" />
        <ActivityIndicator color={colors.lime} size="large" />
      </View>
    );
  }

  if (auth.passwordRecovery) {
    return (
      <View style={styles.darkRoot}>
        <StatusBar style="light" />
        <PasswordRecoveryScreen
          error={auth.recoveryError}
          onCancel={auth.cancelPasswordRecovery}
          onComplete={auth.completePasswordRecovery}
        />
      </View>
    );
  }

  if (!auth.authenticated) {
    return (
      <View style={styles.darkRoot}>
        <StatusBar style="light" />
        <LoginScreen
          backendConfigured={auth.backendConfigured}
          onDemoLogin={auth.demoLogin}
          onResetPassword={auth.resetPassword}
          onSignIn={auth.signIn}
          onSignUp={auth.signUp}
        />
      </View>
    );
  }

  if (auth.privacyRequired) {
    return (
      <View style={styles.darkRoot}>
        <StatusBar style="light" />
        <PrivacyOnboardingScreen
          error={auth.privacyError}
          onAccept={auth.updatePrivacyChoices}
          onLogout={auth.logout}
        />
      </View>
    );
  }

  const isDark = screen === 'auction';

  return (
    <SafeAreaView style={[styles.root, isDark && styles.darkRoot]}>
      <StatusBar style={isDark ? 'light' : 'dark'} />
      <View style={styles.screen}>
        {screen === 'home' && (
          <HomeScreen
            displayName={auth.profile.displayName}
            error={leagueState.error}
            leagues={leagueState.leagues}
            loading={leagueState.loading}
            match={homeMatchState.match}
            matchError={homeMatchState.error}
            matchLoading={homeMatchState.loading}
            unreadCount={notificationState.unreadCount}
            onNavigate={navigate}
            onOpenLeague={openLeague}
            onOpenLineup={openLineup}
            onOpenLive={openLive}
          />
        )}
        {screen === 'about' && (
          <AboutScreen
            onBack={() => setScreen('profile')}
            onPrivacy={() => setScreen('privacy')}
          />
        )}
        {screen === 'account' && (
          <AccountScreen
            displayName={auth.profile.displayName}
            email={auth.profile.email}
            emailVerified={auth.profile.emailVerified}
            isDemo={auth.profile.isDemo}
            userId={auth.profile.userId}
            onBack={() => setScreen('profile')}
            onDeleteAccount={async () => {
              const outcome = await auth.deleteAccount();
              if (!outcome.error) {
                setScreen('home');
                setSelectedLeagueId(null);
              }
              return outcome;
            }}
            onUpdateDisplayName={auth.updateDisplayName}
            onUpdatePassword={auth.updatePassword}
          />
        )}
        {screen === 'league' && (
          <LeagueScreen
            currentUserId={auth.profile.userId}
            league={selectedLeague}
            onNavigate={navigate}
            onOpenTeam={(team, isCurrent) =>
              openTeam(team, isCurrent, 'league')
            }
          />
        )}
        {screen === 'leagueSetup' && (
          <LeagueSetupScreen
            commercial={commercial.entitlement}
            onClose={() => setScreen('home')}
            onCreate={leagueState.create}
            onJoin={leagueState.join}
            onOpenPremium={() => setScreen('premium')}
            onPreviewInvite={leagueState.previewInvite}
            onSuccess={(leagueId) => {
              setSelectedLeagueId(leagueId);
              void commercial.refresh(true);
              setScreen('league');
            }}
          />
        )}
        {screen === 'leagueHistory' && (
          <LeagueHistoryScreen
            league={selectedLeague}
            onBack={() => setScreen('league')}
            onOpenSeason={(leagueId) => {
              setSelectedLeagueId(leagueId);
              setScreen('league');
            }}
          />
        )}
        {screen === 'leagueCup' && (
          <LeagueCupScreen
            league={selectedLeague}
            onBack={() => setScreen('league')}
          />
        )}
        {screen === 'leaguePlayoffs' && (
          <LeaguePlayoffsScreen
            league={selectedLeague}
            onBack={() => setScreen('league')}
            onOpenLineup={() => setScreen('lineup')}
          />
        )}
        {screen === 'leagueSuperCup' && (
          <LeagueSuperCupScreen
            league={selectedLeague}
            onBack={() => setScreen('league')}
          />
        )}
        {screen === 'leagueRulebook' && (
          <LeagueRulebookScreen
            league={selectedLeague}
            onNavigate={navigate}
          />
        )}
        {screen === 'leagueSettings' && (
          <LeagueSettingsScreen
            league={selectedLeague}
            onLeagueChanged={() => void leagueState.refresh()}
            onNavigate={navigate}
          />
        )}
        {screen === 'leagueManagement' && (
          <LeagueManagementScreen
            currentUserId={auth.profile.userId}
            league={selectedLeague}
            onLeagueChanged={() => void leagueState.refresh()}
            onSeasonRenewed={async (leagueId) => {
              setSelectedLeagueId(leagueId);
              await leagueState.refresh(true);
              setScreen('leagueManagement');
            }}
            onNavigate={navigate}
          />
        )}
        {screen === 'leagueOperations' && (
          <LeagueOperationsScreen
            league={selectedLeague}
            onBack={() => setScreen('league')}
            onNavigate={navigate}
          />
        )}
        {screen === 'calendar' && (
          <CalendarScreen
            currentUserId={auth.profile.userId}
            league={selectedLeague}
            onBack={() => setScreen('league')}
          />
        )}
        {screen === 'auction' && (
          <AuctionScreen
            currentUserId={auth.profile.userId}
            league={selectedLeague}
            onNavigate={navigate}
          />
        )}
        {screen === 'roster' && (
          <RosterScreen
            league={selectedLeague}
            onNavigate={navigate}
            onOpenPlayer={(playerId) => openPlayer(playerId, 'roster')}
          />
        )}
        {screen === 'publicRoster' && (
          <PublicRosterScreen
            league={selectedLeague}
            onBack={() => setScreen(selectedPublicTeamReturnScreen)}
            onOpenPlayer={(playerId) => openPlayer(playerId, 'publicRoster')}
            team={selectedPublicTeam}
          />
        )}
        {screen === 'lineup' && (
          <LineupScreen league={selectedLeague} onNavigate={navigate} />
        )}
        {screen === 'standings' && (
          <StandingsScreen
            league={selectedLeague}
            onNavigate={navigate}
            onOpenTeam={(team, isCurrent) =>
              openTeam(team, isCurrent, 'standings')
            }
          />
        )}
        {screen === 'teamMembership' && (
          <TeamMembershipScreen
            currentUserId={auth.profile.userId}
            league={selectedLeague}
            onLeagueChanged={() => leagueState.refresh()}
            onLeagueLeft={async () => {
              setScreen('home');
              setSelectedLeagueId(null);
              await leagueState.refresh();
            }}
            onNavigate={navigate}
          />
        )}
        {screen === 'market' && (
          <MarketScreen
            league={selectedLeague}
            onLeagueChanged={() => void leagueState.refresh()}
            onNavigate={navigate}
            onOpenPlayer={(playerId) => openPlayer(playerId, 'market')}
          />
        )}
        {screen === 'matchup' && (
          <MatchupScreen league={selectedLeague} onNavigate={navigate} />
        )}
        {screen === 'live' && (
          <LiveScreen league={selectedLeague} onNavigate={navigate} />
        )}
        {screen === 'notifications' && (
          <NotificationsScreen
            certifiedActionCount={notificationState.certifiedActionCount}
            error={notificationState.error}
            lastCertifiedAt={notificationState.lastCertifiedAt}
            loading={notificationState.loading}
            notifications={notificationState.notifications}
            protected={notificationState.protected}
            onBack={() => setScreen('home')}
            onMarkAllRead={notificationState.markAllRead}
            onOpen={async (notification) => {
              await notificationState.markRead(notification.id);
              if (notification.leagueId) {
                setSelectedLeagueId(notification.leagueId);
              }
              if (notification.actionScreen) {
                setScreen(notification.actionScreen);
              }
            }}
            onRefresh={notificationState.refresh}
            unreadCount={notificationState.unreadCount}
          />
        )}
        {screen === 'notificationPreferences' && (
          <NotificationPreferencesScreen
            busy={pushState.busy}
            error={pushState.error}
            isDemo={auth.profile.isDemo}
            loading={pushState.loading}
            permission={pushState.permission}
            preferences={pushState.preferences}
            onBack={() => setScreen('profile')}
            onDisable={pushState.disable}
            onEnable={pushState.enable}
            onRefresh={pushState.refresh}
            onUpdate={pushState.update}
          />
        )}
        {screen === 'players' && (
          <PlayersScreen
            initialPlayerId={selectedPlayerId}
            league={selectedLeague}
            onCloseInitialPlayer={() => {
              setSelectedPlayerId(null);
              setScreen(selectedPlayerReturnScreen);
            }}
            onNavigate={navigate}
          />
        )}
        {screen === 'postponements' && (
          <PostponementsScreen
            league={selectedLeague}
            onBack={() => setScreen('league')}
          />
        )}
        {screen === 'premium' && (
          <PremiumScreen
            entitlement={commercial.entitlement}
            error={commercial.error}
            isDemo={auth.profile.isDemo}
            onBack={() => setScreen('profile')}
            onPurchase={commercial.purchase}
            onRestore={commercial.restore}
          />
        )}
        {screen === 'privacy' && (
          <PrivacyScreen
            email={auth.profile.email}
            isDemo={auth.profile.isDemo}
            preferences={auth.privacy}
            userId={auth.profile.userId ?? ''}
            onBack={() => setScreen('profile')}
            onDeleteAccount={() => setScreen('account')}
            onExportData={auth.exportPersonalData}
          />
        )}
        {screen === 'support' && (
          <SupportScreen
            isDemo={auth.profile.isDemo}
            leagues={leagueState.leagues}
            onBack={() => setScreen('profile')}
            userId={auth.profile.userId}
          />
        )}
        {screen === 'profile' && (
          <ProfileScreen
            commercial={commercial.entitlement}
            displayName={auth.profile.displayName}
            email={auth.profile.email}
            isDemo={auth.profile.isDemo}
            onAccount={() => setScreen('account')}
            onAbout={() => setScreen('about')}
            onNotifications={() => setScreen('notifications')}
            onPreferences={() => setScreen('notificationPreferences')}
            onPremium={() => setScreen('premium')}
            onPrivacy={() => setScreen('privacy')}
            onSupport={() => setScreen('support')}
            onLogout={async () => {
              setScreen('home');
              setSelectedLeagueId(null);
              await auth.logout();
            }}
            unreadCount={notificationState.unreadCount}
          />
        )}
      </View>

      {screen !== 'about' &&
        screen !== 'account' &&
        screen !== 'auction' &&
        screen !== 'calendar' &&
        screen !== 'leagueCup' &&
        screen !== 'leaguePlayoffs' &&
        screen !== 'leagueSuperCup' &&
        screen !== 'leagueHistory' &&
        screen !== 'leagueManagement' &&
        screen !== 'leagueOperations' &&
        screen !== 'leagueRulebook' &&
        screen !== 'leagueSettings' &&
        screen !== 'leagueSetup' &&
        screen !== 'roster' &&
        screen !== 'publicRoster' &&
        screen !== 'lineup' &&
        screen !== 'standings' &&
        screen !== 'teamMembership' &&
        screen !== 'market' &&
        screen !== 'matchup' &&
        screen !== 'notifications' &&
        screen !== 'notificationPreferences' &&
        screen !== 'players' &&
        screen !== 'postponements' &&
        screen !== 'premium' &&
        screen !== 'privacy' &&
        screen !== 'support' && (
        <BottomNav
          active={screen === 'league' ? 'league' : screen}
          onNavigate={navigateTab}
        />
        )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  darkRoot: {
    flex: 1,
    backgroundColor: colors.navy,
  },
  loadingRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  screen: {
    flex: 1,
  },
});
