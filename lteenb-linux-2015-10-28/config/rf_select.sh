#!/bin/bash

name="$1"
path=$(dirname "$0")
link="rf_driver"

function help
{
    echo "Usage: $(basename $0)"
    echo "    <type>: " $(cd $path && find . -maxdepth 1 -type d | grep "./" | cut -d '/' -f2)
    exit 1
}

if [ "$name" = "" ] ; then
    help
fi

if [ ! -e "$path/$name" ] ; then
    echo "$name rf driver does not exist"
    help
    exit 1
fi

rm -f "$path/$link"
ln -s "$name" "$path/$link"

echo "RF frontend $name selected"

