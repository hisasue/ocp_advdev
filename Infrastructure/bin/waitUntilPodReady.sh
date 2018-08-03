#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "Usage:"
    echo "  $0 PODNAME PROJECTNAME"
    echo "  Example: $0 jenkins xxxx-jenkins"
    exit 1
fi

echo "Waiting for ${1} pod ready in ${0}"

while : ; do
 echo "Checking if ${1} is Ready..."
 oc get pod -n ${2}|grep -v build|grep -v slave|grep -v deploy|grep "1/1.*Running"
 [[ "$?" == "1" ]] || break
 echo "...no. Sleeping 10 seconds."
 sleep 10
done
