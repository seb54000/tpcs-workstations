#!/bin/bash

ctrlc_count=0

function no_ctrlc()
{
    let ctrlc_count++
    echo
    if [[ $ctrlc_count == 1 ]]; then
        echo "Stop that."
    elif [[ $ctrlc_count == 2 ]]; then
        echo "Once more and I quit."
    else
        echo "That's it.  I quit."
        exit
    fi
}

function handle_term()
{
    echo "Get SIGTERM, handle and close"
    exit 0
}

function handle_kill()
{
    echo "!! SIGKILL Received, handle and close"
    exit 0
}

function handle_stop()
{
    echo "SIGSTOP Received, now pausing process"
    exit 0
}

function handle_cont()
{
    echo "SIGCONT Received, now resuming process"
    exit 0
}

trap no_ctrlc SIGINT
trap handle_term SIGTERM
trap handle_kill SIGKILL
trap handle_stop SIGSTOP
trap handle_cont SIGCONT

echo "########### ########### ########### ###########"
echo "########### Application is STARTING ###########"
echo "########### $(date '+%Y-%m-%d %H:%M:%S') ###########"
echo "########### ########### ########### ###########"

while true
do
    echo "Sleeping for 10 seconds"
    date '+%Y-%m-%d %H:%M:%S'
    sleep 10 & wait ${!}
    # https://linuxize.com/post/bash-wait/
done
