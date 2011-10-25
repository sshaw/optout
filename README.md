# Optout

Validate an option hash and turn it into something suitable to pass to `exec()` and `system()` like functions.

## Overview

    require "optout"

    # Create options for `gem`
    optout = Optout.options do
      on :gem, "install", :required => true
      on :os, "--platform", %w|mswin cygwin mingw|
      on :version, "-v", /\A\d+(\.\d+)*\z/
      on :user, "--user-install"
    end

    options = {
      :gem => "rake",
      :os => "mswin",
      :version => "0.9.2",
      :user => true
    }

    `gem #{optout.shell(options)}` # or
    exec "gem", *optout.argv(options)


## Install

Sorry, no gemspec yet... in process of extracting from a larger project.

## Author

Skye Shaw [sshaw AT lucas.cis.temple.edu]