FROM eclipse-temurin:11-centos7

# Install packages necessary to run EAP
RUN yum update -y && yum -y install xmlstarlet saxon augeas bsdtar unzip && yum clean all

# Create a user and group used to launch processes
# The user ID 1000 is the default for the first "regular" user on Fedora/RHEL,
# so there is a high chance that this ID will be equal to the current user
# making it easier to use volumes (no permission issues)
RUN groupadd -r jboss -g 1000 && useradd -u 1000 -r -g jboss -m -d /opt/jboss -s /sbin/nologin -c "JBoss user" jboss && \
    chmod 755 /opt/jboss

# Set the working directory to jboss' user home directory
WORKDIR /opt/jboss

# Specify the user which should be used to execute all commands below
USER jboss

# User root user to install software
USER root

# Install necessary packages
RUN yum -y install java-1.8.0-openjdk-devel && yum clean all

# Switch back to jboss user
USER jboss

# Set the JAVA_HOME variable to make it clear where Java is located
ENV JAVA_HOME /usr/lib/jvm/java

# Set the WILDFLY_VERSION env variable
ENV WILDFLY_VERSION 23.0.2.Final
ENV WILDFLY_SHA1 cd79cddc334cd58c7b9a8fc65439d4152c8d2fb8
ENV JBOSS_HOME /opt/jboss/wildfly

USER root

# Add the WildFly distribution to /opt, and make wildfly the owner of the extracted tar content
# Make sure the distribution is available from a well-known place
RUN cd $HOME \
    && curl -O https://download.jboss.org/wildfly/$WILDFLY_VERSION/wildfly-$WILDFLY_VERSION.tar.gz \
    && sha1sum wildfly-$WILDFLY_VERSION.tar.gz | grep $WILDFLY_SHA1 \
    && tar xf wildfly-$WILDFLY_VERSION.tar.gz \
    && mv $HOME/wildfly-$WILDFLY_VERSION $JBOSS_HOME \
    && rm wildfly-$WILDFLY_VERSION.tar.gz \
    && chown -R jboss:0 ${JBOSS_HOME} \
    && chmod -R g+rw ${JBOSS_HOME}

# Ensure signals are forwarded to the JVM process correctly for graceful shutdown
ENV LAUNCH_JBOSS_IN_BACKGROUND true

USER jboss

# Expose the ports we're interested in
EXPOSE 8080

####### ENVIRONMENT ############
ENV JBOSS_BIND_ADDRESS 0.0.0.0
ENV KIE_REPOSITORY https://download.jboss.org/jbpm/release
ENV KIE_VERSION 7.74.1.Final
ENV KIE_CLASSIFIER wildfly23
ENV KIE_CONTEXT_PATH business-central
ENV KIE_SERVER_ID sample-server
ENV KIE_SERVER_LOCATION http://localhost:8080/kie-server/services/rest/server
ENV EXTRA_OPTS -Dorg.jbpm.ht.admin.group=admin -Dorg.uberfire.nio.git.ssh.host=$JBOSS_BIND_ADDRESS

####### JBPM-WB ############
RUN curl -o $HOME/jbpm-server-dist.zip $KIE_REPOSITORY/$KIE_VERSION/jbpm-server-$KIE_VERSION-dist.zip && \
unzip -o -q jbpm-server-dist.zip -d $JBOSS_HOME &&  \
rm -rf $HOME/jbpm-server-dist.zip

####### CONFIGURATION ############
USER root
ADD start_jbpm-wb.sh $JBOSS_HOME/bin/start_jbpm-wb.sh
ADD update_db_config.sh $JBOSS_HOME/bin/update_db_config.sh
RUN chown jboss:jboss $JBOSS_HOME/standalone/deployments/*
RUN chown jboss:jboss $JBOSS_HOME/bin/start_jbpm-wb.sh
RUN chown jboss:jboss $JBOSS_HOME/bin/update_db_config.sh
RUN sed -i '/<property name="org.kie.server.location" value="http:\/\/localhost:8080\/kie-server\/services\/rest\/server"\/>/d' $JBOSS_HOME/standalone/configuration/standalone.xml
RUN sed -i '/<property name="org.kie.server.id" value="sample-server"\/>/d' $JBOSS_HOME/standalone/configuration/standalone.xml

RUN mkdir -p $JBOSS_HOME/bin/.niogit
RUN chown jboss:jboss $JBOSS_HOME/bin/.niogit

####### CUSTOM JBOSS USER ############
# Switchback to jboss user
USER jboss

####### EXPOSE INTERNAL JBPM GIT PORT ############
EXPOSE 8001

RUN chmod +x $JBOSS_HOME/bin/start_jbpm-wb.sh
RUN chmod +x $JBOSS_HOME/bin/update_db_config.sh

####### RUNNING JBPM-WB ############
WORKDIR $JBOSS_HOME/bin/
CMD ["./start_jbpm-wb.sh"]