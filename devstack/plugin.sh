# lib/magnetodb

# Dependencies:
# ``functions`` file
# ``DEST``, ``STACK_USER`` must be defined

# ``stack.sh`` calls the entry points in this order:
#
# install_magnetodb
# configure_magnetodb
# start_magnetodb
# stop_magnetodb


# Save trace setting
XTRACE=$(set +o | grep xtrace)
set +o xtrace


# Defaults
# --------

# Set up default repos
MAGNETODB_BACKEND=${MAGNETODB_BACKEND:-cassandra}

MAGNETODB_REPO=${MAGNETODB_REPO:-${GIT_BASE}/stackforge/magnetodb.git}
MAGNETODB_BRANCH=${MAGNETODB_BRANCH:-master}

CCM_REPO=${CCM_REPO:-'https://github.com/pcmanus/ccm.git'}
CCM_BRANCH=${CCM_BRANCH:-master}
CCM_DIR=${CCM_DIR:-$DEST/ccm}
CASSANDRA_VER=${CASSANDRA_VER:-2.1.3}
CASSANDRA_CLUSTER_NAME=${CASSANDRA_CLUSTER_NAME:-test}
# By default CASSANDRA_AMOUNT_NODES = 3
# If you need more, then you need to change the number of loopback network interface aliases below
CASSANDRA_AMOUNT_NODES=${CASSANDRA_AMOUNT_NODES:-3}
CASSANDRA_REPL_FACTOR=${CASSANDRA_REPL_FACTOR:-3}

CASSANDRA_MAX_HEAP_SIZE=${CASSANDRA_MAX_HEAP_SIZE:-300M}
CASSANDRA_HEAP_NEWSIZE=${CASSANDRA_HEAP_NEWSIZE:-100M}

CASSANDRA_JOLOKIA_URL=${CASSANDRA_JOLOKIA_URL:-'http://labs.consol.de/maven/repository/org/jolokia/jolokia-jvm/1.2.2/jolokia-jvm-1.2.2-agent.jar'}

GRADLE_VER=${GRADLE_VER:-2.2.1}
GRADLE_REPO=${GRADLE_REPO:-"https://services.gradle.org/distributions/gradle-$GRADLE_VER-bin.zip"}

# Set up default directories
MAGNETODB_CONF_DIR=${MAGNETODB_CONF_DIR:-/etc/magnetodb}
MAGNETODB_DIR=${MAGNETODB_DIR:-$DEST/magnetodb}
MAGNETODB_LOG_DIR=${MAGNETODB_LOG_DIR:-/var/log/magnetodb}
MAGNETODB_RUN_USER=${MAGNETODB_RUN_USER:-$STACK_USER}

# Set up additional requirements
# Use this pattern: MAGNETODB_ADDITIONAL_REQ="Requirement_1\nRequirement_2\nRequirement_N"
# Example: MAGNETODB_ADDITIONAL_REQ="tox<1.7.0\nBabel>=0.9.6\ncassandra-driver>=1.0.0"

#Keystone variables
MAGNETODB_USER=${MAGNETODB_USER:-magnetodb}
MAGNETODB_SERVICE=${MAGNETODB_SERVICE:-magnetodb}
MAGNETODB_STREAMING_SERVICE=${MAGNETODB_STREAMING_SERVICE:-magnetodb-streaming}
MAGNETODB_MONITORING_SERVICE=${MAGNETODB_MONITORING_SERVICE:-magnetodb-monitoring}
MAGNETODB_MANAGEMENT_SERVICE=${MAGNETODB_MANAGEMENT_SERVICE:-magnetodb-management}
MAGNETODB_SERVICE_HOST=${MAGNETODB_SERVICE_HOST:-$SERVICE_HOST}
MAGNETODB_SERVICE_PORT=${MAGNETODB_SERVICE_PORT:-8480}
MAGNETODB_STREAMING_SERVICE_PORT=${MAGNETODB_STREAMING_SERVICE_PORT:-8481}
MAGNETODB_SERVICE_PROTOCOL=${MAGNETODB_SERVICE_PROTOCOL:-$SERVICE_PROTOCOL}

TEMPEST_REVISION=${TEMPEST_REVISION:-'7e22845c'}

# Functions
# ---------

# create_magnetodb_credentials() - Set up common required magnetodb credentials
#
# Tenant      User       Roles
# ------------------------------
# service     magnetodb     admin
function create_magnetodb_credentials() {
    SERVICE_TENANT=$(openstack project list | awk "/ $SERVICE_TENANT_NAME / { print \$2 }")
    ADMIN_ROLE=$(openstack role list | awk "/ admin / { print \$2 }")

    MAGNETODB_USER_ID=$(openstack user create \
        $MAGNETODB_USER \
        --password "$SERVICE_PASSWORD" \
        --project $SERVICE_TENANT \
        --email $MAGNETODB_USER@example.com \
        | grep " id " | get_field 2)

    openstack role add \
        $ADMIN_ROLE \
        --project $SERVICE_TENANT \
        --user $MAGNETODB_USER_ID

    if [[ "$KEYSTONE_CATALOG_BACKEND" = 'sql' ]]; then
        MAGNETODB_SERVICE=$(openstack service create \
            $MAGNETODB_SERVICE \
            --type=kv-storage \
            --description="MagnetoDB Service" \
            | grep " id " | get_field 2)
        openstack endpoint create \
            $MAGNETODB_SERVICE \
            --region RegionOne \
            --publicurl "$MAGNETODB_SERVICE_PROTOCOL://$MAGNETODB_SERVICE_HOST:$MAGNETODB_SERVICE_PORT/v1/data/\$(tenant_id)s" \
            --adminurl "$MAGNETODB_SERVICE_PROTOCOL://$MAGNETODB_SERVICE_HOST:$MAGNETODB_SERVICE_PORT/v1/data/\$(tenant_id)s" \
            --internalurl "$MAGNETODB_SERVICE_PROTOCOL://$MAGNETODB_SERVICE_HOST:$MAGNETODB_SERVICE_PORT/v1/data/\$(tenant_id)s"
        MAGNETODB_MONITORING_SERVICE=$(openstack service create \
            $MAGNETODB_MONITORING_SERVICE \
            --type=kv-monitoring \
            --description="MagnetoDB Monitoring Service" \
            | grep " id " | get_field 2)
        openstack endpoint create \
            $MAGNETODB_MONITORING_SERVICE \
            --region RegionOne \
            --publicurl "$MAGNETODB_SERVICE_PROTOCOL://$MAGNETODB_SERVICE_HOST:$MAGNETODB_SERVICE_PORT/v1/monitoring" \
            --adminurl "$MAGNETODB_SERVICE_PROTOCOL://$MAGNETODB_SERVICE_HOST:$MAGNETODB_SERVICE_PORT/v1/monitoring" \
            --internalurl "$MAGNETODB_SERVICE_PROTOCOL://$MAGNETODB_SERVICE_HOST:$MAGNETODB_SERVICE_PORT/v1/monitoring"
        MAGNETODB_MANAGEMENT_SERVICE=$(openstack service create \
            $MAGNETODB_MANAGEMENT_SERVICE \
            --type=kv-management \
            --description="MagnetoDB management Service" \
            | grep " id " | get_field 2)
        openstack endpoint create \
            $MAGNETODB_MANAGEMENT_SERVICE \
            --region RegionOne \
            --publicurl "$MAGNETODB_SERVICE_PROTOCOL://$MAGNETODB_SERVICE_HOST:$MAGNETODB_SERVICE_PORT/v1/management" \
            --adminurl "$MAGNETODB_SERVICE_PROTOCOL://$MAGNETODB_SERVICE_HOST:$MAGNETODB_SERVICE_PORT/v1/management" \
            --internalurl "$MAGNETODB_SERVICE_PROTOCOL://$MAGNETODB_SERVICE_HOST:$MAGNETODB_SERVICE_PORT/v1/management"
        MAGNETODB_STREAMING_SERVICE=$(openstack service create \
            $MAGNETODB_STREAMING_SERVICE \
            --type=kv-streaming \
            --description="MagnetoDB Streaming Service" \
            | grep " id " | get_field 2)
        openstack endpoint create \
            $MAGNETODB_STREAMING_SERVICE \
            --region RegionOne \
            --publicurl "$MAGNETODB_SERVICE_PROTOCOL://$MAGNETODB_SERVICE_HOST:$MAGNETODB_STREAMING_SERVICE_PORT/v1/data/\$(tenant_id)s" \
            --adminurl "$MAGNETODB_SERVICE_PROTOCOL://$MAGNETODB_SERVICE_HOST:$MAGNETODB_STREAMING_SERVICE_PORT/v1/data/\$(tenant_id)s" \
            --internalurl "$MAGNETODB_SERVICE_PROTOCOL://$MAGNETODB_SERVICE_HOST:$MAGNETODB_STREAMING_SERVICE_PORT/v1/data/\$(tenant_id)s"
    fi
}

function install_python27() {
    if is_ubuntu; then
        # Ubuntu 12.04 already has python2.7
        :
    elif is_fedora; then
        # Install PUIAS repository
        # PUIAS created and maintained by members of Princeton University and the Institute for Advanced Study and it’s fully compatible with RHEL6 / CentOS6.
        sudo wget -q http://springdale.math.ias.edu/data/puias/6/x86_64/os/RPM-GPG-KEY-puias -O /etc/pki/rpm-gpg/RPM-GPG-KEY-puias
        sudo rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-puias

        sudo sh -c "echo '[PUIAS_6_computational]
name=PUIAS computational Base \$releasever - \$basearch
mirrorlist=http://puias.math.ias.edu/data/puias/computational/\$releasever/\$basearch/mirrorlist
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-puias' > /etc/yum.repos.d/puias-computational.repo"

        sudo yum -y install python27 python27-tools python27-setuptools python27-devel
    fi
    sudo easy_install-2.7 pip
}

function install_jdk() {
     if is_ubuntu; then
         sudo apt-get -y install openjdk-7-jdk
         sudo update-alternatives --set java /usr/lib/jvm/java-7-openjdk-amd64/jre/bin/java
     elif is_fedora; then
         sudo yum -y install java-1.7.0-openjdk java-1.7.0-openjdk-devel
         sudo update-alternatives --set java /usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java
     fi
}

function install_jna() {
    echo "---  Installing JNA  ---"
    if is_ubuntu; then
        sudo apt-get -y install libjna-java
    elif is_fedora; then
        sudo yum -y install jna
    fi
}

function install_cassandra() {
    # for cassandra.io.libevwrapper extension.
    # The C extensions are not required for the driver to run, but they add support
    # for libev and token-aware routing with the Murmur3Partitioner.
    if is_ubuntu; then
        sudo apt-get -y install ant libyaml-0-2 libyaml-dev python-yaml libev4 libev-dev
    elif is_fedora; then
        sudo yum -y install ant ant-nodeps libyaml libyaml-devel PyYAML libev libev-devel
    fi

    #install Cassandra Cluster Manager
    git_clone $CCM_REPO $CCM_DIR $CCM_BRANCH

    if is_ubuntu; then
        sudo pip install -e $CCM_DIR
    elif is_fedora; then
        cd $CCM_DIR
        sudo python setup.py install
    fi

    install_jdk
    install_jna
}

# install_magnetodb() - Collect source and prepare
function install_magnetodb() {

    if [ "$MAGNETODB_BACKEND" == "cassandra" ]; then
        install_cassandra
    fi

    install_python27

    git_clone $MAGNETODB_REPO $MAGNETODB_DIR $MAGNETODB_BRANCH
    echo -e $MAGNETODB_ADDITIONAL_REQ >> $MAGNETODB_DIR/requirements.txt
    if is_ubuntu; then
        setup_develop $MAGNETODB_DIR
    elif is_fedora; then
        cd $MAGNETODB_DIR
        sudo pip2.7 install -r requirements.txt -r test-requirements.txt
    fi
}

function create_keyspace_cassandra() {
    local k_name=$1
    echo "CREATE KEYSPACE $k_name WITH REPLICATION = { 'class' : 'SimpleStrategy', 'replication_factor' : $CASSANDRA_REPL_FACTOR};" >> ~/.ccm/cql.txt
    }

function configure_cassandra() {
    #allocate loopback interfaces 127.0.0.2 - its a first address for second cassandra, the first node will be use 127.0.0.1
    n=1
    addr=2
    while [ $n -lt $CASSANDRA_AMOUNT_NODES ]; do
        echo "add secondary loopback 127.0.0.${addr}/8"
        #adding adresses only if doesnt exist
        sudo ip addr add 127.0.0.${addr}/8 dev lo || [ $? -eq 2 ] && true
        let addr=$addr+1
        let n=$n+1
    done

    ccm status $CASSANDRA_CLUSTER_NAME || ccm create $CASSANDRA_CLUSTER_NAME -v $CASSANDRA_VER

    sed -i -e 's/^#MAX_HEAP_SIZE="4G"$/MAX_HEAP_SIZE="'${CASSANDRA_MAX_HEAP_SIZE}'"/' ~/.ccm/repository/${CASSANDRA_VER}/conf/cassandra-env.sh
    sed -i -e 's/^#HEAP_NEWSIZE="800M"$/HEAP_NEWSIZE="'${CASSANDRA_HEAP_NEWSIZE}'"/' ~/.ccm/repository/${CASSANDRA_VER}/conf/cassandra-env.sh

    # Build cassandra custom index
    wget $GRADLE_REPO -O $DEST/gradle.zip
    cd $DEST
    unzip gradle.zip
    PATH=$PATH:$DEST/gradle-$GRADLE_VER/bin
    cd $MAGNETODB_DIR/contrib/cassandra/magnetodb-cassandra-custom-indices
    gradle build
    CCIV=`grep '^version' build.gradle | cut -d"'" -f2`
    cp $MAGNETODB_DIR/contrib/cassandra/magnetodb-cassandra-custom-indices/build/libs/magnetodb-cassandra-custom-indices-$CCIV.jar ~/.ccm/repository/${CASSANDRA_VER}/lib/

    # Populate cassandra nodes

    ccm populate -n $CASSANDRA_AMOUNT_NODES || true

    wget -q $CASSANDRA_JOLOKIA_URL -O ~/.ccm/jolokia-jvm-agent.jar

    create_keyspace_cassandra magnetodb

    echo 'CREATE TABLE magnetodb.table_info(tenant text, name text, id uuid, exists int, "schema" text, status text, internal_name text, last_update_date_time timestamp, creation_date_time timestamp, PRIMARY KEY(tenant, name));' >> ~/.ccm/cql.txt
    echo 'CREATE TABLE magnetodb.backup_info(tenant text, table_name text, id uuid, name text, status text, start_date_time timestamp, finish_date_time timestamp, location text, strategy map<text, text>, PRIMARY KEY((tenant, table_name), id));' >> ~/.ccm/cql.txt
    echo 'CREATE TABLE magnetodb.restore_info(tenant text, table_name text, id uuid, status text, backup_id uuid, start_date_time timestamp, finish_date_time timestamp, source text, PRIMARY KEY((tenant, table_name), id));' >> ~/.ccm/cql.txt
    echo 'CREATE TABLE magnetodb.dummy(id int PRIMARY KEY);' >> ~/.ccm/cql.txt
}

# configure_magnetodb() - Set config files, create data dirs, etc
function configure_magnetodb() {
    if [ "$MAGNETODB_BACKEND" == "cassandra" ]; then
        configure_cassandra
    fi

    if [[ ! -d $MAGNETODB_LOG_DIR ]]; then
        sudo mkdir -p $MAGNETODB_LOG_DIR
    fi

    if [[ ! -d $MAGNETODB_CONF_DIR ]]; then
        sudo mkdir -p $MAGNETODB_CONF_DIR
    fi
    sudo chown $MAGNETODB_RUN_USER $MAGNETODB_CONF_DIR
    sudo touch $MAGNETODB_LOG_DIR/magnetodb.log
    sudo touch $MAGNETODB_LOG_DIR/magnetodb-streaming.log
    sudo touch $MAGNETODB_LOG_DIR/magnetodb-async-task-executor.log
    sudo chown -R $MAGNETODB_RUN_USER $MAGNETODB_LOG_DIR
    cp -r $MAGNETODB_DIR/etc/* $MAGNETODB_CONF_DIR

    iniset $MAGNETODB_CONF_DIR/api-paste.ini filter:tokenauth auth_host $KEYSTONE_AUTH_HOST
    iniset $MAGNETODB_CONF_DIR/api-paste.ini filter:tokenauth auth_port $KEYSTONE_AUTH_PORT
    iniset $MAGNETODB_CONF_DIR/api-paste.ini filter:tokenauth auth_protocol $KEYSTONE_AUTH_PROTOCOL
    iniset $MAGNETODB_CONF_DIR/api-paste.ini filter:tokenauth admin_tenant_name $SERVICE_TENANT_NAME
    iniset $MAGNETODB_CONF_DIR/api-paste.ini filter:tokenauth admin_user $MAGNETODB_USER
    iniset $MAGNETODB_CONF_DIR/api-paste.ini filter:tokenauth admin_password $SERVICE_PASSWORD
    iniset $MAGNETODB_CONF_DIR/api-paste.ini filter:ec2authtoken auth_uri $KEYSTONE_AUTH_PROTOCOL://$KEYSTONE_AUTH_HOST:$KEYSTONE_AUTH_PORT/v2.0

    iniset $MAGNETODB_CONF_DIR/streaming-api-paste.ini filter:tokenauth auth_host $KEYSTONE_AUTH_HOST
    iniset $MAGNETODB_CONF_DIR/streaming-api-paste.ini filter:tokenauth auth_port $KEYSTONE_AUTH_PORT
    iniset $MAGNETODB_CONF_DIR/streaming-api-paste.ini filter:tokenauth auth_protocol $KEYSTONE_AUTH_PROTOCOL
    iniset $MAGNETODB_CONF_DIR/streaming-api-paste.ini filter:tokenauth admin_tenant_name $SERVICE_TENANT_NAME
    iniset $MAGNETODB_CONF_DIR/streaming-api-paste.ini filter:tokenauth admin_user $MAGNETODB_USER
    iniset $MAGNETODB_CONF_DIR/streaming-api-paste.ini filter:tokenauth admin_password $SERVICE_PASSWORD

    iniset $MAGNETODB_CONF_DIR/magnetodb-api.conf oslo_messaging_rabbit rabbit_password $RABBIT_PASSWORD
    iniset $MAGNETODB_CONF_DIR/magnetodb-async-task-executor.conf oslo_messaging_rabbit rabbit_password $RABBIT_PASSWORD
}

# configure_magnetodb_tempest_plugin() - copies magnetodb tempest plugin to tempest dir
function configure_magnetodb_tempest_plugin() {
    cd $TEMPEST_DIR
    git checkout $TEMPEST_REVISION
    iniset $TEMPEST_DIR/tox.ini testenv:magnetodb-stable commands "\n\tfind . -type f -name \"*.pyc\" -delete\n\tbash tools/pretty_tox.sh 'tempest.api.keyvalue.stable {posargs}'"
    iniset $TEMPEST_DIR/tox.ini testenv:magnetodb-stable setenv "{[tempestenv]setenv}"
    iniset $TEMPEST_DIR/tox.ini testenv:magnetodb-stable deps "{[tempestenv]deps}"
    iniset $TEMPEST_DIR/tox.ini testenv:magnetodb-in-progress commands "\n\tfind . -type f -name \"*.pyc\" -delete\n\tbash tools/pretty_tox.sh 'tempest.api.keyvalue.in_progress {posargs}'"
    iniset $TEMPEST_DIR/tox.ini testenv:magnetodb-in-progress setenv "{[tempestenv]setenv}"
    iniset $TEMPEST_DIR/tox.ini testenv:magnetodb-in-progress deps "{[tempestenv]deps}"
    iniset $TEMPEST_DIR/tox.ini testenv:magnetodb-not-ready commands "\n\tfind . -type f -name \"*.pyc\" -delete\n\tbash tools/pretty_tox.sh 'tempest.api.keyvalue.not_ready {posargs}'"
    iniset $TEMPEST_DIR/tox.ini testenv:magnetodb-not-ready setenv "{[tempestenv]setenv}"
    iniset $TEMPEST_DIR/tox.ini testenv:magnetodb-not-ready deps "{[tempestenv]deps}"
    cp -r $MAGNETODB_DIR/contrib/tempest/ $TEMPEST_DIR/..
}

# function screen_run - This function is a modification of function screen_it and allows you to run processes are not declared as service
# Helper to launch a service in a named screen
# screen_run service "command-line"
function screen_run {
    SCREEN_NAME=${SCREEN_NAME:-stack}
    SERVICE_DIR=${SERVICE_DIR:-${DEST}/status}
    USE_SCREEN=$(trueorfalse True USE_SCREEN)

    # Append the service to the screen rc file
    screen_rc "$1" "$2"

    if [[ "$USE_SCREEN" = "True" ]]; then
        screen -S $SCREEN_NAME -X screen -t $1
        if [[ -n ${SCREEN_LOGDIR} ]]; then
            screen -S $SCREEN_NAME -p $1 -X logfile ${SCREEN_LOGDIR}/screen-${1}.${CURRENT_LOG_TIME}.log
            screen -S $SCREEN_NAME -p $1 -X log on
            ln -sf ${SCREEN_LOGDIR}/screen-${1}.${CURRENT_LOG_TIME}.log ${SCREEN_LOGDIR}/screen-${1}.log
        fi

        # sleep to allow bash to be ready to be send the command - we are
        # creating a new window in screen and then sends characters, so if
        # bash isn't running by the time we send the command, nothing happens
        sleep 3

        NL=`echo -ne '\015'`
        # This fun command does the following:
        # - the passed server command is backgrounded
        # - the pid of the background process is saved in the usual place
        # - the server process is brought back to the foreground
        # - if the server process exits prematurely the fg command errors
        #   and a message is written to stdout and the service failure file
        # The pid saved can be used in screen_stop() as a process group
        # id to kill off all child processes
        screen -S $SCREEN_NAME -p $1 -X stuff "$2 & echo \$! >$SERVICE_DIR/$SCREEN_NAME/$1.pid; fg || echo \"$1 failed to start\" | tee \"$SERVICE_DIR/$SCREEN_NAME/$1.failure\"$NL"
    else
        # Spawn directly without screen
        old_run_process "$1" "$2" >$SERVICE_DIR/$SCREEN_NAME/$1.pid
    fi
}

function start_cassandra() {
    echo "=== Memory info ==="
    cat /proc/meminfo
    echo "===  Starting Cassandra Cluster  ==="
    ccm start
    timeout 120 sh -c 'while ! nc -z 127.0.0.1 9160; do sleep 1; done' || echo 'Could not login at 127.0.0.1:9160'
    # Start jolokia agent
    for ((i=1; i<=$CASSANDRA_AMOUNT_NODES; i++)); do java -jar ~/.ccm/jolokia-jvm-agent.jar --host 127.0.0.$i start `cat ~/.ccm/$CASSANDRA_CLUSTER_NAME/node$i/cassandra.pid`; done

    screen_rc 'cassandra' "n=1; addr=2; while [ \\\$n -lt $CASSANDRA_AMOUNT_NODES ]; do sudo ip addr add 127.0.0.\\\${addr}/8 dev lo || [ \\\$? -eq 2 ] && true; let addr=\\\$addr+1; let n=\\\$n+1; done; ccm start; \
              for ((i=1; i<=$CASSANDRA_AMOUNT_NODES; i++)); do java -jar /home/$STACK_USER/.ccm/jolokia-jvm-agent.jar --host 127.0.0.\\\$i start \`cat /home/$STACK_USER/.ccm/$CASSANDRA_CLUSTER_NAME/node\\\$i/cassandra.pid\`; done"
    echo "===  Load cql.txt  ==="
    test -e ~/.ccm/cql.state || ccm node1 cqlsh -f ~/.ccm/cql.txt
    rm -f ~/.ccm/cql.txt
    echo true > ~/.ccm/cql.state
}

function start_magnetodb_streaming() {
    if is_ubuntu; then
        use_Python="python"
    elif is_fedora; then
        use_Python="python2.7"
    fi

    cmd="timeout 120 sh -c 'while ! nc -z 127.0.0.1 9160; do sleep 1; done' || echo 'Could not login at 127.0.0.1:9160' && cd $MAGNETODB_DIR && $use_Python $MAGNETODB_DIR/bin/magnetodb-streaming-api-server \
        --config-file $MAGNETODB_CONF_DIR/magnetodb-streaming-api-server.conf"

    screen_run magnetodb-streaming "$cmd"
}

function start_magnetodb_async_task_executor() {
    if is_ubuntu; then
        use_Python="python"
    elif is_fedora; then
        use_Python="python2.7"
    fi

    cmd="timeout 120 sh -c 'while ! nc -z 127.0.0.1 9160; do sleep 1; done' || echo 'Could not login at 127.0.0.1:9160' && cd $MAGNETODB_DIR && $use_Python $MAGNETODB_DIR/bin/magnetodb-async-task-executor \
        --config-file $MAGNETODB_CONF_DIR/magnetodb-async-task-executor.conf"

    screen_run magnetodb-async-task-executor "$cmd"
}

# start_magnetodb() - Start running processes, including screen
function start_magnetodb() {

    if [ "$MAGNETODB_BACKEND" == "cassandra" ]; then
        start_cassandra
    fi

    if is_ubuntu; then
        use_Python="python"
    elif is_fedora; then
        use_Python="python2.7"
    fi
    screen_it magnetodb "timeout 120 sh -c 'while ! nc -z 127.0.0.1 9160; do sleep 1; done' || echo 'Could not login at 127.0.0.1:9160' && cd $MAGNETODB_DIR && $use_Python $MAGNETODB_DIR/bin/magnetodb-api-server --config-file $MAGNETODB_CONF_DIR/magnetodb-api-server.conf"
    start_magnetodb_streaming
    start_magnetodb_async_task_executor
}

function stop_cassandra(){
    # Stopping cluster
    ccm stop $CASSANDRA_CLUSTER_NAME
    # Kill the cassandra screen windows
    screen -S $SCREEN_NAME -p cassandra -X kill
}

# stop_magnetodb() - Stop running processes
function stop_magnetodb() {
    if [ "$MAGNETODB_BACKEND" == "cassandra" ]; then
        stop_cassandra
    fi

    # Kill the magnetodb screen windows
    screen -S $SCREEN_NAME -p magnetodb -X kill

    # Kill the magnetodb-streaming screen windows
    screen -S $SCREEN_NAME -p magnetodb-streaming -X kill

    # Kill the magnetodb-async-task-executor screen windows
    screen -S $SCREEN_NAME -p magnetodb-async-task-executor -X kill
}

function clean_magnetodb() {
    rm -f ~/.ccm/cql.state
    ccm remove $CASSANDRA_CLUSTER_NAME
    for i in `sudo ip addr show dev lo | grep 'secondary' | awk '{print $2}'`
        do
            sudo ip addr del $i dev lo
        done
    rm $DEST/gradle.zip
    rm -rf $DEST/gradle-$GRADLE_VER
    sudo rm -rf $MAGNETODB_CONF_DIR
}


# Restore xtrace
$XTRACE

# Dispatcher
if is_service_enabled magnetodb; then
    if [[ "$1" == "source" ]]; then
        # Initial source
        source $TOP_DIR/lib/magnetodb
    elif [[ "$1" == "stack" && "$2" == "install" ]]; then
        echo_summary "Installing Magnetodb"
        install_magnetodb
    elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
        echo_summary "Configuring Magnetodb"
        configure_magnetodb
        create_magnetodb_credentials
        if is_service_enabled tempest; then
            configure_magnetodb_tempest_plugin
        fi
    elif [[ "$1" == "stack" && "$2" == "extra" ]]; then
        echo_summary "Starting Magnetodb"
        start_magnetodb
    fi

    if [[ "$1" == "unstack" ]]; then
        echo "Stopping MagnetoDB"
        stop_magnetodb
        echo "Cleaning MagnetoDB data"
        clean_magnetodb
    fi

    if [[ "$1" == "clean" ]]; then
        echo "Cleaning Magnetodb"
        clean_magnetodb
    fi
fi
