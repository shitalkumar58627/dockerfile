#####################################################################
# Docker for JBoss service running SAE.org compiled web application
# 
# This will need the dependencies:
# Software (loaded via wgets against SOFTWARE_REPO_PATH): 
#   includes/jboss-eap-7.2.0.zip
#   includes/jdk-8u202-linux-x64.tar.gz
# Config: (Should be env specific mount)
#	saeconfig/saeweb.ini
#	saeconfig/?	
# Built Deployment:
#   deployments/*
# Source Libs:
# 	source/lib*
# APM: (This should be a mount, env specific settings in here)
#	elasticapm/* 
#
# Points to be careful of:
#	May be env specific files in:
#		saeconfig
#		deployments\SAEEnterpriseApp.ear\SAEEnterpriseApp.ear\DefaultWebApp.war\WEB-INF
#		elasticapm
#
# Build Process:
#	ant allJBoss
#	copy bin\jbossoutput -> jboss\deployments
#
#####################################################################

#Defaults, these can be replaced with --build-arge ${name}=${value} at build
ARG SOFTWARE_REPO_PATH=https://s3.amazonaws.com/sae-dev-docker/software_installation
ARG REDHAT_USER=sae-developer
ARG REDHAT_PASS='q4LT$A9z&4V$94@*JF^'
ARG APM_JAR_URL=https://repo1.maven.org/maven2/co/elastic/apm/elastic-apm-agent/1.17.0/elastic-apm-agent-1.17.0.jar

#########################Docker for redhat7#####################################################################

FROM  registry.redhat.io/rhel7
LABEL Shitalkumar dhawle <sdhawale@sae.org>
LABEL Tim Pearce <tpearce@sae.org>

ARG SOFTWARE_REPO_PATH
ARG REDHAT_USER
ARG REDHAT_PASS
ARG APM_JAR_URL

RUN subscription-manager register  --username ${REDHAT_USER} --password ${REDHAT_PASS} --auto-attach  && \
    subscription-manager refresh

RUN yum install wget -y \
    yum install curl -y \
    yum install unzip -y \
	yum install glibc.i686 -y \
	yum install glibc.i386 -y \
	yum install libstdc++.i686 -y \
	yum install  glibc-common glibc -y 

#################################################################################################################
################################## Envirnment for StampPDFBatch ############################################################
WORKDIR /usr/local/StampPDFBatch
ENV HOME=/usr/local/StampPDFBatch
ADD StampPDFBatch_60_L26_64 $HOME
RUN $HOME/./install.sh

# Clear package manager metadata
RUN yum clean all && [ ! -d /var/cache/yum ] || rm -rf /var/cache/yum

##########################Installing OracleJDK and Preparing environment ########################################

ENV JAVA_HOME /opt/java
ENV PATH="/opt/java/bin:${PATH}"
ENV JBOSS_USER='jboss'

# Install Oracle Java8
ENV JAVA_VERSION 8u202
ENV SOFTWARE_REPO ${SOFTWARE_REPO_PATH}


RUN wget ${SOFTWARE_REPO}/jdk-${JAVA_VERSION}-linux-x64.tar.gz && \
 tar -xvf jdk-${JAVA_VERSION}-linux-x64.tar.gz                                                              && \
 rm jdk*.tar.gz && \
 mv jdk* ${JAVA_HOME}

###################################### JBOSS-EAP-7.2 Installing ###################################################
# Create a user and group used to launch processes
# The user ID 1000 is the default for the first "regular" user on Fedora/RHEL,
# so there is a high chance that this ID will be equal to the current user
# making it easier to use volumes (no permission issues)
###################################################################################################################
RUN mkdir -p /weblogic/jboss/jboss-eap-7.2

ENV JBOSS_BASE=/weblogic
ENV JBOSS_HOME=/weblogic/jboss

RUN groupadd -r jboss -g 1000 \
 && useradd -l -u 1000 -r -g jboss -m -d /weblogic/jboss/jboss-eap-7.2 -s /sbin/nologin -c "jboss user" jboss \
 && chmod -R 755 /weblogic/jboss/jboss-eap-7.2 \
 && mkdir ${JBOSS_BASE} > /dev/null 2&>1;  chmod 755 ${JBOSS_BASE} ; chown -R jboss:jboss ${JBOSS_BASE} \
 && echo 'jboss ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers 
 
WORKDIR ${JBOSS_HOME}
USER ${JBOSS_USER}

RUN wget ${SOFTWARE_REPO}/jboss-eap-7.2.0.zip

RUN sh -c 'unzip -q jboss-eap-7.2.0.zip' && \
	rm -rf /weblogic/jboss/jboss-eap-7.2.0.zip

#Setup JBoss Home env and add to path
ENV JBOSS_HOME=/weblogic/jboss/jboss-eap-7.2
ENV PATH="/opt/java/bin:${JBOSS_HOME}/bin:${PATH}"

WORKDIR ${JBOSS_HOME}

RUN mkdir -p /weblogic/jboss/source/
RUN mkdir -p /weblogic/weblogic/elasticapm 
RUN mkdir -p /weblogic/debug/jboss/dev3  

#Download and copy APM agent jar files
RUN wget ${APM_JAR_URL} -O /weblogic/weblogic/elasticapm/apm-agent.jar

#Copy in server Configuration
COPY conf/standalone.conf bin/standalone.conf
COPY conf/standalone.xml standalone/configuration/standalone.xml
COPY --chown=jboss:jboss start.sh start.sh
RUN chmod +x start.sh

COPY modules modules

#Copy in Deployment, any application dependencies 
RUN touch standalone/deployments/SAEEnterpriseApp.ear.dodeploy
COPY source /weblogic/jboss/source
COPY deployments standalone/deployments


#Things that will need mounted from configmaps or secrets
#Not sure what this is for, contains the WEB-INF files?
COPY saeconfig /weblogic/jboss/jboss-eap-7.2/bin/saeconfig

########## Expose the ports we're interested in, 8080, for webinterface and 9990 for Admin Console ###################
EXPOSE 9990 8080 8009

######################### This will boot JBoss in the standalone mode and bind to all interface ######################
CMD ["/weblogic/jboss/jboss-eap-7.2/start.sh"]  