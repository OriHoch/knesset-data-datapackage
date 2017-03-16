#!/usr/bin/env bash

set -e  # exit on errors

[ -f .travis/.env ] && source .travis/.env

### functions ###

travis_build_url() {
    echo "https://travis-ci.org/${TRAVIS_REPO_SLUG}/builds/${TRAVIS_BUILD_ID}"
}

travis_metadata() {
    echo "REPO_SLUG=${TRAVIS_REPO_SLUG} BRANCH=${TRAVIS_BRANCH} BUILD_NUMBER=${TRAVIS_BUILD_NUMBER} BUILD_ID=${TRAVIS_BUILD_ID}"
}

send_slack_notification() {
    local msg="${1}"
    echo "sending notification to slack: '${msg}'"
    if [ "${SLACK_LOG_WEBHOOK}" != "" ]; then
        if curl -X POST -g "${SLACK_LOG_WEBHOOK}" --data-urlencode 'payload={"channel": "#oknesset-travis", "username": "travis", "text": "'"${msg}"'"}'; then
            echo "OK"
            return 0
        else
            echo "error sending slack notification"
            return 1
        fi
    else
        echo "skipping slack integration because missing relevant slack tokens"
        return 2
    fi
}

notify_datapackage_url() {
    if [ "${DATAPACKAGE_SSH_NOTIFY_KEY}" != "" ]; then
        echo "notifying open knesset via ssh to download and process the datapackage"
        echo -e "${DATAPACKAGE_SSH_NOTIFY_KEY}" > sshnotify.key
        chmod 400 sshnotify.key
        if ssh -o StrictHostKeyChecking=no -i sshnotify.key "${DATAPACKAGE_SSH_NOTIFY_HOST}" "${1}"; then
            echo "OK"
            return 0
        else
            echo "error running ssh notification to open knesset"
            return 1
        fi
    else
        echo "skipping ssh notification to open knesset because missing ssh notify key"
        return 2
    fi
}

upload_datapackage() {
    local src="${1}"
    local dst="${2}"
    if [ "${AWS_ACCESS_KEY_ID}" != "" ] && [ "${AWS_SECRET_ACCESS_KEY}" != "" ]; then
        echo "uploading '${src}' to S3: '${dst}'"
        if ! which aws; then
            pip install awscli
        fi
        export LC_ALL=C
        if aws s3 cp "${src}" "s3://${dst}" --acl=public-read; then
            echo "OK"
            return 0
        else
            echo "error uploading to S3"
            return 1
        fi
    else
        echo "skipping datapackage upload because missing aws environment vars"
        return 2
    fi
}

make_datapackage() {
    echo "TRAVIS_EVENT_TYPE=${TRAVIS_EVENT_TYPE}"
    echo "TRAVIS_TAG=${TRAVIS_TAG}"
    echo "DATAPACKAGE_LAST_DAYS=${DATAPACKAGE_LAST_DAYS}"
    if [ "${TRAVIS_EVENT_TYPE}" == "cron" ] || [ "${TRAVIS_TAG}" != "" ]; then
        mkdir -p data
        if [ "${DATAPACKAGE_SSH_PROXY_KEY}" != "" ]; then
            echo "making datapackage for last ${DATAPACKAGE_LAST_DAYS} days"
            if make_knesset_datapackage --days "${DATAPACKAGE_LAST_DAYS}" --debug --zip --http-proxy "socks5://localhost:8123 --skip-exceptions"; then
                echo "OK"
                return 0
            else
                echo "failed to create datapackage"
                return 1
            fi
        else
            echo "skipping datapackage creation because missing ssh proxy"
            return 2
        fi
    else
        echo "skipping datapackage creation (we create a datapackage only for crons and published releases)"
        return 2
    fi
}

run_tests() {
    echo "running tests"
    if bin/run_coverage.sh; then
        echo "OK"
        return 0
    else
        echo "Tests failed"
        return 1
    fi
}

exit_error() {
    exit 1
}

exit_success() {
    if [ "${DATAPACKAGE_URL}" != "" ]; then
        if ! send_slack_notification ":sunglasses:\n datapackage: ${DATAPACKAGE_URL}\nTravis build: `travis_build_url`\n`travis_metadata`"; then
            exit_error
        else
            exit 0
        fi
    else
        exit 0
    fi
}


### main ###

if run_tests; then
    if [ "`date '+%u'`" == "5" ]; then
        # every Friday - make a datapackage for last 120 days (instead of default which should be shorter)
        export DATAPACKAGE_LAST_DAYS=120
    fi
    if make_datapackage; then
        DATAPACKAGE_FILENAME="datapackage_last_${DATAPACKAGE_LAST_DAYS}_days_`date "+%Y-%m-%d"`.zip"
        if upload_datapackage "data/datapackage.zip" "${KNESSET_DATA_BUCKET}/${DATAPACKAGE_FILENAME}"; then
            DATAPACKAGE_URL="https://s3.amazonaws.com/${KNESSET_DATA_BUCKET}/${DATAPACKAGE_FILENAME}"
            if ! notify_datapackage_url "${DATAPACKAGE_URL}"; then
                echo "notification to open knesset failed, but we will continue anyway because this feature is experimental"
            fi
        elif [ $? == 1 ]; then
            exit_error
        fi
    elif [ $? == 1 ]; then
        exit_error
    fi
else
    exit_error
fi

exit_success
