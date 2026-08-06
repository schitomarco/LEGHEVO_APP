import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors } from '../theme';
import type { MainTab } from '../types';

type Props = {
  active: MainTab;
  onNavigate: (tab: MainTab) => void;
};

const tabs: { key: MainTab; label: string; symbol: string }[] = [
  { key: 'home', label: 'HOME', symbol: '⌂' },
  { key: 'league', label: 'LEGHE', symbol: '◇' },
  { key: 'live', label: 'LIVE', symbol: '◉' },
  { key: 'profile', label: 'PROFILO', symbol: '○' },
];

export function BottomNav({ active, onNavigate }: Props) {
  return (
    <View style={styles.container}>
      {tabs.map((tab) => {
        const selected = active === tab.key;
        return (
          <Pressable
            key={tab.key}
            accessibilityRole="button"
            accessibilityLabel={tab.label}
            onPress={() => onNavigate(tab.key)}
            style={styles.item}
          >
            <Text style={[styles.symbol, selected && styles.selectedText]}>
              {tab.symbol}
            </Text>
            <Text style={[styles.label, selected && styles.selectedText]}>
              {tab.label}
            </Text>
            <View style={[styles.dot, selected && styles.dotSelected]} />
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    height: 78,
    flexDirection: 'row',
    backgroundColor: colors.white,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: '#DFE4DC',
  },
  item: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 2,
  },
  symbol: {
    color: colors.muted,
    fontSize: 22,
    lineHeight: 24,
  },
  label: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '800',
    letterSpacing: 0.4,
  },
  selectedText: {
    color: colors.navy,
  },
  dot: {
    width: 4,
    height: 4,
    marginTop: 2,
    borderRadius: 2,
    backgroundColor: 'transparent',
  },
  dotSelected: {
    backgroundColor: colors.lime,
  },
});
