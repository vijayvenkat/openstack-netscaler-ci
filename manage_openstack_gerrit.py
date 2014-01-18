#!/usr/bin/env python
# -*- coding: utf-8 -*-
from optparse import OptionValueError

# The MIT License
#
# Copyright 2012 Sony Mobile Communications. All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

""" Example of using the Gerrit client class. """

import subprocess

from pygerrit.client import GerritClient
from pygerrit.error import GerritError
from pygerrit.events import ErrorEvent, PatchsetCreatedEvent
from threading import Event
import logging
import optparse
import sys
import time
import os

import sharefile_upload

""" importing python git commands """
from git import Repo


class CONSTANTS:
    REMOTE=True
    TEST_SCRIPT = '/spare/nsmkernel/usr.src/sdx/controlcenter/build_resources/test_infra/sync_and_test.sh'
    UPLOAD_SCRIPT = '/spare/nsmkernel/usr.src/sdx/controlcenter/build_resources/test_infra/sharefile_upload.py'
    SSH_PERFORCE = 'root@10.102.31.70'
    TEMP_PATH_FOR_REMOTE = "/tmp"
    RESULTS_OUT = "/tmp/result.out"
    UPLOAD_FILES = False
    VOTE=False
    VOTE_NEGATIVE=False
    PROJECT_CONFIG={
                    'neutron':{
                               'name':'neutron',
                               'repo_path':"/opt/stack/gerrit_depot/neutron",
                               'review_repo': "gerrit_repo",
                               'files_to_check' : ['neutron/services/loadbalancer/drivers/netscaler']
                               }
#                    'neutron':{
#                               'name':'neutron',
#                               'repo_path':"/opt/stack/gerrit_depot/neutron",
#                               'review_repo': "gerrit_repo",
#                               'files_to_check' : ['neutron/services/loadbalancer']
#                               },
#                    'tempest':{
#                               'name':'tempest',
#                               'repo_path':"/opt/stack/gerrit_depot/tempest",
#                               'review_repo': "gerrit_repo",
#                               'files_to_check' : ['tempest/api/network/test_load_balancer.py']
#                               }
                    }
    
def is_event_matching_criteria(event):
    if isinstance(event, PatchsetCreatedEvent):
        patchSetCreatedEvent = event
        """ Can check in master branch also"""
        if  patchSetCreatedEvent.change.branch=="master":
            if get_project_event(patchSetCreatedEvent) != None:
                logging.info("Event is matching event criteria")
                return True
        logging.info("Event is not matching event criteria")
    return False

def get_project_event(patchSetCreatedEvent):
    submitted_project = patchSetCreatedEvent.change.project
    for project_name in CONSTANTS.PROJECT_CONFIG.keys():
        if submitted_project.endswith(project_name):
            project_config = CONSTANTS.PROJECT_CONFIG[project_name]
            return project_config
    return None

def are_files_matching_criteria_event(patchSetCreatedEvent):
    change_ref = patchSetCreatedEvent.patchset.ref
    submitted_project = patchSetCreatedEvent.change.project
    logging.info("Checking for file match criteria changeref: %s, project: %s" % (change_ref, submitted_project))
    
    project_config = get_project_event(patchSetCreatedEvent)
    if project_config != None:
        files_matched, commitid = are_files_matching_criteria(project_config['repo_path'], project_config["review_repo"], project_config["files_to_check"], change_ref)
        if files_matched:
                return True
    return False
    
def test_changes(change_ref, submitted_project, commitid, stacksh="SKIP"):
    logging.info("Calling test procedures to test changeref: %s, project: %s" % (change_ref, submitted_project))
    if CONSTANTS.REMOTE:
        p = subprocess.Popen(['ssh', CONSTANTS.SSH_PERFORCE , CONSTANTS.TEST_SCRIPT, stacksh, change_ref, 
                              submitted_project],stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    else:
        p = subprocess.Popen([CONSTANTS.TEST_SCRIPT, stacksh, change_ref, 
                              submitted_project],stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        
    output, errors = p.communicate()
    if errors:
        logging.error("Error: Could not test changes for change: " + change_ref + ". Failed with message: " + errors)
        return False
    else:
        logging.info("Successfully tested changes for change: " + change_ref)
        result = parse_result()
        if 'LOG' not in result or 'REPORT' not in result:
            logging.error("Error: Could not read result...")
            return False
        else:
            logging.info("Report of test run: " + result['REPORT'])
             
        if CONSTANTS.UPLOAD_FILES:
            if CONSTANTS.REMOTE:
                logging.info("Uploading test output...")
                p = subprocess.Popen(['ssh', CONSTANTS.SSH_PERFORCE, '/var/nsmkernel/usr.src/usr/local/bin/python' , CONSTANTS.UPLOAD_SCRIPT,result['LOG'], result['REPORT']],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                output, errors = p.communicate()
                if errors:
                    logging.error("Error: Could not upload test output: " + errors)
                    return False
                else:
                    logging.debug("Successfully uploaded test output...")
                    
                result = parse_result()
                log_url = result['LOGURL']
                report_url = result['REPORTURL']
            else:
                log_url = sharefile_upload.logs_upload(result['LOG'], result['REPORT'])

            # Now Vote
            
            if 'failure' in result['REPORT']:
                vote_num = "-1"
                vote_result = "FAILED"
            else:
                vote_num = "+1"
                vote_result = "PASSED"
            vote(commitid, vote_num, "LBaaS API testing " + vote_result + " with NetScaler providing LBaaS.\nPlease find the results at " + report_url + " and logs at " + log_url + " ")
        return True
    
def test_changes_event(patchSetCreatedEvent):
    change_ref = patchSetCreatedEvent.patchset.ref
#    submitted_project = patchSetCreatedEvent.change.project
    project_config = get_project_event(patchSetCreatedEvent)
    if project_config != None:
        project_name = project_config['name']
        logging.info("patchset values : " + repr(patchSetCreatedEvent))
        commitid = patchSetCreatedEvent.patchset.revision
        is_test_executed = test_changes(change_ref, project_name, commitid, "RUN")
    return 
    
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



def are_files_matching_criteria(local_repo_path, review_repo_name, files_to_check, change_ref):
    """ Check out the even from the depot """
    """git show --name-only  --pretty="format:" HEAD # displays the files"""
    """  Issue checkout using command line"""
#git fetch https://review.openstack.org/openstack/neutron refs/changes/24/57524/9 && git checkout FETCH_HEAD
#git fetch https://review.openstack.org/openstack/tempest refs/changes/97/58697/16 && git checkout FETCH_HEAD

    """ Check the files and see if they are matching criteria"""

    logging.info("Fetching the changes submitted")
    os.chdir(local_repo_path)
#git fetch https://review.openstack.org/openstack/neutron refs/changes/24/57524/9 &&    
    is_executed = execute_command("git checkout master")
    if not is_executed:
        return False, None
    is_executed = execute_command("git fetch " + review_repo_name + " " + change_ref)
    if not is_executed:
        return False, None
    is_executed = execute_command("git checkout FETCH_HEAD")
    if not is_executed:
        return False, None
#    review_remote.fetch(change_ref)
#    repo.git.checkout("FETCH_HEAD")
    
    repo = Repo(local_repo_path)

    # TODO patch the inspection repo with the commit in patch
    # resetting firs the reference to master branch
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

def vote(commitid, vote_num, message):
    #ssh -p 29418 review.example.com gerrit review -m '"Test failed on MegaTestSystem <http://megatestsystem.org/tests/1234>"'
    # --verified=-1 c0ff33
    logging.info("Going to vote commitid %s, vote %s, message %s" % (commitid, vote_num, message))
    if CONSTANTS.VOTE:
        if not CONSTANTS.VOTE_NEGATIVE and vote_num == "-1":
            logging.error("Did not vote -1 for commitid %s, vote %s" % (commitid, vote_num))
            return
        vote_cmd = """ssh$-i$/opt/stack/.ssh/service_account$-p$29418$review.openstack.org$gerrit$review"""
        vote_cmd = vote_cmd + "$-m$'\"" + message + "\"'$--verified=" + vote_num + "$" + commitid
        is_executed = execute_command(vote_cmd,'$')
        if not is_executed:
            logging.error("Error: Could not vote. Voting failed for change: " + commitid)
        else:
            logging.info("Successfully voted " + str(vote_num) + " for change: " + commitid)

    
def record_event_details(event):
    pass

def parse_result():

    result = {}
    if CONSTANTS.REMOTE:
        p = subprocess.Popen(['ssh', CONSTANTS.SSH_PERFORCE, 'cat', CONSTANTS.RESULTS_OUT],stdout=subprocess.PIPE, stderr=subprocess.PIPE)
#        p = subprocess.Popen(['cat', CONSTANTS.TEMP_PATH_FOR_REMOTE+"/1.html"],stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output, errors = p.communicate()
        if errors:
            logging.error("Error: Understanding the result: " + errors)
        else:
            logging.debug("Successfully parsed the result.\n****RESULT****\n " + output)
            
            lines = output.splitlines()
            for line in lines:
                (key,value) = line.split('=')
                result[key]=value.rstrip()
    else:
        file_path = CONSTANTS.RESULTS_OUT
        f = open(file_path, 'r')
        for line in f:
            (key,value) = line.split('=')
            result[key]=value.rstrip()
        f.close()
    return result

def inform_builder(patchSetCreatedEvent):
    # TODO: Ideally this should be called in a separate thread, picking from database 
    test_changes_event(patchSetCreatedEvent)


def check_for_change_ref(option, opt_str, value, parser):
    if not parser.values.change_ref:
        raise OptionValueError("can't use %s, Please provide --change_ref/-c before %s" % (opt_str, opt_str))
    setattr(parser.values, option.dest, value)
    if parser.values.vote:
        if parser.values.vote != "+1" and parser.values.vote != "-1":
            raise OptionValueError("invalid use of %s, Please provide +1/-1" % (opt_str))

def check_for_vote(option, opt_str, value, parser):
    if not parser.values.vote:
        raise OptionValueError("can't use %s, Please provide --vote before %s" % (opt_str, opt_str))
    setattr(parser.values, option.dest, value)


def _main():
    usage = "usage: %prog [options]"
    parser = optparse.OptionParser(usage=usage)
    # 198.101.231.251 is review.openstack.org. For some vague reason the dns entry from inside pygerrit is not resolved.
    # It throws an error "ERROR Gerrit error: Failed to connect to server: [Errno 101] Network is unreachable"
    parser.add_option('-g', '--gerrit-hostname', dest='hostname',
                      default='198.101.231.251',
                      help='gerrit server hostname (default: %default)')
    parser.add_option('-p', '--port', dest='port',
                      type='int', default=29418,
                      help='port number (default: %default)')
    parser.add_option('-u', '--username', dest='username',
                      help='username', default='vijayvenkatachalam')
    parser.add_option('-b', '--blocking', dest='blocking',
                      action='store_true',
                      help='block on event get (default: False)')
    parser.add_option('-t', '--timeout', dest='timeout',
                      default=None, type='int',
                      help='timeout (seconds) for blocking event get '
                           '(default: None)')
    parser.add_option('-v', '--verbose', dest='verbose',
                      action='store_true',default=False,
                      help='enable verbose (debug) logging')
    parser.add_option('-i', '--ignore-stream-errors', dest='ignore',
                      action='store_true',
                      help='do not exit when an error event is received')
    parser.add_option('-c', '--change-ref', dest='change_ref',
                      action="store", type="string",
                      help="to be provided if required to do one time job on a change-ref")
    
    parser.add_option('-x', '--commit-id', dest='commitid',
                      action="callback", callback=check_for_change_ref, type="string",
                      help="to be provided if required to do one time job on a change-id")

    parser.add_option('-j', '--project', dest='project',
                      action="callback", callback=check_for_change_ref, type="string",
                      help="project of the change-ref provided")
    parser.add_option("-n", '--vote-num',  dest='vote', 
                      action="callback", callback=check_for_change_ref, type="string",
                      help="the vote, should be either '+1' or '-1'")
    parser.add_option("-m", '--vote-message',  dest='message', 
                      action="callback", callback=check_for_vote, type="string",
                      help="the message that has to be sent for voting")


    (options, _args) = parser.parse_args()
    if options.timeout and not options.blocking:
        parser.error('Can only use --timeout with --blocking')

    if options.change_ref and not options.project:
        parser.error('Can only use --change_ref with --project')

    if options.vote and not options.message:
        parser.error('Can only use --vote with --vote-message')

    if options.vote and not options.commitid:
        parser.error('Can only use --vote with --commit-id')

    level = logging.DEBUG if options.verbose else logging.INFO
    logging.basicConfig(format='%(asctime)s %(levelname)s %(message)s',
                        level=level)

    if options.change_ref:
        # One time job needs to be performed.
        if options.vote:
            # Just voting needs to be done, no need of testing
            vote(options.commitid, options.vote, options.message)
        else:
            # Execute tests and vote
            if options.project not in CONSTANTS.PROJECT_CONFIG:
                logging.info("Project specified does not match criteria")
                return
            project_config = CONSTANTS.PROJECT_CONFIG[options.project]
            files_matched, commitid = are_files_matching_criteria(project_config['repo_path'], project_config["review_repo"], project_config["files_to_check"], options.change_ref)
            if files_matched:
                test_changes(options.change_ref, options.project, commitid, "RUN")
            else:
                logging.error("Changeref specified does not match file match criteria")
        return
    
    # Starting the loop for listening to Gerrit events
    try:
        logging.info("Connecting to gerrit host " + options.hostname)
        logging.info("Connecting to gerrit username " + options.username)
        logging.info("Connecting to gerrit port " + str(options.port))
        gerrit = GerritClient(host=options.hostname,
                              username=options.username,
                              port=options.port)
        logging.info("Connected to Gerrit version [%s]",
                     gerrit.gerrit_version())
        gerrit.start_event_stream()
    except GerritError as err:
        logging.error("Gerrit error: %s", err)
        return 1

    errors = Event()
    try:
        while True:
            event = gerrit.get_event(block=options.blocking,
                                     timeout=options.timeout)
            if event:
                logging.debug("Event: %s", event)
                """ Logic starts here """
                if is_event_matching_criteria(event):
                    if are_files_matching_criteria_event(event):
                        record_event_details(event)
                        inform_builder(event)
                        
                if isinstance(event, ErrorEvent) and not options.ignore:
                    logging.error(event.error)
                    errors.set()
                    break
            else:
                logging.debug("No event")
                if not options.blocking:
                    time.sleep(1)
    except KeyboardInterrupt:
        logging.info("Terminated by user")
    finally:
        logging.debug("Stopping event stream...")
        gerrit.stop_event_stream()

    if errors.isSet():
        logging.error("Exited with error")
        return 1

if __name__ == "__main__":
#    test_changes("aa", "bb")
#    result = parse_result()
#    logging.info("Test result: " + str(result))
#    logging.basicConfig(format='%(asctime)s %(levelname)s %(message)s',
#                        level=logging.DEBUG)
#
#    project_config = CONSTANTS.PROJECT_CONFIG["neutron"]
#    change_ref = "refs/changes/70/65070/1"
#    are_files_matching_criteria(project_config['repo_path'], project_config["review_repo"], project_config["files_to_check"], change_ref)
#    vote_cmd = """ls -l /opt/stack/.ssh"""

#    vote_cmd = """ssh -i /opt/stack/.ssh/service_account -p 29418 review.openstack.org gerrit review"""
#    is_executed = execute_command(vote_cmd)
#    if not is_executed:
#        logging.error("Error: Could not vote. Voting failed for change: ")
#    else:
#        logging.info("Successfully voted " + str(1) + " for change: ")

    sys.exit(_main())
