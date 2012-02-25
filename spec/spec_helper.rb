require "rspec"
require "optout"
require "tempfile"
require "fileutils"
require "rbconfig"

module SpecHelper
  def create_optout(options = {})
    Optout.options(options) do 
      on :x, "-x" 
      on :y, "-y"
    end
  end
  
  def optout_option(*options)
    Optout.options { on :x, "-x", *options }
  end
end

class Optout
  class Option
    def unix?
      true
    end
  end
end

RSpec.configure do |config| 
  config.include(SpecHelper)
  config.filter_run_excluding :skip_on_windows => File.exists?("NUL") # TODO: Java check
end

