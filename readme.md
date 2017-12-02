Génère des fichiers svg correspondant aux layers d’un keymap pour Ergodox/ergodone (cf [qmk_firmware](https://github.com/qmk/qmk_firmware)).

Il est possible d’exporter en png via l’option export.

Un cumul des layers est possible spécifiants ceux qu’on souhaite, après l’option export.

La syntaxe est :

./parse_layout.pl <source.c> [export|noexport] [layer, …]
