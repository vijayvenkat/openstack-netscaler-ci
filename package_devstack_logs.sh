#!/usr/bin/env bash

ROOT_DIR='/opt/stack'
DEVSTACK_DIR=$ROOT_DIR/devstack
DEPOT_FILES_DIR=$ROOT_DIR/depot_files
DEPOT_LOCALRC=$DEPOT_FILES_DIR/localrc
DEPOT_NEUTRON_NCC_CONF=$DEPOT_FILES_DIR/ncc_in_neutron.conf

source ./functions.sh
export BASE='/opt/stack'
export WORKSPACE='/opt/stack/log_dest'
rm -rf $WORKSPACE
mkdir -p $WORKSPACE/logs
package_logs

