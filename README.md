# Suivi de fermentation

Application de suivi de fermentation (cuves, densité, température, alertes) —
fichier unique `index.html` (HTML/CSS/JS, sans build).

## Roadmap

- [x] Authentification et stockage via Supabase (remplacement de `localStorage`)
- [x] Vue mobile allégée (Saisie rapide + création de cuve)
- [x] Saisie vocale sur Android (Cuve, Densité, Température)

Toutes les évolutions prévues sont livrées et fusionnées sur `main`. Le
développement se poursuit désormais par petits correctifs itératifs (voir
l'historique des commits), notamment autour de la précision de la saisie vocale.

## Configuration Supabase (à faire une seule fois)

1. Ouvrir le [SQL Editor](https://supabase.com/dashboard/project/gctvtjelleajwpcbkqqs/sql/new)
   du projet Supabase et exécuter le contenu de [`supabase/schema.sql`](supabase/schema.sql).
2. Créer un compte depuis l'application (email + mot de passe, bouton
   « Créer un compte » sur l'écran de connexion).
3. Dans le [Table Editor](https://supabase.com/dashboard/project/gctvtjelleajwpcbkqqs/editor),
   table `profiles`, passer votre ligne à `is_admin = true` pour accéder au panneau
   ⚙ Paramètres (référentiel de levures, variables calculées, alertes).
4. La création/suppression de comptes se fait ensuite depuis
   [Authentication → Users](https://supabase.com/dashboard/project/gctvtjelleajwpcbkqqs/auth/users).
