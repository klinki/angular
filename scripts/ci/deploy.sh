#!/usr/bin/env bash

set -u -e -o pipefail

# Setup environment
readonly thisDir=$(cd $(dirname $0); pwd)
source ${thisDir}/_travis-fold.sh


# If the previous commands in the `script` section of .travis.yaml failed, then abort.
# The variable is not set in early stages of the build, so we default to 0 there.
# https://docs.travis-ci.com/user/environment-variables/
if [[ ${TRAVIS_TEST_RESULT=0} == 1 ]]; then
  exit 1;
fi


# Don't deploy if not running against angular/angular
# TODO(i): because we don't let deploy to run outside of angular/angular folks can't use their
#   private travis build to deploy anywhere. This is likely ok, but this means that @alexeagle's
#   fancy setup to publish ES2015 packages to github -build repos no longer works. This is ok
#   since with flat modules we'll have this feature built-in. We should still go and remove
#   stuff that Alex put in for this from publish-build-artifacts.sh
if [[ ${TRAVIS_REPO_SLUG} != "angular/angular" ]]; then
  echo "Skipping deploy because this is not angular/angular."
  exit 0
fi


case ${CI_MODE} in
  e2e)
    # Don't deploy if this is a PR build
    if [[ ${TRAVIS_PULL_REQUEST} != "false" ]]; then
      echo "Skipping deploy because this is a PR build."
      exit 0
    fi

    travisFoldStart "deploy.packages"
      ${thisDir}/publish-build-artifacts.sh
    travisFoldEnd "deploy.packages"
    ;;
  aio)
    # Don't deploy if this build is not for master or aio-master
    if [[ ${TRAVIS_BRANCH} != "master" && ${TRAVIS_BRANCH} != "aio-master" ]]; then
      echo "Skipping deploy because this build is not for master or aio-master."
      exit 0
    fi

    travisFoldStart "deploy.aio"
    (
      cd ${TRAVIS_BUILD_DIR}/aio

      if [[ $TRAVIS_PULL_REQUEST != "false" ]]; then
        # This is a PR: deploy a snapshot for previewing
        travisFoldStart "deploy.aio.pr-preview"
          # Only deploy if this PR has touched relevant files.
          readonly AIO_CHANGED_FILES_COUNT=$(git diff --name-only $TRAVIS_COMMIT_RANGE | grep ^aio/ | wc -l)
          if [[ AIO_CHANGED_FILES_COUNT -eq 0 ]]; then
            echo "Skipping deploy because this PR did not touch any files inside 'aio/'."
          else
            # Only deploy if this PR meets certain preconditions.
            readonly AIO_PREVERIFY_EXIT_CODE=$(./aio-builds-setup/scripts/travis-preverify-pr.sh && echo 0 || echo $?)
            case $AIO_PREVERIFY_EXIT_CODE in
              2)
                # An error occurred: Fail the build
                exit 1;
                ;;
              1)
                # Preconditions not met: Skip deploy
                echo "Skipping deploy because this PR did not meet the preconditions."
                ;;
              0)
                # Preconditions met: Deploy
                yarn run deploy-preview
                ;;
            esac
          fi
        travisFoldEnd "deploy.aio.pr-preview"
      elif [[ ${TRAVIS_BRANCH} == "aio-master" ]]; then
        # This is upstream aio-master: Don't deploy to staging
        echo "Skipping deploy to staging because this build is for upstream aio-master."
      else
        # This is upstream master: Deploy to staging
        travisFoldStart "deploy.aio.staging"
          yarn run deploy-staging
        travisFoldEnd "deploy.aio.staging"
      fi
    )
    travisFoldEnd "deploy.aio"
    ;;
esac
