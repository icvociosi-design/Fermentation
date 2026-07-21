# Suivi de fermentation — brief de transmission

Dernière mise à jour : 2026-07-21. Ce document résume l'architecture de l'application
et le travail effectué lors de la migration de `localStorage` vers Supabase, pour
qu'une future session (humaine ou Claude) puisse reprendre le contexte rapidement.

## En une phrase

Application de suivi de fermentation (cuves, densité, température, alertes) : un
unique fichier `index.html` (HTML/CSS/JS vanilla, ~2950 lignes, aucun build), dont
les données et l'authentification vivent désormais dans Supabase au lieu du
navigateur.

## Dépôt et déploiement

- GitHub : [icvociosi-design/Fermentation](https://github.com/icvociosi-design/Fermentation), branche `main`.
- Supabase : projet `gctvtjelleajwpcbkqqs` ([dashboard](https://supabase.com/dashboard/project/gctvtjelleajwpcbkqqs)).
- Pas de build ni de serveur applicatif : `index.html` est servi tel quel (GitHub Pages,
  hébergement statique, ou simplement ouvert/servi en local).
- `.devserver/serve.ps1` + `.claude/launch.json` : petit serveur statique local
  (PowerShell) créé pour prévisualiser l'app pendant le développement, sans
  dépendance externe (node/python indisponibles sur ce poste). Démarrage :
  `powershell -File .devserver/serve.ps1` → http://localhost:8934.

## Historique de cette migration (4 PR, toutes fusionnées)

1. **Reset du dépôt** — le dépôt GitHub contenait une version antérieure et
   abandonnée (modèle multi-organisation `organisations`/`profiles`, jamais
   fonctionnelle à cause d'une policy RLS récursive). Elle a été remplacée par le
   fichier local fonctionnel (localStorage) comme base propre.
2. **Fondations Supabase** — authentification email/mot de passe + bascule complète
   de la persistance vers Supabase (détails ci-dessous).
3. **Vue mobile allégée** — sur petit écran, seule la Saisie rapide est affichée.
4. **Saisie vocale Android** — bouton micro sur la Saisie rapide (Web Speech API).

## Architecture des données (Supabase)

Schéma dans [`supabase/schema.sql`](supabase/schema.sql) — déjà exécuté sur le
projet. À relancer uniquement en cas de réinitialisation complète (le script
commence par un `DROP TABLE` de toutes les tables listées).

| Table | Portée | Contenu |
|---|---|---|
| `profiles` | 1 ligne / utilisateur (`id` = `auth.users.id`) | `display_name`, `is_admin` |
| `cuves` | privée à son `user_id` | nom, appellation, couleur, qualité, TAP, azote assimilable, levure, archivage |
| `mesures` | liée à une cuve (`cuve_id`) | date, densité, température — unique par `(cuve_id, date)` |
| `alertes_globales` | **partagée** entre tous les comptes | règles d'alerte (conditions JSON, sévérité, message) |
| `levures` | **partagée** | référentiel de levures (nom, besoin en azote) |
| `variables_calculees` | **partagée** | formules type Excel (`=TAP*2,5 - AzoteAssimilable...`) |

Point important : **cuves/mesures sont privées à chaque compte**, alors que
alertes/levures/variables sont **partagées par tous les comptes** — ce comportement
reproduit exactement l'ancien modèle `localStorage` (qui avait un espace de données
par pseudo, mais une config globale unique). Ce n'est *pas* un modèle multi-utilisateur
partagé sur les cuves ; si plusieurs personnes doivent voir les mêmes cuves, il
faudrait introduire une notion d'organisation (non implémentée ici, volontairement,
pour rester fidèle au comportement existant).

### RLS (Row Level Security)

- `profiles` : chacun lit/modifie sa propre ligne, mais **seule la colonne
  `display_name` est modifiable côté client** (`revoke update` + `grant update
  (display_name)`) — sans cette restriction, un utilisateur pourrait s'auto-attribuer
  `is_admin = true` via un simple appel API (faille trouvée et corrigée pendant le
  développement, voir historique de `supabase/schema.sql`).
- `cuves`/`mesures` : lecture/écriture réservées au propriétaire (`user_id = auth.uid()`).
- `alertes_globales`/`levures`/`variables_calculees` : lecture pour tout utilisateur
  connecté, écriture réservée aux comptes `is_admin = true`.
- Un trigger (`handle_new_user`, `security definer set search_path = public`) crée
  automatiquement la ligne `profiles` à l'inscription.

### Devenir admin

Aucun flux in-app pour ça (volontaire, pour éviter l'auto-promotion). Après
inscription, passer manuellement `is_admin = true` sur sa ligne dans la table
`profiles` via le Table Editor Supabase.

### Gestion des comptes

Il n'y a plus de gestion de comptes dans l'app (l'onglet « Comptes » du panneau
Paramètres est devenu un simple message d'information). Créer/supprimer des comptes
se fait depuis **Authentication → Users** dans le dashboard Supabase.

## Architecture du code (`index.html`)

Un seul fichier, un seul `<script>` en bas de page. Pas de framework. État global en
variables JS (`cuves`, `alertes`, `levures`, `variablesCalculees`, `currentUser`,
`currentUserId`, `currentIsAdmin`).

### Client Supabase

```js
var sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY); // ligne ~445
```
La clé anon est publique par design (protégée par les policies RLS ci-dessus), donc
son exposition côté client n'est pas un problème de sécurité.

### Persistance : deux patterns différents selon la donnée

- **Cuves/mesures** (privées, potentiellement modifiées depuis plusieurs appareils) :
  chaque fonction de mutation (`confirmAddCuve`, `removeCuve`, `archiveCuve`,
  `updateCuveInfo`, `addMesure`, `saveSaisieRapide`, `toggleAlerteAcquittement`, …)
  fait un appel Supabase **ciblé** (insert/update/delete sur la ligne concernée),
  après avoir déjà mis à jour le tableau `cuves` en mémoire (UI optimiste — l'écran
  se met à jour immédiatement, l'écriture réseau se fait en arrière-plan via le
  helper `sbSync(promise, label)` qui alerte l'utilisateur en cas d'échec).
- **Alertes/levures/variables** (config partagée, éditée rarement, par un admin
  seulement) : pattern plus simple hérité de l'ancien code — `saveGlobalAlertes()`
  etc. font un `delete` de toute la table puis un `insert` complet de la liste en
  mémoire. Suffisant vu la faible fréquence d'édition et l'absence de concurrence
  réelle (un seul admin à la fois en pratique).

### Authentification

- `submitAuthForm()` : bascule signin/signup (`_authMode`), appelle
  `sb.auth.signInWithPassword` ou `sb.auth.signUp`.
- `onAuthenticated(user)` : charge le profil (`display_name`, `is_admin`), puis
  toutes les données (`Promise.all([loadCuvesFromSupabase(), loadGlobalAlertes(), ...])`).
- `bootSession()` : appelée au chargement de la page, restaure une session existante
  via `sb.auth.getSession()` (évite une reconnexion à chaque ouverture).
- La seule chose encore dans `localStorage` est le jeton de session géré par
  supabase-js (`sb-<ref>-auth-token`) — c'est le comportement standard du SDK, pas
  une donnée applicative.

### Vue mobile allégée

- `isMobileLite()` : `true` si `matchMedia('(max-width: 700px)')` **et** pas de
  bascule manuelle active (`sessionStorage.forceFullView`).
- `applyLayoutMode()` : appelée au chargement et au `resize` (debounce 200ms) ;
  masque les onglets Dernières Mesures/Détail cuves/Graphiques, force l'affichage de
  Saisie rapide, met à jour le lien de bascule (« Voir la version complète » /
  « Revenir à la vue mobile »).
- `renderAll()`/`refreshOtherViews()` : en mode mobile, s'arrêtent après
  `renderSaisieRapide()` — les vues desktop ne sont ni calculées ni affichées, donc
  Chart.js n'est jamais sollicité sur mobile.
- Chart.js et jsPDF (+autotable) ne sont **plus chargés en dur** dans le `<head>` :
  `loadScriptOnce(src)` les injecte à la demande (`ensureChartsLoaded()` dans
  `drawCharts()`, `ensurePdfLoaded()` dans `exportPDF()`), une seule fois (mis en
  cache dans `_scriptPromises`).

### Saisie vocale (Android uniquement)

- Détection : `_voiceSupported = !!(window.SpeechRecognition || window.webkitSpeechRecognition)`.
  Le bouton micro (`#voice-input-block`) n'est visible que si supporté **et** en
  mode mobile allégé (`updateVoiceButtonVisibility()`).
- `startVoiceCapture()` : lance la reconnaissance (`lang: 'fr-FR'`), affiche le
  texte intermédiaire, appelle `handleVoiceResult(transcript)` sur le résultat final.
- `findCuveByVoice()` : normalise (minuscules, sans accents via `normalize('NFD')`)
  et cherche le nom de cuve active le plus long inclus dans le texte reconnu.
- `extractVoiceNumber()` : regex après les mots-clés « densité » / « température »
  ou « degrés ».
- `parseVoiceDensite()` : heuristique métier — un nombre dit sans virgule et > 100
  (ex. « 1080 ») est interprété comme 1,080 g/cm³.
- **Pas d'enregistrement automatique** : les champs de la ligne repérée sont
  remplis, l'utilisateur doit toujours cliquer sur « Enregistrer la saisie »
  (`saveSaisieRapide()`, inchangée) — tolérance aux erreurs de reconnaissance.

### Panneau Admin (⚙ Paramètres)

Plus de mot de passe codé en dur : le bouton n'est visible que si
`currentIsAdmin === true` (chargé depuis `profiles.is_admin` à la connexion).
`showAdminPanel()` ouvre directement le contenu (plus d'étape « code admin »).

## Limites connues / suite possible

- **Cuves non partagées entre comptes** : si plusieurs personnes doivent gérer les
  mêmes cuves depuis des comptes différents, il faut introduire un modèle
  d'organisation (non fait, voir plus haut).
- **Saisie vocale** : Android/Chrome uniquement (Web Speech API non supportée sur
  iOS Safari — bouton masqué proprement, pas de fallback payant type
  Whisper/Google Speech-to-Text, décision volontaire pour rester gratuit et sans
  backend).
- **Pas de migration des anciennes données** `localStorage` : décision assumée avec
  l'utilisateur, redémarrage à vide dans Supabase.
- **Compte de test** `claude-verify4@example.com` (créé pendant les tests, actuellement
  `is_admin = true`, avec une « Cuve Test 1 ») — à supprimer via Authentication → Users
  si non souhaité.
- Les branches de travail fusionnées (`reset-baseline`, `feature/supabase-auth`,
  `feature/mobile-lite`, `feature/voice-input`) existent toujours sur GitHub
  (suppression bloquée par une protection de l'environnement Claude Code lors de la
  session — à supprimer manuellement si souhaité).
