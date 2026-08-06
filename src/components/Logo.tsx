import { StyleSheet, Text, View } from 'react-native';
import { colors } from '../theme';

type Props = {
  size?: number;
  showWordmark?: boolean;
  inverse?: boolean;
};

export function Logo({ size = 132, showWordmark = true, inverse = true }: Props) {
  const scale = size / 132;

  return (
    <View style={styles.wrapper}>
      <View
        style={[
          styles.icon,
          {
            width: size,
            height: size,
            borderRadius: size * 0.24,
            backgroundColor: inverse ? colors.navy : colors.warmWhite,
          },
        ]}
      >
        <View
          style={[
            styles.lVertical,
            {
              width: 14 * scale,
              height: 78 * scale,
              left: 32 * scale,
              top: 26 * scale,
              borderRadius: 7 * scale,
              backgroundColor: inverse ? colors.warmWhite : colors.navy,
            },
          ]}
        />
        <View
          style={[
            styles.lHorizontal,
            {
              width: 76 * scale,
              height: 14 * scale,
              left: 32 * scale,
              top: 91 * scale,
              borderRadius: 7 * scale,
              backgroundColor: inverse ? colors.warmWhite : colors.navy,
            },
          ]}
        />
        <View
          style={[
            styles.centerLine,
            {
              width: 6 * scale,
              height: 80 * scale,
              left: 63 * scale,
              top: 24 * scale,
              borderRadius: 3 * scale,
            },
          ]}
        />
        <View
          style={[
            styles.centerCircle,
            {
              width: 34 * scale,
              height: 34 * scale,
              left: 49 * scale,
              top: 51 * scale,
              borderRadius: 17 * scale,
              borderWidth: 6 * scale,
              backgroundColor: inverse ? colors.navy : colors.warmWhite,
            },
          ]}
        >
          <View
            style={{
              width: 5 * scale,
              height: 5 * scale,
              borderRadius: 3 * scale,
              backgroundColor: colors.lime,
            }}
          />
        </View>
      </View>

      {showWordmark && (
        <View style={styles.wordmarkWrapper}>
          <Text
            style={[
              styles.wordmark,
              { color: inverse ? colors.warmWhite : colors.navy },
            ]}
          >
            LEGHEVO
          </Text>
          <Text style={styles.tagline}>La tua lega. Il tuo gioco.</Text>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    alignItems: 'center',
  },
  icon: {
    position: 'relative',
  },
  lVertical: {
    position: 'absolute',
  },
  lHorizontal: {
    position: 'absolute',
  },
  centerLine: {
    position: 'absolute',
    backgroundColor: colors.lime,
  },
  centerCircle: {
    position: 'absolute',
    borderColor: colors.lime,
    alignItems: 'center',
    justifyContent: 'center',
  },
  wordmarkWrapper: {
    marginTop: 24,
    alignItems: 'center',
  },
  wordmark: {
    fontSize: 42,
    lineHeight: 46,
    fontWeight: '900',
    letterSpacing: 1.5,
  },
  tagline: {
    color: colors.lime,
    fontSize: 14,
    fontWeight: '700',
    marginTop: 8,
  },
});
