#!/bin/zsh
# ci_post_xcodebuild.sh

if [[ -d "$CI_APP_STORE_SIGNED_APP_PATH" ]]; then
  TESTFLIGHT_DIR_PATH=../TestFlight
  mkdir $TESTFLIGHT_DIR_PATH
  echo "Last 5 commits:" > $TESTFLIGHT_DIR_PATH/WhatToTest.en-US.txt
  git fetch --deepen 5 && git log -5 --pretty=format:"%s" >> $TESTFLIGHT_DIR_PATH/WhatToTest.en-US.txt
fi
