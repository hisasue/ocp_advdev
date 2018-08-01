#!/bin/bash
# Setup Production Project (initial active services: Green)
if [ "$#" -ne 1 ]; then
    echo "Usage:"
    echo "  $0 GUID"
    exit 1
fi

GUID=$1
echo "Setting up Parks Production Environment in project ${GUID}-parks-prod"
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
    name: "mongodb"' | oc create -f - -n ${GUID}-parks-prod

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
    name: "mongodb"' | oc create -f - -n ${GUID}-parks-prod

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
            storage: "4Gi"' | oc create -f - -n ${GUID}-parks-prod

# Code to set up the parks production project. It will need a StatefulSet MongoDB, and two applications each (Blue/Green) for NationalParks, MLBParks and Parksmap.
# The Green services/routes need to be active initially to guarantee a successful grading pipeline run.

# To be Implemented by Student
oc policy add-role-to-user admin system:serviceaccount:${GUID}-jenkins:jenkins -n ${GUID}-parks-prod
oc policy add-role-to-user admin system:serviceaccount:gpte-jenkins:jenkins -n ${GUID}-parks-prod
oc policy add-role-to-group system:image-puller system:serviceaccounts:${GUID}-parks-prod -n ${GUID}-parks-prod

# MLBParks
oc new-build --binary=true --name="mlbparks" jboss-eap70-openshift:1.7 -n ${GUID}-parks-prod
#oc patch bc mlbparks -p '{"spec":{"resources":{"requests":{"cpu": 1,"memory": "2Gi"}}}}' -n ${GUID}-parks-prod && \
oc new-app ${GUID}-parks-prod/mlbparks:0.0-0 --name=mlbparks-green --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod
oc new-app ${GUID}-parks-prod/mlbparks:0.0-0 --name=mlbparks-blue  --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod 

for i in `seq 1 10`
do
 echo "Checking if dc/mlbparks is ready..."
 oc get dc mlbparks -n ${GUID}-parks-prod
 [[ "$?" == "1" ]] || break
 echo "...no. Sleeping 10 seconds."
 sleep 10
done

oc set triggers dc/mlbparks-green --remove-all -n ${GUID}-parks-prod && \
oc set triggers dc/mlbparks-blue  --remove-all -n ${GUID}-parks-prod && \
oc set probe dc/mlbparks-green --liveness  --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-prod && \
oc set probe dc/mlbparks-green --readiness --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-prod && \
oc set probe dc/mlbparks-blue  --liveness  --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-prod && \
oc set probe dc/mlbparks-blue  --readiness --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-prod && \
oc expose dc mlbparks-green --port 8080 -l type=parksmap-backend -n ${GUID}-parks-prod && \
#oc expose dc mlbparks-blue  --port 8080 -n ${GUID}-parks-prod && \
oc expose svc mlbparks-green --name mlbparks -n ${GUID}-parks-prod && \
oc create configmap mlbparks-green-config --from-literal="application-users.properties=Placeholder" --from-literal="application-roles.properties=Placeholder" --from-literal="APPNAME=MLB Parks (Green)" -n ${GUID}-parks-prod && \
oc create configmap mlbparks-blue-config  --from-literal="application-users.properties=Placeholder" --from-literal="application-roles.properties=Placeholder" --from-literal="APPNAME=MLB Parks (Blue)"  -n ${GUID}-parks-prod && \
oc set volume dc/mlbparks-green --add --name=jboss-config-green --mount-path=/opt/eap/standalone/configuration/application-users.properties --sub-path=application-users.properties --configmap-name=mlbparks-green-config -n ${GUID}-parks-prod && \
oc set volume dc/mlbparks-green --add --name=jboss-config1-green --mount-path=/opt/eap/standalone/configuration/application-roles.properties --sub-path=application-roles.properties --configmap-name=mlbparks-green-config -n ${GUID}-parks-prod && \
oc set volume dc/mlbparks-blue  --add --name=jboss-config-blue --mount-path=/opt/eap/standalone/configuration/application-users.properties --sub-path=application-users.properties --configmap-name=mlbparks-blue-config -n ${GUID}-parks-prod && \
oc set volume dc/mlbparks-blue  --add --name=jboss-config1-blue --mount-path=/opt/eap/standalone/configuration/application-roles.properties --sub-path=application-roles.properties --configmap-name=mlbparks-blue-config -n ${GUID}-parks-prod




# nationalparks
oc new-build --binary=true --name="nationalparks" redhat-openjdk18-openshift:1.2 -n ${GUID}-parks-prod
#oc patch bc nationalparks -p '{"spec":{"resources":{"requests":{"cpu": 1,"memory": "2Gi"}}}}' -n ${GUID}-parks-prod
oc new-app ${GUID}-parks-prod/nationalparks:0.0-0 --name=nationalparks-green --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod
oc new-app ${GUID}-parks-prod/nationalparks:0.0-0 --name=nationalparks-blue  --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod

for i in `seq 1 10`
do
 echo "Checking if dc/nationalparks is ready..."
 oc get dc nationalparks -n ${GUID}-parks-prod
 [[ "$?" == "1" ]] || break
 echo "...no. Sleeping 10 seconds."
 sleep 10
done

oc set triggers dc/nationalparks-green  --remove-all -n ${GUID}-parks-prod && \
oc set triggers dc/nationalparks-blue  --remove-all -n ${GUID}-parks-prod && \
oc set probe dc/nationalparks-green --liveness  --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-prod && \
oc set probe dc/nationalparks-green --readiness --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-prod && \
oc set probe dc/nationalparks-blue  --liveness  --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-prod && \
oc set probe dc/nationalparks-blue  --readiness --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-prod && \
oc expose dc nationalparks-green --port 8080 -l type=parksmap-backend -n ${GUID}-parks-prod && \
#oc expose dc nationalparks-blue  --port 8080 -n ${GUID}-parks-prod && \
oc expose svc nationalparks-green --name nationalparks -n ${GUID}-parks-prod && \
oc create configmap nationalparks-green-config --from-literal="application-users.properties=Placeholder" --from-literal="application-roles.properties=Placeholder" --from-literal="APPNAME=National Parks (Green)" -n ${GUID}-parks-prod && \
oc create configmap nationalparks-blue-config  --from-literal="application-users.properties=Placeholder" --from-literal="application-roles.properties=Placeholder" --from-literal="APPNAME=National Parks (Blue)"  -n ${GUID}-parks-prod && \
oc set volume dc/nationalparks-green --add --name=jboss-config-green --mount-path=/opt/eap/standalone/configuration/application-users.properties --sub-path=application-users.properties --configmap-name=nationalparks-green-config -n ${GUID}-parks-prod && \
oc set volume dc/nationalparks-green --add --name=jboss-config1-green --mount-path=/opt/eap/standalone/configuration/application-roles.properties --sub-path=application-roles.properties --configmap-name=nationalparks-green-config -n ${GUID}-parks-prod && \
oc set volume dc/nationalparks-blue  --add --name=jboss-config-blue --mount-path=/opt/eap/standalone/configuration/application-users.properties --sub-path=application-users.properties --configmap-name=nationalparks-blue-config -n ${GUID}-parks-prod && \
oc set volume dc/nationalparks-blue  --add --name=jboss-config1-blue --mount-path=/opt/eap/standalone/configuration/application-roles.properties --sub-path=application-roles.properties --configmap-name=nationalparks-blue-config -n ${GUID}-parks-prod

# parksmap
oc policy add-role-to-user view --serviceaccount=default -n ${GUID}-parks-prod && \
oc new-build --binary=true --name="parksmap" redhat-openjdk18-openshift:1.2 -n ${GUID}-parks-prod && \
#oc patch bc parksmap -p '{"spec":{"resources":{"requests":{"cpu": 1,"memory": "2Gi"}}}}' -n ${GUID}-parks-prod && \
oc new-app ${GUID}-parks-prod/parksmap:0.0-0 --name=parksmap-green --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod && \
oc new-app ${GUID}-parks-prod/parksmap:0.0-0 --name=parksmap-blue  --allow-missing-imagestream-tags=true -n ${GUID}-parks-prod && \

for i in `seq 1 10`
do
 echo "Checking if dc/parksmap is ready..."
 oc get dc parksmap -n ${GUID}-parks-prod
 [[ "$?" == "1" ]] || break
 echo "...no. Sleeping 10 seconds."
 sleep 10
done

oc set triggers dc/parksmap-green  --remove-all -n ${GUID}-parks-prod && \
oc set triggers dc/parksmap-blue  --remove-all -n ${GUID}-parks-prod && \
oc set probe dc/parksmap-green --liveness  --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-prod && \
oc set probe dc/parksmap-green --readiness --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-prod && \
oc set probe dc/parksmap-blue  --liveness  --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-prod && \
oc set probe dc/parksmap-blue  --readiness --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-parks-prod && \
oc expose dc parksmap-green --port 8080 -n ${GUID}-parks-prod && \
oc expose dc parksmap-blue  --port 8080 -n ${GUID}-parks-prod && \
oc expose svc parksmap-green --name parksmap -n ${GUID}-parks-prod && \
oc create configmap parksmap-green-config --from-literal="application-users.properties=Placeholder" --from-literal="application-roles.properties=Placeholder" --from-literal="APPNAME=ParksMap (Green)" -n ${GUID}-parks-prod && \
oc create configmap parksmap-blue-config  --from-literal="application-users.properties=Placeholder" --from-literal="application-roles.properties=Placeholder" --from-literal="APPNAME=ParksMap (Blue)"  -n ${GUID}-parks-prod && \
oc set volume dc/parksmap-green --add --name=jboss-config-green --mount-path=/opt/eap/standalone/configuration/application-users.properties --sub-path=application-users.properties --configmap-name=parksmap-green-config -n ${GUID}-parks-prod && \
oc set volume dc/parksmap-green --add --name=jboss-config1-green --mount-path=/opt/eap/standalone/configuration/application-roles.properties --sub-path=application-roles.properties --configmap-name=parksmap-green-config -n ${GUID}-parks-prod && \
oc set volume dc/parksmap-blue  --add --name=jboss-config-blue --mount-path=/opt/eap/standalone/configuration/application-users.properties --sub-path=application-users.properties --configmap-name=parksmap-blue-config -n ${GUID}-parks-prod && \
oc set volume dc/parksmap-blue  --add --name=jboss-config1-blue --mount-path=/opt/eap/standalone/configuration/application-roles.properties --sub-path=application-roles.properties --configmap-name=parksmap-blue-config -n ${GUID}-parks-prod
