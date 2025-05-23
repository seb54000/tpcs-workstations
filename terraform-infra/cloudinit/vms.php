<?php

// Récupérer la région à partir de la zone de disponibilité en utilisant curl
$region = shell_exec("curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone/ | sed 's/.$//'");

// Chargement du fichier JSON des correspondances utilisateur
$userMapping = json_decode(file_get_contents('/var/www/html/json/users.json'), true);

$tptype = file_get_contents('/var/www/html/json/tp_name');
$dns_subdomain = file_get_contents('/var/www/html/json/dns_subdomain');
// Chargement du fichier JSON des clés d'API
if ($tptype == "tpiac") {
    $apiKeys = json_decode(file_get_contents('/var/www/html/json/api_keys.json'), true);
}

echo "<h1>TP type : " .htmlspecialchars($tptype). "</h1>";

echo "Votre nom d'utilisateur est unique pour tous les usages : user guacamole, user vm, user AWS console. Le mot de passe est identique au username (sauf pour console AWS cf. ci-dessous)</br>";
echo "<i>Si besoin vous pouvez vous connectez directement à la vm (via SSH ou RDP) en utilisant le Record DNS (chercher la colonne).</i></br>";
echo "<i>  Exemple : ssh vmxx@vmxx.${dns_subdomain} (ou utiliser un client RDP)</i></br>";

if ($tptype == "tpiac") {
    echo "Les mots de passe pour console AWS et clé secrète d'API sont dans le fichier <b>/home/vmXX/tpcs-iac/.env</b> sur chacune de vos VMs</br></br>";
    echo "<h3><a href=\"https://tpiac.signin.aws.amazon.com/console/\" target=\"_blank\">Accès console AWS</a></h3>";
}

echo "<h3><a href=\"https://access.${dns_subdomain}/\" target=\"_blank\">Accès Guacamole (bureau RDP pour votre VM)</a></h3>";


// En-tête du tableau HTML
echo "<table border='1'>
        <tr>
            <th>Nom réel</th>
            <th>Nom unique (username)</th>";
if ($tptype == "tpiac") {
    echo    "<th>Clé d'API (AK)</th>
            <th>Région où la clé d'API est active</th>";
}
echo        "<th>Adresse IP de la VM</th>
            <th>Record DNS</th>
            <th>Adresse IP du record DNS</th>
            <th>Statut de la VM</th>
        </tr>";

// Parcourir le tableau de correspondance des utilisateurs
foreach ($userMapping as $user => $userData) {
    $UserRealName = $userData['name'];

    // Exécuter la commande AWS CLI pour obtenir les détails de l'instance (we want all status except terminated/removed)
    $instanceName = 'vm' . substr($user, -2);
    $cmd = "aws ec2 describe-instances "
         . "--region $region "
         . "--output json "
         . "--filters "
         . "Name=tag:Name,Values=$instanceName "
         . "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped "
         . "--query 'Reservations[].Instances[].[InstanceId,PublicIpAddress,"
         . "Tags[?Key==`Name`]|[0].Value,"
         . "Tags[?Key==`AUTO_DNS_NAME`]|[0].Value,"
         . "State.Name]'";
    $instanceOutput = shell_exec($cmd);

    // Décoder la sortie JSON
    $instanceDetails = json_decode($instanceOutput, true);

    // // Récupérer la clé d'API associée à l'utilisateur en utilisant le module IAM
    // $iamOutput = shell_exec("aws iam list-access-keys --user-name $user --output json 2>&1");
    // $iamDetails = json_decode($iamOutput, true);
    // $apiKey = isset($iamDetails['AccessKeyMetadata'][0]['AccessKeyId']) ? $iamDetails['AccessKeyMetadata'][0]['AccessKeyId'] : "N/A";

    // Vérifier si $instanceDetails est null avant de tenter d'itérer
    if ($instanceDetails !== null) {
        // Récupérer les clés d'API associées à l'utilisateur
        if ($tptype == "tpiac") {
            $apiKey = isset($apiKeys[$user]['AK']) ? $apiKeys[$user]['AK'] : "N/A";
            $secretKey = isset($apiKeys[$user]['SK']) ? $apiKeys[$user]['SK'] : "N/A";
        }

        // Afficher les détails dans le tableau HTML
        foreach ($instanceDetails as $instance) {
            echo "<tr>";
            echo "<td>{$UserRealName}</td>";
            echo "<td>{$instance[2]}</td>";

            if ($tptype == "tpiac") {
                echo "<td>{$apiKey}</td>";
                // echo "<td>{$secretKey}</td>";
                $GroupName = shell_exec("aws iam list-groups-for-user --user-name $user --output text --query 'Groups[].GroupName' 2>&1");
                echo "<td>{$GroupName}</td>";
            }

            echo "<td>{$instance[1]}</td>";
            echo "<td>{$instance[2]}.${dns_subdomain}</td>";

            // Exécuter un lookup pour obtenir l'adresse IP associée au record DNS
            $dnsIp = shell_exec("dig +short {$instance[2]}.${dns_subdomain} 2>&1");
            echo "<td>{$dnsIp}</td>";

            echo "<td>{$instance[4]}</td>";
            echo "</tr>";
        }
    }
}

// Fermer le tableau HTML
echo "</table>";
?>
