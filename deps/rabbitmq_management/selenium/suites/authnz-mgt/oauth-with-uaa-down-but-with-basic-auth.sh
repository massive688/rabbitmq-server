#!/usr/bin/env bash

SCRIPT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

TEST_CASES_PATH=/oauth/with-basic-auth-idp-down
TEST_CONFIG_PATH=/oauth
PROFILES="uaa uaa-oauth-provider uaa-mgt-oauth-provider enable-basic-auth"

source $SCRIPT/../../bin/suite_template $@
run
