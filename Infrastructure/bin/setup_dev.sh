#!/bin/bash
# Setup Development Project
if [ "$#" -ne 1 ]; then
    echo "Usage:"
    echo "  $0 GUID"
    exit 1
fi

GUID=$1
echo "Setting up Parks Development Environment in project ${GUID}-parks-dev"

# Code to set up the parks development project.

echo 'kind: Service
apiVersion: v1
metadata:
  name: "mongodb-internal"
  labels:
    name: "mongodb"
  annotations:
    service.alpha.kubernetes.io/tolerate-unready-endpoints: "true"
spec:
  clusterIP: None
  ports:
    - name: mongodb
      port: 27017
  selector:
    name: "mongodb"' | oc create -f - -n ${GUID}-parks-dev

echo 'kind: Service
apiVersion: v1
metadata:
  name: "mongodb"
  labels:
    name: "mongodb"
spec:
  ports:
    - name: mongodb
      port: 27017
  selector:
    name: "mongodb"' | oc create -f - -n ${GUID}-parks-dev

echo 'kind: StatefulSet
apiVersion: apps/v1
metadata:
  name: "mongodb"
spec:
  serviceName: "mongodb-internal"
  replicas: 3
  selector:
    matchLabels:
      name: mongodb
  template:
    metadata:
      labels:
        name: "mongodb"
    spec:
      containers:
        - name: mongo-container
          image: "registry.access.redhat.com/rhscl/mongodb-34-rhel7:latest"
          ports:
            - containerPort: 27017
          args:
            - "run-mongod-replication"
          volumeMounts:
            - name: mongo-data
              mountPath: "/var/lib/mongodb/data"
          env:
            - name: MONGODB_DATABASE
              value: "parks"
            - name: MONGODB_USER
              value: "mongodb"
            - name: MONGODB_PASSWORD
              value: "mongodb"
            - name: MONGODB_ADMIN_PASSWORD
              value: "mongodb_admin_password"
            - name: MONGODB_REPLICA_NAME
              value: "rs0"
            - name: MONGODB_KEYFILE_VALUE
              value: "12345678901234567890"
            - name: MONGODB_SERVICE_NAME
              value: "mongodb-internal"
          readinessProbe:
            exec:
              command:
                - stat
                - /tmp/initialized
  volumeClaimTemplates:
    - metadata:
        name: mongo-data
        labels:
          name: "mongodb"
      spec:
        accessModes: [ ReadWriteOnce ]
        resources:
          requests:
            storage: "4Gi"' | oc create -f - -n ${GUID}-parks-dev

oc policy add-role-to-user admin system:serviceaccount:${GUID}-jenkins:jenkins -n ${GUID}-parks-dev
oc policy add-role-to-user admin system:serviceaccount:gpte-jenkins:jenkins -n ${GUID}-parks-dev

# Set up MLBParks Dev Application
oc new-build --binary=true --name="mlbparks" jboss-eap70-openshift:1.7 -n ${GUID}-parks-dev
#oc patch bc mlbparks -p '{"spec":{"resources":{"requests":{"cpu": 1,"memory": "2Gi"}}}}' -n ${GUID}-parks-dev
oc new-app ${GUID}-parks-dev/mlbparks:0.0-0 --name=mlbparks --allow-missing-imagestream-tags=true -l type=parksmap-backend -n ${GUID}-parks-dev
oc set triggers dc/mlbparks --remove-all -n ${GUID}-parks-dev
oc set probe dc/mlbparks --liveness  --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-dev
oc set probe dc/mlbparks --readiness --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-dev
oc expose dc mlbparks --port 8080 -n ${GUID}-parks-dev
oc expose svc mlbparks -n ${GUID}-parks-dev
oc create configmap mlbparks-config --from-literal="application-users.properties=Placeholder" --from-literal="application-roles.properties=Placeholder" --from-literal="APPNAME=MLB Parks (Dev)" -n ${GUID}-parks-dev
oc set volume dc/mlbparks --add --name=jboss-config --mount-path=/opt/eap/standalone/configuration/application-users.properties --sub-path=application-users.properties --configmap-name=mlbparks-config -n ${GUID}-parks-dev
oc set volume dc/mlbparks --add --name=jboss-config1 --mount-path=/opt/eap/standalone/configuration/application-roles.properties --sub-path=application-roles.properties --configmap-name=mlbparks-config -n ${GUID}-parks-dev

# Set up Nationalparks Dev Application
oc new-build --binary=true --name="nationalparks" redhat-openjdk18-openshift:1.2 -n ${GUID}-parks-dev
#oc patch bc nationalparks -p '{"spec":{"resources":{"requests":{"cpu": 1,"memory": "2Gi"}}}}' -n ${GUID}-parks-dev
oc new-app ${GUID}-parks-dev/nationalparks:0.0-0 --name=nationalparks --allow-missing-imagestream-tags=true -l type=parksmap-backend -n ${GUID}-parks-dev
oc set triggers dc/nationalparks --remove-all -n ${GUID}-parks-dev
oc set probe dc/nationalparks --liveness  --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-dev
oc set probe dc/nationalparks --readiness --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-dev
oc expose dc nationalparks --port 8080 -n ${GUID}-parks-dev
oc expose svc nationalparks -n ${GUID}-parks-dev
oc create configmap nationalparks-config --from-literal="application-users.properties=Placeholder" --from-literal="application-roles.properties=Placeholder" --from-literal="APPNAME=National Parks (Dev)" -n ${GUID}-parks-dev
oc set volume dc/nationalparks --add --name=jboss-config --mount-path=/opt/eap/standalone/configuration/application-users.properties --sub-path=application-users.properties --configmap-name=nationalparks-config -n ${GUID}-parks-dev
oc set volume dc/nationalparks --add --name=jboss-config1 --mount-path=/opt/eap/standalone/configuration/application-roles.properties --sub-path=application-roles.properties --configmap-name=nationalparks-config -n ${GUID}-parks-dev

# Set up ParksMap Dev Application
oc policy add-role-to-user view --serviceaccount=default -n ${GUID}-parks-dev
oc new-build --binary=true --name="parksmap" redhat-openjdk18-openshift:1.2 -n ${GUID}-parks-dev
oc new-app ${GUID}-parks-dev/parksmap:0.0-0 --name=parksmap --allow-missing-imagestream-tags=true -n ${GUID}-parks-dev
oc set triggers dc/parksmap --remove-all -n ${GUID}-parks-dev
oc set probe dc/parksmap --liveness  --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-dev
oc set probe dc/parksmap --readiness --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-dev
oc expose dc parksmap --port 8080 -n ${GUID}-parks-dev
oc expose svc parksmap -n ${GUID}-parks-dev
oc create configmap parksmap-config --from-literal="application-users.properties=Placeholder" --from-literal="application-roles.properties=Placeholder" --from-literal="APPNAME=ParksMap (Dev)" -n ${GUID}-parks-dev
oc set volume dc/parksmap --add --name=jboss-config --mount-path=/opt/eap/standalone/configuration/application-users.properties --sub-path=application-users.properties --configmap-name=parksmap-config -n ${GUID}-parks-dev
oc set volume dc/parksmap --add --name=jboss-config1 --mount-path=/opt/eap/standalone/configuration/application-roles.properties --sub-path=application-roles.properties --configmap-name=parksmap-config -n ${GUID}-parks-dev
