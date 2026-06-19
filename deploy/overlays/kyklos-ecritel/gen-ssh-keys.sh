#!/usr/bin/env bash
set -euo pipefail

# Genere 2 paires de cles ED25519 (PREPROD + PROD) et un fichier
# recapitulatif a transmettre a Boris / Ecritel.

KEY_DIR="$HOME/.ssh"
PREFIX="spark-kyklos"
OUTFILE="$(dirname "$0")/reponse-boris.txt"

PREPROD_KEY="$KEY_DIR/${PREFIX}-preprod-ed25519"
PROD_KEY="$KEY_DIR/${PREFIX}-prod-ed25519"

mkdir -p "$KEY_DIR"

echo "=== Generation des cles SSH ED25519 ==="

for env in preprod prod; do
  keyfile="$KEY_DIR/${PREFIX}-${env}-ed25519"
  if [[ -f "$keyfile" ]]; then
    echo "[SKIP] $keyfile existe deja"
  else
    ssh-keygen -t ed25519 -C "${PREFIX}-${env}" -f "$keyfile" -N ""
    echo "[OK]   $keyfile"
  fi
done

IP_PUBLIQUE="83.159.104.155"

cat > "$OUTFILE" <<EOF
================================================================
  INFORMATIONS POUR ACCES SSH — Spark / Kyklos
  Date : $(date +%Y-%m-%d)
================================================================

1. ADRESSE IP SOURCE
   IP fixe : ${IP_PUBLIQUE}
   Merci de whitelister cette IP pour l'acces SSH sur les
   serveurs PREPROD et PROD.

2. CLES PUBLIQUES SSH (ED25519)

   --- PREPROD ---
$(cat "${PREPROD_KEY}.pub")

   --- PROD ---
$(cat "${PROD_KEY}.pub")

3. SYSTEME CIBLE
   Nous concevons la procedure d'installation pour Debian 12+
   (Bookworm) ou Ubuntu 22.04+ LTS.
   Merci de confirmer la distribution et la version exacte
   installee sur les serveurs.

4. DROITS SUDO
   Nous aurons besoin de privileges sudo pendant la phase
   d'installation uniquement, pour :
   - Installer les paquets (Docker CE, cloudflared, outils)
   - Creer un utilisateur systeme dedie (ex: spark)
   - Configurer les services systemd
   - Configurer le pare-feu (ufw)
   Une fois l'installation terminee, l'utilisateur spark
   fonctionnera sans sudo (acces Docker via le groupe docker).

5. REPERTOIRE D'INSTALLATION
   Nous prevoyons d'installer dans /opt/spark/ (convention
   standard Linux pour les applications tierces).
   Si Ecritel a une preference differente (/srv/, /home/spark/,
   autre), merci de nous l'indiquer.

6. RESEAU
   Les serveurs doivent autoriser les connexions sortantes
   HTTPS (port 443) vers Cloudflare. Aucun port entrant n'est
   necessaire (le trafic passe par un tunnel Cloudflare).

7. WOOCOMMERCE
   Non concerne dans le perimetre actuel.

================================================================
EOF

echo ""
echo "=== Fichier recapitulatif genere ==="
echo "    $OUTFILE"
echo ""
echo "Contenu a transmettre a Boris :"
echo "  - Ce fichier texte ($OUTFILE)"
echo "  - Les 2 cles publiques sont incluses dans le fichier"
echo "  - Les cles privees restent sur cette machine ($KEY_DIR)"
