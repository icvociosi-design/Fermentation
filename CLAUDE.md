# Suivi de fermentation — brief de transmission

Dernière mise à jour : 2026-07-23. Ce document résume l'architecture de l'application
et l'historique des évolutions (migration `localStorage` → Supabase, puis plusieurs
rounds d'affinage de la saisie vocale et de la convention d'unité de densité), pour
qu'une future session (humaine ou Claude) puisse reprendre le contexte rapidement.
Une section finale liste des **leçons génériques**, réutilisables sur d'autres projets.

## En une phrase

Application de suivi de fermentation (cuves, densité, température, alertes) : un
unique fichier `index.html` (HTML/CSS/JS vanilla, ~3000 lignes, aucun build), dont
les données et l'authentification vivent dans Supabase. La saisie sur le terrain se
fait principalement à la voix, sur mobile, en touchant une cuve puis en dictant.

## Dépôt et déploiement

- GitHub : [icvociosi-design/Fermentation](https://github.com/icvociosi-design/Fermentation), branche `main`.
- Déployé en statique sur GitHub Pages : https://icvociosi-design.github.io/Fermentation/
- Supabase : projet `gctvtjelleajwpcbkqqs` ([dashboard](https://supabase.com/dashboard/project/gctvtjelleajwpcbkqqs)).
- Pas de build ni de serveur applicatif : `index.html` est servi tel quel.
- `.devserver/serve.ps1` + `.claude/launch.json` : petit serveur statique local
  (PowerShell) pour prévisualiser l'app pendant le développement, sans dépendance
  externe (node/python indisponibles sur ce poste). Démarrage :
  `powershell -File .devserver/serve.ps1` → http://localhost:8934.
- Depuis la bascule vers Supabase, le flux de travail est passé de PR par feature
  (branches `feature/...`) à des **commits directs sur `main`**, poussés à la demande
  de l'utilisateur après chaque correctif validé en test.

## Historique des évolutions

### Migration initiale (4 PR, toutes fusionnées)

1. **Reset du dépôt** — remplacement d'une version antérieure abandonnée
   (modèle multi-organisation jamais fonctionnel) par le fichier local `localStorage`
   fonctionnel, comme base propre.
2. **Fondations Supabase** — authentification email/mot de passe + bascule complète
   de la persistance vers Supabase (détails ci-dessous).
3. **Vue mobile allégée** — sur petit écran, seule la Saisie rapide est affichée.
4. **Saisie vocale Android** — bouton micro sur la Saisie rapide (Web Speech API).

### Affinage post-migration (commits directs, itératifs)

Après la migration, une longue série d'allers-retours de test réel sur le terrain
(Chrome et Samsung Internet Android) a fait remonter des problèmes concrets, corrigés
dans cet ordre :

1. Rendu desktop (séparateur de connexion visuellement barré) et mobile (colonnes du
   tableau de Saisie rapide débordant du cadre sur petit écran).
2. Bug de saisie vocale : les champs remplis par la voix étaient effacés juste avant
   l'enregistrement, à cause d'un `resize` (ouverture du clavier virtuel) qui
   déclenchait un re-rendu complet du tableau. → `applyLayoutMode()` ne re-rend
   maintenant qu'au changement réel mobile/desktop, pas à chaque `resize`.
2. **Précision de la reconnaissance vocale**, plusieurs rounds :
   - Matching de cuve par sous-chaîne trop permissif ("Cuve 1" matchait à tort dans
     "Cuve 12") → recherche par mots entiers bornés (regex avec `\s`/début/fin).
   - Une seule hypothèse de reconnaissance utilisée → passage à 4 alternatives
     (`maxAlternatives`), on teste chacune jusqu'à en trouver une interprétable.
   - Nombres dictés en toutes lettres ("douze", "quatre-vingts") non reconnus →
     petit parseur de nombres français (`parseFrenchNumberWords`) qui les convertit
     en chiffres avant traitement.
   - Suffixes de cuves en doublon ("bis"/"ter", voir `SUFFIXES_DOUBLON`) mal
     transcrits (ex. "ter" entendu "terre") → table d'alias vers la forme canonique.
   - **Sélection tactile de la cuve** (ajoutée ensuite, voir plus bas) : rendue plus
     fiable que la reconnaissance du nom/numéro dicté, surtout avec beaucoup de
     cuves.
3. **Convention d'unité de la densité**, changement en 2 temps :
   - D'abord : la densité dictée/tapée "1080" était automatiquement divisée par 1000
     à l'enregistrement (`1,080`), pour matcher l'unité physique g/cm³.
   - Puis l'utilisateur a demandé l'inverse : **la valeur est stockée et affichée
     nativement "autour de 1000"** (ex. `1080`), sans aucune conversion d'échelle —
     c'est la convention d'écriture du métier, même si l'unité physique réelle est
     ~1. `fmtDensite()` affiche, `sanitizeDensiteValue()` corrige au vol une saisie
     qui ressortirait sous 100 (typiquement une virgule tapée par réflexe de
     notation scientifique, ex. "1,070" lu comme 1,07 — toujours une erreur
     d'échelle dans ce domaine, jamais une vraie valeur).
   - **Ce changement d'échelle a nécessité une migration manuelle des données déjà
     enregistrées** dans Supabase (`UPDATE mesures SET densite = densite * 1000`) —
     l'utilisateur l'a fait lui-même en supprimant ses mesures de test.
   - L'unité "g/cm³" a ensuite été retirée de tout l'affichage (en-têtes, widgets,
     exports CSV/PDF) puisque la valeur affichée ne la respecte plus littéralement.
4. **Bug de perte de sauvegarde des variables calculées** (champ "Unité") : une
   fonction nommée `...Silent` (censée juste mettre à jour la mémoire pendant la
   frappe) déclenchait quand même une sauvegarde réseau à chaque touche. Le pattern
   de sauvegarde "delete + insert complet de la table" combiné à un appel par
   keystroke créait des écritures concurrentes qui s'écrasaient dans le désordre
   selon l'ordre d'arrivée des réponses réseau. Corrigé pour les variables calculées
   ET le référentiel de levures (même bug, même fonction miroir).
5. **Simplification finale de la saisie vocale** : une fois la sélection tactile de
   cuve en place, le contrôle de validation orale ("validé"/"annule" + coche verte,
   ajouté à l'étape 2) est devenu redondant — corriger une valeur, c'est juste
   retoucher la cuve et redicter, qui écrase directement. Toute cette couche a été
   retirée pour simplifier le flux.
6. **Identité visuelle** : ajout du logo Groupe ICV (`assets/logo-icv.jpg`) en
   en-tête de l'app et de l'écran de connexion, et refonte de la palette autour de
   3 teintes tirées du logo (`--c-brand` aubergine, `--c-accent` magenta,
   `--c-accent-2` sarcelle — voir « Identité visuelle » plus bas), boutons/cartes
   avec ombres légères. En parallèle, resserrement de la vue mobile : le bouton
   ⚙ Paramètres reste masqué même pour un compte admin (réservé à la version PC),
   et la dernière colonne (action) de la Saisie rapide est compressée davantage
   (police réduite, libellé "Terminer" caché, icône seule) pour tenir sans
   défilement horizontal sur petit écran. Retrait aussi du sous-titre du header
   ("Densité · Vitesse en ΔDensité/jour · Alertes · Graphiques"), jugé superflu.
7. **Raccourcis « Détail cuves » qui n'atterrissaient pas en haut du cadre** : les
   liens `<a href="#cuve-anchor-N">` de la barre de raccourcis déclenchaient le
   saut d'ancre natif du navigateur, qui aligne le haut de l'élément sur le tout
   haut de la fenêtre — sauf que ce haut est masqué sous le header collant
   (`.sticky-top`), donnant l'impression d'atterrir au milieu de la carte. Remplacé
   par `scrollToCuveAnchor(ci)` (`onclick="...;return false;"`), qui mesure la
   hauteur réelle du header collant au moment du clic et calcule l'offset de scroll
   en conséquence — plus robuste qu'un `scroll-margin-top` figé, puisque cette
   hauteur varie selon le contenu du header. Même correctif appliqué à
   `archiveCuveDetail()`, qui avait le même défaut avec `scrollIntoView({block:'start'})`.
   **Round 2** : le nom de cuve restait quand même caché, cette fois sous la barre
   de raccourcis elle-même (`#detail-shortcuts`), qui est *aussi* `position:sticky`
   (collée juste sous `.sticky-top` via la variable `--sticky-offset`) — deux barres
   collantes empilées, il fallait compenser la hauteur des deux, pas seulement celle
   du header. Le petit décalage cosmétique de 12px ajouté au premier passage n'était
   pas la cause et a été retiré (le nom atterrit maintenant exactement au ras de la
   barre de raccourcis, sans marge).

## Architecture des données (Supabase)

Schéma dans [`supabase/schema.sql`](supabase/schema.sql) — déjà exécuté sur le
projet. À relancer uniquement en cas de réinitialisation complète (le script
commence par un `DROP TABLE` de toutes les tables listées). **Ce fichier ne capture
que le schéma de départ** : deux colonnes (`variables_calculees.unite` et `.visible`)
ont été ajoutées après coup par `ALTER TABLE` directement en production — le
`schema.sql` a été mis à jour en parallèle pour rester la source de vérité en cas de
reset complet, mais il n'y a pas de dossier `migrations/` ; toute évolution de schéma
future devrait probablement en introduire un plutôt que de continuer à divulguer
`schema.sql` + instructions `ALTER TABLE` en texte libre.

| Table | Portée | Contenu |
|---|---|---|
| `profiles` | 1 ligne / utilisateur (`id` = `auth.users.id`) | `display_name`, `is_admin` |
| `cuves` | privée à son `user_id` | nom, appellation, couleur, qualité, TAP, azote assimilable, levure, archivage |
| `mesures` | liée à une cuve (`cuve_id`) | date, densité (échelle native ~1000, voir plus haut), température — unique par `(cuve_id, date)` |
| `alertes_globales` | **partagée** entre tous les comptes | règles d'alerte (conditions JSON, sévérité, message) |
| `levures` | **partagée** | référentiel de levures (nom, besoin en azote) |
| `variables_calculees` | **partagée** | formules type Excel (`=TAP*2,5 - AzoteAssimilable...`), `unite`, `visible` (affichage dans Détail cuves) |

Point important : **cuves/mesures sont privées à chaque compte**, alors que
alertes/levures/variables sont **partagées par tous les comptes** — ce comportement
reproduit exactement l'ancien modèle `localStorage`. Ce n'est *pas* un modèle
multi-utilisateur partagé sur les cuves ; si plusieurs personnes doivent voir les
mêmes cuves, il faudrait introduire une notion d'organisation (non implémentée ici,
volontairement, pour rester fidèle au comportement existant).

**Attention aux seuils d'alertes et formules qui référencent Densite/Vitesse/
DeltaInit** : leur échelle a changé (×1000) en même temps que celle des mesures. Tout
seuil ou formule configuré par l'admin (panneau ⚙ Paramètres) avant ce changement doit
être revu manuellement — le code ne peut pas deviner l'intention d'une formule/d'un
seuil existant.

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
var sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
```
La clé anon est publique par design (protégée par les policies RLS ci-dessus), donc
son exposition côté client n'est pas un problème de sécurité.

### Persistance : deux patterns différents selon la donnée

- **Cuves/mesures** (privées, potentiellement modifiées depuis plusieurs appareils) :
  chaque fonction de mutation (`confirmAddCuve`, `removeCuve`, `archiveCuve`,
  `updateCuveInfo`, `addMesure`, `saveSaisieRapide`, `toggleAlerteAcquittement`, …)
  fait un appel Supabase **ciblé** (insert/update/delete sur la ligne concernée),
  après avoir déjà mis à jour le tableau `cuves` en mémoire (UI optimiste), via le
  helper `sbSync(promise, label)` qui alerte l'utilisateur en cas d'échec.
- **Alertes/levures/variables** (config partagée, éditée rarement, par un admin
  seulement) : pattern plus simple hérité de l'ancien code — `saveGlobalAlertes()`
  etc. font un `delete` de toute la table puis un `insert` complet de la liste en
  mémoire. **Piège rencontré** : les champs texte de ces panneaux ont un handler
  `oninput` "Silent" (censé juste mettre à jour la mémoire pour ne pas perdre le
  focus) qui, par erreur, appelait aussi la sauvegarde réseau à chaque frappe —
  combiné au pattern delete+insert, ça créait des écritures concurrentes qui
  s'écrasaient dans le désordre. Corrigé : les fonctions `...Silent` ne touchent
  plus qu'à la mémoire ; la sauvegarde réelle n'a lieu qu'au `blur`.

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
- `applyLayoutMode()` : appelée au chargement et au `resize` (debounce 200ms), mais
  **ne re-rend/ne change de vue que si l'état mobile/desktop a réellement changé**
  (`_lastMobileLiteState`) — sinon un simple `resize` (ex. ouverture du clavier
  virtuel Android) déclenchait un re-rendu complet qui effaçait les champs en cours
  de saisie (voir « Piège générique » plus bas).
- `renderAll()`/`refreshOtherViews()` : en mode mobile, s'arrêtent après
  `renderSaisieRapide()` — les vues desktop ne sont ni calculées ni affichées, donc
  Chart.js n'est jamais sollicité sur mobile.
- Chart.js et jsPDF (+autotable) sont injectés à la demande (`loadScriptOnce`,
  `ensureChartsLoaded()`, `ensurePdfLoaded()`), pas chargés en dur dans le `<head>`.
- La table de Saisie rapide masque la colonne Alertes sur mobile (`body.mobile-lite
  .col-alerts { display:none }`) et resserre les colonnes restantes, pour que le
  bouton d'action ("Terminer") ne déborde pas du cadre visible sur petit écran. La
  dernière colonne (action) est la plus comprimée : police réduite (~10.5px) et
  libellé "Terminer" caché (`.action-label { display:none }`, icône ⏹ seule) — le
  bouton de suppression d'une mesure garde lui une date courte (`JJ/MM`) car
  l'information reste utile. Vérifié sans débordement jusqu'à 360px de large.
- `#btn-admin-settings` reste masqué en mode mobile allégé quel que soit
  `currentIsAdmin`, via une règle CSS `body.mobile-lite #btn-admin-settings {
  display:none !important }` qui prime sur le `style.display=''` posé par
  `onAuthenticated()` — le panneau ⚙ Paramètres est volontairement réservé à la
  version PC.

### Saisie vocale (Android uniquement)

Le flux actuel (après plusieurs itérations, voir Historique) : **toucher le nom
d'une cuve** dans la Saisie rapide pour la cibler, puis dicter « densité … » et/ou
« température … » — pas de mot-clé de validation à dire, corriger = retoucher la
cuve et redicter (écrase directement les champs).

- Détection : `_voiceSupported = !!(window.SpeechRecognition || window.webkitSpeechRecognition)`.
  Le bouton micro (`#voice-input-block`) n'est visible que si supporté **et** en
  mode mobile allégé (`updateVoiceButtonVisibility()`).
- `selectVoiceCuve(ci)` : au tap sur le nom d'une cuve, la désigne comme cible
  (`_voiceCurrentCi`), surligne la ligne (`setVoiceActiveRow`), démarre le micro si
  besoin (sans interrompre une écoute déjà en cours).
- `startVoiceCapture()` : reconnaissance **continue** (`continuous: true`, reste
  active entre plusieurs cuves) avec **4 alternatives** par phrase
  (`maxAlternatives`) — `handleVoiceResult()` teste chaque alternative jusqu'à en
  trouver une interprétable, au lieu de se fier aveuglément à la meilleure
  hypothèse du moteur.
- `findCuveByVoice()` : recherche le nom de cuve actif le plus long, en tant que
  **mots entiers bornés** (pas simple sous-chaîne — sinon "Cuve 1" matche à tort
  dans "Cuve 12").
- `convertFrenchNumberWordsToDigits()` / `parseFrenchNumberWords()` : convertit les
  nombres dictés en toutes lettres ("douze", "quatre-vingts") en chiffres avant le
  reste du traitement.
- `normalizeVoiceSuffixWords()` : corrige les homophones probables des suffixes de
  cuves en doublon ("ter" entendu "terre", etc. — voir `SUFFIXES_DOUBLON`).
- `extractVoiceNumber()` : regex après les mots-clés « densité » / « température »
  ou « degrés ».
- **Densité** : la valeur dictée (ex. "1080") est reportée telle quelle dans le
  champ, sans conversion — voir la section densité plus haut.
- **Pas d'enregistrement automatique** : les champs de la ligne ciblée sont remplis,
  l'utilisateur doit toujours cliquer sur « Enregistrer la saisie »
  (`saveSaisieRapide()`) — tolérance aux erreurs de reconnaissance.
- **Piège navigateur** : `recognition.start()` peut lever une exception synchrone
  sur certains navigateurs (observé sur Chrome Android, pas sur Samsung Internet —
  typiquement permission micro non accordée) plutôt que de la signaler via
  `onerror`. `startVoiceCapture()` et `selectVoiceCuve()` l'encapsulent dans un
  `try/catch` pour que ça n'empêche jamais la sélection tactile de fonctionner.

### Panneau Admin (⚙ Paramètres)

Plus de mot de passe codé en dur : le bouton n'est visible que si
`currentIsAdmin === true` (chargé depuis `profiles.is_admin` à la connexion).
`showAdminPanel()` ouvre directement le contenu (plus d'étape « code admin »).
**Réservé à la version PC** : même pour un compte admin, le bouton reste masqué en
mode mobile allégé (voir « Vue mobile allégée » ci-dessus) — accéder aux Paramètres
se fait depuis un écran plus large.

### Identité visuelle

- Logo Groupe ICV en `assets/logo-icv.jpg`, affiché en en-tête (`.header-logo`) et
  sur l'écran de connexion (`.login-logo`).
- Palette dérivée du logo, définie en variables CSS dans `:root` : `--c-brand`
  (#5A1852, aubergine — actions principales, onglet actif, focus), `--c-accent`
  (#A3186E, magenta) et `--c-accent-2` (#3C6E68, sarcelle) — ces deux derniers
  servent surtout à la barre dégradée sous l'en-tête/le login (`.brand-bar`,
  `.login-box::before`) et à la palette catégorielle des graphiques (`PALETTE`,
  une couleur par cuve). Les couleurs sémantiques d'alerte (`--c-amber`, `--c-red`,
  `--c-blue`, `--c-green*`) sont **restées inchangées** — volontairement découplées
  de la marque pour ne pas mélanger identité visuelle et statut (ok/lent/stop/rapide).

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
- Les branches de travail fusionnées (`reset-baseline`, `feature/supabase-auth`,
  `feature/mobile-lite`, `feature/voice-input`) existent toujours sur GitHub
  (suppression bloquée par une protection de l'environnement Claude Code lors de la
  session — à supprimer manuellement si souhaité).

## Leçons génériques (réutilisables sur d'autres projets)

Ces points ne sont pas spécifiques à cette app — ce sont des pièges rencontrés
pendant le développement qui valent la peine d'être vérifiés d'emblée sur un futur
projet avec des caractéristiques similaires (SPA vanilla JS, mobile web, saisie
vocale, backend Supabase/REST) :

- **Un handler de `resize` qui re-rend l'UI doit vérifier qu'un état a *réellement*
  changé avant d'agir.** Sur mobile, l'ouverture du clavier virtuel déclenche un
  `resize` même sans changement de layout logique. Un re-rendu inconditionnel à
  chaque `resize` peut effacer des champs de formulaire en cours de saisie.
- **Un pattern de sauvegarde "delete tout + insert tout" ne doit jamais être
  déclenché à chaque frappe (`oninput`).** Plusieurs écritures concurrentes sur une
  table entière peuvent s'écraser dans le désordre selon l'ordre d'arrivée des
  réponses réseau (pas l'ordre d'envoi) — perte de données silencieuse. Ne
  sauvegarder qu'au `blur`/à une action explicite, ou passer à des upserts ciblés.
- **`SpeechRecognition.start()` peut lever une exception synchrone selon le
  navigateur** (Chrome vs Samsung Internet observés différents) au lieu de passer
  par `onerror`. Toujours encapsuler dans un `try/catch`, et s'assurer qu'un échec
  du micro n'empêche pas le reste d'une fonction UI de s'exécuter.
- **Le matching de texte libre (reconnaissance vocale, recherche) doit être borné
  par mots entiers, pas par sous-chaîne.** Une entité courte ("1", "A") matche
  presque toujours à tort à l'intérieur d'une entité plus longue partageant le même
  préfixe ("12", "AB").
- **Changer la convention/l'échelle d'une valeur déjà persistée est un projet en
  deux parties : le code ET les données existantes.** Mettre à jour uniquement le
  code laisse les anciennes lignes dans l'ancienne échelle (silencieusement fausses
  à l'affichage/aux calculs) tant qu'une migration explicite n'a pas été faite —
  et tout seuil/formule configuré par un utilisateur référençant cette valeur doit
  être revu manuellement, le code ne peut pas deviner l'intention.
- **Un garde-fou de plausibilité (ex. "cette valeur ne peut physiquement pas être
  sous X") est plus robuste qu'une conversion implicite basée sur la présence d'un
  séparateur décimal** pour attraper les erreurs de saisie par habitude (ex. virgule
  tapée par réflexe de notation scientifique).
- **Une fonctionnalité de confirmation/validation ajoutée pour compenser un manque
  de fiabilité (ici : contrôle vocal "validé" pour compenser une reconnaissance de
  cuve imparfaite) devient souvent obsolète une fois la fiabilité résolue à la
  racine (ici : sélection tactile).** Vérifier périodiquement si les couches de
  sécurité ajoutées tôt sont encore nécessaires, plutôt que de les accumuler.
- **Avec un header collant (`position: sticky`), tout saut d'ancre (`<a href="#id">`
  natif ou `scrollIntoView({block:'start'})`) atterrit avec le haut de la cible
  caché sous le header**, donnant l'impression d'un défilement imprécis. Compenser
  avec un offset (`scroll-margin-top` fixe, ou mesure dynamique de la hauteur du
  header au moment du clic si cette hauteur varie). **Si plusieurs éléments sticky
  sont empilés** (ex. un header puis une barre de sous-navigation elle-même sticky
  juste en dessous), l'offset doit additionner la hauteur de *tous* les éléments
  empilés, pas seulement du premier — sinon la cible reste cachée sous le second.
