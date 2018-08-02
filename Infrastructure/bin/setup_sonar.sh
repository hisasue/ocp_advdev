#!/bin/bash
# Setup Sonarqube Project
if [ "$#" -ne 1 ]; then
    echo "Usage:"
    echo "  $0 GUID"
    exit 1
fi

GUID=$1
echo "Setting up Sonarqube in project $GUID-sonarqube"

# Code to set up the SonarQube project.
# Ideally just calls a template
# oc new-app -f ../templates/sonarqube.yaml --param .....

# To be Implemented by Student
oc project $GUID-sonarqube
oc new-app --template=postgresql-persistent --param POSTGRESQL_USER=sonar --param POSTGRESQL_PASSWORD=sonar --param POSTGRESQL_DATABASE=sonar --param VOLUME_CAPACITY=4Gi --labels=app=sonarqube_db -n $GUID-sonarqube
oc new-app --docker-image=wkulhanek/sonarqube:6.7.4 --env=SONARQUBE_JDBC_USERNAME=sonar --env=SONARQUBE_JDBC_PASSWORD=sonar --env=SONARQUBE_JDBC_URL=jdbc:postgresql://postgresql/sonar --labels=app=sonarqube -n $GUID-sonarqube
oc rollout pause dc sonarqube -n $GUID-sonarqube
oc expose service sonarqube -n $GUID-sonarqube
echo "apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: sonarqube-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 4Gi" | oc create -f - -n $GUID-sonarqube
oc set volume dc/sonarqube --add --overwrite --name=sonarqube-volume-1 --mount-path=/opt/sonarqube/data/ --type persistentVolumeClaim --claim-name=sonarqube-pvc -n $GUID-sonarqube
oc set resources dc/sonarqube --limits=memory=3Gi,cpu=2 --requests=memory=2Gi,cpu=1 -n $GUID-sonarqube
oc patch dc sonarqube --patch='{ "spec": { "strategy": { "type": "Recreate" }}}' -n $GUID-sonarqube
oc set probe dc/sonarqube --liveness --failure-threshold 3 --initial-delay-seconds 40 -n $GUID-sonarqube -- echo ok
oc set probe dc/sonarqube --readiness --failure-threshold 3 --initial-delay-seconds 20 -n $GUID-sonarqube --get-url=http://:9000/about

oc rollout resume dc sonarqube -n $GUID-sonarqube
