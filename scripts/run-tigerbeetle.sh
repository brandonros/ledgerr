#!/bin/bash

if [ ! -f "./0_0.tigerbeetle" ]; then
    tigerbeetle format --cluster=0 --replica=0 --replica-count=1 --development ./0_0.tigerbeetle
fi

tigerbeetle start --addresses=5000 --development ./0_0.tigerbeetle
