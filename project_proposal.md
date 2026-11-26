# Projet 05 – MécaRobotix

**Mots clés : Secrets management, IAG, segmentation OT/IT, comptes techniques, robots industriels**

## Société : MécaRobotix

MécaRobotix est une entreprise spécialisée dans la conception, l’intégration et la maintenance de robots industriels destinés à l’automatisation des chaînes de production. Ses clients sont des usines automobiles, pharmaceutiques et agroalimentaires.

L’entreprise compte **160 employés**, dont :

- 40 développeurs firmware,
- 35 ingénieurs mécatroniques,
- 50 techniciens d’installation,
- 20 personnels IT,
- 15 administratifs.

Les robots déployés chez les clients utilisent des **comptes techniques**, des clés API, et des certificats pour communiquer avec la plateforme de diagnostic fournie par MécaRobotix.

## Organisation interne

- **Ingénieurs mécatroniques** : conçoivent la partie mécanique et électronique.
- **Développeurs firmware** : implémentent la logique embarquée.
- **Techniciens installation** : déploiement sur site client, mise à jour robots.
- **IT interne** : gestion du réseau, serveurs, comptes techniques.
- **Sécurité IT** : audit interne, durcissement OT, séparation des environnements.

## Contexte du système d'information

Le SI sépare mal les environnements opérationnels et administratifs.

### Environnement OT (robots)

- Serveurs de supervision robotique.
- Scripts de maintenance contenant **des secrets en clair**.
- Comptes techniques partagés.
- Aucune solution de gestion de secrets.

### Environnement IT

- Annuaire interne mais **pas d’IAG**.
- Comptes services mal documentés.
- Accès administrateurs trop larges.

### Faiblesses actuelles

- Compte root partagé entre plusieurs techniciens (!).
- Scripts CI/CD embarquant les identifiants robot identiques pour chaque type de robot.
- Mauvaise isolation OT ↔ IT.
- Pas de rotation des secrets.
- Aucune traçabilité des actions sensibles.

## Menaces

- Compromission d’un script → accès à des robots clients.
- Attaques internes (comptes partagés).
- Mouvement latéral depuis un équipement OT compromis.
- Sabotage ou modification de firmware.

## Règles d’hygiène ANSSI pertinentes

- **Règle 4** : Identification des actifs sensibles.
- **Règle 5** : Inventaire comptes techniques et admin.
- **Règle 6** : Processus d’arrivée/départ.
- **Règle 8** : Comptes nominatifs.
- **Règle 9** : Droits stricts.
- **Règle 11** : Protection des secrets stockés.
- **Règle 12** : Changement des identifiants par défaut.
- **Règle 22** : Segmentation OT/IT.
- **Règle 25** : Filtrage réseau minimal.
- **Règle 32** : Sécurisation de l'administration.
- **Règle 35** : Supervision et logs.

