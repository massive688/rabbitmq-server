# --------------------------------------------------------------------
# dialyzer
# --------------------------------------------------------------------

DIALYZER_OPTS ?= -Werror_handling -Wunmatched_returns -Wunknown

dialyze: ERL_LIBS = $(APPS_DIR):$(DEPS_DIR):$(DEPS_DIR)/rabbitmq_cli/_build/dev/lib:$(dir $(shell elixir --eval ":io.format '~s~n', [:code.lib_dir :elixir ]"))

# --------------------------------------------------------------------
# %-on-concourse dependencies.
# --------------------------------------------------------------------

ifneq ($(words $(filter %-on-concourse,$(MAKECMDGOALS))),0)
TEST_DEPS += ci $(RMQ_CI_CT_HOOKS)
NO_AUTOPATCH += ci $(RMQ_CI_CT_HOOKS)
dep_ci = git git@github.com:rabbitmq/rabbitmq-ci.git main
endif

# --------------------------------------------------------------------
# Common Test flags.
# --------------------------------------------------------------------

# We start the common_test node as a hidden Erlang node. The benefit
# is that other Erlang nodes won't try to connect to each other after
# discovering the common_test node if they are not meant to.
#
# This helps when several unrelated RabbitMQ clusters are started in
# parallel.

CT_OPTS += -hidden

# Enable the following common_test hooks on GH and Concourse:
#
# cth_fail_fast
#   This hook will make sure the first failure puts an end to the
#   testsuites; ie. all remaining tests are skipped.
#
# cth_styledout
#   This hook will change the output of common_test to something more
#   concise and colored.
#
# On Jenkins, in addition to those common_test hooks, enable JUnit-like
# report. Jenkins parses those reports so the results can be browsed
# from its UI. Furthermore, it displays a graph showing evolution of the
# results over time.

CT_HOOKS ?= cth_styledout
TEST_DEPS += cth_styledout

ifdef CONCOURSE
FAIL_FAST = 1
SKIP_AS_ERROR = 1
endif

RMQ_CI_CT_HOOKS = cth_fail_fast
ifeq ($(FAIL_FAST),1)
CT_HOOKS += $(RMQ_CI_CT_HOOKS)
TEST_DEPS += $(RMQ_CI_CT_HOOKS)
endif

dep_cth_fail_fast = git https://github.com/rabbitmq/cth_fail_fast.git master
dep_cth_styledout = git https://github.com/rabbitmq/cth_styledout.git master

CT_HOOKS_PARAM_VALUE = $(patsubst %,and %,$(CT_HOOKS))
CT_OPTS += -ct_hooks $(wordlist 2,$(words $(CT_HOOKS_PARAM_VALUE)),$(CT_HOOKS_PARAM_VALUE))

# On CI, set $RABBITMQ_CT_SKIP_AS_ERROR so that any skipped
# testsuite/testgroup/testcase is considered an error.

ifeq ($(SKIP_AS_ERROR),1)
export RABBITMQ_CT_SKIP_AS_ERROR = true
endif
