#!/bin/sh

echo "--------------------------------------------------------------------"
echo
echo "SoftEther VPN Client (Ver 4.44, Build 9807, Intel x64 / AMD64) for Mac OS X Build Utility"
echo "Copyright (c) SoftEther Project at University of Tsukuba, Japan. All Rights Reserved."
echo
echo "--------------------------------------------------------------------"
echo
echo

if [ -f ReadMeFirst_License.txt ]; then
    cat ReadMeFirst_License.txt
else
    echo "[Warning] ReadMeFirst_License.txt not found, skipping license display."
fi

echo
echo "--------------------------------------------------------------------"
echo
echo

make main

exit 0

