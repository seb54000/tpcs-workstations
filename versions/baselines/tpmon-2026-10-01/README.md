# TP monitoring — inventaire réel du 1er octobre 2026

Inventaire AWS complété depuis le Mele ; manifests LGTM et helper figés dans les dépôts. Aucun changement appliqué à la stack en cours.

Périmètre : cluster00 / eks-training-00, namespace vm00, stack créée par le helper LGTM.

## Infrastructure observée

- EKS : `{"version": "1.36", "platformVersion": "eks.14", "status": "ACTIVE"}`.
- Nœuds : 6, tous Ready : True.
- Kubernetes nœuds : v1.36.4-eks-f4fc4f1 ; OS : Amazon Linux 2023.12.20260918 ; runtime : containerd://2.2.7+unknown.
- Chart cert-manager-v1.20.2 ; application v1.20.2 ; état deployed.
- Chart ingress-nginx-4.15.1 ; application 1.15.1 ; état deployed.

## Images effectivement exécutées dans vm00

| Référence demandée | Identité exécutée |
|---|---|
| `896025786589.dkr.ecr.eu-west-3.amazonaws.com/tpmon-demoboard:api-v1` | `896025786589.dkr.ecr.eu-west-3.amazonaws.com/tpmon-demoboard@sha256:5140b4f7a58121bcffeec202ef610f253173703814028381d9d45dfd00b0eb85` |
| `896025786589.dkr.ecr.eu-west-3.amazonaws.com/tpmon-demoboard:front-v2` | `896025786589.dkr.ecr.eu-west-3.amazonaws.com/tpmon-demoboard@sha256:22ca953f428235a40d7547b160b54e472007259488ea2e54ed11afcba45b3202` |
| `896025786589.dkr.ecr.eu-west-3.amazonaws.com/tpmon-demoboard:worker-v1` | `896025786589.dkr.ecr.eu-west-3.amazonaws.com/tpmon-demoboard@sha256:655b4921ddcf4989e1c703396b69ec5eb739dad36e7c816fe2a204adf63e2662` |
| `bitnami/kubectl:latest` | `docker.io/bitnami/kubectl@sha256:f7f9e4f64d9e114650c115a4ac6fd383394b3d494061a8f17b1a0f6c8d55bc25` |
| `grafana/otel-lgtm:latest` | `docker.io/grafana/otel-lgtm@sha256:b966ea107831d526d9eb8fe4d2d86c9e5731392fad9dce8296bcf2072031f07c` |
| `postgres:15` | `docker.io/library/postgres@sha256:724292da1f2e50bdccfc3302ce75bbba7f4a6076701b588cc795fcac65683550` |
| `python:3.12-alpine` | `docker.io/library/python@sha256:4c47124a8391cb7a9f571164147d154777cf012a4ece5f86097130d7a4478111` |
| `redis:7` | `docker.io/library/redis@sha256:c6eabf748fc7a61dbb5a705c78bcf3d6377b1127a97d0ce965c11c44ba46896f` |

## Limites et preuves

Les fichiers JSON voisins contiennent les versions, états et identités des images, sans kubeconfig, Secret ni variables applicatives. Les noms de nœuds et références de registre y figurent. Les lectures AWS refusées depuis docs ont été complétées depuis le Mele, sans élargir les permissions de docs.
Un pod Ready et un chart deployed ne prouvent pas la collecte des métriques, logs et traces : ces tests ne sont pas encore effectués. Les autres exercices monitoring ne sont pas encore inventoriés.
Aucun commit ni push. Message proposé : `chore: figer les images LGTM et Demoboard du TP monitoring`.

## Complément et gel préparé

Les lectures AWS depuis le Mele ont réussi sans modification IAM :
- aws-ebs-csi-driver : **v1.66.0-eksbuild.1**, ACTIVE.
- vpc-cni : **v1.22.4-eksbuild.3**, ACTIVE.
- ng-00-az1 : Kubernetes 1.36, release AMI **1.36.4-20260923**, type **AL2023_x86_64_STANDARD**.
- ng-00-az2 : Kubernetes 1.36, release AMI **1.36.4-20260923**, type **AL2023_x86_64_STANDARD**.
- ng-00-az3 : Kubernetes 1.36, release AMI **1.36.4-20260923**, type **AL2023_x86_64_STANDARD**.

`images.lock.json` est la référence de contrôle. Les manifests EKS et Compose
LGTM du dépôt monitoring fixent LGTM/Promtail (et Python pour Compose). Le helper
fige aussi PostgreSQL, Redis, kubectl et les trois images Demoboard dans ses deux
manifests générés (v1 et scaled). Le job de rafraîchissement Grafana fixe Python.
Le helper reste compatible avec un clone étudiant contenant les anciens tags :
il remplace ces références et refuse toute image flottante avant le premier apply.

Le mode partagé exige les digests capturés dans le dépôt ECR sélectionné. Aucun
fallback vers un tag mutable ni rebuild automatique. Le mode local, explicitement
choisi, construit une nouvelle candidate et déploie les digests de ses nouveaux
builds ; il ne prétend pas reproduire la référence du 1er octobre.

**Promtail n'était pas déployé** lors de la vérification complémentaire (aucun
DaemonSet Promtail). Son digest linux/amd64 a été résolu au registre pour le tag
3.6.1, pas validé en exécution. Voir `promtail-registry.json`. Son déploiement et
la réception des logs sont des points obligatoires du prochain test.

### À retester, sans l'avoir exécuté pendant cette intervention

1. Mettre à disposition les changements des deux dépôts sur une VM de test,
   y compris le nouveau helper de rafraîchissement Grafana.
2. Vérifier que les digests ECR capturés existent toujours. Les dépôts ECR actuels
   sont destructibles avec leur contenu : conserver/exporter les images avant
   destruction. Un simple rebuild n'est pas une restauration de ces artefacts.
3. Lancer le helper avec accord pour le déploiement ; vérifier démarrage des
   workloads et Promtail, bootstrap Grafana, API, métriques, traces et logs.
4. Tester ensuite le manifeste scaled et le mode de build local si nécessaire.

Le code Terraform EKS/nœuds/addons n'est pas figé dans cette étape : ses versions
sont désormais toutes connues et enregistrées, mais leur application constituerait
un chantier de provisioning distinct. Les outils des VM et les autres exercices
monitoring (classique, Golden Signals, OpenTelemetry Demo) restent hors de ce gel.
Aucune mise à jour de sécurité ou migration de composant n'est incluse.

## Contrôles locaux réalisés

`~/ansiblevenv/bin/python versions/scripts/check-tpmon-pins.py` : syntaxe Bash
(des deux helpers rendus), YAML Compose/manifests, génération des variantes v1
et scaled, adaptation namespace/DNS, références exclusivement par digest et
refus d'une nouvelle image flottante : OK. `git diff --check` : OK dans les deux
dépôts. Aucun build, apply, commit ou push pendant cette étape.
