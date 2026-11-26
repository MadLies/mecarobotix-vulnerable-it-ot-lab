# Scenario strategic 1 | Chemin d'attaque 1.1

L'attaquand commence par faire une reconnaissance des emails publique sur des plateforms comme LinkedIn ou <https://hunter.io/try/search/google.com?locale=en>.

Un personal de l'admin recois email d'hameceonnage et execute le script en piece jointe (ou telechargé par un lien).

Pour la simplicité de l'exemple, on suppose que la personne visée dans l'admin utilise une machine personnelle linux et elle execute le script malveillant update.sh.

Un exemple d'email d'hammeconnage peut ressembler à :

FROM: @linux-updates.com
TO: <l'email du personnel d'admin>
Sujet: Urgent Linux update

Dear user,
Please be advised that a critical security vulnerability has been discovered in your linux version.
A fast patch update script has been released as a fast fix before the next official release. Please consider executing it to secure your system as soon as possible.
Best regrards,

John Ripper
Senior software developper - Security operations
Linux foundation
+1 514 481 4270 post 7714

(update.sh en fichier join)

Le script update.sh install un backdoor qui se connecte à la machine de l'attaquant et lui permet d'executer n'importe quelle commande en tant que root ! Le script s'assure aussi que le backdoor est systémariquement executé (sans intervention de l'utilisateur)

L'attaquant lance ensuite `sudo nc -l 80 -v` sur sa machine et attend que sa cible execute le script pour se connecter.

Un fois que sa cible connectée, l'attaquant a un accès root à la machine du personel d'admin et peut donc installer nmap, executer de la reconnaissance sur le réseau intern pour découvrir par exeemble la base de données PostGres dans le réseau intern.

Il peut alors faire la commande `psql -h 10.10.1.31 -p 5432 -U admin_db -d postgres` et essayer quelques mot de passe puisque le mdp n'est pas si difficil à trouver (`Admin123!`). Ensuite, il peut exfilrer les information.
