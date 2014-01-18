#!/usr/bin/env bash
ALL_PARAMS="$@"
CHANGE_REF=$2

ROOT_DIR='/opt/stack'
DEVSTACK_DIR=$ROOT_DIR/devstack
TEMPEST_DIR=$ROOT_DIR/tempest
DEPOT_FILES_DIR=$ROOT_DIR/depot_files
DEPOT_LOCALRC=$DEPOT_FILES_DIR/localrc
DEPOT_NEUTRON_NCC_CONF=$DEPOT_FILES_DIR/ncc_in_neutron.conf
PERFORCE_BASE='/spare/nsmkernel'
TEST_INFRA_BASE=$PERFORCE_BASE/usr.src/sdx/controlcenter/build_resources/test_infra
# if change ref is 'refs/changes/24/57524/9'
# LOG_FOLDER_CHANGE_PART == Change_57524_PatchSet_9
#CHANGE_REF='refs/changes/24/57524/9'
LOG_FOLDER_CHANGE_PART=`echo $CHANGE_REF | awk -F '/' '{print "Change_" $4 "_PatchSet_" $5 "_"}'`
LOG_FOLDER_DATE_PART=`date +%Y-%m-%d_%H_%M_%S`
LOG_FOLDER_NAME=$LOG_FOLDER_CHANGE_PART$LOG_FOLDER_DATE_PART
LOG_ARCHIVE_NAME=$LOG_FOLDER_NAME.tar.gz
LOG_ARCHIVE=/tmp/$LOG_ARCHIVE_NAME
LOG_FOLDER=/tmp/$LOG_FOLDER_NAME


REQUIRED_LOGS=5

OPENSTACK_SVC_PORT=4311
ADMIN_SVC_PORT=4301
LB_SVC_PORT=4302

NEUTRON_PORT=9696

XENSERVER_IP=10.102.31.27

DEVSTACK_VM_IP=10.102.31.113
DEVSTACK_VM_UUID='71d4e326-5ad4-5484-634a-9944741bbe3b'
DEVSTACK_BASE_IMG_SS_UUID='9c4a0def-7706-8985-fb41-9942a88be65a'


NS_1_VM_IP=10.102.31.108
NS_1_VM_UUID='819c5d2b-b296-cfa3-562a-d2537382b721'
NS_1_BASE_IMG_SS_UUID='0fc4df12-851f-1054-b64b-b62793d1c463'

CONTROLCENTER_VM_IP=10.102.31.70

# all console outputs/errors go to <logfolder>/debug.log
mkdir $LOG_FOLDER
# Redirecting all std output and std error redirection to debug.log
exec &> $LOG_FOLDER/debug.log

rm -rf /tmp/debug.log
ln -s $LOG_FOLDER/debug.log /tmp/debug.log 
rm -rf /tmp/progress.log
ln -s $LOG_FOLDER/progress.log /tmp/progress.log 

function debug_msg
{
	echo "$1" >> $LOG_FOLDER/debug.log
}

function progress_msg
{
	debug_msg "$1"
	echo "$1" >> $LOG_FOLDER/progress.log
}

function cleanup_logs
{
	# Each cycle has three entries  
	# 1) /tmp/Change_57524_PatchSet_9_2014-01-08_17_17_47 (dir)
	# 2) /tmp/Change_57524_PatchSet_9_2014-01-08_17_17_47.tar.gz 
	# 3) /tmp/Change_57524_PatchSet_9_2014-01-08_17_24_32_report_successful.html
	required_logs=$((REQUIRED_LOGS * 3))
	total_logs=`ls -td /tmp/Change*  | wc -l`
	logs_to_delete=$(( total_logs - required_logs))

	if [ $logs_to_delete -gt 0 ]
	then
		ls -td /tmp/Change* | tail -n $logs_to_delete | xargs rm -rf 
	fi
}

function package_log_files
{
	cleanup_logs
	mkdir $LOG_FOLDER/devstack
	# copy all devstack files, similar to what the OS test infrastructure is doing. Atleast the screen log files
	scp -r stack@$DEVSTACK_VM_IP:/opt/stack/tempest/.testrepository $LOG_FOLDER/devstack
	scp stack@$DEVSTACK_VM_IP:/opt/stack/tempest/tempest.log $LOG_FOLDER/devstack
	mkdir $LOG_FOLDER/controlcenter
	cp /var/controlcenter/log/*  $LOG_FOLDER/controlcenter
	mkdir $LOG_FOLDER/netscaler	
	scp nsroot@$NS_1_VM_IP:/var/log/ns.log  $LOG_FOLDER/netscaler
	scp nsroot@$NS_1_VM_IP:/nsconfig/ns.conf $LOG_FOLDER/netscaler
	ssh stack@$DEVSTACK_VM_IP /tmp/package_devstack_logs.sh
	scp -r stack@$DEVSTACK_VM_IP:/opt/stack/log_dest $LOG_FOLDER/devstack
	tar cvfz $LOG_ARCHIVE $LOG_FOLDER
	echo "LOG="$LOG_ARCHIVE >> /tmp/result.out
}

function testreport_msg
{
	echo "<html>" >> $LOG_FOLDER/report.html
	echo "<h2>Test Results for " $LOG_FOLDER_CHANGE_PART "</h2>" >> $LOG_FOLDER/report.html
	echo "<h3>Test executed at "$LOG_FOLDER_DATE_PART".</h3>" >> $LOG_FOLDER/report.html
	if [ $# -eq "0" ]
	then
		echo '<h3 style='\''color:#FF4500'\''>SETUP FAILED.</h3>' >> $LOG_FOLDER/report.html
		mv $LOG_FOLDER/report.html $LOG_FOLDER"_report_failure.html"
		echo "REPORT="$LOG_FOLDER"_report_failure.html" > /tmp/result.out
		return
	fi
	
	RESULTS=$1
	echo '<table border="1" style="border-collapse:collapse;width:900px" cellpadding="5">' >> $LOG_FOLDER/report.html
	echo "<tr>" >> $LOG_FOLDER/report.html
	echo '<th align="left" style="background-color:silver">Test</th>' >> $LOG_FOLDER/report.html
	echo '<th align="left" style="background-color:silver">Result</th>' >> $LOG_FOLDER/report.html
	echo "</tr>" >> $LOG_FOLDER/report.html
	echo "$RESULTS" | awk -v q="'" '{print "<tr>" "<td align=" q "left" q ">" $1 "</td>" "<td align=" q "left" q ">" $2 "</td>"}' >> $LOG_FOLDER/report.html
	echo "</html>" >>  $LOG_FOLDER/report.html
	cat $LOG_FOLDER/report.html | sed 's!>successful:! style='\''color:#228B22'\''><b>successful</b>!g' > $LOG_FOLDER/report1.html	
	cat $LOG_FOLDER/report1.html | sed 's!>failure:! style='\''color:#FF4500'\''><b>failure</b>!g' > $LOG_FOLDER/report2.html
	is_failed=`grep failure $LOG_FOLDER/report1.html | wc -l | tr  -d ' '`
	if [ $is_failed -eq '0' ]
	then
		mv $LOG_FOLDER/report2.html $LOG_FOLDER"_report_successful.html"
		echo "REPORT="$LOG_FOLDER"_report_successful.html" > /tmp/result.out
	else
		mv $LOG_FOLDER/report2.html $LOG_FOLDER"_report_failure.html"
		echo "REPORT="$LOG_FOLDER"_report_failure.html" > /tmp/result.out
	fi
}

function error_exit
{
    if [ "$?" != "0" ]; then
		get_out "Error: ""$1"
    fi
}

function get_out
{
	progress_msg "$1"
	testreport_msg
	package_log_files
	exit 1
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
			debug_msg "Port "$PORT_NUM" is UP"
			return
		fi
		sleep 1
	done
	get_out "Error: Timed out waiting for ControlCenter_service to be UP on port "$PORT_NUM
}

function wait_till_remote_port_open
{
	USER_AT_HOST_IP=$1
	PORT_NUM=$2
	debug_msg "Checking for "$USER_AT_HOST_IP":"$PORT_NUM
	# Waiting 2 minutes for the service to be up
	for i in {1..120}
	do
		port_open=`ssh -o ConnectTimeout=5 $USER_AT_HOST_IP "netstat -an | grep "$PORT_NUM" | wc -l | tr  -d ' '"`
		if [ $port_open -eq '1' ]
		then
			debug_msg $USER_AT_HOST_IP":"$PORT_NUM" is UP"
			return
		fi
		sleep 1
	done
	get_out "Error: Timed out waiting for "$USER_AT_HOST_IP":"$PORT_NUM
}


function wait_till_remote_host_up
{
	HOST_IP=$1
	COMMAND=$2
	# Waiting 4 minutes for the NS to be up
	for i in {1..240}
	do
		ssh -o ConnectTimeout=5 $HOST_IP $COMMAND
		if [ $? -eq '0' ]
		then
			debug_msg "Remote host "$HOST_IP" is UP."
			return
		fi
		sleep 1
	done
	get_out "Error: TimedOut waiting for Machine "$HOST_IP" to be up.."
}

function add_ns_to_controlcenter
{
	NSIP=$1
	progress_msg "Adding NetScaler-'"$NSIP"' to ControlCenter..."
	PAYLOAD='<device name="device1"  type="LBDEVICE"  producttype="LOADBALANCER" productname="NetScalerVPX" productversion="10.0">'
	PAYLOAD=$PAYLOAD'<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="NetScalerConfig">'
	PAYLOAD=$PAYLOAD'<config_address ip="'$NSIP'" port="80" protocol="HTTP" />'
	PAYLOAD=$PAYLOAD'<credentials  username="nsroot" password="nsroot" timeout="30" /></config></device>'
	rm -rf /tmp/device_payload.txt
	echo $PAYLOAD > /tmp/device_payload.txt
	POST_URL="http://"$CONTROLCENTER_VM_IP":4302/admin/v1/devices"
	http_status=`curl -s -o /dev/null -w "%{http_code}" -X POST $POST_URL -d @/tmp/device_payload.txt --header "Content-Type:application/xml"`
	error_exit "Unable to add "$NSIP" to ControlCenter"
    if [ $http_status != "201" ]; then
        get_out "Error: HTTP Status Error "$http_status" returned while adding "$NSIP" to ControlCenter"
    fi
}

function bring_netscaler1_to_base
{
	progress_msg "Rebooting NetScaler to clean slate..."
	ssh root@$XENSERVER_IP "xe snapshot-revert snapshot-uuid="$NS_1_BASE_IMG_SS_UUID
	ssh root@$XENSERVER_IP "xe vm-start vm="$NS_1_VM_UUID
	wait_till_remote_host_up nsroot@$NS_1_VM_IP 'what'
}

function  bring_devstack_to_base
{
	progress_msg "Rebooting DevStack VM to clean slate..."
	ssh root@$XENSERVER_IP "xe snapshot-revert snapshot-uuid="$DEVSTACK_BASE_IMG_SS_UUID
	ssh root@$XENSERVER_IP "xe vm-start vm="$DEVSTACK_VM_UUID
	wait_till_remote_host_up stack@$DEVSTACK_VM_IP 'ls'
}

function  check_devstack
{
	wait_till_remote_port_open stack@$DEVSTACK_VM_IP $NEUTRON_PORT
	# check if tempest directory is present
	ssh stack@$DEVSTACK_VM_IP  "ls "$TEMPEST_DIR"/run_tests.sh"
	error_exit "Devstack not properly installed.. Unable to find tempest...."
}

function  setup_devstack
{
	progress_msg "Setting up DevStack..."
	ssh stack@$DEVSTACK_VM_IP "sudo rm -rf /opt/stack/depot_files/*"
	scp $TEST_INFRA_BASE/* stack@$DEVSTACK_VM_IP:/opt/stack/depot_files/
	ssh stack@$DEVSTACK_VM_IP  "chmod 777 /opt/stack/depot_files/setup_devstack.sh"
	ssh stack@$DEVSTACK_VM_IP  "cd /opt/stack/depot_files && /opt/stack/depot_files/setup_devstack.sh ""$ALL_PARAMS"
	
	check_devstack
}

function  setup_controlcenter_db
{
	# Setup ControlCenter
	su -l mpspostgres -c "sh "$TEST_INFRA_BASE"/../controlcenter_db_deletion"
	error_exit "controlcenter db deletion failed while setting up controlcenter db"
	su -l mpspostgres -c "sh "$TEST_INFRA_BASE"/../controlcenter_db_creation"
	error_exit "controlcenter db creation failed while setting up controlcenter db"
}

function  wait_for_controlcenter_services
{
	wait_till_port_open $OPENSTACK_SVC_PORT
	wait_till_port_open $ADMIN_SVC_PORT
	wait_till_port_open $LB_SVC_PORT
	debug_msg "Started ControlCenter services..."
}

function  run_tests
{
	progress_msg "Running OpenStack API tests..."
	test_init_out=`ssh -o ConnectTimeout=5 stack@$DEVSTACK_VM_IP "cd $TEMPEST_DIR && testr init"`
	test_out=`ssh -o ConnectTimeout=5 stack@$DEVSTACK_VM_IP "cd $TEMPEST_DIR && testr run tempest.api.network.test_load_balancer"`
	progress_msg "===  API tests result  ==="
	progress_msg "$test_out"
	debug_msg "Gathering test results..."
	test_results=`ssh -o ConnectTimeout=5 stack@$DEVSTACK_VM_IP "find $TEMPEST_DIR/.testrepository/ -regextype posix-extended -regex '.*[0-9]' | xargs ls -tr | tail -n 1 | xargs grep  tempest.api.network | cut -d '[' -f 1 | egrep 'successful|failure'"`
	
	test_results=`echo "$test_results" | awk '{print $2 " " $1}'`
	progress_msg "===  API tests report  ==="
	
	progress_msg "$test_results"
	testreport_msg "$test_results"
}

function stop_controlcenter
{
	echo "Stopping...."
	cd /mps/controlcenter/services && sh stop_services.sh
	echo "Stopped...."
	ps -ax | grep python
}

function start_controlcenter
{
	cd /mps/controlcenter/services && sh start_services.sh
}

function setup_controlcenter
{
	stop_controlcenter
	setup_controlcenter_db
	start_controlcenter
	wait_for_controlcenter_services
}

######bring_devstack_to_base
setup_devstack

setup_controlcenter

# Cleanup of NetScaler
bring_netscaler1_to_base

# Add NS to ControlCenter
add_ns_to_controlcenter $NS_1_VM_IP
# Execute the tests
run_tests
package_log_files
exit 0