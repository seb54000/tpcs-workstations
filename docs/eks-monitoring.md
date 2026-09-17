# Monitoring global EKS

Le dashboard provisionné **AWS EKS — Vue globale TP** (`/d/tpcs-eks-overview`)
présente les clusters, les groupes managés, les nœuds présents et souhaités par
groupe, les états et problèmes de santé AWS, le CPU et les contrôles EC2 par VM.
Les filtres région et cluster permettent de parcourir plusieurs clusters.
Le total des clusters est régional ; les autres panneaux d’inventaire suivent le filtre cluster.

L’exporteur EC2 existant inclut déjà Paris (`eu-west-3`), mais expose uniquement
l’inventaire : il ne fournit pas la consommation CPU des instances.
Le nouvel exporteur utilise les API EKS et Auto Scaling pour rattacher les instances
aux groupes, puis CloudWatch pour les métriques EC2. La collecte détaillée utilise aussi
l’API Kubernetes en lecture avec le rôle AWS de la VM access déjà autorisé par `eks_shared`.

## Installation

Appliquer la modification Terraform de la policy du rôle `access` avec le workflow
habituel du dépôt (plan puis apply), puis relancer le rôle Ansible `access_docs` :

```sh
ansible-playbook post_install.yml -t access_docs
```

La policy ajoute seulement les lectures `eks:ListNodegroups`,
`eks:DescribeNodegroup`, `autoscaling:DescribeAutoScalingGroups` et
`cloudwatch:GetMetricStatistics`, `ec2:DescribeVolumes`, `ec2:DescribeSnapshots`
et `ec2:DescribeNetworkInterfaces` aux autorisations existantes.
Les credentials du rôle d’instance sont utilisés par AWS CLI ; aucun secret n’est ajouté.
Python 3.10+ et AWS CLI doivent être présents sur la VM docs (Ubuntu 22.04 du TP).

Un cron root toutes les cinq minutes écrit atomiquement
`/var/www/html/json/aws_eks_metrics.prom`. Un verrou empêche les collectes concurrentes.
Prometheus lit `/json/aws_eks_metrics.prom` via le job `aws_eks_exporter`.
Ansible redémarre Prometheus si sa configuration change ; Grafana découvre le JSON
via son provisioning existant. Attendre le premier cron pour voir les données.

Par défaut, seule Paris est interrogée, comme le provider EKS Terraform. Pour étendre :

```sh
ansible-playbook post_install.yml -t access_docs \
  -e '{"eks_monitoring_regions":["eu-west-3","eu-west-1"]}'
```

## Lecture et limites

- `aws_eks_collection_success` distingue l’inventaire et CloudWatch : `0` = erreur,
  `1` = appels réussis. Une erreur d’inventaire supprime les valeurs de la région,
  sans les remplacer par un faux zéro. Une erreur CloudWatch conserve l’inventaire.
- L’âge de collecte détecte un cron arrêté, même si Nginx continue à servir le fichier.
  Si le job Prometheus est inaccessible, vérifier aussi `up{job="aws_eks_exporter"}`.
- Les points CPU sont des moyennes CloudWatch sur cinq minutes. Les contrôles EC2
  utilisent le maximum sur cette période. Le dashboard masque les points de plus
  de quinze minutes ; une métrique absente n’est pas assimilée à zéro.
- Les nœuds comptés sont les instances présentes dans les ASG des **groupes managés**,
  y compris les transitions. Fargate, Karpenter et les groupes autogérés sont exclus.
- `ACTIVE` et une santé ASG correcte ne prouvent pas que les pods sont sains ou que
  les nœuds sont Kubernetes `Ready`. La collecte détaillée compte les phases des pods,
  mais ne mesure pas leur readiness ni la santé applicative.
- Collecte : appels d’inventaire par cluster/groupe, puis deux appels CloudWatch
  par instance toutes les cinq minutes. Pour une grande flotte, préférer une collecte
  CloudWatch par lots ; des frais API peuvent s’appliquer.

Dashboard Kubernetes existant pour une future collecte dans les clusters :
[Grafana Kubernetes / Views / Nodes](https://grafana.com/grafana/dashboards/15759-kubernetes-views-nodes/),
prévu pour kube-prometheus-stack. Il ne fonctionne pas avec le seul inventaire AWS.
Sources : [santé et ressources des groupes EKS](https://docs.aws.amazon.com/eks/latest/APIReference/API_DescribeNodegroup.html),
[métriques EC2 CloudWatch](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/viewing_metrics_with_cloudwatch.html).

## RAM et compteurs Kubernetes historiques

`eks_workload_exporter.py workloads` tourne **chaque minute**, avec verrou et publication
atomique dans `aws_eks_workloads_metrics.prom`. Le job Prometheus correspondant scrape
chaque minute. L’accès HTTPS vérifie le certificat du cluster ; le token AWS est renouvelé
à chaque collecte et ne figure ni dans les métriques ni dans les logs. Aucun agent n’est
installé sur les nœuds. L’accès EKS du rôle `access` est déjà configuré par `eks_shared`.
Sur une installation neuve, exécuter ce rôle (tag `eks`) avant d’attendre des données.

- **RAM par instance** : working set du nœud (OS + pods, hors cache récupérable), en
  octets et en pourcentage de la mémoire physique. Source : kubelet `/stats/summary`,
  `workingSetBytes / (workingSetBytes + availableBytes)`. Grafana calcule une moyenne
  glissante sur 5 minutes des échantillons disponibles, à pas d’une minute. Les observations
  âgées de plus de deux minutes sont exclues ; une panne ne devient pas un faux zéro.
- **Pods** : nombre de pods en phase Running et détail par phase, tous namespaces
  inclus. Running ne signifie pas Ready. Les pods terminés restent dans leurs phases
  Succeeded/Failed tant que les objets existent.
- **CSI** : total des PV CSI, nombre en phase Bound, nombre de VolumeAttachments
  actifs ; table avec driver, identifiant du volume, phase et politique Delete/Retain.
  Un PV Bound n’est pas forcément monté par un pod en cours d’exécution.
- **Services LoadBalancer** : nombre demandé dans Kubernetes, y compris ceux en attente,
  et détail du provisionnement. Les ALB créés par Ingress sont visibles dans l’inventaire AWS.

Ces courbes commencent à l’installation de la collecte : aucun historique antérieur
n’est reconstruit. Prometheus conserve les données sur son volume Docker persistant,
avec sa rétention par défaut de 15 jours. Si la VM/le volume de monitoring est supprimé
à la fin du TP, exporter les données nécessaires avant cette suppression.

## Inventaire AWS après suppression des clusters

`eks_workload_exporter.py resources` tourne toutes les cinq minutes et publie
`aws_eks_resources_metrics.prom`. Il inspecte directement les API régionales AWS,
y compris lorsqu’il ne reste **aucun cluster** :

- volumes EBS et snapshots du compte ;
- ALB/NLB et Classic ELB, ainsi que les target groups ;
- interfaces réseau, adresses IP élastiques et groupes de sécurité.

Seules les ressources portant des tags Kubernetes/EKS reconnus sont comptées.
Le cluster est extrait notamment de `kubernetes.io/cluster/<nom>`,
`ebs.csi.aws.com/cluster-name` et `elbv2.k8s.aws/cluster`. Un marqueur CSI sans
nom de cluster apparaît sous `unknown`. Le filtre Grafana inclut aussi les noms issus
des ressources AWS : un cluster supprimé reste sélectionnable tant qu’il a des ressources.
Les graphiques **total régional** et la table **à vérifier** ignorent volontairement le
filtre cluster pour ne pas masquer les ressources restantes ; zéro est publié lorsque
l’inventaire régional est réellement vide.

Les raisons de vérification sont : cluster absent/inconnu, EBS ou ENI détaché, EIP non
associée, target group sans LB. Elles signalent des **candidats à examiner**, pas des
orphelins prouvés : des transitions normales et des ressources partagées sont possibles.
Un snapshot conservé reste dans l’inventaire même sans être marqué suspect.
Aucune ressource n’est supprimée, et aucun coût n’est calculé.

Limites : l’inventaire ne lit pas le state Terraform, donc ne certifie pas qu’une ressource
est hors Terraform. Les ressources sans tags identifiants (notamment certaines ENI/EIP),
les régions non configurées et les services non inventoriés (EFS, entrées DNS ExternalDNS,
logs CloudWatch, images ECR, etc.) ne sont pas couverts. Des volumes CSI non EBS restent
visibles comme PV dans Kubernetes mais ne sont pas inventoriés côté AWS. Une recréation
d’un cluster du même nom ne suffit pas à attribuer ses anciennes ressources à sa nouvelle
incarnation. Cet inventaire complète les scripts de nettoyage du TP, sans remplacer
la vérification finale du compte AWS.

Les erreurs sont isolées par cluster, par nœud et par type de ressource. En cas de refus
IAM ou d’API inaccessible, les données concernées disparaissent et
`aws_eks_detail_collection_success` vaut zéro : pas de faux inventaire vide.
L’âge des collectes détecte un cron bloqué même si Nginx continue à servir le fichier.

Sources : [métriques des nœuds Kubernetes](https://kubernetes.io/docs/reference/instrumentation/node-metrics/),
[tags du driver EBS CSI](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/tagging.md),
[tags AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.8/guide/ingress/annotations/).

## Vérification locale

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_eks*.py' -v
```

Les tests simulent AWS : aucun cluster n’est créé ni modifié. Ils couvrent une région
vide, les refus IAM, la santé et le comptage ASG, l’ordre des points CloudWatch,
les points absents, les pannes CloudWatch et le remplacement du fichier publié.


