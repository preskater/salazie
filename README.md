# Salazie : Trois générations

## Présentation

Salazie : Trois générations est un jeu qui raconte l’histoire d’une famille à travers trois générations.

Le joueur commence comme un marron dans la nature sauvage, devient cultivateur, puis héritier qui doit protéger l’avenir de Salazie.

## Les trois maps

### Map 1 — Le marron

Le joueur doit survivre dans la nature sauvage sans se faire repérer.

Il doit trouver de la nourriture, se cacher et éviter les dangers.

### Map 2 — Le cultivateur

Le joueur doit cultiver la terre et vendre ses produits.

Il doit aussi s’adapter aux changements économiques de l’époque.

### Map 3 — L’héritier

Le joueur doit résoudre les problèmes du changement climatique, de l’économie et de l’avenir de Salazie.

Il doit aider les habitants et prendre de bonnes décisions.

## Progression

Chaque génération possède une liste de tâches. Une tâche peut être **réussie** ou **échouée** ; les échecs sont conservés dans le résultat de la génération, même si la tâche est retentée et réussie ensuite. La map est terminée lorsque toutes les tâches sont résolues : les échecs restants ne bloquent pas le passage, mais ils affaiblissent le résultat et l'épilogue.

1. Survivre comme marron : nourriture, eau, cachette, traversée des patrouilles et refuge.
2. Cultiver et vendre comme cultivateur : préparer, planter, récolter, vendre et réunir 100 G de patrimoine (argent et biens) avant le jour 6.
3. Écouter, évaluer, financer et décider comme héritier : habitants, zones fragiles, plan et vote du conseil.

Sur la map 1, être repéré par une patrouille ou s'effondrer de faim ou de soif est un revers : les deux premiers réduisent l'argent de départ du cultivateur et pèsent sur le vote final. Les échecs de la map 2 réduisent l'héritage transmis à l'héritier. Sur la map 3, l'héritage devient le budget de l'héritier : financer les zones fragiles, écouter tous les habitants et parcourir le village rapportent des voix au conseil. Il en faut six ; la famille en apporte cinq, moins une par échec des trois générations. Le plan choisi et le vote déterminent l'épilogue.

La liste des tâches est visible en permanence en haut de l'écran. **T** ou **Select/Back** ouvre le détail, avec les tâches réussies, échouées et les raisons des échecs.

## Cycle jour/nuit

Chaque map alterne une phase de jour et une phase de nuit. Le cycle est décoratif : ce sont les tâches qui débloquent la génération suivante. Le nombre de nuits reste configurable dans `scenes/preloads/day_night_cycle.tscn`, via `nights_required_for_next_map`.

## Transitions entre maps

Le passage d'une map à l'autre utilise `scenes/preloads/scene_transition.tscn`, chargé en autoload : un fondu au noir affiche un titre et un sous-texte, la scène suivante est chargée, puis le jeu réapparaît. Les durées (`fade_out_duration`, `hold_duration`, `fade_in_duration`), la couleur du fondu et les couleurs de texte se configurent dans cette scène.

Pour déclencher la transition, placer une zone `MapExit` (`scenes/world/map_exit.tscn`) dans la map et renseigner :

- `next_scene_path` : la scène de destination ;
- `title` et `subtitle` : le texte affiché pendant la transition ;
- `requires_map_complete` : si vrai, la sortie attend que toutes les tâches de la génération soient résolues ;
- `requires_map_ready` : conserve l'ancien verrou par nuits, désactivé dans les maps actuelles ;
- `complete_task_on_enter` : tâche terminée à l'entrée, utilisée par le refuge de la map 1 ;
- `show_result` : affiche le bilan de la génération avant la transition.

Le bilan affiche les tâches réussies, les échouées, le nombre d'échecs et la conséquence pour la génération suivante.

On peut aussi appeler directement `SceneTransition.change_scene(chemin, titre, sous_texte)` depuis un script.

## Objectif final

Le but du jeu est de traverser les trois générations et de devenir maire de Salazie.

## Menus et sauvegarde

Le jeu démarre sur un menu d’accueil : **Nouvelle partie**, **Continuer**, **Options**,
**Crédits** et **Quitter**. La map 1 — Le marron est la première map jouable.

- Une seule sauvegarde automatique est conservée dans `user://savegame.json`.
- Elle est écrite au changement de jour, à chaque tâche résolue, à l'ouverture de la pause,
  au retour au menu et à la fermeture du jeu.
- **Échap** ou **Start** ouvre le menu pause : reprendre, options, commandes, sauvegarder,
  menu principal ou quitter.
- **T** ou **Select/Back** ouvre la liste détaillée des tâches.
- Les options couvrent le volume général, la musique, les effets, le mode d’affichage, la
  résolution et la synchronisation verticale.

Détails techniques : [docs/UI.md](docs/UI.md).

## Son

Chaque map a sa musique et le jeu réagit par des effets sonores : pas, ramassage, alerte des gardes, récolte, vente, tâche accomplie. Les sons actuels sont **provisoires** : ils sont synthétisés par un script du projet (`tools/audio/generate_audio.py`), donc libres de droits, et peuvent être remplacés fichier par fichier. Les volumes se règlent dans les options.

Détails techniques : [docs/AUDIO.md](docs/AUDIO.md).

## Économie

Chaque génération possède sa propre économie, configurable dans
`game_resources/economy/economy.tres` :

- **Le marron** : économie désactivée, le joueur survit sans argent.
- **Le cultivateur** : gourdes (G), marché des récoltes, des graines et des propriétés.
- **L’héritier** : euros (€) et crédits verts (CV), avec leurs propres offres.

Le joueur peut acheter, vendre et échanger des objets, des bâtiments et des emplacements.
Une génération peut être désactivée dans le fichier de configuration ; ses transactions et
ses boutons de marché sont alors bloqués.

Les portefeuilles, les stocks et les propriétés sont sauvegardés avec la partie. Détails
techniques et API : [docs/ECONOMY.md](docs/ECONOMY.md).

## Assets du jeu

Les assets utilisés dans le jeu proviennent de LimeZu.

Ils servent à créer les personnages, les décors, les objets, les bâtiments et les éléments visuels des trois maps.

L’interface (menus et HUD) utilise uniquement le pack **Modern UI 48x48** de LimeZu, afin de garder une direction artistique cohérente avec le reste du jeu.

Site des assets : <https://limezu.itch.io/>
