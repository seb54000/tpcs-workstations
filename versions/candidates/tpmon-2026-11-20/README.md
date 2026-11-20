# TP monitoring — candidate ECR images du 20 novembre 2026

Images partagées reconstruites depuis le checkout Demoboard `e63f58b` et
poussées dans `896025786589.dkr.ecr.eu-west-3.amazonaws.com/tpmon-demoboard`.
Les trois tags `api-v1`, `worker-v1` et `front-v2` ont été vérifiés dans ECR
après le push ; leurs digests sont consignés dans `images.lock.json`.

Cette candidate remplace les artefacts ECR capturés le 1er octobre, qui avaient
été supprimés. Elle n'est pas encore validée par un déploiement fonctionnel de
Demoboard et de la stack LGTM sur EKS.
