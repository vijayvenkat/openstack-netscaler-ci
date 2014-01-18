#!/bin/bash
ROOT_DIR='/opt/stack'
DEVSTACK_DIR=$ROOT_DIR/devstack
DEPOT_FILES_DIR=$ROOT_DIR/depot_files
DEPOT_LOCALRC=$DEPOT_FILES_DIR/localrc
DEPOT_NEUTRON_NCC_CONF=$DEPOT_FILES_DIR/ncc_in_neutron.conf

STACK_SH=$1
CHANGE_REF=$2
CHANGE_REF_PROJECT=$3
DEP_CHANGE_REF=$4
DEP_CHANGE_REF_PROJECT=$5


function error_exit
{

    if [ "$?" != "0" ]; then
            echo "Error: ""$1"
	            exit 1
    fi
}

function wait_till_port_open
{
	PORT_NUM=$1
	# Waiting 2 minutes for the service to be up
	for i in {1..120}
	do
		port_open=`netstat -an | grep $PORT_NUM | wc -l | tr  -d ' '`
		if [ $port_open -eq '1' ]
		then
			echo "Port "$PORT_NUM" is UP"
			return
		fi
		sleep 1
	done
	echo "Error: Timed out waiting for service to be UP on port "$PORT_NUM
	exit 1
}

function configure_ncc_in_openstack
{
	#introduce netscaler controlcenter config files
	echo "Configuring NetScaler as the default LBaaS provider...."
	sed -i 's!HaproxyOnHostPluginDriver:default!HaproxyOnHostPluginDriver\nservice_provider=LOADBALANCER:NetScaler:neutron.services.loadbalancer.drivers.netscaler.netscaler_driver.NetScalerPluginDriver:default!g' /etc/neutron/neutron.conf
	cat $DEPOT_NEUTRON_NCC_CONF >> /etc/neutron/neutron.conf
}

function patch_submited_change
{
	# patch the newly submittedfiles
	if [ -n "$CHANGE_REF_PROJECT" ]
	then
		echo "Patching changeref submitted"
		cd $ROOT_DIR/$CHANGE_REF_PROJECT
		git checkout master
		git fetch https://review.openstack.org/openstack/$CHANGE_REF_PROJECT $CHANGE_REF && git checkout FETCH_HEAD
		#TODO: TBR, to be removed, instrumentation for indrucing error./tmp/netscaler_driver.py
	else
		echo "Nothing to be patched"
		return
	fi

	if [ -n "$DEP_CHANGE_REF_PROJECT" ]
	then
		echo "Getting dependent changeref"
		cd $ROOT_DIR/$DEP_CHANGE_REF_PROJECT
		git fetch https://review.openstack.org/openstack/$DEP_CHANGE_REF_PROJECT $DEP_CHANGE_REF 
		if [ $CHANGE_REF_PROJECT != $DEP_CHANGE_REF_PROJECT ]
		then
			# if different project bring patch to be HEAD
			echo "Checking out dependent changeref"
			git checkout FETCH_HEAD
		else
			# if same project merge the dependent patch to the changeref
			# TODO: Hopefully no merge conflict
			echo "Merging dependent changeref"
			git merge FETCH_HEAD
		fi
		python setup.py install
	fi
}

function restart_neutron
{
	# restart neutron
	PID=`ps ax | grep neutron-server | grep -v grep | awk '{print $1}'`
	echo "Stopping neutron process: $PID"
	kill -9 $PID
	NL=`echo -ne '\015'`
	screen -S stack -p 'q-svc' -X stuff 'cd /opt/stack/neutron && python /usr/local/bin/neutron-server --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini'$NL
	check_neutron_is_up
}

function  check_neutron_is_up
{
	wait_till_port_open 9696
}

function  check_devstack_is_up
{
	check_neutron_is_up
}

function run_stack_sh
{
	if [ ! -e $DEPOT_LOCALRC ]
	then
		echo "Error: unable to source localrc to setup devstack"
		exit 1
	fi

	# Copy the localrc, the settings that is required to setup devstack.
	cp $DEPOT_LOCALRC $DEVSTACK_DIR

	# change devstack git repo sync to use https. "git:" is blocked in lab network
	sed -i 's!git://git.openstack.org!https://git.openstack.org!g' $DEVSTACK_DIR/stackrc
	cd $DEVSTACK_DIR
	./unstack.sh > /tmp/unstack.out 2>&1
	./stack.sh > /tmp/stack.out 2>&1
	check_devstack_is_up

	configure_ncc_in_openstack
}
#mkdir $DEVSTACK_DIR
#cd $ROOT_DIR
#git clone https://github.com/openstack-dev/devstack.git
#error_exit "Unable to clone devstack"
#cd $DEVSTACK_DIR

if [ $STACK_SH == "RUN" ]
then
	echo "Running stack.sh"
	run_stack_sh
elif [ $STACK_SH == "SKIP" ]
then
	echo "Skipping stack.sh"
else
	echo "Expecting either stack.sh RUN or stack.sh SKIP"
	exit 1
fi

patch_submited_change
restart_neutron
exit 0