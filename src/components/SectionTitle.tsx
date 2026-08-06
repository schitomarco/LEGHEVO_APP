import { StyleSheet, Text, View } from 'react-native';
import { colors } from '../theme';

type Props = {
  eyebrow?: string;
  title: string;
  dark?: boolean;
  action?: string;
};

export function SectionTitle({ eyebrow, title, dark, action }: Props) {
  return (
    <View style={styles.row}>
      <View>
        {eyebrow ? (
          <Text style={[styles.eyebrow, dark && styles.darkMuted]}>{eyebrow}</Text>
        ) : null}
        <Text style={[styles.title, dark && styles.darkTitle]}>{title}</Text>
      </View>
      {action ? (
        <Text style={[styles.action, dark && styles.darkAction]}>{action}</Text>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
  },
  eyebrow: {
    color: colors.muted,
    fontSize: 14,
    marginBottom: 6,
  },
  title: {
    color: colors.navy,
    fontSize: 30,
    lineHeight: 34,
    fontWeight: '900',
  },
  action: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '800',
  },
  darkMuted: {
    color: colors.mutedLight,
  },
  darkTitle: {
    color: colors.warmWhite,
  },
  darkAction: {
    color: colors.lime,
  },
});
