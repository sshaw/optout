require "rbconfig"
require "pathname"

class Optout
  VERSION = "0.0.2"

  class OptionError < StandardError
    attr :key
    def initialize(key, message)
      super(message)
      @key = key
    end
  end

  class OptionRequired < OptionError
    def initialize(key)
      super(key, "option required: '#{key}'")
    end
  end

  class OptionUnknown < OptionError
    def initialize(key)
      super(key, "option unknown: '#{key}'")
    end
  end

  class OptionInvalid < OptionError
    def initialize(key, message)
      super(key, "option invalid: #{key}; #{message}")
    end
  end

  class << self
    ##
    # Define a set of options. 
    # After the options are defined call Optout#argv or Optout#shell to create them.
    # 
    #  optz = Optout.options config do 
    #    on :key, "-switch", ValidationRule, :multiple => false, :required => true
    #    # ...
    #  end        
    #
    # === Parameters
    #
    # [config     (Hash)] Configuration options
    # [block      (Proc)] Option definitions
    #
    # === Configuration Options
    #
    # [:arg_separator] Set the default argument seperator (i.e., the char used to seperate a switch from its value) for all subsequent options defined via Optout#on.
    # [:check_keys]    If +true+ an +OptionUnknown+ error will be raised when the incoming option hash contains a key that has not been associated with an option via Optout#on.
    #                  Defaults to +true+.
    # [:multiple]      Set the default for all subsequent options defined via +on+. See Optout#on.
    # [:required]      Set the default for all subsequent options defined via +on+. See Optout#on.
    #
    # === Errors
    #
    # [ArgumentError] Calls to +on+ from inside a block can raise an +ArgumentError+.
    #
    # === Examples
    #
    #  optz = Optout.options do
    #    on :all,  "-a"
    #    on :size, "-b", /\A\d+\z/, :required => true
    #    on :file, Optout::File.under("/home/sshaw"), :default => "/home/sshaw/tmp"
    #  end
    #
    #  optz = Optout.options :required => true, :check_keys => false do
    #    on :lib
    #    on :prefix, "--prefix" , %w{/sshaw/lib /sshaw/usr/lib}, :arg_separator => "="
    #  end
    #
    #  # Same as above
    #  optz = Optout.options :check_keys => false do
    #    required do 
    #      on :lib
    #      on :prefix, "--prefix" , %w{/sshaw/lib /sshaw/usr/lib}, :arg_separator => "="
    #    end
    #  end
    #
    
    def options(config = {}, &block)
      optout = new(config)
      optout.instance_eval(&block) if block_given?
      optout
    end

    alias :keys :options
  end

  def initialize(args = {})
    @options = {}
    @check_keys = args.include?(:check_keys) ? args[:check_keys] : true
    @required_context = option_context(:required => true)
    @optional_context = option_context(:required => false)  
    @default_opt_options = {
      :required => args[:required],
      :multiple => args[:multiple],
      :arg_separator => args[:arg_separator]
    }
  end

  ##
  # Define an option. 
  #
  # === Parameters
  #
  # [key     (Symbol)] The key of the option in the option hash passed to +shell+ or +argv+. 
  # [switch  (String)] Optional. The option's command line switch. If no switch is given only the option's value is output.
  # [rule    (Object)] Optional. Validation rule, see Optout#on@Validating.
  # [options   (Hash)] Additional option configuration, see Optout#on@Options. 
  #
  # === Options
  #
  # [:arg_separator] The +String+ used to separate the option's switch from its value. Defaults to <code>" "</code> (space). This can be set globally via Optout::options. 
  # [:default]  The option's default value. This will be used if the option is +nil+ or +empty?+. 
  # [:multiple] If +true+ the option will accept multiple values. If +false+ an <code>Optout::OptionInvalid</code> error will be raised if the option contains multiple values. By default multiple values are joined on a comma, you can set this to a +String+ to join on that string instead. Defaults to +false+. This can be set globally via Optout::options. 
  # [:required] If +true+ the option must contian a value i.e., it must not be +false+ or +nil+ otherwise an <code>Optout::OptionRequired</code> exception will be raised. 
  #		Defaults to +false+. This can be set globally via Optout::options or for a set of options via Optout#required or Optout#optional.
  #
  # === Errors
  #
  # [ArgumentError] An +ArgumentError+ is raised if +key+ is +nil+ or has already been defined
  #
  # === Validating
  #
  # An option's value can be restricted by a validation rule. If validation fails an Optout::OptionInvalid exception is raised. 
  #
  # Validation rules will only be applied if the option hash contains a non-nil value for the given option's key.    
  # If the option is required you must either define it in a Optout#required block or set the +:required+ option to +true+ when calling Optout#on.
  #
  # Validation rules can be in one of the following forms:
  #
  # ==== Regex
  #
  # A pattern to match the option's value against.
  #
  #  on :key, /\d+/
  #  on :key, "-switch", /\d+/
  #
  # ==== Array
  #
  # Only accept value(s) contained in the given array.
  #
  #  on :key, %w(item_a item_b item_c)
  #  on :key, "-switch", %w(item_a item_b item_c)
  #
  # ==== Class
  #
  # Must be an instance of the given class. 
  #
  #  on :key, Fixnum
  #  on :key, "-switch", Fixnum
  #
  # ==== Optout::Boolean
  #
  # Must be +true+ or +false+.
  #
  #  on :key, Optout::Boolean
  #  on :key, "-switch", Optout::Boolean
  #
  # ==== Optout::File   
  #
  # Must be a file. Note that the file does not have to exist.
  #
  #  on :key, Optout::File
  #  on :key, "-switch", Optout::File
  #
  # <code>Optout::File</code> has several methods that can be used to tune validation:
  #
  #  on :key, "-switch", Optout::File.named(/-\d{2}$/).under("/home/sshaw")
  #
  # In this case the file's basename must match the given regexp and exist under the given directory. See Optout::File for more info.
  #
  # ==== Optout::Dir
  #
  # Like <code>Optout::File</code> except for directories. <code>Optout::Dir</code> has several methods that can be used to tune validation, see Optout::Dir.
  #
  #  on :key, Optout::Dir
  #  on :key, "-switch", Optout::Dir
  #
  # ==== Custom Validator
  #
  # A class that responds to +validate!+ and accepts a single argument containing the option (as an instance of Optout::Option).
  #
  #  class MyValidator
  #    def validate!(option)
  #      if option.empty? || option.value.size % 2 != 1
  #        raise Optout::OptionInvalid.new(option.key, "bad option!")
  #      end
  #    end
  #  end
  # 
  #  on :key, MyValidator.new
  #  on :key, "-switch", MyValidator.new
 
  def on(*args)
    key = args.shift

    # switch is optional, this could be a validation rule
    switch = args.shift if String === args[0]
    raise ArgumentError, "option key required" if key.nil?

    key = key.to_sym
    raise ArgumentError, "option already defined: '#{key}'" if @options[key]

    opt_options = Hash === args.last ? @default_opt_options.merge(args.pop) : @default_opt_options.dup
    opt_options[:index] ||= @options.size
    opt_options[:validator] = args.shift

    @options[key] = Option.create(key, switch, opt_options)
  end

  ##
  # Create a set of options that are optional. This can also be set on a per option basis, see Optout#on.
  #
  # === Examples
  #
  #  optz = Optout.options do 
  #    optional do 
  #      on :ignore, "-i"
  #      on :recurse, "-r"
  #    end
  #  end
  #
  #  optz.optional { on :path, Optout::File }

  def optional(&block)
    @optional_context.instance_eval(&block)
  end

  ##
  # Create a set of options that are required. 
  #
  # If any +required+ option is missing from the option hash passed to Optout#argv or Optout#shell an 
  # <code>Optout::OptionRequired</code> exception is raised. 
  #
  # This can also be set on a per option basis, see Optout#on.
  #
  # === Examples
  #
  #  optz = Optout.options do 
  #    required do 
  #      on :ignore, "-i"
  #      on :recurse, "-r"
  #    end
  #  end
  #
  #  optz.required { on :path, Optout::File }
  #

  def required(&block)    
    @required_context.instance_eval(&block)
  end

  ##
  # Create an argument string that can be to passed to a +system+ like function.
  # Options must first be defined via Optout#on.
  #
  # === Parameters
  #
  # [options (Hash)] The option hash used to construct the argument string.
  #
  # === Returns
  #
  # [String] The argument string.
  #
  # === Errors
  #
  # See Optout#argv@Errors
  #
  # === Examples
  #
  # Create <code>"-a -b '1024' '/home/sshaw/some file'"</code>
  #
  #  optz = Optout.options do
  #    on :all,  "-a"
  #    on :size, "-b", /\A\d+\z/, :required => true
  #    on :file, Optout::File.under("/home/sshaw"), :default => "/home/sshaw/tmp"
  #  end  
  #
  #  optz.shell(:all => true, :size => 1024, :file => "/home/sshaw/some file")

  def shell(options = {})
    create_options(options).map { |opt| opt.to_s }.join " "
  end

  ##
  # Create an +argv+ array that can be to passed to an +exec+ like function.
  # Options must first be defined via Optout#on.
  #
  # === Parameters
  #
  # [options (Hash)] The options hash used to construct the +argv+ array. 
  #
  # === Returns
  #
  # [Array] The +argv+ array, each element is a +String+
  #
  # === Errors
  #
  # [ArgumentError] If options are not a +Hash+
  # [Optout::OptionRequired] The option hash is missing a required value.
  # [Optout::OptionUnknown] The option hash contains an unknown key.
  # [Optout::OptionInvalid] The option hash contains a value the does not conform to the defined specification.
  # 
  # === Examples
  #
  # Create <code>["--prefix='/sshaw/usr/lib'", "libssl2"]</code>
  #
  #  optz = Optout.options do
  #    on :all,  "-a"
  #    on :size, "-b", /\A\d+\z/, :required => true
  #    on :file, Optout::File.under("/home/sshaw"), :default => "/home/sshaw/tmp"
  #  end  
  #
  #  optz.argv(:lib      => "libssl2",
  #            :prefix   => "/sshaw/usr/lib")

  def argv(options = {})
    create_options(options).map { |opt| opt.to_a }.flatten
  end

  private
  def create_options(options = {})    
    raise ArgumentError, "options must be a Hash" unless Hash === options

    argv = []
    options = options.dup

    @options.each do |key, klass|
      value = options.delete(key) || options.delete(key.to_s)
      opt = klass.new(value)
      opt.validate!
      argv << opt
    end

    if @check_keys && options.any?
      raise OptionUnknown, options.keys[0]
    end

    argv.select  { |opt| !opt.empty? }.
         sort_by { |opt| opt.index }
  end

  def option_context(forced_options)
    klass = self
    Class.new do
      define_method(:on) do |*args|
        options = Hash === args.last ? args.pop.dup : {}        
        options.merge!(forced_options)
        args << options
        klass.on *args
      end
    end.new
  end
  
  class Option
    attr :key
    attr :value
    attr :index

    ##    
    # Creates a subclass of +Option+ 
    #
    # === Parameters
    #
    # [key     (Symbol)] The hash key that will be used to lookup and create this option.
    # [switch  (String)] Optional. 
    # [config    (Hash)] Describe how to validate and create the option.
    #
    # === Examples
    #
    #  MyOption = Optout::Option.create(:quality, "-q", :arg_separator => "=", :validator => Fixnum)
    #  opt = MyOption.new(75)
    #  opt.empty? # false
    #  opt.validate!
    #  opt.to_s   # "-q='75'"
    #
    def self.create(key, *args)
      options = Hash === args.last ? args.pop : {}
      switch  = args.shift

      Class.new(Option) do
        define_method(:initialize) do |*v|
          @key    = key
          @switch = switch
          @value  = v.shift || options[:default]
          @joinon = String === options[:multiple] ? options[:multiple] : ","
          @index  = options[:index].to_i
          @separator = options[:arg_separator] || " "
          
          @validators = []
          @validators << Validator::Required.new(options[:required])
          @validators << Validator::Multiple.new(options[:multiple])

          # Could be an Array..?
          @validators << Validator.for(options[:validator]) if options[:validator]
        end
      end
    end

    ##
    # Turn the option into a string that can be to passed to a +system+ like function.
    # This _does_ _not_ validate the option. You must call <code>validate!</code>.
    #
    # === Examples
    #
    #  MyOption = Optout::Option.create(:level, "-L", %w(fatal info warn debug))
    #  MyOption.new("debug").to_s
    #  # Returns: "-L 'debug'"
    #
    def to_s
      opt = create_opt_array
      if opt.any?
        if opt.size == 1
          opt[0] = quote(opt[0]) unless @switch
        else
          opt[1] = quote(opt[1])
        end
      end
      opt.join(@separator)
    end

    ##
    # Turn the option into an array that can be passed to an +exec+ like function.
    # This _does not_ validate the option. You must call <code>validate!</code>.
    #
    # === Examples
    #
    #  MyOption = Optout::Option.create(:level, "-L", %w(fatal info warn debug))
    #  MyOption.new("debug").to_a
    #  # Returns: [ "-L", "debug" ]
    #
    def to_a
      opt = create_opt_array
      opt = [ opt.join(@separator) ] unless @separator =~ /\A\s+\z/
      opt
    end

    ##
    # Check if the option contains a value
    #
    # === Returns
    #
    # +false+ if the option's value is +false+, +nil+, or an empty +String+, +true+ otherwise.
    #
    def empty?
      !@value || @value.to_s.empty?
    end

    ##
    # Validate the option
    #
    # === Errors
    #
    # [OptionRequired] The option is missing a required value
    # [OptionUnknown] The option contains an unknown key
    # [OptionInvalid] The option contains a value that does not conform to the defined specification
    #
    def validate!
      @validators.each { |v| v.validate!(self) }
    end

    private
    def create_opt_array
      opt = []
      opt << @switch if @switch && @value
      opt << normalize(@value) if !empty? && @value != true       # Only include @value for non-boolean options
      opt
    end

    def quote(value)
      if unix?
        sprintf "'%s'", value.gsub("'") { "'\\''" }
      else
        # TODO: Real cmd.exe quoting
        %|"#{value}"|
      end
    end

    def unix?
      RbConfig::CONFIG["host_os"] !~ /mswin|mingw|msys/i
    end
    
    def normalize(value)
      value.respond_to?(:entries) ? value.entries.join(@joinon) : value.to_s.strip
    end
  end
  
  module Validator	#:nodoc: all
    def self.for(setting)
      if setting.respond_to?(:validate!)
        setting
      else
        # Load validator based on the setting's name or the name of its class
        # Note that on 1.9 calling class.name on anonymous classes (i.e., Class.new.new) returns nil
        validator = setting.class.name.to_s  
        if validator == "Class"
          name = setting.name.to_s.split("::", 2)
          validator = name[1] if name[1] && name[0] == "Optout"
        end

        # Support 1.8 and 1.9, avoid String/Symbol and const_defined? differences
        if validator.empty? || !constants.include?(validator) && !constants.include?(validator.to_sym)
          raise ArgumentError, "don't know how to validate with #{setting}"
        end

        const_get(validator).new(setting)
      end
    end

    Base = Struct.new :setting

    # Checks for multiple values
    class Multiple < Base  
      def validate!(opt)
        if !opt.empty? && opt.value.respond_to?(:entries) && opt.value.entries.size > 1 && !multiple_values_allowed?
          raise OptionInvalid.new(opt.key, "multiple values are not allowed")
        end
      end

      private
      def multiple_values_allowed?
        !!setting
      end
    end

    class Required < Base
      def validate!(opt)
        if opt.empty? && option_required?
          raise OptionRequired, opt.key
        end
      end

      private
      def option_required?
        !!setting
      end
    end

    class Array < Base
      def validate!(opt)
        return if opt.empty?

        values = [opt.value].flatten
        values.each do |e|
          if !setting.include?(e)
            raise OptionInvalid.new(opt.key, "value '#{e}' must be one of (#{setting.join(", ")})")
          end
        end
      end
    end

    class Regexp < Base
      def validate!(opt)
        if !opt.empty? && opt.value.to_s !~ setting
          raise OptionInvalid.new(opt.key, "value '#{opt.value}' does not match pattern #{setting}")
        end
      end
    end

    class Class < Base
      def validate!(opt)
        if !opt.empty? && !(setting === opt.value)
          raise OptionInvalid.new(opt.key, "value '#{opt.value}' must be type #{setting}")
        end
      end
    end

    class Boolean < Base
      def validate!(opt)
        if !(opt.value == true || opt.value == false || opt.value.nil?)
          # TODO: Better message
          raise OptionInvalid.new(opt.key, "does not accept an argument")
        end
      end
    end

    class File < Base
      RULES = %w|under named permissions|;
      MODES = { "x" => :executable?, "r" => :readable?, "w" => :writable? }

      RULES.each do |r|
        define_method(r) do |arg|
          instance_variable_set("@#{r}", arg)
          self
        end
      end

      def exists(wanted = true)
        @exists = wanted
        self
      end

      def validate!(opt)
        return if opt.empty?

        @file = Pathname.new(opt.value.to_s)
        what  = self.class.name.split("::")[-1].downcase
        error = case
                when !under?
                  "#{what} must be under '#{@under}'"
                when !named?
                  "#{what} name must match '#{@named}'"
                when !permissions?
                  "#{what} must have user permission of #{@permissions}"
                when !exists?
                  "#{what} '#{@file}' does not exist"
                when !creatable?
                  # TODO: Why can't it be created!?
                  "can't create a #{what} at '#{@file}'"
                end
        raise OptionInvalid.new(opt.key, error) if error
      end

      protected
      def correct_type?
        @file.file?
      end

      def permissions?
        !@permissions ||
        exists? &&
        @permissions.split(//).inject(true) { |can, m| can && MODES[m] && @file.send(MODES[m]) }
      end

      def exists?
        !@exists || @file.exist? && correct_type?
      end

      def named?
        basename = @file.basename.to_s
        !@named ||
        (::Regexp === @named ?
          basename =~ @named :
          basename == @named)
      end

      def under?
        !@under ||
        exists? &&
        (::Regexp === @under ?
          @file.parent.to_s =~ @under :
          @file.parent.expand_path.to_s == ::File.expand_path(@under))
      end

      # TODO: Should probably make correct_type? a separate check
      def creatable?
       @file.exist? && correct_type? ||
       !@file.exist? && @file.parent.exist? && @file.parent.writable?
      end
    end

    class Dir < File
      protected
      def correct_type?
        @file.directory?
      end
    end
  end

  
  #
  # The following are shortcuts and/or marker classes used by Optout's public. They enable Validator.for()
  # to load the appropriate validation class.
  #

  ##
  # <code>Optout::File</code> is a validaton rule that can be used to check that an option's value is a path to a file.
  # By default <code>Optout::File</code> *does* *not* *check* that the file exists. Instead, it checks that the file's parent directory 
  # exists. This is done so that you can validate a path that _will_ be created by the program the options are for. 
  # If you do want the file to exist just call the +exists+ method. 
  #
  # Validation rules can be combined:
  #
  #  Optout.options do 
  #    on :path, "--path", Optout::File.exists.under("/home").named(/\.txt$/)
  #  end
  # 
  # To validate directories use Optout::Dir.
  # 
  class File
    class << self
      Validator::File::RULES.each do |r|
        define_method(r) { |arg| proxy_for.new.send(r, arg) }
      end

      ##
      # :singleton-method: under
      # :call-seq: 
      #   under(path)
      #   under(Regexp)
      #
      # The option must be under the given path.
      #
      # === Parameters
      #
      # This can be a +String+ denoting the parent directory or a +Regexp+ to match the parent directory against. 


      ##
      # :singleton-method: named
      # :call-seq: 
      #   named(basename)
      #   named(Regexp)
      #  
      # The option's basename must match the given basename.
      #
      # === Parameters
      #
      # A +String+ denoting the basename or a +Regexp+ to match the basename against. 


      ##
      # :singleton-method: permissions
      # :call-seq:
      #  permissions(symbolic_mode)
      #
      # The option's *user* *permissions* must match the given permission(s). 
      #
      #
      # === Parameters
      #
      # A <code>chmod(1)</code> symbolic mode +String+ denoting the desired permission(s).
      # Any combination of <code>"r"</code>, <code>"w"</code> and <code>"x"</code> is supported. 
      #
      # Note that permissions are system dependent, certain modes might not be supported by your OS. 

      ##
      #
      # If +wanted+ is true the file must exist. 
      #
      def exists(wanted = true) 
        proxy_for.new.exists(wanted)
      end

      def proxy_for #:nodoc:
        Validator::File
      end
    end
  end

  ##
  # <code>Optout::Dir</code> is a validaton rule that can be used to check that an option's value is a path to a directory.
  # This class proivdes the same functionality for directories that Optout::File provides for files. See Optout::File for more info. 
  #
  # Validation rules can be combined: 
  #
  #  Optout.options do 
  #    on :path, "--path", Optout::Dir.exists.under("/tmp").named(/\d$/)
  #  end
  #
  # See Optout::File for a list of methods.
  #
  class Dir < File
    def self.proxy_for #:nodoc:
      Validator::Dir
    end
  end

  ##
  # <code>Optout::Boolean</code> is a validaton rule that can be used to check that an option's value is +true+ or +false+.
  #
  #  Optout.options do 
  #    on :force, "-f", Optout::Boolean
  #  end

  class Boolean
  end
end

