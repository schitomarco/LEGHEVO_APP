export const LEGHEVO_LEGAL_PROFILE = {
  serviceName: 'LEGHEVO',
  controllerName: 'Marco Schito',
  developerName: 'Marco Schito',
  taxCode: 'SCHMRC85D23C978M',
  address: 'Via Giotto 8, 72024 Oria (BR), Italia',
  privacyEmail: 'info@leghevo.com',
  supportEmail: 'info@leghevo.com',
  certifiedEmail: 'schitomarco@pec.it',
  phone: '+39 333 899 3741',
  minimumAge: 14,
  launchMarket: 'Italia',
  dpoAppointed: false,
} as const;

export const LEGHEVO_ACTIVE_SERVICES = [
  {
    name: 'Supabase',
    purpose:
      'database, autenticazione, funzioni backend, sicurezza e conservazione tecnica',
  },
  {
    name: 'Expo / EAS',
    purpose:
      'build, distribuzione degli aggiornamenti e notifiche push quando attivate',
  },
  {
    name: 'API-Football / API-Sports',
    purpose:
      'calendari, squadre, calciatori, statistiche e risultati calcistici',
  },
  {
    name: 'Apple App Store e Google Play',
    purpose:
      'distribuzione dell’app e gestione degli acquisti Premium quando disponibili',
  },
] as const;

export const LEGHEVO_OPTIONAL_FEATURES = [
  'foto profilo e fotocamera',
  'posizione geografica',
  'selezione di contatti dalla rubrica',
  'chat tra partecipanti',
  'accesso con Apple o Google',
] as const;
