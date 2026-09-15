# Terraform depuis plusieurs PC et comptes AWS

Le code reste sur GitHub. Les states sont partagés dans le projet privé
[tpcs-workstations-tfstates](https://gitlab.multiseb.com/seb54000/tpcs-workstations-tfstates)
(ID 5). Un state décrit une plateforme TP ; le nom inclut l'ID du compte AWS :
`tpcs-workstations-123456789012`. Changer de clé d'accès dans le même compte ne
change pas le state. Deux comptes différents ont deux states distincts.

## Préparer le clone

Sur le MeLE, le rôle Ansible `tpcs_workstation` installe les outils et clone la
branche initiale `fixes-tpmon`. Il conserve les modifications et la branche des
clones existants. Sur un autre PC, installer les prérequis du README (Terraform,
AWS CLI v2, Python 3, jq, Ansible et les collections AWS ; Bash et `flock` pour
les scripts). Le contrôleur est prévu pour Linux.

Copier le fichier de KeePass dans `terraform-infra/credentials-setup.sh`, puis
`chmod 600 terraform-infra/credentials-setup.sh`. Il doit exporter les credentials
AWS habituels et les valeurs GitLab copiées depuis le MeLE :

```bash
export GITLAB_TFSTATE_URL='https://gitlab.multiseb.com'
export GITLAB_TFSTATE_PROJECT_ID='5'
export GITLAB_TFSTATE_PROJECT_PATH='seb54000/tpcs-workstations-tfstates'
export TF_HTTP_USERNAME='<compte bot du jeton Terraform>'
export TF_HTTP_PASSWORD='<jeton de projet, scope api>'
export GITLAB_TFSTATE_TOKEN_EXPIRES_AT='2027-03-14'
```

Ces variables sont portables : les scripts ne chargent aucun fichier propre au
MeLE. `CREDENTIALS_FILE=/chemin/credentials-setup.sh` permet de choisir un autre
fichier de secrets. Les jetons sont partagés entre les PC qui les utilisent ;
renouveler un jeton impose d'actualiser KeePass et ses copies. Le jeton Terraform
permet déjà lecture et écriture ; il ne faut pas utiliser le jeton de sauvegarde
à sa place, car ce dernier ne peut pas verrouiller un state.

La paire SSH `terraform-infra/key` / `key.pub` reste nécessaire pour les VM.
Pour reprendre la même plateforme depuis un autre PC, copier aussi cette paire
de manière privée. Sa future intégration au fichier de credentials est un sujet
distinct ; le backend partagé ne transporte pas les clés SSH locales.

## Utilisation habituelle

Depuis la racine du dépôt :

```bash
./tf.sh context       # STS + contrôle GitLab ; affiche compte, state et répertoire
./tf.sh init          # initialise uniquement le backend et les providers
./tf.sh validate
./tf.sh plan          # prépare un plan ; peut lire les API AWS/Cloudflare
./tf.sh show-plan     # consulte le plan du compte courant (peut contenir des secrets)
./tf.sh apply-plan    # applique ce plan ; cette commande modifie l'infrastructure
./tf.sh output -json  # outputs du state courant ; peuvent contenir des secrets
./tf.sh state list
```

Les helpers habituels sont adaptés :

```bash
./01-prepare_platform.sh full   # Terraform puis Ansible
./01-prepare_platform.sh tf -auto-approve
./01-prepare_platform.sh ao -t student
./02-destroy_platform.sh       # nettoyages EKS puis Terraform destroy
```

`./tf.sh apply` effectue directement le plan et l'application habituels, avec
confirmation Terraform. `./tf.sh apply-plan` applique un plan déjà enregistré,
sans nouvelle confirmation Terraform. Ne pas confondre ces commandes avec une
simple consultation. `./tf.sh destroy` ne fait pas les nettoyages EKS : préférer
`02-destroy_platform.sh` pour supprimer une plateforme complète.

Le playbook `post_install.yml` lit les outputs via `tf.sh`. Les helpers de nettoyage
EKS et de diagnostic lisent également le backend sélectionné ; la destruction
initialise le backend avant de capturer ses outputs. Le contrôle des states
Terraform créés par les étudiants *dans leurs VM* reste un processus distinct.

## Changer de compte sans mélanger les states

1. Choisir les credentials AWS du compte voulu dans le fichier privé (ou choisir
   un autre `CREDENTIALS_FILE`). Pour des credentials temporaires, inclure leur
   `AWS_SESSION_TOKEN` et ne pas conserver un token de session d'un autre profil.
2. Exécuter `./tf.sh context` et vérifier l'ID affiché avant un apply/destroy.
3. Utiliser les commandes habituelles ; aucun transfert de state ne se produit.

Le helper demande l'identité à **AWS STS** à chaque invocation. Il refuse de
continuer si STS échoue. Le provider AWS reçoit aussi `allowed_account_ids`
pour refuser un compte différent de celui sélectionné. Une opération composée
(préparation/destruction) fixe `TPCS_EXPECTED_AWS_ACCOUNT_ID` pour ses sous-étapes :
un changement de credentials vers un autre compte pendant le run le fera échouer.

Les fichiers locaux sont isolés sous :

```text
terraform-infra/.tpcs/<empreinte-serveur-et-projet>/<compte-AWS>/
  data/       # TF_DATA_DIR : configuration locale du backend et providers
  plans/      # plans et métadonnées compte/backend/empreinte du fichier
  recovery/   # copies des anciens states lors d'une migration explicite
```

Deux PC utilisant le même compte et le même projet partagent le même state et
ses verrous GitLab. Dans un clone, un verrou local empêche deux commandes Terraform
simultanées sur le même compte ; un second protège l'initialisation commune des
providers. Réessayer après la fin de l'opération qui détient le verrou.

Les plans sont privés (`umask 077`) et ne doivent pas être versionnés.
`./tf.sh plan -out=essai.tfplan` puis `./tf.sh apply-plan essai.tfplan` utilisent
le répertoire du compte courant. Un chemin extérieur ou un plan copié d'un autre
compte/backend est refusé ; son empreinte doit aussi correspondre aux métadonnées.
Les plans restent propres au PC : les recréer après changement de clone.

Le helper réinitialise les adresses `TF_HTTP_*` et `TF_DATA_DIR` plutôt que de
réutiliser ceux d'un ancien shell. Il refuse les workspaces non-default, les
`TF_CLI_ARGS` implicites et les options qui désactivent le verrouillage ou imposent
un autre state/backend. Passer les options Terraform ordinaires explicitement.
Utiliser `tf.sh` plutôt que `terraform` directement pour bénéficier de ces contrôles.

Le lockfile `.terraform.lock.hcl` est maintenant versionné pour conserver les
mêmes providers entre PC. `./tf.sh init -upgrade` les actualise volontairement ;
examiner le diff avant commit. L'isolation par compte ne sépare pas les ressources
Cloudflare : choisir des sous-domaines distincts pour des plateformes simultanées.

## Migrer un ancien state local, uniquement sur demande explicite

Aucun TP n'était actif sur le Samsung lors de la préparation du MeLE. Aucune
migration de ressources existantes n'a été faite automatiquement.

Si `terraform-infra/terraform.tfstate` existe, les commandes ordinaires bloquent
pour éviter de démarrer sur un backend vide. Après arrêt des autres contrôleurs
et vérification du compte auquel appartient le state :

```bash
./tf.sh migrate-local /chemin/terraform.tfstate --account 123456789012
```

Cette commande vérifie le compte via STS et exige que la destination soit absente.
Elle conserve une copie privée avec une empreinte SHA-256, prend le verrou GitLab,
vérifie de nouveau qu'aucune version n'est apparue, transfère le state puis contrôle
lineage, serial, ressources et outputs. Elle n'exécute aucun apply/destroy.
Un backend existant n'est pas écrasé.

Si le fichier source était le `terraform.tfstate` à la racine Terraform du clone,
il est déplacé dans `recovery/` après vérification réussie ; sinon le fichier
externe reste intact. Ne plus utiliser l'ancien state sur le Samsung après le
transfert. Une migration d'un autre backend distant nécessite une procédure
spécifique ; ne pas la confondre avec un changement de compte.

## Jeton de lecture et clé de sauvegarde dans KeePass

Le fichier privé du MeLE a été complété avec :

```bash
# Facultatif : consultation API en lecture seule ; futur helper du lot 4.
export GITLAB_TFSTATE_READ_TOKEN='<jeton read_api>'

# Secours : identité privée age, conservée dans KeePass, NON exportée.
GITLAB_TFSTATE_BACKUP_AGE_IDENTITY='AGE-SECRET-KEY-...'
export -n GITLAB_TFSTATE_BACKUP_AGE_IDENTITY
```

La première variable n'est pas nécessaire au fonctionnement de Terraform. La
seconde n'est transmise ni à Terraform ni aux processus enfants. Elle sert
uniquement à recréer le fichier de clé si le MeLE est perdu. Les sauvegardes
automatiques du MeLE continuent d'utiliser leurs fichiers gérés par Ansible ;
les variables du setup ne changent pas le timer et ne remplacent pas ses jetons.

Pour récupérer l'identité dans un fichier privé, depuis un shell ayant sourcé
le fichier de KeePass :

```bash
umask 077
mkdir -p -m 700 ~/.config/tpcs
# À exécuter pour une récupération, sans écraser une autre identité existante.
(set -o noclobber; printf '%s\n' "$GITLAB_TFSTATE_BACKUP_AGE_IDENTITY" > ~/.config/tpcs/gitlab-backup.agekey)
unset GITLAB_TFSTATE_BACKUP_AGE_IDENTITY
```

Le [guide GitLab](https://docs.multiseb.com/readme-gitlab.html) décrit les archives
chiffrées, leur rétention et le renouvellement des jetons. Garder cette identité
dans KeePass même si les states de TP sont éphémères : elle permet de récupérer
les states présents dans les archives et les secrets GitLab qu'elles contiennent.

## Contrôles et limites du lot 3

Le 15 septembre 2026 : identité du compte réel chargé sur le MeLE vérifiée,
initialisation et validation de la configuration réelle réussies, sans plan/apply
de ses ressources. Deux comptes simulés ont créé des states distincts dans le
vrai backend, avec création et application de plans ne contenant que des outputs
(0 ressource). Une migration locale explicite vers un troisième state a été
vérifiée. Les states temporaires ont été supprimés. Le second compte AWS réel
n'a pas été utilisé dans ces essais.

Tests unitaires : `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests`.
Ils couvrent séparation par compte, rotation des clés, backend hérité, identité
invalide, plans d'un autre compte, ancien state local et destination de migration
existante. Les tests d'intégration manuels utilisent le vrai GitLab et Terraform
avec trois identités AWS simulées et **aucun provider AWS** :

```bash
source terraform-infra/credentials-setup.sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/integration_backend.py
```

Ce test crée des states temporaires après vérification de leur absence et les
supprime à la fin. Les tests ne constituent pas une validation du provisioning
d'une classe réelle ni des credentials du second compte AWS. Le rappel quotidien
par mail et le helper listant tous les backends restent dans les lots suivants.
