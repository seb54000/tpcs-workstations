# Monitoring global EKS

Le dashboard provisionné **AWS EKS — Vue globale TP** (`/d/tpcs-eks-overview`)
présente les clusters, les groupes managés, les nœuds présents et souhaités par
groupe, les états et problèmes de santé AWS, le CPU et les contrôles EC2 par VM.
Les filtres région et cluster permettent de parcourir plusieurs clusters.
Le total des clusters est régional ; les autres panneaux d’inventaire suivent le filtre cluster.

L’exporteur EC2 existant inclut déjà Paris (`eu-west-3`), mais expose uniquement
l’inventaire : il ne fournit pas la consommation CPU des instances.
Le nouvel exporteur utilise les API EKS et Auto Scaling pour rattacher les instances
aux groupes, puis CloudWatch pour les métriques EC2. Aucun accès au cluster n’est requis.

## Installation

Appliquer la modification Terraform de la policy du rôle `access` avec le workflow
habituel du dépôt (plan puis apply), puis relancer le rôle Ansible `access_docs` :

```sh
ansible-playbook post_install.yml -t access_docs
```

La policy ajoute seulement les lectures `eks:ListNodegroups`,
`eks:DescribeNodegroup`, `autoscaling:DescribeAutoScalingGroups` et
`cloudwatch:GetMetricStatistics` aux autorisations existantes.
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
  les nœuds sont Kubernetes `Ready`. La mémoire et la santé des workloads ne sont
  pas collectées ici. Pour cela, installer kube-prometheus-stack dans les clusters
  et organiser la remontée des métriques vers le monitoring central.
- Collecte : appels d’inventaire par cluster/groupe, puis deux appels CloudWatch
  par instance toutes les cinq minutes. Pour une grande flotte, préférer une collecte
  CloudWatch par lots ; des frais API peuvent s’appliquer.

Dashboard Kubernetes existant pour une future collecte dans les clusters :
[Grafana Kubernetes / Views / Nodes](https://grafana.com/grafana/dashboards/15759-kubernetes-views-nodes/),
prévu pour kube-prometheus-stack. Il ne fonctionne pas avec le seul inventaire AWS.
Sources : [santé et ressources des groupes EKS](https://docs.aws.amazon.com/eks/latest/APIReference/API_DescribeNodegroup.html),
[métriques EC2 CloudWatch](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/viewing_metrics_with_cloudwatch.html).

## Vérification locale

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_eks_monitoring.py -v
```

Les tests simulent AWS : aucun cluster n’est créé ni modifié. Ils couvrent une région
vide, les refus IAM, la santé et le comptage ASG, l’ordre des points CloudWatch,
les points absents, les pannes CloudWatch et le remplacement du fichier publié.


