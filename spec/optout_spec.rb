require "optout"
require "tempfile"
require "fileutils"

# shared_examples_for "all editions" do
#   it "should behave like all editions" do
#   end
# end

describe Optout::Option do
  before { @klass = Optout::Option.create(:x) }

  context "creating a class" do
    it "should require a key" do
      proc { Optout::Option.create }.should raise_exception(ArgumentError)
    end

    it "should create a subclass of Optout::Option" do
      klass = Optout::Option.create(:x)
      klass.should be_an_instance_of(Class)
      klass.superclass.should == Optout::Option
    end
  end

  context "creating the option string" do
    it "should only output the switch if its value is true" do
      klass = Optout::Option.create(:x, "-x")
      opt = klass.new
      opt.to_s.should == ""
      opt = klass.new(false)
      opt.to_s.should == ""
      #opt = @klass.new(99)
      #opt.to_s.should == ""
      opt = klass.new(true)
      opt.to_s.should == "-x"
    end

    it "should only output the switch with its argument if the value is not a boolean" do
      klass = Optout::Option.create(:x, "-x")
      klass.new(123).to_s.should == "-x 123"
    end

    it "should only output the value if there's no switch" do
      klass = Optout::Option.create(:x)
      klass.new("123").to_s.should == "123"
    end

    it "should use the default if no value is given" do
      klass = Optout::Option.create(:x, "-x", :default => 69)
      klass.new.to_s.should == "-x 69"
      klass.new(123).to_s.should == "-x 123"
    end

    it "should separate the option from its value with an alternate character" do
      klass = Optout::Option.create(:x, "-x", :arg_separator => ":")
      klass.new(123).to_s.should eql("-x:123")
    end

    it "should concatinate the value if it's an array" do
      klass = Optout::Option.create(:x, "-x")
      klass.new(%w|A B C|).to_s.should eql("-x A,B,C")
      klass = Optout::Option.create(:x, "-x", :multiple => ":")
      klass.new(%w|A B C|).to_s.should eql("-x A:B:C")
    end

    it "should quote a value with spaces that aren't leading/trailing" do
      klass = Optout::Option.create(:x, "-x")
      klass.new(" a ").to_s.should eql("-x a")
      klass.new("a b c").to_s.should eql("-x 'a b c'")
    end

    # This is not correct.. see bash
    it "should escape quotes in a value" do
      klass = Optout::Option.create(:x, "-x")
      klass.new("'a'b'c'").to_s.should == %|-x \'a\'b\'c\'|
    end
  end

  context "validating the option" do
    it "should raise an OptionRequired error if there's no value and one's required" do
      klass = Optout::Option.create(:x)
      proc { klass.new.validate! }.should_not raise_exception
      klass = Optout::Option.create(:x, :required => true)
      proc { klass.new(123).validate! }.should_not raise_exception
      proc { klass.new.validate! }.should raise_exception(Optout::OptionRequired)
    end

    it "should raise an OptionRequired error if there's no value and the switch ends with a '='" do
      klass = Optout::Option.create(:x, "--x=")
      proc { klass.new(123).validate! }.should_not raise_exception
      proc { klass.new.validate! }.should raise_exception(Optout::OptionRequired)
      # Separate spec for this?
      klass = Optout::Option.create(:x, "--x=", :required => false)
      proc { klass.new.validate! }.should_not raise_exception
    end

    # need to check multiple's default value
    it "should raise an OptionInvalid error if multiple values are given when they're not allowed" do
      klass = Optout::Option.create(:x)
      proc { klass.new.validate! }.should_not raise_exception
      klass = Optout::Option.create(:x, :multiple => false)
      proc { klass.new(123).validate! }.should_not raise_exception
      proc { klass.new(%w|A B|).validate! }.should raise_exception(Optout::OptionInvalid)
    end

    it "should call custom validator" do
      v = Class.new do
        def validate!(opt)
          raise "raise up!"
        end
      end
      klass = Optout::Option.create(:x, :validator => v.new)
      proc { klass.new.validate! }.should raise_exception(RuntimeError, "raise up!")
    end
  end
end

describe Optout do
  context "defining options" do
    before {  @optout = Optout.new }

    it "should require the option's key" do
      proc { @optout.on }.should raise_exception(ArgumentError, /option key required/)
    end

    it "should not allow an option to be defined twice" do
      @optout.on :x
      proc { @optout.on :x }.should raise_exception(ArgumentError, /already defined/)
    end

    it "should return the options as an Array of Strings" do
      @optout.on :x, "-x"
      argv = @optout.argv({ :x => true })
      argv.should be_an_instance_of(Array)
      argv.should have(1).option
      argv[0].should be_an_instance_of(String)
    end

    it "should order elements in the option Array in the order they were defined" do
      @optout.on :x, "-x"
      @optout.on :y, "-y"
      @optout.on :z, "-z"
      options = { :x => true, :y => true, :z => true }
      argv = @optout.argv(options)
      argv.should have(3).options
      argv[0].should eql("-x")
      argv[1].should eql("-y")
      argv[2].should eql("-z")
    end

    it "should order elements in the option Array by their :index value" do
      @optout.on :x, "-x", :index => 2
      @optout.on :y, "-y", :index => 0
      @optout.on :z, "-z", :index => 1
      options = { :x => true, :y => true, :z => true }
      argv = @optout.argv(options)
      argv.should have(3).options
      argv[0].should eql("-y")
      argv[1].should eql("-z")
      argv[2].should eql("-x")
    end
  end
end

shared_examples_for "something that validates files" do

  before do
    @tmpdir = Dir.mktmpdir
    @klass = Optout::Option.create(:x)
  end

  after { FileUtils.rm_rf(@tmpdir) }

  # Each ex needs @validator, @file and @opt
  context "validating permissions" do
    it "should raise an exception when they don't match the specified permissions" do
      path = @opt.value
      FileUtils.chmod(0100, path)
      @validator.permissions("r")
      proc { @validator.validate!(@opt) }.should raise_exception(Optout::OptionInvalid, /user permission/)
    end

    it "should not raise an exception when they match the specified permissions" do
      path = @opt.value
      FileUtils.chmod(0100, path)
      @validator.permissions("x")
      proc { @validator.validate!(@opt) }.should_not raise_exception

      FileUtils.chmod(0200, path)
      @validator.permissions("w")
      proc { @validator.validate!(@opt) }.should_not raise_exception

      FileUtils.chmod(0400, path)
      @validator.permissions("r")
      proc { @validator.validate!(@opt) }.should_not raise_exception

      FileUtils.chmod(0700, path)
      @validator.permissions("rwx")
      proc { @validator.validate!(@opt) }.should_not raise_exception
    end
  end

  context "validating existence" do
    it "should raise an exception if it does not exist" do
      @opt = @klass.new(@file.path + "no_file")
      @validator.exists
      proc { @validator.validate!(@opt) }.should raise_exception(Optout::OptionInvalid, /does not exist/)

      @validator.exists(true)
      proc { @validator.validate!(@opt) }.should raise_exception(Optout::OptionInvalid, /does not exist/)
    end

    it "should not raise an exception if it exists" do
      @validator.exists
      proc { @validator.validate!(@opt) }.should_not raise_exception

      @validator.exists(true)
      proc { @validator.validate!(@opt) }.should_not raise_exception
    end
  end

  # Check regex
  context "validating location" do
    it "should not raise an exception if under the specified parent directory" do
      @validator.under(@tmpdir)
      proc { @validator.validate!(@opt) }.should_not raise_exception
    end

    it "should raise an exception if not under the specified parent directory" do
      @validator.under("/wrong")
      proc { @validator.validate!(@opt) }.should raise_exception(Optout::OptionInvalid)
    end
  end

  # Regex here too..
  context "validating basename" do
    it "should not raise an exception if it matches the specified basename" do
      @validator.named(File.basename(@file.path))
      proc { @validator.validate!(@opt) }.should_not raise_exception
    end

    it "should raise an exception if it does not match the specified basename" do
      @validator.named("bad")
      proc { @validator.validate!(@opt) }.should raise_exception(Optout::OptionInvalid)
    end
  end
end

describe Optout::Validator do
  context "retrieving a validator" do
    it "should return the Regex validator for a Rexep instance" do
      Optout::Validator.for(//).should be_an_instance_of(Optout::Validator::Regexp)
    end

    it "should return the Array validator for an Array instance" do
      Optout::Validator.for([]).should be_an_instance_of(Optout::Validator::Array)
    end

    it "should return the argument if it responds to validate!" do
      v = Class.new {  def validate!; end }.new
      Optout::Validator.for(v).should eql(v)
    end
  end
end

describe Optout::Validator::File do
  it_should_behave_like "something that validates files"

  before do
    @file = Tempfile.new(nil, @tmpdir)
    @opt = @klass.new(@file.path)
    @validator = Optout::Validator::File.new
  end
end

describe Optout::Validator::Directory do
  it_should_behave_like "something that validates files"

  before do
    @file = File.new(Dir.mktmpdir(nil, @tmpdir))
    @opt = @klass.new(@file.path)
    @validator = Optout::Validator::Directory.new
  end
end
