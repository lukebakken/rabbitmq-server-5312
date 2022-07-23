#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# shellcheck disable=SC2155
readonly dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

readonly rabbitmqadmin_bin="$dir/bin/rabbitmqadmin"

# Defaults for start-cluster:
# TMPDIR ?= /tmp
# TEST_TMPDIR ?= $(TMPDIR)/rabbitmq-test-instances
readonly test_tmpdir="$dir/tmp/rabbitmq-test-instances"

mkdir -p "$test_tmpdir"

git submodule update --init

if command -v asdf
then
    asdf current erlang
    asdf current elixir
    echo 'ERLANG VERSION:'
    erl -noinput -eval 'F=filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"]),io:format("~p~n",[
file:read_file(F)]),halt().'
fi

{
    cd "$dir/rabbitmq-server"
    make FULL=1
} &

{
    cd "$dir/rabbitmq-perf-test"
    make compile
} &

wait

#### {
####     cd "$dir/rabbitmq-server"
#### 
####     set_erlang_version
#### 
####     make TEST_TMPDIR="$test_tmpdir" RABBITMQ_CONFIG_FILE="$dir/rabbitmq.conf" PLUGINS='rabbitmq_management rabbitmq_top' NODES=3 start-cluster
#### 
####     ./sbin/rabbitmqctl --node rabbit-1 set_policy --apply-to queues \
####         --priority 0 policy-0 ".*" '{"ha-mode":"all", "ha-sync-mode": "automatic", "queue-mode": "lazy"}'
#### 
####     ./sbin/rabbitmqctl --node rabbit-1 set_policy --apply-to queues \
####         --priority 1 policy-1 ".*" '{"ha-mode":"all", "ha-sync-mode": "automatic"}'
#### }
#### 
#### make -C "$dir/rabbitmq-perf-test" ARGS='--consumers 0 --producers 1 --predeclared --queue gh-5086 --pmessages 2000000 --size 1024' run
#### 
#### {
####     cd "$dir/rabbitmq-server"
####     ./sbin/rabbitmqctl --node rabbit-1 clear_policy policy-1
#### }
