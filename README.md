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

Le joueur doit réussir toutes les tâches d’une map pour passer à la génération suivante.

1. Survivre comme marron.
2. Cultiver et vendre comme cultivateur.
3. Résoudre les problèmes comme héritier.

## Cycle jour/nuit

Chaque map alterne une phase de jour et une phase de nuit. Le nombre de nuits à passer avant de pouvoir rejoindre la map suivante est configurable dans `game/world/DayNightCycle.tscn`, via la propriété entière `nights_required_for_next_map`. Une nuit n'est comptée qu'une fois entièrement écoulée ; le signal `ready_for_next_map` est alors émis.

## Transitions entre maps

Le passage d'une map à l'autre utilise `game/ui/SceneTransition.tscn`, chargé en autoload : un fondu au noir affiche un titre et un sous-texte, la scène suivante est chargée, puis le jeu réapparaît. Les durées (`fade_out_duration`, `hold_duration`, `fade_in_duration`), la couleur du fondu et les couleurs de texte se configurent dans cette scène.

Pour déclencher la transition, placer une zone `MapExit` (`game/world/MapExit.tscn`) dans la map et renseigner :

- `next_scene_path` : la scène de destination ;
- `title` et `subtitle` : le texte affiché pendant la transition ;
- `requires_map_ready` : si vrai, la sortie attend que `DayNightCycle.is_ready_for_next_map()` soit vrai.

On peut aussi appeler directement `SceneTransition.change_scene(chemin, titre, sous_texte)` depuis un script.

## Objectif final

Le but du jeu est de traverser les trois générations et de devenir maire de Salazie.

## Menus et sauvegarde

Le jeu démarre sur un menu d’accueil : **Nouvelle partie**, **Continuer**, **Options**,
**Crédits** et **Quitter**. La map 2 est la première map jouable.

- Une seule sauvegarde automatique est conservée dans `user://savegame.json`.
- Elle est écrite au changement de jour, à l’ouverture de la pause, au retour au menu et à
  la fermeture du jeu.
- **Échap** ou **Start** ouvre le menu pause : reprendre, options, commandes, sauvegarder,
  menu principal ou quitter.
- Les options couvrent le volume général, la musique, les effets, le mode d’affichage, la
  résolution et la synchronisation verticale.

Détails techniques : [docs/UI.md](docs/UI.md).

## Économie

Chaque génération possède sa propre économie, configurable dans
`game/systems/economy/config/economy.tres` :

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
