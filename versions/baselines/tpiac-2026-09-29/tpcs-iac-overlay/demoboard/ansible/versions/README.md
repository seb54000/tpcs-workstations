# Référence Demoboard IaC — 30 septembre 2026

Versions observées après un déploiement réussi sur les huit VM, puis test de
création/modification, traitement worker et suppression d'une tâche : Python
3.12.3, Node 22.23.3, npm 10.9.9, nginx 1.24.0, PostgreSQL 16.15, Redis 7.0.15,
AWS CLI 2.37.6. Vue 3.5.30 / Vite 8.0.16 / plugin Vue 6.0.7 via le lock npm.

`apt.json` est consommé par le premier play de `setup.yml`. Les locks Python
sont copiés dans `/etc/demoboard` et utilisés par les rôles API/worker. Les
préférences APT sont persistantes ; une mise à jour doit les modifier explicitement.
`capture_versions.py` collecte les versions sans exporter de credentials.

Terraform 1.13.1, provider AWS 6.66.0 ; helper Ansible 10.7.0 / core 2.17.14.
Source Demoboard validée : e63f58b451b947bed13cd91db672ac398551d280.
Le rapport et les preuves complets sont dans le dépôt tpcs-workstations :
`versions/baselines/tpiac-2026-09-29/README.md`.

Les versions sont fixées, mais les artefacts restent fournis par leurs dépôts
publics : conserver un miroir si leur disponibilité à long terme est nécessaire.
Le nouveau gel reste à valider par une création complète autorisée ; aucun
commit/push ni reprovisionnement des postes étudiants n'a été effectué.
