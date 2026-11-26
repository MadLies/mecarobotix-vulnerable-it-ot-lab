#!/usr/bin/env bash

while true; do
    curl -X POST http://10.10.2.10/api/robots/register -H "Content-Type: application/json" -d '{"a":"a"}' > /dev/null 2>&1 &
done
