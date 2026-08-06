import AsyncStorage from '@react-native-async-storage/async-storage';

const INSTALLATION_ID_KEY = 'leghevo.installation_id.v1';

function createUuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(
    /[xy]/g,
    (character) => {
      const random = Math.floor(Math.random() * 16);
      const value = character === 'x' ? random : (random & 0x3) | 0x8;
      return value.toString(16);
    },
  );
}

export async function getOrCreateInstallationId(): Promise<string> {
  const stored = await AsyncStorage.getItem(INSTALLATION_ID_KEY);
  if (stored && /^[0-9a-f-]{36}$/i.test(stored)) {
    return stored;
  }
  const created = createUuid();
  await AsyncStorage.setItem(INSTALLATION_ID_KEY, created);
  return created;
}
