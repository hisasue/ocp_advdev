#!/bin/bash
# Setup Jenkins Project
if [ "$#" -ne 3 ]; then
    echo "Usage:"
    echo "  $0 GUID REPO CLUSTER"
    echo "  Example: $0 wkha https://github.com/wkulhanek/ParksMap na39.openshift.opentlc.com"
    exit 1
fi

GUID=$1
REPO=$2
CLUSTER=$3
echo "Setting up Jenkins in project ${GUID}-jenkins from Git Repo ${REPO} for Cluster ${CLUSTER}"

# Code to set up the Jenkins project to execute the
# three pipelines.
# This will need to also build the custom Maven Slave Pod
# Image to be used in the pipelines.
# Finally the script needs to create three OpenShift Build
# Configurations in the Jenkins Project to build the
# three micro services. Expected name of the build configs:
# * mlbparks-pipeline
# * nationalparks-pipeline
# * parksmap-pipeline
# The build configurations need to have two environment variables to be passed to the Pipeline:
# * GUID: the GUID used in all the projects
# * CLUSTER: the base url of the cluster used (e.g. na39.openshift.opentlc.com)

# To be Implemented by Student
oc policy add-role-to-user admin system:serviceaccount:gpte-jenkins:jenkins -n ${GUID}-jenkins
#oc new-app jenkins-persistent --param ENABLE_OAUTH=true --param MEMORY_LIMIT=2Gi --param VOLUME_CAPACITY=4Gi -e GUID=${GUID} -e REPO=${REPO} -e CLUSTER=${CLUSTER} -n ${GUID}-jenkins
oc new-app jenkins-persistent --param ENABLE_OAUTH=true --param VOLUME_CAPACITY=4Gi -e GUID=${GUID} -e REPO=${REPO} -e CLUSTER=${CLUSTER} -n ${GUID}-jenkins
oc set resources dc/jenkins --limits=memory=3Gi,cpu=1.5 --requests=memory=3Gi,cpu=1.5 -n ${GUID}-jenkins
#yum install -y docker
#cd $DIR/../templates/jenkins-slave-appdev/
#oc new-build --name=jenkins-slave-maven-centos --dockerfile=$'FROM docker.io/openshift/jenkins-slave-maven-centos7:v3.9\nUSER root\nRUN yum -y install skopeo apb && yum clean all\nUSER 1001' -n ${GUID}-jenkins && \
oc new-build --name=jenkins-slave-maven-appdev-build --to="docker-registry-default.apps.na39.openshift.opentlc.com/${GUID}-jenkins/jenkins-slave-maven-appdev:v3.9" --dockerfile=$'FROM docker.io/openshift/jenkins-slave-maven-centos7:v3.9\nUSER root\nRUN yum -y install skopeo apb && yum clean all\nUSER 1001' -n ${GUID}-jenkins && \

#  sleep 10 && \
#oc tag jenkins-slave-maven-centos7:v3.9 jenkins-slave-maven-appdev:v3.9 -n ${GUID}-jenkins
#cd ./Infrastructure/templates/jenkins-slave-appdev/
#docker build . -t docker-registry-default.apps.na39.openshift.opentlc.com/${GUID}-jenkins/jenkins-slave-maven-appdev:v3.9
#docker login -u thisasue-redhat.com -p $(oc whoami -t) docker-registry-default.apps.na39.openshift.opentlc.com
#docker push docker-registry-default.apps.na39.openshift.opentlc.com/${GUID}-jenkins/jenkins-slave-maven-appdev:v3.9
#cd ../
#oc process -f ./Infrastructure/templates/bc-jenkins-slave.yaml \
#  -p GUID=${GUID} \
#  -p REPO=${REPO} \
#  -p CLUSTER=${CLUSTER} \
#  -n ${GUID}-jenkins \
#  | oc create -f -

oc process -f ./Infrastructure/templates/bc-app.yaml \
  -p GUID=${GUID} \
  -p REPO=${REPO} \
  -p CLUSTER=${CLUSTER} \
  -n ${GUID}-jenkins \
  | oc create -n ${GUID}-jenkins -f -
 
./Infrastructure/bin/waitUntilPodReady.sh jenkins ${GUID}-jenkins

sleep 400
