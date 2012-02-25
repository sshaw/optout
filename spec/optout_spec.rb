require "spec_helper"

shared_examples_for "a validator" do 
  context "when the option is nil" do 
    it "should not be validated" do 
      lambda { subject.argv(:x => nil) }.should_not raise_exception
    end
  end
end

shared_examples_for "something that validates files" do
  context "when the file does not exist but its directory does" do
    it "should not raise an exception" do 
      no_file = File.join(File.dirname(file), "does_not_exist")
      optout = optout_option(described_class)
      proc { optout.argv(:x => no_file) }.should_not raise_exception
    end
  end

  # Only some chmod() modes work on Win
  describe "#permissions", :skip_on_windows => true do
    context "when the specified user permissions aren't set" do 
      it "should raise an OptionInvalid exception" do
        FileUtils.chmod(0100, file)
        optout = optout_option(described_class.permissions("r"))
        lambda { optout.argv(options) }.should raise_exception(Optout::OptionInvalid, /user permission/)
      end
    end

    def chmod_and_check(mode, validator)
      FileUtils.chmod(mode, file)
      lambda { optout_option(validator).argv(options) }.should_not raise_exception
    end

    context "when user read is set" do 
      it "should not raise an exception" do  
        chmod_and_check(0400, described_class.permissions("r"))   
      end
    end

    context "when user write is set" do      
      it "should not raise an exception" do 
        chmod_and_check(0200, described_class.permissions("w"))     
      end
    end

    context "when user execute is set" do 
      it "should not raise an exception" do 
        chmod_and_check(0100, described_class.permissions("x"))
      end
    end

    context "when all permissions are set" do 
      it "should not raise an exception" do 
        chmod_and_check(0700, described_class.permissions("rwx"))
      end
    end
  end

  describe "#exists" do
    subject { optout_option(described_class.exists) }
    
    context "when the file exists" do
      it "does not raise an exception" do
        lambda { subject.argv(options) }.should_not raise_exception
      end
    end
    
    context "when the file does not exist" do
      it "raises an OptionInvalid exception" do
        lambda { subject.argv(:x => file + "no_file") }.should raise_exception(Optout::OptionInvalid, /does not exist/)
      end
    end
  end
  
  describe "#under" do
    context "when not under the given directory" do
      it "should raise an OptionInvalid exception" do
        optout = optout_option(described_class.under(File.join("wrong", "path")))
        lambda { optout.argv(options) }.should raise_exception(Optout::OptionInvalid, /must be under/)
      end
    end
    
    context "when under the given directory" do
      it "should not raise an exception" do
        optout = optout_option(described_class.under(File.dirname(file)))
        lambda { optout.argv(options) }.should_not raise_exception
      end
    end
    
    context "when the parent directory does not match the given regex" do
      it "should raise an OptionInvalid exception" do      
        optout = optout_option(described_class.under(/_{20},#{Time.now.to_i}$/))
        lambda { optout.argv(options) }.should raise_exception(Optout::OptionInvalid, /must be under/)
      end
    end

    context "when the parent directory matches the given regex" do
      it "should not raise an exception" do
        regex = /#{File.dirname(file)[-1,1]}$/
        optout = optout_option(described_class.under(regex))
        lambda { optout.argv(options) }.should_not raise_exception
      end
    end
  end

  describe "#named" do
    context "when the basename matches the regex" do
      it "should not raise an exception" do 
        ends_with = File.basename(subject)[/.{2}\z/]
        optout = optout_option(described_class.named(/#{Regexp.quote(ends_with)}\z/))
        lambda { optout.argv(options) }.should_not raise_exception
      end
    end

    context "when the basename does not match the regex" do
      it "should raise an OptionInvalid exception" do 
        optout = optout_option(described_class.named(/\A#{Time.now.to_i}/))
        lambda { optout.argv(options) }.should raise_exception(Optout::OptionInvalid, /name must match/)
      end
    end
    
    context "when the basename is not equal" do 
      it "should raise an OptionInvalid exception" do
        optout = optout_option(described_class.named(Time.now.to_s))
        lambda { optout.argv(options) }.should raise_exception(Optout::OptionInvalid, /name must match/)
      end
    end

    context "when the basename is equal" do 
      it "should not raise an exception" do
        optout = optout_option(described_class.named(File.basename(file)))
        lambda { optout.argv(options) }.should_not raise_exception
      end
    end
  end
end

describe Optout do
  describe "#on" do
    before(:each) { @optout = Optout.new }

    it "requires the option's key" do
      lambda { @optout.on }.should raise_exception(ArgumentError, /option key required/)
    end

    it "should not allow an option to be defined twice" do
      @optout.on :x
      [:x, "x"].each do |opt|
        lambda { @optout.on opt }.should raise_exception(ArgumentError, /already defined/)
      end
    end

    describe "the :required option" do
      context "when true" do
        subject { optout_option(:required => true) }
      
        it "should raise an OptionRequired exception if the option is missing" do 
          lambda { subject.argv }.should raise_exception(Optout::OptionRequired, /'x'/)
          lambda { subject.argv(:x => nil) }.should raise_exception(Optout::OptionRequired, /'x'/)
        end

        it "should not raise an exception if the option is not missing" do 
          lambda { subject.argv(:x => "x") }.should_not raise_exception
        end
      end

      context "when false" do
        it "should not raise an exception if the option is missing" do 
          optout = optout_option(:required => false) 
          lambda { optout.argv }.should_not raise_exception
        end      
      end
    end      

    describe "the :multiple option" do
      let(:collection) do
        [ :x => %w|a b|,
          :x => { :a => "a", :b => "b" } ]
      end
      
      context "when false" do
        before(:each) { @optout = optout_option(:multiple => false) }
        
        it "should raise an OptionInvalid exception if an option contains multiple values" do
          collection.each do |options|
            lambda { @optout.argv(options) }.should raise_exception(Optout::OptionInvalid)
          end
        end
        
        it "should not raise an exception if an option contains a collection with only 1 element" do
          [ :x => %w|a|,
            :x => { :a => "a" } ].each do |options|
            lambda { @optout.argv(options) }.should_not raise_exception(Optout::OptionInvalid)
          end
        end
        
        it "should not raise an exception if an option contains a single value" do
          lambda { @optout.argv(:x => "x") }.should_not raise_exception(Optout::OptionInvalid)
        end
      end
      
      context "when true" do
        before(:each) { @optout = optout_option(:multiple => true) }
        
        it "should not raise an OptionInvalid exception if an option contains multiple values" do
          collection.each do |options|
            lambda { @optout.argv(options) }.should_not raise_exception(Optout::OptionInvalid)
          end
        end
        
        it "should not raise an OptionInvalid exception if an option contains a single value" do
          lambda { @optout.argv(:x => "x") }.should_not raise_exception(Optout::OptionInvalid)
        end
      end
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

      it "should raise an ArgumentError if the options are not a Hash" do
        lambda { @optout.shell("optionz") }.should raise_exception(ArgumentError)
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

      it "should raise an ArgumentError if the options are not a Hash" do
        lambda { @optout.argv("optionz") }.should raise_exception(ArgumentError)
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
    # Global
    describe "the :check_keys option" do
      context "when true" do
        it "raises an exception if the option hash contains an unknown key" do
          optout = create_optout
          lambda { optout.argv(:bad => 123) }.should raise_exception(Optout::OptionUnknown)
        end
      end

      context "when false" do
        it "does not raise an exception if the option hash contains an unknown key" do
          optout = create_optout(:check_keys => false)
          lambda { optout.argv(:bad => 123) }.should_not raise_exception
        end
      end
    end

    # These should be for #on and then tested globally
    describe "type checking" do
      it_should_behave_like "a validator"
      subject { optout_option(Float) }
      
      context "when the type is correct" do
        it "should not raise an exception" do
          lambda { subject.argv(:x => 123.0) }.should_not raise_exception
        end
      end
      
      context "when the type is incorrect" do
        it "should raise an OptionInvalid exception" do
          lambda { subject.argv(:x => 123) }.should raise_exception(Optout::OptionInvalid, /type Float/)
        end
      end
    end

    describe "restricting the option to a set of values " do
      it_should_behave_like "a validator"
      subject { optout_option(%w|sshaw skye|) }

      context "when a value is included in the set" do
        it "should not raise an exception" do
          lambda { subject.argv(:x => "skye") }.should_not raise_exception
        end
      end

      context "when a value is not included in the set" do
        it "should raise an OptionInvalid exception" do
          lambda { subject.argv(:x => "jay_kat") }.should raise_exception(Optout::OptionInvalid, /must be one of/)
        end
      end
    end

    describe "pattern matching" do 
      it_should_behave_like "a validator"
      subject { optout_option(/X\d{2}/) }
      
      context "when it matches" do 
        it "should not raise an exception" do 
          lambda { subject.argv(:x => "X21") }.should_not raise_exception
        end
      end

      context "when it does not match" do 
        it "should raise an OptionInvalid exception" do 
          lambda { subject.argv(:x => "X7") }.should raise_exception(Optout::OptionInvalid, /match pattern/)
        end
      end
    end

    describe Optout::Boolean do 
      it_should_behave_like "a validator"
      subject { optout_option(Optout::Boolean) }

      context "when the option's a boolean" do 
        it "should not raise an exception" do 
          [ false, true ].each do |v|
            lambda { subject.argv(:x => v) }.should_not raise_exception
          end
        end
      end

      context "when the option's not a boolean" do 
        it "should raise an OptionInvalid exception" do 
          lambda { subject.argv(:x => "x") }.should raise_exception(Optout::OptionInvalid, /does not accept/)
        end
      end          
    end
  end
  
  describe "a custom validator" do 
    context "when it responds to :validate!" do 
      it "should be called" do 
        klass = mock("validator")
        klass.should_receive(:validate!)
        optout = optout_option(klass)
        optout.argv(:x => "x")
      end
    end
    
    context "when it does not respond to :validate!" do 
      it "should raise an ArgumentError" do 
        optout = optout_option(Class.new.new)
        lambda { optout.argv(:x => "x") }.should raise_exception(ArgumentError, /don't know how to validate/)        
      end
    end    
  end
  
  describe "unknown validation rules" do 
    it "should raise an ArgumentError" do 
      optout = optout_option("whaaaaa")
      lambda { optout.argv(:x => "x") }.should raise_exception(ArgumentError, /don't know how to validate/)
    end
  end
  
  describe "#required" do
    before :all do
      @optout = Optout.new
      @optout.required do
        on :x, "-x"
        on :y, "-y"
      end
    end

    context "when options are missing" do 
      it "should raise an OptionRequired exception" do 
        lambda { @optout.argv }.should raise_exception(Optout::OptionRequired, /'x|y'/)
        lambda { @optout.argv :x => "x" }.should raise_exception(Optout::OptionRequired, /'y'/)
        lambda { @optout.argv :y => "y" }.should raise_exception(Optout::OptionRequired, /'x'/)
      end
    end

    context "when no options are missing" do 
      it "should not raise an exception" do 
        lambda { @optout.argv :x => "x", :y => "y" }.should_not raise_exception
      end
    end
  end

  describe "#optional" do
    before :all do 
      @optout = Optout.new      
      @optout.optional do
        on :x, "-x"
        on :y, "-y"
      end
    end
    
    it "should not raise an exception if any options are missing" do
      lambda { @optout.argv }.should_not raise_exception(Optout::OptionRequired)
      lambda { @optout.argv(:x => "x", :y => "y") }.should_not raise_exception(Optout::OptionRequired)
    end
  end
end

shared_context "file validation" do 
  before(:all) { @tmpdir = Dir.mktmpdir }
  after(:all) { FileUtils.rm_rf(@tmpdir) }
end

describe Optout::File do
  include_context "file validation"
  it_should_behave_like "something that validates files"

  before(:all) { @file = Tempfile.new("", @tmpdir) }
  subject { @file.path }

  let(:file) { @file.path }  
  let(:options) { { :x => file } }

  #Tempfile.new("", tmpdir).path }
  
  context "when the option is not a file" do
    it "raises an OptionInvalid exception" do
      optout = optout_option(described_class)
      lambda { optout.argv(:x => @tmpdir) }.should raise_exception(Optout::OptionInvalid, /can't create a file/)
    end
  end
end
  
describe Optout::Dir do
  include_context "file validation"
  it_should_behave_like "something that validates files"

  subject { @tmpdir }
  let(:file) { @tmpdir }
  let(:options) { {:x => file} }
  
  context "when the option is not a directory" do    
    it "raises an OptionInvalid exception" do
      optout = optout_option(described_class)
      lambda { optout.argv(:x => Tempfile.new("", @tmpdir).path) }.should raise_exception(Optout::OptionInvalid)
    end
  end
end
