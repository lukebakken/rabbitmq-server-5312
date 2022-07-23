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

"$rabbitmqadmin_bin" declare queue name=dlq auto_delete=false durable=true

{
    cd "$dir/rabbitmq-server"

    make TEST_TMPDIR="$test_tmpdir" RABBITMQ_CONFIG_FILE="$dir/rabbitmq.conf" PLUGINS='rabbitmq_management rabbitmq_top' NODES=3 start-cluster

    ./sbin/rabbitmqctl --node rabbit-1 set_policy --apply-to queues \
        --priority 0 ha "." '{"ha-mode":"all", "ha-sync-mode": "automatic", "queue-mode": "lazy"}'
}

make -C "$dir/rabbitmq-perf-test" ARGS='--consumers 0 --producers 1 --predeclared --queue gh-5086 --pmessages 2000000 --size 1024' run

{
    cd "$dir/rabbitmq-perf-test"
    mvn exec:java -Dexec.mainClass=com.rabbitmq.perf.PerfTest \
        -Dexec.args='--queue input --uri amqp://localhost:5672 --auto-delete false --flag persistent --queue-args x-dead-letter-exchange=,x-dead-letter-routing-key=dlq --producers 4 --consumers 0 --size 1000 --pmessages 250000'
} &


{
    cd "$dir/rabbitmq-perf-test"
    mvn exec:java -Dexec.mainClass=com.rabbitmq.perf.PerfTest \
        -Dexec.args='--queue input --uri amqp://localhost:5672 --auto-delete false --flag persistent --queue-args x-dead-letter-exchange=,x-dead-letter-routing-key=dlq --producers 0 --consumers 10 --nack --requeue false'
} &

wait
