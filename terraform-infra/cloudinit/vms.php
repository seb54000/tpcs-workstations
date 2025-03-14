<?php

// Récupérer la région à partir de la zone de disponibilité en utilisant curl
$region = shell_exec("curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone/ | sed 's/.$//'");

// Chargement du fichier JSON des correspondances utilisateur
$userMapping = json_decode(file_get_contents('/var/www/html/json/users.json'), true);

// Chargement du fichier JSON des clés d'API
$apiKeys = json_decode(file_get_contents('/var/www/html/json/api_keys.json'), true);

$tptype = file_get_contents('/var/www/html/json/tp_name');
echo "<h1>TP type : " .htmlspecialchars($tptype). "</h1>";

echo "Votre nom d'utilisateur est unique pour tous les usages : user guacamole, user vm, user AWS console. Le mot de passe est identique au username (sauf pour console AWS cf. ci-dessous)</br>";
echo "<i>Si besoin vous pouvez vous connectez directement à la vm (via SSH ou RDP) en utilisant le Record DNS (chercher la colonne).</i></br>";
echo "<i>  Exemple : ssh vmxx@vmxx.tpcs.multiseb.com (ou utiliser un client RDP)</i></br>";

if ($tptype == "tpiac") {
    echo "Les mots de passe pour console AWS et clé secrète d'API sont dans le fichier <b>/home/vmXX/tpcs-iac/.env</b> sur chacune de vos VMs</br></br>";
    echo "<h3><a href=\"https://tpiac.signin.aws.amazon.com/console/\" target=\"_blank\">Accès console AWS</a></h3>";
}

echo "<h3><a href=\"https://access.tpcs.multiseb.com/\" target=\"_blank\">Accès Guacamole (bureau RDP pour votre VM)</a></h3>";


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
            <th>Adresse IP associée actuellement</th>
            <th>Statut de la VM</th>
        </tr>";

// Parcourir le tableau de correspondance des utilisateurs
foreach ($userMapping as $user => $userData) {
    $UserRealName = $userData['name'];

    // Exécuter la commande AWS CLI pour obtenir les détails de l'instance
    $instanceOutput = shell_exec("aws ec2 describe-instances --region $region --output json --filters Name=tag:Name,Values=vm" . substr($user, 2) . " --query 'Reservations[].Instances[].[InstanceId,PublicIpAddress,Tags[?Key==`Name`]|[0].Value,Tags[?Key==`AUTO_DNS_NAME`]|[0].Value,State.Name]' 2>&1");

    // Décoder la sortie JSON
    $instanceDetails = json_decode($instanceOutput, true);

    // // Récupérer la clé d'API associée à l'utilisateur en utilisant le module IAM
    // $iamOutput = shell_exec("aws iam list-access-keys --user-name $user --output json 2>&1");
    // $iamDetails = json_decode($iamOutput, true);
    // $apiKey = isset($iamDetails['AccessKeyMetadata'][0]['AccessKeyId']) ? $iamDetails['AccessKeyMetadata'][0]['AccessKeyId'] : "N/A";

    // Vérifier si $instanceDetails est null avant de tenter d'itérer
    if ($instanceDetails !== null) {
        // Récupérer les clés d'API associées à l'utilisateur
        $apiKey = isset($apiKeys[$user]['AK']) ? $apiKeys[$user]['AK'] : "N/A";
        $secretKey = isset($apiKeys[$user]['SK']) ? $apiKeys[$user]['SK'] : "N/A";

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
            echo "<td>{$instance[2]}.tpcs.multiseb.com</td>";

            // Exécuter un lookup pour obtenir l'adresse IP associée au record DNS
            $dnsIp = shell_exec("nslookup {$instance[2]}.tpcs.multiseb.com 2>&1 | grep -Eo 'Address: ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)' | cut -d' ' -f2");
            echo "<td>{$dnsIp}</td>";

            echo "<td>{$instance[4]}</td>";
            echo "</tr>";
        }
    }
}

// Fermer le tableau HTML
echo "</table>";
?>
