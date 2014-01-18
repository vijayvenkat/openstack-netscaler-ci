Setting Up a Testing Infrastrure for OpenStack 
====================================


Need
--------

Inorder to make sure the code contributed by you, to OpenStack community, remains stable and to identify problems before it is too late, you need to setup a testing infrastructure that will continuously test and give feedback whenever changes get submitted to the community. This cannot be done by the openstack community CI infrastructure, because it most likely won.t have your  hardware/software. You need to setup your own testing infrastructure, probably in your company lab, in the deployment you prefer and test the changes that get submitted. 

We had contributed NetScaler driver and wanted to make sure it is not broken by changes happening in the community hence we setup a testing infrastructure at Citrix. 

The starting point is http://ci.openstack.org/third_party.html

This document can be considered an addendum to the above link.

First things First
~~~~~~~~~~~~~

You have to be clear on certain things before jumping on to setup the testing infrastructure.

1) What are you trying to qualify? This should have been obvious in most cases. It is most probably the plugin/driver that was written for your software/hardware. Is this opensource? Can it be part of the OpenStack community CI?
2) What changes to listen for? . Make a note of the code areas that will impact your software, you would want to trigger tests only if those changes are submitted on that. For example, it could be the core modules of the openstack project.
3) What tests to run? Most likely vendors run a subset of tempest tests but you could in addition run your own tests as well.


Areas of caution
~~~~~~~~~~~~~
You might want to enable manual run
You might not want to vote in the beginning.

Order of work
~~~~~~~~~~~

Listening to code submission
~~~~~~~~~~~~~~~~~~~~~
Openstack has a gerrit code review system  review.openstack.org through which developers submit code. Your infrastructure has to listen whenever code patches are submitted to gerrit and trigger tests. 

Use pygerrit to listen to events. Store the identities of the change set and the patch. Here is a sample code
  <code here>
Use GitPython in combination with git command line to inspect the files in the patch. By this time assuming you already would have answers for .What changes to listen for?. you should look for the exact directories/files to check for code submission. Here is a code snippet that will do that.
<code here>

Setting Up All Systems (including DevStack)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Once the code submit event is of interest, the next thing is to setup the systems involved. Before running the tests, it is imperative to make sure all the systems involved in the test suite are in a clean-state. Assuming you would know how to bring your own systems in the deployments to clean slate, following are the steps that have to be done to setup devstack

1. . Copy localrc to Devstack VM. Here is a copy we used. It is recommended to use the following setting
RECLONE=YES # inorder to pull latest changes during every test cycle
DEST=/opt/stack/new  # test scripts would be expecting devstack to be installed in this directory
2. Run unstack.sh which stops that which is started by stack.sh (mostly) mysql and 
rabbit are left running as OpenStack code refreshes do not require them to be restarted.
3. Run stack.sh It installs and configures various combinations of Ceilometer, Cinder, 
Glance, Heat, Horizon, Keystone, Nova, Neutron, Swift, and Trove
4. Kill neutron-server 
5. Patch the code.
6. Configure Netscaler Driver in neutron.conf
7. Start  neutron-server
2.
3.

Running the tempest tests 
~~~~~~~~~~~~~~~~~~~~

cd /opt/stack/tempest && testr init  
cd /opt/stack/tempest && testr run tempest.api.network.test_load_balancer

Collecting logs
~~~~~~~~~~~
For packaging devstack related log files and generating html file having results of the tests run, cleanup_host function from functions.sh script of devstack-gate can be used


Uploading logs
~~~~~~~~~~~
plan a way of sharing the log files and test results publicly, like uploading them on sharefile

Vote
~~~
Apply for a service account in openstack which will enable him/her to vote for changes which he/she is testing.
<code here>

NOTE:
Vote should contain link to logs.



