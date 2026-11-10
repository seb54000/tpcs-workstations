# Politique APT des sessions

Depuis octobre 2026, les inventaires `apt-versions.json` et `apt.json` restent des
références historiques, et non des listes exhaustives de versions imposées.
Les fichiers `apt-constraints.json` définissent les branches supportées.

- Postes Ubuntu 22.04 : Ansible 10.x / core 2.17.x, XRDP 0.9.x,
  xorgxrdp 0.2.x et métapaquet XFCE 4.16 ; docs : nginx 1.18.x et PHP 8.1.x.
- Demoboard Ubuntu 24.04 : Redis 7.0.x (serveur et outils), PostgreSQL 16
  (métapaquets, client et libpq compris), Node.js 22.x et nginx 1.24.x.
- Les autres paquets suivent les dépôts configurés de la distribution LTS.
  Cette politique suppose de conserver ces dépôts ; ajouter un PPA doit être revu.

La branche autorisée reçoit la priorité 990 ; les autres versions du même paquet
sont interdites. Aucune préférence pour une ancienne révision, aucun downgrade
forcé. Les installations restent en `state: present` : une version compatible
installée est conservée, sauf ajustement de dépendances nécessaire. Un runtime
installé hors branche est signalé avant installation, sans migration automatique.
Les préférences ne constituent pas une borne minimale de sécurité.

Le prochain passage des tâches de baseline réécrit **le même fichier** de
préférences et retire ainsi les anciens verrous exhaustifs. Il faut passer par
ces tâches avant de reprendre une installation ; commencer directement à la tâche
Redis ne suffit pas. Les fichiers des clones étudiants existants ne sont pas
synchronisés automatiquement par le provisioning : préserver leur travail et
appliquer une mise à jour ciblée. Synchroniser le dépôt IaC et son overlay lors
chaque maintenance tant que cet overlay est distribué.

Le filtre des postes vérifie toujours que les paquets directs sont connus, mais
ne demande plus `paquet=version`. Demoboard vérifie la branche Node.js 22 au lieu
d'une révision exacte et ne désinstalle plus Node.js à chaque passage.

Snap, pip/npm, Terraform, images Docker, références Git et AWS CLI ne sont pas
modifiés dans ce lot. Leurs verrous peuvent encore nécessiter une maintenance.
Avant une session : tester un poste et Demoboard, relever les versions effectives,
puis conserver ce résultat comme référence. Les correctifs réduisent les risques
de disponibilité sans garantir l'absence de régression.
