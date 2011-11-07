# Optout

Validate an option hash and turn it into something appropriate for `exec()` and `system()` like functions.

## Overview

    require "optout"

    # Create options for `gem`
    optout = Optout.options do
      on :gem, "install", :required => true
      on :os, "--platform", %w|mswin cygwin mingw|
      on :version, "-v", /\A\d+(\.\d+)*\z/
      on :user, "--user-install"
      on :location, "-i", Optout::Dir.exists.under(ENV["HOME"])
    end

    options = {
      :gem => "rake",
      :os => "mswin",
      :version => "0.9.2",
      :user => true
    }

    exec "gem", *optout.argv(options)
    # Returns: ["install", "rake", "--platform", "mswin", "-v", "0.9.2", "--user-install"]

    `gem #{optout.shell(options)}`
    # Returns: "'install' 'rake' --platform 'mswin' -v '0.9.2' --user-install"

## Install

Sorry, no gem yet... in process of extracting (and enhancing) from a larger project.

## Author

Skye Shaw [sshaw AT lucas.cis.temple.edu]