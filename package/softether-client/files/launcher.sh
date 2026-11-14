#!/bin/sh
# SoftEther VPN command wrapper for OpenWrt
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
EXEC_NAME="$(basename "$0")"
DIR="/usr/libexec/softether"

if [ ! -d "$DIR" ]; then
	echo "Error: SoftEther directory $DIR does not exist." >&2
	exit 1
fi

cd "$DIR" || exit 1

if [ "$EXEC_NAME" = "launcher.sh" ]; then
	EXEC_NAME="vpncmd"
fi

exec ./"$EXEC_NAME" "$@"

