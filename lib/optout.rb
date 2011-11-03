require "rbconfig"
require "pathname"


require "pp"



class Optout
  VERSION = "0.01"

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
      super(key, "option invalid: '#{key}'; #{message}")
    end
  end

  class << self

    ##
    # Define a set of options to create
    #
    # === Parameters
    # [config     (Hash)] Configuration information
    # [definition (Proc)] Option definitions
    #
    # === Options
    #
    #
    # === Examples
    #
    #    optz = Optout.options do
    #      on :all,  "-a"
    #      on :size, "-b", /\A\d+\z/, :required => true
    #      on :file, Optout::File.under("/home/sshaw"), :default => "/home/sshaw/tmp"
    #    end
    #
    #    optz.shell(:all => true, :size => 1024, :file => "/home/sshaw/some file")
    #    # Creates: "-a -b 1024 '/home/sshaw/some file'
    #
    #    optz = Optout.options :required => true, :assert_valid_keys => false do
    #      on :lib, :index => 1
    #      on :prefix, "--prefix=" , %w{/sshaw/lib /sshaw/usr/lib}
    #    end
    #
    #    optz.argv(:lib      => "libssl2",
    #              :prefix   => "/sshaw/home/lib",
    #              :bad_key  => "No error raised because of moi")
    #
    #
    #    # Creates: ["--prefix=/sshaw/lib", "libssl2"]
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
    @assert_valid_keys = args.include?(:assert_valid_keys) ? args[:assert_valid_keys] : true
    #@opt_seperator = args[:opt_seperator]
    @default_opt_options = {
      :required => args[:required],
      :arg_separator => args[:arg_separator]
    }
  end

  ##
  # Define an option
  #
  # === Parameters
  # [key    (Symbol)] The hash key used for this option
  # [switch (String)] The command line switch for this option
  # [rule   (String)] A validations rule
  #
  # === Options
  # required
  #
  #
  # === Errors
  # An +ArgumentError+ is raised if:
  # * +key+ is +nil+
  # * +key+ has already been defined
  #
  # === Examples
  #
  #
  #

  def on(*args)
    key = args.shift

    # switch is optional, this could be a validation rule
    switch = args.shift if String === args[0]
    raise ArgumentError, "option key required" if key.nil?
    raise ArgumentError, "option already defined: '#{key}'" if @options[key]

    opt_options = Hash === args.last ? args.pop : {}
    opt_options.merge!(@default_opt_options)
    opt_options[:index] ||= @options.size
    opt_options[:validator] = args.shift

    @options[key] = Option.create(key, switch, opt_options)
  end


  ##
  # Create an argument string that can be to passed to a +system()+ like method
  #
  # === Parameters
  # [options (Hash)] The options hash used to construct the argument string
  #
  # === Returns
  # [String] The argument string
  #
  def shell(options = {})
    create_options(options).map { |opt| opt.to_s }.join " "
  end

  ##
  # Create an +argv+ array that can be to passed to an +exec()+ like method
  #
  # === Parameters
  # [options (Hash)] The options hash used to construct an +argv+ array
  #
  # === Returns
  # [Array] The +argv+ array, each element is a +String+
  #
  def argv(options = {})
    create_options(options).map { |opt| opt.to_a }.flatten
  end

  private
  def create_options(options = {})
    argv = []
    options = options.dup

    @options.each do |key, klass|
      value = options.delete(key) || options.delete(key.to_s)
      opt = klass.new(value)
      opt.validate!
      argv << opt
    end

    if @assert_valid_keys && options.any?
      raise OptionUnknown, options.keys[0]
    end

    argv.select  { |opt| !opt.empty? }.
         sort_by { |opt| opt.index }
  end

  class Option
    attr :key
    attr :value
    attr :index

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

    def to_a
      opt = create_opt_array
      opt = [ opt.join(@separator) ] if blank_separator?
      opt
    end

    def empty?
      !@value || @value.to_s.empty?
    end

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

    def blank_separator?
      @separator.gsub(/\s+/, "").empty?
    end

    # bob's     = bob\'s
    # bob's big = 'bob'\''s big'
    def quote(value)
      if unix?
        # For --opt=n we dont always want to quote!
        sprintf "'%s'", value.gsub("'") { "'\\''" }
      else
        %|"#{value}"|
      end
    end

    def unix?
      RbConfig::CONFIG["host_os"] !~ /mswin|mingw/i
    end

    def normalize(value)
      value.respond_to?(:join) ? value.join(@joinon) : value.to_s.strip
    end
  end

  module Validator
    def self.for(setting)
      if setting.respond_to?(:validate!)
        setting
      else
        # Load based on setting's name or the name of its class
        validator = setting.class.name
        if validator == "Class"
          name = setting.name.split("::", 2)
          validator = name[1] if name[1] && name[0] == "Optout"
        end

        begin
          const_get(validator).new(setting)
        rescue NameError
          raise ArgumentError, "don't know how to validate with #{setting}"
        end
      end
    end

    Base = Struct.new :setting

    # Check for multiple values
    class Multiple < Base
      def validate!(opt)
        if !opt.empty? && opt.value.respond_to?(:join) && opt.value.size > 1 && !multiple_values_allowed?
          raise OptionInvalid.new(opt.key, "multiple values are not allowed")
        end
      end

      protected
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

      protected
      def option_required?
        !!setting
      end
    end

    class Array < Base
      def validate!(opt)
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
        if !(setting === opt.value)
          raise OptionInvalid.new(opt.key, "value '#{opt.value}' must be type #{setting}")
        end
      end
    end

    class Boolean < Base
      def validate!(opt)
        if !(opt.value == true || opt.value == false || opt.value.nil?)
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
        @file = Pathname.new(opt.value.to_s)
        what  = self.class.name.split("::")[-1]
        error = case
                when !under?
                  "#{what} must be under #{@under}"
                when !named?
                  "#{what} name must match '#{@named}'"
                when !permissions?
                  "#{what} must have user permission of #{@permissions}"
                when !exists?
                  "'#{@file}' does not exist"
                when !creatable?
                  "can't create #{what.downcase} '#{@file}'"
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
        (Regexp === @named ?
          basename =~ @named :
          basename == @named)
      end

      def under?
        !@under ||
        exists? &&
        (Regexp === @under ?
          @under =~ /\A#{::Regexp.quote(@file.parent.expand_path.to_s)}/ :
          @under == @file.parent.expand_path.to_s)
      end

      def creatable?
       @file.exist? && correct_type? ||
       @file.parent.exist? && @file.parent.writable?
      end
    end

    class Dir < File
      protected
      def correct_type?
        @file.directory?
      end
    end
  end

  # These are shortcuts and/or marker classes use by Validator.for() to load the equivalent validation class
  class File
    class << self
      Validator::File::RULES.each do |r|
        define_method(r) { |arg| proxy_for.new.send(r, arg) }
      end

      def exists(wanted = true)
        proxy_for.new.exists(wanted)
      end

      def proxy_for
        Validator::File
      end
    end
  end

  class Dir < File
    def self.proxy_for
      Validator::Dir
    end
  end

  Boolean = Class.new
end

