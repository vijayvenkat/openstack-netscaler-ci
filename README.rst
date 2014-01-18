Setting Up a Testing Infrastructure for OpenStack 
=================================================


Need
-----

Inorder to make sure the code contributed by you, to OpenStack community,
remains stable and to identify problems before it is too late, you need
to setup a testing infrastructure. It should continuously test and give 
feedback/vote whenever changes get submitted to the community. Tests 
cannot be run by the openstack community CI infrastructure, because
it won't have your/vendor's hardware/software. You need 
to setup your own testing infrastructure, probably in your company lab,
in the deployment you prefer and test the changes that get submitted. 

We had contributed NetScaler driver, inorder to make sure it is 
not broken we setup a test infrastructure. The following paragraphs 
captures the thought process of setting up a test infrasture, and provides 
code snipetts from the code that was used to setup the testing 
infrastructure at Citrix. Hoping, it will be useful for others who 
are setting up their own test infrastructure.

The starting point is http://ci.openstack.org/third_party.html

This document can be considered an addendum to the above link.

First things first
------------------

You have to be clear on certain things before jumping on to setup the testing infrastructure.

What are you trying to qualify? 
  This should have been obvious in most cases. It is most probably the 
  plugin/driver that was written for your software/hardware.  
What changes to listen for?
  Make a note of the code areas that will impact your software, you 
  would want to trigger tests only if those changes are submitted 
  on that. For example, it could be the core modules of the openstack 
  project.
What tests to run? 
  Most likely vendors run a subset of tempest_ tests, but you could 
  in addition run your own tests as well.


Recommendations
~~~~~~~~~~~~~~~~

1. You might want to enable the test infrastructure to run tests 
   on a particular changelist. This will be handy when you observe that 
   a code submit event got lost and you want to trigger a test offline. 
   Or during the test infrastructure development phase.
2. You might **not** want to vote (-1) from the test infrastructure to start with.
   It is best if the testing infrastructure can send you an email on -1 cases.
   You can inspect files manually, once confident, you could trigger the 
   the negatve vote manually.


Listening to code submission
-----------------------------
Openstack has a gerrit_ code review system via which developers submit 
code. Your infrastructure has to listen to gerrit, and whenever *relavant*
code patches are submitted to gerrit it should trigger tests. 

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
  inspect the files in the patch. If you already have answered
  - **What changes to listen for?** - you should have the exact 
  directories/files to check during code submission. Here is a 
  code snippet that will check if files in a change submitted is 
  of your interest.

.. code-block:: python

  def execute_command(command, delimiter=' '):
    command_as_array = command.split(delimiter)
    logging.debug("Executing command: " + str(command)) 
    p = subprocess.Popen(command_as_array,stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output, errors = p.communicate()
    if p.returncode != 0:
        logging.error("Error: Could not exuecute command " + str(command)  + ". Failed with errors " + str(errors))
        return False
    logging.debug("Output command: " + str(output))
    
    return True

  """ 
  1. local_repo_path == /opt/stack/gerrit_depot/neutron # the git repository that will be used for file inspection
  2. review_repo_name == gerrit_repo # git remote name in local_repo_path that is pointing to review.openstack.org repository
  3. files_to_check == 'neutron/services/loadbalancer/drivers/netscaler' # files of interest
  4. change_ref == refs/changes/24/57524/9 # changeref of a patchset submitted for a particular change
  """
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
Once the code submitted is found to be of interest, the tests idenified have to be run.

Setting up all systems 
~~~~~~~~~~~~~~~~~~~~~~~
The first step is to setup the systems involved in testing. You should 
setup vendor specific systems in the deployment to clean slate, and 
also setup DevStack. To setup the former, you are the best person
to know the steps. To setup the latter (devstack), following are 
the steps that are recommended

1. Use an appropriate localrc with Devstack VM. Here_ is a full sample. It is recommended to use the following setting

.. code-block:: bash

  RECLONE=YES # inorder to pull latest changes during every test cycle
  DEST=/opt/stack/new  # log collection scripts would be expecting devstack to be installed in this directory

2. Run the following script to setup DevStack

.. code-block:: bash

  cd $DEVSTACK_DIR
  ./unstack.sh > /tmp/unstack.out 2>&1
  ./stack.sh > /tmp/stack.out 2>&1

3. Patch submitted code 

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
	else
		echo "Nothing to be patched"
		return
	fi
  }

4. Setup openstack configuration files to use your software

   We had to patch the neutron.conf to include NetScaler driver

.. code-block:: bash

  function configure_netscaler_driver
  {
	echo "Configuring NetScaler as the default LBaaS provider...."
	sed -i 's!HaproxyOnHostPluginDriver:default!HaproxyOnHostPluginDriver\nservice_provider=LOADBALANCER:NetScaler:neutron.services.loadbalancer.drivers.netscaler.netscaler_driver.NetScalerPluginDriver:default!g' /etc/neutron/neutron.conf
  }

5. Restart concerned openstack service

   We had to restart neutron

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
	screen -S stack -p 'q-svc' -X stuff 'cd /opt/stack/new/neutron && python /usr/local/bin/neutron-server --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini'$NL
	# wait till neutron is up
	wait_till_port_open 9696
  }

Running the tempest tests 
~~~~~~~~~~~~~~~~~~~~~~~~

We run the LBaaS API tests today. In future, LBaaS scenario tests will 
be included.

.. code-block:: bash

  cd /opt/stack/new/tempest && testr init  
  cd /opt/stack/new/tempest && testr run tempest.api.network.test_load_balancer

Collecting logs
~~~~~~~~~~~~~~~

The best way to collect logs from DevStack is to use cleanup_host function 
present in devstack-gate's functions.sh_. In addition to collecting log files it
also generates results in pretty format.

.. code-block:: bash
  source /opt/stack/new/devstack-gate/functions.sh
  export BASE='/opt/stack/new'
  export WORKSPACE='/opt/stack/log_dest'
  rm -rf $WORKSPACE
  mkdir -p $WORKSPACE/logs
  cleanup_host

**NOTE** The above script is dependent on 
https://github.com/openstack-infra/config/blob/master/modules/jenkins/files/slave_scripts/subunit2html.py
copy this to /usr/local/jenkins/slave_scripts/subunit2html.py

Uploading logs
~~~~~~~~~~~~~~
Upload the log files in the public domain. Only then,
the community members will be able to have a look at the test results.
At Citrix, we have used sharefile. We might be able to contribute space 
for community depending on the number of requests received. Please
feel free to shoot a mail to me by next week (Jan-25).

Vote
----
The final step in the process is to vote (+1/-1) depending on the result. 
There are three kinds of voting available in the gerrit system. The 3rd 
party infrastructure is expected to execute the 'Verified' votes.
Apply for a service account in openstack as per the details specificed in
http://ci.openstack.org/third_party.html#requesting-a-service-account
Use the ssh key to execute a Verified vote. An example is given below  

.. code-block:: bash

   $ ssh -p 29418 review.openstack.org gerrit review -m '"LBaaS API testing failed with NetScaler providing LBaaS. Please find logs at <http://....>"' --verified=-1 c0ff33111123313131

**NOTE** Vote should contain link to logs.

.. _tempest: https://github.com/openstack/tempest
.. _gerrit: https://review.openstack.org
.. _functions.sh: https://github.com/openstack-infra/devstack-gate/blob/master/functions.sh
.. _Here: https://github.com/vijayvenkat/openstack-netscaler-ci/blob/master/localrc


