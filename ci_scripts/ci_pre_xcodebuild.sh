#!/bin/sh

# Set the -e flag to stop running the script in case a command returns
# # a nonzero exit code.
set -e

# Logs each command being run in the terminal
set -v

# Skip macro validation
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES

# Skip package plugin validation (for build tool plugins like ISOStandardCodegenPlugin)
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES

