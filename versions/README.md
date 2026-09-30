# Versions des TP

- [Référence IaC des 29–30 septembre 2026](baselines/tpiac-2026-09-29/README.md) : inventaires, preuves et limites.
- `baselines/` : données observées et overlay distribué sur les clones étudiants neufs.
- `tasks/` : règles APT/Snap appelées par le rôle commun en mode IaC.
- `filter_plugins/` : sélection des versions APT ; déclaré dans `ansible.cfg`.
- `scripts/check-tpiac-baseline.py` : contrôle du Mele, sans modification.

Le branchement au provisioning reste dans les rôles existants et `group_vars/all.yml`.
Les tests sont dans le répertoire `tests/` commun au dépôt.
Les verrous propres aux applications IaC sont aussi présents dans `tpcs-iac/demoboard/ansible/versions/`.
