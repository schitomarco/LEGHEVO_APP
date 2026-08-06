import { Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { getLegalDocument, type LegalDocumentKind } from '../legalDocuments';
import { colors, radius } from '../theme';

type Props = {
  kind: LegalDocumentKind | null;
  onClose: () => void;
};

export function LegalDocumentModal({ kind, onClose }: Props) {
  if (!kind) {
    return null;
  }

  const document = getLegalDocument(kind);

  return (
    <Modal
      animationType="slide"
      onRequestClose={onClose}
      presentationStyle="pageSheet"
      visible
    >
      <View style={styles.root}>
        <View style={styles.header}>
          <View style={styles.headerCopy}>
            <Text style={styles.eyebrow}>DOCUMENTI LEGHEVO</Text>
            <Text style={styles.title}>{document.title}</Text>
            <Text style={styles.version}>
              Versione {document.version} · {document.updatedAt}
            </Text>
          </View>
          <Pressable onPress={onClose} style={styles.closeButton}>
            <Text style={styles.closeText}>×</Text>
          </Pressable>
        </View>

        <ScrollView
          contentContainerStyle={styles.content}
          showsVerticalScrollIndicator={false}
        >
          <View style={styles.noticeCard}>
            <Text style={styles.noticeText}>{document.warning}</Text>
          </View>

          <Text style={styles.intro}>{document.intro}</Text>

          {document.sections.map((section) => (
            <View key={section.title} style={styles.section}>
              <Text style={styles.sectionTitle}>{section.title}</Text>
              {section.paragraphs.map((paragraph) => (
                <Text key={paragraph} style={styles.paragraph}>
                  {paragraph}
                </Text>
              ))}
            </View>
          ))}
        </ScrollView>

        <View style={styles.footer}>
          <Pressable onPress={onClose} style={styles.button}>
            <Text style={styles.buttonText}>HO LETTO</Text>
          </Pressable>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingTop: 22,
    paddingBottom: 16,
    backgroundColor: colors.navy,
  },
  headerCopy: {
    flex: 1,
  },
  eyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.55,
  },
  title: {
    color: colors.warmWhite,
    fontSize: 23,
    fontWeight: '900',
    marginTop: 4,
  },
  version: {
    color: colors.mutedLight,
    fontSize: 11,
    marginTop: 5,
  },
  closeButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navySoft,
    marginLeft: 12,
  },
  closeText: {
    color: colors.warmWhite,
    fontSize: 28,
    lineHeight: 30,
  },
  content: {
    padding: 20,
    paddingBottom: 30,
  },
  noticeCard: {
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: '#CCD5CA',
    padding: 15,
    backgroundColor: '#F3F7EF',
  },
  noticeText: {
    color: colors.navy,
    fontSize: 11,
    lineHeight: 17,
    fontWeight: '800',
  },
  intro: {
    color: colors.navy,
    fontSize: 14,
    lineHeight: 21,
    fontWeight: '700',
    marginTop: 18,
  },
  section: {
    marginTop: 23,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
    marginBottom: 8,
  },
  paragraph: {
    color: '#44505C',
    fontSize: 13,
    lineHeight: 20,
    marginBottom: 9,
  },
  footer: {
    paddingHorizontal: 20,
    paddingVertical: 14,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: '#D8DDD6',
    backgroundColor: colors.white,
  },
  button: {
    height: 50,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  buttonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
});
