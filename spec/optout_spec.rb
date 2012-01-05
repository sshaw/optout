require "optout"
require "tempfile"
require "fileutils"
require "rbconfig"

def create_optout(options = {})
  Optout.options(options) do 
    on :x, "-x" 
    on :y, "-y"
  end
end

def optout_option(*options)
  Optout.options { on :x, "-x", *options }
end

class Optout
  class Option
    def unix?
      true
    end
  end
end

shared_examples_for "something that validates files" do
  before(:all) { @tmpdir = Dir.mktmpdir }
  after(:all) { FileUtils.rm_rf(@tmpdir) }

  def options
    { :x => @file }
  end

  it "should not raise an exception if a file does not exist but its directory does" do          
    file = File.join(@tmpdir, "__bad__")
    optout = optout_option(@validator)
    proc { optout.argv(:x => file) }.should_not raise_exception
  end

  describe "permissions" do 
    # Only some chmod() modes work on Win
    if RbConfig::CONFIG["host_os"] !~ /mswin|mingw/i
      it "should raise an exception when user permissions don't match" do 
        FileUtils.chmod(0100, @file)    
        optout = optout_option(@validator.permissions("r"))
        proc { optout.argv(options) }.should raise_exception(Optout::OptionInvalid, /user permission/)
      end
      
      it "should not raise an exception when user permissions match" do 
        checker = proc do |validator| 
          proc { optout_option(validator).argv(options) }.should_not raise_exception
        end
        
        FileUtils.chmod(0100, @file)
        checker.call(@validator.permissions("x"))
        
        FileUtils.chmod(0200, @file)
        checker.call(@validator.permissions("w"))
        
        FileUtils.chmod(0400, @file)
        checker.call(@validator.permissions("r"))
        
        FileUtils.chmod(0700, @file)
        checker.call(@validator.permissions("rwx"))
      end
    end
  end

  describe "exists" do 
    it "should raise an exception if the file does not exist" do
      optout = optout_option(@validator.exists)
      proc { optout.argv(:x => @file + "no_file") }.should raise_exception(Optout::OptionInvalid, /does not exist/)
      proc { optout.argv(options) }.should_not raise_exception
    end  
  end

  describe "under a directory" do 
    it "should raise an exception if not under the given directory" do 
      optout = optout_option(@validator.under(File.join("wrong", "path")))
      proc { optout.argv(options) }.should raise_exception(Optout::OptionInvalid, /must be under/)
      
      optout = optout_option(@validator.under(@tmpdir))
      proc { optout.argv(options) }.should_not raise_exception
    end
    
    it "should raise an exception if the parent directory does not match the given pattern" do       
      # We need to respect the @file's type to ensure other validation rules implicitly applied by the @validator pass.
      # First create parent dirs to validate against
      tmp = File.join(@tmpdir, "a1", "b1")
      FileUtils.mkdir_p(tmp)

      # Then copy the target of the validation (file or directory) under the parent dir. 
      FileUtils.cp_r(@file, tmp)

      # And create the option's value
      tmp = File.join(tmp, File.basename(@file))
      options = { :x => tmp }

      optout = optout_option(@validator.under(/X$/))
      proc { optout.argv(options) }.should raise_exception(Optout::OptionInvalid, /must be under/)

      [ %r|(/[a-z]\d){2}|, %r|[a-z]\d$| ].each do |r|
        optout = optout_option(@validator.under(r))
        proc { optout.argv(options) }.should_not raise_exception      
      end
    end
  end
  
  describe "basename" do
    it "should raise an exception if it does not equal the given value" do 
      optout = optout_option(@validator.named("__bad__"))
      proc { optout.argv(options) }.should raise_exception(Optout::OptionInvalid, /name must match/)
      
      optout = optout_option(@validator.named(File.basename(@file)))
      proc { optout.argv(options) }.should_not raise_exception
    end
    
    it "should raise an exception if it does not match the given pattern" do    
      optout = optout_option(@validator.named(/\A-_-_-_/))
      proc { optout.argv(options) }.should raise_exception(Optout::OptionInvalid, /name must match/)

      ends_with = File.basename(@file)[/.{2}\z/]
      optout = optout_option(@validator.named(/#{Regexp.quote(ends_with)}\z/))
      proc { optout.argv(options) }.should_not raise_exception    
    end
  end
end

describe Optout do
  describe "defining options" do
    before(:each) { @optout = Optout.new }

    it "should require the option's key" do
      proc { @optout.on }.should raise_exception(ArgumentError, /option key required/)
      proc { Optout.options { on } }.should raise_exception(ArgumentError, /option key required/)
    end
    
    it "should not allow an option to be defined twice" do
      @optout.on :x
      proc { @optout.on :x }.should raise_exception(ArgumentError, /already defined/)
      proc do
        Optout.options do
          on :x
          on :x
        end
      end.should raise_exception(ArgumentError, /already defined/)
    end
  end

  describe "creating options" do
    before(:each) { @optout = create_optout }

    context "as a string" do	
      it "should only output the option's value if there's no switch" do
        optout = Optout.options { on :x }
        optout.shell(:x => "x").should eql("'x'")
      end

      it "should output an empty string if the option hash is empty" do
        @optout.shell({}).should be_empty
      end

      it "should only output the option's switch if its value if true" do        
        @optout.shell(:x => true, :y => true).should eql("-x -y")
      end

      it "should not output the option if its value is false" do        
        @optout.shell(:x => false, :y => true).should eql("-y")
      end

      it "should only output the options that have a value" do        
        @optout.shell(:x => "x", :y => nil).should eql("-x 'x'")
      end
      
      it "should output all of the options" do        
        @optout.shell(:x => "x", :y => "y").should eql("-x 'x' -y 'y'")
      end

      it "should escape the single quote char" do        
        @optout.shell(:x => "' a'b'c '").should eql(%q|-x ''\'' a'\''b'\''c '\'''|)
      end

      it "should not separate switches from their value" do 
        optout = create_optout(:arg_separator => "")
        optout.shell(:x => "x", :y => "y").should eql("-x'x' -y'y'")
      end
      
      it "should seperate all switches from their value with a '='" do
        optout = create_optout(:arg_separator => "=")
        optout.shell(:x => "x", :y => "y").should eql("-x='x' -y='y'")
      end      

      it "should join all options with multiple values on a delimiter" do         
        optout = create_optout(:multiple => true)
        optout.shell(:x => %w|a b c|, :y => "y").should eql("-x 'a,b,c' -y 'y'")
      end

      it "should join all options with multiple values on a ':'" do         
        optout = create_optout(:multiple => ":")
        optout.shell(:x => %w|a b c|, :y => "y").should eql("-x 'a:b:c' -y 'y'")
      end     
    end

    context "as an array" do
      it "should only output the option's value if there's no switch" do
        optout = Optout.options { on :x }
        optout.argv(:x => "x").should eql(["x"])
      end

      it "should output an empty array if the option hash is empty" do
        @optout.argv({}).should be_empty
      end

      it "should only output the option's switch if its value if true" do
        @optout.argv(:x => true, :y => true).should eql(["-x", "-y"])
      end

      it "should not output the option if its value is false" do
        @optout.argv(:x => false, :y => true).should eql(["-y"])
      end

      it "should only output the options that have a value" do        
        @optout.argv(:x => "x", :y => nil).should eql(["-x", "x"])
      end

      it "should output all of the options" do
        @optout.argv(:x => "x", :y => "y").should eql(["-x", "x", "-y", "y"])
      end

      it "should not escape the single quote char" do        
        @optout.argv(:x => "' a'b'c '").should eql(["-x", "' a'b'c '"])
      end

      it "should not separate switches from their value" do 
        optout = create_optout(:arg_separator => "")
        optout.argv(:x => "x", :y => "y").should eql(["-xx", "-yy"])
      end

      it "should seperate all of switches from their value with a '='" do
        optout = create_optout(:arg_separator => "=") 
        optout.argv(:x => "x", :y => "y").should eql(["-x=x", "-y=y"])
      end

      it "should join all options with multiple values on a delimiter" do         
        optout = create_optout(:multiple => true)
        optout.argv(:x => %w|a b c|, :y => "y").should eql(["-x", "a,b,c", "-y", "y"])
      end

      it "should join all options with multiple values on a ':'" do      
        optout = create_optout(:multiple => ":")
        optout.argv(:x => %w|a b c|, :y => "y").should eql(["-x", "a:b:c", "-y", "y"])
      end     
    end
  end

  # TODO: Check exception.key
  describe "validation rules" do 
    it "should raise an exception if the option hash contains an unknown key" do
      optout = create_optout
      proc { optout.argv(:bad => 123) }.should raise_exception(Optout::OptionUnknown)
    end

    it "should not raise an exception if the option hash contains an unknown key" do
      optout = create_optout(:check_keys => false)
      proc { optout.argv(:bad => 123) }.should_not raise_exception
    end

    it "should raise an exception if an option is missing" do
      optout = create_optout(:required => true) 
      proc { optout.argv(:x => 123) }.should raise_exception(Optout::OptionRequired, /'y'/)
    end

    it "should raise an exception if a required option is missing" do
      optout = Optout.options do
        on :x
        on :y, :required => true
      end

      [ { :x => 123 }, { :x => 123, :y => false } ].each do |options|
        proc { optout.argv(options) }.should raise_exception(Optout::OptionRequired, /'y'/)
      end
    end

    it "should raise an exception if any option contains multiple values" do
      optout = create_optout(:multiple => false) 

      [ { :x => 123, :y => %w|a b c| },
        { :x => 123, :y => { :a => "b", :b => "c" }} ].each do |options|
        proc { optout.argv(options) }.should raise_exception(Optout::OptionInvalid)
      end

      # An Array with 1 value is OK
      proc { optout.argv(:x => 123, :y => %w|a|) }.should_not raise_exception(Optout::OptionInvalid)    
    end

    it "should raise an exception if a single value option contains multiple values" do 
      optout = Optout.options do 
        on :x
        on :y, :multiple => false
      end

      proc { optout.argv(:x => "x", :y => %w|a b c|) }.should raise_exception(Optout::OptionInvalid, /\by\b/)
    end

    it "should check the option's type" do
      optout = optout_option(Float)
      proc { optout.argv(:x => 123) }.should raise_exception(Optout::OptionInvalid, /type Float/)
      proc { optout.argv(:x => 123.0) }.should_not raise_exception(Optout::OptionInvalid)      
    end

    it "should raise an exception if the option's value is not in the given set" do 
      optout = optout_option(%w|sshaw skye|, :multiple => true)

      [ "bob", [ "jack", "jill" ] ].each do |v|
        proc { optout.argv(:x => v) }.should raise_exception(Optout::OptionInvalid)
      end

      [ "sshaw", [ "sshaw", "skye" ] ].each do |v|
        proc { optout.argv(:x => v) }.should_not raise_exception
      end
    end

    it "should raise an exception if the option's value does not match the given pattern" do 
      optout = optout_option(/X\d{2}/)
      proc { optout.argv(:x => "X7") }.should raise_exception(Optout::OptionInvalid, /match pattern/)
      proc { optout.argv(:x => "X21") }.should_not raise_exception
    end

    it "should raise an exception if the option has a non-boolean value" do 
      optout = optout_option(Optout::Boolean)
      proc { optout.argv(:x => "x") }.should raise_exception(Optout::OptionInvalid, /does not accept/)
      [ false, true, nil ].each do |v|
        proc { optout.argv(:x => v) }.should_not raise_exception
      end
    end
    
    it "should call a custom validator" do
      klass = Class.new do
        def validate!(opt)
          raise "raise up!"
        end
      end

      optout = optout_option(klass.new)
      proc { optout.argv(:x => "x") }.should raise_exception(RuntimeError, "raise up!")
    end

    it "should raise an exception if an unknown validation rule is used" do 
      optout = optout_option("whaaaaa")
      proc { optout.argv(:x => "x") }.should raise_exception(ArgumentError, /don't know how to validate/)
    end

    context "when validating a file" do 
      it_should_behave_like "something that validates files"      

      before(:all) do
        @file = Tempfile.new("", @tmpdir).path
        @validator = Optout::File
      end

      it "should raise an exception if it's not a file" do
        optout = optout_option(@validator)
        proc { optout.argv(:x => @tmpdir) }.should raise_exception(Optout::OptionInvalid, /can't create a file/)
      end      
    end

    context "when validating a directory" do 
      it_should_behave_like "something that validates files"      

      before(:all) do
        @file = Dir.mktmpdir(nil, @tmpdir)
        @validator = Optout::Dir
      end     

      it "should raise an exception if it's not a directory" do
        optout = optout_option(@validator)
        proc { optout.argv(:x => Tempfile.new("", @tmpdir).path) }.should raise_exception(Optout::OptionInvalid) 
      end
    end
  end
end
