#!/bin/dash

<<<<<<< HEAD
# . $(dirname $(readlink -f $0))/basic_functions.sh
=======
#. $(dirname $(readlink -f $0))/basic_functions.sh
>>>>>>> 9a6423fe5f32205037cd96d723a275e76b168b03
. $(dirname $(dirname $(readlink -f $0)))/basic_functions.sh
. $ROOT_DIR/setup_routines.sh

main () 
{
}

maintain()
{
	check_update
	[ "$1" = 'help' ] && show_help_exit
}

show_help_exit()
{
	cat << EOL

EOL
	exit 0
}

maintain "$@"; main "$@"; exit $?
