#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# shellcheck disable=SC2155
readonly dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

readonly rabbitmqadmin_bin="$dir/bin/rabbitmqadmin"
readonly rabbitmqctl_bin="$dir/rabbitmq-server/sbin/rabbitmqctl"

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
fi

echo 'ERLANG VERSION:'
erl -noinput -eval 'F=filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"]),io:format("~p~n",[
file:read_file(F)]),halt().'

{
    cd "$dir/rabbitmq-server"
    make FULL=1
} &

{
    cd "$dir/rabbitmq-perf-test"
    make compile
} &

wait

make -C "$dir/rabbitmq-server" TEST_TMPDIR="$test_tmpdir" RABBITMQ_CONFIG_FILE="$dir/rabbitmq.conf" PLUGINS='rabbitmq_management rabbitmq_top' NODES=3 start-cluster

"$rabbitmqadmin_bin" declare queue name=dlq auto_delete=false durable=true queue_type=quorum
"$rabbitmqadmin_bin" declare queue name=input auto_delete=false durable=true arguments='{"x-dead-letter-exchange":"","x-dead-letter-routing-key":"dlq","x-queue-type":"quorum"}'

declare -ri msg_count=250000

make -C "$dir/rabbitmq-perf-test" \
    ARGS="--predeclared --queue input --uri amqp://localhost:5672 --flag persistent --producers 4 --consumers 0 --size 1000 --pmessages $msg_count" \
    run &

sleep 10

make -C "$dir/rabbitmq-perf-test" \
    ARGS="--predeclared --queue input --uri amqp://localhost:5672 --producers 0 --consumers 10 --nack --requeue false" \
    run
