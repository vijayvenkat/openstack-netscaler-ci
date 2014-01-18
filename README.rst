Setting Up a Testing Infrastrure for OpenStack 
====================================


Need
-----

Inorder to make sure the code contributed by you, to OpenStack community, remains stable and to identify problems before it is too late, you need to setup a testing infrastructure that will continuously test and give feedback whenever changes get submitted to the community. This cannot be done by the openstack community CI infrastructure, because it most likely won.t have your  hardware/software. You need to setup your own testing infrastructure, probably in your company lab, in the deployment you prefer and test the changes that get submitted. 

We had contributed NetScaler driver and wanted to make sure it is not broken by changes happening in the community hence we setup a testing infrastructure at Citrix. 

The starting point is http://ci.openstack.org/third_party.html

This document can be considered an addendum to the above link.

First things First
------------------

You have to be clear on certain things before jumping on to setup the testing infrastructure.

What are you trying to qualify? 
  This should have been obvious in most cases. It is most probably the 
  plugin/driver that was written for your software/hardware. Is 
  this opensource? Can it be part of the OpenStack Jenkins?
What changes to listen for?
  Make a note of the code areas that will impact your software, you 
  would want to trigger tests only if those changes are submitted 
  on that. For example, it could be the core modules of the openstack 
  project.
What tests to run? 
  Most likely vendors run a subset of tempest tests but you could 
  in addition run your own tests as well.


Recommendations
~~~~~~~~~~~~~~~~
1. You might want to enable the test infrastructure to run tests 
   on a particular changelist. This will be handy if code submit 
   events had got lost or during test runs during test infra development.
2. You might not want to vote (-1) from the test infrastructure to start with.
   It is best if the testing infrastructure can send you an email and
   you can inspect before voting.


Listening to code submission
-----------------------------
Openstack has a gerrit code review system review.openstack.org through which 
developers submit code. Your infrastructure has to listen whenever code 
patches are submitted to gerrit and trigger tests. 

Use pypi **pygerrit** to listen to events. 

  The example code of pygerrit is a good place to start 
  https://github.com/sonyxperiadev/pygerrit/blob/master/example.py

  Get the patchset and project details from the event.
.. code-block:: bash
    if isinstance(event, PatchsetCreatedEvent):
      change_ref = patchSetCreatedEvent.patchset.ref
      submitted_project = patchSetCreatedEvent.change.project

Check if files match criteria?

  Use pypi **GitPython** in combination with git command line to 
  inspect the files in the patch. By this time assuming you already 
  would have answers for - **What changes to listen for?** - you 
  should look for the exact directories/files to check for code 
  submission. Here is a code snippet that will do that.

.. code-block:: python

  def are_files_matching_criteria(local_repo_path, review_repo_name, files_to_check, change_ref):

    """  Issue checkout using command line"""
    logging.info("Fetching the changes submitted")
    os.chdir(local_repo_path)
    is_executed = execute_command("git checkout master")
    if not is_executed:
        return False, None
    is_executed = execute_command("git fetch " + review_repo_name + " " + change_ref)
    if not is_executed:
        return False, None
    is_executed = execute_command("git checkout FETCH_HEAD")
    if not is_executed:
        return False, None
    
    """ Check the files and see if they are matching criteria using GitPython"""
    repo = Repo(local_repo_path)

    review_remote = None
    for remote in repo.remotes:
        if remote.name == review_repo_name:
            review_remote=remote
            break
    if not review_remote:
        logging.error("Unable to find review repo. It is used to check if files are matched")
        return False, None
    
    headcommit = repo.head.commit
    commitid = headcommit.hexsha
    submitted_files = headcommit.stats.files.keys()
    for submitted_file in submitted_files:
        for file_to_check in files_to_check:
            if file_to_check in submitted_file:
                logging.info("Some files changed match the test criteria")
                return True, commitid

    return False, None

Running tests & packaging logs
------------------------------------
Once the code submitted is found to be of interest, next step is to run the tests idenified.

Setting Up All Systems 
~~~~~~~~~~~~~~~~~~~~~~~
The first step is to setup the systems involved in testing. Assuming you would know how to bring your own systems in the deployments to clean slate, following are the steps that have to be done to setup devstack

1. Use an appropriate localrc with Devstack VM. 

It is recommended to use the following setting

.. code-block:: bash
  RECLONE=YES # inorder to pull latest changes during every test cycle
  DEST=/opt/stack/new  # test scripts would be expecting devstack to be installed in this directory

Here is a full sample

2. Run the following script to setup DevStack

.. code-block:: bash
  cd $DEVSTACK_DIR
  ./unstack.sh > /tmp/unstack.out 2>&1
  ./stack.sh > /tmp/stack.out 2>&1

3. patch submitted code 
.. code-block:: bash
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
  }

4. Setup openstack configuration files to use your software

.. code-block:: bash

  function configure_netscaler_driver
  {
	echo "Configuring NetScaler as the default LBaaS provider...."
	sed -i 's!HaproxyOnHostPluginDriver:default!HaproxyOnHostPluginDriver\nservice_provider=LOADBALANCER:NetScaler:neutron.services.loadbalancer.drivers.netscaler.netscaler_driver.NetScalerPluginDriver:default!g' /etc/neutron/neutron.conf
  }

5. Restart concerned service

.. code-block:: bash
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


  function restart_neutron
  {
	# restart neutron
	PID=`ps ax | grep neutron-server | grep -v grep | awk '{print $1}'`
	echo "Stopping neutron process: $PID"
	kill -9 $PID
	NL=`echo -ne '\015'`
	screen -S stack -p 'q-svc' -X stuff 'cd /opt/stack/neutron && python /usr/local/bin/neutron-server --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini'$NL
	# wait till neutron is up
	wait_till_port_open 9696
  }

Running the tempest tests 
~~~~~~~~~~~~~~~~~~~~~~~~

Run the identified tests
.. code-block:: bash

  cd /opt/stack/tempest && testr init  
  cd /opt/stack/tempest && testr run tempest.api.network.test_load_balancer

Collecting logs
~~~~~~~~~~~~~~~
For packaging devstack related log files and generating html 
file having results of the tests run, cleanup_host function from 
functions.sh script of devstack-gate can be used

Uploading logs
~~~~~~~~~~~~~~
Plan a way of sharing the log files and test results publicly, like uploading them on sharefile

Vote
----
Apply for a service account in openstack which will enable him/her to vote for changes which he/she is testing.
<code here>

NOTE:
Vote should contain link to logs.
