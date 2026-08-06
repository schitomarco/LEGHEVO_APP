import { LEGHEVO_LEGAL_PROFILE } from './legalProfile';

export const PRIVACY_POLICY_VERSION = '2026.07.29';
export const TERMS_VERSION = '2026.07.29';
export const MINIMUM_AGE_VERSION = '14-2026.07.29';
export const LEGAL_DOCUMENT_DATE = '29 luglio 2026';

export type LegalDocumentKind = 'privacy' | 'terms';

export type LegalSection = {
  title: string;
  paragraphs: string[];
};

export type LegalDocument = {
  kind: LegalDocumentKind;
  title: string;
  version: string;
  updatedAt: string;
  warning: string;
  intro: string;
  sections: LegalSection[];
};

const controllerContact =
  `${LEGHEVO_LEGAL_PROFILE.controllerName}, C.F. ` +
  `${LEGHEVO_LEGAL_PROFILE.taxCode}, ${LEGHEVO_LEGAL_PROFILE.address}. ` +
  `Email: ${LEGHEVO_LEGAL_PROFILE.privacyEmail}. PEC: ` +
  `${LEGHEVO_LEGAL_PROFILE.certifiedEmail}. Telefono: ` +
  `${LEGHEVO_LEGAL_PROFILE.phone}.`;

export const privacyPolicy: LegalDocument = {
  kind: 'privacy',
  title: 'Informativa privacy',
  version: PRIVACY_POLICY_VERSION,
  updatedAt: LEGAL_DOCUMENT_DATE,
  warning:
    'VERSIONE PUBBLICATA PER L’ITALIA. LEGHEVO raccoglie solo i dati necessari alle funzioni effettivamente attive. Permessi e servizi facoltativi restano disattivati finché l’utente non li sceglie.',
  intro:
    'Questa informativa spiega con parole semplici quali dati personali usa LEGHEVO, per quali motivi e per quanto tempo. Leggere l’informativa non significa prestare un consenso generale: il servizio usa le basi giuridiche indicate per ciascuna finalità e chiede un consenso separato soltanto quando necessario.',
  sections: [
    {
      title: '1. Titolare del trattamento',
      paragraphs: [
        `Il titolare del trattamento è ${controllerContact}`,
        `Ideazione e sviluppo dell’app: ${LEGHEVO_LEGAL_PROFILE.developerName}. Non è stato nominato un Responsabile della protezione dei dati (DPO). Le richieste privacy possono essere inviate a ${LEGHEVO_LEGAL_PROFILE.privacyEmail} o tramite il Centro Diritti dell’app.`,
      ],
    },
    {
      title: '2. Utenti e ambito del servizio',
      paragraphs: [
        'LEGHEVO è destinata agli utenti in Italia che hanno compiuto 14 anni. Chi ha tra 14 e 17 anni deve utilizzare il servizio con l’autorizzazione di un genitore o tutore; gli acquisti Premium di un minorenne devono essere autorizzati o effettuati dal genitore o tutore.',
        'L’app registra la dichiarazione relativa al requisito di età, ma non chiede la data di nascita né un documento di identità durante la normale registrazione.',
      ],
    },
    {
      title: '3. Dati trattati',
      paragraphs: [
        'Account e profilo: indirizzo email, nome visualizzato, identificativo utente, stato di verifica, dichiarazione sul requisito di età, eventuale foto profilo e dati tecnici di autenticazione.',
        'Gioco e vita della lega: leghe, squadre, ruoli, inviti, aste, offerte, rose, formazioni, mercato, risultati, classifiche, trofei, notifiche, preferenze e operazioni necessarie al fantasy football.',
        'Assistenza e diritti: comunicazioni inviate all’assistenza, richieste privacy, stato della pratica, risposte e cronologia delle accettazioni dei documenti.',
        'Dati tecnici: sessione, indirizzo IP e informazioni essenziali su dispositivo, versione dell’app, eventi di sicurezza, errori e log necessari a proteggere e mantenere il servizio. LEGHEVO non usa al momento strumenti esterni di profilazione o analytics pubblicitari.',
        'Dati calcistici: calendari, squadre, calciatori, statistiche, voti e risultati ottenuti da API-Football/API-Sports. Questi dati non vengono usati per prendere decisioni giuridiche sulle persone.',
      ],
    },
    {
      title: '4. Finalità e basi giuridiche',
      paragraphs: [
        'Creare e proteggere l’account, gestire le leghe, calcolare i risultati, fornire assistenza e rendere disponibili le funzioni richieste: esecuzione del contratto e misure precontrattuali.',
        'Gestire gli acquisti Premium e gli abbonamenti tramite Apple App Store o Google Play: esecuzione del contratto e adempimento degli obblighi amministrativi applicabili. LEGHEVO non riceve i dati completi della carta di pagamento.',
        'Prevenire abusi, accessi illeciti e frodi, mantenere la sicurezza, correggere errori e difendere un diritto: legittimo interesse del titolare, bilanciato con i diritti dell’utente.',
        'Gestire obblighi fiscali, contabili, richieste dell’autorità e reclami: adempimento di obblighi legali.',
        'Usare posizione precisa o altre funzioni per le quali la legge richiede una scelta specifica: consenso facoltativo, revocabile dalle impostazioni del dispositivo senza perdere le funzioni principali.',
      ],
    },
    {
      title: '5. Funzioni e permessi facoltativi',
      paragraphs: [
        'Foto profilo e fotocamera: se la funzione viene attivata, l’utente può scegliere o scattare un’immagine. Il permesso è richiesto soltanto al momento dell’uso e la foto resta modificabile o eliminabile.',
        'Rubrica: se viene attivato l’invito dai contatti, LEGHEVO usa la selezione effettuata dall’utente e non copia l’intera rubrica sul server. Quando possibile viene usato il pannello di condivisione del dispositivo.',
        'Posizione: se vengono attivate funzioni locali, LEGHEVO privilegia la posizione approssimativa. La posizione precisa viene richiesta solo quando indispensabile, non viene usata per seguire gli spostamenti e non è necessaria per giocare nelle leghe ordinarie.',
        'Chat: quando attivata, tratta messaggi, data, mittente, lega e allegati scelti dall’utente. La chat è limitata ai partecipanti autorizzati e deve essere usata nel rispetto degli altri utenti.',
        'Accesso con Apple o Google: quando attivato, LEGHEVO riceve dal provider l’identificativo dell’account e i dati che l’utente decide di condividere, normalmente email e nome. Il provider gestisce autonomamente il proprio account.',
        'Nella versione pubblicata alla data di questa informativa tali funzioni non ancora presenti nel codice restano disattivate e non producono raccolta di dati.',
      ],
    },
    {
      title: '6. Comunicazioni, pubblicità e sponsor',
      paragraphs: [
        'LEGHEVO invia email di servizio, ad esempio per verifica dell’account, recupero password, sicurezza, assistenza e modifiche importanti. Può inoltre inviare notifiche tecniche e di gioco tramite il dispositivo, se l’utente le abilita.',
        'L’app può mostrare pubblicità contestuale o contenuti sponsorizzati chiaramente riconoscibili. Alla data di questa informativa non è attiva pubblicità comportamentale, non viene creato un profilo pubblicitario e i dati personali non vengono ceduti a sponsor. Prima di attivare una rete pubblicitaria che tratti dati sarà aggiornata l’informativa e, se richiesto, verrà raccolto un consenso separato.',
        'Non sono previste newsletter o comunicazioni promozionali dirette. Un’eventuale futura attivazione richiederà una scelta facoltativa distinta.',
      ],
    },
    {
      title: '7. Destinatari e fornitori',
      paragraphs: [
        'Supabase tratta dati per database, autenticazione, funzioni backend, sicurezza e conservazione tecnica. Expo/EAS supporta build, aggiornamenti e, quando attivate, notifiche push. API-Football/API-Sports fornisce dati calcistici tramite richieste server-to-server e non riceve il profilo completo degli utenti.',
        'Apple e Google trattano in autonomia i dati necessari alla distribuzione dell’app, agli acquisti nei rispettivi store e, se scelto, all’accesso federato. Per i messaggi di autenticazione è usato Supabase Auth; non è configurato un diverso provider email dedicato.',
        'Possono accedere ai dati soltanto soggetti autorizzati o fornitori vincolati da contratto per assistenza, sicurezza, obblighi legali e funzionamento del servizio. I dati non vengono venduti.',
      ],
    },
    {
      title: '8. Trasferimenti internazionali',
      paragraphs: [
        'Alcuni fornitori internazionali possono trattare dati fuori dallo Spazio Economico Europeo. Il trattamento avviene, secondo il servizio e la regione contrattualmente selezionata, sulla base di decisioni di adeguatezza, del Data Privacy Framework UE-USA quando applicabile, di clausole contrattuali standard o di altre garanzie previste dagli articoli 44 e seguenti del GDPR.',
        `Per informazioni sulle garanzie applicabili a un fornitore o per ottenerne una copia, l’utente può scrivere a ${LEGHEVO_LEGAL_PROFILE.privacyEmail}.`,
      ],
    },
    {
      title: '9. Tempi di conservazione',
      paragraphs: [
        'Account, profilo e dati di gioco sono conservati mentre l’account è attivo. Dopo una richiesta valida di cancellazione, i dati personali vengono eliminati o anonimizzati dai sistemi operativi entro 30 giorni; le copie di sicurezza vengono sovrascritte secondo il ciclo del fornitore e comunque entro 90 giorni, salvo obblighi di legge o necessità di difesa.',
        'I risultati già ufficializzati possono restare nello storico della lega in forma anonima, senza email, foto o identificativo dell’account, per non alterare le competizioni degli altri partecipanti.',
        'Foto profilo e token di notifica restano fino alla sostituzione, alla revoca del permesso o alla cancellazione dell’account. La posizione usata solo durante una funzione locale non viene conservata; la rubrica non viene copiata integralmente.',
        'Messaggi e allegati della chat, quando la funzione sarà attiva, restano fino alla loro eliminazione e comunque non oltre 24 mesi dalla chiusura della lega, salvo segnalazioni o obblighi di conservazione.',
        'Richieste di assistenza e relative risposte sono conservate fino a 24 mesi dalla chiusura. I log applicativi di sicurezza controllati da LEGHEVO sono conservati fino a 12 mesi. Le richieste privacy e la cronologia delle accettazioni restano durante la vita dell’account e, solo se necessario, per il tempo utile a dimostrare l’adempimento o difendere un diritto.',
        'Riferimenti di acquisto, rimborsi e documenti soggetti a obblighi fiscali o contabili sono conservati per il periodo imposto dalla legge. I dati completi di pagamento restano presso Apple o Google secondo le rispettive informative.',
      ],
    },
    {
      title: '10. Diritti dell’utente',
      paragraphs: [
        'Nei casi previsti dal GDPR l’utente può chiedere accesso, rettifica, cancellazione, limitazione, opposizione e portabilità. Può revocare un consenso senza rendere illeciti i trattamenti già effettuati e può disattivare i permessi dalle impostazioni del dispositivo.',
        'Il Centro Diritti di LEGHEVO consente di inviare e seguire le richieste, normalmente gestite entro un mese. L’utente può anche esportare una copia strutturata dei propri dati ed eliminare l’account dalle impostazioni.',
        `È sempre possibile scrivere a ${LEGHEVO_LEGAL_PROFILE.privacyEmail} o alla PEC ${LEGHEVO_LEGAL_PROFILE.certifiedEmail}. L’utente può inoltre proporre reclamo al Garante per la protezione dei dati personali.`,
      ],
    },
    {
      title: '11. Minori e sicurezza',
      paragraphs: [
        'Le spiegazioni e le richieste di consenso sono formulate in modo comprensibile anche per un utente di 14 anni. LEGHEVO non richiede categorie particolari di dati, non effettua pubblicità comportamentale verso minori e limita i dati di profilo ai partecipanti autorizzati della lega.',
        'Contenuti offensivi, minacce, molestie, dati altrui pubblicati senza diritto e comportamenti di cyberbullismo possono essere segnalati all’assistenza. Il titolare può rimuoverli o sospendere l’account nel rispetto della legge e dei Termini.',
      ],
    },
    {
      title: '12. Sicurezza e decisioni automatizzate',
      paragraphs: [
        'LEGHEVO usa controlli di accesso, separazione dei ruoli, connessioni cifrate, registrazione delle operazioni sensibili e regole server-side. Nessun sistema è privo di rischio, ma vengono adottate misure proporzionate e aggiornate.',
        'Non vengono prese decisioni esclusivamente automatizzate che producano effetti giuridici o analogamente significativi sull’utente. Calcoli di voti, classifiche, sostituzioni e risultati hanno esclusivamente effetti nel gioco e possono essere verificati o corretti secondo le regole della lega.',
      ],
    },
    {
      title: '13. Aggiornamenti dell’informativa',
      paragraphs: [
        'Le modifiche sostanziali vengono comunicate prima della loro efficacia. LEGHEVO registra la versione letta e richiede una nuova presa visione quando cambiano in modo rilevante finalità, dati, fornitori o diritti. Un consenso facoltativo viene richiesto di nuovo soltanto quando necessario.',
      ],
    },
  ],
};

export const termsOfService: LegalDocument = {
  kind: 'terms',
  title: 'Termini di utilizzo',
  version: TERMS_VERSION,
  updatedAt: LEGAL_DOCUMENT_DATE,
  warning:
    'VERSIONE PUBBLICATA PER L’ITALIA. I prezzi e le condizioni specifiche di Premium vengono mostrati nello store prima di ogni acquisto e prevalgono insieme alle norme inderogabili del consumatore.',
  intro:
    'Questi Termini regolano l’uso di LEGHEVO. Creando un account, l’utente dichiara di averli letti, di rispettare il requisito di età e di usare il servizio correttamente. L’Informativa privacy descrive separatamente il trattamento dei dati personali.',
  sections: [
    {
      title: '1. Fornitore del servizio',
      paragraphs: [
        `LEGHEVO è offerta e sviluppata da ${controllerContact}`,
        `Assistenza: ${LEGHEVO_LEGAL_PROFILE.supportEmail}. LEGHEVO è il nome del servizio offerto personalmente dal titolare indicato.`,
      ],
    },
    {
      title: '2. Che cos’è LEGHEVO',
      paragraphs: [
        'LEGHEVO è una piattaforma di fantasy football che permette di creare leghe private, invitare partecipanti, gestire aste, rose, formazioni, mercato, competizioni, risultati, statistiche, notifiche e storico.',
        'LEGHEVO è un gioco di abilità e organizzazione tra utenti. Non offre scommesse, non raccoglie puntate e non garantisce premi in denaro. Eventuali premi organizzati autonomamente dai partecipanti restano estranei al servizio e devono rispettare la legge.',
      ],
    },
    {
      title: '3. Età e capacità',
      paragraphs: [
        'L’età minima è 14 anni. Chi ha tra 14 e 17 anni deve avere l’autorizzazione di un genitore o tutore per creare l’account e usare il servizio. Gli acquisti Premium di un minorenne devono essere autorizzati o effettuati dal genitore o tutore.',
        'Registrandosi, l’utente conferma di avere almeno 18 anni oppure di avere almeno 14 anni e l’autorizzazione richiesta. In caso di dichiarazione non veritiera o di rischio per un minore, l’account può essere limitato o sospeso.',
      ],
    },
    {
      title: '4. Account',
      paragraphs: [
        'L’utente deve fornire dati corretti, mantenere sicure le credenziali e non cedere l’account. È responsabile delle attività svolte tramite il proprio profilo, salvo uso non autorizzato tempestivamente segnalato.',
        'L’accesso con Apple o Google, quando disponibile, resta soggetto anche alle condizioni del relativo provider. La cancellazione dell’account può essere richiesta dall’app; i dati vengono gestiti come descritto nell’Informativa privacy.',
      ],
    },
    {
      title: '5. Leghe e ruolo del Presidente',
      paragraphs: [
        'Il Presidente configura le regole della lega, amministra gli inviti e compie le operazioni riservate nei limiti degli strumenti disponibili. Gli altri partecipanti accettano le regole pubblicate nella lega.',
        'LEGHEVO applica in modo automatico configurazioni, dati sportivi e criteri di spareggio. Le controversie puramente interne tra manager devono essere risolte dal gruppo; restano disponibili correzioni e registri tecnici per gli errori del servizio o del provider.',
      ],
    },
    {
      title: '6. Condotta, nomi e chat',
      paragraphs: [
        'Sono vietati contenuti illeciti, offensivi, discriminatori, minacciosi, fraudolenti, lesivi della privacy o dei diritti altrui. Non è consentito impersonare altre persone, aggirare i controlli, accedere a dati non autorizzati, disturbare il servizio o automatizzare operazioni senza permesso.',
        'L’utente conserva i diritti sui contenuti che inserisce e concede a LEGHEVO una licenza gratuita, non esclusiva e limitata a ospitarli e mostrarli quanto necessario al funzionamento della lega.',
        'Quando la chat sarà attiva, messaggi e allegati dovranno rispettare queste regole. Contenuti e account possono essere segnalati a ' +
          `${LEGHEVO_LEGAL_PROFILE.supportEmail}; il titolare può limitarli o rimuoverli, conservando quanto necessario per sicurezza o richieste dell’autorità.`,
      ],
    },
    {
      title: '7. Dati sportivi e risultati',
      paragraphs: [
        'Calendari, statistiche, eventi e voti provengono da API-Football/API-Sports o da fonti tecniche collegate e possono subire ritardi, indisponibilità o rettifiche. LEGHEVO può ricalcolare i risultati quando il dato sorgente viene corretto.',
        'Il verdetto ufficiale della lega dipende dalle regole configurate e dalle operazioni di ufficializzazione previste nell’app. Nessun dato sportivo è garantito come adatto a scommesse, decisioni economiche o altri usi professionali.',
      ],
    },
    {
      title: '8. Piano gratuito e Premium',
      paragraphs: [
        'LEGHEVO può offrire funzioni gratuite e funzioni Premium. Prezzo, durata, rinnovo, prova gratuita, limiti e contenuto dell’offerta vengono mostrati prima dell’acquisto su Apple App Store o Google Play.',
        'Se l’offerta è un abbonamento, il rinnovo e l’addebito sono gestiti dallo store scelto. L’utente può disdire dalle impostazioni del proprio account Apple o Google entro i termini indicati dallo store; la cancellazione dell’app non annulla automaticamente l’abbonamento.',
        'Pagamenti, rimborsi e recesso sono gestiti secondo le procedure dello store, le presenti condizioni e i diritti inderogabili riconosciuti al consumatore. LEGHEVO non chiede né conserva il numero completo della carta.',
      ],
    },
    {
      title: '9. Pubblicità e sponsor',
      paragraphs: [
        'LEGHEVO può mostrare pubblicità contestuale, partnership o contenuti sponsorizzati, che saranno riconoscibili come tali. La presenza di uno sponsor non costituisce garanzia o raccomandazione personale.',
        'Alla data di questi Termini non è attiva profilazione pubblicitaria. L’eventuale introduzione di pubblicità personalizzata sarà preceduta dalle informazioni e dalle scelte richieste dalla legge.',
      ],
    },
    {
      title: '10. Proprietà intellettuale',
      paragraphs: [
        'Nome, grafica, software, testi, database originali e funzioni di LEGHEVO sono protetti dalle norme applicabili. L’utente riceve una licenza personale, revocabile, non esclusiva e non trasferibile per usare l’app secondo questi Termini.',
        'Marchi, stemmi, immagini e dati sportivi di terzi appartengono ai rispettivi titolari. Nessuna disposizione concede il diritto di estrarli, ripubblicarli o sfruttarli fuori dalle funzioni consentite.',
      ],
    },
    {
      title: '11. Disponibilità e aggiornamenti',
      paragraphs: [
        'Il servizio viene mantenuto con ragionevole diligenza, ma manutenzioni, rete, dispositivi, store e fornitori possono causare interruzioni. Aggiornamenti necessari a sicurezza, compatibilità o conformità possono essere installati tramite lo store o Expo/EAS.',
        'Funzioni non ancora attive, incluse chat, accesso social o alcuni permessi, diventano disponibili soltanto dopo il completamento tecnico e delle misure di sicurezza necessarie.',
      ],
    },
    {
      title: '12. Sospensione e chiusura',
      paragraphs: [
        'LEGHEVO può limitare o sospendere un account per violazioni gravi, rischi di sicurezza, frodi, obblighi di legge o tutela degli utenti. Quando possibile viene fornita una spiegazione e un modo per contestare la decisione.',
        'L’utente può smettere di usare il servizio ed eliminare l’account. Risultati già disputati possono restare anonimizzati per preservare classifiche e storico degli altri partecipanti.',
      ],
    },
    {
      title: '13. Garanzie e responsabilità',
      paragraphs: [
        'LEGHEVO risponde secondo la legge applicabile e non limita responsabilità che non possono essere escluse, inclusi dolo, colpa grave, danni alla persona e diritti inderogabili del consumatore.',
        'Nei limiti consentiti, il titolare non risponde di condotte dei partecipanti, accordi o premi esterni alla piattaforma, indisponibilità non controllabili, dati errati di terzi o danni dovuti a uso illecito o contrario alle istruzioni.',
      ],
    },
    {
      title: '14. Modifiche e continuità',
      paragraphs: [
        'Le modifiche rilevanti ai Termini vengono comunicate con anticipo ragionevole e richiedono una nuova accettazione quando necessario. Se l’utente non accetta, può interrompere l’uso ed eliminare l’account prima dell’efficacia delle nuove condizioni.',
        'La nullità di una singola clausola non rende inefficaci le altre. La mancata applicazione immediata di una disposizione non costituisce rinuncia.',
      ],
    },
    {
      title: '15. Legge applicabile e assistenza',
      paragraphs: [
        'I Termini sono regolati dalla legge italiana. Per il consumatore resta competente il giudice del luogo di residenza o domicilio e restano salve tutte le tutele inderogabili previste dalla normativa italiana ed europea.',
        `Prima di una controversia l’utente può contattare ${LEGHEVO_LEGAL_PROFILE.supportEmail}, la PEC ${LEGHEVO_LEGAL_PROFILE.certifiedEmail} o il numero ${LEGHEVO_LEGAL_PROFILE.phone}. Restano utilizzabili le procedure di risoluzione alternativa previste dalla legge, quando applicabili.`,
      ],
    },
  ],
};

export function getLegalDocument(kind: LegalDocumentKind) {
  return kind === 'privacy' ? privacyPolicy : termsOfService;
}
