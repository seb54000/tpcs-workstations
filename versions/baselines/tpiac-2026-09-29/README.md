# Référence TP IaC — 29–30 septembre 2026

## Périmètre et preuves

Inventaire SSH en lecture seule du 29 septembre sur le contrôleur Mele, vm00 et access/docs (`tpcsonline.org`). Contrôle complémentaire APT/Snap de vm01 à vm12. La référence des postes est vm00 ; les différences du parc sont conservées dans `student-parity.json`.

Le provisioning du 29 septembre a réussi : 165 ressources créées ; recap Ansible access et vm00–vm12 sans échec ni inaccessible. Source : `/tmp/tpcs-workstations-prepare-20260929-074952.log` sur le Mele. Les logs bruts, états Terraform, inventaires AWS, IP, clés et credentials ne sont pas copiés dans cette référence.

Le formateur avait validé Demoboard puis détruit la stack. Le 30 septembre, son helper a recréé les 42 ressources mais s'est arrêté avant Ansible : SSH refusé sur le bastion encore en démarrage. Une reprise du playbook Ansible existant a été autorisée pour récupérer les versions applicatives. Voir la section de validation finale ci-dessous.

Ces observations constituent une référence fonctionnelle datée, pas une recommandation de versions récentes. Aucune migration ni harmonisation des versions entre les environnements n'est incluse.

## Versions des contrôleurs et postes

| Brique | Mele | vm00 | access/docs |
|---|---|---|---|
| OS | Ubuntu 24.04.3 LTS | Ubuntu 22.04.3 LTS | Ubuntu 22.04, même AMI |
| Python contrôleur | 3.12.3 | 3.10.12 | 3.10 (venv GDrive) |
| Terraform | 1.11.4 | 1.13.1 | 1.11.4 |
| AWS CLI | 2.36.45 | 2.37.5 | 2.37.5 |
| Ansible core | 2.18.12 | 2.17.14 système et helper | non utilisé comme contrôleur IaC |
| Distribution Ansible | 11.13.0 | 10.7.0 | — |
| Docker | hors référence de déploiement IaC | 29.8.0 / snap 3613 | 29.8.0 / snap 3613 |
| Compose | — | 5.5.1 | 5.5.1 |
| Node Exporter | — | 1.8.2 demandé par le provisioning | 1.8.2 demandé par le provisioning |

Providers infrastructure : AWS 4.67.0, Cloudflare 5.25.0, cloudinit 2.4.1, TLS 4.4.1 dans le lockfile existant. Provider Guacamole 1.4.1. Providers exercices IaC et Demoboard : AWS 6.66.0, relevé dans les deux lockfiles de vm00.

APT Ansible vm00 : `ansible=10.7.0-1ppa~jammy`, `ansible-core=2.17.14-1ppa~jammy`. Les dépendances Python du helper diffèrent volontairement de celles du Mele : boto3 1.28.49 / botocore 1.31.49 sur vm00 ; 1.37.38 / 1.37.38 sur Mele. Les deux environnements passent `pip check`.

Les paquets APT complets et leurs versions Debian sont dans `student-apt.tsv` et `docs-apt.tsv`; `apt-versions.json` est la représentation consommée par Ansible. Les snaps, bases et dépendances de contenu sont dans `*-snaps.txt` et `snap-versions.json`. Les extensions VS Code avec versions sont dans `student-vscode.txt`. Les fichiers `*-requirements.txt` incluent les dépendances transitives installées ainsi que pip/setuptools ; les collections sont inventoriées en JSON.

APT est identique sur les 12 autres postes lors du relevé. Quelques postes ont déjà rafraîchi SSM Agent (révision 13349 au lieu de 7628) et LXD (40911 au lieu de 24322) : le parc n'est pas totalement identique à vm00. Aucun retour arrière n'a été effectué.

## Services docs observés

| Service | Version exécutée | Référence immuable |
|---|---|---|
| Grafana | 13.2.2 | digest enregistré dans `group_vars/all.yml` |
| Prometheus | 3.15.0 | idem |
| Guacamole / guacd | images 1.6.0 | idem |
| PostgreSQL Guacamole | image 15.2-alpine | idem |
| nginx Guacamole | 1.31.6 | idem |
| nginx système | paquet 1.18.0-6ubuntu14.21 | inventaire APT docs |
| PHP FPM | paquet 8.1.2-1ubuntu2.26 | inventaire APT docs |
| certbot | 5.8.0 / snap 5893 | inventaire Snap docs |

Les six conteneurs étaient en exécution ; pages publiques docs et access : HTTP 200. Ces contrôles ne remplacent pas une session RDP interactive. Les dépendances du venv GDrive sont capturées ; aucun export documentaire supplémentaire n'a été lancé.

Guacamole Compose est figé au commit `7b5cc1614d56488a7d106cca81b9218688a077ce`. L'image utilisée pour initialiser sa base est également figée par digest ; le script upstream reste intact.

## Sources et activation du gel

- `tpcs-workstations` avant modifications : `3436d5f74089d04ea24ad3b1f65fda4f4da48916`.
- `tpcs-iac` : `97bac37784cfe719c86589b6a3681d1698173f4d`, puis overlay de gel versionné ici.
- `tpcs-demoboard` : `e63f58b451b947bed13cd91db672ac398551d280`. Ses 35 fichiers suivis sur vm00 ont été comparés par SHA-256 et sont identiques au dépôt local ; preuves dans `demoboard-source.sha256`.

Le profil `tpcs_baseline_enabled` s'active par défaut uniquement pour `tp_names == ['tpiac']`. Il fixe les références Git, les versions demandées à APT, les snaps/révisions et leur refresh, AWS CLI sur les postes, les images docs, le venv GDrive et les extensions VS Code. Les snaps d'une autre révision provoquent un arrêt explicite plutôt qu'une migration/downgrade implicite. Les nouveaux paquets non présents dans l'inventaire APT restent installables pour les exercices ; les paquets capturés ont une version imposée.

Le dépôt `tpcs-iac` contient aussi les mêmes locks pour une utilisation directe. Comme aucun commit/push n'est effectué pendant cette intervention, `tpcs-iac-overlay/` transporte ces fichiers sur un clone étudiant neuf du commit de référence. Cet overlay n'est pas appliqué sur une référence Git explicitement surchargée, ni sur un répertoire étudiant existant. Lors d'une future maintenance, synchroniser les fichiers entre le dépôt IaC et cet overlay, puis idéalement passer au nouveau commit publié et retirer l'overlay une fois celui-ci inclus dans le commit sélectionné.

Un changement de référence Git ne supprime plus automatiquement un répertoire étudiant existant. Il faut une VM neuve ou une décision explicite après sauvegarde du travail. Ne pas relancer le provisioning complet sur le cours en cours pour appliquer le gel.

Sur le Mele, `requirements` sélectionne l'environnement Python capturé. Vérification sans modification :

```sh
~/ansiblevenv/bin/python versions/scripts/check-tpiac-baseline.py
```

Ce contrôle vérifie Python, Terraform, AWS CLI, paquets Python et collections effectivement visibles. Il n'installe rien. Ne pas remplacer une autre installation existante avant d'avoir examiné les écarts ; un venv séparé peut être créé à partir du fichier de référence.

## Conservation, limites et prochaines mises à jour

Un numéro exact garantit la sélection, pas la disponibilité éternelle du paquet. Les paquets APT, Snap, roues Python, VSIX, archives Terraform/AWS CLI et images doivent être conservés dans un stockage d'artefacts si une reconstruction indépendante des dépôts publics est requise. Les binaires ne sont pas ajoutés au Git. Si un artefact disparaît, le provisioning doit échouer plutôt que choisir une nouvelle version silencieusement.

Les préférences APT et holds Snap persistent après installation. Désactiver le profil dans Ansible ne les supprime pas d'une VM déjà configurée : prévoir une étape explicite de migration, ou reconstruire une VM. Les mises à jour de sécurité des composants gelés doivent être étudiées hors séance ; aucune politique de mise à jour automatique ne peut simultanément garantir ces versions exactes.

Le gel complet du système du Mele est hors périmètre : l'environnement de contrôle est enregistré et contrôlable, son OS n'est pas modifié. Les VM de session ne sont pas modifiées par la préparation de ces fichiers.

Pour une future évolution : comparer les versions candidates avec cette référence, examiner les notes officielles et changements pédagogiques, présenter un plan de tests et retour arrière, obtenir l'accord avant déploiement long, puis enregistrer une nouvelle référence sans écraser celle-ci. Ne pas faire de commit/push automatiquement.

## Demoboard : relevé et validation du 30 septembre

La reprise Ansible a réussi sur les huit hôtes : aucun échec ni inaccessible.
Les deux builds frontend `npm ci` puis `npm run build` ont réussi. Log conservé
sur vm00 : `~/tpiac-demoboard-ansible-20260930.log`.

| Composant | Version effectivement observée |
|---|---|
| Python | 3.12.3 |
| Node.js / npm | 22.23.3 / 10.9.9 |
| Vue / Vite / plugin Vue | 3.5.30 / 8.0.16 / 6.0.7 |
| nginx | 1.24.0 Ubuntu |
| PostgreSQL | 16.15 |
| Redis | 7.0.15 |
| AWS CLI sur les frontends | 2.37.6 (les postes restent à 2.37.5) |

`demoboard-runtime-20260930.json` contient l'inventaire APT complet par hôte,
les dépendances Python transitives et les résultats `pip check` (tous OK).
Le dépôt IaC et son overlay fixent désormais ces paquets et dépendances ; les
images Docker des autres TP ne sont pas modifiées.

`demoboard-smoke-20260930.json` prouve : HTTP 200 frontend, JavaScript, monitor et
health API 1.0.0 ; création et modification d'une tâche ; traitement Redis/worker
jusqu'à completed ; suppression de la tâche de test et vérification du 404.
La stack peut être détruite après ce relevé : aucune donnée nécessaire ne reste
uniquement sur ces VM. Aucun test de redémarrage/persistance ni navigateur
interactif n'a été exécuté.

Les modifications de gel ne sont pas encore validées par un reprovisionnement
complet depuis zéro. Le succès fonctionnel porte sur les versions capturées et
le playbook précédent ; les nouveaux verrous sont contrôlés localement. Aucun
gel n'a été appliqué à vm00/docs ni aux autres postes pendant la séance.

## Contrôles des fichiers de gel

- 41 tests existants et nouveaux réussis avant regroupement ; 4 tests dédiés au
  gel rejoués après déplacement sous `versions/`, réussis.
- Validation Terraform du provisioning avec les providers déjà présents : OK.
- Syntaxe YAML/Python/Ansible, rendu des Compose avec/sans profil, syntaxe Bash
  du helper, cohérence de l'overlay avec tpcs-iac, `git diff --check` : OK.
- Contrôle du Mele contre la référence Python/outils/collections : OK.
- Aucun commit ni push. Aucun nouveau Terraform apply effectué par l'assistant.
