require "lib/optout"

Gem::Specification.new do |s|
  s.name        = "optout"
  s.version     = Optout::VERSION
  s.date        = Date.today
  s.summary     = "The opposite of getopt(): validate an option hash and turn it into something appropriate for exec() and system() like functions"
  s.description =<<-DESC
    Optout helps you write code that will call exec() and system() like functions. It allows you to map hash keys to command line 
    arguments and define validation rules that must be me before the command line options are created. 
  DESC
  s.authors     = ["Skye Shaw"]
  s.email       = "sshaw@lucas.cis.temple.edu"
  s.files       = ["lib/optout.rb", "spec/optout_spec.rb", "README.rdoc"]
  s.test_files  = ["spec/optout_spec.rb"]
  s.homepage    = "http://github.com/sshaw/optout"
  s.license     = "MIT"
  s.add_development_dependency "rake", "~> 0.9.0"
  s.add_development_dependency "rspec", "~> 1.3.0"
  s.extra_rdoc_files = ["README.rdoc"]
end
