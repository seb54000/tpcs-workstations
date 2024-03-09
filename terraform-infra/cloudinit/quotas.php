<?php

// Obtenez la liste des régions AWS
// Récupérer la région à partir de la zone de disponibilité en utilisant curl
$region = shell_exec("curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone/ | sed 's/.$//'");
// A first region is needed to list all regions...
$regionsOutput = shell_exec("aws ec2 describe-regions --output json --region $region");
$regions = json_decode($regionsOutput, true);

// aws service-quotas list-service-quota --region eu-west-3 --output json
// aws service-quotas list-service-quotas --region eu-west-3 --output json --service-code ec2
// aws service-quotas get-service-quota --region eu-west-3 --output json --service-code ec2 --quota-code L-FB451C26
// aws service-quotas get-aws-default-service-quota --region eu-west-3 --output json --service-code ec2 --quota-code L-FB451C26
// get-aws-default-service-quota
// list-aws-default-service-quotas

// En-tête du tableau HTML
echo "<table border='1'>
        <tr>
            <th>Région</th>
            <th>Type de ressource</th>
            <th>Quota actuel</th>
            <th>Utilisation actuelle</th>
        </tr>";

// Parcourir les régions
foreach ($regions['Regions'] as $region) {
    $currentRegion = $region['RegionName'];

    // Pour VPC
    $quotasOutput = shell_exec("aws service-quotas list-service-quotas --service-code vpc --region $currentRegion --output json");
    $quotas = json_decode($quotasOutput, true);

    // Afficher les détails dans le tableau HTML pour les quotas VPC et Internet Gateway
    foreach ($quotas['Quotas'] as $quota) {
        $quotaCode = $quota['QuotaCode'];

        // aws service-quotas list-service-quotas --service-code vpc --region eu-west-3 --output json | jq '.Quotas[] | .QuotaName'
        // "QuotaCode": "L-F678F1CE", "VPCs per Region",
        // L-FE5A380F , NAT gateways per Availability Zone
        // L-407747CB, Subnets per VPC

        // Quotas nécessaires pour TP iac par étudiant
        // 1 VPC, 2 NAT gw (et donc 2 EIP à priori) , 2 LB , 2 x 3 subnets ,  2 jumhposts,  2 APIs (to scale), 1 Db (to scale)

        // Filtrer les résultats pour les quotas VPC et Internet Gateway
        if ($quotaCode === 'L-F678F1CE' || $quotaCode === 'L-FE5A380F' || $quotaCode === 'L-407747CB') {
            // Obtenir le quota actuel et l'utilisation actuelle
            $currentQuotaOutput = shell_exec("aws service-quotas get-service-quota --service-code vpc --quota-code $quotaCode --region $currentRegion --output json");
            $currentQuota = json_decode($currentQuotaOutput, true);

            echo "<tr>";
            echo "<td>{$currentRegion}</td>";
            echo "<td>{$quota['QuotaName']}</td>";
            echo "<td>{$currentQuota['Quota']['Value']}</td>"; // Quota actuel
            echo "<td>{$currentQuota['Quota']['UsageMetric']['MetricName']}</td>"; // Utilisation actuelle
            echo "</tr>";
        }
    }
    // Obtenir les quotas pour chaque région liés à EC2
    $quotasOutput = shell_exec("aws service-quotas list-service-quotas --service-code ec2 --region $currentRegion --output json");
    $quotas = json_decode($quotasOutput, true);

    // Afficher les détails dans le tableau HTML pour les quotas VPC et Internet Gateway
    foreach ($quotas['Quotas'] as $quota) {
        $quotaCode = $quota['QuotaCode'];

        // aws service-quotas list-service-quotas --service-code ec2 --region eu-west-3 --output json | jq '.Quotas[] | .QuotaName'
        // "QuotaCode": "L-0263D0A3",  EC2-VPC Elastic IPs
        // L-1216C47A , Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances

        // Quotas nécessaires pour TP iac par étudiant
        // 1 VPC, 2 NAT gw (et donc 2 EIP à priori) , 2 LB , 2 x 3 subnets ,  2 jumhposts,  2 APIs (to scale), 1 Db (to scale)

        // Filtrer les résultats pour les quotas VPC et Internet Gateway
        if ($quotaCode === 'L-0263D0A3' || $quotaCode === 'L-1216C47A') {
            // Obtenir le quota actuel et l'utilisation actuelle
            $currentQuotaOutput = shell_exec("aws service-quotas get-service-quota --service-code ec2 --quota-code $quotaCode --region $currentRegion --output json");
            $currentQuota = json_decode($currentQuotaOutput, true);

            echo "<tr>";
            echo "<td>{$currentRegion}</td>";
            echo "<td>{$quota['QuotaName']}</td>";
            echo "<td>{$currentQuota['Quota']['Value']}</td>"; // Quota actuel
            echo "<td>{$currentQuota['Quota']['UsageMetric']['MetricName']}</td>"; // Utilisation actuelle
            echo "</tr>";
        }
    }

    // TODO , ELB for lad balancer are also different quotas...
    // Problem AWS support wants first a 90% capacity usage of the quotas before raising them
    // Need to add (TODO) the actual usage for a quota
    // We need to think about usage of multiple region at once for TP IaC
      // Some of the students will have only access to region X, other to region Y
      // Need to follow the quotas and take a snapshot at the beginning of the TP and at the end to be sure everything is removed
      // A script to remove all the resources in all the regions ?

}


// Fermer le tableau HTML
echo "</table>";
?>
